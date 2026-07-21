"""Annotate artefacts in MaxFiltered DAD MEG recordings.

This script is the Python-script version of ``02_artefact_annotation.ipynb``.
It preserves the notebook's processing order and manual-review workflow while
placing non-interactive diagnostic plots in an MNE report.

Usage
-----
Run from a Python environment with MNE-Python and Qt browser support:

    python /Volumes/MORWUR/Projects/SHARED/mne-meg-preprocessing-pipeline/code/02_artefact_annotation.py

To process a different participant or session, edit ``config.toml``. The main
settings are ``dataset.subject``, ``dataset.session``, ``dataset.task``,
``dataset.runs``, and the ``annotation`` manual-review settings.

Manual eye-annotation workflow
------------------------------
The script intentionally opens MNE raw-browser windows for manual annotation
and inspection, matching the notebook workflow:

1. Set ``annotation.manual_annotation_run_index`` in ``config.toml`` to the run
   that should be reviewed.
2. Run the script and use the first browser window to mark intervals whose
   labels start with ``BAD_blink`` or ``BAD_eye_movement``.
3. Close the browser window. The script saves only those manual eye annotations
   under the configured derivative dataset's ``manual_eye`` folder.
4. Repeat for every run before running the final batch step with
   ``skip_manual_eye_ann = False``.

Inputs
------
The script expects the MaxFiltered files created by ``01_maxfilter.py``:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-maxfilter_meg.fif

Outputs
-------
Annotated FIF files and annotation CSV files are written per run:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-annotated_meg.fif
    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/*_desc-annotations.csv

Manual blink and eye-movement annotation files are written separately:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/meg/manual_eye/*_desc-manualeye-annot.fif

The muscle z-score diagnostic plot is collected in:

    <ROOT>/derivatives/mne-preprocessing/sub-<subject>/ses-<session>/reports/02_artefact_annotation.html

Key assumptions
---------------
Eye blinks and eye movements are manually identified from frontal MEG channels
and eye-tracker analog channels stored as ``MISC001``-``MISC006``. Muscle
artefacts are detected automatically from magnetometer data filtered in the
110-140 Hz range with a z-score threshold of 10. Artefacts are annotated rather
than removed, so later preprocessing steps can decide how to reject affected
epochs or time periods.
"""

# %%
from pathlib import Path
try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - for Python < 3.11
    import tomli as tomllib
import numpy as np
import mne
from mne.preprocessing import annotate_muscle_zscore
import matplotlib.pyplot as plt


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
maxfilter_dir = deriv_root / bids_subject / bids_session / "meg"
annotation_dir = deriv_root / bids_subject / bids_session / "meg"
manual_eye_annotation_dir = annotation_dir / "manual_eye"
report_dir = deriv_root / bids_subject / bids_session / "reports"
annotation_dir.mkdir(parents=True, exist_ok=True)
manual_eye_annotation_dir.mkdir(parents=True, exist_ok=True)
report_dir.mkdir(parents=True, exist_ok=True)

report_file = report_dir / "02_artefact_annotation.html"
report = mne.Report(title=f"02 Artefact annotation - {bids_subject} {bids_session}")

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

annotation_files = {
    max_file: annotation_dir / max_file.name.replace(
        "_desc-maxfilter_meg.fif", "_desc-annotated_meg.fif"
    )
    for max_file in maxfilter_files
}
annotation_csv_files = {
    max_file: annotation_dir / max_file.name.replace(
        "_desc-maxfilter_meg.fif", "_desc-annotations.csv"
    )
    for max_file in maxfilter_files
}
manual_eye_annotation_files = {
    max_file: manual_eye_annotation_dir / max_file.name.replace(
        "_desc-maxfilter_meg.fif", "_desc-manualeye-annot.fif"
    )
    for max_file in maxfilter_files
}

print("Config file:")
print("  ", config_file)
print("Pipeline root:")
print("  ", root)
print("Subject/session/task/runs:")
print("  ", bids_subject, bids_session, task, run_labels)

print("Input MaxFiltered files:")
for path in maxfilter_files:
    print("  ", path)

print("\nManual eye-annotation files:")
for path in manual_eye_annotation_files.values():
    print("  ", path)

print("\nOutput annotation files:")
for path in annotation_files.values():
    print("  ", path)

print("\nReport file:")
print("  ", report_file)


