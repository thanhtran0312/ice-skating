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
    PsychDebugWindowConfiguration([], 1);
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
fb_text_size = 100;% just feedback symbol size
fb_text_time = 0.3;% how long feedback symbol is shown in seconds
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

%% 4.task parameters/which occlusions to show?
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
        DrawFormattedText(win,'- Some of them are shown in a normal format, some are blurred, and some are sharpened. -','center', yCenter-yCenter*4/6, black);
        DrawFormattedText(win,'- Try to stay as relaxed as possible without moving during an 10-minute block -','center', yCenter-yCenter*3/6, black);
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
abortit = 0;
blocking = 1;
movierate = 1;

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
    if itrial==1
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
    framecount = 0;
    triggercount = 0;
    t1 = GetSecs;
    occ_count_within_trial = 1;

    [movie, movieduration, fpsn, imgw, imgh, ~, ~] = Screen('OpenMovie', win, movienames);
    if fps ~= fpsn
        error('Indicated frames per second at parameter initialization at experiment start not same as frames per second as read from movie file')
    end
    
    % compute movierect
    if imgw*moviesize > screenXpix || imgh*moviesize > screenYpix
        movierect = CenterRect((screenXpix / imgw) * [0, 0, imgw, imgh], Screen('Rect', win));
    elseif moviesize == 1
        movierect = [];
    else
        movierect = CenterRect(moviesize * [0, 0, imgw, imgh], Screen('Rect', win));
    end

    % Compute screen-space mapping for pelvis coordinates
    % pelvis coords are in video frame space (imgw x imgh).
    % We need to map them to screen space using movierect.
    if isempty(movierect)
        % movie displayed at actual size, centered
        movie_left    = xCenter - imgw/2;
        movie_top     = yCenter - imgh/2;
        movie_scale_x = 1;
        movie_scale_y = 1;
    else
        movie_left    = movierect(1);
        movie_top     = movierect(2);
        movie_scale_x = (movierect(3) - movierect(1)) / imgw;
        movie_scale_y = (movierect(4) - movierect(2)) / imgh;
    end

    Screen('PlayMovie', movie, movierate, 0, audiovolume);

    % choose how many occlusions in this trial
    n_occ = [2,3];
    idx = randi(2);
    n_occ_this_trial = n_occ(idx);

    % choose which occlusions out of 5 for this trial
    ind = randperm(5);
    ind = sort(ind(1:n_occ_this_trial));
    occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind);
    occ_onset(end+1) = movieduration*fps + 10; % padding
    notexcount = 0;

    correct_response_for_this_trial = [zeros(1,ceil(n_occ_this_trial/2)) ones(1,floor(n_occ_this_trial/2))];
    correct_response_for_this_trial = correct_response_for_this_trial(randperm(length(correct_response_for_this_trial)));

    correct_response = [correct_response, correct_response_for_this_trial];

   %% frame by frame loop
    while 1
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if (keyIsDown==1 && keyCode(esc))
            endtime = Screen('GetMovieTimeIndex', movie);
            break;
        end

        if abs(movierate) > 0
            framecount = framecount + 1;
            tex = Screen('GetMovieImage', win, movie, blocking);

            if tex < 0
                Screen('CloseMovie', movie);
                break
            end
            if tex == 0
                notexcount = notexcount + 1;
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

        %% task - occlusion
        if framecount == round(occ_onset(occ_count_within_trial))
             occlusion_start = Screen('GetMovieTimeIndex', movie);

             KbReleaseWait;
             movierate = 0;
             Screen('PlayMovie', movie, movierate, 0, audiovolume);

             % show black screen for occ_time
             Screen('FillRect', win, bg, movierect);
             Screen('Flip', win);
             WaitSecs(occ_time);

             %% posture task (conditions 1,2,3)
             if any(currentcondition(itrial) == [1 2 3])
                if MEG
                    DrawFormattedText(win, '-Orange button = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-green button = different posture-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-left arrow = different posture-','center', yCenter-yCenter*1/6, black);
                end
                Screen('Flip',win,bg);
                WaitSecs(1);

                % show posture frame: coherent or incoherent
                if correct_response_for_this_trial(occ_count_within_trial) == 1 % coherent -> frame 5 frames later
                    targetTime = (framecount + 5)/fps;
                    Screen('SetMovieTimeIndex', movie, targetTime);
                    Screen('PlayMovie', movie, 1, 0, audiovolume);
                    tex_probe = Screen('GetMovieImage', win, movie, 1);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0 % incoherent -> load saved image
                    if currentcondition(itrial) == 1
                        tmp_path = fullfile(stimdir,'posture_incoherent_normal');
                        frametoshow = sprintf("norm_occ_vid_%d_time_%d_.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 2
                        tmp_path = fullfile(stimdir,'posture_incoherent_low');
                        frametoshow = sprintf("low_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 3
                        tmp_path = fullfile(stimdir,'posture_incoherent_high');
                        frametoshow = sprintf("high_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    end
                    img = imread(fullfile(tmp_path, frametoshow));
                    tex_probe = Screen('MakeTexture', win, img);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);
                end

             %% position task (conditions 4,5,6)
             elseif any(currentcondition(itrial) == [4 5 6])
                if MEG
                    DrawFormattedText(win, '-Orange button = same-','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Green button = different position-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same position-','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Left arrow = different position-','center', yCenter-yCenter*1/6, black);
                end
                Screen('Flip',win,bg,movierect);
                WaitSecs(1);

                % get pelvis position in video space
                if correct_response_for_this_trial(occ_count_within_trial) == 1 % coherent -> 5 frames later
                    pelvisx_vid = pelvis(vid2disp(itrial), 1, framecount+5);
                    pelvisy_vid = pelvis(vid2disp(itrial), 2, framecount+5);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0 % incoherent -> 50 frames later
                    pelvisx_vid = pelvis(vid2disp(itrial), 1, framecount+50);
                    pelvisy_vid = pelvis(vid2disp(itrial), 2, framecount+50);
                end

                % map from video frame space -> screen space
                
                pelvisx_screen = movie_left + pelvisx_vid * movie_scale_x;
                pelvisy_screen = movie_top  + pelvisy_vid * movie_scale_y;

                dotRect = CenterRectOnPoint([0 0 dotSize dotSize], pelvisx_screen, pelvisy_screen);
                rect = CenterRect([0, 0, imgw, imgh], windowRect);

                Screen('FillRect', win, [1 1 1], rect);
                Screen('FillOval', win, [0 0 0], dotRect);
             end

             Screen('Flip', win);

             % collect response
             start_resp_time = GetSecs;
             respMade = false;

%     % - collect response
%              wait til response/kb pressed
%              check if response was correct or not
%              show feedback
%              store response & reaction time
             while ~respMade 

                % get response
                if ~MEG
                    [keyIsDown, time_resp, keyCode] = KbCheck;
                    if keyIsDown==1 && (keyCode(congruent) || keyCode(incongruent))
                        respMade = true;
                        if keyCode(congruent)
                            given_response = 1;
                        else% if keyCode(incongruent)
                            given_response = 0;
                        end
                    end
                else%if MEG
                    [respCode, ~, time_resp] = B.getResponse(max_resp_time + 0.005,1); % wait for response time length (max_response_time + 0.005, just to make sure it wouldn't enter the while loop again), return as soon as response is given
                    if (respCode == 99 || respCode == 100)   % Bitsi returns response = 0 and rt = timeout when no response is made
                        respMade = true;
                        given_response = 100 - respCode;
                    end
                end

             end% while loop% 
             if respMade

                Screen('TextSize', win, fb_text_size);% set text size for feedback symbols
                Screen('FillRect', win, bg, movierect);

                % check if response was correct or not      
                if given_response == correct_response_for_this_trial(occ_count_within_trial)
                    DrawFormattedText(win, 'Correct', 'center', 'center', colors(1,:));
                else
                    DrawFormattedText(win, 'Incorrect', 'center', 'center', colors(2,:));
                end

                % show feedback
                Screen('Flip', win);
                Screen('TextSize', win, text_size);% set back to regular text size

                WaitSecs(1);
             end
             % rewind to 1s before occlusion & update parameters
             newtime = occlusion_start - 1;
             framecount = round(occ_onset(occ_count_within_trial)) - fps - 1;
             occ_count_within_trial = occ_count_within_trial + 1;

             % restart the movie
             Screen('SetMovieTimeIndex', movie, newtime);
             movierate = 1;
             Screen('PlayMovie', movie, movierate, 0, audiovolume);
        end 

    end % while loop

    Screen('Flip', win, bg, movierect);
    
end % for loop through 6 trials      