function [dRSAmat] = dRSA_coreFunction (Y, model, params, varargin)



%% INPUT:
% Y: an array of features*time, OR an RDM of nsubsampless x nsubsamples x time
% model: 1*nModels cell arrray in which each cell has features * time
% a cell array of RDMs

% params.modelToTest: array of models to test e.g. = [ 1 4 5]
% params.modeltoRegressout: cell of models, that are not tested, but only regressed out.
% In each cell, we have a vector of modelsls e.g.  {4 5} {1 3} {1 2};
%this cell array should align with modeltoTest So for each model that gets tested, we have here a cell that fits
%e.g.  
%params.modelToTest = [ 1 4 5]  or can be a cell {1 4 5}
%-- params.modeltoRegressout = {[4 5] [1 3] [1 2]}; for those three models

% params.modelNames: 1*nModels cell arrray with names of ALL models
% params.neuralDistMeasure: type of dist measure for neural data
% params.modelDistMeasure: 1*nModels cell arrray where each Distance Measure for each Model is specified

% params.dRSAtype = 'corr' or 'PCR'

% params.normalizazion = 'Standardize' or 'Rescale'  %important for PCR

%For PCR:
%params.PCR.RegressAutocor: Regress out Autocorrelation, yes (1) or no (0). Default is yes
%params.PCR.RessModel: Regress out other models, yes (1) or no (0). Default is yes
%params.PCR.AdditionalPCR: perform additional PCR, yes (1) or no (0).Default is no
                           % also needs to normalize PCA components, see params.normalizazion  

%params.PCR.Method: which PCR to perform. Default is ExplainedVar
            % 'FixedComp' : Like Ingmar did, choose  n fixed amount of parameters, e.g. n = 71
            % 'MinCompPCR'  Choose Minimum of Fatures and Predictors, * n , e.g. n = 0.85
            % 'ExplainedVar' Take all component that explain more than n amount an variance, e.g. n = 0.1
            % 'CumulativeVar' Take all components until n of summed variance is explained, e.g. n = 0.99
%params.PCR.Methodfactor: depending on which method we choose, it can be 71,0.85, 0.1, 0.99..... see explanation before



% varargin:  can be added, but must not be
%             CurrSubsamples: nSubsamples*subSampleDuration*1, needed if no RDM provided
%             Autocorrborder: For PCR necessary. A vector of nmodel x 1 where the number is the sample for the border



%% OUTPUT
%dRSAmat: array with dimensions nTimepoints x nTimepoints x nModels = dRSA matrix for each Model

% TODO:
%also add RDMs as output so they can be saved? Use varagout for optional output, depending on what is needed

%% Input Parsing
p = inputParser;
addParameter(p, 'CurrSubsamples', [], @(x) isnumeric(x));
addParameter(p, 'Autocorrborder', [], @(x) isnumeric(x));

parse(p, varargin{:});

CurrSubsamples = p.Results.CurrSubsamples;   %if not added, take it here
Autocorrborder = p.Results.Autocorrborder;   %if not added, take it here


%% Some Default Options
% defaultParams.autocorrelation = 0;
defaultParams.modelNames = cellfun(@(x) ['Model' num2str(x)], num2cell(1:numel(model)), 'UniformOutput', false);
defaultParams.neuralDistMeasure = 'correlation';
defaultParams.modelDistMeasure = repmat({'correlation'}, 1, numel(model));
defaultParams.dRSAtype = 'corr';

%default for the PCR. If we dont use it, we dont care for them
defaultParams.PCR.Method = 'ExplainedVar';
defaultParams.PCR.Methodfactor = 0.1;
defaultParams.PCR.AdditionalPCA = 0;
defaultParams.PCR.RegressAutocor = 1;
defaultParams.PCR.RessModel = 1;


%add them if they were not given
f = fieldnames(defaultParams);
for i = 1:numel(f)
    if ~isfield(params, f{i})
        params.(f{i}) = defaultParams.(f{i});
    elseif isstruct(defaultParams.(f{i}))
        % Check subfields recursively
        subf = fieldnames(defaultParams.(f{i}));
        for j = 1:numel(subf)
            if ~isfield(params.(f{i}), subf{j})
                params.(f{i}).(subf{j}) = defaultParams.(f{i}).(subf{j});
            end
        end
    end
