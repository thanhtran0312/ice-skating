import glob,os
from scipy.io import loadmat
import numpy as np
import natsort
import pandas as pd

def import_output_matrix(subnum,runnum):
    """one sub one run at a time"""
    
    folders = glob.glob('./matlab&eyetrack/SUB*')
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
    dfsub = df[(df['subnum']==subnum) & (df['runnum']==runnum)]
    return dfsub

def unique(array):
    uniq, index = np.unique(array, return_index=True)
    return uniq[index.argsort()]

def estimate_occlusion_frames(
    df,
    trigger_values_config,
    fps=50,
    rewind_sec=1.0,
):
    """
    Estimate the original movie-frame position of each occlusion using
    GetSecs timestamps stored in df.task_onset.

    Logic
    -----
    First occlusion:
        frame ~= (occ_time - trial_start_time) * fps

    Later occlusions:
        frame ~= previous_occ_frame
                 - rewind_sec * fps
                 + (occ_time - previous_restart_time) * fps

    Parameters
    ----------
    df : pandas.DataFrame
        Output matrix imported from MATLAB.
        Must contain:
            'trial'
            'trigger'
            'task_onset'

    trigger_values_config : dict
        Dictionary containing at least:
            'trial_start'
            'trial_end'
            'occlusion_onset'
            'movie_restart'

    fps : float
        Movie frame rate.

    rewind_sec : float
        Amount the movie was rewound after each occlusion.

    Returns
    -------
    result : pandas.DataFrame
        One row per occlusion with:
            trial
            occ_num
            occ_trigger
            getsecs
            estimated_frame
            estimated_movie_time
            previous_restart_getsecs
    """

    # Keep trigger and task_onset aligned
    tmp = df.loc[
        df["trigger"].notna() &
        df["task_onset"].notna()
    ].copy()

    tmp["trigger"] = tmp["trigger"].astype(int)

    results = []

    # use actual trial numbers if present
    trials = tmp["trial"].dropna().astype(int).unique()

    for trial in trials:

        trial_df = tmp[tmp["trial"] == trial].copy()

        # preserve experiment order
        trial_df = trial_df.sort_index()

        start_rows = trial_df[
            trial_df["trigger"].isin(
                trigger_values_config["trial_start"]
            )
        ]

        occ_rows = trial_df[
            trial_df["trigger"].isin(
                trigger_values_config["occlusion_onset"]
            )
        ]

        restart_rows = trial_df[
            trial_df["trigger"].isin(
                trigger_values_config["movie_restart"]
            )
        ]

        if len(start_rows) == 0:
            print(f"Trial {trial}: no trial-start trigger found")
            continue

        trial_start_time = start_rows.iloc[0]["task_onset"]

        occ_rows = occ_rows.sort_index()
        restart_rows = restart_rows.sort_index()

        previous_occ_frame = None
        previous_restart_time = None

        for occ_idx, (_, occ_row) in enumerate(occ_rows.iterrows(), start=1):
            occ_time = occ_row["task_onset"]
            if occ_idx == 1:

                estimated_frame = (
                    occ_time - trial_start_time
                ) * fps
            else:

                if previous_restart_time is None:
                    estimated_frame = np.nan

                else:
                    elapsed_since_restart = (
                        occ_time - previous_restart_time
                    )

                    estimated_frame = (
                        previous_occ_frame
                        - rewind_sec * fps
                        + elapsed_since_restart * fps
                    )

            results.append({
                "trial": trial,
                "occ_num": occ_idx,
                "occ_trigger": int(occ_row["trigger"]),
                "getsecs": occ_time,
                "estimated_frame": estimated_frame,
                "estimated_movie_time": (
                    estimated_frame / fps
                    if np.isfinite(estimated_frame)
                    else np.nan
                ),
                "previous_restart_getsecs": previous_restart_time,
            })

            previous_occ_frame = estimated_frame

            # restart AFTER this occlusion
            if occ_idx <= len(restart_rows):
                previous_restart_time = (
                    restart_rows.iloc[occ_idx - 1]["task_onset"]
                )
            else:
                previous_restart_time = None

    return pd.DataFrame(results)

def nearest_candidate(estimated_frame, candidate_frames):
    candidate_frames = np.asarray(candidate_frames)

    idx = np.argmin(
        np.abs(candidate_frames - estimated_frame)
    )
    return candidate_frames[idx]


def check_occ_frame(trigger_values_config,subnum,runnum):
    occ_matrix = loadmat('/mnt/storage/tier2/ingdev/projects/THANH/IceSkating/data/occlusion_matrix.mat')['occlusion_onset']
    df = import_output_matrix(subnum,runnum)
    movie = unique(df.video[~np.isnan(df.video)].astype(int).to_numpy())

    estimated_occs = estimate_occlusion_frames(df,trigger_values_config,fps=50,rewind_sec=1.0)
    trials = unique(estimated_occs['trial'])
    all_occs = {
        trial : []
        for trial in range(1,7)
    }
    for i in range(len(trials)):
        candidates = occ_matrix[movie[i]-1]
        occs_per_trial = estimated_occs['estimated_frame'][estimated_occs['trial']==i+1]
        for occs in occs_per_trial:
            frame = nearest_candidate(
                occs,candidates
            )
            all_occs[i+1].append(frame)
    return all_occs

# if __name__ == '__main__':

#     trigger_values_config = {
#             'trial_start': set(range(1, 40)),               # trig_trial_start = vid2disp(itrial) => movie id from 1 -39
#             'trial_end'  : set(range(61, 67)),              # trig_trial_end = 60 + currentcondition(itrial)
#             'occlusion_onset': set(range(71,89)),           # trig_occ_onset = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial) => 77-88
#             'task_onset': set(range(91,109)),               # trig_task_onset = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
#             'response': set(range(120, 129)),
#             'movie_restart': set(range(131,149))            # trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial)
#             }

#     occ_matrix = loadmat('/Users/goal0312/Desktop/thesis/7_experiment/occlusion_matrix.mat')['occlusion_onset']

    

