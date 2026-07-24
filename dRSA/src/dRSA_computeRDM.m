function RDM = dRSA_computeRDM (data, params, CurrSubsamples, DistMeasure)

% function for calculating RDMS

%% INPUT
%data in format features x time
%DistMeasure: type of dist measure
% CurrSubsamples: a matrix of nSubsamples*subSampleDuration
%params


%% OUTPUT
% matrix in format events x time





%% calculate RDM
nTimePoints = size(CurrSubsamples,2);
nFeatures = size(CurrSubsamples,1) * (size(CurrSubsamples,1) - 1) / 2;
RDM = zeros(nFeatures, nTimePoints);

for iTime = 1:nTimePoints
    if  strcmp(DistMeasure, 'correlation')
        RDM(:,iTime) = dRSA_fastpdist (data(:, CurrSubsamples(:,iTime))', DistMeasure);
    else
        RDM(:,iTime) = pdist(data(:, CurrSubsamples(:,iTime))', DistMeasure);
    end
end



%% Normalization

if isfield(params, 'normalization') || strcmp(params.dRSAtype, 'PCR')

    %BEFORE DOING PCR:  all the RDMS should have been normalized here and centered
    if ~isfield(params, 'normalization') && strcmp(params.dRSAtype, 'PCR')
        params.normalization = 'Standardize';  %add a default version if we do PCR
    end

    if strcmp(params.normalization, 'Standardize')
        RDM = dRSA_standardizeRDM (RDM);
    elseif strcmp(params.normalization, 'Rescale')
        RDM = dRSA_rescaleRDM (RDM);
    else
        error('Unknown Normalization method');
    end


    %maybe again call here a new function for normalizing and centering
    %this funciton can be used in dRSA_PCR

end

end