clearvars
clc
%% load model data
% 5 models: 2d posture = normalized_coords; position; OF direction;
% OF magnitude; pixelwise luminance
% server = '\\cimec-storage6.cimec.unitn.it\ingdev\projects\THANH\IceSkating\models\';
% server = '/Volumes/THANH/IceSkating/models';
rootdir = '/Users/goal0312/Desktop/thesis/model';
% addpath(genpath('\\cimec-storage6.cimec.unitn.it\ingdev\projects\THANH\IceSkating\models\dRSA_toolbox-main'));
addpath(genpath('/Users/goal0312/Desktop/thesis/2_simulations/dRSA_toolbox-main'));

load(fullfile(rootdir,'pixelwise_lum.mat'),'pixelwise_lum')
load(fullfile(rootdir,'ofs_vxvy.mat'))

% load(fullfile(server,'ofs_dir.mat'),'ofs_dir')
% load(fullfile(server,'ofs_mag.mat'),'ofs_mag')
load(fullfile(rootdir,'interpolated_2d_coords.mat'))
load(fullfile(rootdir,'normalized_coords.mat'))


normalized_coords = reshape(normalized_coords, [52, 34, 4200]);
position = squeeze((coords(:,12,:,:)+coords(:,13,:,:))/2);

%% concatenate: 
% input: trial x feature x time array
% output: feature x time
dataIn1 = squeeze(num2cell(position,[2, 3]));
position_model = squeeze(cat(3, dataIn1{:})); % concat arrays

dataIn2 = squeeze(num2cell(normalized_coords,[2, 3]));
posture_model = squeeze(cat(3, dataIn2{:})); % concat arrays

dataIn3 = squeeze(num2cell(ofs,[2, 3]));
of_model = squeeze(cat(3, dataIn3{:})); % concat arrays

dataIn4 = squeeze(num2cell(pixelwise_lum,[2, 3]));
pixelwise_model = squeeze(cat(3, dataIn4{:})); % concat arrays

% mask boundaries between videos
len = repmat([size(dataIn1{1},3)],[size(dataIn1), 1]); % the same for all vids so taking 1 is ok
maskConcat = ones(1,sum(len));
startEndIdx = [cumsum(len), cumsum(len)+1]; % store start and end indexes
startEndIdx = startEndIdx(1:end-1); % take out last one
maskConcat(startEndIdx) = 0; % assign 0 to start and end    
maskSubsampling = logical(maskConcat);

clear dataIn1 dataIn2 dataIn3 dataIn4 
clear position normalized_coords ofs pixelwise_lum coords

% paramsional module: create subsamples
params.spacing = 5;
params.nIter   = 100;
params.nSubSamples = 30; 
params.SubSampleDur = 250;


subsamples = dRSA_random_subsampling(maskSubsampling, params);
% include illustration
% mask is maskTypes*time
% output: nSubsamples*subSampleDuration*iterations
% for later: paramsion to provide predefined time points (e.g. for predictable vs. unpredictable time points)


%% Simulations



%% dRSA



% wrapper for many subsamples (most cases, except e.g. Ayman)


% In case we do the PCR, it is better to calculate the border outside, because otherwise we would need to recalculate it
% for each iteration
params.nIter = 100;  %how many Iterations?
params.AverageTime = 10; %in s
params.fs = 50; %framerate or how many samples fit into 1 second
params.modelToTest = [1 2 3 4];  %array of models to test
params.Var = 0.1; % how much variance? 

params.modelDistMeasure = {'euclidean', 'correlation','correlation','correlation'};



Autocorrborder = [];
% if ~strcmp(params.dRSAtype, 'corr') % Autocorrelation not used with 'corr' type.
%     Autocorrborder = dRSA_border(model, subsamples, params);
% end

%For the PCR
params.dRSAtype = 'corr';
%params.modeltoRegressout = {[4 5] [1 3] [1 2]};
%the other stuff use default values. Can be changed, see documentation of PCR function


