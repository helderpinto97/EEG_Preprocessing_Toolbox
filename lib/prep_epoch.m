function [EEG, qc] = prep_epoch(EEG, cfg)
% PREP_EPOCH  Epoch, correct the baseline, and optionally reject epochs.
%
%   Time-locked:  cfg.events {'S 1','S 2'}, cfg.window [-0.2 0.8] s
%   Fixed length: cfg.epochLength 2 s, cfg.epochOverlap 0
%   Either:       cfg.baseline [-200 0] ms ([] = none), cfg.epochReject,
%                 cfg.epochThresh, cfg.epochProbSD, cfg.epochMaxRejFrac
%
% Neither mode set leaves the data continuous. Requested event types that
% are missing, and epochs that could not be built, are reported in the QC
% row, since pop_epoch drops both silently.

% Every field exists whether or not the recording is epoched, so all QC
% rows have the same columns.
qc = struct('n_epochs', NaN, 'n_epochs_built', NaN, 'n_epochs_lost', NaN, ...
            'n_epochs_rejected', NaN, 'n_epochs_rej_thresh', NaN, 'n_epochs_rej_prob', NaN, ...
            'epoch_rej_frac', NaN, 'epoch_events', "", 'epoch_missing', "", ...
            'epoch_counts', "", 'epoch_mode', "", 'baseline', "", 'epoch_reject', "off");

if ~isempty(cfg.epochLength)
    [EEG, qc, found] = fixed_epochs(EEG, cfg, qc);
elseif ~isempty(cfg.events)
    [EEG, qc, found] = event_epochs(EEG, cfg, qc);
else
    return
end

if isempty(cfg.baseline)
    qc.baseline = "none";
else
    EEG = pop_rmbase(EEG, cfg.baseline);
    qc.baseline = string(sprintf('%g %g ms', cfg.baseline(1), cfg.baseline(2)));
end

if cfg.epochReject
    [EEG, qc] = reject_epochs(EEG, cfg, qc);
end

% Trials per condition: a total alone hides a condition that lost most.
qc.n_epochs = EEG.trials;
lab = prep_epoch_labels(EEG, found);
qc.epoch_counts = string(strjoin(cellfun(@(t) sprintf('%s:%d', t, sum(lab == string(t))), ...
                                         found, 'UniformOutput', false), '|'));
end

%% Auxiliary functions
function [EEG, qc, found] = fixed_epochs(EEG, cfg, qc)
% Contiguous epochs via eeg_regepochs, which drops the remainder at the end
% and epochs spanning a boundary.
if EEG.trials > 1
    error('prep_epoch:alreadyEpoched', ...
        'Fixed-length epoching needs continuous data; this set has %d trials.', EEG.trials);
end
L     = cfg.epochLength;
recur = L * (1 - cfg.epochOverlap);
dur   = EEG.xmax - EEG.xmin;
if recur > dur
    error('prep_epoch:epochTooLong', ...
        'cfg.epochLength %g s (step %g s) is longer than the %.1f s recording.', L, recur, dur);
end

found    = {'fixed'};
nPlanned = floor((EEG.xmax + 1/EEG.srate) / recur);   % as eeg_regepochs counts
EEG = eeg_regepochs(EEG, 'recurrence', recur, 'limits', [0 L], 'rmbase', NaN, 'eventtype', found{1});

qc.n_epochs_built = EEG.trials;
qc.n_epochs_lost  = max(0, nPlanned - EEG.trials);
qc.epoch_events   = "fixed";
qc.epoch_mode     = string(sprintf('fixed %g s', L));
if cfg.epochOverlap > 0
    qc.epoch_mode = qc.epoch_mode + string(sprintf(', %g%% overlap', 100*cfg.epochOverlap));
end
if qc.n_epochs_lost > 0
    warning('prep_epoch:epochsDropped', ...
        '%d of %d planned epochs were dropped (end of recording or a discontinuity).', ...
        qc.n_epochs_lost, nPlanned);
end
end

