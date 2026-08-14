"""for the purpose of this pilot i ignore the factor task for now and average over videos A from all runs, 
and videos D from all runs (so i have 6 reps to average over), and then concatenate video A and D (they are one filter condition)
so i have 2:50 min of data for subsampling (with a mask between the videos so no subsample crosses the video boundary). 
And this i can then do separately for the three filter conditions. so here is the step to average over videos for each video_id of a subject"""


from utils_checkoccframe import unique
from pathlib import Path
from scipy.io import savemat

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import pandas as pd
import mne
import sys


script_dir = Path('__file__').resolve().parent

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
bids_subject = f"sub-{subject}"
bids_session = f"ses-{session}"
bids_prefix = f"{bids_subject}_{bids_session}_task-{task}"

output_path = script_dir.parents[0] / 'preprocessed_data'
path = script_dir.parents[0]/'derivatives'/'mne-preprocessing'/'sub-01'/'ses-01'/'meg'
epoch_files = path / f"{bids_prefix}_epo.fif"

epochs = mne.read_epochs(epoch_files, preload=True).pick("meg")

vid_ids = epochs.metadata['condition'].to_numpy()
unique_vid_ids = unique(vid_ids)
data = epochs.pick("meg").get_data() # 36, 306, 84000

n_channels = epochs.info['nchan']
n_timepoints = epochs.times.shape[0]
vid_average = {
    vid_id: []
    for vid_id in unique_vid_ids
}

for vid_id in unique_vid_ids:
    one_vid_average = np.mean(data[epochs.metadata['condition']==vid_id],axis=0)
    vid_average[vid_id] = one_vid_average

file_name = output_path / f"sub-{subject}_vid_average.mat"

savemat(file_name,vid_average)
