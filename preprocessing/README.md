the meg preprocessing pipeline for this dataset: 
each subject goes through 6 runs, where each run has 6 trials, each trial showing one stimulus video. so each run shows 6 unique videos, but the videos repeat for other runs for one subject.

1. maxfilter
2. highpass filter at 0.01Hz
3. cut from the beginning of the run to the end of a run
4. detrend across trials of a run
5. annotate muscle artefacts between 110-140Hz
6. ica
7. epoch trials - remove catch trials
