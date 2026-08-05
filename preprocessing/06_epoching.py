# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import pandas as pd
import matplotlib

# Use a non-interactive Matplotlib backend so review figures can be captured in
# the report when the script runs outside a notebook.
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import mne
from mne.preprocessing import ICA
import sys

def epoch(signal, trigger_values_config, n_trials=6):
        """mne.Epochs() only works for fixed-length segments, this function here supports variable lengths"""
        sfreq = signal.info["sfreq"]
        events = mne.find_events(
            signal,
            stim_channel="STI101"
            )
        start_events = events[np.isin(events[:, 2], list(trigger_values_config['trial_start']))]
        end_events   = events[np.isin(events[:, 2], list(trigger_values_config['trial_end']))]

        start_time = (start_events[:,0] - signal.first_samp)/sfreq
        end_time = (end_events[:,0] - signal.first_samp)/sfreq

        trial_segments = []
        for i in range(n_trials):
            signal_per_trial = signal.copy().crop(
                tmin = start_time[i],
                tmax = end_time[i],
                include_tmax=True)
            
            trial_segments.append({
                "start_trigger": start_events[i],
                "end_trigger": end_events[i],
                "duration": end_time[i] - start_time[i],
                "raw": signal_per_trial
            })
        return trial_segments

    # take catch trials out
def remove_catch_trials(trial_segments, trigger_values_config):
        trials_for_onerun = []
        for trial in trial_segments:
            signal = trial['raw']
            sfreq = signal.info["sfreq"]

            events = mne.find_events(
                signal,
                stim_channel="STI101",
                initial_event=True
                )
            # find catch trials:'occlusion_onset' = 77-88; 'movie_restart' = 131-148
            occ_events = events[np.isin(events[:, 2], list(trigger_values_config['occlusion_onset']))]
            restart_events = events[np.isin(events[:, 2], list(trigger_values_config['movie_restart']))]

            occ_time = (occ_events[:,0] - signal.first_samp)/sfreq
            occ_time = np.concatenate((occ_time,np.array([signal.duration])))        
            restart_time = ((restart_events[:,0] - signal.first_samp)/sfreq) + 1 # because i rewinded to 1s before the occlusion onset
            restart_time = np.concatenate((np.array([0]),restart_time))        

            n_occs = len(occ_time)
            segments = []
            for i in range(n_occs):
                segments_without_catchtrials = signal.copy().crop(
                        tmin = restart_time[i],
                        tmax=min(occ_time[i], signal.times[-1]),
                        include_tmax=True)
                segments.append(segments_without_catchtrials)
            trial_without_catchtrials = mne.concatenate_raws(segments,preload=True)
            trials_for_onerun.append(trial_without_catchtrials)
        return trials_for_onerun

# %%
# -----------------------------------------------------------------------------
# Load shared configuration
# -----------------------------------------------------------------------------
script_dir = Path(__file__).resolve().parent
for candidate_root in (script_dir, *script_dir.parents):
    config_file = candidate_root / "config.toml"
    if config_file.exists():
        break
    else:
        raise FileNotFoundError(
            "Could not find config.toml. Keep it in the BIDS dataset root "
            "or update the script config lookup."
        )

with config_file.open("rb") as fid:
    config = tomllib.load(fid)

root = Path(config["paths"]["root"])
if not root.is_absolute():
    root = (config_file.parent / root).resolve()

if len(sys.argv) > 1:
    subject = sys.argv[1].removeprefix("sub-")  # accepts "sub-01" or "01"
else:
    subject = str(config["dataset"]["subject"])
subject = subject.zfill(2)
session = str(config["dataset"]["session"])
task = str(config["dataset"]["task"])
run_labels = [f"{int(run):02d}" for run in config["dataset"]["runs"]]

bids_subject = f"sub-{subject}"
bids_session = f"ses-{session}"
bids_prefix = f"{bids_subject}_{bids_session}_task-{task}"

deriv_root = root / config["paths"]["derivatives"]
deriv_dir = deriv_root / bids_subject / bids_session / "meg"
report_dir = deriv_root / bids_subject / bids_session / "reports"

ica_files = [
    deriv_dir / f"{bids_prefix}_run-{run}_desc-ica_meg.fif"
    for run in run_labels
]

output_file = deriv_dir / f'{bids_prefix}_epo.fif'

epochs_per_run = []
# Step 1 — Load one run's cleaned continuous data + events.
for i, run in enumerate(config["dataset"]["runs"]):
    file = ica_files[i]
    raw = mne.io.read_raw_fif(file, preload=True)
    # events = mne.find_events(raw, stim_channel='STI101')

    # events = mne.find_events(
    #     raw,
    #     stim_channel="STI101",
    # )

    # trigger codes
    trigger_values_config = {
        'trial_start': set(range(1, 40)),               # trig_trial_start = vid2disp(itrial) => movie id from 1 -39
        'trial_end'  : set(range(61, 67)),              # trig_trial_end = 60 + currentcondition(itrial)
        'occlusion_onset': set(range(71,89)),           # trig_occ_onset = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial) => 77-88
        'task_onset': set(range(91,109)),               # trig_task_onset = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
        'response': set(range(120, 129)),
        'movie_restart': set(range(131,149))            # trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
        }
    # electricity went out in the last run of subject number 4 so we only have 4 trials 
    if file == deriv_dir / f"sub-04_ses-01_task-IceSkating_run-06_desc-ica_meg.fif":
        trial_segments = epoch(raw, trigger_values_config, n_trials=4)
    else:
        trial_segments = epoch(raw, trigger_values_config, n_trials=6) # a list of each trial appended, still include catch trials
    trials_for_one_run = remove_catch_trials(trial_segments, trigger_values_config) # a list of 6 trials, catch trials excluded

    ## each trial after excluding catch trials is supposed to be of the same length of the stimulus video,
    ## but they are some miliseconds different because of trigger delays, so i need to resample all trials 
    ## to a common length, here taking the shortest length of all trials

    target_len = min([trials_for_one_run[j].duration for j in range(len(trials_for_one_run))])

    data = []
    meta_rows = []
    for idx, trial in enumerate(trials_for_one_run):
        raw = trial  
        raw_cropped = raw.copy().crop(tmin=0, tmax=(target_len - 1) / raw.info['sfreq'])
        data.append(raw_cropped.get_data())
        meta_rows.append({"run": i, "trial": idx})
    data = np.stack(data)  # (n_trials, n_channels, n_times)

    events = np.column_stack([
            np.arange(len(trials_for_one_run)) * int(target_len * 1000),   
            np.zeros(len(trials_for_one_run), dtype=int),
            np.arange(len(trials_for_one_run),dtype=int)                 # event_id = condition idx
        ])

    ep = mne.EpochsArray(data, raw.info, events=events, tmin=0, verbose=False)
    ep.metadata = pd.DataFrame(meta_rows)
    epochs_per_run.append(ep)
    
epochs_all = mne.concatenate_epochs(epochs_per_run)
epochs_all.save(output_file,overwrite=True)
