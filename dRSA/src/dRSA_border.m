function border  = dRSA_border (model, subsamples, params)


%% INPUT:
% model: 1*nModels cell arrray (also used for regress out models, automatically regresses out other models)
% subsamples: nSubsamples*subSampleDuration*nIter

% params.modelToTest = [ 1 4 5]  or can be a cell {1 4 5}
% params.AverageTime = 2; %in s 
% params.Var % how much variance
% params.AverageTime %used for calculating the border for that Interval

%% OUTPUT
%border:  In samples the distance from which we regress out our own model
%the rest that we are not interested in is NaN

%% Preparation
border = NaN(length(model), 1);
regvalue = sqrt(params.Var ); %apparently, explains 10% of variance ?
%We identify 

%if cell, transform to array
if iscell(params.modelToTest)
    params.modelToTest = [params.modelToTest{:}];  % flatten cell into numeric array
end
%% Autocorrelation
% First we calculate the autocorrelation for all the models
%we can use the core function for calculating that
params.modelDistMeasursaved = params.modelDistMeasure; % save it for later 


for iModel = params.modelToTest
    
    for iIter = 1:params.nIter
        CurrSubsamples = subsamples(:,:,iIter); % subsamples is nSubsamples*subSampleDuration*iterations
        params.dRSAtype = 'corr';
        if mod(iIter, 50) == 0 || iIter == 1
            fprintf('  Iteration %d\n', iIter);
        end
        params.modelDistMeasure = params.modelDistMeasursaved {iModel}; 
        dRSAma = dRSA_coreFunction (model{iModel}, {model{iModel}}, params, 'CurrSubsamples', CurrSubsamples); %get autocorrelation
        dRSA_Iter(iIter,:,:,:) = dRSAma;
    end
    
    dRSA = mean(dRSA_Iter ,1); % 1 = Fmean across first dim
    dRSA = reshape(dRSA, size(dRSA,2), size(dRSA,3));  %remove singleton dimensions
    
    mRSA(:, :, iModel) = dRSA;  %we leave those we do not want empty!
    
end % of iModel



%% Average across time
Averaged_Autocorr = dRSA_average(mRSA, params); 
%output: model x timevec

%% Identify borders

%find where Lag = 0
[~, Lag0] = max(Averaged_Autocorr, [], 2);


for iModel = params.modelToTest
    peak = max(Averaged_Autocorr(iModel,:));  %the highest autocorrelation for this model

    %Define the left and right side of the peak
    LeftSide = squeeze(Averaged_Autocorr(iModel,1:Lag0(iModel)));
    RightSide = squeeze(Averaged_Autocorr(iModel,Lag0(iModel):end));
    
    %find the regression borders where less than xx% of variance has been explained
    LeftBorder = find((LeftSide) < regvalue*peak,1, 'last');  %flip to find the first from the left side
    RightBorder = length(RightSide) - find((RightSide) < regvalue*peak, 1, 'first');
    
    border(iModel, :) = ceil(nanmean([LeftBorder RightBorder ])); %take the average
    
     if isnan(border(iModel,:))
        fprintf('ERROR: For Model "%d" the regression border could not be calculated! \n', iModel);
    end
end






end