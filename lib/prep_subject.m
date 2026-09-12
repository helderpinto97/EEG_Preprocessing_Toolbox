function qc = prep_subject(inFile, outDir, cfg, env)
% PREP_SUBJECT  Preprocess one recording. Returns a QC row.
%
%   qc = prep_subject(inFile, outDir, cfg)
%   qc = prep_subject(inFile, outDir, cfg, env)
%
% ENV is what prep_env recorded for the batch: MATLAB, EEGLAB and plugin
% versions, which go at the front of the QC row. Passed in rather than read
% off cfg, so cfg stays a struct prep_config would accept and config.mat can
% be fed back in. Optional; without it the QC row omits those columns.
%
% Pipeline order:
%   import -> resample -> line noise -> filter (two branches) ->
%   bad channels (ASR-assisted) -> average reference -> ICA -> ICLabel ->
%   [interpolate] -> [epoch] -> save

[~, base] = fileparts(inFile);
qc = struct('subject', string(base), ...
            'datetime', string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));

% Software versions, at the front of the QC row.
if nargin >= 4 && ~isempty(env)
    qc = addfields(qc, env);
end

%% Import
EEG = prep_load(inFile);
EEG = eeg_checkset(EEG);

qc.nchan_raw = EEG.nbchan;
qc.dur_sec   = EEG.pnts / EEG.srate;

% Drop non-EEG channels. clean_rawdata and ASR assume an EEG-only matrix;
% a trigger or auxiliary channel breaks both the correlation criterion and
% the rank estimate. 
[EEG, q] = prep_noneeg(EEG, cfg);
qc = addfields(qc, q);

% Attach and verify electrode positions. Errors out if they are missing:
% clean_rawdata and ICLabel both do worse without them, and say nothing.
[EEG, q] = prep_chanlocs(EEG, cfg);
qc = addfields(qc, q);

if ~isempty(cfg.srate) && EEG.srate ~= cfg.srate
    EEG = pop_resample(EEG, cfg.srate);
end
qc.srate = EEG.srate;

%% Line Noise 
% Zapline-plus filters the mains component spectrally and spatially, so it
% does not carve a hole out of the neighbouring frequencies the way a notch
% does. The wrapper name has changed across plugin releases; if the fallback
% keeps firing, run `which -all zapline` and fix the call.
qc.line_method = "none";
if ~isempty(cfg.lineFreq)
    try
        EEG = clean_data_with_zapline_plus_eeglab_wrapper(EEG, ...
                  struct('noisefreqs', cfg.lineFreq, 'plotResults', 0));
        qc.line_method = "zapline-plus";
    catch
        EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.lineFreq-2, ...
                                  'hicutoff', cfg.lineFreq+2, 'revfilt', 1);
        qc.line_method = "notch";
    end
end

% Spectrum of the data as it stands now, for the before/after QC panel.
% Only the spectrum is kept, never a second copy of the samples.
pre = struct([]);
if cfg.qcFigures
    pre = prep_snapshot(EEG, cfg);
end

%% Filtering: 
% EEGica is only ever used to estimate the unmixing matrix.
EEGica = pop_eegfiltnew(EEG, 'locutoff', cfg.hpICA,      'hicutoff', cfg.lp);
EEG    = pop_eegfiltnew(EEG, 'locutoff', cfg.hpAnalysis, 'hicutoff', cfg.lp);

%% Bad channels
% Only the channel mask is taken from this call. clean_artifacts runs on
% EEGica and, with BurstRejection 'off', returns burst-corrected data, but
% EEGica exists only to estimate ICA weights and its data is discarded
% later. So cfg.asrForChannelDetection does not clean the output; it only
% lets ASR inform which channels are judged bad. Applying ASR to the
% analysis branch would mean running clean_asr on 0.1 Hz data, which its own
% documentation advises against.
% The two ASR numbers are clean_rawdata's own defaults, left fixed rather
% than exposed in prep_config. They tune burst correction, and burst
% correction is discarded here: only the channel mask is read out of this
% call. Making them config fields would offer a knob that changes nothing in
% the saved data, which is worse than not offering it.
if cfg.asrForChannelDetection, burst = 20; win = 0.25; else, burst = 'off'; win = 'off'; end

EEGica = clean_artifacts(EEGica, ...
    'FlatlineCriterion',  cfg.flatlineSec, ...
    'ChannelCriterion',   cfg.chanCorr,    ...
    'LineNoiseCriterion', cfg.lineNoiseSD, ...
    'Highpass',           'off',           ...  % already filtered
    'BurstCriterion',     burst,           ...
    'WindowCriterion',    win,             ...
    'BurstRejection',     'off');               % correct bursts, don't delete

