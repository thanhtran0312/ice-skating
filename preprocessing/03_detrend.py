from scipy.signal import detrend
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # for Python < 3.11
    import tomli as tomllib
import numpy as np
import matplotlib.pyplot as plt
import mne
import sys


script_dir = Path('__file__').resolve().parent
config_file = Path('config.toml')
if not config_file.exists():
    for parent in Path.cwd().resolve().parents:
        candidate = parent / 'config.toml'
        if candidate.exists():
            config_file = candidate
            break
if not config_file.exists():
    raise FileNotFoundError('Could not find config.toml. Start Jupyter from the pipeline root or edit config_file.')

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
highpassfilter_cut_dir = deriv_root / bids_subject / bids_session / "meg"
deriv_dir = deriv_root / bids_subject / bids_session / 'meg'
report_dir = deriv_root / bids_subject / bids_session / "reports"

highpassfilter_cut_files = [
    highpassfilter_cut_dir / f"{bids_prefix}_run-{run}_desc-highpassfilter-cut_meg.fif"
    for run in run_labels
]
# missing_maxfilter_files = [path for path in maxfilter_files if not path.is_file()]
# if missing_maxfilter_files:
#     missing = "\n  ".join(str(path) for path in missing_maxfilter_files)
#     raise FileNotFoundError(
#         "Missing configured MaxFiltered files. Run 01_maxfilter.py first.\n  "
#         f"{missing}"
#     )

sss_files = {
    file: deriv_dir / f'{bids_prefix}_run-{run}_desc-detrend_meg.fif'
    for file, run in zip(highpassfilter_cut_files, run_labels, strict=True)
}

for cropped_file in highpassfilter_cut_files:
    print(f"\nDetrending {cropped_file.name}")
    raw = mne.io.read_raw_fif(cropped_file, preload=True, verbose=True)

    picks = mne.pick_types(raw.info, meg=True, eeg=False, stim=False, misc=False)
    data = raw.get_data(picks=picks)

    # Keep a copy for before/after report figures
    data_before = data.copy()

    data_detrended = detrend(data, axis=-1, type="linear")
    raw._data[picks] = data_detrended

    output_file = sss_files[cropped_file]
    raw.save(output_file, overwrite=True)
    print("Saved", output_file)
