function r = prep_rank(EEG)
% PREP_RANK  Numerical rank of the channel data, for the ICA dimension.
%
% Running ICA above the true rank (after average reference, interpolation or
% component removal) splits components into ghost pairs. The estimate uses
% up to 30000 usable samples spread over the whole recording, so a flat
% opening segment cannot drive it to zero.

nSamples = 30000;
nch = size(EEG.data, 1);
D   = reshape(EEG.data, nch, []);          % epoched data too; no copy

% Screen a candidate grid, not every sample, to avoid full-size temporaries.
npts = size(D, 2);
cand = unique(round(linspace(1, npts, min(npts, 10 * nSamples))));
G    = D(:, cand);
idx  = cand(all(isfinite(G), 1) & any(G ~= 0, 1));
if isempty(idx)
    error('prep:rankEmpty', 'No usable samples for a rank estimate.');
end
if numel(idx) > nSamples
    idx = idx(round(linspace(1, numel(idx), nSamples)));
end
X = double(D(:, idx));
if size(X, 2) < 10 * nch
    warning('prep:rankSamples', '%d usable samples for %d channels; the rank estimate is unreliable.', ...
            size(X, 2), nch);
end

% The smaller of MATLAB rank() and a relative cut; erring low is safe.
s = svd(X', 'econ');
r = min(sum(s > max(size(X)) * eps(s(1))), sum(s > s(1) * 1e-6));

% EEGLAB uses an absolute 1e-7 eigenvalue cut, which assumes microvolts.
% Disagreement means the data are probably not in microvolts.
rAbs = sum(eig(cov(X', 1)) > 1e-7);
if rAbs ~= r
    warning('prep:rankUnits', ...
        ['Rank %d, but the absolute 1e-7 criterion of EEGLAB gives %d. The data are ' ...
         'probably not in microvolts, which also affects pop_runica and ICLabel. Using %d.'], r, rAbs, r);
end
r = max(1, min(r, nch));
end
