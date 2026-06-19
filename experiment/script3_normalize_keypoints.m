load('/Users/goal0312/Desktop/thesis/4_VITPOSE_2d/interpolated_2d_coords.mat','coords');

% normalized keypoints should be used to compute similarity between postures 

coords_copy = coords;
% n_videos = size(coords,1);
% frames = size(coords,4);

left_hip_x = squeeze(coords(:,12,1,:));
left_hip_y = squeeze(coords(:,12,2,:));
right_hip_x = squeeze(coords(:,13,1,:));
right_hip_y = squeeze(coords(:,13,2,:));
pelvis_x = (left_hip_x+right_hip_x)/2;
pelvis_y = (left_hip_y+right_hip_y)/2;
% pelvis = permute(repmat(cat(3,pelvis_x,pelvis_y),[1,1,1,17]), [1,4,3,2]);
% repmat not necessary because of broadcasting
pelvis = permute(cat(3,pelvis_x,pelvis_y), [1,4,3,2]); % 52 vids x 1 joint - pelvis x 2 xy x 4200 frames

% or
pelvis_vectorized = (coords(:,12,:,:) + coords(:,13,:,:))/2;

normalized_coords = coords - pelvis;
save('normalized_coords.mat','normalized_coords')