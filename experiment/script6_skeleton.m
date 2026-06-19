%% this script is a skeleton of the experiment, without MEG, triggers, and output matrix yet.
%% 1.cleanup, debug
close all;
clearvars -except subnum runnum
clc;
sca; % closes experiment



MEG = false;
trackeye = false;

% For debugging purposes this makes experiment transparent
debug = true;
if debug
    PsychDebugWindowConfiguration([], 0.5);
    Screen('Preference', 'SkipSyncTests', 1);%1 = don't do screen sync + size tests
else
    Screen('Preference', 'SkipSyncTests', 0);% 0 = do screen sync + size tests
end
%% 2.parameters: 
% path 
% - set paths
rootdir = '/Users/goal0312/Desktop/thesis';
% rootdir =    '\\tsclient\thesis';
stimdir = fullfile(rootdir,'7_experiment');
addpath(genpath(stimdir));
load(fullfile(stimdir,"rescaled_coords.mat"),"keypoints_new")

% movie, 
fps = 50;
audiovolume = 0;
colors = [27 158 119;217 95 2;117 112 179;231,41,138;102,166,30]/255;% colorblind friendly colors in RGB values between 0 and 1
crosssize = 12;% fixation cross size in pixels 
crosswidth = round(crosssize/3);% fixation cross thickness in pixels
dotsize = crosswidth-2;% fixation cross dot size in pixels
moviesize = 1;
text_size = 30;
photodiodepos = [0 0 50 50];
occ_time = 0.1;
occ_num = 12; % for each run except 2 first practice
dotSize = 20;
pelvis = squeeze(keypoints_new(:,12,:,:) + keypoints_new(:,13,:,:))/2; % for position task 
% task: task parameters: occlusion times, response times, number of occlusions
% visual: cross etc

%% 3.initialize experiment


% - automatically update runnum
experiment_name = 'IceSkating';
defaultinput = {'0','1'}; % because inputdlg() wants strings 
if exist('subnum','var')
    defaultinput{1} = num2str(subnum);
end
if exist('runnum','var')
    defaultinput{2} = num2str(runnum+1);
end

% - get subnum, runnum
prompt = {'\fontsize{14}Subject number','\fontsize{14}Run number ( 1 or 2 = practice )'};
if defaultinput{2} > 1
    dlgtitle = ['Previous run: ' num2str(str2double(defaultinput{2})-1)];
else
    dlgtitle = 'First run for this subject';
end
fieldsize = [1 80; 1 80];
options.Resize='on';
options.WindowStyle='normal';
options.Interpreter='tex';
answer = inputdlg(prompt,dlgtitle,fieldsize,defaultinput,options);
subnum = str2double(answer{1});
runnum = str2double(answer{2});

% save directory, build file
savedir = sprintf('%s%sdata%sSUB%02d',pwd,filesep,filesep,subnum);
if ~exist(savedir,'dir')
    mkdir(savedir);
end
filename = sprintf('ProjectAttention_subject%02d_run%d',subnum,runnum);
Eyefilename = sprintf('IVs%02dr%02d.edf',subnum,runnum);

if exist([savedir filesep filename '.mat'],'file') && runnum > 2 && subnum ~= 99
    error(['\nExperiment stopped because the filename %s.mat already exists!\n\n' ...
        'If this is not a mistake, please first delete or rename the existing file in the folder.\n'...
        'If it is a mistake, please run the script again with a different subject and/or run number'],filename);
end

%% - psychtoolbox window
PsychDefaultSetup(2);

% KEYBOARD MAPPING
KbName('UnifyKeyNames');
space=KbName('SPACE');
esc=KbName('ESCAPE');
right=KbName('RightArrow');
left=KbName('LeftArrow');
up=KbName('UpArrow');
down=KbName('DownArrow');
cal=KbName('c');
val=KbName('v');
congruent=KbName('LeftArrow');
incongruent=KbName('RightArrow');
enter=KbName('RETURN');
RestrictKeysForKbCheck([esc space right left up down cal val enter congruent incongruent]);

