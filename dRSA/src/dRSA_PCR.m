function dRSAmat = dRSA_PCR(mRDM,nRDM, Autocorrborder, params)

%% INPUT:
%mRDM: cell array with each cell having events x time, some of them empty (we ignore those)
%nRDM: array with events x time
%Autocorrborder: A vector of nmodel x 1 where the number is the sample for the border

% params.modelToTest: array of models to test e.g. = [ 1 4 5]
% params.modeltoRegressout: cell of models, that are not tested, but only regressed out.
% In each cell, we have a vector of modelsls e.g.  {4 5} {1 3} {1 2};
%this cell array should align with modeltoTest So for each model that gets tested, we have here a cell that fits
%e.g.  params.modelToTest = [ 1 4 5] -- params.modeltoRegressout = {4 5} {1 3} {1 2}; for those three models

% ----------------Parameters specific for PCR----------------------------

%params.PCR.RegressAutocor: Regress out Autocorrelation, yes (1) or no (0). Default is yes
%params.PCR.RessModel: Regress out other models, yes (1) or no (0). Default is yes

%params.PCR.AdditionalPCA: perform additional PCA, yes (1) or no (0). Default is no
%if yes, specify also % params.normalizazion = 'Standardize' or 'Rescale'.
%Default is 'Standardize'

%params.PCR.Method: which PCR to perform.
% 'FixedComp' : Like Ingmar did, choose  n fixed amount of parameters, e.g. n = 71
% 'MinCompPCR'  Choose Minimum of Fatures and Predictors, * n , e.g. n = 0.85
% 'ExplainedVar' Take all component that explain more than n amount an variance, e.g. n = 0.1
% 'CumulativeVar' Take all components until n of summed variance is explained, e.g. n = 0.99
%params.PCR.Methodfactor: depending on which method we choose, it can be 71,0.85, 0.1, 0.99..... see explanation before



%% OUTPUT:
%dRSAmat: array with dimensions nTimepoints x nTimepoints x nModels = dRSA matrix for each Model


%% Preparation
iMod = 0;
nModels = length(params.modelToTest);
nTimePoints = size(nRDM,2);

dRSAmat = zeros(nTimePoints,nTimePoints,nModels);

%in case additional PCA, but no method specified
if isfield(params.PCR, 'AdditionalPCA') && isequal(params.PCR.AdditionalPCA, 1)&& ~isfield(params, 'normalization')
    params.normalization = 'Standardize';  %add a default version if we do PCR, just in case
end



%% dRSA loop

