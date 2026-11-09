function qc = prep_subject(inFile, outDir, cfg, env)
% PREP_SUBJECT  Preprocess one recording. Returns a QC row.
%
%   qc = prep_subject(inFile, outDir, cfg)
%   qc = prep_subject(inFile, outDir, cfg, env)   env from prep_env, put
%                                                 at the front of the row
%
% import -> resample -> flat channels -> line noise -> filter (two branches) -> bad channels
% -> reference -> ICA -> ICLabel + component rules -> [interpolate
% -> average reference again] -> [epoch] -> save -> QC figures

[~, base] = fileparts(inFile);
if nargin < 4, env = []; end
qc = prep_qc_row(base, env);

%% Import
EEG = eeg_checkset(prep_load(inFile));
qc.nchan_raw = EEG.nbchan;
qc.dur_sec   = EEG.pnts / EEG.srate;

% A recorded ECG is kept aside for the cardiac rule before the non-EEG
% channels are dropped; clean_rawdata and the rank estimate need EEG only.
[ECG, q] = prep_ecgref(EEG, cfg);          qc = addfields(qc, q);
[EEG, q] = prep_noneeg(EEG, cfg);          qc = addfields(qc, q);
[EEG, q] = prep_chanlocs(EEG, cfg);        qc = addfields(qc, q);

if ~isempty(cfg.srate) && EEG.srate ~= cfg.srate
    EEG = pop_resample(EEG, cfg.srate);
end
qc.srate = EEG.srate;

%% Flat channels, on the raw signal
% Zapline-plus skips a channel only in chunks where it is flat throughout,
% so a dropout that does not fill whole chunks picks up small values and no
% longer passes as flat after line-noise removal and filtering.
flatRaw = false(1, EEG.nbchan);
if ~isempty(cfg.flatlineSec)
    F0 = clean_flatlines(EEG, cfg.flatlineSec);
    if isfield(F0.etc, 'clean_channel_mask')
        flatRaw = ~logical(F0.etc.clean_channel_mask(:)');
    end
    clear F0
end
qc.chans_flat_raw = string(strjoin({EEG.chanlocs(flatRaw).labels}, '|'));

%% Line noise
% Zapline-plus if available, a notch otherwise.
qc.line_method = "none";
if ~isempty(cfg.lineFreq)
    try
        EEG = clean_data_with_zapline_plus_eeglab_wrapper(EEG, ...
                  struct('noisefreqs', cfg.lineFreq, 'plotResults', 0));
        qc.line_method = "zapline-plus";
        % Zapline-plus can leave a residual peak (non-stationary or local
        % line noise). Only relevant when the low-pass keeps the mains.
        if cfg.lineNotch && (isempty(cfg.lp) || cfg.lp > cfg.lineFreq - 2)
            EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.lineFreq-2, ...
                                      'hicutoff', cfg.lineFreq+2, 'revfilt', 1);
            qc.line_method = "zapline-plus+notch";
        end
    catch
        EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.lineFreq-2, ...
                                  'hicutoff', cfg.lineFreq+2, 'revfilt', 1);
        qc.line_method = "notch";
    end
end

pre = struct([]);                          % pre-filter spectrum and traces
if cfg.qcFigures, pre = prep_snapshot(EEG, cfg); end

%% Filtering
% ICA is trained on a 1 Hz copy and its weights applied to the analysis copy.
EEGica = pop_eegfiltnew(EEG, 'locutoff', cfg.hpICA,      'hicutoff', cfg.lp);
EEG    = pop_eegfiltnew(EEG, 'locutoff', cfg.hpAnalysis, 'hicutoff', cfg.lp);

%% Bad channels
% Only the channel mask is used; the burst-corrected EEGica is discarded,
% so ASR (cfg.asrForChannelDetection) informs detection but never the output.
if cfg.asrForChannelDetection, burst = 20; win = 0.25; else, burst = 'off'; win = 'off'; end
EEGica = clean_artifacts(EEGica, ...
    'FlatlineCriterion',  cfg.flatlineSec, ...
    'ChannelCriterion',   cfg.chanCorr, ...
    'LineNoiseCriterion', cfg.lineNoiseSD, ...
    'Highpass',           'off', ...
    'BurstCriterion',     burst, ...
    'WindowCriterion',    win, ...
    'BurstRejection',     'off');