# %%
# -----------------------------------------------------------------------------
# Load first MaxFiltered run
# -----------------------------------------------------------------------------
# The notebook uses the first run as the worked example for muscle-threshold
# inspection and combined annotation review before processing the remaining runs.

first_file = maxfilter_files[0]
raw1 = mne.io.read_raw_fif(first_file, preload=True, verbose=True)
print(raw1)


# %%
# -----------------------------------------------------------------------------
# Eye-tracker channel mapping and manual-review settings
# -----------------------------------------------------------------------------
# DAD stores eye-tracker analog traces as MISC channels. These channels are
# plotted with frontal MEG sensors so blinks and eye movements can be marked
# manually in the MNE raw browser.

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

missing_eye_channels = [ch for ch in eye_tracker_channels if ch not in raw1.ch_names]
if missing_eye_channels:
    raise RuntimeError(f"Missing expected eye-tracker MISC channels: {missing_eye_channels}")

# Set this to True only if you intentionally want the batch step to continue
# when a run has not been manually reviewed for eye artefacts.
skip_manual_eye_ann = bool(config["annotation"]["skip_manual_eye_ann"])

# Select the run to inspect manually. Use 0 for the first MaxFiltered run,
# 1 for the second run, and so on.
manual_annotation_run_index = int(config["annotation"]["manual_annotation_run_index"])
if manual_annotation_run_index >= len(maxfilter_files):
    raise IndexError(
        "annotation.manual_annotation_run_index is outside the configured run list."
    )
manual_file = maxfilter_files[manual_annotation_run_index]
manual_raw = mne.io.read_raw_fif(manual_file, preload=True, verbose=True)

# Frontal sensors are useful context because ocular artefacts are strongest at
# the front of the helmet. These Neuromag sensor groups are intentionally broad
# enough to show frontal MEG activity without plotting the whole recording.
frontal_meg_prefixes = (
    "MEG011", "MEG012", "MEG013", "MEG014",
    "MEG021", "MEG022", "MEG023", "MEG024",
    "MEG031", "MEG032", "MEG033", "MEG034",
    "MEG041", "MEG042", "MEG043", "MEG044",
    "MEG051", "MEG052", "MEG053", "MEG054",
)
frontal_meg_channels = [
    ch for ch in manual_raw.ch_names
    if ch.startswith(frontal_meg_prefixes)
]
if not frontal_meg_channels:
    frontal_meg_channels = [
        manual_raw.ch_names[pick]
        for pick in mne.pick_types(manual_raw.info, meg=True, eeg=False, stim=False, misc=False)
    ][:30]

manual_plot_channels = frontal_meg_channels + eye_tracker_channels
manual_eye_annotation_prefixes = ("BAD_blink", "BAD_eye_movement")

print("Selected run:", manual_annotation_run_index, manual_file.name)
print("Manual eye annotations will be saved to:")
print("  ", manual_eye_annotation_files[manual_file])
print("Channels shown in the interactive browser:", len(manual_plot_channels))
print("Eye-tracker channels:", eye_tracker_channels)


# %%
# -----------------------------------------------------------------------------
# Interactive manual blink and eye-movement annotation
# -----------------------------------------------------------------------------
# This replaces the notebook's ``%matplotlib qt`` magic with explicit MNE browser
# usage. Close the browser after adding or editing BAD_blink and
# BAD_eye_movement annotations; the updated annotations remain in manual_raw.

mne.viz.set_browser_backend("qt")

manual_plot_scalings = dict(
    mag="auto",
    grad="auto",
    misc=1.0,
)

manual_raw.plot(
    picks=manual_plot_channels,
    n_channels=len(manual_plot_channels),
    duration=20,
    scalings=manual_plot_scalings,
    remove_dc=True,
    block=True,
)


# %%
# -----------------------------------------------------------------------------
# Save manual eye annotations for the selected run
# -----------------------------------------------------------------------------
# Only manual blink and eye-movement annotations are exported here. Existing
# acquisition annotations stay in the raw object and are not duplicated into the
# manual eye-annotation file.

