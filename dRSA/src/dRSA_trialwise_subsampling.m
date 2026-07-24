function [SSIndices, SSIndicesPlot, usedIterations] = dRSA_trialwise_subsampling(maskSubsampling, maskTrial, opt)
% dRSA_trialwise_subsampling - Random subsampling selecting at most one subsample per trial
%
% INPUTS:
%   maskSubsampling : 1×N logical vector (true = available, false = unavailable)
%   maskTrial       : 1×N integer vector indicating trial ID for each point (1..nTrials)
%   opt.SubSampleDur: number of points per subsample
%   opt.spacing     : spacing between subsamples (in points)
%   opt.nSubSamples : number of subsamples per iteration
%   opt.nIter       : number of iterations (repetitions)
%   opt.checkRepetition (optional): true/false (default = true)
%
% OUTPUTS:
%   SSIndices      : [nSubSamples × SubSampleDur × nIter] matrix of indices
%   SSIndicesPlot  : [nIter × N] logical mask of selected points (for visualization)
%   usedIterations : number of successfully generated unique iterations
%
% -------------------------------------------------------------------------

%% --- Parameter setup ---
if nargin < 3
    error('Usage: dRSA_trialwise_subsampling(maskSubsampling, maskTrial, opt)');
end
if ~islogical(maskSubsampling)
    error('maskSubsampling must be logical.');
end
if numel(maskSubsampling) ~= numel(maskTrial)
    error('maskSubsampling and maskTrial must have the same length.');
end

% Defaults
if ~isfield(opt, 'checkRepetition'), opt.checkRepetition = true; end
if ~isfield(opt, 'spacing'), opt.spacing = 0; end

SubSampleDur = opt.SubSampleDur;
spacing      = opt.spacing;
nSubSamples  = opt.nSubSamples;
nIter        = opt.nIter;
checkRepetition = opt.checkRepetition;

trialIDs = unique(maskTrial(~isnan(maskTrial)));
nTrials = numel(trialIDs);

if nSubSamples > nTrials
    error('Not enough trials available for the requested number of subsamples.');
end

N = numel(maskSubsampling);
rng('shuffle');

%% --- Step 1: Compute valid start positions per trial ---
trialStarts = cell(nTrials,1);
for t = 1:nTrials
    idx = (maskTrial == trialIDs(t));
    trialMask = maskSubsampling(idx);
    trialIndices = find(idx);
    localValid = find(conv(double(trialMask), ones(1, SubSampleDur), 'valid') == SubSampleDur);
    trialStarts{t} = trialIndices(localValid);
end

%% --- Step 2: Initialize outputs ---
SSIndices = nan(nSubSamples, SubSampleDur, nIter);
SSIndicesPlot = false(nIter, N);
usedIterations = 0;

if checkRepetition
    seen = containers.Map('KeyType','char','ValueType','logical');
    repeatedCount = 0;
    repeatedSubsequent = 0;
end

%% --- Step 3: Iterative subsampling ---
for iter = 1:nIter
    success = false;
    attempt = 0;
    maxAttempts = 5000;

    while ~success && attempt < maxAttempts
        attempt = attempt + 1;

        % Randomly choose trials (without replacement)
        selectedTrials = trialIDs(randperm(nTrials, nSubSamples));

        selectedStarts = zeros(1, nSubSamples);
        for s = 1:nSubSamples
            startsThisTrial = trialStarts{trialIDs == selectedTrials(s)};
            if isempty(startsThisTrial)
                continue;
            end
            selectedStarts(s) = startsThisTrial(randi(length(startsThisTrial)));
        end

        % Ensure all subsamples have valid starts
        if all(selectedStarts)
            selectedStarts = sort(selectedStarts);

            % Repetition control
            if checkRepetition
                if repeatedSubsequent >= 100
                    warning('Iteration %d: No unique iteration found on 100 attempts. Ending subsampling...', iter);
                    break
                end

                key = mat2str(selectedStarts);
                if isKey(seen, key)
                    repeatedCount = repeatedCount + 1;
                    repeatedSubsequent = repeatedSubsequent + 1;
                    continue;
                else
                    seen(key) = true;
                    repeatedSubsequent = 0;
                end
            end

            % Compute indices for each subsample
            for s = 1:nSubSamples
                SSIndices(s,:,iter) = selectedStarts(s) + (0:SubSampleDur-1);
            end

            % Visualization mask
            idxAll = SSIndices(:,:,iter);
            SSIndicesPlot(iter, idxAll(:)) = true;

            usedIterations = usedIterations + 1;
            success = true;
        end
    end

    if ~success
        warning('Iteration %d: Could not find valid non-overlapping subsamples after %d attempts. Ending subsampling...', ...
            iter, maxAttempts);
        break;
    end
end

fprintf('\nGenerated %d unique trialwise subsampling iterations (requested %d)\n', usedIterations, nIter);

if checkRepetition
    if repeatedCount > 0
        fprintf('Note: %d duplicate iterations were skipped due to repetition.\n', repeatedCount);
    else
        fprintf('No duplicate iterations detected.\n');
    end
end

end
