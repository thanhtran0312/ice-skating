## pixelwise model


input_path =      '/Users/goal0312/Desktop/thesis/7_experiment/normal';
output_path =     '/Users/goal0312/Desktop/thesis/model';
vids  = natsortfiles(dir(fullfile(input_path,'*mp4')));

sdsf  = 50;
sigma = 2.5;
pixelwise_lum = zeros(52,2960,4200,'uint8');
for ivid =  1:52
    vid = VideoReader(fullfile(input_path,vids(ivid).name));
    nframe = vid.NumFrame;
    nsize = floor(vid.Width*vid.Height/sdsf);
    downsamples = zeros(nsize,nframe,'uint8'); % 2959 x 4200
    iframe = 0;
    while hasFrame(vid)
        iframe = iframe + 1;
        frame = readFrame(vid);
        frame = frame(:,:,1); % take 1 color channel 272 x 544
        smoothed_frame = imgaussfilt(frame,sigma);
        smoothed_frame = reshape(smoothed_frame,[],1); % 147968
        downsampled_frame = smoothed_frame(1:sdsf:end);
        downsamples(1:length(downsampled_frame),iframe) = downsampled_frame;
    end
    downsamples(downsamples(:,1)==0,:) = [];
    pixelwise_lum(ivid,:,:) = downsamples(:,:);
end

name = sprintf('pixelwise_lum.mat');
file = fullfile(output_path,name);
save(file,"pixelwise_lum")

