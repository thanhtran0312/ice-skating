function D = dRSA_fastpdist(X, metric)
% X: m-by-n data matrix
% metric: 'euclidean' or 'correlation'
% Output: condensed distance vector in pdist order

[m, ~] = size(X);
numPairs = m*(m-1)/2;
D = zeros(1, numPairs);

if any(isnan(X(:)))
    disp("here")
end

X = double(X); % Ensure double precision
C = corr(X');            % correlation between rows

if any(isnan(C(:)))
    disp('Zero-variance detected (e.g., black frames). Filling NaNs with 0 correlation.');
    
    % Identity should always be 1 (self-similarity)
    % Other NaNs represent 'no relationship' (correlation = 0)
    C(isnan(C)) = 0;
    for i = 1:m    %with ittseelf we have eprfect correlation, to not break it
        C(i,i) = 1;
    end
end

RDM_full = 1 - C;

% 4. Vectorize
D = squareform(RDM_full, 'tovector');
% D = squareform(1 - C);    % condensed vector in pdist order

end
