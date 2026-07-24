function RDM = dRSA_rescaleRDM (RDM)

% rescale all RDMs to same [0 1] interval.
% Unscaled might be problematic for PCA or regression (i.e., larger scale = more variance = higher component)


ResizedModel = reshape(RDM, size(RDM, 1)* size(RDM, 2), 1); %reshape to a vector

RescaledModel = rescale(ResizedModel, 0, 1 );  %rescale

TempModel = reshape(RescaledModel, size(RDM, 1), size(RDM, 2));%put it back into the shape we need


% center the model
RDM = TempModel - repmat(mean(TempModel,'omitnan'),size(TempModel,1),1);


end