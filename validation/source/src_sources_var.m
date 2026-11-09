function [S, truth, trip] = src_sources_var(cond, nPar, T, trips, src, seed, amp)
% SRC_SOURCES_VAR  Regional signals with dynamics, for the rate measures.
%
%   [S, truth, trip] = src_sources_var(cond, nPar, T, trips, src, seed, amp)
%
% As src_sources, but every parcel is an AR(2) oscillator instead of white
% noise, and the target triplet interacts through lagged couplings:
%   red_*  common driver: x1 -> x2 and x1 -> x3        (redundancy)
%   syn_*  common target: x1 -> x3 and x2 -> x3        (synergy)
%   null   no coupling
% at lag src.var.lag samples with coefficient src.var.c. The triplet
% oscillates at src.var.fTrip Hz, the other parcels at random frequencies
% in src.var.fRange. Each parcel is scaled to unit variance, the parcels
% outside the triplet to amp. truth holds the true triplet VAR (Am, Su,
% target last) and its exact OIR (O, Olag, Oinst; src_oir3), all 0 for null.

v = src.var;
rng(seed);
fs = src.srate;
if strcmp(cond, 'null'), trip = trips.near; else, trip = trips.(extractAfter(cond, '_')); end
trip = sort(trip(:))';

% triplet VAR, order: trip(1) trip(2) trip(3)
p  = max(2, v.lag);
Ak = zeros(3, 3, p);
for i = 1:3
    Ak(i, i, 1) = 2 * v.r * cos(2*pi*v.fTrip/fs);
    Ak(i, i, 2) = -v.r^2;
end
switch extractBefore([cond '_'], '_')
    case 'red', Ak(2, 1, v.lag) = v.c; Ak(3, 1, v.lag) = v.c;   % Ak(target, source, lag)
    case 'syn', Ak(3, 1, v.lag) = v.c; Ak(3, 2, v.lag) = v.c;
end
truth.Am = reshape(Ak, 3, []);
truth.Su = eye(3);
[truth.O, truth.Olag, truth.Oinst] = src_oir3([], [], [], truth.Am, truth.Su);

% simulate: triplet jointly, the rest as independent AR(2) oscillators
burn = 1000;
S = zeros(nPar, T);
E = randn(3, T + burn);
Y = filter_var(truth.Am, E);
S(trip, :) = Y(:, burn+1:end);
others = setdiff(1:nPar, trip);
f = v.fRange(1) + diff(v.fRange) * rand(numel(others), 1);
for k = 1:numel(others)
    a = [1, -2 * v.r * cos(2*pi*f(k)/fs), v.r^2];
    y = filter(1, a, randn(1, T + burn));
    S(others(k), :) = y(burn+1:end);
end
S = S ./ std(S, 0, 2);
S(others, :) = amp * S(others, :);
end

function Y = filter_var(Am, E)
% Y(:,t) = sum_k A(k) Y(:,t-k) + E(:,t)
[M, n] = size(E);
p = size(Am, 2) / M;
Y = zeros(M, n);
for t = p+1:n
    Y(:, t) = Am * reshape(Y(:, t-1:-1:t-p), [], 1) + E(:, t);
end
end