def extract_manual_eye_annotations(raw):
    """Return only manually marked blink and eye-movement annotations.

    Parameters
    ----------
    raw : mne.io.BaseRaw
        Raw object after interactive manual annotation.

    Returns
    -------
    mne.Annotations
        Annotation object containing only descriptions whose labels start with
        ``BAD_blink`` or ``BAD_eye_movement``. If no matching labels exist, an
        empty annotation object is returned with the run measurement date.
    """
    keep = [
        index
        for index, description in enumerate(raw.annotations.description)
        if description.startswith(manual_eye_annotation_prefixes)
    ]
    if not keep:
        return mne.Annotations([], [], [], orig_time=raw.info["meas_date"])

    return mne.Annotations(
        onset=raw.annotations.onset[keep],
        duration=raw.annotations.duration[keep],
        description=raw.annotations.description[keep],
        orig_time=raw.annotations.orig_time,
    )


def load_manual_eye_annotations(maxfilter_file, raw, *, allow_missing=False):
    """Load manual blink/eye-movement annotations for one MaxFiltered run.

    Parameters
    ----------
    maxfilter_file : pathlib.Path
        MaxFiltered FIF file whose manual eye annotation file should be loaded.
    raw : mne.io.BaseRaw
        Raw object used to provide ``meas_date`` when an empty annotation object
        is allowed for a missing manual file.
    allow_missing : bool
        If True, missing manual eye annotations are treated as an intentionally
        empty review. If False, missing files stop processing so unreviewed runs
        are not silently accepted.

    Returns
    -------
    mne.Annotations
        Manual blink and eye-movement annotations for this run.
    """
    manual_eye_file = manual_eye_annotation_files[maxfilter_file]
    if manual_eye_file.exists():
        annotations = mne.read_annotations(manual_eye_file)
        print(f"Loaded {len(annotations)} manual eye annotations from {manual_eye_file}")
        return annotations

    if allow_missing:
        print(
            "WARNING: no manual eye annotations found for "
            f"{maxfilter_file.name}; continuing without blink/eye-movement annotations."
        )
        return mne.Annotations([], [], [], orig_time=raw.info["meas_date"])

    raise FileNotFoundError(
        "Manual eye annotations are missing for "
        f"{maxfilter_file.name}. Annotate this run first, or set "
        "skip_manual_eye_ann = True to continue without them."
    )


manual_eye_annotations = extract_manual_eye_annotations(manual_raw)
manual_eye_annotation_file = manual_eye_annotation_files[manual_file]
manual_eye_annotations.save(manual_eye_annotation_file, overwrite=True)

print(f"Saved {len(manual_eye_annotations)} manual eye annotations to:")
print("  ", manual_eye_annotation_file)
print("Descriptions:", sorted(set(manual_eye_annotations.description)))


# %%
# -----------------------------------------------------------------------------
# Automatic muscle artefact annotation for the first run
# -----------------------------------------------------------------------------
# Muscle artefacts are detected from magnetometer data filtered in the
# 110-140 Hz range and z-scored. The threshold follows the notebook default.

threshold_muscle = config["annotation"]["threshold_muscle"]
annotations_muscle, scores_muscle = annotate_muscle_zscore(
    raw1,
    ch_type="mag",
    threshold=threshold_muscle,
    min_length_good=0.2,
    filter_freq=[110, 140],
)
print("muscle annotations:", len(annotations_muscle))


# %%
# -----------------------------------------------------------------------------
# Report muscle z-score threshold check
# -----------------------------------------------------------------------------
# This replaces the notebook's inline Matplotlib plot. The threshold line and
# scores are saved into the subject-specific HTML report.

fig1, ax = plt.subplots(figsize=(14, 4))
ax.plot(raw1.times, scores_muscle, linewidth=0.5)
ax.axhline(y=threshold_muscle, color="r")
ax.set(
    xlabel="time (s)",
    ylabel="z-score",
    title=f"Muscle activity (threshold = {threshold_muscle})",
)
fig1.tight_layout()
report.add_figure(
    fig1,
    title=f"Muscle z-score threshold check - {first_file.name}",
    section="Muscle artefacts",
)
plt.close(fig1)


# %%
# -----------------------------------------------------------------------------
# Combine annotations in the first-run raw object
# -----------------------------------------------------------------------------
# set_annotations() replaces the current annotations, so the existing acquisition
# annotations are added explicitly alongside manual eye and muscle annotations.

annotations_event = raw1.annotations
annotations_manual_eye = load_manual_eye_annotations(
    first_file,
    raw1,
    allow_missing=skip_manual_eye_ann,
)
raw1.set_annotations(
    annotations_event + annotations_manual_eye + annotations_muscle
)

