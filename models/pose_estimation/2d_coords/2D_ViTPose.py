### using ViTPose for feature extraction for one vid


from transformers import AutoProcessor, RTDetrForObjectDetection, VitPoseForPoseEstimation
from PIL import Image
import torch, cv2, h5py
import os, glob, sys
import numpy as np
from scipy.linalg import inv
from numpy.linalg import inv
from datetime import datetime
# output: one file per camera, in which each row is per frame
# bounding boxes, box confidence
# 17 keypoints (x,y), keypoint confidence (?)
# fixed shape for framesxfeatures so each frame is a vector of 17 joints x (x,y) => (34,)

# step 1: reading video frames with cv2.VideoCapture() and cap.read()
# step 2: object detection on one frame
# step 3: pose estimation within the bounding box
# step 4: handle edge cases such as NaN



# path
root_dir = '/Volumes/THANH'
input_path = os.path.join(root_dir, 'IceSkating', 'experiment','stimuli')
video_files = glob.glob(os.path.join(input_path, 'video_1_chunks', 'big_chunk_1_small_chunk_1.mp4'))
video_file = video_files[0]

cap = cv2.VideoCapture(video_file)
frames = []
while cap.isOpened():
    ret,frame = cap.read()
    if not ret:
        break
    frames.append(frame)
cap.release()
# Load ViTPose
processor = AutoProcessor.from_pretrained("minghao/vitpose-base")
pose_model = VitPoseForPoseEstimation.from_pretrained("minghao/vitpose-base")

pose_model.eval()  # eval mode
device = "cuda" if torch.cuda.is_available() else "cpu"
pose_model.to(device)

all_keypoints = []

for frame in frames:
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    
    # Detect people (replace with your detector)
    # Example: assume boxes = [[x1,y1,x2,y2], ...]
    boxes = [[0,0,frame.shape[1], frame.shape[0]]]  # full frame if no detector
    
    frame_keypoints = []
    for bbox in boxes:
        x1, y1, x2, y2 = bbox
        crop = frame_rgb[y1:y2, x1:x2]
        image = Image.fromarray(crop)
        
        inputs = processor(images=image, return_tensors="pt").to(device)
        with torch.no_grad():
            outputs = pose_model(**inputs)
        
        # Decode 2D keypoints in pixel coordinates
        keypoints = processor.post_process_pose_estimation(
            outputs, boxes=[bbox], target_sizes=[(frame.shape[0], frame.shape[1])]
        )
        frame_keypoints.append(keypoints[0]["keypoints"].cpu().numpy())
    
    all_keypoints.append(frame_keypoints)

    np.save("video1_keypoints.npy",all_keypoints)
