"""Fit and apply ICA to reduce artefacts in DAD MEG recordings.

This script is the Python-script version of ``03_ica.ipynb``. It preserves the
notebook processing order while collecting visual review plots in an MNE report
instead of relying on inline notebook display.

Usage
-----
Run from a Python environment with MNE-Python installed:

    python /Volumes/MORWUR/Projects/SHARED/mne-meg-preprocessing-pipeline/code/03_ica.py

To process a different participant or session, edit ``config.toml``. The main
settings are ``dataset.subject``, ``dataset.session``, ``dataset.task``,
``dataset.runs``, and the ``ica`` settings.

Manual ICA-review workflow
--------------------------
The central decision in this step is manual. Fit the ICA model, inspect the
report plots for source time courses, component topographies, eye-tracker timing
guides, and candidate component properties, then edit ``candidate_components``
and ``exclude_components`` in ``config.toml`` before applying ICA. Leave
``exclude_components`` empty until the components have been reviewed.

Inputs
------
The script expects annotated FIF files created by ``02_artefact_annotation.py``:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-annotated_meg.fif

If MaxFiltered files are present, the script checks that every MaxFiltered run
has a corresponding annotated input before ICA fitting begins.

Outputs
-------
The subject-level ICA model and per-run ICA-cleaned FIF files are written to:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-ica_ica.fif
    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-ica_meg.fif

Diagnostic plots are collected in:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/reports/03_ica.html

Key assumptions
---------------
ICA is fitted on concatenated MEG-only copies of the annotated runs after
resampling to 200 Hz and band-pass filtering from 1 to 40 Hz. Previously marked
bad segments are excluded during fitting with ``reject_by_annotation=True``.
The fitted subject-level decomposition is applied back to each original
annotated run separately so run structure and non-MEG channels are preserved.
"""

# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import matplotlib

# Use a non-interactive Matplotlib backend so review figures can be captured in
# the report when the script runs outside a notebook.
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import mne
from mne.preprocessing import ICA


# %%
# -----------------------------------------------------------------------------
# Load shared configuration
# -----------------------------------------------------------------------------
# All user-facing settings live in config.toml. If ``root`` is relative, it is
# interpreted relative to the config file so the whole folder can be moved.

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

subject = str(config["dataset"]["subject"]).zfill(2)
session = str(config["dataset"]["session"])
task = str(config["dataset"]["task"])
run_labels = [f"{int(run):02d}" for run in config["dataset"]["runs"]]

bids_subject = f"sub-{subject}"
bids_session = f"ses-{session}"
bids_prefix = f"{bids_subject}_{bids_session}_task-{task}"

deriv_root = root / config["paths"]["derivatives"]
deriv_meg_dir = deriv_root / bids_subject / bids_session / "meg"
report_dir = deriv_root / bids_subject / bids_session / "reports"
deriv_meg_dir.mkdir(parents=True, exist_ok=True)
report_dir.mkdir(parents=True, exist_ok=True)

report_file = report_dir / "03_ica.html"
report = mne.Report(title=f"03 ICA - {bids_subject} {bids_session}")

ann_files = [
    deriv_meg_dir / f"{bids_prefix}_run-{run}_desc-annotated_meg.fif"
    for run in run_labels
]
missing_ann_files = [path for path in ann_files if not path.is_file()]
if missing_ann_files:
    missing = "\n  ".join(str(path) for path in missing_ann_files)
    raise FileNotFoundError(
        "Missing configured annotated files. Run 02_artefact_annotation.py first.\n  "
        f"{missing}"
    )

ica_model_file = deriv_meg_dir / f"{bids_prefix}_desc-ica_ica.fif"
ica_output_files = {
    ann_file: deriv_meg_dir / ann_file.name.replace(
        "_desc-annotated_meg.fif", "_desc-ica_meg.fif"
    )
    for ann_file in ann_files
}

print("Config file:")
print("  ", config_file)
print("Pipeline root:")
print("  ", root)
print("Subject/session/task/runs:")
print("  ", bids_subject, bids_session, task, run_labels)

print("Input annotated files:")
for path in ann_files:
    print("  ", path)

print("\nICA model file:")
print("  ", ica_model_file)

print("\nCleaned output files:")
for path in ica_output_files.values():
    print("  ", path)

