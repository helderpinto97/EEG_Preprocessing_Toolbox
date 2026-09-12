function [EEG, qc] = prep_epoch(EEG, cfg)
% PREP_EPOCH  Cut the recording into epochs, correct the baseline, and
% optionally reject bad epochs.
%
% Two modes. Set the parameter for the one you want. Setting neither leaves
% the data continuous; setting both is rejected by prep_checkcfg before a
% batch starts.
%
%   Time-locked, for task data:
%     cfg.events      {'S 1','S 2'}  event types to lock to
%     cfg.window      [-0.2 0.8]     epoch limits, SECONDS
%
%   Fixed length, for resting state:
%     cfg.epochLength  2             seconds per epoch
%     cfg.epochOverlap 0             fraction in [0, 1)
%
%   Either mode:
%     cfg.baseline [-200 0]          baseline window, MILLISECONDS
%     cfg.baseline []                no baseline correction
%
%   cfg.epochReject     false        post-epoch rejection, on or off
%   cfg.epochThresh     150          uV, +/-; [] = no amplitude check
%   cfg.epochProbSD     5            joint probability, SD; [] = no check
%   cfg.epochMaxRejFrac 0.40         warn above this rejected fraction
%
% pop_epoch matches event types exactly and reports nothing about the ones
% it does not find. Asking for {'S 1','S 2'} against triggers written 'S1'
% and 'S2' gives "empty epoch range" and neither list. A subject whose
% 'S 2' triggers are missing loses half its trials and still reports a
% normal-looking count. Both cases go in the QC row here instead.
%
% Both rejection criteria mark epochs first and the removal happens once.
% Letting each pop_ call reject on its own renumbers the epochs in between,
% so the second criterion indexes data the first already changed.

% Every field is set here, including the ones only rejection fills in, so
% the QC table has the same columns whether or not a subject was epoched.
qc = struct('n_epochs',             NaN, ...
            'n_epochs_built',       NaN, ...
            'n_epochs_lost',        NaN, ...
            'n_epochs_rejected',    NaN, ...
            'n_epochs_rej_thresh',  NaN, ...
            'n_epochs_rej_prob',    NaN, ...
            'epoch_rej_frac',       NaN, ...
            'epoch_events',         "", ...
            'epoch_missing',        "", ...
            'epoch_counts',         "", ...
            'epoch_mode',           "", ...
            'baseline',             "", ...
            'epoch_reject',         "off");

useEvents = ~isempty(cfg.events);
useFixed  = ~isempty(cfg.epochLength);

if ~useEvents && ~useFixed
    return
end

if useFixed
    [EEG, qc, found] = fixed_epochs(EEG, cfg, qc);
else
    [EEG, qc, found] = event_epochs(EEG, cfg, qc);
end

% Baseline correction subtracts a constant per trial and per channel, so
% it changes every value downstream. Recorded in the QC row either way:
% config.json is written per batch, so a study run in two passes cannot be
% told apart from the merged log alone.
if isempty(cfg.baseline)
    qc.baseline = "none";
else
    EEG = pop_rmbase(EEG, cfg.baseline);
    qc.baseline = string(sprintf('%g %g ms', cfg.baseline(1), cfg.baseline(2)));
end

%% Optional rejection ------------------------------------------------------
if cfg.epochReject
    [EEG, qc] = reject_epochs(EEG, cfg, qc);
end

qc.n_epochs     = EEG.trials;
qc.epoch_counts = count_per_condition(EEG, found);
end


% =========================================================================
function [EEG, qc, found] = fixed_epochs(EEG, cfg, qc)
% Contiguous epochs of a fixed length, for resting state.
%
% eeg_regepochs inserts a dummy event every RECURRENCE seconds and calls
% pop_epoch on them, so boundary-spanning epochs and the short remainder at
% the end are dropped by the same code as the time-locked mode.

if EEG.trials > 1
    error('prep_epoch:alreadyEpoched', ...
        'Fixed-length epoching needs continuous data; this set has %d trials.', ...
        EEG.trials);
end

L       = cfg.epochLength;
overlap = cfg.epochOverlap;
recur   = L * (1 - overlap);
dur     = EEG.xmax - EEG.xmin;

if recur > dur
    error('prep_epoch:epochTooLong', ...
        ['cfg.epochLength %g s (step %g s after %g%% overlap) is longer than\n' ...
         'the %.1f s recording, so not one epoch could be cut.'], ...
         L, recur, 100*overlap, dur);
end

found = {'fixed'};
% Same arithmetic eeg_regepochs uses for the number of dummy events, so
% n_epochs_lost counts what pop_epoch dropped.
nPlanned = floor((EEG.xmax + 1/EEG.srate) / recur);

EEG = eeg_regepochs(EEG, 'recurrence', recur, 'limits', [0 L], ...
                    'rmbase', NaN, 'eventtype', found{1});

qc.n_epochs_built = EEG.trials;
qc.n_epochs_lost  = max(0, nPlanned - EEG.trials);
qc.epoch_events   = string(found{1});
if overlap > 0
    qc.epoch_mode = string(sprintf('fixed %g s, %g%% overlap', L, 100*overlap));
else
    qc.epoch_mode = string(sprintf('fixed %g s', L));
end

if qc.n_epochs_lost > 0
    warning('prep_epoch:epochsDropped', ...
        ['%d of %d planned epochs were dropped (the last one ran past the\n' ...
         'end of the recording, or it spanned a discontinuity).'], ...
         qc.n_epochs_lost, nPlanned);
end
end


% =========================================================================
function [EEG, qc, found] = event_epochs(EEG, cfg, qc)
% Time-locked epochs around the requested event types.

