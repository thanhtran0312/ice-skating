## i have an output matrix from matlab for each run of each subject, so i compared the occlusion triggers there with the one from this script to see if the epoch cut into trials etc

# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import pandas as pd
import matplotlib
import pickle

# Use a non-interactive Matplotlib backend so review figures can be captured in
# the report when the script runs outside a notebook.
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import mne
from mne.preprocessing import ICA
import sys

# -----------------------------------------------------------------------------
# Load shared configuration
# -----------------------------------------------------------------------------
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

session = str(config["dataset"]["session"])
task = str(config["dataset"]["task"])
run_labels = [f"{int(run):02d}" for run in config["dataset"]["runs"]]
bids_session = f"ses-{session}"
deriv_root = root / config["paths"]["derivatives"]
trigger_values_config = {
            'trial_start': set(range(1, 40)),               # trig_trial_start = vid2disp(itrial) => movie id from 1 -39
            'trial_end'  : set(range(61, 67)),              # trig_trial_end = 60 + currentcondition(itrial)
            'occlusion_onset': set(range(71,89)),           # trig_occ_onset = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial) => 77-88
            'task_onset': set(range(91,109)),               # trig_task_onset = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
            'response': set(range(120, 129)),
            'movie_restart': set(range(131,149))            # trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
            }

subjects = ["01", "02", "03", "04"]

occs_fif = np.zeros((4,6))
for s,subject in enumerate(subjects):
    subject = subject.zfill(2)


    bids_subject = f"sub-{subject}"
    bids_prefix = f"{bids_subject}_{bids_session}_task-{task}"

    deriv_dir = deriv_root / bids_subject / bids_session / "meg"
    report_dir = deriv_root / bids_subject / bids_session / "reports"

    ica_files = [
        deriv_dir / f"{bids_prefix}_run-{run}_desc-ica_meg.fif"
        for run in run_labels
    ]

    for i, run in enumerate(config["dataset"]["runs"]):
        file = ica_files[i]
        raw = mne.io.read_raw_fif(file, preload=True)
        sfreq = raw.info["sfreq"]
        events = mne.find_events(
                raw,
                stim_channel="STI101",
                min_duration = 2/sfreq
                )

        occ_events = events[np.isin(events[:, 2], list(trigger_values_config['occlusion_onset']))]
        occs_fif[s,i] = len(occ_events)
# np.save('occs_fif.npy', occs_fif)

folders = glob.glob('/Volumes/THANH/IceSkating/data/matlab&eyetrack/SUB*')
output_matrices = []
for folder in folders:
    matrices = glob.glob(os.path.join(folder,'*mat'))
    output_matrices.extend(matrices)
output_matrices = natsort.natsorted(output_matrices)
outputs = []
for matrix in output_matrices:
    mat = loadmat(matrix, struct_as_record=False, squeeze_me=True)
    output = mat['output']  # this is a numpy array of MATLAB struct objects (mat_struct)
    outputs.extend(output)
    
records = []
for entry in outputs:
    records.append({field: getattr(entry, field) for field in entry._fieldnames})
df = pd.DataFrame(records)
occs = np.zeros((4,6))
for i in range(sub):
    for j in range(run):
        dfsub = df[(df['subnum'] == i+1) & (df['runnum'] == j+1)]
        n_occs = np.isin(dfsub['trigger'],list(trigger_values_config['occlusion_onset'])).sum()
        occs[i,j] = n_occs
if occs_fif != occs:
    diff = occs_fif - occs
    raise ValueError(f'{diff}')

