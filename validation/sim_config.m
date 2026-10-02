function sim = sim_config(overrides)
% SIM_CONFIG  Parameters of the simulation study. Defaults, then overrides.
%
%   sim = sim_config()               defaults
%   sim = sim_config(struct('secs', 60, 'snrDb', [10 0]))
%
% Unknown fields are rejected, as in prep_config, so a typo fails loudly
% instead of running a whole study with the default it meant to change.

root = fileparts(fileparts(mfilename('fullpath')));

%% Paths
sim.sereegaPath = fullfile(root, 'lib', 'toolboxes', 'SEREEGA');
sim.hartmutPath = fullfile(root, 'lib', 'toolboxes', 'HArtMuT');  % HArtMuT_NYhead_small.mat
sim.outRoot     = fullfile(root, 'validation', 'results');       % one subfolder per run
sim.runName     = '';     % appended to the run folder name, e.g. 'stroke_acute'

%% Clean EEG (SEREEGA, HArtMuT New York Head lead field)
sim.labels = {'Fp1','Fp2','AF3','AF4','F7','F3','Fz','F4','F8', ...
              'FC5','FC1','FC2','FC6','T7','C3','Cz','C4','T8', ...
              'CP5','CP1','CP2','CP6','P7','P3','Pz','P4','P8', ...
              'PO3','PO4','O1','Oz','O2'};
sim.secs       = 120;   % s of continuous data
sim.srate      = 250;   % Hz
sim.seeds      = 1:5;   % one full set of datasets per seed; results pooled
sim.nBackground = 60;   % spatially spread cortical noise sources
sim.bgSpacing  = 20;    % mm between background sources
sim.nAlpha     = 4;     % posterior alpha generators
sim.nTheta     = 2;     % frontal midline theta generators
sim.eegRms     = 15;    % uV, median channel SD the clean EEG is scaled to
sim.sensorNoise = 0.5;  % uV SD of white noise per electrode

%% Stroke (sim_clean_eeg)
% 'none', 'acute' or 'chronic'. A lesion attenuates background activity
% inside it and alpha on its side, adds polymorphic delta from inside it,
% and slows the background everywhere; acute more than chronic.
sim.stroke       = 'none';
sim.lesionCentre = [-45 -20 25];   % MNI mm; left perisylvian cortex
sim.lesionRadius = 40;             % mm

%% Artifacts
% Severity is set by SNR, 10*log10(P_clean / P_artifact), over all channels
% and samples of the raw data. Lower is worse.
sim.severity = {'low', 'medium', 'high', 'severe'};
sim.snrDb    = [10 5 0 -5];
% Artifact types, each run at every severity (see sim_artifact):
%   eog_blink, eog_vertical, eog_horizontal     sim_eog
%   emg_temporal, emg_frontal, emg_neck         sim_emg
%   ecg                                         sim_ecg
%   line                                        sim_line
%   drift, pop                                  sim_drift, sim_pop
%   badchan                                     sim_badchan; the severity
%                                               index is the number of bad
%                                               channels (1-4), not an SNR
% Join names with '+' for a combined condition, e.g. 'eog_blink+ecg': every
% part is scaled to the same SNR against the clean EEG, then all are added.
sim.artifacts = {'eog_blink', 'eog_vertical', 'eog_horizontal', ...
                 'emg_temporal', 'emg_frontal', 'emg_neck', 'ecg', 'line'};
sim.blinkRate    = 15;  % blinks per minute
sim.saccadeRate  = 10;  % eye movements per minute
sim.emgBurstRate = 6;   % muscle bursts per minute
sim.emgSources   = 10;  % sources drawn from each active muscle
sim.heartRate    = 70;  % beats per minute
sim.lineFreq     = 50;  % Hz mains
sim.driftChannels = 3;  % electrodes with slow drift
sim.popChannels  = 2;   % electrodes with pops
sim.popRate      = 6;   % pops per minute

%% Pipeline
% Passed to run_preprocessing on top of prep_config defaults. Only the QC
% figures are off: they do not change the data and cost time per dataset.
% Everything that does change the data stays at the production settings,
% which is what the validation is about.
sim.pipeline = struct('qcFigures', false);

%% Evaluation
sim.bands = struct('name', {'delta','theta','alpha','beta','gamma'}, ...
                   'range', {[1 4], [4 8], [8 13], [13 30], [30 45]});

%% Overrides
if nargin < 1 || isempty(overrides), return, end
given = fieldnames(overrides);
if isempty(given), return, end        % isfield(s, {}) is a scalar false, not []
bad   = given(~isfield(sim, given));
if ~isempty(bad)
    error('sim_config:unknownField', 'Unknown field(s): %s', strjoin(bad', ', '));
end
for k = 1:numel(given), sim.(given{k}) = overrides.(given{k}); end
assert(numel(sim.severity) == numel(sim.snrDb), 'sim_config:severity', ...
    'sim.severity and sim.snrDb must have the same length.');
end
