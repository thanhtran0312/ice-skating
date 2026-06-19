load('/Users/goal0312/Desktop/thesis/7_experiment/interpolated_2d_coords.mat','coords')
% coords 52 x 17 x 2 x 4200
n_vids = size(coords,1);
normalized_coords = zeros(n_vids,17,2,4200);
for ivid = 1:n_vids
    for iframe = 1:4200
        normalized_coord = standardize_pose(squeeze(coords(ivid,:,:,iframe)));
        normalized_coords(ivid,:,:,iframe) = normalized_coord;
    end
end

save('normalized_coords.mat',"normalized_coords")