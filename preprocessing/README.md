the meg preprocessing pipeline for this dataset: 

1. maxfilter
2. highpass filter at 0.01Hz
3. cut from the beginning of the run to the end of a run
4. detrend across trials of a run
5. annotate muscle artefacts between 110-140Hz
6. ica
7. epoch trials
