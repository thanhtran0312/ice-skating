
# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import pandas as pd
import matplotlib
from utils import import_output_matrix


import mne
import sys

def check_events_onerun(signal,subnum,runnum):
    """if the events from mne.find_events() are not consistent with the one from the output matrix,
        we remove/modify to make it consistent"""
    output_matrix = import_output_matrix(subnum,runnum)
    trigger = output_matrix.trigger
    trigger = trigger[~np.isnan(trigger)].astype(int).to_numpy()
    tmp_events = mne.find_events(
                signal,
                stim_channel="STI101",
                shortest_event=1,
                initial_event=True,
            )
    for i, trig in enumerate(trigger):
        if trig != tmp_events[:,2][i]:
            tmp_events = np.delete(tmp_events,i,axis=0)
    # i = np.where(trigger != tmp_events[:,2][:len(trigger)])[0]
    # if np.size(i) == 0:
    #     events=tmp_events
    # else:
    #     events = np.delete(tmp_events,i,axis=0)
    return tmp_events


def check_events_onetrial(trigger_values_config,trial_signal,subnum,runnum):
    """if the events from mne.find_events() are not consistent with the one from the output matrix,
        we remove/modify to make it consistent"""
    tmp_events = mne.find_events(
                trial_signal,
                stim_channel="STI101",
                shortest_event=1,
                initial_event=True,
            )
    start_trial = tmp_events[:,2][np.isin(tmp_events[:,2],list(trigger_values_config['trial_start']))]
    start_keep = np.r_[True, start_trial[1:] != start_trial[:-1]]
    start_trial = start_trial[start_keep]
    end_trial = tmp_events[:,2][np.isin(tmp_events[:,2],list(trigger_values_config['trial_end']))]
    end_keep = np.r_[True, end_trial[1:] != end_trial[:-1]]
    end_trial = end_trial[end_keep]
    output_matrix = import_output_matrix(subnum,runnum)
    trigger = output_matrix.trigger
    trigger = trigger[~np.isnan(trigger)].astype(int).to_numpy()
    trigger = trigger[np.where(trigger == start_trial)[0][0]:np.where(trigger==end_trial)[0][0]+1]    
    for i, trig in enumerate(trigger):
        if trig != tmp_events[:,2][i]:
            tmp_events = np.delete(tmp_events,i,axis=0)
   
    # i = np.where(trigger != tmp_events[:,2][:len(trigger)])[0]
    # if np.size(i) == 0:
    #     events=tmp_events
    # else:
    #     events = np.delete(tmp_events,i,axis=0)
    return tmp_events
         
         
def epoch(signal,trigger_values_config, subnum, runnum, n_trials=6):
        """mne.Epochs() only works for fixed-length segments, this function here supports variable lengths"""   
        events = check_events_onerun(signal,subnum,runnum)
        start_events = events[np.isin(events[:, 2], list(trigger_values_config['trial_start']))] 
        start_keep = np.r_[True, start_events[1:, 2] != start_events[:-1, 2]]
        start_events = start_events[start_keep]
        end_events   = events[np.isin(events[:, 2], list(trigger_values_config['trial_end']))]
        end_keep = np.r_[True, end_events[1:, 2] != end_events[:-1, 2]]
        end_events = end_events[end_keep]

        start_time = (start_events[:,0] - signal.first_samp)
        end_time = (end_events[:,0] - signal.first_samp)

        trial_segments = []
        for i in range(6):
            signal_per_trial = raw.copy().get_data(start = start_time[i], 
                                                    stop = end_time[i]+1)

            signal_per_trial = mne.io.RawArray(signal_per_trial,raw.info)
            trial_segments.append({
                            "start_trigger": start_events[i],
                            "end_trigger": end_events[i],
                            'duration': (end_time[i] - start_time[i] + 1) / raw.info['sfreq'],
                            "raw": signal_per_trial
                        })
        return trial_segments

    # take catch trials out
