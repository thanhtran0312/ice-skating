%% filter frames

%% path
load("/Users/goal0312/Desktop/thesis/7_experiment/occlusion_matrix.mat","occlusion_onset");
rootdir = '/Users/goal0312/Desktop/thesis';
% stimdir = fullfile(rootdir, '7_experiment','posture_incoherent_normal');
% % rootdir = '/Users/goal0312/Desktop/thesis';
% % rootdir =    "\\cimec-storage6.cimec.unitn.it\ingdev\projects\THANH";
% % stimdir = fullfile(rootdir, 'IceSkating','experiment','stimuli','video_1_smaller_chunks');
outputdir3= '/Users/goal0312/Desktop/thesis/7_experiment/posture_incoherent_normal';
outputdir1 = '/Users/goal0312/Desktop/thesis/7_experiment/posture_incoherent_low';
outputdir2 = '/Users/goal0312/Desktop/thesis/7_experiment/posture_incoherent_high';

input_1 = '/Users/goal0312/Desktop/thesis/7_experiment/low_frequency';
input_2 = '/Users/goal0312/Desktop/thesis/7_experiment/high_frequency';
input_3 = '/Users/goal0312/Desktop/thesis/7_experiment/normal';

low_vids = dir(fullfile(input_1,'*mp4'));
names1 = {low_vids.name};
[names1,idx1] = natsortfiles(names1);
low_vids = low_vids(idx1);

high_vids = dir(fullfile(input_2,'*mp4'));
names2 = {high_vids.name};
[names2,idx2] = natsortfiles(names2);
high_vids = high_vids(idx2);

norm_vids = dir(fullfile(input_3,'*mp4'));
names3 = {norm_vids.name};
[names3,idx3] = natsortfiles(names3);
norm_vids = norm_vids(idx3);

occ_time = 0.1*50;

for ivid = 1:39
    for iocc = 1:5
        vid = incongruent_vid(ivid,iocc);
        frame = incongruent_frame(ivid,iocc) + occ_time;

        vid1 = VideoReader(fullfile(input_1,low_vids(vid).name));
        readframe1 = read(vid1,frame);
        outputname1 = sprintf("low_occ_vid_%d_time_%d.png",ivid,iocc);
        imwrite(readframe1,fullfile(outputdir1,outputname1));

        vid2 = VideoReader(fullfile(input_2,high_vids(vid).name));
        readframe2 = read(vid2,frame);
        outputname2 = sprintf("high_occ_vid_%d_time_%d.png",ivid,iocc);
        imwrite(readframe2,fullfile(outputdir2,outputname2));


        vid3 = VideoReader(fullfile(input_3,norm_vids(vid).name));
        readframe3 = read(vid3,frame);
        outputname3 = sprintf("norm_occ_vid_%d_time_%d.png",ivid,iocc);
        imwrite(readframe3,fullfile(outputdir3,outputname3));

    end
end

% ____from incongruent_stimuli.mat to incongruent_vid
% incongruent_frame = incongruent(1,1).frame;
% incongruent_vid = incongruent(1,1).vid;