print("\nReport file:")
print("  ", report_file)


# %%
# -----------------------------------------------------------------------------
# Report helper
# -----------------------------------------------------------------------------
# MNE plotting functions can return one figure or a list of figures, depending
# on the visualization. This helper normalizes both cases and closes figures
# after they have been embedded in the report.

def add_figures_to_report(figures, title, section):
    """Add one or more MNE/Matplotlib figures to the report.

    Parameters
    ----------
    figures : matplotlib.figure.Figure | list | tuple
        Figure object or collection returned by an MNE plotting function.
    title : str
        Base title used in the report entry. If multiple figures are supplied,
        a part number is appended to keep titles unique.
    section : str
        Report section name.

    Returns
    -------
    None
        The function adds figures to the global ``report`` object and closes
        Matplotlib figures to avoid keeping unnecessary GUI state alive.
    """
    if figures is None:
        return

    if not isinstance(figures, (list, tuple)):
        figures = [figures]

    for index, fig in enumerate(figures, start=1):
        fig_title = title if len(figures) == 1 else f"{title} ({index})"
        report.add_figure(fig, title=fig_title, section=section)
        try:
            plt.close(fig)
        except TypeError:
            # Some MNE browser figures are not plain Matplotlib Figure objects.
            # They are still embedded above, so failing to close is not fatal.
            pass


# %%
# -----------------------------------------------------------------------------
# Eye-tracker channel mapping
# -----------------------------------------------------------------------------
# These MISC channels are not used for automatic ICA scoring here. They are used
# as synchronized timing information when interpreting ICA components.

left_eye = config["eye_tracker"]["left"]
right_eye = config["eye_tracker"]["right"]
left_eye_channels = {
    "x": left_eye[0],
    "y": left_eye[1],
    "pupil_or_validity": left_eye[2],
}
right_eye_channels = {
    "x": right_eye[0],
    "y": right_eye[1],
    "pupil_or_validity": right_eye[2],
}

eye_tracker_channels = [
    left_eye_channels["x"],
    left_eye_channels["y"],
    left_eye_channels["pupil_or_validity"],
    right_eye_channels["x"],
    right_eye_channels["y"],
    right_eye_channels["pupil_or_validity"],
]
print(eye_tracker_channels)


# %%
# -----------------------------------------------------------------------------
# Build the ICA fitting data
# -----------------------------------------------------------------------------
# ICA is fitted on prepared copies of the annotated runs. The original annotated
# FIF files are not modified here; each copy is reduced to MEG channels,
# resampled, filtered, and then concatenated for subject-level ICA fitting.

fit_raws = []
fit_summaries = []
for ann_file in ann_files:
    print(f"\nPreparing {ann_file.name}")
    raw = mne.io.read_raw_fif(ann_file, preload=True, verbose=True)

    missing_eye_channels = [ch for ch in eye_tracker_channels if ch not in raw.ch_names]
    if missing_eye_channels:
        print("Missing eye-tracker channels in this run:", missing_eye_channels)

    raw_fit = raw.copy().pick("meg")
    raw_fit.resample(config["ica"]["resample_sfreq"])
    raw_fit.filter(config["ica"]["l_freq"], config["ica"]["h_freq"])

    fit_summaries.append({
        "file": ann_file.name,
        "n_channels": raw_fit.info["nchan"],
        "n_samples": raw_fit.n_times,
        "sfreq": raw_fit.info["sfreq"],
        "bad_channels": list(raw_fit.info["bads"]),
    })
    fit_raws.append(raw_fit)

raw_resmpl_all = mne.concatenate_raws(fit_raws, on_mismatch="warn")
print("\nPrepared data for ICA:")
print(raw_resmpl_all)
print(fit_summaries)


# %%
# -----------------------------------------------------------------------------
# Fit and save the ICA model
# -----------------------------------------------------------------------------
# The FastICA settings match the notebook and DAD preprocessing defaults.
# Previously annotated bad segments are excluded from the fitting data.

ica = ICA(
    method="fastica",
    random_state=config["ica"]["random_state"],
    n_components=config["ica"]["n_components"],
    max_iter="auto",
    verbose=True,
)
ica.fit(raw_resmpl_all, reject_by_annotation=True, verbose=True)

