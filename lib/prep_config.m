function cfg = prep_config(overrides)
% PREP_CONFIG  Pipeline parameters: the defaults, and the only list of what
% a valid parameter name is.
%
%   cfg = prep_config()                 defaults
%   cfg = prep_config(struct('lp',100)) defaults with overrides applied
%   cfg = prep_config('config/my.m')    defaults with a study file applied
%
% A study file is a function returning a struct of only the fields it
% changes; see config/example_study.m. Small override files instead of
% edited copies of the whole script keep a study's parameters diffable, so
% "what changed between the pilot and the final run" has an answer.
%
% Any field not listed below is rejected, so a typo like cfg.hpAnalyis fails
% here with a readable message rather than deep inside pop_eegfiltnew.

root = fileparts(fileparts(mfilename('fullpath')));

%% Paths
cfg.eeglabPath = fullfile(root, 'lib', 'toolboxes', 'eeglab');
cfg.inDir      = fullfile(root, 'data');         % folder with raw recordings
cfg.outDir     = fullfile(root, 'derivatives');  % where cleaned files go
cfg.fileExt    = '*.set';                        % '*.bdf', '*.vhdr', ...

%% Sampling Rate
cfg.srate = [];           % target sampling rate (Hz); [] = leave unchanged

% Non-EEG channels, dropped before the EEG-only steps. Whole-label match,
% case-insensitive, '*' and '?' wildcards. Mastoids and earlobes are
% absent on purpose, since they are often the reference. See prep_noneeg.
cfg.nonEEG = {'*EOG*','*EMG*','*ECG*','*EKG*', ...   % ocular, muscle, cardiac
              'Status','Trigger','TRIG*','STI*', ... % event channels
              'EXG*', ...                            % BioSemi externals
              'GSR*','Erg*','Resp*','Plet','Temp'};  % BioSemi auxiliaries

% Matched against chanlocs.type when the importer populates it; {} ignores
% types entirely.
cfg.nonEEGTypes = {'EOG','ECG','EKG','EMG','MISC','TRIG','STIM','AUX','REF'};

%% Channels Locations
cfg.chanlocFile    = '';   % .ced/.elp/.sfp/.elc/.locs; '' = don't load one.
                           % Use for digitized positions, or caps whose
                           % labels are not 10-20.
cfg.lookupTemplate = 'standard_1005.elc';  % fallback; '' = no lookup
cfg.renameChans    = {};   % label translation before lookup, e.g.
                           % {'A1','Fp1'; 'A2','AF7'}
cfg.minLocFrac     = 0.90; % abort the file below this fraction located

%% Filtering 
% Two high-pass values. ICA converges better on 1 Hz data, but
% 1 Hz destroys slow activity. The weights are estimated on a 1 Hz copy and
% applied to the cfg.hpAnalysis copy, so you get both.
% See ......
cfg.hpAnalysis = 0.1;      % Hz, the data you analyse
cfg.hpICA      = 1.0;      % Hz, the copy ICA is trained on
cfg.lp         = 45;       % Hz; [] = no low-pass
cfg.lineFreq   = 50;       % Hz mains; [] = skip line-noise removal
 
% Re-check with pop_eegfiltnew(EEG, 'hicutoff', cfg.lp, 'plotfreqz', 1)
% if you change cfg.lp or cfg.srate.

%% Reference
% []            average reference (the usual choice in ICA pipelines)
% 'none'        leave the recording's existing reference alone
% 'Cz'          single channel
% {'M1','M2'}   linked mastoids
cfg.reref = [];

%% Bad Channels
cfg.flatlineSec = 5;       % s of flatline => dead channel
cfg.chanCorr    = 0.80;    % min correlation with neighbours
cfg.lineNoiseSD = 4;       % SD of line noise
cfg.maxBadFrac  = 0.10;    % skip the file if more channels than this are bad

%% ICA 
cfg.icaType   = 'runica';  % 'runica' | 'picard'
cfg.icaThresh = 0.80;      % ICLabel probability to flag an artifact class
cfg.icaMode   = 'subtract';% 'subtract' = remove flagged ICs (standard)
                           % 'flag'     = classify only, remove nothing