screen = max(Screen('Screens'));%1;% in MEG lab it might find several screens and you have to force the correct one, i.e., the projector in the scanner, e.g., 1
PsychImaging('PrepareConfiguration');

% define colors
white = WhiteIndex(screen);
black = BlackIndex(screen);
grey = white / 2;
bg = grey*0.8;

% Open the experiment window
[win, windowRect] = PsychImaging('OpenWindow',  screen, bg);

% Get screen info
% Screen('BlendFunction', win, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');

[screenXpix, screenYpix] = Screen('WindowSize', win);%get screen size
[xCenter, yCenter] = RectCenter(windowRect);% get screen center

% Choose 28 pixel text size:
Screen('TextSize', win, 28);

% For real experiment hide cursor
if ~debug
    HideCursor(screen,0);
end

% Set PTB to top priority so no other running processes on this PC interfere
topPriorityLevel = MaxPriority(win);
Priority(topPriorityLevel);

% Flip to clear
Screen('Flip', win);

%% - load condition matrix, occlusion matrix
load(fullfile(stimdir,'condmat.mat')); % n_subs,n_blocks,n_runs,2
load(fullfile(stimdir,'occlusion_matrix.mat'),'occlusion_onset'); % 52 vids x 5 timepoints of occlusion in frames

% 1=T1N, 2=T1B, 3=T1H
% 4=T2N, 5=T2B, 6=T2H    
% select 6 movies & conds for this subject for this run
vid2disp = condmat(subnum, :, runnum, 1); % 6 x 1 of the 6 videos of this subject - different order for different run but the same vid ids
currentcondition = condmat(subnum, :, runnum, 2); % order of conditions for this run

% in this run, we run 6 blocks/trials
% each vid corresponds to the condition

% vid2disp =          44    11    52    48    38    14
% currentcondition =  4     3     2     1     6     5

% we have 6 trials per run, each is a different condition with corresponding vid

%% which vids to show - inside the trials loop
% movienames = {};
% for itrial = 1:size(condmat,2) % looping through 6 trials
%     if any(currentcondition(itrial) == [1,4])
%             moviename = sprintf('%s%s%s%schunk%d.mp4',stimdir,filesep,'normal',filesep,vid2disp(itrial));
%             movienames{itrial} = moviename;
%     elseif any(currentcondition(itrial) == [2,5])
%             moviename = sprintf('%s%s%s%slow_frequency_filtered_%d.mp4',stimdir,filesep,'low_frequency',filesep, vid2disp(itrial));
%             movienames{itrial} = moviename;
%     elseif any(currentcondition(itrial) == [3,6])
%             moviename = sprintf('%s%s%s%shigh_frequency_filtered%d.mp4',stimdir,filesep,'high_frequency', filesep, vid2disp(itrial));
%             movienames{itrial} = moviename;
%     end 
% end


%% 4.task parameters/which occlusions to show?
% - for **iblock = 1:6**
%     - determine which movie/condition to show
%     - set fixation cross color based on condition
% correct_response = [zeros(1,ceil(occ_num/2)) ones(1,ceil(occ_num/2))];
% correct_response = correct_response(randperm(length(correct_response)));
% occ_count_across_trials = 1; % increment to 12

correct_response = [];
%% 5. general instructions

% outside instructions before any run because if run loop is inside of trial loop
% then for each trial of 1st run => it repeats everything

% instruction for run 1 & run 2
if runnum == 1
        % general
        DrawFormattedText(win,'- Thank you very much for participating in this experiment -','center', yCenter-yCenter*3/6, black);
        DrawFormattedText(win,'- Please read the following instructions carefully and ask the experimenter if anything is unclear -','center', yCenter-yCenter*2/6, black);
    
        DrawFormattedText(win,'- press button to start the instructions -','center', yCenter+yCenter*5/6, black);
    
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        if MEG
            B.getResponse(100,1); % wait for 100 sec for response or return as soon as response is given
        else
            KbStrokeWait;
        end
            % movie
        DrawFormattedText(win,'- You are about to watch 6 different short clips of a skater -','center', yCenter-yCenter*5/6, black);
        DrawFormattedText(win,'- Each clip is repeated 6 times, resulting in 6 experiment runs -','center', yCenter-yCenter*4/6, black);
        DrawFormattedText(win,'- Some of them are shown in a normal format, some are blurred, and some are sharpened. -','center', yCenter-yCenter*3/6, black);
        DrawFormattedText(win,'- Try to stay as relaxed as possible without moving during an 10-minute block -','center', yCenter-yCenter*2/6, black);
        DrawFormattedText(win,'- After each run you will have a little break -','center', yCenter-yCenter*1/6, black);
        DrawFormattedText(win,'- There will always be a fixation cross displayed on top of the movie -','center', yCenter, black);
        DrawFormattedText(win,'- Please always fixate this cross while watching the movie in your periphery -','center', yCenter+yCenter*1/6, black);
        DrawFormattedText(win,'- Therefore, please try to blink as little as possible without being uncomfortable -','center', yCenter+yCenter*3/6, black);
    
        DrawFormattedText(win,'- Inform the experimenter you have read the instructions -','center', yCenter+yCenter*5/6, black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;
    
        % task 
        DrawFormattedText(win,'- For each trial, you will have to perform 1 of 2 possible tasks -','center', yCenter-yCenter*6/7, black);
        DrawFormattedText(win,'- The first task is that you simply pay careful attention to the posture of the skater. -','center', yCenter-yCenter*5/7, black);
        DrawFormattedText(win,'- In this case the fixation cross is always orange.-','center', yCenter-yCenter*4/7, black);
        DrawFormattedText(win,'- At unexpected moments your attention to the movie will be tested: -','center', yCenter-yCenter*3/7, black);
        DrawFormattedText(win,'- The movie screen will turn black for a brief second','center', yCenter-yCenter*2/7, black);
    
        if MEG
            DrawFormattedText(win,'- On the screen, there will be a frame showing the posture of the skater.-','center', yCenter-yCenter*1/7, black);
            DrawFormattedText(win,'- You will need to indicate whether that was the correct posture of the skater-','center', yCenter, black);
            DrawFormattedText(win,'-before the occlusion. (by pressing the green button) -','center', yCenter+yCenter*1/7, black);
            DrawFormattedText(win,'- Or whether it was a different posture (by pressing the red button) -','center', yCenter+yCenter*2/7, black);
        else
            DrawFormattedText(win,'- On the screen, there will be a frame showing the posture of the skater.-','center', yCenter-yCenter*1/7, black);
            DrawFormattedText(win,'-You will need to indicate whether that was the correct posture of the skater-','center', yCenter, black);
            DrawFormattedText(win,'before the occlusion. (by pressing the left arrow) -','center', yCenter+yCenter*1/7, black);
            DrawFormattedText(win,'-  Or whether it was a different posture (by pressing the right arrow) -','center', yCenter+yCenter*2/7, black);
        end
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;

        DrawFormattedText(win,'- The second task is that you simply pay careful attention to the position of the skater. -','center', yCenter-yCenter*5/6, black);
        DrawFormattedText(win,'- In this case the fixation cross is always green.-','center', yCenter-yCenter*4/6, black);
        DrawFormattedText(win,'- At unexpected moments your attention to the movie will be tested: -','center', yCenter-yCenter*3/6, black);
        DrawFormattedText(win,'- The movie screen will turn black for a brief second','center', yCenter-yCenter*2/6, black);
    
        % or not)
        if MEG
            DrawFormattedText(win,'- On the screen, there will be a frame showing the position of the skater.-','center', yCenter-yCenter*1/6, black);
            DrawFormattedText(win,'- You will need to indicate whether that was the correct position of the skater-','center', yCenter, black);
            DrawFormattedText(win,'- before the occlusion. (by pressing the green button) -','center',yCenter+yCenter*1/6,black);
            DrawFormattedText(win,'- Or whether it was a different position (by pressing the red button) -','center', yCenter+yCenter*2/6, black);
        else
            DrawFormattedText(win,'- On the screen, there will be a frame showing the position of the skater.-','center', yCenter-yCenter*1/6, black);
            DrawFormattedText(win,'- You will need to indicate whether that was the correct position of the skater-','center', yCenter, black);
            DrawFormattedText(win,'- before the occlusion. (by pressing the left arrow) -','center',yCenter+yCenter*1/6,black);
            DrawFormattedText(win,'-  Or whether it was a different position (by pressing the right arrow) -','center', yCenter+yCenter*2/6, black);
        end
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;

        DrawFormattedText(win,'Before each trial, you will be informed if you should focus on the posture or position of the skater.-','center', yCenter-yCenter*2/6, black);
        DrawFormattedText(win,'The color of the fixation cross also indicates the task of the trial, with orange for posture and green for position.','center', yCenter-yCenter*1/6, black);

        DrawFormattedText(win,'- You will now first perform a practice run of this task -','center', yCenter+yCenter*1/6, black);
  
        DrawFormattedText(win,'- Inform the experimenter you have read the instructions -','center', yCenter+yCenter*2/6, black);
    
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;

elseif runnum == 2 % 2nd practice

        DrawFormattedText(win,'- You will now first perform a second practice run -','center', yCenter+yCenter*2/6, black);    
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;
        % let subjects know which condition they're in in this run
elseif runnum > 2
        DrawFormattedText(win,'- Now, you will perform the main run. Before each trial, you will be informed if you should focus on-','center', yCenter-yCenter*2/6, black);
        DrawFormattedText(win,'-the posture or position of the skater.-','center', yCenter-yCenter*1/6, black);
        DrawFormattedText(win,'-The color of the fixation cross also indicates the task of the trial-','center', yCenter+yCenter*1/6, black);
        DrawFormattedText(win,'-with orange for posture and green for position.','center', yCenter+yCenter*2/6, black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;
end
    
    % last reminder of fixation and blinking
DrawFormattedText(win,'- Please remember to not move your eyes but keep fixating the cross -','center', yCenter - yCenter*2/4, black);
DrawFormattedText(win,'- Please remember to blink as little as possible without being uncomfortable -','center', yCenter - yCenter*1/4, black);

if MEG
        DrawFormattedText(win,'- When ready, ask the experimenter to start -','center', yCenter, black);
else
        DrawFormattedText(win,'- When ready, press space to start the experiment -','center', yCenter, black);
end
Screen('FillRect', win, [black black black], photodiodepos);
Screen('Flip', win);
KbStrokeWait;
    
%% 6.experiment
%% initialize 
abortit = 0;% check if escape or pause buttons were pressed for movie abortion, initialized at zero
blocking = 1;% Use blocking wait for new frames by default bl; wait til the right frame arrives 
movierate = 1;% Playbackrate defaults to 1;;
% stop when set to 0 during occlusions
% -1 for playing backwards
for itrial = 1:size(condmat,2) % condmat = 30 participants x 6 trials x 6 runs x 2 vid&cond
   %% movie for the condition
    if any(currentcondition(itrial) == [1,4])
            movienames = sprintf('%s%s%s%schunk_%d.mp4',stimdir,filesep,'normal',filesep,vid2disp(itrial));
    elseif any(currentcondition(itrial) == [2,5])
            movienames = sprintf('%s%s%s%slow_frequency_filtered_%d.mp4',stimdir,filesep,'low_frequency',filesep, vid2disp(itrial));
    elseif any(currentcondition(itrial) == [3,6])
            movienames = sprintf('%s%s%s%shigh_frequency_filtered_%d.mp4',stimdir,filesep,'high_frequency', filesep, vid2disp(itrial));
    end 
    %% instruction about the task of this trial 
    if any(currentcondition(itrial) == [1,2,3])
        DrawFormattedText(win,'For this trial, you need to focus on the posture of the skater and ignore the position.','center',yCenter, black);
        colorID = 2;
    elseif any(currentcondition(itrial) == [4,5,6])
        DrawFormattedText(win,'For this trial, you need to focus on the position of the skater and ignore the posture.','center',yCenter, black);
        colorID = 1;
    end
    fix_color = colors(colorID,:);
    colorstr = {'green','orange'};
    colorstr = colorstr{colorID};

    Screen('FillRect', win, [black black black], photodiodepos);
    Screen('Flip', win);
    WaitSecs(2); 

    %countdown at start each trial
    if itrial==1 % count down to the start of the movie in the first trial
        DrawFormattedText(win, ['The movie starts in \n\n ' num2str(3)], 'center', 'center', black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        WaitSecs(1);
        DrawFormattedText(win, ['The movie starts in \n\n ' num2str(2)], 'center', 'center', black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        WaitSecs(1);
        DrawFormattedText(win, ['The movie starts in \n\n ' num2str(1)], 'center', 'center', black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        WaitSecs(1); 
    end

    %% Start movie playback
    % Open movie file and retrieve basic info about movie:
    framecount = 0;
    triggercount = 0;
    t1 = GetSecs;
    occ_count_within_trial = 1; % increment to 2
    % movie gives a handle; imgw,imgh = size of movie; 
    [movie, movieduration, fpsn, imgw, imgh, ~, ~] = Screen('OpenMovie', win, movienames);
    if fps ~= fpsn
        error('Indicated frames per second at parameter initialization at experiment start not same as frames per second as read from movie file')
    end
    
    % movie size - only where there are movements - already done in preprocessing
    % sourceRect = [70 50 1800 725]; 
    % (pixel values change) - 
    % cropw = 1800 - 70;
    % croph = 725 - 50;

    if imgw*moviesize > screenXpix || imgh*moviesize > screenYpix
    % Video frames too big to fit into window, so define size to be window size:
        movierect = CenterRect((screenXpix / imgw) * [0, 0, imgw, imgh], Screen('Rect', win));
    elseif moviesize == 1
        % keep movie the actual size
        movierect = [];
    else
        % multiply size with factor
        movierect = CenterRect(moviesize * [0, 0, imgw, imgh], Screen('Rect', win));
    end

    % start 
    Screen('PlayMovie', movie, movierate, 0, audiovolume);

    % tex = Screen('GetMovieImage', win, movie, blocking);
    % Screen('DrawTexture', win, tex, sourceRect, movierect);
    % Screen('Flip', win);  

    %  choose 2 occlusions out of 5 for this trial
 % choose how many occlusions in this trial
    n_occ = [2,3];
    idx = randi(2);
    n_occ_this_trial = n_occ(idx);

    %  choose 2 occlusions out of 5 for this trial
    ind = randperm(5);
    ind = sort(ind(1:n_occ_this_trial));
    occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind); % 2 frames of occlusion onset
    occ_onset(end+1) = movieduration*fps + 10; % add padding
    notexcount = 0;

    correct_response_for_this_trial = [zeros(1,ceil(n_occ_this_trial/2)) ones(1,floor(n_occ_this_trial/2))];
    correct_response_for_this_trial = correct_response_for_this_trial(randperm(length(correct_response_for_this_trial)));

    correct_response = [correct_response, correct_response_for_this_trial];
   %% b. frame by frame loop to Get next movie frame and draw it

   %% b. frame by frame loop to Get next movie frame and draw it

    while 1
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if (keyIsDown==1 && keyCode(esc))
            % Set the abort flag.
            endtime = Screen('GetMovieTimeIndex', movie);
            break;
        end
        if abs(movierate) > 0
            framecount = framecount + 1;
            tex = Screen('GetMovieImage', win, movie, blocking); % to get texture 

            if tex <0
                Screen('CloseMovie', movie);
                break
            end
            if tex == 0
                notexcount = notexcount + 1; % just checking if this ever happens at all
                WaitSecs('YieldSecs', 0.005);
                continue;
            end
            Screen('DrawTexture', win, tex, [], movierect);
            Screen('DrawLine', win, fix_color, xCenter-crosssize, yCenter, xCenter+crosssize, yCenter, crosswidth);
            Screen('DrawLine', win, fix_color, xCenter, yCenter-crosssize, xCenter, yCenter+crosssize, crosswidth);
            Screen('FillOval', win, black, [xCenter - dotsize, yCenter - dotsize, xCenter + dotsize, yCenter + dotsize], dotsize*2);

            Screen('Flip', win);
            Screen('Close', tex)
        end
        %% MEG & triggers
        %% task
        if framecount == round(occ_onset(occ_count_within_trial))
             occlusion_start = Screen('GetMovieTimeIndex', movie);

             KbReleaseWait;
             movierate = 0;
             Screen('PlayMovie', movie, movierate, 0, audiovolume);
% %% c. at occlusion onset:
%     % - **Stop movie, show black screen**
             Screen('FillRect', win, [black black black], movierect);
             Screen('Flip', win);
             WaitSecs(occ_time);
%     % - **show frame according to condition 123 - posture vs 456 - position
             if any(currentcondition(itrial) == [1 2 3])
                if MEG
                    DrawFormattedText(win, '-Orange button = same posture,','center', yCenter-yrandiCenter*2/6, black);
                    DrawFormattedText(win, '-green button = different posture-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-left arrow = different posture-','center', yCenter-yCenter*1/6, black);
                end
                Screen('Flip',win);
                WaitSecs(1);
                 %    show posture/coherent or incoherent
                if correct_response_for_this_trial(occ_count_within_trial) == 1 % coherent -> show the frame after 5 frames
                    targetTime = (framecount + 5)/fps;
                    Screen('SetMovieTimeIndex',movie,targetTime);
                    Screen('PlayMovie',movie,1,0,audiovolume);
                    tex_probe = Screen('GetMovieImage', win, movie, 1);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0 
                    if currentcondition(itrial) == 1
                        tmp_path = fullfile(mac_dir,'posture_incoherent_normal');
                        frametoshow = sprintf("occ_vid_%d_time_%d_.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 2
                        tmp_path = fullfile(mac_dir,'posture_incoherent_low');
                        frametoshow = sprintf("low_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 3
                        tmp_path = fullfile(mac_dir,'posture_incoherent_high');
                        frametoshow = sprintf("high_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    end
                    img = imread(fullfile(tmp_path, frametoshow));  % read image
                    tex_probe = Screen('MakeTexture', win, img);    % make texture
                    Screen('DrawTexture', win, tex_probe, [], movierect);  % draw it
                    Screen('Close', tex_probe);   
                end
             % else
             elseif any(currentcondition(itrial) == [4 5 6])
                 %    show position/coherent or incoherent
                if MEG
                    DrawFormattedText(win, '-Orange button = same position-','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Green button = different position-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same position-','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Left arrow = different position-','center', yCenter-yCenter*1/6, black);
                end
                Screen('Flip',win);
                WaitSecs(1);

                if correct_response_for_this_trial(occ_count_within_trial) == 1
                    pelvisx = pelvis(vid2disp(itrial), 1, framecount+5);
                    pelvisy = pelvis(vid2disp(itrial), 2, framecount+5);
                    dotRect = CenterRectOnPoint([0 0 dotSize dotSize], pelvisx, pelvisy);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0
                    pelvisx = pelvis(vid2disp(itrial), 1, framecount+50);
                    pelvisy = pelvis(vid2disp(itrial), 2, framecount+50);
                    dotRect = CenterRectOnPoint([0 0 dotSize dotSize], pelvisx, pelvisy); 
                end
                Screen('FillRect', win, bg);       
                Screen('FillOval', win, [0 0 0], dotRect);   
             end
             Screen('Flip', win);
%     % - collect response
             [keyTime, keyCode] = KbStrokeWait();
             keyPressed = KbName(keyCode); % save?
            
%              wait til response/kb pressed
%              check if response was correct or not
%              show feedback
%              store response & reaction time
%              start 1s before occlusion
% 
%     % - show feedback % store
%     % - rewinde to 1s before occlusion & update parameters 
            newtime = occlusion_start - 1;
            framecount = round(occ_onset(occ_count_within_trial)) - fps - 1;
            occ_count_within_trial = occ_count_within_trial + 1;
       % restart the movie
            Screen('SetMovieTimeIndex', movie, newtime);
            movierate = 1;
            Screen('PlayMovie', movie, movierate, 0, audiovolume);  


        end 
    end % while loop still have frames
    Screen('Flip',win);
    
end % for loop through 6 blocks

