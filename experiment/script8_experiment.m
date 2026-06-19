      %% this script is a skeleton of the experiment, MEG, triggers, and output matrix yet.
%% 1.cleanup, debug
close all;
clearvars -except subnum runnum
clc;
sca; % closes experiment

  
MEG = false;
trackeye = false;
  
% F or debugging purposes this makes experiment transparent
debug = true;
if debug
    PsychDebugWindowConfiguration([], 1       );
    Screen('Preference', 'SkipSyncTests', 1);%1 = don't do screen sync + size tests
else
    Screen('Preference', 'SkipSyncTests', 0);% 0 = do screen sync + size tests
end
%% 2.parameters: 
% path 
rootdir = '/Users/goal0312/Desktop/thesis';  
stimdir = fullfile(rootdir,'7_experiment');
addpath(genpath(stimdir));
load(fullfile(stimdir,"rescaled_coords.mat"),"keypoints_new")
     
% movie, 
fps = 50;
audiovolume = 0;
colors = [27 158 119;217 95 2;117 112 179;231,41,138;102,166,30]/255;% colorblind friendly colors in RGB values between 0 and 1
crosssize = 9;% fixation cross size in pixels 
crosswidth = round(crosssize/3);% fixation cross thickness in pixels
dotsize = crosswidth;% fixation cross dot size in pixels
moviesize = 1;
text_size = 30;
photodiodepos = [0 0 50 50];
occ_time = 0.1;
occ_num = 12; % for each run except 2 first practice
dotSize = 15; % position task
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
incongruent=KbName('LeftArrow');
congruent=KbName('RightArrow');
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

%% output matrix
% save correct_response,runnum,video,condition per run/block,
% trigger,frame, how many occlusion (idx) in each run, where occ_onset,
% correct_response, given response

% every time an occlusion happens, send a trigger 6*(2~3) =  12~18
% the rest ~ 84*8 / 5 = 130

maxtrignum = 150; % 6 trials * ~15 triggers each = safe upper bound
output = struct(...
    'subnum',        num2cell(repmat(subnum,  1, maxtrignum)), ...
    'runnum',        num2cell(repmat(runnum,  1, maxtrignum)), ...
    'trial',         num2cell(NaN(1, maxtrignum)), ...  % filled per trigger
    'video',         num2cell(NaN(1, maxtrignum)), ...  % filled per trigger
    'condition',     num2cell(NaN(1, maxtrignum)), ...  % filled per trigger
    'trigger',       num2cell(NaN(1, maxtrignum)), ...
    'task_num',      num2cell(NaN(1, maxtrignum)), ...
    'task_onset',    num2cell(NaN(1, maxtrignum)), ...
    'correct_response', num2cell(NaN(1, maxtrignum)), ...
    'given_response',   num2cell(NaN(1, maxtrignum)), ...
    'RT',            num2cell(NaN(1, maxtrignum)));
% output = struct('subnum',num2cell(repmat(subnum,1,maxtrignum)),...
%     'runnum',num2cell(repmat(runnum,1,maxtrignum)),...
%     % 'trial',num2cell(repmat(runnum,1,maxtrignum)),...
%     % 'video',num2cell(repmat(vid2disp,1,maxtrignum)),... 
%     % 'condition',num2cell(repmat(currentcondition,1,maxtrignum)),...
%     'trigger',num2cell(NaN(1,maxtrignum)),...
%     % 'frame',num2cell(1:fps*ITI:maxtrignum*fps*ITI),...
%     % 'movietime',num2cell(NaN(1,maxtrignum)),...
%     'task_num',num2cell(NaN(1,maxtrignum)),...
%     'task_onset',num2cell(NaN(1,maxtrignum)),...
%     'correct_response',num2cell(NaN(1,maxtrignum)),...
%     'given_response',num2cell(NaN(1,maxtrignum)));


%% 4.task parameters/which occlusions to show?
% correct_response = [zeros(1,ceil(occ_num/2)) ones(1,ceil(occ_num/2))];
% correct_response = correct_response(randperm(length(correct_response)));
% occ_count_across_trials = 1; % increment to 12

