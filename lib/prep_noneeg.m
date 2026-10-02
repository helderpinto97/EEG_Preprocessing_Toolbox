function [EEG, qc] = prep_noneeg(EEG, cfg)
% PREP_NONEEG  Remove non-EEG channels before the EEG-only steps.
%
% A channel is dropped when its label matches cfg.nonEEG or its
% chanlocs.type matches cfg.nonEEGTypes (see prep_chanmatch). Trigger and
% auxiliary channels break the neighbour correlation of clean_rawdata and
% inflate the rank.

if isempty(EEG.chanlocs) || ~isfield(EEG.chanlocs, 'labels')
    error('prep_noneeg:noLabels', ...
        'This recording has no channel labels; fix the import or set cfg.chanlocFile.');
end
labels = cellstr(string({EEG.chanlocs.labels}));
isNon  = prep_chanmatch(EEG.chanlocs, cfg.nonEEG, cfg.nonEEGTypes);
qc.nchan_nonEEG = sum(isNon);
qc.chans_nonEEG = string(strjoin(labels(isNon), '|'));
if all(isNon)
    error('prep_noneeg:allDropped', ...
        'Every one of the %d channels matched cfg.nonEEG / cfg.nonEEGTypes. Labels: %s', ...
        numel(labels), strjoin(labels(1:min(end, 15)), ', '));
end
if any(isNon)
    EEG = pop_select(EEG, 'channel', find(~isNon));
end
qc.nchan_eeg = EEG.nbchan;
end