% Which ICLabel classes may be removed, named rather than numbered. The
% names are matched against EEG.etc.ic_classification.ICLabel.classes at run
% time, so a classifier that lists its classes in a different order still
% removes what you asked for.
% Brain and Other are left out deliberately: Other collects components the
% classifier is unsure about, which on atypical data means real signal.
cfg.icaRemove = {'Muscle', 'Eye', 'Line Noise', 'Channel Noise'};
cfg.icaReproducible = true;

%% Optional Steps 
% ASR informs which channels are judged bad; it does NOT burst-correct the
% saved data. See the note at step 4 of prep_subject.
cfg.asrForChannelDetection = false;
cfg.interpolate            = false;  % spherical-spline interp of bad channels

%% Epoching
% Two ways to cut epochs. Set the parameter for the one you want, leave
% both empty to keep the data continuous, and note that setting both is an
% error rather than a silent choice, since there is no way to tell which
% one you meant.
%
%   cfg.events       time-locked epochs, for task data with real triggers
%   cfg.epochLength  fixed-length epochs, for resting state and for any
%                    recording whose triggers carry no meaning
cfg.events   = {};         % e.g. {'S 1','S 2'}
cfg.window   = [-0.2 0.8]; % s, around the event

% Fixed-length epoching. The epochs are contiguous from the start of the
% recording, and the short remainder at the end is dropped and counted in
% qc.n_epochs_lost. Overlap is a fraction: 0.5 steps half an epoch at a
% time. Common for spectral estimates, and the epochs then share samples, so
% they are no longer independent.
cfg.epochLength  = [];     % s; [] = no fixed-length epoching
cfg.epochOverlap = 0;      % fraction in [0, 1)

% Baseline correction, in MILLISECONDS. Note cfg.window is in seconds.
% Set [] to skip it.
% Recorded per subject as qc.baseline, "none" or the window removed.
cfg.baseline = [-200 0];

% Post-epoch artifact rejection. ICA removes what it can describe as a
% component. It does not remove a movement artifact confined to one trial,
% or an epoch spanning a lapse in electrode contact. Off by default:
% rejecting trials changes the statistics of what follows, so it should be
% asked for. Both criteria apply together; see prep_epoch.
cfg.epochReject     = false;
cfg.epochThresh     = 150;  % uV, +/-; [] = no amplitude criterion.
                            % Sensible only on referenced, ICA-cleaned data
                            % in uV. Raise it for high-impedance or infant
                            % recordings, where 150 rejects most of the set.
cfg.epochProbSD     = 5;    % joint probability, SD; [] = no such criterion.
                            % Improbable joint activity across channels;
                            % catches what a fixed amplitude limit misses.
cfg.epochMaxRejFrac = 0.40; % warn above this rejected fraction. A warning,
                            % not an abort: which subjects to drop belongs
                            % to the analysis, and it needs the QC row.

%% Batch Behaviour 
cfg.qcFigures      = true; % write <subject>_qc.png next to each derivative
cfg.qcTraceSecs    = 10;   % s of trace kept for the before/after panel
cfg.qcIcsMargin    = 0.10; % a kept component within this of cfg.icaThresh is
                           % drawn on the component sheet as a near-miss.
                           % 0 = show the removed components only.
cfg.recursive      = true; % search cfg.inDir's subfolders too. Datasets are
                           % usually one folder per subject (PhysioNet, BIDS),
                           % and a non-recursive search finds nothing there
                           % while still reporting a clean run.
cfg.overwrite      = true; % false = skip subjects whose output already exists
cfg.extraToolboxes = {};   % pinned in the QC log, e.g.
                           % {fullfile(root,'lib','toolboxes','fieldtrip')}

%% Apply Overrides 
if nargin > 0 && ~isempty(overrides)
    cfg = apply_overrides(cfg, overrides);
end
end

%% Auxiliary Functions
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
    error('prep_config:unknownField', ...
        'Unknown config field(s): %s\n\nValid fields are:\n  %s', ...
        strjoin(bad', ', '), strjoin(known', ', '));
end

for k = 1:numel(given)
    cfg.(given{k}) = o.(given{k});
end
end

function o = load_study_file(p)
% Run a study config file and take the struct it returns. The file is added
% to the path by folder rather than run by path, so it can live anywhere.
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
