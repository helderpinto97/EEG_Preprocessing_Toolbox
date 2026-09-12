function [EEG, qc] = prep_noneeg(EEG, cfg)
% PREP_NONEEG  Remove non-EEG channels before the EEG-only steps.
%
% clean_rawdata, ASR and the rank estimate all assume an EEG-only matrix: a
% trigger or auxiliary channel breaks the neighbour-correlation criterion and
% inflates the apparent rank.
%
% Channels are identified two ways, and a channel matching either is dropped:
%
%   cfg.nonEEG       label patterns, case-insensitive, matched against the
%                    whole label. '*' and '?' wildcards are supported, so
%                    one entry covers a family: 'EXG*' catches EXG1..EXG8,
%                    '*EOG*' catches EOG, VEOG, HEOG_L and EOGv. Exact
%                    strings still work.
%
%   cfg.nonEEGTypes  patterns matched against chanlocs.type, which most
%                    importers populate ('EOG', 'MISC', 'TRIG'). Consulted
%                    only when the field exists and is non-empty, since many
%                    recordings leave it blank.
%
% Mastoids and earlobes (M1/M2, A1/A2, TP9/TP10) are not in the defaults.
% They are often the reference or part of the montage, and dropping them
% silently is worse than keeping an extra channel.

if isempty(EEG.chanlocs) || ~isfield(EEG.chanlocs, 'labels')
    error('prep_noneeg:noLabels', ...
        ['This recording has no channel labels, so non-EEG channels cannot\n' ...
         'be identified. Fix the import, or supply a montage via\n' ...
         'cfg.chanlocFile so labels exist before this step.']);
end

labels = cellstr(string({EEG.chanlocs.labels}));
isNon  = match_patterns(labels, cfg.nonEEG);

if isfield(EEG.chanlocs, 'type')
    types = {EEG.chanlocs.type};
    ok    = cellfun(@(t) ischar(t) || isstring(t), types);
    types(~ok) = {''};
    types = cellstr(string(types));
    isNon = isNon | match_patterns(types, cfg.nonEEGTypes);
end

qc.nchan_nonEEG = sum(isNon);
qc.chans_nonEEG = string(strjoin(labels(isNon), '|'));

if all(isNon)
    error('prep_noneeg:allDropped', ...
        ['Every one of the %d channels matched cfg.nonEEG / cfg.nonEEGTypes.\n' ...
         'Labels: %s\nCheck the patterns before rerunning.'], ...
         numel(labels), strjoin(labels(1:min(end,15)), ', '));
end

if any(isNon)
    EEG = pop_select(EEG, 'channel', find(~isNon));
end
qc.nchan_eeg = EEG.nbchan;
end

% Auxiliary Functions
function tf = match_patterns(strs, patterns)
tf = false(1, numel(strs));
if isempty(patterns), return; end
if ischar(patterns) || isstring(patterns), patterns = cellstr(patterns); end

for k = 1:numel(patterns)
    p = char(patterns{k});
    if isempty(p), continue; end
    rx  = ['^' regexptranslate('wildcard', p) '$'];
    hit = ~cellfun(@isempty, regexpi(strs, rx, 'once'));
    tf  = tf | reshape(hit, 1, []);
end
end
