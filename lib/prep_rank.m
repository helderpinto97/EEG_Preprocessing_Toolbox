function r = prep_rank(EEG)
% PREP_RANK  Numerical rank of the channel data.
%
% The result feeds pop_runica's 'pca' argument, so it has to agree with
% what pop_runica decides internally. Running ICA at the nominal channel
% count on rank-deficient data, after average referencing, interpolation or
% component subtraction, splits components into ghost pairs and makes
% ICLabel meaningless.
%
% The estimate reads NSAMPLES columns, spread evenly across the recording
% rather than taken from the front.

nSamples = 30000;

% Epoched data is nbchan x pnts x trials, and size(EEG.data,2) is then pnts
% rather than pnts*trials. Two subscripts do not error, since MATLAB
% collapses the trailing dimensions, but the sample count comes out as one
% epoch's worth: a 64-channel montage ranked from 200 samples. Flatten
% explicitly instead.
nch = size(EEG.data, 1);
D   = reshape(EEG.data, nch, []);   % shares the buffer, nothing is copied

% Spread the sample across the whole recording. Taking the first N lets a
% flat or saturated opening segment dominate: a dead first 120 s drives the
% estimate to 0, and that 0 reaches pop_runica as its 'pca' dimension.
%
% The usability test runs on a candidate grid rather than on every column.
% Screening the whole recording first would read every sample and allocate
% two logical arrays the size of the data, several gigabytes on a long file,
% to end up keeping 30000 columns. The grid is cut 10x oversize so there is
% room to discard unusable columns and still fill the quota.
npts = size(D, 2);
cand = unique(round(linspace(1, npts, min(npts, 10 * nSamples))));

G   = D(:, cand);
ok  = all(isfinite(G), 1) & any(G ~= 0, 1);
idx = cand(ok);
if isempty(idx)
    error('prep:rankEmpty', 'No usable samples for a rank estimate.');
end
if numel(idx) > nSamples
    idx = idx(round(linspace(1, numel(idx), nSamples)));
end

% Indices first, so only the columns that survive are converted to double.
X = double(D(:, idx));
if size(X, 2) < 10 * nch
    warning('prep:rankSamples', ...
        '%d usable samples for %d channels; the rank estimate is unreliable.', ...
        size(X, 2), nch);
end

s = svd(X', 'econ');

% Two scale-invariant estimates: MATLAB's own rank() tolerance, and a
% relative singular-value cut. Take the smaller. Erring low is the safe
% direction, since over-estimating rank produces ghost components.
rMat = sum(s > max(size(X)) * eps(s(1)));      % equivalent to rank(X')
rRel = sum(s > s(1) * 1e-6);
r    = min(rMat, rRel);

% EEGLAB's own criterion (getrank, local to pop_runica) counts covariance
% eigenvalues above an absolute 1e-7, which assumes microvolts: the same
% data in volts collapses it to zero. Used here only as a units check.
% Disagreement means the scaling is not what EEGLAB expects, and
% pop_runica's internal checks will misbehave for the same reason.
rAbs = sum(eig(cov(X', 1)) > 1e-7);
if rAbs ~= r
    warning('prep:rankUnits', ...
        ['Rank %d, but EEGLAB''s absolute 1e-7 criterion gives %d. This ' ...
         'usually means the data is not in microvolts, which will also ' ...
         'affect pop_runica and ICLabel. Using %d.'], r, rAbs, r);
end

r = max(1, min(r, nch));
end
