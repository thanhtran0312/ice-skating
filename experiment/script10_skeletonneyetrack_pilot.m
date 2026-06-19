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
    PsychDebugWindowConfiguration([], 1);
    Screen('Preference', 'SkipSyncTests', 1);%1 = don't do screen sync + size tests
else
    Screen('Preference', 'SkipSyncTests', 0);% 0 = do screen sync + size tests
end
%% 2.parameters: 
% path 
if MEG
    rootdir =   'C:\Users\loca-admin\Desktop\projects';
    stimdir = fullfile(rootdir,'THANH_Wurm');
else
    rootdir = '/Users/goal0312/Desktop/thesis';  
    stimdir = fullfile(rootdir, '7_experiment');
end
addpath(genpath(stimdir));
load(fullfile(stimdir,"rescaled_coords.mat"),"keypoints_new")
load(fullfile(stimdir,"condmat.mat"),"condmat")
keypoints_new = permute(keypoints_new, [4,1,2,3]);     
      
% movie, 
fps = 50;
audiovolume = 0;sca
colors = [27 158 119;217 95 2;117 112 179;231,41,138;102,166,30]/255;% colorblind friendly colors in RGB values between 0 and 1
crosssize = 9;% fixation cross size in pixels 
crosswidth = round(crosssize/3);% fixation cross thickness in pixels
dotsize = crosswidth-1;% fixation cross dot size in pixels
moviesize = 1;
text_size = 30;
photodiodepos = [0 0 50 50]+200;
occ_time = 0.1;
occ_num = 12; % for each run except 2 f  cv     irst practice
dotSize = 15; % position task
fb_text_size = 100;% just feedback symbol size
fb_text_time = 0.3;% how long feedback symbol is shown in seconds

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
filename = sprintf('ProjectIceSkating_subject%02d_run%d',subnum,runnum);
Eyefilename = sprintf('Aice%02dr%02d.edf',subnum,runnum);

