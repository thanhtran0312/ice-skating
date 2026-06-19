% exclude vids 1,2,6,17,18,19,20,21,22,23,24,25,47
stimdir =     '/Users/goal0312/Desktop/2d_interpolation';
coords = h5read(fullfile(stimdir,"coords_52.h5"),'/coords_52');

idx_vids_excluded = [1,2,6,17,18,19,20,21,22,23,24,25,47];
coords(:,:,:,idx_vids_excluded) = [];

save('interpolated_2d_coords.mat', "coords")

%-------change names
stimdir =  '/Users/goal0312/Desktop/thesis/7_experiment';
normal_vids = natsortfiles(dir(fullfile(stimdir,'normal','*mp4')));

hf_vids = natsortfiles(dir(fullfile(stimdir,'high_frequency','*mp4')));

lf_vids = natsortfiles(dir(fullfile(stimdir,'low_frequency','*mp4')));


for i = 1:size(normal_vids, 1)
    movefile(fullfile(normal_vids(i).folder, normal_vids(i).name), ...
             fullfile(normal_vids(i).folder, sprintf('chunk_%d.mp4', i)));

    movefile(fullfile(hf_vids(i).folder, hf_vids(i).name), ...
             fullfile(hf_vids(i).folder, sprintf('high_frequency_filtered_%d.mp4', i)));

    movefile(fullfile(lf_vids(i).folder, lf_vids(i).name), ...
             fullfile(lf_vids(i).folder, sprintf('low_frequency_filtered_%d.mp4', i)));
end
