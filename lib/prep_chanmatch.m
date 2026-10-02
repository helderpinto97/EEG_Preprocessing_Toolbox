function tf = prep_chanmatch(chanlocs, labelPats, typePats)
% PREP_CHANMATCH  Channels whose label or chanlocs.type matches a pattern.
%
%   tf = prep_chanmatch(EEG.chanlocs, cfg.nonEEG, cfg.nonEEGTypes)
%
% Patterns match the whole string, case-insensitive, with '*' and '?'
% wildcards: 'EXG*' catches EXG1..EXG8, '*EOG*' catches VEOG and HEOG_L.
% Types are read only when the field exists; non-text types count as ''.
% Shared by prep_noneeg and prep_ecgref.

tf = match(cellstr(string({chanlocs.labels})), labelPats);
if isfield(chanlocs, 'type')
    types = {chanlocs.type};
    types(~cellfun(@(t) ischar(t) || isstring(t), types)) = {''};
    tf = tf | match(cellstr(string(types)), typePats);
end
end

function tf = match(strs, patterns)
tf = false(1, numel(strs));
if ischar(patterns) || isstring(patterns), patterns = cellstr(patterns); end
for k = 1:numel(patterns)
    p = char(patterns{k});
    if isempty(p), continue, end
    hit = ~cellfun(@isempty, regexpi(strs, ['^' regexptranslate('wildcard', p) '$'], 'once'));
    tf  = tf | reshape(hit, 1, []);
end
end
