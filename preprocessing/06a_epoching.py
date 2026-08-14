"""because of some problems with the triggers, each trial ends up not having the same number of samples, here trying to squeeze and interpolate to the same length"""


# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import pandas as pd
import matplotlib
from utils import import_output_matrix, check_occ_frame
from scipy.signal import resample

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
        events = check_events_onerun(raw,subnum,runnum)
        start_events = events[np.isin(events[:, 2], list(trigger_values_config['trial_start']))] 
        start_keep = np.r_[True, start_events[1:, 2] != start_events[:-1, 2]]
        start_events = start_events[start_keep]
        end_events   = events[np.isin(events[:, 2], list(trigger_values_config['trial_end']))]
        end_keep = np.r_[True, end_events[1:, 2] != end_events[:-1, 2]]
        end_events = end_events[end_keep]

        start_time = (start_events[:,0] - signal.first_samp)
        end_time = (end_events[:,0] - signal.first_samp)

        trial_segments = []
        for i in range(n_trials):
            signal_per_trial = signal.copy().get_data(start = start_time[i], 
                                                      stop = end_time[i]+1)
            signal_per_trial = mne.io.RawArray(signal_per_trial,signal.info)
            trial_segments.append({
                "start_trigger": start_events[i],
                "end_trigger": end_events[i],
                "duration": end_time[i] - start_time[i],
                "raw": signal_per_trial
            })
        return trial_segments

    # take catch trials out
def remove_catch_trials(trial_segments, trigger_values_config,subnum,runnum):
        trials_for_onerun = []
        for trial in trial_segments:
            signal = trial['raw']
            events = check_events_onetrial(signal,subnum,runnum)
            # find catch trials:'occlusion_onset' = 77-88; 'movie_restart' = 131-148
            occ_events = events[np.isin(events[:, 2], list(trigger_values_config['occlusion_onset']))]
            restart_events = events[np.isin(events[:, 2], list(trigger_values_config['movie_restart']))]

            occ_time = (occ_events[:,0] - signal.first_samp)
            occ_time = np.concatenate((occ_time,np.array([signal.n_times])))        
            restart_time = ((restart_events[:,0] - signal.first_samp)) + 1000 # because i rewinded to 1s before the occlusion onset
            restart_time = np.concatenate((np.array([0]),restart_time))        

            n_occs = len(occ_time)
            segments = []
            for i in range(n_occs):
                segments_without_catchtrials = signal.copy().get_data(start = restart_time[i],
                                                                      stop = min(occ_time[i], int(signal.times[-1]*1000)))
                segments_without_catchtrials = mne.io.RawArray(segments_without_catchtrials,signal.info)
                segments.append(segments_without_catchtrials)
            trial_without_catchtrials = mne.concatenate_raws(segments,preload=True)
            trials_for_onerun.append(trial_without_catchtrials)
        return trials_for_onerun


def interpolate_raw_segment(raw_segment, target_n):
    """
    Linearly interpolate an MNE Raw segment to target_n samples,
    while keeping the original sampling frequency in the output.
    """

    data = raw_segment.get_data()
    n_channels, n_old = data.shape

    # Express both old and new sample positions over the same
    # normalized segment duration
    old_time = np.linspace(0, 1, n_old)
    new_time = np.linspace(0, 1, target_n)

    data_interp = np.empty((n_channels, target_n))

    for ch in range(n_channels):
        data_interp[ch] = np.interp(
            new_time,
            old_time,
            data[ch]
        )

    info = raw_segment.info.copy()

    raw_corrected = mne.io.RawArray(
        data_interp,
        info,
        first_samp=0,
        verbose=False
    )

    return raw_corrected