%First we loop through (1) each model we want to test
for iModel = params.modelToTest
    iMod = iMod+1;
    fprintf('\n Model: %04d ',iModel);
    
    
    %Load models to be excluded
    models2regressout = params.modeltoRegressout{iMod};
    
    
    % then (2) we loop through all time points
    for iT = 1:nTimePoints
        
        % define our current model
        XTest = mRDM{iModel}(:,iT); %our Model, all features, at time point iT
        
        
        %% A) Regressout Autocorrelation outside the regression border
        
        if params.PCR.RegressAutocor && ~isnan(Autocorrborder(iModel))
            %the regborder can be NaN, then nothing gets regressed out
            regborder = Autocorrborder(iModel);
            
            LeftSide = iT - params.AverageTime*params.fs : iT - params.AverageTime*params.fs + regborder ;
            RightSide = iT + params.AverageTime*params.fs - regborder : iT + params.AverageTime*params.fs;
            
            Autocorrelation_indexes = [LeftSide  RightSide];
            Autocorrelation_indexes(logical((Autocorrelation_indexes<1) + (Autocorrelation_indexes > nTimePoints))) = [];
            
            xAutocorrelation = mRDM{iModel}(:,Autocorrelation_indexes );  %our model to test, at time points to regress out
            
            
            %% If Additional PCA is wanted
            if isfield(params.PCR, 'AdditionalPCA') && isequal(params.PCR.AdditionalPCA, 1)  %if we have large models, we perform a second PCA beforehand
                [~, score, ~, ~, exp, ~] = pca(xAutocorrelation);
                imax = sum(exp>.1); %only the first with a high explained variance
                xAutocorrelation  = score(:,1:imax); %reduce only to most important components
            end
            
            
        else  %if we do not want to regress out the autocorrelation
            xAutocorrelation = [];
        end
        
        %% B) Regress out other Models at all time points
        
        if params.PCR.RessModel
            regressout_indexes = iT - params.AverageTime*params.fs : iT + params.AverageTime*params.fs;           % for averaging across time we need the indexes
            regressout_indexes(logical((regressout_indexes<1) + (regressout_indexes > nTimePoints ))) = []; %Delete indexes outside our sample
            
            
            xModelRegressout = zeros(size(mRDM{iModel},1), 5000); % %prepare matrix for PCA and fill it with our data
            %comment: 5000 is just in case, we delte what is too much later
            
            %now for loop for models to regress out
            for iReg = models2regressout
                Regressmodel = mRDM{iReg}(:, regressout_indexes);  %we take the other
                
                %% If Additional PCA is wanted
                if isfield(params.PCR, 'AdditionalPCA') && isequal(params.PCR.AdditionalPCA, 1) %if we have large models, we perform a second PCA beforehand
                    [~, score, ~, ~, exp, ~] = pca(Regressmodel);
                    imax = sum(exp>.1); %only the first with a high explained variance
                    Regressmodel  = score(:,1:imax); %reduce only to most important components
                end
                
                Index_NewData = nnz(xModelRegressout(1,:)); %Index where to add our new data to
                xModelRegressout(:, Index_NewData + 1 : Index_NewData + size(Regressmodel, 2) ) = Regressmodel;
            end
            
            %now delete the 0s we do not need
            NotZeros = nnz(xModelRegressout(1,:));
            xModelRegressout = xModelRegressout(:,1:NotZeros);
            
            
        else  %if we do not want to regress out other models
            
            xModelRegressout = [];
            
        end
        
        %% C) Prepare PCA
        
        %first we join both matrixes
        xRegressout = [xModelRegressout xAutocorrelation];
        
        
        %if we did the additional PCA, we need to normalize the data beforehand
        if isfield(params.PCR, 'AdditionalPCA') && isequal(params.PCR.AdditionalPCA, 1)   %if we have large models, we perform a second PCA beforehand
            %normalize data here. 
            if strcmp(params.normalization, 'Standardize')
                xRegressout = dRSA_standardizeRDM (xRegressout);
            elseif strcmp(params.normalization, 'Rescale')
                xRegressout = dRSA_rescaleRDM (xRegressout);
            else
                error('Unknown Normalization method');
            end
        end
        
        
        clearvars NotZeros Index_NewData Regressmodel regressout_indexes LeftSide RightSide Autocorrelation_indexes ResizedModel RescaledModel;
        
        %Nowe put it together with our model we are actually interested in
        %huge matrix with nFeatures x nPredictors. The first column is the model we want to test, then columns for the Models we
        %want to regress out, then columns for the autocorrelation
        Xx = [XTest xRegressout];
        
        
        [nFeature, nPredictors] = size(Xx);

        
        %% D) PCA
        %  1) First we run a PCA is run on X, resulting in the PCAscores (components)
        %Now, this depends on WHAT kind of PCA we want to do. Choose one of the options above
        
        
        if strcmp(params.PCR.Method,'FixedComp')
            [PCALoadings,PCAScores,~,~,explained] = pca(Xx,'NumComponents',params.PCR.Methodfactor);
            
        elseif strcmp(params.PCR.Method,'MinCompPCR')
            
            %to get the minimum amount of features
            MinComp = min(nFeature,nPredictors);
            MinComp = floor(params.PCR.Methodfactor*MinComp);
            [PCALoadings,PCAScores,~,~,explained] = pca(Xx,'NumComponents',MinComp);
            
            
            if MinComp > size(explained,1)  %in case we take all components
                MinComp = size(explained,1);
            end
            
            
        elseif strcmp(params.PCR.Method,'ExplainedVar')
            [PCALoadings,PCAScores,~,~,explained] = pca(Xx);
            imax = sum(explained>params.PCR.Methodfactor); %only the first with a high explained variance
            
            if imax >= nFeature
                error('More Predictors than observations.  This will lead to overfitting.')
            end
            
            PCAScores  = PCAScores(:,1:imax); %reduce only to most important components
            PCALoadings = PCALoadings(1,1:imax);
            
            
        elseif strcmp(params.PCR.Method,'CumulativeVar')
            [PCALoadings,PCAScores,~,~,explained] = pca(Xx);
            threshold = params.PCR.Methodfactor *  sum(explained);
            imax = find(cumsum(explained) >= threshold, 1);
            
            if imax >= nFeature
                error('More Predictors than observations.  This will lead to overfitting.')
            end
            
            PCAScores  = PCAScores(:,1:imax); %reduce only to most important components
            PCALoadings = PCALoadings(1,1:imax);
            
        end
        
        %now we have the PCAscores
        
        %% Regression
        % 2) We use these scores as predictor variables in a least-squares regression, with our neural RDM as response variable
        betaPCR = PCAScores\(nRDM);  % The \ operator performs a least-squares regression to calculate the slopes or regression coefficient
        
        
        % 3) the principal component regression weights (betaPCR) are projected back onto the original variable space using the PCA loadings,
        %    to extract a single regression weight corresponding to the original X
        
        temporarydRSA = PCALoadings*betaPCR;
        
        % 4) Select the first weight, which corresponds to XTest. The others represent xRegressout and xAutocorrelation
        
        dRSAmat(iT,:,iMod) = temporarydRSA(1,:)';

        
    end %of iTime
end %of iModel


end