end

clearvars defaultParams

%warning for PCR
if strcmp(params.dRSAtype, 'PCR') && params.PCR.RegressAutocor == 0 && params.PCR.RessModel == 0
    error('PCR calculation is not possible if both RegressAutocor and RessModel are 0. You need to regress something out.');
end



%% Choose RDMs

%if we use PCR and have models to regress out we also need to calculate the RDM for them
if strcmp(params.dRSAtype, 'PCR') && isfield(params, 'modeltoRegressout')
    modelsToRegress = [params.modeltoRegressout{:}];  % Flatten the cell array
else
    modelsToRegress = [];
end

%if cell, transform to array
if iscell(params.modelToTest)
    params.modelToTest = [params.modelToTest{:}];  % flatten cell into numeric array
end



% add them all together to know for which models we create the RDMs
allModels =  unique([params.modelToTest, modelsToRegress]);


clearvars modelsToRegress

%% RDM calculation


% First we check the dimensions to see if it is RDMs or not
isY_RDM = ~isempty(Y) && ndims(Y) == 3;
isModel_RDM = iscell(model) && all(cellfun(@(x) isempty(x) || ndims(x) == 3, model));

%if subsamples not provided, complain here
if ~(isY_RDM && isModel_RDM) && isempty(CurrSubsamples)
    error(['CurrSubsamples must be provided when computing RDMs from raw data.']);
else
    %first we drop the last useless singleton dimension
    CurrSubsamples = reshape(CurrSubsamples, size(CurrSubsamples,1), size(CurrSubsamples,2));
end



%%in case we want to have the autocorrelation we only calculate it one time
if iscell(model) && numel(model) == 1 && isequal(model{1}, Y) && strcmp(params.dRSAtype, 'corr')
    disp('Calculating autocorrelation');
    DistMeasure = params.modelDistMeasure; % create RDMs with model distance measure choosen
    singleRDM  = dRSA_computeRDM(Y, params, CurrSubsamples, DistMeasure); % params.neuralDistMeasure = type of dist measure
    
    %for later
    params.Autocorr = 1;
    
else
    % is neural RDM given?
    if isY_RDM
        %         nRDM = neuralRDM;
        %          nRDM = squareform(neuralRDM);
        % TO be added by Ingmar
    else    %if not, calculate neural RDM
        DistMeasure = params.neuralDistMeasure;
        nRDM = dRSA_computeRDM(Y, params, CurrSubsamples, DistMeasure); % params.neuralDistMeasure = type of dist measure
    end %of nRDM
    
    
    if isModel_RDM    %In case we provide a model RDM, we have them already added here:
        %         mRDM = modelRDMs(allModels);
        %             mRDM = squareform(model);
        % TO be added by Ingmar
        
    else %if not, we calculate it ourselfes
        
        for iModel = allModels  %we are calculating it for each model
            DistMeasure = params.modelDistMeasure{iModel};
            
            mRDM{iModel} = dRSA_computeRDM(model{iModel}, params, CurrSubsamples, DistMeasure); % mRDM should remain empty for the Models we do
            % not want so that we do not lose track of which model are which later in the PCR
        end
    end %of mRDM
    
    
end % of autocorrelation


clearvars model CurrSubsamples Y DistMeasure iModel 

%% dRSA


if strcmp(params.dRSAtype, 'corr')
    
    %if we want autocorrelation
    if isfield(params, 'Autocorr') && params.Autocorr == 1
        params.modelToTest = 1; %we only test that one input
        dRSAmat = dRSA_corr({singleRDM},singleRDM,params);
        
    else  %if we want normal dRSA
        dRSAmat = dRSA_corr(mRDM, nRDM, params);
    end
elseif strcmp(params.dRSAtype, 'PCR')
    
    % border should be provided beforehand
    % reminder to normalize the RDMS in dRSA_computeRDM beforehand!
    
    %then we do the PCR
    dRSAmat = dRSA_PCR(mRDM,nRDM, Autocorrborder, params);
    
end

end
