%% path
rootdir = '/Users/goal0312/Desktop/thesis';
stimdir = fullfile(rootdir, '1_videos','video_1_smaller_chunks');
output_lsf = '/Users/goal0312/Desktop/thesis/7_experiment/low_frequency';
output_hsf = '/Users/goal0312/Desktop/thesis/7_experiment/high_frequency';
output_normal = '/Users/goal0312/Desktop/thesis/7_experiment/normal';

movies = dir(fullfile(stimdir,'*mp4'));
names = {movies.name};
[names,idx] = natsortfiles(names);
movies = movies(idx);

va_h = 5;
va_w = 10;
dist = 1000;
screen_w = 410;
resolution = 1280;
% sample 
[rows, cols] = visangle2stimsize(va_h, va_w, dist, screen_w, resolution); %visual angle x,y,dist,width,resolution

% MPEG-4 expects dimensions (not in pixels but square tiles that the encoder processes) to be divisible by 16 to avoid edge cases
rows = floor(rows / 16) * 16;
cols = floor(cols / 16) * 16;

%% PPD and cutoffs
% ppd = pixels per degree / horizontal size of the screen in degrees of
% visual angle = 2 x arctan(physical size / (2 x distance)) with physical
% size = 41 cm and distance = 100 cm
screenwidth = 1280;
va = 23.2; % of the whole screen
ppd = screenwidth/va;            % 55.2 px/degree
cpd_h = 5;
cpd_l = 2;

imw = cols;
cycles_per_pixel_h = cpd_h / ppd; 
cycles_per_image_h = cycles_per_pixel_h * imw; 

cycles_per_pixel_l = cpd_l / ppd; 
cycles_per_image_l = cycles_per_pixel_l * imw;   

% butterworth masking
% to make the grid size 552x276
[x,y] = meshgrid(-(cols/2):(cols/2)-1, -(rows/2):(rows/2)-1);
% distance from center
z = sqrt(x.^2 + y.^2);

b_l=1./(1+(z./cycles_per_image_l).^8);
% high
b_h=1./(1+(z./cycles_per_image_h).^8);
h =   1-b_h;
%% filter all movies
for i = 1:length(movies)
    movie = VideoReader(fullfile(stimdir, movies(i).name));
    outputname_lsf = sprintf('low_frequency_filtered_%d.mp4', i);
    outputname_hsf = sprintf('high_frequency_filtered_%d.mp4', i);
    outputname_normal = sprintf('chunk_%d.mp4', i);

    writer_lsf = VideoWriter(fullfile(output_lsf, outputname_lsf), 'MPEG-4');
    writer_hsf = VideoWriter(fullfile(output_hsf, outputname_hsf), 'MPEG-4');
    writer_normal = VideoWriter(fullfile(output_normal, outputname_normal), 'MPEG-4');

    writer_lsf.FrameRate = 50;
    writer_hsf.FrameRate = 50;
    writer_normal.FrameRate = 50;

    writer_normal.Quality = 95;
    writer_lsf.Quality = 95;
    writer_hsf.Quality = 95;
    open(writer_lsf)
    open(writer_hsf)
    open(writer_normal)

    frame_count = 0;

    while hasFrame(movie)
        frame = rgb2gray(readFrame(movie));
        frame_count = frame_count + 1;

        % crop and resize
        img_cropped = frame(50:730, 70:1865);
        img_resized = imresize(img_cropped, [rows cols]);

        % % FFT and filter
        cf = fftshift(fft2(double(img_resized))); 

        cfl_l=cf.*b_l;
        cfl_h=cf.*h;

        cfli_l=ifft2(ifftshift(cfl_l));
        cfli_h=ifft2(ifftshift(cfl_h));

        img_lsf = uint8(min(max(real(cfli_l),       0), 255));
        img_hsf = uint8(min(max(real(cfli_h) + 128, 0), 255));
        writeVideo(writer_lsf,    repmat(img_lsf, [1 1 3]));
        writeVideo(writer_hsf,    repmat(img_hsf, [1 1 3]));
        writeVideo(writer_normal, repmat(uint8(img_resized), [1 1 3]));


    end    
    close(writer_lsf);
    close(writer_hsf);
    close(writer_normal);
end


% ---check if cross is in the middle of the frame
% frame = frame(50:730,70:1865)
% centroid_x = size(resized,1)/2; % 351
% centroid_y = size(resized,2)/2; % 899
% figure;
% hold on
% imshow(resized)
% plot(centroid_y,centroid_x,'r.','MarkerSize',20);
% hold off;

% ----ccheck frequenncy content
%% Check frequency content of a filtered frame

figure('Name','Frequency content check');

frames_to_check = {img_resized, img_lsf, img_hsf};
titles = {'Original', 'LSF (low-pass)', 'HSF (high-pass)'};

for k = 1:3
    img = double(frames_to_check{k});
    
    % FFT magnitude spectrum (log scale for visibility)
    cf = fftshift(fft2(img));
    mag = log(1 + abs(cf));
    
    % Radial average: power as function of spatial frequency
    [rows_f, cols_f] = size(img);
    [xg, yg] = meshgrid(-(cols_f/2):(cols_f/2)-1, -(rows_f/2):(rows_f/2)-1);
    r = sqrt(xg.^2 + yg.^2);
    r_int = round(r);                      % bin by integer radius
    max_r = floor(min(rows_f, cols_f)/2);
    radii  = 0:max_r;
    power  = zeros(size(radii));
    for ri = radii
        mask = (r_int == ri);
        power(ri+1) = mean(abs(cf(mask)).^2);
    end
    
    % Convert radius (cycles/image) to cycles/degree
    freq_cpd = radii * (ppd / imw);   % imw = cols
    
    subplot(2,3,k)
    imagesc(mag); colormap gray; axis image off;
    title([titles{k} ' – 2D spectrum']);
    
    subplot(2,3,k+3)
    plot(freq_cpd, 10*log10(power));
    xlabel('Spatial frequency (cpd)');
    ylabel('Power (dB)');
    title([titles{k} ' – radial power']);
    xline(cpd_l, 'r--', sprintf('%d cpd (low cutoff)', cpd_l));
    xline(cpd_h, 'b--', sprintf('%d cpd (high cutoff)', cpd_h));
    xlim([0 20]);
    grid on;
end