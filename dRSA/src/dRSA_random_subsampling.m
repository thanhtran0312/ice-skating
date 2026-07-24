
function [SSIndices, SSIndicesPlot, usedIterations] = dRSA_random_subsampling(maskSubsampling, opt)
% dRSA_random_subsampling - Random non-overlapping subsampling with optional repetition check
%
% INPUTS:
%   maskSubsampling : 1×N logical vector (true = available, false = unavailable)
%   opt.SubSampleDur: number of points per subsample
%   opt.spacing     : required spacing between subsamples (in points)
%   opt.nSubSamples : number of subsamples per iteration
%   opt.nIter       : number of iterations (repetitions)
%   opt.checkRepetition (optional): true/false (default = true)
%   opt.checkSpacing (optional): true/false (default = false)
%
% OUTPUTS:
%   SSIndices      : [nSubSamples × SubSampleDur × nIter] matrix of indices
%   SSIndicesPlot  : [nIter × N] logical mask of selected points (for visualization)
%   usedIterations : number of successfully generated unique iterations
%
% -------------------------------------------------------------------------
% Based on: dRSA_subsampling_V6 (Dami's original script)
% -------------------------------------------------------------------------

%% --- Parameter setup ---
if nargin < 2
    error('You must provide both maskSubsampling and opt.');
end
if ~islogical(maskSubsampling)
    error('maskSubsampling must be logical.');
end

% Default values
if ~isfield(opt, 'checkRepetition'), opt.checkRepetition = true; end
if ~isfield(opt, 'spacing'), opt.spacing = 0; end
if ~isfield(opt, 'checkSpacing'), opt.checkSpacing = false; end

SubSampleDur = opt.SubSampleDur;
spacing      = opt.spacing;
nSubSamples  = opt.nSubSamples;
nIter        = opt.nIter;
checkRepetition = opt.checkRepetition;
checkSpacing = opt.checkSpacing;

N = numel(maskSubsampling); % num_vids x num_frames my case 52*4200

rng('shuffle'); % randomize RNG for each run

%% --- Step 1: Compute valid starting positions ---
% convolve kernel size (1,250) on mask (1,218400)
validStarts = find(conv(double(maskSubsampling), ones(1, SubSampleDur), 'valid') == SubSampleDur);
if isempty(validStarts)
    error('No valid starting positions found. Check your mask or parameters.');
end

%% --- Step 2: Initialize outputs ---
SSIndices = nan(nSubSamples, SubSampleDur, nIter);
SSIndicesPlot = false(nIter, N);
usedIterations = 0;

% Optional repetition tracker
if checkRepetition
    seen = containers.Map('KeyType','char','ValueType','logical');
    repeatedCount = 0; % <-- count repeated (duplicate) iterations
    repeatedSubsequent = 0;
end

%% --- Step 3: Generate subsamples ---
for iter = 1:nIter
    success = false;
    attempt = 0;
    maxAttempts = 5000;

    while ~success && attempt < maxAttempts
        attempt = attempt + 1;
        availableStarts = validStarts;
        selectedStarts = zeros(1, nSubSamples);

        % Select each subsample start, ensuring spacing
        for s = 1:nSubSamples
            if isempty(availableStarts)
                break;
            end
            startIdx = availableStarts(randi(length(availableStarts)));
            selectedStarts(s) = startIdx;

            % Remove nearby indices (current subsample + spacing)
            excludeIdx = (startIdx - (SubSampleDur + spacing - 1)): ...
                (startIdx + SubSampleDur + spacing - 1);
            excludeIdx = excludeIdx(excludeIdx >= 1 & excludeIdx <= N - SubSampleDur + 1);
            availableStarts = setdiff(availableStarts, excludeIdx);
        end

        % Check if full set was drawn
        if all(selectedStarts)
            selectedStarts = sort(selectedStarts);

            % Optional repetition check
            if checkRepetition
                if repeatedSubsequent >= 100  % quit after 100 subsequent repetitions
                    warning('Iteration %d: No unique iteration found on 100 attempts. Ending subsampling...', ...
                        iter);
                    break
                end
                key = mat2str(selectedStarts);
                if isKey(seen, key)
                    repeatedCount = repeatedCount + 1;  % <-- count duplicate
                    repeatedSubsequent = repeatedSubsequent + 1; % count subsequent repetitions
                    continue; % skip duplicate combination
                else
                    seen(key) = true;
                    repeatedSubsequent = 0; % reet subsequent repetition tracker
                end
            end

            % Compute indices for each subsample
            for s = 1:nSubSamples
                SSIndices(s, :, iter) = selectedStarts(s) + (0:SubSampleDur-1);
            end

            % For visualization
            idxAll = SSIndices(:, :, iter);
            SSIndicesPlot(iter, idxAll(:)) = true;

            success = true;
            usedIterations = usedIterations + 1;
        end
    end

    if ~success
        warning('Iteration %d: could not find valid non-overlapping subsamples after %d attempts. Ending subsampling...', ...
                iter, maxAttempts);
        break; % stop the outer for-loop immediately
    end
end

fprintf('\nGenerated %d unique subsampling iterations (requested %d)\n', ...
        usedIterations, nIter);

%% --- Step 4: Optional start-time spacing and overlap check ---
if checkSpacing

    fprintf('\n--- Start-time spacing diagnostics ---\n');
    fprintf('SubSampleDur = %d, spacing = %d (required min start distance = %d)\n', ...
        SubSampleDur, spacing, SubSampleDur + spacing);

    minDists = nan(1, usedIterations);
    meanDists = nan(1, usedIterations);
    maxDists = nan(1, usedIterations);

    overlapViolations = false(1, usedIterations);
    spacingViolations = false(1, usedIterations);

    for iter = 1:usedIterations
        starts = squeeze(SSIndices(:,1,iter));

        if any(isnan(starts))
            continue
        end

        starts = sort(starts);
        dists  = diff(starts);

        minDists(iter)  = min(dists);
        meanDists(iter) = mean(dists);
        maxDists(iter)  = max(dists);

        % --- Rule checks
        overlapViolations(iter) = any(dists < SubSampleDur);
        spacingViolations(iter) = any(dists < (SubSampleDur + spacing));
    end

    % --- Summary statistics
    fprintf('\nStart-distance summary across %d iterations:\n', usedIterations);
    fprintf('  Minimum: %g\n', min(minDists));
    fprintf('  Mean   : %g\n', mean(meanDists, 'omitnan'));
    fprintf('  Maximum: %g\n', max(maxDists));

    % --- Overlap feedback
    if any(overlapViolations)
        fprintf('\n  OVERLAP VIOLATION detected in %d / %d iterations.\n', ...
            sum(overlapViolations), usedIterations);
        fprintf('   (Some start distances < SubSampleDur = %d)\n', SubSampleDur);
    else
        fprintf('\n  No overlap violations detected.\n');
    end

    % --- Spacing feedback
    if spacing > 0
        if any(spacingViolations)
            fprintf('\n  SPACING VIOLATION detected in %d / %d iterations.\n', ...
                sum(spacingViolations), usedIterations);
            fprintf('   (Some start distances < SubSampleDur + spacing = %d)\n', ...
                SubSampleDur + spacing);
        else
            fprintf('\n  Spacing constraint maintained in all iterations.\n');
        end
    else
        fprintf('\n  Spacing = 0 → spacing constraint not enforced.\n');
    end

    fprintf('--------------------------------------\n');
end

%% --- Step 5: Repetition warning logic ---
if checkRepetition
    if exist('repeatedCount', 'var') && repeatedCount > 0
        fprintf('Note: %d duplicate iterations were skipped due to repetition.\n', repeatedCount);
        % Arbitrary heuristic: warn if duplicates exceed 1% of requested iterations
        if repeatedCount > 0.01 * nIter
            warning('High repetition rate detected (%.2f%%). Consider revising parameters.', ...
                100 * repeatedCount / nIter);
        end
    else
        fprintf('No duplicate iterations detected.\n');
    end

    % Explicit warning if zero unique iterations found
    if usedIterations == 0
        warning(['No unique subsampling iterations could be generated.\n' ...
                 'All attempted iterations were duplicates or invalid.\n' ...
                 'Consider reducing nSubSamples, SubSampleDur, or spacing.']);
    end

else
    % Post-hoc repetition check (no impact on speed)
    allStarts = nan(nSubSamples, nIter);
    for i = 1:nIter
        if any(isnan(SSIndices(1,:,i)))
            continue
        end
        allStarts(:, i) = squeeze(SSIndices(:,1,i));
    end
    [~, uniqueIdx] = unique(allStarts.', 'rows');
    nRepetitions = nIter - numel(uniqueIdx);
    if nRepetitions > 0
        warning('Detected %d repeated iterations (%.2f%%) after sampling without repetition check.', ...
            nRepetitions, 100 * nRepetitions / nIter);
    else
        fprintf('No repeated iterations detected in post-hoc check.\n');
    end
end

end