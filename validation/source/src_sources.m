function [S, Ctrue, trip] = src_sources(cond, nPar, T, trips, src, seed, amp)
% SRC_SOURCES  One white Gaussian source per parcel, with a known covariance.
%
%   [S, Ctrue, trip] = src_sources(cond, nPar, T, trips, src, seed, amp)
%
% cond   'null', 'red_near', 'red_far', 'syn_near' or 'syn_far'
% trips  struct with fields near and far, each three parcel indices
% amp    amplitude of the parcels outside the triplet (1 = all equally
%        active, 0.1 = sparse). O-information does not depend on scale, so
%        the true values are the same.
% S      nPar x T source time courses
% Ctrue  their covariance, from which the true O-information follows
% trip   the parcels of the multiplet (the near triplet for 'null')
%
% null      all sources independent, true O = 0 for every triplet
% red_*     x_i = a*s + e_i on the triplet          (redundancy, O > 0)
% syn_*     x3 = x1 + x2 + b*e, x1 and x2 independent (synergy, O < 0)

rng(seed);
S = randn(nPar, T);
Ctrue = eye(nPar);
if strcmp(cond, 'null')
    trip = trips.near;
    parts = {'null'};
else
    parts = split(cond, '_');
    trip  = trips.(parts{2});
end
rest = setdiff(1:nPar, trip);
S(rest, :) = amp * S(rest, :);
Ctrue(rest, rest) = amp^2 * Ctrue(rest, rest);
switch parts{1}
    case 'red'
        a = src.redA;
        S(trip, :) = a * randn(1, T) + randn(3, T);
        Ctrue(trip, trip) = a^2 * ones(3) + eye(3);
    case 'syn'
        b = src.synB;
        S(trip(3), :) = S(trip(1), :) + S(trip(2), :) + b * randn(1, T);
        Ctrue(trip, trip) = [1 0 1; 0 1 1; 1 1 2 + b^2];
end
end
