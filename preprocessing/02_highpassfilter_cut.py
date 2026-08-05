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
maxfilter_dir = deriv_root / bids_subject / bids_session / "meg"
deriv_dir = deriv_root / bids_subject / bids_session / 'meg'
report_dir = deriv_root / bids_subject / bids_session / "reports"

maxfilter_files = [
    maxfilter_dir / f"{bids_prefix}_run-{run}_desc-maxfilter_meg.fif"
    for run in run_labels
]
missing_maxfilter_files = [path for path in maxfilter_files if not path.is_file()]
if missing_maxfilter_files:
    missing = "\n  ".join(str(path) for path in missing_maxfilter_files)
    raise FileNotFoundError(
        "Missing configured MaxFiltered files. Run 01_maxfilter.py first.\n  "
        f"{missing}"
    )

sss_files = {
    file: deriv_dir / f'{bids_prefix}_run-{run}_desc-highpassfilter-cut_meg.fif'
    for file, run in zip(maxfilter_files, run_labels, strict=True)
}

maxfilter = {}
highpass_filter = {}

trial_start_codes = set(range(1, 40))
trial_end_codes   = set(range(61, 67))

# read maxfiltered files, filter out below 0.01 Hz, find events, crop.
for file in maxfilter_files:
    maxfilter[file] = mne.io.read_raw_fif(file, preload=True, verbose=True)

    signal = maxfilter[file].copy()  # independent copy — maxfilter[file] stays untouched
    signal.filter(l_freq=0.01, h_freq=None, picks='meg', verbose=True)

    sfreq = signal.info['sfreq']
    events = mne.find_events(signal, stim_channel='STI101', min_duration=2/sfreq, verbose=True)

    start_events = events[np.isin(events[:, 2], list(trial_start_codes))]
    end_events   = events[np.isin(events[:, 2], list(trial_end_codes))]

    if len(start_events) == 0 or len(end_events) == 0:
        raise ValueError(f"No trial-start or trial-end events found for {file.name}")

    start_time = (start_events[:,0]-signal.first_samp)/sfreq
    end_time = (end_events[:,0]-signal.first_samp)/sfreq

    padding_before = 0.1
    padding_after = 0.1

    tmin = max(0.0, start_time.min() - padding_before)
    tmax = min(signal.times[-1], end_time.max() + padding_after)

    signal.crop(
        tmin=tmin,
        tmax=tmax,
        include_tmax=True,
    )
    signal.save(sss_files[file], overwrite=True)

    highpass_filter[file] = signal

print("\nDone.")
