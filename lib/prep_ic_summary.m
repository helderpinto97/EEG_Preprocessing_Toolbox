function s = prep_ic_summary(ic)
% PREP_IC_SUMMARY  Unpack what the ICLabel sheets draw from, once.
%
%   s = prep_ic_summary(ic)   ic is pre.ic, built in prep_subject
%
% Returns a struct with:
%   probs      nIC-by-nClass, the classifier output
%   pmax       probability of the top class, per component
%   winner     index of the top class, per component
%   nIC        number of components
%   flagged    1-by-nIC logical, what the threshold rule marked
%   removable  class rows cfg.icaRemove resolved to
%   exempt     the class rows the rule could never act on
%
% Two sheets read the same struct, and before this they each derived these
% values with their own copy of the same five lines. A change to the shape
% of pre.ic had to be tracked into both, and neither errors when it is not:
% both degrade quietly by design, so the sheets would disagree with nothing
% to show it. The same argument prep_epoch_labels makes for the epoch label
% rule applies here.

probs = ic.classifications;
nIC   = size(probs, 1);

flagged = ic.flagged(:)';
if numel(flagged) ~= nIC, flagged = false(1, nIC); end

[pmax, winner] = max(probs, [], 2);

s.probs     = probs;
s.pmax      = pmax;
s.winner    = winner;
s.nIC       = nIC;
s.flagged   = flagged;
s.removable = ic.removable;
s.exempt    = setdiff(1:numel(ic.classes), ic.removable);
end