def correct_movie_timing_piecewise(
    segments,
    occ_frames,
    movie_total_frames=4200,
    movie_fps=50,
):
    """
    Correct the timing of each continuous movie segment using
    linear interpolation.

    segments:
        list of MNE Raw objects corresponding to:
            movie start -> occ1
            occ1 -> occ2
            occ2 -> occ3
            ...
            last occ -> movie end

    occ_frames:
        recovered true movie-frame positions of the occlusions.
    """

    sfreq = segments[0].info["sfreq"]

    # Movie-frame boundaries
    boundaries = np.r_[
        0,
        np.asarray(occ_frames, dtype=int),
        movie_total_frames
    ]

    # Intended duration of every segment in movie frames
    segment_frames = np.diff(boundaries)

    # Convert movie-frame durations to MEG sample counts
    target_lengths = np.round(
        segment_frames / movie_fps * sfreq
    ).astype(int)

    if len(segments) != len(target_lengths):
        raise ValueError(
            f"{len(segments)} MEG segments but "
            f"{len(target_lengths)} expected movie segments."
        )

    corrected_segments = []

    for i, (segment, target_n) in enumerate(
        zip(segments, target_lengths)
    ):

        print(
            f"Segment {i+1}: "
            f"{segment.n_times} -> {target_n} samples "
            f"(difference = {segment.n_times - target_n})"
        )

        corrected = interpolate_raw_segment(
            segment,
            target_n
        )

        corrected_segments.append(corrected)

    corrected_trial = mne.concatenate_raws(
        corrected_segments,
        preload=True
    )

    print(
        f"\nFinal corrected trial: "
        f"{corrected_trial.n_times} samples"
    )

    return corrected_trial
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

# trigger codes
trigger_values_config = {
        'trial_start': set(range(1, 40)),               # trig_trial_start = vid2disp(itrial) => movie id from 1 -39
        'trial_end'  : set(range(61, 67)),              # trig_trial_end = 60 + currentcondition(itrial)
        'occlusion_onset': set(range(71,89)),           # trig_occ_onset = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial) => 77-88
        'task_onset': set(range(91,109)),               # trig_task_onset = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
        'response': set(range(120, 129)),
        'movie_restart': set(range(131,149))            # trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
        }

all_runs_trials = []   # list of lists: trials_for_one_run per run
all_video_ids = []     # matching video IDs per run# Step 1 — Load one run's cleaned continuous data + events.
for i, run in enumerate(config["dataset"]["runs"]):
    file = ica_files[i]
    raw = mne.io.read_raw_fif(file, preload=True)
    # electricity went out in the last run of subject number 4 so we only have 4 trials 
    if file == deriv_dir / f"sub-04_ses-01_task-IceSkating_run-06_desc-ica_meg.fif":
        trial_segments = epoch(raw, trigger_values_config,subnum=int(subject),runnum=run, n_trials=4)
    else:
        trial_segments = epoch(raw, trigger_values_config,subnum=int(subject),runnum=run, n_trials=6) # a list of each trial appended, still include catch trials
    video_ids = [trial['start_trigger'][2] for trial in trial_segments]
    all_occ_frames = check_occ_frame(trigger_values_config,subnum=int(subject),runnum=run)

    trials_for_one_run = []
    for j,trial in enumerate(trial_segments):
        occ_frames = all_occ_frames[j+1]
        signal = trial['raw']
        events = check_events_onetrial(trigger_values_config,signal,subnum=int(subject),runnum=run)
            # find catch trials:'occlusion_onset' = 77-88; 'movie_restart' = 131-148
        occ_events = events[np.isin(events[:, 2], list(trigger_values_config['occlusion_onset']))]
        restart_events = events[np.isin(events[:, 2], list(trigger_values_config['movie_restart']))]

        occ_time = (occ_events[:,0] - signal.first_samp)
        occ_time = np.concatenate((occ_time,np.array([signal.n_times])))        
        restart_time = ((restart_events[:,0] - signal.first_samp)) + 1000 # because i rewinded to 1s before the occlusion onset
        restart_time = np.concatenate((np.array([0]),restart_time))        

        n_occs = len(occ_time)
        segments = []
        for k in range(n_occs):
                segments_without_catchtrials = signal.copy().get_data(start = restart_time[k],
                                                                      stop = min(occ_time[k], int(signal.times[-1]*1000)))
                segments_without_catchtrials = mne.io.RawArray(segments_without_catchtrials,signal.info)
                segments.append(segments_without_catchtrials)
        corrected_segments = correct_movie_timing_piecewise(
                segments,
                occ_frames,
                movie_total_frames=4200,
                movie_fps=50)
        trials_for_one_run.append(corrected_segments)
    all_runs_trials.append(trials_for_one_run)
    all_video_ids.append(video_ids)

epochs_per_run = []
for i, (trials_for_one_run, video_ids) in enumerate(zip(all_runs_trials, all_video_ids)):
        data = []
        meta_rows = []
        for idx, trial in enumerate(trials_for_one_run):
            raw_cropped = trial.copy()
            data.append(raw_cropped.get_data())
            meta_rows.append({"run": i+1, "trial": idx+1,"condition": video_ids[idx]})
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