function [EEG, qc, found] = event_epochs(EEG, cfg, qc)
types = deblank(cellstr(string(cfg.events(:)))');
if isempty(EEG.event)
    error('prep_epoch:noEventStruct', ...
        'cfg.events asks for %s but the recording carries no events.', strjoin(types, ', '));
end

present = cellfun(@(t) deblank(prep_event_str(t)), {EEG.event.type}, 'UniformOutput', false);
nAvail  = cellfun(@(t) sum(strcmp(t, present)), types);
missing = types(nAvail == 0);
found   = types(nAvail > 0);
if isempty(found)
    error('prep_epoch:noMatchingEvents', ...
        'None of the requested event types occur.\n  requested: %s\n  available: %s', ...
        strjoin(types, ', '), strjoin(unique(present), ', '));
end
if ~isempty(missing)
    % Not fatal (a design can omit a condition), but usually a label mismatch.
    warning('prep_epoch:missingEvents', ...
        'Requested event type(s) not present: %s\nEpoching on %s only. Available: %s', ...
        strjoin(missing, ', '), strjoin(found, ', '), strjoin(unique(present), ', '));
end

qc.epoch_events  = string(strjoin(found, '|'));
qc.epoch_missing = string(strjoin(missing, '|'));
qc.epoch_mode    = string(sprintf('events [%g %g] s', cfg.window(1), cfg.window(2)));

EEG = pop_epoch(EEG, found, cfg.window, 'epochinfo', 'yes');
qc.n_epochs_built = EEG.trials;
qc.n_epochs_lost  = sum(nAvail) - EEG.trials;   % too close to an edge or a boundary
if qc.n_epochs_lost > 0
    warning('prep_epoch:epochsDropped', ...
        '%d of %d matched events did not yield an epoch (recording edge or a discontinuity).', ...
        qc.n_epochs_lost, sum(nAvail));
end
end

function [EEG, qc] = reject_epochs(EEG, cfg, qc)
% Both criteria mark first and the removal happens once, so the second does
% not index epochs the first already removed.
bad  = false(1, EEG.trials);
used = {};
if ~isempty(cfg.epochThresh)
    thr = abs(cfg.epochThresh);
    hit = flagvec(pop_eegthresh(EEG, 1, 1:EEG.nbchan, -thr, thr, EEG.xmin, EEG.xmax, 0, 0), ...
                  'rejthresh', EEG.trials);
    qc.n_epochs_rej_thresh = sum(hit);
    bad = bad | hit;
    used{end+1} = sprintf('thresh %g uV', thr);
end
if ~isempty(cfg.epochProbSD)
    sd  = cfg.epochProbSD;
    hit = flagvec(pop_jointprob(EEG, 1, 1:EEG.nbchan, sd, sd, 0, 0), 'rejjp', EEG.trials);
    qc.n_epochs_rej_prob = sum(hit);
    bad = bad | hit;
    used{end+1} = sprintf('jointprob %g SD', sd);
end

qc.epoch_reject      = string(strjoin(used, ' + '));
qc.n_epochs_rejected = sum(bad);
qc.epoch_rej_frac    = qc.n_epochs_rejected / EEG.trials;
if qc.epoch_rej_frac > cfg.epochMaxRejFrac
    % A warning: dropping subjects is a decision for the analysis.
    warning('prep_epoch:highRejection', ...
        '%.0f%% of epochs rejected (%d of %d), above cfg.epochMaxRejFrac = %.0f%%.', ...
        100*qc.epoch_rej_frac, qc.n_epochs_rejected, EEG.trials, 100*cfg.epochMaxRejFrac);
end
if all(bad)
    error('prep_epoch:allEpochsRejected', 'Every one of the %d epochs was rejected by %s.', ...
          EEG.trials, strjoin(used, ' + '));
end
if any(bad)
    EEG = pop_rejepoch(EEG, find(bad), 0);
end
end

function v = flagvec(EEG, field, n)
% The flag field can be absent or empty when nothing was marked.
v = false(1, n);
if isfield(EEG.reject, field) && ~isempty(EEG.reject.(field))
    f = logical(EEG.reject.(field)(:)');
    v(1:min(n, numel(f))) = f(1:min(n, numel(f)));
end
end
