function cfg = cairo_dataset()
% CAIRO_DATASET  Cairo recordings: EDF, 500 Hz, 19 EEG (10-20) + ECG + X/Y/Z.
%
%   run_preprocessing('config/cairo_dataset.m')
%
% Only the raw .edf files are read; the .mat files next to them hold an
% earlier, already cleaned version and are ignored.

root = fileparts(fileparts(mfilename('fullpath')));
d    = prep_config();

cfg.inDir   = fullfile(root, 'data', 'Cairo_Dataset');
cfg.outDir  = fullfile(root, 'derivatives', 'cairo_dataset');
cfg.fileExt = '*.edf';

cfg.lineFreq = 50;     % Egyptian mains
cfg.reref    = [];     % average reference (before ICA and after interpolation)
cfg.lp=70;
% Zapline-plus leaves about 10 dB of 50 Hz (plus a burst on F8) in
% i01_MANCAVA; with lp = 70 the residue stays in the band without a notch.
cfg.lineNotch = true;

% X, Y, Z are accelerometer channels. ECG is kept aside by the default
% cfg.ecgChannels and used by the cardiac component rule.
cfg.nonEEG = [d.nonEEG, {'X', 'Y', 'Z'}];

% 19 channels: the default 10% allows a single bad one. i01_MANCAVA has 5
% (O2 dropout, poor contact on T8/P3, P8/P7 borderline); check the
% raw_figures before trusting a file near this limit.
cfg.maxBadFrac = 0.30;

% Restore the full 19-channel montage, then average again.
cfg.interpolate = true;
end