if isfield(EEGica.etc, 'clean_channel_mask')
    keep = logical(EEGica.etc.clean_channel_mask(:)');
else
    keep = true(1, EEG.nbchan);
end

chanlocsFull      = EEG.chanlocs;                 % kept for interpolation
qc.asr_chandetect = cfg.asrForChannelDetection;
qc.nchan_rejected = sum(~keep);
qc.frac_rejected  = qc.nchan_rejected / numel(keep);
qc.chans_rejected = string(strjoin({EEG.chanlocs(~keep).labels}, '|'));

if qc.frac_rejected > cfg.maxBadFrac
    error('prep_subject:tooManyBadChannels', ...
          '%.0f%% of channels are bad (limit %.0f%%).', ...
          100*qc.frac_rejected, 100*cfg.maxBadFrac);
end

EEG = pop_select(EEG, 'channel', find(keep));     % same channels in both

%% Referencing
% Applied to both copies so the ICA weights stay valid when transferred.
% See cfg.reref; average is the default.
[EEG, EEGica, q] = prep_reref(EEG, EEGica, cfg);
qc = addfields(qc, q);

%% ICA
qc.rank_before_ica = prep_rank(EEGica);

% ICA needs roughly 20 * rank^2 samples. Warn rather than fail.
qc.samples          = EEGica.pnts;
qc.samples_needed   = 20 * qc.rank_before_ica^2;
qc.ica_underpowered = qc.samples < qc.samples_needed;
if qc.ica_underpowered
    warning('prep:ica', '%s: %d samples for rank %d (want >= %d).', ...
            base, qc.samples, qc.rank_before_ica, qc.samples_needed);
end

% runica reseeds the RNG internally, so setting it here would be ignored.
% The 'rndreset' option is what actually controls it: 'no' makes runica use
% rand('state',0) and produce the same decomposition every run. Passed only
% for runica, since picard does not accept it.
qc.ica_reproducible = cfg.icaReproducible;
icaOpts = {};
if strcmpi(cfg.icaType, 'runica')
    reset   = {'yes', 'no'};                 % 'no' reseeds nothing, so it repeats
    icaOpts = {'rndreset', reset{1 + cfg.icaReproducible}};
end

EEGica = pop_runica(EEGica, 'icatype', cfg.icaType, 'extended', 1, ...
                            'pca', qc.rank_before_ica, 'interrupt', 'off', ...
                            icaOpts{:});

EEG.icaweights  = EEGica.icaweights;   % transfer to the analysis branch
EEG.icasphere   = EEGica.icasphere;
EEG.icawinv     = EEGica.icawinv;
EEG.icachansind = EEGica.icachansind;
EEG = eeg_checkset(EEG, 'ica');
clear EEGica

%% Component Classification
EEG = pop_iclabel(EEG, 'default');

% Which rows may be flagged, resolved from the class NAMES in cfg.icaRemove
% against the classifier's own class list. The row order belongs to the
% classifier, so pinning it to integers here would quietly subtract the
% wrong classes under a build that lists them in a different order.
classes   = EEG.etc.ic_classification.ICLabel.classes;
removable = resolve_classes(classes, cfg.icaRemove);
qc.ica_remove = string(strjoin(classes(removable), '|'));

% NaN leaves a class alone. A named class gets [thresh 1], so a component is
% flagged once the classifier is at least cfg.icaThresh sure of it.
rule = NaN(numel(classes), 2);
rule(removable, :) = repmat([cfg.icaThresh 1], numel(removable), 1);
EEG = pop_icflag(EEG, rule);

qc.n_ic_flagged = sum(EEG.reject.gcompreject);
qc.ica_mode     = string(cfg.icaMode);
qc.ica_thresh   = cfg.icaThresh;  

% Capture what ICLabel decided BEFORE anything is subtracted. pop_subcomp
% trims etc.ic_classification to the components that are left, so afterwards the
% removed ones are simply gone and the figure could neither show them nor
% state a correct total.
if isstruct(pre) && ~isempty(pre) && isfield(EEG.etc, 'ic_classification')
    pre.ic = struct( ...
        'classifications', EEG.etc.ic_classification.ICLabel.classifications, ...
        'classes',  {EEG.etc.ic_classification.ICLabel.classes}, ...
        'flagged',  logical(EEG.reject.gcompreject(:)'), ...
        'thresh',   cfg.icaThresh, ...
        'removable', removable, ...      % rows the threshold could act on
        'winv',     EEG.icawinv, ...          % scalp maps, for the topoplots
        'chansind', EEG.icachansind, ...      % which channels those rows are
        'chanlocs', EEG.chanlocs);
end

if strcmpi(cfg.icaMode, 'subtract')
    EEG = pop_subcomp(EEG, [], 0);     % costs one rank per component
end

%% Optional Interpolation
if cfg.interpolate
    EEG = pop_interp(EEG, chanlocsFull, 'spherical');
end
qc.interpolated  = cfg.interpolate;
qc.rank_final    = prep_rank(EEG);
qc.nchan_final   = EEG.nbchan;

%% Optional Epoching
% Epoching, baseline correction and the optional post-ICA epoch rejection
% all live in prep_epoch, which reports what it could not find: a subject
% whose trigger labels differ from the study file's otherwise loses trials
% without saying so. Leave cfg.events empty to keep the data continuous.
[EEG, q] = prep_epoch(EEG, cfg);
qc = addfields(qc, q);

%% Save Processed Data
EEG.setname  = [base '_clean'];
EEG.etc.prep = qc;                     
pop_saveset(EEG, 'filename', [EEG.setname '.set'], 'filepath', outDir);

%% QC figures
% A failed plot must never cost a successfully preprocessed recording, so
% each sheet is attempted on its own and one failing does not stop the rest.
% The outcome is recorded in the QC row as well as on the console: a warning
% in a hundred-subject batch scrolls away, and a blank column in qc_log.csv
% reads the same as "there was nothing to draw".
qc.qc_figure         = "";
qc.qc_figure_ics     = "";
qc.qc_figure_data    = "";
qc.qc_figure_epochs  = "";
qc.qc_figures_failed = "";
if cfg.qcFigures
    [qc.qc_figure, qc.qc_figures_failed] = try_fig( ...
        qc.qc_figures_failed, base, 'qc', ...
        @() prep_qcfig(EEG, pre, qc, outDir, base));

    % Scalp maps of what was removed, and of the kept components that came
    % close. Returns '' when there is nothing to show.
    [qc.qc_figure_ics, qc.qc_figures_failed] = try_fig( ...
        qc.qc_figures_failed, base, 'ics', ...
        @() prep_qcfig_ics(pre, outDir, base, cfg.qcIcsMargin));

    % The traces themselves, every channel, before vs after.
    [qc.qc_figure_data, qc.qc_figures_failed] = try_fig( ...
        qc.qc_figures_failed, base, 'data', ...
        @() prep_qcfig_data(EEG, pre, outDir, base));

    % The averages, per condition. Returns '' for continuous data, which has
    % no trials to average.
    [qc.qc_figure_epochs, qc.qc_figures_failed] = try_fig( ...
        qc.qc_figures_failed, base, 'epochs', ...
        @() prep_qcfig_epochs(EEG, qc, outDir, base));
end

fprintf('%-28s chans -%d | ICs -%d | rank %d -> %d\n', base, ...
        qc.nchan_rejected, qc.n_ic_flagged, qc.rank_before_ica, qc.rank_final);
end

% Auxiliary Functions
function qc = addfields(qc, q)
% Copy every field of q into qc.
%
% Each step owns a disjoint slice of one flat namespace, with nothing but
% convention keeping them apart. A step that reuses a name another already
% wrote would overwrite it, silently, and the column order of qc_log.csv
% would shift with merge order. Erring here turns that into two lines at
% the point it happens.
n = fieldnames(q);
clash = n(isfield(qc, n));
if ~isempty(clash)
    error('prep_subject:qcFieldClash', ...
        ['Two pipeline steps both write the QC field(s): %s\n' ...
         'One flat row means one owner per name.'], strjoin(clash', ', '));
end
for k = 1:numel(n), qc.(n{k}) = q.(n{k}); end
end

function idx = resolve_classes(classes, wanted)
% Row numbers in the classifier's class list for the names in WANTED.
% An unmatched name is an error: removing three of the four classes you
% asked for, without saying which one was skipped, is worse than stopping.
wanted     = cellstr(string(wanted(:)'));
[tf, idx]  = ismember(lower(wanted), lower(classes));
if ~all(tf)
    % Every unmatched name at once. Reporting only the first means fixing
    % the config one run at a time.
    error('prep_subject:unknownIcClass', ...
        ['cfg.icaRemove names %s, which this classifier does not have.\n' ...
         'Its classes are: %s'], ...
        strjoin(compose('"%s"', string(wanted(~tf))), ', '), ...
        strjoin(classes, ', '));
end
idx = unique(idx);
end

function [png, failed] = try_fig(failed, base, name, fcn)
% Draw one QC sheet. A failure costs that sheet and nothing else.
png = "";
try
    png = string(fcn());
catch ME
    warning('prep_subject:qcfig', ...
            '%s: QC sheet "%s" failed (%s). Preprocessing itself is unaffected.', ...
            base, name, ME.message);
    if strlength(failed) > 0, failed = failed + "|"; end
    failed = failed + name + ": " + string(ME.message);
end
end
