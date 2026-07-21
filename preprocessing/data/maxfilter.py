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
import json, os, pickle

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

for raw_file, run_bads in detected_bads.items():
    print(raw_file.name)
    print("  noisy:", run_bads["noisy"])
    print("  flat: ", run_bads["flat"])

print("\nFinal bad-channel list applied to every run:")
print(union_bad_channels)


# %%
# -----------------------------------------------------------------------------
# Report bad-channel time courses
# -----------------------------------------------------------------------------
# The notebook displayed these traces inline. In the script, the figure is
# created without opening a window and then added to the MNE report.

example_bad_channels = union_bad_channels[:4]
first_raw_file = raw_files[0]

if example_bad_channels:
    raw_bad_preview = raws[first_raw_file].copy().pick(example_bad_channels)
    fig = raw_bad_preview.plot(
        proj=False,
        show=False,
        title=f"Detected bad-channel traces - {first_raw_file.name}",
    )
    report.add_figure(
        fig,
        title="Detected bad-channel traces",
        section="Bad channels",
    )
    plt.close(fig)
else:
    print("No automatic bad channels were detected, so there are no bad-channel traces to plot.")


# %%
# -----------------------------------------------------------------------------
# Report bad-channel power spectra
# -----------------------------------------------------------------------------
# Spectra for the same preview sensors are captured in the report so the HTML
# output replaces the notebook's inline PSD display.

if example_bad_channels:
    n_fft = 2000
    temp_psd = raw_bad_preview.compute_psd(
        method="welch",
        fmin=1,
        fmax=60,
        n_fft=min(n_fft, raw_bad_preview.n_times),
        n_overlap=min(int(n_fft / 2), max(raw_bad_preview.n_times - 1, 0)),
    )
    fig = temp_psd.plot(show=False)
    report.add_figure(
        fig,
        title="Detected bad-channel spectra",
        section="Bad channels",
    )
    plt.close(fig)
else:
    print("No automatic bad channels were detected, so there are no bad-channel spectra to plot.")


with open(os.path.join(script_dir, 'detected_bads.pkl'), 'wb') as f:
    pickle.dump(detected_bads, f)

# %%
# -----------------------------------------------------------------------------
# Apply common bad-channel list
# -----------------------------------------------------------------------------
# Replace any pre-existing header bad labels with the union derived above so the
# MaxFilter decision is explicit and reproducible.

for raw_file, raw in raws.items():
    raw.info["bads"] = list(union_bad_channels)
    print(raw_file.name, "bads =", raw.info["bads"])


# %%
# -----------------------------------------------------------------------------
# Harmonize MEGIN magnetometer coil types
# -----------------------------------------------------------------------------
# This follows the FLUX recommendation to make magnetometer coil definitions
# compatible across MEGIN systems before applying Maxwell filtering.

for raw_file, raw in raws.items():
    raw.fix_mag_coil_types()
    print(f"Checked magnetometer coil types for {raw_file.name}")


# %%
# -----------------------------------------------------------------------------
# Common destination head position
# -----------------------------------------------------------------------------
# Select the acquisition run whose head origin is closest to the average head
# origin across all loaded runs. Positions are compared in MEG device
# coordinates, which represent where the head was inside the helmet.

head_origin_dev = {}

for raw_file in raw_files:
    dev_head_t = raws[raw_file].info.get("dev_head_t")
    if dev_head_t is None:
        raise RuntimeError(f"Missing dev_head_t for {raw_file.name}")

    # info["dev_head_t"] maps device -> head. Invert it so the translation is
    # the head origin expressed in device coordinates.
    head_dev_t = mne.transforms.invert_transform(dev_head_t)
    head_origin_dev[raw_file] = head_dev_t["trans"][:3, 3]

head_positions = np.vstack([head_origin_dev[raw_file] for raw_file in raw_files])
mean_head_position = head_positions.mean(axis=0)

distance_to_mean = {
    raw_file: np.linalg.norm(head_origin_dev[raw_file] - mean_head_position)
    for raw_file in raw_files
}

destination_file = min(distance_to_mean, key=distance_to_mean.get)
destination = raws[destination_file].info["dev_head_t"]

print("Average head origin in device coordinates [m]:", mean_head_position)
print("\nDistance from average head position:")
for raw_file in raw_files:
    print(f"{raw_file.name}: {distance_to_mean[raw_file] * 1000:.2f} mm")

print("\nCommon destination run:", destination_file.name)
print(destination)


# %%
# -----------------------------------------------------------------------------
# Maxwell filtering per acquisition run
# -----------------------------------------------------------------------------
# SSS is applied independently to every raw run using the common destination
# head position selected above. The raw runs are not concatenated at this stage.

raws_sss = {}
for raw_file, raw in raws.items():
    print(f"\nApplying Maxwell filtering to {raw_file.name}")
    raws_sss[raw_file] = mne.preprocessing.maxwell_filter(
        raw,
        cross_talk=str(crosstalk_file),
        calibration=str(calibration_file),
        destination=destination,
        st_duration=None,
        st_correlation=0.98,
        verbose=True,
    )

    raws_sss[raw_file].save(sss_files[raw_file], overwrite=True)
print("\nFinished Maxwell filtering for all runs.")