correct_response = [];
given_response = [];
%% initialize MEG & eyetrack
if trackeye
    % INITIALIZE EYELINK
    % It is better not to send too many Eyelink commands to the eye-tracker in a row. For this reason, between them, we wait for a short time, here defined.
    elk.wait = 0.01;
    
    % This code initializes the connection with the eyelink: if something fails, it exit program with error
    if EyelinkInit()~= 1;
        error('Eyelink disconnected !!!');
    end;
    
    % We need to provide Eyelink with details about the graphics environment and perform some initializations. The initialization information is returned in a
    % structure that also contains useful defaults and control codes (e.g. tracker state bit and Eyelink key values). The structure, moreover, acts as an handle
    % for subsequent commands, like "windowHandle" for Psychtoolbox.
    elk.el = EyelinkInitDefaults(window);
    
    % Here we create the name for the eyelink datafile. Data gathered from the eye tracker are saved on the eye-tracking PC in a file. Data from all users are
    % saved in the same folder and the folder is routinely cleaned up without any advice. So, be sure to copy your data after the experiment and choose an
    % unique name for the datafile (containing date/time, subject number etc...). It has to be less than 8 characters long.
    %
    if subject_num < 10
        Eyefilename = ['Aice0' num2str(subject_num) 'b' num2str(block)];
    else
        Eyefilename = ['Aice' num2str(subject_num) 'b' num2str(block)];
    end
    Eyefilename = [Eyefilename '.edf'];
    elk.edfFile = sprintf(Eyefilename);		% Create file name
    Eyelink('Openfile', elk.edfFile);									% Open the file to the eye-tracker
    
    % Writing a short preamble to the file helps if the name became not that informative ;-)
    Eyelink('command', sprintf('add_file_preamble_text ''Ingmar de Vries Project Unpredict: subject %d ; block %d ; practice %d ; time %s''', subject_num, block, practice, datestr(now, 'YYYYmmddhhMM')));
    
    % Setting the eye-tracker so as to record GAZE of  LEFT and RIGHT eyes, together with pupil AREA
    Eyelink('Command', 'link_sample_data = LEFT,RIGHT,GAZE,AREA');
    
    % Setting the proper recording resolution, proper calibration type, as well as the data file content
    Eyelink('command','screen_pixel_coords = %ld %ld %ld %ld', 0, 0, screenXpixels - 1, screenYpixels - 1);
    Eyelink('message', 'DISPLAY_COORDS %ld %ld %ld %ld', 0, 0, screenXpixels - 1, screenYpixels - 1);
    
    % Setting the proper calibration type. Usually we use 9 points calibration. For a long range mount also 13 points (HV13) is a good (longer) calibration.
    Eyelink('command', 'calibration_type = HV9');
    
    % Setting the proper data file content
    Eyelink('command', 'file_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON');
    Eyelink('command', 'file_sample_data  = LEFT,RIGHT,GAZE,HREF,AREA,GAZERES,STATUS');
    
    % Setting link data (used for gaze cursor, optional)
    Eyelink('command', 'link_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON');
    Eyelink('command', 'link_sample_data  = LEFT,RIGHT,GAZE,GAZERES,AREA,STATUS');
    
    % Saccade detection thresholds (optional)
    Eyelink('command', 'saccade_velocity_threshold = 35');
    Eyelink('command', 'saccade_acceleration_threshold = 9500');
    
    % Now make sure that we are still connected to the Eyelink ... otherwise throw error
    if Eyelink('IsConnected')~=1
        error('Eyelink disconnected !!!');
    end;
    
    % EYELINK CALIBRATION
    % This code allow the EyeLink software to take control of your psychtoolbox screen. This means that at this point you will see participant eyes as recorded
    % by the Eye-tracker camera on the MEG whiteboard, a condition essential for setting up the camera. After setting up the camera you can perform calibration
    % and validation at this step.
    
    % Some calibration parameters
    elk.el.foregroundcolour = 0;
    elk.el.backgroundcolour = [bg bg bg] * 255;
    
    % Give eye-tracker control of the screen for camera setup and calibration, until you exit back to psychtoolbox by pressing ESC
    EyelinkDoTrackerSetup(elk.el);
    