def remove_catch_trials(trial_segments, trigger_values_config,subnum,runnum):
    trials_for_onerun = []
    for t,trial in enumerate(trial_segments):
                signal = trial['raw']
                tmp_events = mne.find_events(
                                signal,
                                stim_channel="STI101",
                                shortest_event=1,
                                initial_event=True,
                            )
                            # find catch trials:'occlusion_onset' = 77-88; 'movie_restart' = 131-148
                occ_events = tmp_events[np.isin(tmp_events[:, 2], list(trigger_values_config['occlusion_onset']))]
                continue_events = tmp_events[np.isin(tmp_events[:,2], list(trigger_values_config['continuation']))]
                occ_time = (occ_events[:,0] - signal.first_samp)
                occ_time = np.concatenate((occ_time,np.array([signal.n_times])))        

                continue_time = continue_events[:,0] - signal.first_samp
                continue_time = continue_time - signal.info['sfreq']/50           
                restart_time = np.concatenate(([0], continue_time))
                n_occs = len(occ_time)
                segments = []
                for i in range(n_occs):
                    segments_without_catchtrials = signal.copy().get_data(start=int(restart_time[i]), stop=int(occ_time[i]))
                    segments_without_catchtrials = mne.io.RawArray(segments_without_catchtrials,signal.info)
                    segments.append(segments_without_catchtrials)
                trial_without_catchtrials = mne.concatenate_raws(segments,preload=True)
                trials_for_onerun.append(trial_without_catchtrials)
    return trials_for_onerun

# %%
if __name__ == '__main__':
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

    # trigger codes
    trigger_values_config = {
            'trial_start': set(range(1, 40)),               # trig_trial_start = vid2disp(itrial) => movie id from 1 -39
            'trial_end'  : set(range(41, 47)),              # trig_trial_end = 60 + currentcondition(itrial)
            'occlusion_onset': set(range(51,69)),           # trig_occ_onset = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial) => 77-88
            'task_onset': set(range(71,89)),               # trig_task_onset = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
            'response': set(range(100, 109)),
            'movie_restart': set(range(111,129)), 
            'continuation': set(range(131,149))
            }

    all_runs_trials = []   # list of lists: trials_for_one_run per run
    all_video_ids = []     # matching video IDs per run# Step 1 — Load one run's cleaned continuous data + events.
    for i, run in enumerate(config["dataset"]["runs"]):
        file = ica_files[i]
        raw = mne.io.read_raw_fif(file, preload=True)
        # electricity went out in the last run of subject number 4 so we only have 4 trials 
        if file == deriv_dir / f"sub-04_ses-01_task-IceSkating_run-06_desc-ica_meg.fif":
            trial_segments = epoch(raw, trigger_values_config,subnum=subject,runnum=run, n_trials=4)
        else:
            trial_segments = epoch(raw, trigger_values_config,subnum=subject,runnum=run, n_trials=6) # a list of each trial appended, still include catch trials
        video_ids = [trial['start_trigger'][2] for trial in trial_segments]
        trials_for_one_run = remove_catch_trials(trial_segments, trigger_values_config,subnum=subjects,runnum=run) # a list of 6 trials, catch trials excluded

        all_runs_trials.append(trials_for_one_run)
        all_video_ids.append(video_ids)
    ## resample to a common length

    epochs_per_run = []
    for i, (trials_for_one_run, video_ids) in enumerate(zip(all_runs_trials, all_video_ids)):
        data = []
        meta_rows = []
        for idx, trial in enumerate(trials_for_one_run):
            raw_cropped = trial.copy()
            data.append(raw_cropped.get_data())
            meta_rows.append({"run": i, "trial": idx,"condition": video_ids[idx]})
        data = np.stack(data)  # (n_trials, n_channels, n_times)

        events = np.column_stack([
                np.arange(len(trials_for_one_run)),   
                np.zeros(len(trials_for_one_run), dtype=int),
                np.arange(len(trials_for_one_run),dtype=int)                 # event_id = condition idx
            ])

        ep = mne.EpochsArray(data, trials_for_one_run[0].info, events=events, tmin=0, verbose=False)
        ep.metadata = pd.DataFrame(meta_rows)
        epochs_per_run.append(ep)
        
    epochs_all = mne.concatenate_epochs(epochs_per_run)
    epochs_all.save(output_file,overwrite=True)
