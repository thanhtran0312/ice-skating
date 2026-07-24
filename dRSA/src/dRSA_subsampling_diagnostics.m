function diagnostics = dRSA_subsampling_diagnostics(SSIndices, maskSubsampling, varargin)
% dRSA_subsampling_diagnostics
% ----------------------------------------------------------
% Combined descriptive + iteration-level overlap diagnostics
% for dRSA subsampling (continuous or trialwise mode).
%
% INPUTS:
%   SSIndices        : [nSubSamples x SubSampleDur x nIter]
%   maskSubsampling  : 1 x N logical (true = available)
%   Optional:
%     maskTrial      : 1 x N integer vector labeling trials (trialwise mode)
%
% OUTPUT:
%   diagnostics : struct with descriptive + overlap + entropy metrics
%
% Dependencies: only base MATLAB functions.
% ----------------------------------------------------------

%% --- Determine mode
if nargin > 2 && ~isempty(varargin{1})
    maskTrial = varargin{1};
    mode = 'trialwise';
else
    maskTrial = [];
    mode = 'continuous';
end

fprintf('\nRunning dRSA subsampling diagnostics (%s mode)\n', mode);
fprintf('--------------------------------------------------\n');

%% --- Basic helpers (toolbox-free)
sumNoNan   = @(x) sum(x(~isnan(x)));
nanmean_   = @(x) mean(x(~isnan(x)));
nanstd_    = @(x) std(x(~isnan(x)));
nanmedian_ = @(x) median(x(~isnan(x)));

%% ==========================================================
%  MASK DESCRIPTIVES
% ==========================================================
maskDesc = struct();
N = numel(maskSubsampling);
maskDesc.totalPoints = N;
maskDesc.nAvailable = sum(maskSubsampling);
maskDesc.nUnavailable = N - maskDesc.nAvailable;
maskDesc.propAvailable = maskDesc.nAvailable / N;

availDiff = diff([false, maskSubsampling(:).', false]);
availStarts = find(availDiff == 1);
availEnds   = find(availDiff == -1) - 1;
availSegLengths = availEnds - availStarts + 1;

unavailDiff = diff([true, maskSubsampling(:).', true]);
unavailStarts = find(unavailDiff == -1);
unavailEnds   = find(unavailDiff == 1) - 1;
unavailSegLengths = unavailEnds - unavailStarts + 1;

maskDesc.nAvailableSegments = numel(availSegLengths);
maskDesc.nUnavailableSegments = numel(unavailSegLengths);

maskDesc.availSeg_mean = nanmean_(availSegLengths);
maskDesc.availSeg_std  = nanstd_(availSegLengths);
maskDesc.availSeg_min  = min(availSegLengths);
maskDesc.availSeg_max  = max(availSegLengths);

maskDesc.unavailSeg_mean = nanmean_(unavailSegLengths);
maskDesc.unavailSeg_std  = nanstd_(unavailSegLengths);
maskDesc.unavailSeg_min  = min(unavailSegLengths);
maskDesc.unavailSeg_max  = max(unavailSegLengths);

%% ==========================================================
%  ITERATION-LEVEL JACCARD OVERLAP
% ==========================================================
[nS, L, nIter] = size(SSIndices);
N = numel(maskSubsampling);

% Build incidence for each iteration
iterInc = false(nIter, N);
for i = 1:nIter
    these = squeeze(SSIndices(:,:,i));
    these = these(~isnan(these)); % flatten
    iterInc(i, unique(these)) = true;
end

% Compute pairwise Jaccard (intersection/union)
allJacc = [];
for i = 1:nIter-1
    for j = i+1:nIter
        inter = sum(iterInc(i,:) & iterInc(j,:));
        uni   = sum(iterInc(i,:) | iterInc(j,:));
        if uni == 0
            J = NaN;
        else
            J = inter / uni;
        end
        allJacc(end+1,1) = J; %#ok<AGROW>
    end
end

% summary stats
meanJacc = nanmean_(allJacc);
medianJacc = nanmedian_(allJacc);
pctHighJacc = 100 * sum(allJacc > 0.5) / numel(allJacc);

% plot histogram
figure('Units','inches','Position',[1 1 5 3]);
histogram(allJacc, 30);
xlabel('Jaccard overlap between iterations');
ylabel('Count');
title('Distribution of iteration-level overlaps');
grid on;

%% ==========================================================
%  EFFECTIVE COVERAGE
% ==========================================================
coveredPts = any(iterInc, 1);
effectiveCoverage = sum(coveredPts & maskSubsampling) / sum(maskSubsampling);

%% ==========================================================
%  START-POINT ENTROPY + VISUALIZATION
% ==========================================================
startCounts = zeros(1, N);
for i = 1:nIter
    for s = 1:nS
        idx = SSIndices(s,1,i);
        if ~isnan(idx)
            startCounts(idx) = startCounts(idx) + 1;
        end
    end
end

% normalize
if sum(startCounts) > 0
    p = startCounts / sum(startCounts);
    startEntropy = -sumNoNan(p(p>0) .* log(p(p>0))) / log(sum(maskSubsampling));
else
    startEntropy = NaN;
end

% visualize start density over mask
normDensity = startCounts / max(startCounts + eps);
colorMap = hot(256);
colorData = zeros(N,3);
for t = 1:N
    if ~maskSubsampling(t)
        colorData(t,:) = [0 0 0]; % unavailable
    else
        cIdx = max(1, round(normDensity(t)*255));
        colorData(t,:) = colorMap(cIdx,:);
    end
end

% figure('Units','inches','Position',[1 1 10 2.5]);
% imagesc(permute(colorData, [1 3 2]));
% axis tight; axis off;
% title('Start-point density (color = frequency, black = unavailable)');
% colorbar('Ticks',[0 1],'TickLabels',{'Low','High'});

%% ==========================================================
%  PACKAGE RESULTS
% ==========================================================
diagnostics = struct();
diagnostics.mode = mode;
diagnostics.mask = maskDesc;
diagnostics.meanJaccard = meanJacc;
diagnostics.medianJaccard = medianJacc;
diagnostics.pctHighJaccard = pctHighJacc;
diagnostics.allJaccard = allJacc;
diagnostics.effectiveCoverage = effectiveCoverage;
diagnostics.startEntropy = startEntropy;
diagnostics.startCounts = startCounts;

%% ==========================================================
%  PRINT SUMMARY
% ==========================================================
fprintf('Mask descriptives:\n');
fprintf('  %d total points, %.1f%% available (%d segments)\n', ...
    maskDesc.totalPoints, 100*maskDesc.propAvailable, maskDesc.nAvailableSegments);
fprintf('  Available segs: mean %.1f (min %d, max %d)\n', ...
    maskDesc.availSeg_mean, maskDesc.availSeg_min, maskDesc.availSeg_max);
fprintf('  Unavailable segs: mean %.1f (min %d, max %d)\n', ...
    maskDesc.unavailSeg_mean, maskDesc.unavailSeg_min, maskDesc.unavailSeg_max);

fprintf('Iteration-overlap diagnostics:\n');
fprintf('  Mean Jaccard %.3f | Median %.3f | High-overlap pairs %.2f%%\n', ...
    meanJacc, medianJacc, pctHighJacc);
fprintf('Effective coverage: %.2f%% of available points\n', 100*effectiveCoverage);
fprintf('Start-point entropy (normalized 0..1): %.3f\n', startEntropy);
fprintf('--------------------------------------------------\n\n');

end
