"""Apply Maxwell filtering after identifying bad MEG sensors.

This script is the Python-script version of ``01_maxfilter.ipynb``. It keeps
the notebook processing order intact while replacing inline notebook plots with
an MNE report saved under the subject-specific reports directory.

Usage
-----
Run from any working directory with the Python environment that has MNE-Python
installed:

    python /Volumes/MORWUR/Projects/SHARED/mne-meg-preprocessing-pipeline/code/01_maxfilter.py

To process a different participant or session, edit ``config.toml``. The main
settings are ``dataset.subject``, ``dataset.session``, ``dataset.task``, and
``dataset.runs``.

Inputs
------
The script expects the BIDS-oriented example layout:

    <ROOT>/sub-<subject>/ses-<session>/meg/*_task-<task>_run-<run>_meg.fif
    <ROOT>/sub-<subject>/ses-<session>/meg/*_acq-crosstalk_meg.fif
    <ROOT>/sub-<subject>/ses-<session>/meg/*_acq-calibration_meg.dat

Outputs
-------
Maxwell-filtered FIF files are written one run at a time:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-maxfilter_meg.fif

Diagnostic plots that were shown inline in the notebook are collected in:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/reports/01_maxfilter.html

Key assumptions
---------------
Bad channels are detected separately for every acquisition run, the union of
those bad channels is applied to every run, a common destination head position
is selected from the real acquisition run closest to the average head position,
and Maxwell filtering is applied independently per run. Raw acquisition runs
are not concatenated before Maxwell filtering.
"""

# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import matplotlib
import json, os

# Use a non-interactive backend so figures can be captured into the report when
# the script is run outside a notebook session.
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import mne
mne.viz.set_browser_backend("matplotlib")

# %%
# -----------------------------------------------------------------------------
# Load shared configuration
# -----------------------------------------------------------------------------
# All user-facing settings live in config.toml. If ``root`` is relative, it is
# interpreted relative to the config file so the whole folder can be moved.

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
# if not root.is_absolute():
#     root = (config_file.parent / root).resolve()

subject = str(config["dataset"]["subject"]).zfill(2)
session = str(config["dataset"]["session"])
task = str(config["dataset"]["task"])
run_labels = [f"{int(run):02d}" for run in config["dataset"]["runs"]]

bids_subject = f"sub-{subject}"
bids_session = f"ses-{session}"
bids_prefix = f"{bids_subject}_{bids_session}_task-{task}"

raw_dir = root / bids_subject / bids_session / "meg"
deriv_root = root / config["paths"]["derivatives"]
deriv_dir = deriv_root / bids_subject / bids_session / "meg"
report_dir = deriv_root / bids_subject / bids_session / "reports"
deriv_dir.mkdir(parents=True, exist_ok=True)
report_dir.mkdir(parents=True, exist_ok=True)

report_file = report_dir / "01_maxfilter.html"
report = mne.Report(title=f"01 MaxFilter - {bids_subject} {bids_session}")

raw_files = [
    raw_dir / f"{bids_prefix}_run-{run}_meg.fif"
    for run in run_labels
]
missing_raw_files = [path for path in raw_files if not path.is_file()]
if missing_raw_files:
    missing = "\n  ".join(str(path) for path in missing_raw_files)
    raise FileNotFoundError(f"Missing configured raw FIF files:\n  {missing}")

sss_files = {
    raw_file: deriv_dir / f"{bids_prefix}_run-{run}_desc-maxfilter_meg.fif"
    for raw_file, run in zip(raw_files, run_labels, strict=True)
}

print("Config file:")
print("  ", config_file)
print("Pipeline root:")
print("  ", root)
print("Subject/session/task/runs:")
print("  ", bids_subject, bids_session, task, run_labels)

print("Raw files:")
for raw_file in raw_files:
    print("  ", raw_file)

print("\nOutput files:")
for raw_file, sss_file in sss_files.items():
    print("  ", sss_file)

print("\nReport file:")
print("  ", report_file)


# %%
# -----------------------------------------------------------------------------
# Calibration and cross-talk files
# -----------------------------------------------------------------------------
# These site-specific files should come from the local MEG facility. They are
# required both for bad-channel detection with Maxwell filtering and for the
# final SSS reconstruction.

crosstalk_file = raw_dir / f"{bids_subject}_{bids_session}_acq-crosstalk_meg.fif"
calibration_file = raw_dir / f"{bids_subject}_{bids_session}_acq-calibration_meg.dat"

if not crosstalk_file.is_file():
    raise FileNotFoundError(crosstalk_file)
if not calibration_file.is_file():
    raise FileNotFoundError(calibration_file)

print(crosstalk_file)
print(calibration_file)


# %%
# -----------------------------------------------------------------------------
# Read raw acquisition runs
# -----------------------------------------------------------------------------
# All runs are loaded because the bad-channel detection and Maxwell filtering
# steps operate on the signal. Processing remains run-wise throughout the script.

raws = {}
for raw_file in raw_files:
    print(f"\nReading {raw_file.name}")
    raws[raw_file] = mne.io.read_raw_fif(raw_file, preload=True, verbose=True)

print("\nLoaded runs:")
for raw_file, raw in raws.items():
    print(
        f'{raw_file.name}: {raw.info["nchan"]} channels, '
        f'{raw.n_times} samples, sfreq={raw.info["sfreq"]}'
    )


# %%
# -----------------------------------------------------------------------------
# Automatic bad-channel detection per run
# -----------------------------------------------------------------------------
# Each run is inspected independently, then the union of noisy and flat channels
# is applied to every run so the channel basis is consistent downstream.

detected_bads = {}
for raw_file, raw in raws.items():
    print(f"\nDetecting bad channels in {raw_file.name}")
    raw_for_detection = raw.copy()
    raw_for_detection.info["bads"] = []

    auto_noisy_chs, auto_flat_chs, auto_scores = mne.preprocessing.find_bad_channels_maxwell(
        raw_for_detection,
        cross_talk=str(crosstalk_file),
        calibration=str(calibration_file),
        return_scores=True,
        verbose=True,
    )

    detected_bads[raw_file] = {
        "noisy": list(auto_noisy_chs),
        "flat": list(auto_flat_chs),
    }

    print("noisy =", auto_noisy_chs)
    print("flat  =", auto_flat_chs)

union_bad_channels = sorted({
    ch
    for run_bads in detected_bads.values()
    for ch in (run_bads["noisy"] + run_bads["flat"])
})

print("\nUnion of bad channels across all runs:")
print(union_bad_channels)

with open(os.path.join(script_dir,'union_bad_channels.json'),'w') as f:
    json.dump(union_bad_channels,f,indent=2)

with open(os.path.join(script_dir,'detected_bads.json'),'w') as f:
    json.dump(detected_bads,f,indent=2)