ica.save(ica_model_file, overwrite=True)
print("Saved ICA model:", ica_model_file)


# %%
# -----------------------------------------------------------------------------
# Report ICA source time courses
# -----------------------------------------------------------------------------
# The notebook displayed component source traces inline. Here the same view is
# generated without opening a browser window and embedded in the report.

mne.viz.set_browser_backend("matplotlib")
fig = ica.plot_sources(
    raw_resmpl_all,
    title="ICA components",
    show=False,
)
add_figures_to_report(fig, "ICA source time courses", "ICA review")


# %%
# -----------------------------------------------------------------------------
# Report ICA component topographies
# -----------------------------------------------------------------------------
# Component topographies are a key part of deciding whether a component reflects
# eye, muscle, or other non-neural artefact structure.

fig = ica.plot_components(show=False)
add_figures_to_report(fig, "ICA component topographies", "ICA review")


# %%
# -----------------------------------------------------------------------------
# Eye-tracker annotation guide
# -----------------------------------------------------------------------------
# This guide plots the eye-tracker MISC traces and existing eye-related
# annotation masks for the first run. It is a visual timing reference, not an
# automatic ICA scoring step.

def robust_zscore(values):
    """Return a robust z-score using the median absolute deviation.

    Parameters
    ----------
    values : array-like
        Numeric time series to normalize.

    Returns
    -------
    numpy.ndarray
        Robust z-scored values. If the median absolute deviation and standard
        deviation are both unusable, zeros are returned to avoid false structure
        from constant or invalid channels.
    """
    values = np.asarray(values, dtype=float)
    median = np.nanmedian(values)
    mad = np.nanmedian(np.abs(values - median))
    scale = 1.4826 * mad
    if not np.isfinite(scale) or scale == 0:
        scale = np.nanstd(values)
    if not np.isfinite(scale) or scale == 0:
        return np.zeros_like(values)
    return (values - median) / scale


def annotation_mask(raw, descriptions):
    """Return a boolean mask for annotations whose description is selected.

    Parameters
    ----------
    raw : mne.io.BaseRaw
        Raw object containing annotations to convert into sample masks.
    descriptions : iterable of str
        Annotation descriptions that should be marked as True.

    Returns
    -------
    numpy.ndarray
        Boolean vector with one entry per raw sample.
    """
    descriptions = set(descriptions)
    mask = np.zeros(raw.n_times, dtype=bool)
    sfreq = raw.info["sfreq"]
    for annotation in raw.annotations:
        if annotation["description"] not in descriptions:
            continue
        start = max(0, int(round(annotation["onset"] * sfreq)) - raw.first_samp)
        stop = min(
            raw.n_times,
            int(round((annotation["onset"] + annotation["duration"]) * sfreq)) - raw.first_samp,
        )
        if stop > start:
            mask[start:stop] = True
    return mask


def plot_eye_tracker_with_annotations(raw, title, start_sec=0, duration_sec=60):
    """Plot eye-tracker traces and eye-related annotation masks.

    Parameters
    ----------
    raw : mne.io.BaseRaw
        Annotated raw run containing configured eye-tracker MISC channels.
    title : str
        Figure title.
    start_sec : float
        Start time in seconds for the displayed window.
    duration_sec : float
        Duration in seconds for the displayed window.

    Returns
    -------
    matplotlib.figure.Figure
        Figure showing robust-z-scored eye-tracker traces and binary masks for
        ``BAD_blink`` and ``BAD_eye_movement`` annotations.
    """
    available = [ch for ch in eye_tracker_channels if ch in raw.ch_names]
    if not available:
        raise RuntimeError("No configured eye-tracker MISC channels found in this raw file.")

    sfreq = raw.info["sfreq"]
    start = int(start_sec * sfreq)
    stop = min(raw.n_times, int((start_sec + duration_sec) * sfreq))
    times = raw.times[start:stop]
    data = raw.get_data(picks=available)[:, start:stop]
    blink_mask = annotation_mask(raw, ["BAD_blink"])[start:stop]
    movement_mask = annotation_mask(raw, ["BAD_eye_movement"])[start:stop]

    fig, axes = plt.subplots(len(available) + 1, 1, figsize=(14, 11), sharex=True)
    for ax, channel, values in zip(axes[:-1], available, data, strict=True):
        ax.plot(times, robust_zscore(values), linewidth=0.5)
        ax.set_ylabel(channel)
    axes[-1].plot(times, blink_mask.astype(float), label="BAD_blink")
    axes[-1].plot(times, movement_mask.astype(float), label="BAD_eye_movement")
    axes[-1].set_ylim(-0.1, 1.1)
    axes[-1].set_ylabel("mask")
    axes[-1].set_xlabel("time (s)")
    axes[-1].legend(loc="upper right")
    fig.suptitle(title)
    fig.tight_layout()
    return fig


