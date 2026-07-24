function [dataOut, maskOut] = dRSA_concatenate(dataIn, maskIn)
    %dRSA_CONCATENATE  Concatenate feature matrices over time and create a boundary mask.
%
%   [dataOut, maskOut] = dRSA_concatenate(dataIn)
%   [dataOut, maskOut] = dRSA_concatenate(dataIn, maskIn)
%
% DESCRIPTION
%   Produces a single features×time matrix by concatenating inputs along the
%   time dimension and returns/updates a "Concatenation mask" that flags the
%   boundaries between segments (0 at each boundary sample, 1 elsewhere).
%
%   Accepted input forms:
%     • Numeric 3D array  (trial × feature × time)
%         – Trials are concatenated along time. Output is feature × time.
%     • Numeric 2D array  (feature × time)
%         – Passed through (internally promoted to 1 × feature × time).
%     • Cell array of 2D numeric matrices  {feature × time, feature × time, feature × time, ...}
%         – Each cell is concatenated horizontally (along time).
%     • Cell array of .mat file paths  {'/full/path/A.mat', '/full/path/B.mat', ...}
%         – Each file must contain exactly one variable that is a 2D numeric matrix
%           of size feature × time. Files are loaded and then concatenated.
%
%   Mask handling:
%     If maskIn is provided as a struct with fields .label (cellstr) and .mask
%     (double, rows = masks types, columns = time), the function:
%       – searches for a label 'Concatenation mask';
%       – if found, throws an error (to avoid accidental overwrite);
%       – if not found, appends the new mask as a new row and adds the label 'Concatenation mask'.
%     If maskIn is missing, a new struct is created with:
%       maskOut.label = {'Concatenation mask'};
%       maskOut.mask  = maskConcat;   % 1 × time vector of 0/1 boundary flags
%
% SYNTAX
%   [dataOut, maskOut] = dRSA_concatenate(dataIn)
%   [dataOut, maskOut] = dRSA_concatenate(dataIn, maskInStruct)
%
% INPUTS
%   dataIn  : One of
%              – double array trial × feature × time
%              – double array feature × time
%              – cell array of double matrices (each feature × time, where
%              feature dimension must be consistent)
%              – cell array of char/string full paths to .mat files
%   maskIn  : (optional) struct with fields:
%              – label : 1×N cellstr of mask names
%              – mask  : N×T double, each row a mask over time
%
% OUTPUTS
%   dataOut : double, feature × time concatenation of the input segments.
%   maskOut : struct with fields:
%              – label : includes 'Concatenation mask'
%              – mask  : includes the boundary mask (zeros at concatenation
%                        boundaries, ones elsewhere). Length matches size(dataOut,2).
%
% BOUNDARY MASK DEFINITION
%   For 3D inputs (trial × feature × time), the last sample of each trial and
%   the first sample of the next trial are set to 0. The very first and very
%   last samples of the entire concatenation are set back to 1.
%   For cell inputs, the mask is 0 at each join index between matrices.
%
% SIDE EFFECTS
%   Opens a figure with two subplots:
%     (1) imagesc of dataOut (features × time)
%     (2) imagesc of the 0/1 boundary mask (gray colormap)
%
%
% ASSUMPTIONS & CONSTRAINTS
%   • All segments to be concatenated must have the same number of features
%     (rows). Time lengths may differ; concatenation aligns along columns.
%   • For .mat paths, each file must contain a single variable that is the
%     intended feature × time matrix (no name assumptions are made).

    if nargin < 1
        % nargin is number of input argument.
        % if user provides fewer than 1, throw error
        error('dRSA_concatenate:missingData', 'Input data is required.');
    end
    
    if iscell(dataIn) % check if input is cell array
        if all(cellfun(@(x) isnumeric(x) && ismatrix(x), dataIn)) 
            % For each cell in dataIn, take that element (call it x)
            % Check if it's numeric AND 2D
            % Return true/false for each cell
            disp('dataIn is a cell array of 2D matrices');            
            [dataOut, maskConcat] = concat_cellArray(dataIn); 
        elseif all(cellfun(@(x) ischar(x) || isstring(x), dataIn)) % dataIn is a cell array of .mat file paths          
            loadedData = cell(size(dataIn));
            for i = 1:numel(dataIn)
                filePath = char(dataIn{i});
                if ~isfile(filePath)
                    error('dRSA_concatenate:fileNotFound', 'File not found: %s', filePath);
                end
                tmp = load(filePath);
                % Expect each file to contain a single variable that is a numeric 2D matrix
                vars = struct2cell(tmp);
                if isempty(vars) || ~isnumeric(vars{1}) || ~ismatrix(vars{1})
                    error('File %s does not contain a valid 2D numeric matrix.', filePath);
                end
                loadedData{i} = vars{1};
            end
            [dataOut, maskConcat] = concat_cellArray(loadedData);
