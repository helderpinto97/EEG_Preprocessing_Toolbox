function [k, ty] = prep_epoch_zero(ep)
% PREP_EPOCH_ZERO  Which events in one epoch sit at latency 0.
%
%   [k, ty] = prep_epoch_zero(EEG.epoch(e))
%
% K indexes the events at latency 0, in order. TY is that epoch's event
% types, normalised to a cell array so K indexes it directly. K is empty
% when the epoch carries nothing at 0, or when the type and latency lists
% disagree in length and cannot be paired.
%
% The time-locking event is the one at latency 0, and both prep_epoch_labels
% and prep_trial_time have to find it. They want different things from it,
% a type and a urevent index, but the rule for locating it is the same rule
% and a tolerance of 1e-6 either agrees or it does not. Two copies of it can
% drift apart while both keep working, which is the case prep_epoch_labels
% argues against in its own header.

k  = [];
ty = {};
if isempty(ep), return, end

ty = ep.eventtype;
l  = ep.eventlatency;
if ~iscell(ty), ty = {ty}; end
if ~iscell(l),  l  = {l};  end
if numel(ty) ~= numel(l), ty = {}; return, end

k = find(cellfun(@(x) isnumeric(x) && isscalar(x) && abs(x) < 1e-6, l));
end
