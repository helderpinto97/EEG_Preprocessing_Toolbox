function s = prep_ic_summary(ic)
% PREP_IC_SUMMARY  Unpack pre.ic once for both component sheets.
%
%   probs, pmax, winner   classifier output, top probability and class
%   nIC, flagged, reason  removed components and the rule that removed them
%                         ("" = ICLabel or kept)
%   removable, exempt     class rows that can and cannot be removed
%   thresh, threshText    per-class thresholds (a scalar applies to all),
%                         and "0.80, Muscle 0.50" for titles

s.probs = ic.classifications;
s.nIC   = size(s.probs, 1);
[s.pmax, s.winner] = max(s.probs, [], 2);

s.flagged = ic.flagged(:)';
if numel(s.flagged) ~= s.nIC, s.flagged = false(1, s.nIC); end
s.reason = strings(1, s.nIC);
if isfield(ic, 'reason') && numel(ic.reason) == s.nIC, s.reason = ic.reason(:)'; end

s.removable = ic.removable;
s.exempt    = setdiff(1:numel(ic.classes), ic.removable);
s.thresh    = ic.thresh(:)';
if isscalar(s.thresh), s.thresh = repmat(s.thresh, 1, numel(ic.classes)); end
base = mode(s.thresh(ic.removable));
s.threshText = sprintf('%.2f', base);
odd = ic.removable(s.thresh(ic.removable) ~= base);
for k = odd(:)'
    s.threshText = sprintf('%s, %s %.2f', s.threshText, ic.classes{k}, s.thresh(k));
end
end