%             maskOut = maskConcat;
        else
            error('If dataIn is a cell array: all elements must be either 2D numeric matrices or charachter vectors representing full paths of files from where to lead the 2D numeric matrices');
        end
    elseif isnumeric(dataIn) && (ismatrix(dataIn) || ndims(dataIn) == 3) % if dataIn is a numeric 2D or 3D matrix
        disp('dataIn is a numeric 2D or 3D matrix');       
        [dataOut, maskConcat] = do_reshape(dataIn); % reshape and create mask
    else
        error('dataIn must be either a 2D/3D numeric matrix or a cell array of 2D matrices');
    end
    
        % --- Handle maskIn: create "Concatenation mask" entry ---
    if nargin < 2 || ~isstruct(maskIn) || ~all(isfield(maskIn, {'label','mask'})) % check maskIn exist and has necessary fields
        % Create new structure if maskIn not provided or invalid
        maskIn.label = {'Concatenation mask'}; % give concatenation mask label
        maskIn.mask  = maskConcat; % store mask itself
    else
        idx = find(strcmp(maskIn.label, 'Concatenation mask'), 1); % find if a 'Concatenation mask' label already exist

        if ~isempty(idx) % if it does exist already, throw and error (we don't want to overwrite by accident)
            error('maskIn contains a Concatenation mask already.')
%             maskIn.mask(idx, :) = maskConcat; % Overwrite existing mask (will error automatically if size mismatched)
        else
            % if mask structure is passed and has the right fields
            maskIn.label{end+1} = 'Concatenation mask'; % Append new label entry
            maskIn.mask(end+1, :) = maskConcat; % and the mask itself in the right place
        end
    end

    maskOut = maskIn;
    

    
    %% plot concatenated data and mask
    figure('Name', 'Concatenated data and mask', 'NumberTitle', 'off');

    subplot(2, 1, 1);
    imagesc(dataOut);
    colorbar;
    title('Concatenated output (features × time)');
    ylabel('Feature');

    subplot(2, 1, 2);
    ax1 = gca;
    imagesc(maskConcat);
    colormap(ax1,gray); 
    colorbar;
    xlabel('Time');
    title('Boundary mask');


    
 end




function [dataOut, maskConcat] = do_reshape(dataIn)

% do_concatenation: Minimal concatenation for trial*feature*time inputs.
%
%   [dataOut, maskOut] = dRSA_concatenate_V0(dataIn) concatenates a
%   3D array organised as trial*feature*time along the time dimension.
%   It is robust to the 1*feature*time case, returning the input.
%   The output data is a features*time matrix and the output mask flags 
%   concatenation boundaries by setting the last sample of each trial and 
%   the first sample of the next trial to zero.

% Examples quick tests:
% [dataOut, maskOut] = dRSA_concatenate_V0(rand(6,13,10))
% [dataOut, maskOut] = dRSA_concatenate_V0(rand(1,3,10)) % 1*features*time

    % Basic input validation to ensure the function receives the expected shapes.
    if ismatrix(dataIn)
        warning('Assuming "dataIn" to be a feature*time matrix.')
        dataIn = reshape(dataIn,[1,size(dataIn)]);
    end
    if ndims(dataIn) ~= 3
        error('dRSA_concatenate_V0:invalidData', ...
            'dataIn must be a 3D array organised as trial*feature*time.');
    end


    [nTrials, nFeatures, nTime] = size(dataIn);

    % Flatten the data so that trials are concatenated along time.
    tmp = permute(dataIn, [2, 3, 1]); % trial*feature*time -> feature*time*trial
    dataOut = reshape(tmp, nFeatures, []); %feature*time

    % Create empty mask of inputTime size
    emptyMask = ones(1,nTime);
    middleTrial = emptyMask; clear('emptyMask');
    middleTrial(1) = 0; % Insert zeros at the trial start 
    middleTrial(end) = 0; % and at the trial end
    % Replicate the mask for each trial.
    maskConcat = repmat(middleTrial, 1, nTrials); clear('middleTrial');
    maskConcat(1) = 1; % remove 0 at very start
    maskConcat(end) = 1; % remove 0 at very end

end

function [dataOut, maskConcat] = concat_cellArray(dataIn)
    % Takes cell array and return concat array and a mask of concatenation
            dataOut = cat(2, dataIn{:}); % concat arrays
            % mask when one video ends and the next begins
            widths   = cellfun(@(x) size(x,2), dataIn); % store widths
            maskConcat = ones(1,sum(widths)); % create empty mask
            startEndIdx = [cumsum(widths), cumsum(widths)+1]; % store start and end indexes
            startEndIdx = startEndIdx(1:end-1); % take out last one
            maskConcat(startEndIdx) = 0; % assign 0 to start and end    
end

% dataIn = trials x features x times = 52 x 2 x 4200
% dataOut = feature x time  = 2 x 218400