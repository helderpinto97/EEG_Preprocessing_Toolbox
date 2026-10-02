function cfg = prep_config(overrides)
% PREP_CONFIG  Pipeline parameters: the defaults, and the list of valid names.
%
%   cfg = prep_config()                 defaults
%   cfg = prep_config(struct('lp',100)) defaults with overrides applied
%   cfg = prep_config('config/my.m')    defaults with a study file applied
%
% A study file is a function returning a struct of only the fields it
% changes (see config/example_study.m). Unknown field names are rejected.

root = fileparts(fileparts(mfilename('fullpath')));

%% Paths
cfg.eeglabPath = fullfile(root, 'lib', 'toolboxes', 'eeglab');
cfg.inDir      = fullfile(root, 'data');         % raw recordings
cfg.outDir     = fullfile(root, 'derivatives');  % cleaned files
cfg.fileExt    = '*.set';                        % '*.bdf', '*.vhdr', ...

cfg.srate = [];            % target sampling rate (Hz); [] = unchanged

%% Non-EEG channels
% Whole-label patterns, case-insensitive, '*' and '?' wildcards. Mastoids
% and earlobes are left out on purpose, since they are often the reference.
cfg.nonEEG = {'*EOG*','*EMG*','*ECG*','*EKG*', ...   % ocular, muscle, cardiac
              'Status','Trigger','TRIG*','STI*', ... % event channels
              'EXG*', ...                            % BioSemi externals
              'GSR*','Erg*','Resp*','Plet','Temp'};  % BioSemi auxiliaries
cfg.nonEEGTypes = {'EOG','ECG','EKG','EMG','MISC','TRIG','STIM','AUX','REF'};  % chanlocs.type

%% Channel locations
cfg.chanlocFile    = '';   % .ced/.elp/.sfp/.elc/.locs; '' = none
cfg.lookupTemplate = 'standard_1005.elc';  % fallback lookup; '' = none
cfg.renameChans    = {};   % {old, new} rows, e.g. {'A1','Fp1'; 'A2','AF7'}
cfg.minLocFrac     = 0.90; % abort below this fraction of located channels

%% Filtering
% ICA is trained on a cfg.hpICA copy and applied to the cfg.hpAnalysis copy.
cfg.hpAnalysis = 0.5;      % Hz. Also removes slow electrode drift, which ICA
                           % cannot; lower it (e.g. 0.1) for slow ERPs.
cfg.hpICA      = 1.0;      % Hz
cfg.lp         = 45;       % Hz; [] = no low-pass
cfg.lineFreq   = 50;       % Hz mains; [] = no line-noise removal

%% Reference
% [] average | 'none' keep the existing one | 'Cz' | {'M1','M2'}
cfg.reref = [];

%% Bad channels
cfg.flatlineSec = 5;       % s of flat line => dead channel
cfg.chanCorr    = 0.80;    % minimum correlation with the neighbours
cfg.lineNoiseSD = 4;       % line noise, SD
cfg.maxBadFrac  = 0.10;    % stop the file above this fraction of bad channels

%% ICA and component removal
cfg.icaType   = 'runica';  % 'runica' | 'picard'
cfg.icaThresh = 0.80;      % ICLabel probability that flags a removable class
% Per-class exceptions as {class, threshold} rows, e.g. {'Muscle', 0.6}; {} =
% cfg.icaThresh for all. A lower threshold removes more of that artifact but
% also more mixed and brain components; check the QC component sheets.
cfg.icaThreshClass = {};
cfg.icaMode   = 'subtract';% 'subtract' | 'flag' (classify only)
% Class names, matched to the classifier at run time. Brain and Other are
% never removed: Other holds uncertain components, often real signal.
cfg.icaRemove = {'Muscle', 'Eye', 'Heart', 'Line Noise', 'Channel Noise'};
cfg.icaReproducible = true;

% Rules for components ICLabel misses (prep_icrules). [] or false = off.
cfg.ecgChannels   = {'*ECG*','*EKG*'}; % recorded ECG, by label or chanlocs.type
cfg.ecgCorr       = 0.5;   % |r| with the ECG channel => cardiac
cfg.icaHeartbeat  = true;  % heartbeat detector when there is no ECG channel
cfg.icaSingleChan = 0.95;  % map power share on one channel => electrode artifact

%% Optional steps
cfg.asrForChannelDetection = false;  % ASR informs channel detection only
cfg.interpolate            = false;  % spherical-spline interpolation of bad channels

%% Epoching
% Time-locked (cfg.events) or fixed length (cfg.epochLength), not both;
% neither keeps the data continuous.
cfg.events       = {};         % e.g. {'S 1','S 2'}
cfg.window       = [-0.2 0.8]; % s, around the event
cfg.epochLength  = [];         % s; [] = no fixed-length epoching
cfg.epochOverlap = 0;          % fraction in [0, 1)
cfg.baseline     = [-200 0];   % MILLISECONDS; [] = none

% Post-epoch rejection, off by default since it changes the statistics.
cfg.epochReject     = false;
cfg.epochThresh     = 150;  % uV, +/-; [] = no amplitude criterion
cfg.epochProbSD     = 5;    % joint probability, SD; [] = none
cfg.epochMaxRejFrac = 0.40; % warn above this rejected fraction

%% Batch
cfg.qcFigures      = true; % QC sheets next to each derivative
cfg.qcTraceSecs    = 10;   % s of trace in the before/after sheet
cfg.qcIcsMargin    = 0.10; % kept components this close to the threshold are
                           % shown as near-misses; 0 = removed only
cfg.recursive      = true; % search subfolders of cfg.inDir
cfg.overwrite      = true; % false = skip subjects already processed
cfg.extraToolboxes = {};   % folders whose git version goes in the QC log

if nargin > 0 && ~isempty(overrides)
    cfg = apply_overrides(cfg, overrides);
end
end

%% Auxiliary functions
function cfg = apply_overrides(cfg, o)
if ischar(o) || (isstring(o) && isscalar(o))
    o = load_study_file(char(o));
end
if ~isstruct(o) || ~isscalar(o)
    error('prep_config:badOverrides', ...
        'Overrides must be a scalar struct or a path to a study config file.');
end
known = fieldnames(cfg);
given = fieldnames(o);
bad   = given(~ismember(given, known));
if ~isempty(bad)
    error('prep_config:unknownField', 'Unknown config field(s): %s\n\nValid fields are:\n  %s', ...
        strjoin(bad', ', '), strjoin(known', ', '));
end
for k = 1:numel(given)
    cfg.(given{k}) = o.(given{k});
end
end

function o = load_study_file(p)
% Run a study file from anywhere and take the struct it returns.
if ~isfile(p)
    error('prep_config:noStudyFile', 'Study config file not found: %s', p);
end
[d, name] = fileparts(p);
if ~isempty(d)
    oldPath = addpath(d);
    cleanup = onCleanup(@() path(oldPath));
end
o = feval(name);
end
