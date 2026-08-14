%% 2d coords all cameras
path = pwd;

n_cam = 3;
joints = 17;
dim = 2;
frames = 4200;
n_vids = size(chunks,1);
conf_threshold = 0.5;
clips_to_remove = [1,2,6,17,18,19,20,21,22,23,24,25,47];

for cam = 1:n_cam
    cam_path = fullfile(path,sprintf('cam%d',cam));
    output_dir = fullfile(path,sprintf('cam%d_2d_coords',cam));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    chunks = natsortfiles(dir(fullfile(cam_path,'*h5')));
    coords_52 = zeros(joints,dim,frames,n_vids);
    for chunk = 1:size(chunks,1)
        file = h5read((fullfile(cam_path,chunks(chunk).name)),"/kpts");
        coords = reshape(file, [17,2,4200]);
    
        conf = h5read(fullfile(fullfile(cam_path,chunks(chunk).name)),"/score_kpts");
        
        % clean_keypoints gives back shape (17,2,4200)
        interpolated_keypoints = clean_keypoints(coords, conf, conf_threshold);
        coords_52(:,:,:,chunk) =  interpolated_keypoints;
    end
    coords_39 = coords_52(:,:,:,~ismember(1:size(coords_52,4), clips_to_remove));
    file_name = sprintf('%s/chunk%d',output_dir,chunk);
    h5create(file_name,"/coords_39",size(coords_39))
    h5write(file_name,"/coords_39",coords_39)
end


