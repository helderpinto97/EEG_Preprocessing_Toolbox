function lat = prep_trial_time(EEG)
% PREP_TRIAL_TIME  When each trial happened, in seconds from the start.
%
%   lat = prep_trial_time(EEG)   1-by-EEG.trials
%
% Read from EEG.urevent, which keeps the continuous latencies that pop_epoch
% rewrites. Without it, or if any trial cannot be placed, falls back to
% trial order times the epoch length for all trials (never a mix).

lat = nan(1, EEG.trials);
if isfield(EEG, 'urevent') && ~isempty(EEG.urevent) && ...
   isfield(EEG, 'epoch') && isfield(EEG.epoch, 'eventurevent')
    [~, ev] = prep_epoch_labels(EEG, {});
    for e = find(~isnan(ev))
        ur = EEG.epoch(e).eventurevent;
        if ~iscell(ur), ur = {ur}; end
        if ev(e) > numel(ur), continue, end
        u = ur{ev(e)};
        if isnumeric(u) && isscalar(u) && u >= 1 && u <= numel(EEG.urevent)
            lat(e) = double(EEG.urevent(u).latency) / EEG.srate;
        end
    end
end
if any(isnan(lat))
    lat = (1:EEG.trials) * EEG.pnts / EEG.srate;
end
end