print(raw1.annotations)


# %%
# -----------------------------------------------------------------------------
# Interactive inspection of all annotations
# -----------------------------------------------------------------------------
# This browser mirrors the notebook review cell and lets the user inspect the
# combined event, manual eye, and muscle annotations before saving.

mne.viz.set_browser_backend("qt")
raw1.plot(start=50, block=True)


# %%
# -----------------------------------------------------------------------------
# Interactive inspection of eye-tracker analog channels
# -----------------------------------------------------------------------------
# Display only the configured MISC eye channels so blink and eye-movement labels
# can be checked against the analog traces.

mne.viz.set_browser_backend("qt")

scl = dict(misc=1.0)
eye_picks = mne.pick_channels(raw1.ch_names, include=eye_tracker_channels)
raw1.plot(picks=eye_picks, scalings=scl, start=50, block=True)


# %%
# -----------------------------------------------------------------------------
# Save annotated first run
# -----------------------------------------------------------------------------
# The annotated Raw FIF and a CSV copy of the annotations are saved separately so
# downstream scripts can use the FIF while humans can inspect the CSV.

raw1.save(annotation_files[first_file], overwrite=True)
raw1.annotations.save(annotation_csv_files[first_file], overwrite=True)
print("Saved", annotation_files[first_file])
print("Saved", annotation_csv_files[first_file])


# %%
# -----------------------------------------------------------------------------
# Batch annotation helper for remaining runs
# -----------------------------------------------------------------------------
# Manual eye annotations are loaded from the files saved during the manual-review
# pass. Muscle annotations are recomputed automatically for each run.

def count_annotations_with_prefix(annotations, prefix):
    """Count annotations whose description starts with a given prefix.

    Parameters
    ----------
    annotations : mne.Annotations
        Annotation object to count.
    prefix : str
        Prefix that accepted annotation descriptions must start with.

    Returns
    -------
    int
        Number of matching annotation descriptions.
    """
    return sum(description.startswith(prefix) for description in annotations.description)


def annotate_one_run(maxfilter_file):
    """Load one MaxFiltered run, add manual eye and muscle annotations, and save it.

    Parameters
    ----------
    maxfilter_file : pathlib.Path
        MaxFiltered FIF file to annotate.

    Returns
    -------
    dict
        Summary of input, output, manual eye annotation file, and annotation
        counts for blink, eye-movement, and muscle artefacts.
    """
    raw = mne.io.read_raw_fif(maxfilter_file, preload=True, verbose=True)

    annotations_manual_eye = load_manual_eye_annotations(
        maxfilter_file,
        raw,
        allow_missing=skip_manual_eye_ann,
    )
    annotations_muscle, _ = annotate_muscle_zscore(
        raw,
        ch_type="mag",
        threshold=threshold_muscle,
        min_length_good=0.2,
        filter_freq=[110, 140],
    )

    raw.set_annotations(
        raw.annotations + annotations_manual_eye + annotations_muscle
    )
    raw.save(annotation_files[maxfilter_file], overwrite=True)
    raw.annotations.save(annotation_csv_files[maxfilter_file], overwrite=True)

    return {
        "input": str(maxfilter_file),
        "manual_eye_annotation_file": str(manual_eye_annotation_files[maxfilter_file]),
        "output_fif": str(annotation_files[maxfilter_file]),
        "output_csv": str(annotation_csv_files[maxfilter_file]),
        "n_blink_annotations": count_annotations_with_prefix(annotations_manual_eye, "BAD_blink"),
        "n_eye_movement_annotations": count_annotations_with_prefix(
            annotations_manual_eye,
            "BAD_eye_movement",
        ),
        "n_muscle_annotations": len(annotations_muscle),
    }


run_summaries = []
for maxfilter_file in maxfilter_files[1:]:
    print(f"\nAnnotating {maxfilter_file.name}")
    run_summaries.append(annotate_one_run(maxfilter_file))

print(run_summaries)


# %%
# -----------------------------------------------------------------------------
# Save the MNE report
# -----------------------------------------------------------------------------
# The report collects non-interactive diagnostics from this notebook conversion.
# Interactive manual-review browser windows remain part of the script workflow.

report.save(report_file, overwrite=True)
print("Saved report", report_file)
