function [O, p, Of, f] = src_oir_full(X, trip, p, fs, nfft, pmax)
% SRC_OIR_FULL  O-information rate of triplets from one VAR on all parcels.
%
%   [O, p, Of, f] = src_oir_full(X, trip, p, fs, nfft)
%   [O, p]        = src_oir_full(X, trip, [], fs, nfft, pmax)   order by MDL
%
% Fits one VAR(p) to all parcels (X, parcels x samples; oir_idVAR), computes
% its spectral matrix S(f) (sir_VARspectra of the SIR toolbox) and restricts
% it to each triplet: S(trip, trip, f) is the exact spectrum of the triplet
% within the full model, so no model is refitted per triplet. For three
% processes the spectral OIR (Faes et al. 2022; sir_deltaO) is symmetric:
%   O(f) = 1/2 [ sum_i log S_ii - sum_pairs log det S_pair + log det S_abc ]
% and O is its mean over 0..fs/2. Of is k x nfft, f the frequencies.
% Needs more samples and data rank than parcels; use few parcels (coarse20).

tb = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'lib', 'toolboxes');
if isempty(which('oir_idVAR')), addpath(fullfile(tb, 'OIR')); end
if isempty(which('sir_VARspectra')), addpath(fullfile(tb, 'SIR_toolbox', 'functions')); end
if isempty(p), [~, p] = sir_mos_idMVAR(X, pmax); end   % MDL order
[Am, Su] = oir_idVAR(X, p);
[S, ~, f] = sir_VARspectra(Am, Su, nfft, fs);
n  = size(S, 1);
S2 = reshape(S, n * n, []);
s  = @(i, j) S2(sub2ind([n n], i, j), :);       % k x nfft cross-spectra
a = trip(:, 1); b = trip(:, 2); c = trip(:, 3);
Saa = real(s(a, a)); Sbb = real(s(b, b)); Scc = real(s(c, c));
Sab = s(a, b); Sac = s(a, c); Sbc = s(b, c);
dab = Saa .* Sbb - abs(Sab).^2;
dac = Saa .* Scc - abs(Sac).^2;
dbc = Sbb .* Scc - abs(Sbc).^2;
dabc = Saa .* Sbb .* Scc + 2 * real(Sab .* Sbc .* conj(Sac)) ...
     - Saa .* abs(Sbc).^2 - Sbb .* abs(Sac).^2 - Scc .* abs(Sab).^2;
Of = 0.5 * (log(Saa) + log(Sbb) + log(Scc) - log(dab) - log(dac) - log(dbc) + log(dabc));
O  = mean(Of, 2);
end
