% when i created the filtered stimuli, i cropped and resized 
% the frames, so the positions of the skater across frames 
% in the vids now are different from the ones i got from vitpose.

% i have to scale it to track her position for the position task

load('/Users/goal0312/Desktop/thesis/7_experiment/interpolated_2d_coords.mat','coords')
% coords 52 vids x 17 js x 2xy x 4200 frames
%         img_cropped = frame(50:730, 70:1865);

keypoints_orig = coords;
crop_row_start = 50;
crop_col_start = 70;
orig_crop_h = 730 - 50 + 1;   
orig_crop_w = 1865 - 70 + 1;  
cols = 544;
rows = 272;

% your resize target (from your filter grid)
scale_x = cols / orig_crop_w;
scale_y = rows / orig_crop_h;

% recalculate — works on whole matrix at once
keypoints_new = keypoints_orig;
keypoints_new(:,1,:,:) = (keypoints_orig(:,1,:,:) - crop_col_start + 1) * scale_x;
keypoints_new(:,2,:,:) = (keypoints_orig(:,2,:,:) - crop_row_start + 1) * scale_y;

%% save
save('rescaled_coords.mat',"keypoints_new")



%% pick one keypoint from one frame and verify visually
stimdir = '/Users/goal0312/Desktop/thesis/7_experiment/normal';
movies = natsortfiles(dir(fullfile(stimdir,'*mp4')));

frame = rgb2gray(read(VideoReader(fullfile(stimdir, movies(1).name)),4200));

figure;
imshow(frame);
hold on;
% plot keypoint 1 of frame 1
scatter(keypoints_new(:,1,4200,1), keypoints_new(:,2,4200,1), 'r', 'filled');

%%
stimdir = '/Users/goal0312/Desktop/thesis/1_videos/video_1_smaller_chunks';
movies = dir(fullfile(stimdir,'*mp4'));

frame = rgb2gray(readFrame(VideoReader(fullfile(stimdir, movies(3).name))));
img_cropped = frame(50:730, 70:1865);
img_resized = imresize(img_cropped, [rows cols]);

figure;
imshow(img_resized);
hold on;
% plot keypoint 1 of frame 1
scatter(keypoints_new(17,1,4200,1), keypoints_new(17,2,4200,1), 'r', 'filled');

