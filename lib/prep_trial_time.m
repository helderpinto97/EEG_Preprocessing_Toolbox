function lat = prep_trial_time(EEG)
% PREP_TRIAL_TIME  When each trial happened, in seconds from the start of
% the recording.
%
%   lat = prep_trial_time(EEG)   1-by-EEG.trials, seconds
%
% pop_epoch rewrites EEG.event latencies relative to the epochs laid end to
% end, so they no longer answer this. EEG.urevent keeps the original
% continuous latencies and each epoch points back into it.
%
% Without a urevent table, falls back to trial order times the epoch length.
% Data built in memory rather than loaded from a file has no urevent. The
% axis is then approximate, which beats an empty one.

lat = nan(1, EEG.trials);

if isfield(EEG, 'urevent') && ~isempty(EEG.urevent) && ...
   isfield(EEG, 'epoch')   && ~isempty(EEG.epoch)   && ...
   isfield(EEG.epoch, 'eventurevent')

    for e = 1:min(numel(EEG.epoch), EEG.trials)
        % Same rule prep_epoch_labels uses to pick the time-locking event,
        % so the figure axis and the trial counts cannot disagree about
        % which event a trial is locked to.
        k  = prep_epoch_zero(EEG.epoch(e));
        ur = EEG.epoch(e).eventurevent;
        if ~iscell(ur), ur = {ur}; end

        if isempty(k), continue, end
        k = k(1);
        if k > numel(ur) || isempty(ur{k}) || ~isnumeric(ur{k})
            continue
        end
        if ur{k} >= 1 && ur{k} <= numel(EEG.urevent)
            lat(e) = double(EEG.urevent(ur{k}).latency) / EEG.srate;
        end
    end
end

% All or nothing. Filling in only the unplaced trials would put some points
% at their measured time and the rest at an estimate, on one axis, with
% nothing to tell them apart.
if any(isnan(lat))
    lat = (1:EEG.trials) * EEG.pnts / EEG.srate;
end
end
