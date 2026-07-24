function dRSA_diagonal = dRSA_average(dRSA, params)

%% INPUT:
% params.AverageTime = 2; %in s what to average across
% %dRSA: array with dimensions nTimepoints x nTimepoints x nModels = dRSA matrix for each Model we wanted to test


%% OUTPUT
% dRSA_diagonal:  model x timevec


%% Preparation
nModels = size(dRSA,3);
nTimePoints = size(dRSA,1);
tRange = (params.AverageTime * params.fs);
nAveragedTimePoints =  (params.AverageTime * params.fs )*2+1;
rstack = zeros(nModels, nTimePoints, nAveragedTimePoints); %preallocate


%% average across the time diagonal
for iModel = 1:nModels
    for iModelTime = 1:nTimePoints
        timeindex = iModelTime - tRange:iModelTime + tRange;  % Get the index of our time window
        OutsideSample = logical((timeindex < 1) + (timeindex > nTimePoints));  % Outside of our subsample
        timeindex(OutsideSample) = 1; % Remove indices that are before or after the sample

        slice = dRSA(iModelTime, timeindex, iModel); % Slice of our time over which we average
        slice = reshape(slice, size(slice, 1), []);  % Reshape to N x nAveragedTimePoints
        slice( :, OutsideSample) = NaN; % Remove indices that are outside our sample

        rstack(iModel, iModelTime, :) = slice;
    end %of iModelTime
end %of iModel


%we average across the ModelTime
dRSA_temp1 = nanmean(rstack,2);
dRSA_diagonal =  reshape(dRSA_temp1, [size(dRSA_temp1,1), size(dRSA_temp1,3)]);  %we cannot squeeze in case we have other singleton dimensions



end