end


% if MEG

if MEG
    % INITIALIZE DATAPIXX
    Datapixx('Open');					% Open DataPixx
    
    Datapixx('SetVideoMode', 0);		% This set video mode to normal passthrought, no stereo mode. C24, Straight passthrough from DVI 8-bit RGB to VGA RGB.
    % In this configuration luminance is linear with RGB (see our wiki).
    
    Datapixx('StopAllSchedules');		% Stop all schedules (audio waveforms, triggers etc...)
    
    Datapixx('SetDoutValues', 0);		% Set digital output to zero, as required to prepare for triggering
    
    Datapixx('EnableDinDebounce');		% Enable response debouncing. This is required to prune out spurious button presses after a real response
    
    Datapixx('SetDinLog');				% Clear digital input logger, i.e: clear old responses in the register
    Datapixx('StopDinLog');				% Stop running response logger
    
    Datapixx('RegWrRd');				% So far, no real changes occurred on the physical blue box devices. This command synchronize local and remote registers
    % in a read/write mode and immediately. Only now, the blue box status is as determined by the above initializations.
    
    responseButtonsMask = 2^0 + 2^1 + 2^2 + 2^3;	% Values of response buttons are stored in a cumbersome binary way. This is a binary mask useful to
    % transform them in decimal human-readable values. In particular, red = 1, blue = X, geen = X and yellow =
    % X. It works. Just believe it. I do, I am a true believer. Neo is the one.
end


%% 5. general instructions
% outside instructions before any run because if run loop is inside of trial loop
% then for each trial of 1st run => it repeats everything
% instruction for run 1 & run 2
if runnum == 1
        DrawFormattedText(win,'- Thank you very much for participating in this experiment -','center', yCenter-yCenter*3/6, black);
        DrawFormattedText(win,'- Please read the following instructions carefully and ask the experimenter if anything is unclear -','center', yCenter-yCenter*2/6, black);
        
        DrawFormattedText(win,'- press button to start the instructions -','center', yCenter+yCenter*5/6, black);
        
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        
        if MEG
            Datapixx('EnableDinDebounce');  % Set this to avoid fast oscillation in button press (if unsure use it !)
            
            % Reset and fire up the response logger
            Datapixx('SetDinLog');
            Datapixx('StartDinLog');
            Datapixx('RegWrRd');                        % Commit changes to/from DP
            status = Datapixx('GetDinStatus');
            
            while status.newLogFrames == 0
            % general
                Datapixx('RegWrRd');
                status = Datapixx('GetDinStatus');
            end
        else
            KbStrokeWait;
        end    
            % movie
        DrawFormattedText(win,'- You are about to watch 6 different short clips of a skater -','center', yCenter-yCenter*5/6, black);
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
triggercount = 0;
for itrial = 1:size(condmat,2) % condmat = 30 participants x 6 trials x 6 runs x 2 vid&cond
   % trig should send condition information
    trig_trial_start = vid2disp(itrial);   %  1–52  (video ID)
    trig_trial_end   = 60 + currentcondition(itrial);          % 61–66  (condition)           

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
    WaitSecs(5); 

    %countdown at start each trial
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


    %% Start movie playback
    % Open movie file and retrieve basic info about movie:
    framecount = 0;
    occ_count_within_trial = 1; % increment to 2
    % movie gives a handle; imgw,imgh = size of movie; 
    [movie, movieduration, fpsn, imgw, imgh, ~, ~] = Screen('OpenMovie', win, movienames);
    if fps ~= fpsn
        error('Indicated frames per second at parameter initialization at experiment start not same as frames per second as read from movie file')
    end

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

    % start 
    Screen('PlayMovie', movie, movierate, 0, audiovolume);

    % tex = Screen('GetMovieImage', win, movie, blocking);
    % Screen('DrawTexture', win, tex, sourceRect, movierect);
    % Screen('Flip', win);  

    % choose how many occlusions in this trial
    n_occ = [2,3];
    idx = randi(2);
    n_occ_this_trial = n_occ(idx);

    %  choose 2/3 occlusions out of 5 for this trial
    if n_occ_this_trial == 2
        ind = randperm(4);
        ind = [sort(ind(1)),5]; % make sure if there are only 2 occlusions, the second one is in the second to last 10s
        occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind); % 2 frames of occlusion onset
        occ_onset(end+1) = movieduration*fps + 10; % add padding
    elseif n_occ_this_trial == 3
        ind = randperm(5);
        ind = sort(ind(1:n_occ_this_trial));
        occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind); % 3 frames of occlusion onset
        occ_onset(end+1) = movieduration*fps + 10; % add padding
    end

    notexcount = 0;

    correct_response_for_this_trial = [zeros(1,ceil(n_occ_this_trial/2)) ones(1,floor(n_occ_this_trial/2))];
    correct_response_for_this_trial = correct_response_for_this_trial(randperm(length(correct_response_for_this_trial)));


    % output
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
                     
            if framecount == 1
                Screen('FillRect', win, [white white white], photodiodepos);
            else       
                Screen('FillRect', win, [black black black], photodiodepos);
            end
        
            Screen('Flip', win);
            Screen('Close', tex);
             if framecount == 1
                if MEG
                    triggerPulse = [1 0] .* trig_trial_start;
                    Datapixx('StopDoutSchedule');
                    Datapixx('WriteDoutBuffer', triggerPulse);
                    Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                    Datapixx('StartDoutSchedule');
                end
                if trackeye
                    Eyelink('Message', sprintf('TRIGGER %d trial_start cond%d vid%d', ...
                        trig_trial_start, currentcondition(itrial), vid2disp(itrial)));
                end
                triggercount = triggercount + 1;
                output(triggercount).trigger    = trig_trial_start;
                output(triggercount).task_onset = GetSecs;
                output(triggercount).trial      = itrial;
                output(triggercount).condition  = currentcondition(itrial);
                output(triggercount).video      = vid2disp(itrial);
            end
        
            if MEG
                Datapixx('RegWrVideoSync');
            end
        end
        %% task
        if framecount == round(occ_onset(occ_count_within_trial))
             trig_occ_onset    = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial);    % 100 + 4                
             trig_task_onset   = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial);   % 110 + 4           
             trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial); 

             occlusion_start = Screen('GetMovieTimeIndex', movie);
             movierate = 0;
             Screen('PlayMovie', movie, movierate, 0, audiovolume);
