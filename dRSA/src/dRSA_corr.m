function [dRSAmat] = dRSA_corr(mRDM, nRDM, params)

%% INPUT:
%mRDM: cell array with each cell having events x time, some of them empty (we ignore those) 
%nRDM: array with events x time
%params.modelToTest: array of models to test

%% OUTPUT: 
%dRSAmat: array with dimensions nTimepoints x nTimepoints x nModels = dRSA matrix for each Model


%%  correlation-based dRSA
iMod = 0;
nTimepoints = size(nRDM,2);  %how many Time Points?
nModels = length(params.modelToTest);  %how many models?

dRSAmat = zeros(nTimepoints, nTimepoints, nModels); %preallocate

for iModel = params.modelToTest
    iMod = iMod+1;
    dRSAmat(:,:, iMod)  = corr(mRDM{iModel},nRDM);  % dRSA; x:model, y:neural
end


end