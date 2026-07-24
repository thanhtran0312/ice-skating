## optical flow model

stimdir =      '/Users/goal0312/Desktop/thesis/7_experiment/normal';
output_path =     '/Users/goal0312/Desktop/thesis/model';
vids  = natsortfiles(dir(fullfile(stimdir,'*mp4')));

sdsf    =  50;
width   = 544;
height  = 272;
nframe  = 4200;
nsize   = ceil(width*height/sdsf);
ofs_mag = zeros(size(vids,1),nsize,nframe,1,'uint8'); % 52 x 2960 x 4200 
ofs_dir = zeros(size(vids,1),nsize*2,nframe,'uint8'); % 52 x 5920 x 4200 
for ivid = 1:size(vids,1)
    vid = VideoReader(fullfile(stimdir,vids(ivid).name));
    opticFlow = opticalFlowFarneback;
    of_vid = zeros(nsize,nframe,3,'uint8'); % 2960 x 4200 x 3
    iframe = 0;
    while hasFrame(vid)
        iframe = iframe+1;
        frame = readFrame(vid);
        frame = frame(:,:,1);
        flow = estimateFlow(opticFlow,frame); % struct of 4 output cells, each has 272 x 544 values
        of_frame = cat(3,flow.Magnitude,cos(flow.Orientation),sin(flow.Orientation)); % 272 x 544 x 3
        of_frame = reshape(of_frame,[],size(of_frame,3)); % (272*544) x 3 = 147968 x 3
        of_downsampled = of_frame(1:sdsf:end,:); % 2960 x 3

        for i = 1:size(of_downsampled,2)
            % rescale() rescales min and max of the vector to a range
            % here 1-256.
            % rescale = (input - min(input)) / (max(input) - min(input)) × (maxVal - minVal) + minVal
            of_downsampled(:,i) = uint8(rescale(of_downsampled(:,i),1,2^8)); % 2960 x 3
        end
        of_vid(:,iframe,:) = of_downsampled(:,:);
    end
    of_vid(of_vid(:,1)==0,:,:) = [];
    of_mag = squeeze(of_vid(:,:,1)); % 2960 x 4200
    of_dir = [of_vid(:,:,2);of_vid(:,:,3)]; % concatenate cos & sin 5920 x 4200 

    ofs_mag(ivid,:,:) = of_mag;
    ofs_dir(ivid,:,:) = of_dir;
end

% save("ofs_mag.mat","ofs_mag")
% save("ofs_dir.mat","ofs_dir")
% 
% h = figure; movegui(h);hViewPanel=uipanel(h,'Position',[0 0 1 1],'Title','Farneback Optical Flow Vectors');hPlot=axes(hViewPanel);
% imshow(frame);hold on; plot(flow,'DecimationFactor',[5 5],'ScaleFactor',2,'Parent',hPlot);
