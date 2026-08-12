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

