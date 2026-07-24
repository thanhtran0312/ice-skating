function RDM = dRSA_standardizeRDM (RDM)

%first center the model
RDM = RDM - repmat(mean(RDM,'omitnan'),size(RDM,1),1);

%standardize
RDM = RDM ./ std(RDM(:));


end