keep = true(1, EEG.nbchan);
if isfield(EEGica.etc, 'clean_channel_mask')
    keep = logical(EEGica.etc.clean_channel_mask(:)');
end
% Flat before line-noise removal; dropped from the ICA copy as well, which
% clean_artifacts has already reduced to its own mask.
extraFlat = {EEG.chanlocs(flatRaw & keep).labels};
if ~isempty(extraFlat)
    EEGica = pop_select(EEGica, 'nochannel', extraFlat);
end
keep = keep & ~flatRaw;
chanlocsFull      = EEG.chanlocs;          % for interpolation
qc.asr_chandetect = cfg.asrForChannelDetection;
qc.nchan_rejected = sum(~keep);
qc.frac_rejected  = qc.nchan_rejected / numel(keep);
qc.chans_rejected = string(strjoin({EEG.chanlocs(~keep).labels}, '|'));
if qc.frac_rejected > cfg.maxBadFrac
    error('prep_subject:tooManyBadChannels', '%.0f%% of channels are bad (limit %.0f%%).', ...
          100*qc.frac_rejected, 100*cfg.maxBadFrac);
end
EEG = pop_select(EEG, 'channel', find(keep));

% Same reference on both copies, so the ICA weights stay valid.
[EEG, EEGica, q] = prep_reref(EEG, EEGica, cfg);
qc = addfields(qc, q);

%% ICA
qc.rank_before_ica  = prep_rank(EEGica);
qc.samples          = EEGica.pnts;
qc.samples_needed   = 20 * qc.rank_before_ica^2;
qc.ica_underpowered = qc.samples < qc.samples_needed;
if qc.ica_underpowered
    warning('prep:ica', '%s: %d samples for rank %d (want >= %d).', ...
            base, qc.samples, qc.rank_before_ica, qc.samples_needed);
end

% runica reseeds itself; 'rndreset','no' is what makes it repeatable.
qc.ica_reproducible = cfg.icaReproducible;
icaOpts = {};
if strcmpi(cfg.icaType, 'runica')
    reset   = {'yes', 'no'};
    icaOpts = {'rndreset', reset{1 + cfg.icaReproducible}};
end
EEGica = pop_runica(EEGica, 'icatype', cfg.icaType, 'extended', 1, ...
                    'pca', qc.rank_before_ica, 'interrupt', 'off', icaOpts{:});

EEG.icaweights  = EEGica.icaweights;
EEG.icasphere   = EEGica.icasphere;
EEG.icawinv     = EEGica.icawinv;
EEG.icachansind = EEGica.icachansind;
EEG = eeg_checkset(EEG, 'ica');
clear EEGica

%% Component classification
% Classes are resolved by name, since the row order belongs to the classifier.
EEG = pop_iclabel(EEG, 'default');
classes   = EEG.etc.ic_classification.ICLabel.classes;
removable = resolve_classes(classes, cfg.icaRemove);
thresh    = repmat(cfg.icaThresh, 1, numel(classes));
for k = 1:size(cfg.icaThreshClass, 1)
    thresh(resolve_classes(classes, cfg.icaThreshClass(k, 1))) = cfg.icaThreshClass{k, 2};
end
rule = NaN(numel(classes), 2);             % NaN = never flag this class
rule(removable, :) = [thresh(removable)' ones(numel(removable), 1)];
EEG = pop_icflag(EEG, rule);

icl = logical(EEG.reject.gcompreject(:)');
[extra, reason, q] = prep_icrules(EEG, ECG, cfg);
qc = addfields(qc, q);
reason(icl) = "";                          % "" = flagged by ICLabel
EEG.reject.gcompreject = icl | extra;
clear ECG

odd = thresh ~= cfg.icaThresh;
qc.ica_remove       = string(strjoin(classes(removable), '|'));
qc.n_ic_iclabel     = sum(icl);
qc.n_ic_flagged     = sum(EEG.reject.gcompreject);
qc.ica_mode         = string(cfg.icaMode);
qc.ica_thresh       = cfg.icaThresh;
qc.ica_thresh_class = string(strjoin(compose('%s=%.2f', string(classes(odd)), thresh(odd)), '|'));

% Kept before subtraction: pop_subcomp drops the removed components.
if cfg.qcFigures
    pre.ic = struct('classifications', EEG.etc.ic_classification.ICLabel.classifications, ...
                    'classes', {classes}, 'flagged', EEG.reject.gcompreject, ...
                    'reason', reason, 'thresh', thresh, 'removable', removable, ...
                    'winv', EEG.icawinv, 'chansind', EEG.icachansind, ...
                    'chanlocs', EEG.chanlocs, 'act', []);
    fmax = min([cfg.lp, 80, EEG.srate/2]);
    try
        pre.ic.act = prep_ic_act(EEG, cfg.qcTraceSecs, fmax);
    catch ME                               % the sheet falls back to maps only
        warning('prep_subject:icact', '%s: no component time courses (%s).', base, ME.message);
    end
end
if strcmpi(cfg.icaMode, 'subtract')
    EEG = pop_subcomp(EEG, [], 0);
end

%% Interpolation, epoching, save
if cfg.interpolate
    EEG = pop_interp(EEG, chanlocsFull, 'spherical');
end
qc.interpolated = cfg.interpolate;

% The average was taken before interpolation, over the kept channels only;
% the interpolated ones break the zero sum. 'refica','off' keeps the ICA
% weights, which pop_reref would otherwise drop since icachansind no longer
% covers every channel.
qc.reref_final = "none";
if cfg.rerefAfterInterp && isempty(cfg.reref) && cfg.interpolate && qc.nchan_rejected > 0
    EEG = pop_reref(EEG, [], 'refica', 'off');
    qc.reref_final = "average";
end
qc.rank_final   = prep_rank(EEG);
qc.nchan_final  = EEG.nbchan;

[EEG, q] = prep_epoch(EEG, cfg);
qc = addfields(qc, q);

EEG.setname  = [base '_clean'];
EEG.etc.prep = qc;
pop_saveset(EEG, 'filename', [EEG.setname '.set'], 'filepath', outDir);

%% QC figures
% Each sheet on its own: a failed plot costs that sheet, never the recording.
sheets = {'qc_figure',        'qc',     @() prep_qcfig(EEG, pre, qc, outDir, base); ...
          'qc_figure_ics',    'ics',    @() prep_qcfig_ics(pre, outDir, base, cfg.qcIcsMargin); ...
          'qc_figure_data',   'data',   @() prep_qcfig_data(EEG, pre, outDir, base); ...
          'qc_figure_epochs', 'epochs', @() prep_qcfig_epochs(EEG, qc, outDir, base)};
failed = strings(0);
for k = 1:size(sheets, 1)
    qc.(sheets{k, 1}) = "";
    if ~cfg.qcFigures, continue, end
    try
        qc.(sheets{k, 1}) = string(sheets{k, 3}());
    catch ME
        warning('prep_subject:qcfig', ...
                '%s: QC sheet "%s" failed (%s). Preprocessing itself is unaffected.', ...
                base, sheets{k, 2}, ME.message);
        failed(end+1) = sheets{k, 2} + ": " + ME.message; %#ok<AGROW>
    end
end
qc.qc_figures_failed = strjoin(failed, '|');

fprintf('%-28s chans -%d | ICs -%d | rank %d -> %d\n', base, ...
        qc.nchan_rejected, qc.n_ic_flagged, qc.rank_before_ica, qc.rank_final);
end

%% Auxiliary functions
function qc = addfields(qc, q)
% Copy the fields of q into qc. Two steps writing the same name is an error.
n = fieldnames(q);
clash = n(isfield(qc, n));
if ~isempty(clash)
    error('prep_subject:qcFieldClash', 'Two pipeline steps both write the QC field(s): %s', ...
          strjoin(clash', ', '));
end
for k = 1:numel(n), qc.(n{k}) = q.(n{k}); end
end

function idx = resolve_classes(classes, wanted)
% Rows of the classifier class list for the names in WANTED. All unmatched
% names are reported at once.
wanted    = cellstr(string(wanted(:)'));
[tf, idx] = ismember(lower(wanted), lower(classes));
if ~all(tf)
    error('prep_subject:unknownIcClass', ...
        'cfg.icaRemove names %s, which this classifier does not have.\nIts classes are: %s', ...
        strjoin(compose('"%s"', string(wanted(~tf))), ', '), strjoin(classes, ', '));
end
idx = unique(idx);
end