first_ann_file = ann_files[0]
raw_review = mne.io.read_raw_fif(first_ann_file, preload=True, verbose=True)
fig = plot_eye_tracker_with_annotations(
    raw_review,
    f"Eye-tracker annotation guide: {first_ann_file.name}",
    start_sec=0,
    duration_sec=60,
)
add_figures_to_report(fig, "Eye-tracker annotation guide", "ICA review")


# %%
# -----------------------------------------------------------------------------
# Report candidate component properties
# -----------------------------------------------------------------------------
# Edit this list after inspecting the source traces and topographies. The
# properties plot is included to support manual exclusion decisions.

candidate_components = config["ica"]["candidate_components"]
fig = ica.plot_properties(
    raw_resmpl_all,
    picks=candidate_components,
    show=False,
)
add_figures_to_report(fig, "Candidate ICA component properties", "ICA review")


# %%
# -----------------------------------------------------------------------------
# Set ICA components to exclude
# -----------------------------------------------------------------------------
# Leave exclude_components empty in config.toml until the ICA components have
# been reviewed. After review, put the chosen component indices there.

ica.exclude = config["ica"]["exclude_components"]
print("Components marked for exclusion:", ica.exclude)


# %%
# -----------------------------------------------------------------------------
# Apply ICA to all annotated runs
# -----------------------------------------------------------------------------
# The ICA model was fitted on concatenated prepared copies, but correction is
# applied back to each original annotated run separately. This preserves run
# boundaries, annotations, and non-MEG channels.

cleaned_runs = []
for ann_file in ann_files:
    print(f"\nApplying ICA to {ann_file.name}")
    raw_ica = mne.io.read_raw_fif(ann_file, preload=True, verbose=True)
    ica.apply(raw_ica)

    output_file = ica_output_files[ann_file]
    raw_ica.save(output_file, overwrite=True)
    cleaned_runs.append(raw_ica)
    print("Saved", output_file)


# %%
# -----------------------------------------------------------------------------
# Select channels for before/after artefact-reduction inspection
# -----------------------------------------------------------------------------
# Frontal magnetometers are useful for ocular artefacts. If the preferred
# channels are not present, use the first available magnetometers as a fallback.

raw_before = raw_review
raw_after = cleaned_runs[0]

frontal_candidates = ["MEG0311", "MEG0121", "MEG1211", "MEG1411"]
chs = [ch for ch in frontal_candidates if ch in raw_before.ch_names]
if not chs:
    chs = raw_before.copy().pick("mag").ch_names[:4]
chan_idxs = [raw_before.ch_names.index(ch) for ch in chs]
print("Channels for before/after inspection:", chs)


# %%
# -----------------------------------------------------------------------------
# Report data before ICA correction
# -----------------------------------------------------------------------------
# This replaces the notebook's inline raw browser snapshot for the selected
# frontal channels before ICA projections are applied.

fig = raw_before.plot(
    order=chan_idxs,
    duration=5,
    show=False,
    title="Before ICA correction",
)
add_figures_to_report(fig, "Before ICA correction", "Before/after")


# %%
# -----------------------------------------------------------------------------
# Report data after ICA correction
# -----------------------------------------------------------------------------
# The same channels and duration are shown after ICA application so artefact
# reduction can be checked against the original signal.

fig = raw_after.plot(
    order=chan_idxs,
    duration=5,
    show=False,
    title="After ICA correction",
)
add_figures_to_report(fig, "After ICA correction", "Before/after")


# %%
# -----------------------------------------------------------------------------
# Save the MNE report
# -----------------------------------------------------------------------------
# The report stores the visual checkpoints that were inline in the notebook.

report.save(report_file, overwrite=True)
print("Saved report", report_file)
