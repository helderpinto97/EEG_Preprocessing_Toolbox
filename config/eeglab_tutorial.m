function cfg = eeglab_tutorial()
% EEGLAB_TUTORIAL  Settings for the EEGLAB tutorial dataset (eeglab_data.set).
%
%   run_preprocessing('config/eeglab_tutorial.m')
%
% An example of why the defaults are a starting point. Two of them are wrong
% for this recording:
%
%   srate    The file is sampled at 128 Hz. The default of 250 would
%            upsample it, which adds no information, enlarges the file and
%            interpolates samples that were never measured. [] leaves the
%            rate alone.
%
%   lineFreq The recording is from UCSD, so mains is 60 Hz, not the 50 Hz
%            default. With cfg.lp = 45 the low-pass removes most of it
%            anyway, but the setting should describe the data.
%
% 32 channels, of which EOG1 and EOG2 are ocular and dropped by prep_noneeg,
% leaving 30 EEG channels. Electrode coordinates are already in the file, so
% no template lookup is needed.

root = fileparts(fileparts(mfilename('fullpath')));
cfg.inDir    = fullfile(root, 'lib', 'toolboxes', 'eeglab', 'sample_data');
cfg.outDir   = fullfile(root, 'derivatives', 'eeglab_tutorial');
cfg.fileExt  = 'eeglab_data.set';

cfg.srate    = [];      % keep 128 Hz; do not upsample
cfg.lineFreq = 60;      % UCSD recording

% 30 EEG channels, so the 10% default allows only 3 bad ones. Real data
% often exceeds that. Raise it here and read chans_rejected in the QC log,
% rather than having the file skipped.
cfg.maxBadFrac = 0.20;
end