% cfg.events is a cell or string array; prep_checkcfg has already made sure
% of that. cellstr(string(...)) takes both.
types = deblank(cellstr(string(cfg.events(:)))');

if isempty(EEG.event)
    error('prep_epoch:noEventStruct', ...
        ['cfg.events asks for %s but the recording carries no events at all.\n' ...
         'Either the importer did not read the trigger channel, or the\n' ...
         'events are in a separate file that has not been loaded in.'], ...
         strjoin(types, ', '));
end

present = event_type_strings(EEG);
nAvail  = cellfun(@(t) sum(strcmp(t, present)), types);

missing = types(nAvail == 0);
found   = types(nAvail >  0);

if isempty(found)
    error('prep_epoch:noMatchingEvents', ...
        ['None of the requested event types occur in this recording.\n' ...
         '  requested: %s\n' ...
         '  available: %s'], ...
         strjoin(types, ', '), strjoin(unique(present), ', '));
end

if ~isempty(missing)
    % Not fatal, since a design can omit a condition for one subject. Not
    % silent either: the usual cause is a label mismatch costing half the
    % trials.
    warning('prep_epoch:missingEvents', ...
        ['Requested event type(s) not present: %s\n' ...
         'Epoching on %s only. Available: %s'], ...
         strjoin(missing, ', '), strjoin(found, ', '), ...
         strjoin(unique(present), ', '));
end

qc.epoch_events  = string(strjoin(found, '|'));
qc.epoch_missing = string(strjoin(missing, '|'));
qc.epoch_mode    = string(sprintf('events [%g %g] s', cfg.window(1), cfg.window(2)));

nRequested = sum(nAvail);
EEG = pop_epoch(EEG, found, cfg.window, 'epochinfo', 'yes');

qc.n_epochs_built = EEG.trials;
% Events matched minus epochs built. Two causes, both silent in pop_epoch:
% an event too close to either end for the full window, and an epoch
% spanning a boundary left by clean_rawdata or prep_concat.
qc.n_epochs_lost  = nRequested - EEG.trials;

if qc.n_epochs_lost > 0
    warning('prep_epoch:epochsDropped', ...
        ['%d of %d matched events did not yield an epoch (too close to the\n' ...
         'recording edge for a [%g %g] s window, or spanning a discontinuity).'], ...
         qc.n_epochs_lost, nRequested, cfg.window(1), cfg.window(2));
end
end


% =========================================================================
function [EEG, qc] = reject_epochs(EEG, cfg, qc)
% Mark with each criterion independently, then remove once.

thr = cfg.epochThresh;
sd  = cfg.epochProbSD;

bad  = false(1, EEG.trials);
used = {};

if ~isempty(thr)
    E = pop_eegthresh(EEG, 1, 1:EEG.nbchan, -abs(thr), abs(thr), ...
                      EEG.xmin, EEG.xmax, 0, 0);
    hit = flagvec(E, 'rejthresh', EEG.trials);
    qc.n_epochs_rej_thresh = sum(hit);
    bad  = bad | hit;
    used{end+1} = sprintf('thresh %g uV', abs(thr));
end

if ~isempty(sd)
    E = pop_jointprob(EEG, 1, 1:EEG.nbchan, sd, sd, 0, 0);
    hit = flagvec(E, 'rejjp', EEG.trials);
    qc.n_epochs_rej_prob = sum(hit);
    bad  = bad | hit;
    used{end+1} = sprintf('jointprob %g SD', sd);
end

qc.epoch_reject      = string(strjoin(used, ' + '));
qc.n_epochs_rejected = sum(bad);
qc.epoch_rej_frac    = qc.n_epochs_rejected / EEG.trials;

maxFrac = cfg.epochMaxRejFrac;
if qc.epoch_rej_frac > maxFrac
    % A warning, not an error. Which subjects to drop is a decision for the
    % analysis, made from the QC row.
    warning('prep_epoch:highRejection', ...
        ['%.0f%% of epochs rejected (%d of %d), above cfg.epochMaxRejFrac = %.0f%%.\n' ...
         'Check <subject>_qc_data.png before using this subject.'], ...
         100*qc.epoch_rej_frac, qc.n_epochs_rejected, EEG.trials, 100*maxFrac);
end

if all(bad)
    error('prep_epoch:allEpochsRejected', ...
        'Every one of the %d epochs was rejected by %s.', ...
        EEG.trials, strjoin(used, ' + '));
end

if any(bad)
    EEG = pop_rejepoch(EEG, find(bad), 0);
end
end


% =========================================================================
function v = flagvec(EEG, field, n)
% pop_eegthresh and pop_jointprob leave their flag field untouched when
% nothing was marked, so it can be absent or empty rather than all-false.
v = false(1, n);
if isfield(EEG, 'reject') && isfield(EEG.reject, field) && ~isempty(EEG.reject.(field))
    f = logical(EEG.reject.(field)(:)');
    v(1:min(n, numel(f))) = f(1:min(n, numel(f)));
end
end


% =========================================================================
function s = count_per_condition(EEG, types)
% Trials per condition, since a single total hides a condition that lost
% most of its trials.
lab = prep_epoch_labels(EEG, types);
parts = cell(1, numel(types));
for k = 1:numel(types)
    parts{k} = sprintf('%s:%d', types{k}, sum(lab == string(types{k})));
end
s = string(strjoin(parts, '|'));
end


% =========================================================================
function c = event_type_strings(EEG)
% EEG.event.type is char in most importers and numeric in some. pop_epoch
% handles both; the comparison here has to as well.
c = cell(1, numel(EEG.event));
for k = 1:numel(EEG.event)
    c{k} = deblank(prep_event_str(EEG.event(k).type));
end
end