% %% c. at occlusion onset:
%     % - **Stop movie, show black screen**
             Screen('FillRect', win, bg, movierect);
             Screen('FillRect', win, [white white white], photodiodepos);
             triggercount = triggercount + 1;

             if MEG
                triggerPulse = [1 0] .* trig_occ_onset;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                Datapixx('StartDoutSchedule');
                Datapixx('RegWrVideoSync');
             end
    
             if trackeye
                % send occlusion trigger
                Eyelink('Message', sprintf('TRIGGER %d occ_onset occ%d', trig_occ_onset, occ_count_within_trial));
    
             end
             output(triggercount).trial     = itrial;
             output(triggercount).video     = vid2disp(itrial);
             output(triggercount).condition = currentcondition(itrial);
             output(triggercount).trigger    = trig_occ_onset;
             output(triggercount).task_onset = GetSecs;
             output(triggercount).task_num   = occ_count_within_trial;

             Screen('Flip', win);
             WaitSecs(occ_time);
%     % - **show frame according to condition 123 - posture vs 456 - position
             if any(currentcondition(itrial) == [1 2 3])
                if MEG
                    DrawFormattedText(win, '-Orange button = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-green button = different posture-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-left arrow = different posture-','center', yCenter-yCenter*1/6, black);
                end
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip',win);
                WaitSecs(1);
                 %    show posture/coherent or incoherent
                if correct_response_for_this_trial(occ_count_within_trial)  == 1 % coherent -> show the frame after 5 frames
                    targetTime = (framecount + occ_time)/fps;
                    Screen('SetMovieTimeIndex',movie,targetTime);
                    Screen('PlayMovie',movie,1,0,audiovolume);
                    tex_probe = Screen('GetMovieImage', win, movie, 1);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);
                elseif correct_response_for_this_trial(occ_count_within_trial)  == 0 
                    if currentcondition(itrial) == 1
                        tmp_path = fullfile(stimdir,'posture_incoherent_normal');
                        frametoshow = sprintf("norm_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 2
                        tmp_path = fullfile(stimdir,'posture_incoherent_low');
                        frametoshow = sprintf("low_occ_vid_%d_time_%d.png", vid2disp(itrial), ind(occ_count_within_trial));
                    elseif currentcondition(itrial) == 3
                        tmp_path = fullfile(stimdir,'posture_incoherent_high');
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
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip',win);
                WaitSecs(1);        
                if correct_response_for_this_trial(occ_count_within_trial) == 1 % coherent -> 5 frames later
                    pelvisx_vid = pelvis(vid2disp(itrial), 1, framecount+5);
                    pelvisy_vid = pelvis(vid2disp(itrial), 2, framecount+5);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0 % incoherent -> 50 frames later
                    pelvisx_vid = pelvis(vid2disp(itrial), 1, framecount+100);
                    pelvisy_vid = pelvis(vid2disp(itrial), 2, framecount+100);
                end

                % map from video frame space -> screen space
                
                pelvisx_screen = movie_left + pelvisx_vid * movie_scale_x;
                pelvisy_screen = movie_top  + pelvisy_vid * movie_scale_y;

                dotRect = CenterRectOnPoint([0 0 dotSize dotSize], pelvisx_screen, pelvisy_screen);
                rect = CenterRect([0, 0, imgw, imgh], windowRect);

                Screen('FillRect', win, [1 1 1       ], rect);
                Screen('FillOval', win, [0 0 0], dotRect);
             end 
             Screen('FillRect', win, [white white white], photodiodepos);
             Screen('Flip', win);
             triggercount = triggercount + 1;
             if MEG
                triggerPulse = [1 0] .* trig_task_onset;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                Datapixx('StartDoutSchedule');

                % Set marker here to measure RT from
                Datapixx('RegWrVideoSync');
             end
             if trackeye
                Eyelink('Message', sprintf('TRIGGER %d task_onset occ%d', trig_task_onset, occ_count_within_trial));
             end
             output(triggercount).trial     = itrial;
             output(triggercount).video     = vid2disp(itrial);
             output(triggercount).condition = currentcondition(itrial);
             output(triggercount).trigger    = trig_task_onset;
             output(triggercount).task_onset = GetSecs;
             output(triggercount).task_num   = occ_count_within_trial;
             output(triggercount).correct_response = correct_response_for_this_trial(occ_count_within_trial);

             if MEG
                Datapixx('SetMarker');
                Datapixx('RegWrRd');
                rtMarkerTime = Datapixx('GetMarker');
             end

%     % - collect response
             start_resp_time = GetSecs;
             respMade = false;
             given_response_for_this_trial = NaN; 
%              wait til response/kb pressed
%              check if response was correct or not
%              show feedback
%              store response & reaction time
             while ~respMade && (GetSecs - start_resp_time) < 3

                % get response      
                if ~MEG
                    [keyIsDown, time_resp, keyCode] = KbCheck;
                    if keyIsDown==1 && (keyCode(congruent) || keyCode(incongruent))
                        respMade = true;
                        if keyCode(congruent)
                            given_response_for_this_trial = 1;
                        else% if keyCode(incongruent)
                            given_response_for_this_trial = 0;
                        end
                        respMade = true;
                    end
                else%if MEG
                    Datapixx('RegWrRd');
                    status = Datapixx('GetDinStatus');
                    if status.newLogFrames > 0
                        [data, time_resp] = Datapixx('ReadDinLog');
                        respCode = bitand(data(end), responseButtonsMask);
                        % map  MEG buttons: e.g. red=1 → same, blue=2 → different
                        if respCode == 1
                            given_response_for_this_trial = 1;
                        elseif respCode == 2
                            given_response_for_this_trial = 0;
                        end
                        respMade = true;
                    end
                end

            end% while loop% 
            % given_response = [given_response,given_response_for_this_trial
%     % - show feedback % store
            triggercount = triggercount + 1;

            if ~isnan(given_response_for_this_trial)
                resp_trig = 120 + (occ_count_within_trial-1)*2 + given_response_for_this_trial;
            else
                resp_trig = 139 + + occ_count_within_trial;
            end            
            if MEG
                triggerPulse = [1 0] .* resp_trig;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 0, 100, 2);  % no delay for response trigger
                Datapixx('StartDoutSchedule');
                Datapixx('RegWrRd');
                output(triggercount).RT = Datapixx('GetMarker') - rtMarkerTime;
            end
            if trackeye
                Eyelink('Message', sprintf('TRIGGER %d response %d occ%d', resp_trig, given_response_for_this_trial, occ_count_within_trial));
            end
            output(triggercount).trial     = itrial;
            output(triggercount).video     = vid2disp(itrial);
            output(triggercount).condition = currentcondition(itrial);
            output(triggercount).trigger        = resp_trig;
            output(triggercount).task_onset     = GetSecs;
            output(triggercount).task_num       = occ_count_within_trial;
            output(triggercount).given_response = given_response_for_this_trial;
            output(triggercount).correct_response = correct_response_for_this_trial(occ_count_within_trial);
            

            if respMade

                given_response = [given_response, given_response_for_this_trial];
                Screen('TextSize', win, fb_text_size);% set text size for feedback symbols
                Screen('FillRect', win, bg, movierect);

                % check if response was correct or not
                if given_response_for_this_trial == correct_response_for_this_trial(occ_count_within_trial)
                    DrawFormattedText(win, 'Correct', 'center', 'center', colors(1,:));
                else
                    DrawFormattedText(win, 'Incorrect', 'center', 'center', colors(2,:));
                end

                % show feedback
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip', win);
                Screen('TextSize', win, text_size);% set back to regular text size

                WaitSecs(1);
            else
                
                given_response = [given_response, NaN]; % log the miss
            end
%     % - rewinde to 1s before occlusion & update parameters 
            newtime = occlusion_start - 1;
            framecount = round(occ_onset(occ_count_within_trial)) - fps - 1;
            occ_count_within_trial = occ_count_within_trial + 1;
       % restart the movie
            Screen('SetMovieTimeIndex', movie, newtime);
            movierate = 1;
            Screen('PlayMovie', movie, movierate, 0, audiovolume);  
            Screen('FillRect', win, [white white white], photodiodepos);
            Screen('Flip', win);
              % trigger restart
            triggercount = triggercount + 1;
            if MEG
                triggerPulse = [1 0] .* trig_movie_restart;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                Datapixx('StartDoutSchedule');
                % RegWrVideoSync will be called on next frame in the while loop
            end
            if trackeye
                Eyelink('Message', sprintf('TRIGGER %d movie_restart occ%d', trig_movie_restart, occ_count_within_trial-1));
            end
            output(triggercount).trial     = itrial;
            output(triggercount).video     = vid2disp(itrial);
            output(triggercount).condition = currentcondition(itrial);
            output(triggercount).trigger   = trig_movie_restart;
            output(triggercount).task_onset = GetSecs;
            output(triggercount).task_num  = occ_count_within_trial - 1;

        end 
    end % while loop still have frames
    Screen('FillRect', win, [white white white], photodiodepos);
    Screen('Flip', win       );
    triggercount = triggercount + 1;
    if MEG
        triggerPulse = [1 0] .* trig_trial_end;
        Datapixx('StopDoutSchedule');
        Datapixx('WriteDoutBuffer', triggerPulse);
        Datapixx('SetDoutSchedule', 0, 100, 2);
        Datapixx('StartDoutSchedule');
        Datapixx('RegWrRd');
    end
    if trackeye
        Eyelink('Message', sprintf('TRIGGER %d trial_end cond%d vid%d', trig_trial_end, currentcondition(itrial), vid2disp(itrial)));
    end
    output(triggercount).trial     = itrial;
    output(triggercount).video     = vid2disp(itrial);
    output(triggercount).condition = currentcondition(itrial);
    output(triggercount).trigger   = trig_trial_end;
    output(triggercount).task_onset = GetSecs;


end % for loop through 6 blocks
save(fullfile(savedir, filename), 'output');

