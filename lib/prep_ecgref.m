function [ECG, qc] = prep_ecgref(EEG, cfg)
% PREP_ECGREF  Keep the recorded ECG channels aside, for the cardiac rule.
%
% Called before prep_noneeg drops them. Returns the channels matching
% cfg.ecgChannels (label or chanlocs.type) as they were recorded, or []
% when there are none or cfg.ecgCorr is empty. ICLabel often calls cardiac
% components Brain; the correlation with a recorded ECG does not.

ECG = [];
qc.ecg_channels = "";
if isempty(cfg.ecgCorr) || isempty(cfg.ecgChannels) || isempty(EEG.chanlocs), return, end
isEcg = prep_chanmatch(EEG.chanlocs, cfg.ecgChannels, cfg.ecgChannels);
if ~any(isEcg), return, end
ECG = pop_select(EEG, 'channel', find(isEcg));
qc.ecg_channels = string(strjoin({ECG.chanlocs.labels}, '|'));
end
