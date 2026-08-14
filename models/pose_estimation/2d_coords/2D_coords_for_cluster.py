## ViTPose for all vids, run on the cluster

import torch, cv2, h5py
import os, glob, sys, natsort
import numpy as np
from scipy.linalg import inv
from numpy.linalg import inv
from PIL import Image

# download models
from transformers import (
        AutoProcessor, 
        RTDetrForObjectDetection, 
        VitPoseForPoseEstimation,
)
from transformers import AutoImageProcessor, AutoModelForObjectDetection

device = "cuda" if torch.cuda.is_available() else "cpu"

person_processor = AutoImageProcessor.from_pretrained("PekingU/rtdetr_r50vd_coco_o365")
person_model = AutoModelForObjectDetection.from_pretrained("PekingU/rtdetr_r50vd_coco_o365").to(device)

pose_processor = AutoImageProcessor.from_pretrained("danelcsb/vitpose-base-simple")
pose_model = VitPoseForPoseEstimation.from_pretrained("danelcsb/vitpose-base-simple").to(device)


# helper function
def fill_in_res(res: list, key: str, size: tuple, top_k: int, box=0): 
    if box == 0:
        data = [res[i][key].cpu().numpy() for i in range(len(res))]
    else:
        data = [np.array([i.cpu().numpy()]) for i in res["scores"]]
    if len(data) < top_k: # fills in if there are less than 5 pers
        fill_in = [np.full(size, np.nan) for _ in range(int(top_k - len(data)))]
        data.extend(fill_in)
    
    data = data[0:1]
    data = np.stack(data, axis=-1) # stacks them along the last dimension
    data = data.flatten(order='F') # vectorizes it fortran style (column-major like matlab)
    return data 

# path
root_dir = '/mnt/storage/tier2/ingdev/projects/THANH'
input_path = os.path.join(root_dir, 'IceSkating', 'experiment','stimuli','video_2_smaller_chunks')
video_files = natsort.natsorted(glob.glob(os.path.join(input_path, '*.mp4')))

output_dir = os.path.join(root_dir, 'IceSkating', '2d_coords','cam2')

# dict to save points, boxes, and scores
feats = {
    "kpts" : [],
    "boxes" : [], 
    "score_boxes" : [],
    "score_kpts" : [], 
}

i = int(sys.argv[1])
path2vid = video_files[i]
feats = {
                    "kpts" : [],
                    "boxes" : [], 
                    "score_boxes" : [],
                    "score_kpts" : [], 
                    }
cap = cv2.VideoCapture(path2vid)
while True:
                    ret,frame = cap.read()
                    if not ret:
                            break

                    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    inputs = person_processor(frame_rgb, return_tensors="pt").to(device)

                    # detect people
                    with torch.no_grad():
                            outputs = person_model(**inputs) # performs object detection on the input
                    # box detection
                    result = person_processor.post_process_object_detection(
                    outputs, target_sizes=torch.tensor([(frame_rgb.shape[0], frame_rgb.shape[1])]), threshold=0.3 # converts raw model outputs into interpretable bounding box predictions 
                    )[0]
                    person_boxes = result["boxes"][result["labels"] == 0] # index only the boxes associated with label 0 (person) in COCO class labels
                    if person_boxes.numel() == 0: # predef dimensionalities, sorry for hardcoding
                            person_boxes_store = np.full((4,), np.nan)
                            score_boxes_store = np.full((1,), np.nan)
                            kpts_store = np.full((34,), np.nan)
                            kpts_scores_store = np.full((17,), np.nan)
                            # print(datetime.now().strftime("%H:%M:%S")," skipping frame", count, "because people weren't detected", flush=True)
                    else:
                            score_boxes = result["scores"][result["labels"] == 0]
                            score_boxes = score_boxes.cpu().numpy()
                            # score_boxes_store = fill_in_res(person_boxes, "scores", (1, 1), 5) 
                    # feats["score_boxes"].append(score_boxes_store)
                    # converts boxes from VOC format: (x1, y1, x2, y2) to COCO format: N pers detected x 4 -> 4 cols are => (x, y, width, height)
                            person_boxes[:, 2] = person_boxes[:, 2] - person_boxes[:, 0] 
                            person_boxes[:, 3] = person_boxes[:, 3] - person_boxes[:, 1] 
                    
                            # 6 - preprocess for kpt detection
                            inputs = pose_processor([frame_rgb], boxes=[person_boxes], return_tensors="pt").to(device) # processes the original image using the bounding boxes -> ViTPose expects tightly cropped pics
                    # inputs is a dict like type with "pixels_value" as only entry. It is a tensor [Batch, Channels, Height, Width] -> Batch is the number of people detected
                            with torch.no_grad():
                                    outputs = pose_model(**inputs) # runs ViTPose
                            pose_results = pose_processor.post_process_pose_estimation(outputs, boxes=[person_boxes])[0]
                            kpts_store = fill_in_res(pose_results, "keypoints", (17,2), 1)
                            kpts_scores_store = fill_in_res(pose_results, "scores", (17), 1)
                            person_boxes_store = fill_in_res(pose_results, "bbox", (4), 1) 
                            score_boxes_store = fill_in_res(result, "scores", (1), 1, box=1)
                    feats["boxes"].append(person_boxes_store)
                    feats["kpts"].append(kpts_store)
                    feats["score_kpts"].append(kpts_scores_store)
                    feats["score_boxes"].append(score_boxes_store)
with h5py.File(os.path.join(output_dir, f"cam2_feats_chunk{i+1}.h5"), "w") as f:
                    for key, value in feats.items():
                            f.create_dataset(key, data=value, compression="gzip")
cap.release()
print(f"Processing video {i}: {path2vid}", flush=True)
