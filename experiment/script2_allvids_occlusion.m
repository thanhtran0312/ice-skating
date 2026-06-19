load('/Users/goal0312/Desktop/thesis/7_experiment/interpolated_2d_coords.mat','coords');

n_vids = size(coords,1);
fps = 50;
win = 0.1;
step = round(win * fps); 
occ_num = 5;
occ_duration = 0.1; 
minIOI = 7;

% padding in the beginning & ending 5s
% from 2 to 3 catch trials 
% practice runs
% on average 

% per 5 frames, how many pixels the pelvis moves
pelvis_x = squeeze((coords(:,12,1,:) + coords(:,13,1,:))/2);
pelvis_y = squeeze((coords(:,12,2,:) + coords(:,13,2,:))/2);

dx = pelvis_x(:,1+step:step:end) - pelvis_x(:,1:step:end-step);
dy = pelvis_y(:,1+step:step:end) - pelvis_y(:,1:step:end-step);
speeds = sqrt(dx.^2 + dy.^2);

% figure;histogram(speeds(:))   

%% start with all frames, then discard moments where occlusions shouldnt occur by masking them to 0

org_framenum = ones(52,4200);

% padding first & last 5 séc
org_framenum(:,1:5*fps) = 0;
org_framenum(:,end-5*fps:end) = 0;

% mask too slow speed = 0
frame_idx = 1:step:4200-step;
for ifile = 1:n_vids % 1:52
    slow_mask = find(speeds(ifile,:) < prctile(speeds(ifile,:),10));
    slow_frame = frame_idx(slow_mask);
    for i = 1:length(slow_frame)
        org_framenum(ifile,slow_frame(i):slow_frame(i)+5) = 0;
    end    
end    

% keep where there are 5 frames in around
occlusion_onset = zeros(n_vids,occ_num);
occ_duration_frames = round(occ_duration * fps);

for ivid = 1:n_vids    
    frame_where_occ_possible = find(org_framenum(ivid,:)==1); % after masking, where are frames left
    total_frames = numel(frame_where_occ_possible) - (occ_num+1)*minIOI*fps - (occ_num*occ_duration*fps); % how many frames left if i want 5 occ with min IOI and 100ms per occ 
    valid_onset = [];
    % the occ can only happen when there are 5 frames in a row
    for i = 1:length(frame_where_occ_possible)-occ_duration_frames
        chunk = frame_where_occ_possible(i:i+occ_duration_frames);
        if chunk(end) - chunk(1) == occ_duration_frames  % all continuous
            valid_onset(end+1) = frame_where_occ_possible(i);
        end
    end
    % gap
    occ_onset = rand(occ_num+1,1); % 6x1 random real numbers 
    occ_onset = occ_onset/sum(occ_onset)*total_frames; % 5 x 1 rescale 6 numbers so they sum to total_frames; cutting total frames to 6 pieces => how much gaps they have from each other
    % convert gap into frame positions
    occ_onset = round(cumsum((occ_onset+minIOI*fps))); % 5 x 1
    occ_onset(end) = [];
    % 
    target_idx = find(valid_onset >= 74*fps & ...
                  valid_onset >= valid_onset(occ_onset(4)) + minIOI*fps);
    occ_onset(5) = target_idx(randi(numel(target_idx)));
    if isempty(target_idx)
        warning('Video %d: no valid onset in 74-79s window', ivid);
        continue
    end


    occlusion_onset(ivid,:) = valid_onset(occ_onset);
end 

save('occlusion_matrix.mat', 'occlusion_onset')

% --- enough displacement
load('/Users/goal0312/Desktop/thesis/7_experiment/interpolated_2d_coords.mat','coords');
coords = permute(coords, [4,1,2,3]);
n_vids  = size(coords,1);
fps     = 50;
win     = 0.1;
step    = round(win * fps);
occ_num      = 5;
occ_duration = 0.1;
minIOI       = 7;

min_disp_px  = 50;
probe_offset = occ_duration*fps;  % always use +100 frames, just ensure it's enough

pelvis_x = squeeze((coords(:,12,1,:) + coords(:,13,1,:))/2);
pelvis_y = squeeze((coords(:,12,2,:) + coords(:,13,2,:))/2);
dx = pelvis_x(:,1+step:step:end) - pelvis_x(:,1:step:end-step);
dy = pelvis_y(:,1+step:step:end) - pelvis_y(:,1:step:end-step);
speeds = sqrt(dx.^2 + dy.^2);

n_frames = size(coords, 4);

%% base mask
org_framenum = ones(n_vids, n_frames);
org_framenum(:, 1:5*fps)       = 0;
org_framenum(:, end-5*fps:end) = 0;
org_framenum(:, end-probe_offset:end) = 0;  % need probe_offset frames after onset

% mask slow frames
frame_idx = 1:step:n_frames-step;
for ifile = 1:n_vids
    slow_mask  = find(speeds(ifile,:) < prctile(speeds(ifile,:), 10));
    slow_frame = frame_idx(slow_mask);
    for i = 1:length(slow_frame)
        org_framenum(ifile, slow_frame(i):slow_frame(i)+5) = 0;
    end
end

%% mask frames where pelvis hasn't moved enough by +probe_offset
for ivid = 1:n_vids
    for f = 1:n_frames - probe_offset
        if org_framenum(ivid, f) == 0, continue; end
        dpx = pelvis_x(ivid, f + probe_offset) - pelvis_x(ivid, f);
        dpy = pelvis_y(ivid, f + probe_offset) - pelvis_y(ivid, f);
        if sqrt(dpx^2 + dpy^2) < min_disp_px
            org_framenum(ivid, f) = 0;
        end
    end
end

%% place occlusions
occ_duration_frames = round(occ_duration * fps);
occlusion_onset = zeros(n_vids, occ_num);

for ivid = 1:n_vids
    frame_where_occ_possible = find(org_framenum(ivid,:) == 1);

    valid_onset = [];
    for i = 1:length(frame_where_occ_possible) - occ_duration_frames
        chunk = frame_where_occ_possible(i:i+occ_duration_frames);
        if chunk(end) - chunk(1) == occ_duration_frames
            valid_onset(end+1) = frame_where_occ_possible(i);
        end
    end

    total_frames = numel(frame_where_occ_possible) - ...
                   (occ_num+1)*minIOI*fps - (occ_num*occ_duration*fps);

    occ_onset = rand(occ_num+1, 1);
    occ_onset = occ_onset / sum(occ_onset) * total_frames;
    occ_onset = round(cumsum(occ_onset + minIOI*fps));
    occ_onset(end) = [];

    target_idx = find(valid_onset >= 74*fps & ...
                      valid_onset >= valid_onset(occ_onset(4)) + minIOI*fps);
    if isempty(target_idx)
        warning('Video %d: no valid onset in late window', ivid);
        continue
    end
    occ_onset(5) = target_idx(randi(numel(target_idx)));

    occlusion_onset(ivid,:) = valid_onset(occ_onset);
end

save('occlusion_matrix.mat', 'occlusion_onset')