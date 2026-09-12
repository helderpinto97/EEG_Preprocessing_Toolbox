function lab = prep_epoch_labels(EEG, types)
% PREP_EPOCH_LABELS  The time-locking event type of each epoch.
%
%   lab = prep_epoch_labels(EEG, types)
%
% Returns a 1-by-EEG.trials string array, empty where no type could be read.
% TYPES is the list the caller asked to epoch on.
%
% The time-locking event is the one at latency 0. Several events can share
% that latency, a stimulus code and a marker written by the same trigger for
% example, so prefer one the caller asked for.
%
% prep_epoch counts trials per condition with this, and prep_qcfig_epochs
% splits its panels with it. They have to agree. A figure labelled by a
% different rule than the epoching used would be wrong with nothing to show
% it, which is why this lives in one file rather than two.

lab = strings(1, EEG.trials);
if ~isfield(EEG, 'epoch') || isempty(EEG.epoch), return, end

for e = 1:min(numel(EEG.epoch), EEG.trials)
    [atZero, ty] = prep_epoch_zero(EEG.epoch(e));
    if isempty(atZero), continue, end

    % Several events can share latency 0, a stimulus code and a marker
    % written by the same trigger for example, so prefer one the caller
    % asked to epoch on.
    pick = atZero(1);
    for c = atZero
        if any(strcmp(prep_event_str(ty{c}, ''), types)), pick = c; break, end
    end
    lab(e) = string(prep_event_str(ty{pick}, ''));
end
end