%Y = data1;


model{1} = position_model;
model{2} = posture_model;
model{3} = of_model;
model{4} = pixelwise_model;

allDiagonals = {zeros(4,1)};
for imod = 1:4
    dRSA_Iter = [];  % reset

    Y = model{imod};
    params.neuralDistMeasure = params.modelDistMeasure{imod};
    for iIter = 1:params.nIter

        CurrSubsamples = subsamples(:,:,iIter); % subsamples is nSubsamples*subSampleDuration*iterations
        dRSAma = dRSA_coreFunction(Y,model, params, ...
            'CurrSubsamples', CurrSubsamples);%
        % Y is features*time or a finished RDM of subsamples x subsamples x time
        % models: 1*nModels cell arrray (also used for regress out models, automatically regresses out other models)
        
        
        %In this funciton we have default values
        % we also have varagin: If we want, we can add the autocorrelation and already Subsamples at the end, but we dont need to
        
        
        dRSA_Iter(iIter,:,:,:) = dRSAma;
    end  %of nIter
    
    % average dRSAmats (do by summing current with previous summed)  
     % ----------------------------------QUESTION:  include this into averaging function?
    dRSA = mean(dRSA_Iter ,1); % 1 = Fmean across first dim
    dRSA = reshape(dRSA, size(dRSA,2), size(dRSA,3), size(dRSA,4));
    
    %% plot 
    % - module for averaging across Time
    params.AverageTime = 10; %in s, how much should be left and right of the zerolag middle? 
    params.fs = 50; %framerate or how many samples fit into 1 second
    dRSA_diagonal = dRSA_average(dRSA, params);
    allDiagonals{imod} = dRSA_diagonal;  % store per model

end

%% stats and plots
model = {'position', 'posture', 'of', 'pixelwise'};
for imod = 1:4
    figure;
    hold on
    for jmod = 1:4
            plot(allDiagonals{imod}(jmod, :));
            title(sprintf('%d'),model{imod})
            xlim([0 200])
            ylim([0 1])
            legend(model)
    end
    hold off
end
% 
%% stats and plots%% stats and plots
modelNames = {'position', 'posture', 'of', 'pixelwise'};
nModels = 4;

% Time axis: centered at 0, converted to seconds
nTimePoints = size(allDiagonals{1}, 2);
t = linspace(-params.AverageTime, params.AverageTime, nTimePoints);

% Restrict to -1 to 1 sec
tMask = t >= -5 & t <= 5;
t_plot = t(tMask);

% Colormap: one color per model (purple to yellow)
cmap = parula(nModels);

for imod = 1:nModels
    figure('Position', [100 100 650 450]);
    hold on;

    h = gobjects(nModels, 1); % store line handles for legend

    for jmod = 1:nModels
        data = allDiagonals{imod}(jmod, tMask);
        h(jmod) = plot(t_plot, data, 'Color', cmap(jmod,:), 'LineWidth', 2);
    end

    % Vertical dashed red line at lag = 0
    xline(0, '--r', 'LineWidth', 1.2);

    % Axes formatting
    xlabel('lag [sec]', 'FontSize', 13);
    ylabel('autocorrelation', 'FontSize', 13);
    title(modelNames{imod}, 'Interpreter', 'none', 'FontSize', 14);
    xlim([-5 5]);
    ylim([0 1]);
    box off;

    % Legend
    legend(h, modelNames, 'Location', 'northwest', 'FontSize', 10, 'Interpreter', 'none');

    % Colorbar
    cb = colorbar;
    colormap(parula(nModels));
    caxis([0 1]);                          % <-- replaces clim()
    cb.Label.String = 'layer depth';
    cb.Label.FontSize = 12;
    cb.Label.Rotation = 270;
    cb.Label.VerticalAlignment = 'bottom';

    hold off;
end