if exist([savedir filesep filename '.mat'],'file') && runnum > 2 && subnum ~= 99
    error(['\n   stopped because the filename %s.mat already exists!\n\n' ...
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

screen = max(Screen('Screens'));
PsychImaging('PrepareConfiguration');

% define colors
white = WhiteIndex(screen);
black = BlackIndex(screen);
grey = white / 2;
bg = grey*0.8;

% Open the experiment window
[win, windowRect] = PsychImaging('OpenWindow',  screen, bg);



% Get screen info
[screenXpix, screenYpix] = Screen('WindowSize', win);
[xCenter, yCenter] = RectCenter(windowRect);

% Choose 28 pixel text size:
Screen('TextSize', win, 28);

% set parameters that need xCenter yCenter
buttonSize = 30;
buttonX = xCenter - 100;
buttonY = yCenter - yCenter*2/6;
buttonY2 = yCenter - yCenter*1/6;

% For real        hide cursocvccv
%       cvr

% if ~debug
%     HideCursor(win,0);
% end

% Set PTB to top priority so no other running processes on this PC interfere
topPriorityLevel = MaxPriority(win);
Priority(topPriorityLevel);

% Flip to clear
Screen('Flip', win);

%% - eyetracking setup
% Compute pixels per degree (ppd) from screen geometry and viewing distance
viewingDistanceMm = 1000;                          % 1 meter
[monWidthMm, ~]   = Screen('DisplaySize', screen);
ppd               = pi * screenXpix / atan(monWidthMm / viewingDistanceMm / 2) / 360;

% Fixation monitoring parameters
fixWindowDeg          = 7.0;                       % degrees radius around fixation cross
fixWindowPx           = fixWindowDeg * ppd;        % convert to pixels
fixBreakToleranceFrames = 5;                       % consecutive frames outside window before counting as a break
fixBreakReminderThreshold = 3;                     % number of breaks per trial before showing reminder

% Per-run accumulator: how many breaks happened in each trial
fixation_breaks_per_trial = zeros(1, size(condmat, 2));

if trackeye
    % INITIALIZE EYELINK
    elk.wait = 0.01;
    
    if EyelinkInit() ~= 1
        error('Eyelink disconnected !!!');
    end
    
    elk.el = EyelinkInitDefaults(win);
    
    % Build EDF filename (max 8 chars for EyeLink)
    if subnum < 10
        Eyefilename = ['Aice0' num2str(subnum) 'r' num2str(runnum)];
    else
        Eyefilename = ['Aice' num2str(subnum) 'r' num2str(runnum)];
    end
    Eyefilename = [Eyefilename '.edf'];
    elk.edfFile = sprintf(Eyefilename);
    Eyelink('Openfile', elk.edfFile);
    
    Eyelink('command', sprintf('add_file_preamble_text ''IceSkating: subject %d ; run %d ; time %s''', ...
        subnum, runnum, datestr(now, 'YYYYmmddHHMM')));
    
    Eyelink('Command', 'link_sample_data = LEFT,RIGHT,GAZE,AREA');
    
    Eyelink('command', 'screen_pixel_coords = %ld %ld %ld %ld', 0, 0, screenXpix-1, screenYpix-1);
    Eyelink('message', 'DISPLAY_COORDS %ld %ld %ld %ld', 0, 0, screenXpix-1, screenYpix-1);
    
    Eyelink('command', 'calibration_type = HV9');
    Eyelink('command', 'file_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON');
    Eyelink('command', 'file_sample_data  = LEFT,RIGHT,GAZE,HREF,AREA,GAZERES,STATUS');
    Eyelink('command', 'link_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON');
    Eyelink('command', 'link_sample_data  = LEFT,RIGHT,GAZE,GAZERES,AREA,STATUS');
    Eyelink('command', 'saccade_velocity_threshold = 35');
    Eyelink('command', 'saccade_acceleration_threshold = 9500');
    
    if Eyelink('IsConnected') ~= 1
        error('Eyelink disconnected !!!');
    end
    
    % Calibration
    elk.el.foregroundcolour = 0;
    elk.el.backgroundcolour = [bg bg bg] * 255;
    EyelinkDoTrackerSetup(elk.el);
end

if MEG
    Datapixx('Open');
    Datapixx('SetVideoMode', 0);
    Datapixx('StopAllSchedules');
    Datapixx('SetDoutValues', 0);
    Datapixx('EnableDinDebounce');
    Datapixx('SetDinLog');
    Datapixx('StopDinLog');
    Datapixx('RegWrRd');
    responseButtonsMask = 2^0 + 2^1 + 2^2 + 2^3;
end

%% - load condition matrix, occlusion matrix
load(fullfile(stimdir,'condmat.mat'));
load(fullfile(stimdir,'occlusion_matrix.mat'),'occlusion_onset');

vid2disp        = condmat(subnum, :, runnum, 1);
currentcondition = condmat(subnum, :, runnum, 2);

%% output matrix
maxtrignum = 90;
output = struct(...
    'subnum',        num2cell(repmat(subnum,  1, maxtrignum)), ...
    'runnum',        num2cell(repmat(runnum,  1, maxtrignum)), ...
    'trial',         num2cell(NaN(1, maxtrignum)), ...
    'video',         num2cell(NaN(1, maxtrignum)), ...
    'condition',     num2cell(NaN(1, maxtrignum)), ...
    'trigger',       num2cell(NaN(1, maxtrignum)), ...
    'task_num',      num2cell(NaN(1, maxtrignum)), ...
    'task_onset',    num2cell(NaN(1, maxtrignum)), ...
    'correct_response', num2cell(NaN(1, maxtrignum)), ...
    'given_response',   num2cell(NaN(1, maxtrignum)), ...
    'RT',            num2cell(NaN(1, maxtrignum)), ...
    'fixation_breaks', num2cell(NaN(1, maxtrignum)));  % <-- added fixation break count per trigger

%% 5. general instructions
if runnum == 1
        DrawFormattedText(win,'- Thank you very much for participating in this experiment -','center', yCenter-yCenter*3/6, black);
        DrawFormattedText(win,'- Please read the following instructions carefully and ask the experimenter if anything is unclear -','center', yCenter-yCenter*2/6, black);
        DrawFormattedText(win,'- press button to start the instructions -','center', yCenter+yCenter*5/6, black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        
        if MEG
            Datapixx('EnableDinDebounce');
            Datapixx('SetDinLog');
            Datapixx('StartDinLog');
            Datapixx('RegWrRd');
            status = Datapixx('GetDinStatus');
            while status.newLogFrames == 0
                Datapixx('RegWrRd');
                status = Datapixx('GetDinStatus');
            end
        else
            KbStrokeWait;
        end    

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
        DrawFormattedText(win,'- You will now first perform the first run -','center', yCenter+yCenter*1/6, black);
        DrawFormattedText(win,'- Inform the experimenter you have read the instructions -','center', yCenter+yCenter*2/6, black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        KbStrokeWait;
end
    
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
abortit = 0;
blocking = 1;
movierate = 1;
triggercount = 0;

for itrial = 1:size(condmat,2)

    trig_trial_start = vid2disp(itrial);
    trig_trial_end   = 60 + currentcondition(itrial);

    %% --- fixation break counters: reset at the start of each trial ---
    gazeOutsideCounter = 0;   % consecutive frames outside fixation window
    fixBreakCount      = 0;   % number of distinct breaks this trial
    currentlyOutside   = false; % are we currently mid-break?

    if trackeye
        Eyelink('StartRecording', 1, 1, 1, 1);
        WaitSecs(elk.wait);
        Eyelink('Message', sprintf('TRIAL_START trial%d vid%d cond%d', ...
            itrial, vid2disp(itrial), currentcondition(itrial)));
    end

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
        DrawFormattedText(win,'Focus on POSTURE.','center',yCenter, black);
        colorID = 2;
    elseif any(currentcondition(itrial) == [4,5,6])
        DrawFormattedText(win,'Focus on POSITION.','center',yCenter, black);
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
    framecount = 0;
    occ_count_within_trial = 1;
    [movie, movieduration, fpsn, imgw, imgh, ~, ~] = Screen('OpenMovie', win, movienames);

    if fps ~= fpsn
        error('fps mismatch between parameters and movie file')
    end

    if imgw*moviesize > screenXpix || imgh*moviesize > screenYpix
        movierect = CenterRect((screenXpix / imgw) * [0, 0, imgw, imgh], Screen('Rect', win));
    elseif moviesize == 1
        movierect = [];
    else
        movierect = CenterRect(moviesize * [0, 0, imgw, imgh], Screen('Rect', win));
    end
    if isempty(movierect)
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

    n_occ = [2,3];
    idx = randi(2);
    n_occ_this_trial = n_occ(idx);

    if n_occ_this_trial == 2
        ind = randperm(4);
        ind = [sort(ind(1)),5];
        occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind);
        occ_onset(end+1) = movieduration*fps + 10;
    elseif n_occ_this_trial == 3
        ind = randperm(5);
        ind = sort(ind(1:n_occ_this_trial));
        occ_onset = occlusion_onset(condmat(subnum,itrial,runnum,1),ind);
        occ_onset(end+1) = movieduration*fps + 10;
    end

    notexcount = 0;

    correct_response_for_this_trial = [zeros(1,ceil(n_occ_this_trial/2)) ones(1,floor(n_occ_this_trial/2))];
    correct_response_for_this_trial = correct_response_for_this_trial(randperm(length(correct_response_for_this_trial)));

    %% b. frame by frame loop
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
            Screen('DrawLine', win, fix_color, xCenter-crosssize      , yCenter, xCenter+crosssize, yCenter, crosswidth);
            Screen('DrawLine', win, fix_color, xCenter, yCenter-crosssize, xCenter, yCenter+crosssize, crosswidth);
            Screen('FillOval', win, black, [xCenter - dotsize, yCenter - dotsize, xCenter + dotsize, yCenter + dotsize], dotsize*2);
                     
            if framecount == 1
                Screen('FillRect', win, [white white white], photodiodepos);
            else       
                Screen('FillRect', win, [black black black], photodiodepos);
            end
        
            Screen('Flip', win);
            Screen('Close', tex);

            %% --- fixation monitoring: runs every frame during movie playback ---
            if trackeye
                try
                    sample = Eyelink('NewestFloatSample');
                catch
                    sample = [];
                end

                if ~isempty(sample) && isstruct(sample)
                    gazeX  = double(sample.gx);
                    gazeY  = double(sample.gy);
                    pupilA = double(sample.pa);

                    % valid eyes: not NaN gaze and pupil > 0 (pupil = 0 during blinks)
                    validEyes = (~isnan(gazeX)) & (~isnan(gazeY)) & (pupilA > 0);

                    if any(validEyes)
                        % Euclidean distance from fixation cross center
                        distFromFix = sqrt((gazeX - xCenter).^2 + (gazeY - yCenter).^2);
                        eyeWithinWindow = any(distFromFix(validEyes) <= fixWindowPx);
                    else
                        % blink or tracker dropout: don't penalise
                        eyeWithinWindow = true;
                    end

                    if ~eyeWithinWindow
                        gazeOutsideCounter = gazeOutsideCounter + 1;
                    else
                        if currentlyOutside
                            % gaze just came back inside: end of this break
                            currentlyOutside = false;
                        end
                        gazeOutsideCounter = 0;
                    end

                    % count as one new break only the moment threshold is first crossed
                    if gazeOutsideCounter == fixBreakToleranceFrames && ~currentlyOutside
                        fixBreakCount    = fixBreakCount + 1;
                        currentlyOutside = true;
                        Eyelink('Message', sprintf('FIXATION_BREAK trial%d break%d frame%d', ...
                            itrial, fixBreakCount, framecount));
                    end
                end
            end
            %% --- end fixation monitoring ---

             if framecount == 1
                if MEG
                    triggerPulse = [1 0] .* trig_trial_start;
                    Datapixx('StopDoutSchedule');
                    Datapixx('WriteDoutBuffer', triggerPulse);
                    Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                    Datapixx('StartDoutSchedule');
                    Datapixx('RegWr');
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

        %% task: occlusion
        if framecount == round(occ_onset(occ_count_within_trial))
             trig_occ_onset    = 70 + (occ_count_within_trial-1)*6 + currentcondition(itrial);
             trig_task_onset   = 90 + (occ_count_within_trial-1)*6 + currentcondition(itrial);
             trig_movie_restart = 130 + (occ_count_within_trial-1)*6 + currentcondition(itrial);

             occlusion_start = Screen('GetMovieTimeIndex', movie);
             movierate = 0;
             Screen('PlayMovie', movie, movierate, 0, audiovolume);

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

             if any(currentcondition(itrial) == [1 2 3])
                % if MEG
                %     Screen('FillOval', win, [0 1 0],[buttonX-buttonSize, buttonY-buttonSize, buttonX+buttonSize, buttonY+buttonSize]);
                %     DrawFormattedText(win, '= same posture', buttonX+buttonSize+10, buttonY-10, black);
                %     Screen('FillOval', win, [1 0.5 0],[buttonX-buttonSize, buttonY2-buttonSize, buttonX+buttonSize, buttonY2+buttonSize]);
                %     DrawFormattedText(win, '= different posture', buttonX+buttonSize+10, buttonY2-10, black);
                % else
                %     Screen('FillOval', win, [0 1 0],[buttonX-buttonSize, buttonY-buttonSize, buttonX+buttonSize, buttonY+buttonSize]);
                %     DrawFormattedText(win, '= same position', buttonX+buttonSize+10, buttonY-10, black);
                %     Screen('FillOval', win, [1 0.5 0],[buttonX-buttonSize, buttonY2-buttonSize, buttonX+buttonSize, buttonY2+buttonSize]);
                %     DrawFormattedText(win, '= different position', buttonX+buttonSize+10, buttonY2-10, black);
                % end
                if MEG
                    DrawFormattedText(win, '-Right button = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Left button = different posture-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-left arrow = different posture-','center', yCenter-yCenter*1/6, black);
                end
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip',win);
                WaitSecs(1);

                if correct_response_for_this_trial(occ_count_within_trial) == 1
                    targetTime = (framecount + occ_time)/fps;
                    Screen('SetMovieTimeIndex',movie,targetTime);
                    Screen('PlayMovie',movie,1,0,audiovolume);
                    tex_probe = Screen('GetMovieImage', win, movie, 1);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0 
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
                    img = imread(fullfile(tmp_path, frametoshow));
                    tex_probe = Screen('MakeTexture', win, img);
                    Screen('DrawTexture', win, tex_probe, [], movierect);
                    Screen('Close', tex_probe);   
                end

             elseif any(currentcondition(itrial) == [4 5 6])
                % if MEG
                %     Screen('FillOval', win, [0 1 0],[buttonX-buttonSize, buttonY-buttonSize, buttonX+buttonSize, buttonY+buttonSize]);
                %     DrawFormattedText(win, '= same position', buttonX+buttonSize+10, buttonY-10, black);
                %     Screen('FillOval', win, [1 0.5 0],[buttonX-buttonSize, buttonY2-buttonSize, buttonX+buttonSize, buttonY2+buttonSize]);
                %     DrawFormattedText(win, '= different position', buttonX+buttonSize+10, buttonY2-10, black);
                % else
                %     Screen('FillOval', win, [0 1 0],[buttonX-buttonSize, buttonY-buttonSize, buttonX+buttonSize, buttonY+buttonSize]);
                %     DrawFormattedText(win, '= same position', buttonX+buttonSize+10, buttonY-10, black);
                %     Screen('FillOval', win, [1 0.5 0],[buttonX-buttonSize, buttonY2-buttonSize, buttonX+buttonSize, buttonY2+buttonSize]);
                %     DrawFormattedText(win, '= different position', buttonX+buttonSize+10, buttonY2-10, black);
                % end
                if MEG
                    DrawFormattedText(win, '-Right button = same position,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-Left button = different position-','center', yCenter-yCenter*1/6, black);
                else
                    DrawFormattedText(win, '-Right arrow = same posture,','center', yCenter-yCenter*2/6, black);
                    DrawFormattedText(win, '-left arrow = different posture-','center', yCenter-yCenter*1/6, black);
                end
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip',win);
                WaitSecs(1);        

                if correct_response_for_this_trial(occ_count_within_trial) == 1
                    skeleton_x = keypoints_new(vid2disp(itrial),:,1,framecount+occ_time*fps);
                    skeleton_y = keypoints_new(vid2disp(itrial),:,2,framecount+occ_time*fps);
                elseif correct_response_for_this_trial(occ_count_within_trial) == 0
                    skeleton_x = keypoints_new(vid2disp(itrial),:,1, framecount + occ_time*fps);
                    skeleton_y = keypoints_new(vid2disp(itrial),:,2, framecount + occ_time*fps);
                
                    pelvis_x_now  = (keypoints_new(vid2disp(itrial),12,1,framecount + occ_time*fps) + ...
                                     keypoints_new(vid2disp(itrial),13,1,framecount + occ_time*fps)) / 2;
                    pelvis_y_now  = (keypoints_new(vid2disp(itrial),12,2,framecount + occ_time*fps) + ...
                                     keypoints_new(vid2disp(itrial),13,2,framecount + occ_time*fps)) / 2;
                
                    pelvis_x_100  = (keypoints_new(vid2disp(itrial),12,1,framecount + 200) + ...
                                     keypoints_new(vid2disp(itrial),13,1,framecount + 200)) / 2;
                    pelvis_y_100  = (keypoints_new(vid2disp(itrial),12,2,framecount + 200) + ...
                                     keypoints_new(vid2disp(itrial),13,2,framecount + 200)) / 2;
                
                    skeleton_x = skeleton_x + (pelvis_x_100 - pelvis_x_now);
                    skeleton_y = skeleton_y + (pelvis_y_100 - pelvis_y_now);
                end

                skeleton_x_screen = movie_left + skeleton_x * movie_scale_x;
                skeleton_y_screen = movie_top  + skeleton_y * movie_scale_y;
                
                skeleton_bones = [1 2; 1 3; 
                                    2 4; 3 5;
                                    6 7; 
                                    6 8; 8 10; 
                                    7 9; 9 11;
                                    6 12; 7 13;
                                    12 13;
                                    12 14; 14 16;
                                    13 15; 15 17];
                
                rect = CenterRect([0, 0, imgw, imgh], windowRect);
                Screen('FillRect', win, [199/255 199/255 199/255], rect);
                
                for b = 1:size(skeleton_bones, 1)
                    p1 = skeleton_bones(b, 1);
                    p2 = skeleton_bones(b, 2);
                    Screen('DrawLine', win, [0 0 0], ...
                        skeleton_x_screen(p1), skeleton_y_screen(p1), ...
                        skeleton_x_screen(p2), skeleton_y_screen(p2), 3);
                end
                
                jointSize = 8;
                for j = 1:17
                    jointRect = CenterRectOnPoint([0 0 jointSize jointSize], ...
                        skeleton_x_screen(j), skeleton_y_screen(j));
                    Screen('FillOval', win, [0 0 0], jointRect);
                end
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
                Datapixx('EnableDinDebounce');
                Datapixx('SetDinLog');
                Datapixx('StartDinLog'); 
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

             start_resp_time = GetSecs;
             respMade = false;
             given_response_for_this_trial = NaN; 

             while ~respMade && (GetSecs - start_resp_time) < 3
                if ~MEG
                    [keyIsDown, time_resp, keyCode] = KbCheck;
                    if keyIsDown==1 && (keyCode(congruent) || keyCode(incongruent))
                        respMade = true;
                        if keyCode(congruent)
                            given_response_for_this_trial = 1;
                        else
                            given_response_for_this_trial = 0;
                        end
                    end
                else
                    Datapixx('RegWrRd');
                    status = Datapixx('GetDinStatus');
                    if status.newLogFrames > 0
                        [data, time_resp] = Datapixx('ReadDinLog');
                        respCode = bitand(data(end), responseButtonsMask);
                        if respCode == 8
                            given_response_for_this_trial = 1;
                        elseif respCode == 1
                            given_response_for_this_trial = 0;
                        end
                        respMade = true;
                    end
                end
            end

            triggercount = triggercount + 1;
            if ~isnan(given_response_for_this_trial)
                resp_trig = 120 + (occ_count_within_trial-1)*2 + given_response_for_this_trial; 
            else
                resp_trig = 139 + occ_count_within_trial;
            end            
            if MEG 
                triggerPulse = [1 0] .* resp_trig;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 0, 100, 2);
                Datapixx('StartDoutSchedule');
                Datapixx('RegWrRd');
                if respMade
                    output(triggercount).RT = time_resp(end) - rtMarkerTime;
                else
                    output(triggercount).RT = NaN;
                end
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
                Screen('TextSize', win, fb_text_size);
                Screen('FillRect', win, bg, movierect);
                if given_response_for_this_trial == correct_response_for_this_trial(occ_count_within_trial)
                    DrawFormattedText(win, 'Correct', 'center', 'center', colors(1,:));
                else
                    DrawFormattedText(win, 'Incorrect', 'center', 'center', colors(2,:));
                end
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip', win);
                Screen('TextSize', win, text_size);
                WaitSecs(1);
            else
                Screen('TextSize', win, fb_text_size);
                Screen('FillRect', win, bg, movierect);
                DrawFormattedText(win,'Please respond faster next time','center','center',black);
                Screen('FillRect', win, [black black black], photodiodepos);
                Screen('Flip', win); 
                WaitSecs(1);
                Screen('TextSize', win, text_size);
            end

            newtime = occlusion_start - 1;
            framecount = round(occ_onset(occ_count_within_trial)) - fps - 1;
            occ_count_within_trial = occ_count_within_trial + 1;
            Screen('SetMovieTimeIndex', movie, newtime);
            movierate = 1;
            Screen('PlayMovie', movie, movierate, 0, audiovolume);  
            Screen('FillRect', win, [white white white], photodiodepos);
            Screen('Flip', win);
            triggercount = triggercount + 1;
            if MEG
                triggerPulse = [1 0] .* trig_movie_restart;
                Datapixx('StopDoutSchedule');
                Datapixx('WriteDoutBuffer', triggerPulse);
                Datapixx('SetDoutSchedule', 1.0/fps, 1000, 2);
                Datapixx('StartDoutSchedule');
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
    end % while loop: movie frames

    %% --- end of trial: store fixation break count and show reminder if needed ---
    fixation_breaks_per_trial(itrial) = fixBreakCount;

    % store break count on the trial-end trigger row (filled just below)
    % so it is also in the output struct alongside other trial info
    if trackeye
        Eyelink('StopRecording');
        Eyelink('Message', sprintf('TRIAL_END trial%d fixation_breaks%d', itrial, fixBreakCount));
    end

    Screen('FillRect', win, [white white white], photodiodepos);
    Screen('Flip', win);
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
    output(triggercount).fixation_breaks = fixBreakCount;  

    %% --- fixation reminder: shown between trials if threshold exceeded ---
    if trackeye && fixBreakCount >= fixBreakReminderThreshold
        Screen('TextSize', win, text_size);
        DrawFormattedText(win, ...
            ['Please try to keep your eyes on the fixation cross.\n\n' ...
             'The cross is always visible in the center of the screen.'], ...
            'center', 'center', black);
        Screen('FillRect', win, [black black black], photodiodepos);
        Screen('Flip', win);
        WaitSecs(3);
    end
    %% --- end fixation reminder ---

end % for loop: trials

%% 7. save
save(fullfile(savedir, filename), 'output', 'fixation_breaks_per_trial');

%% 8. close eyetracker
if trackeye
    Eyelink('Command', 'set_idle_mode');
    WaitSecs(0.5);
    Eyelink('CloseFile');
    try
        fprintf('Receiving EDF file: %s\n', elk.edfFile);
        Eyelink('ReceiveFile');
        if exist(elk.edfFile, 'file')
            movefile(elk.edfFile, fullfile(savedir, elk.edfFile));
            fprintf('EDF saved to: %s\n', fullfile(savedir, elk.edfFile));
        end
    catch
        fprintf('Warning: could not receive EDF file.\n');
    end
    Eyelink('ShutDown');
end

if MEG
    Datapixx('StopDinLog');
    Datapixx('SetDoutValues', 0);
    Datapixx('RegWrRd');
    Datapixx('Close');
end

Priority(0);
ShowCursor;
sca;