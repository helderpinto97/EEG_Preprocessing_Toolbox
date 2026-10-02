function [lab, ev] = prep_epoch_labels(EEG, types)
% PREP_EPOCH_LABELS  The time-locking event of each epoch.
%
%   [lab, ev] = prep_epoch_labels(EEG, types)
%
% LAB is the event type of each epoch (1-by-EEG.trials string, "" where
% none), EV its index within EEG.epoch(e) (NaN where none). The time-locking
% event is the one at latency 0; when several share it, one of TYPES is
% preferred. prep_epoch, prep_trial_time and prep_qcfig_epochs all use this,
% so the counts, the time axis and the figure agree.

lab = strings(1, EEG.trials);
ev  = NaN(1, EEG.trials);
if ~isfield(EEG, 'epoch') || isempty(EEG.epoch), return, end

for e = 1:min(numel(EEG.epoch), EEG.trials)
    ty = EEG.epoch(e).eventtype;
    l  = EEG.epoch(e).eventlatency;
    if ~iscell(ty), ty = {ty}; end
    if ~iscell(l),  l  = {l};  end
    if numel(ty) ~= numel(l), continue, end
    atZero = find(cellfun(@(x) isnumeric(x) && isscalar(x) && abs(x) < 1e-6, l));
    if isempty(atZero), continue, end

    pick = atZero(1);
    for c = atZero
        if any(strcmp(prep_event_str(ty{c}, ''), types)), pick = c; break, end
    end
    lab(e) = string(prep_event_str(ty{pick}, ''));
    ev(e)  = pick;
end
end
