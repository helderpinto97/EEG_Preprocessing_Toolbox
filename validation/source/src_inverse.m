function K = src_inverse(method, L, C, reg, labels, pos)
% SRC_INVERSE  FieldTrip inverse operator for fixed-orientation sources.
%
%   K = src_inverse('eloreta' | 'lcmv' | 'champagne', L, C, reg, labels, pos)
%
% L is the average-referenced lead field (channels x sources), C the
% average-referenced data covariance, reg the regularisation as a fraction
% of the mean diagonal, labels the channel labels, pos the source
% positions (mm). C is not used by eLORETA. K is sources x
% channels, so the source time courses are K*Y.
%
% Runs ft_sourceanalysis with the lead field as precomputed one-column
% leadfields (fixed orientation, normal to the cortex), so no head model is
% needed. eLORETA: FieldTrip mkfilt_eloreta (Pascual-Marqui 2007), which
% does not use C. LCMV: ft_inverse_lcmv (Van Veen et al. 1997) with
% unit-noise-gain weights (Sekihara and Nagarajan 2008), so deep sources
% do not dominate the principal component of a parcel.
% Champagne: sparse Bayesian learning (Wipf et al. 2010), not in FieldTrip,
% see the local function below.

if strcmp(method, 'champagne')
    K = champagne(L, C, reg);
    return
end

if ~exist('ft_sourceanalysis', 'file')
    % The EEGLAB Fileio plugin carries a partial FieldTrip copy; two copies
    % on the path make FieldTrip warn. The plugin is only needed to import.
    p = strsplit(path, pathsep);
    old = p(contains(p, [filesep 'Fileio']));
    if ~isempty(old), rmpath(old{:}); end
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(fullfile(root, 'lib', 'toolboxes', 'fieldtrip'));
    ft_defaults;
end

[m, n] = size(L);
labels = labels(:);
sm = struct('pos', pos, 'inside', true(n, 1), 'unit', 'mm');
sm.leadfield = num2cell(L, 1);
sm.label = labels;

tl = struct('label', {labels}, 'time', 0, 'avg', zeros(m, 1), 'cov', C, ...
            'dimord', 'chan_time');

cfg = struct('method', method, 'sourcemodel', sm, 'channel', {labels});
cfg.feedback = 'no';
switch method
    case 'eloreta'
        cfg.eloreta = struct('lambda', reg, 'keepfilter', 'yes', 'keepmom', 'no');
    case 'lcmv'
        cfg.lcmv = struct('lambda', sprintf('%g%%', 100 * reg), 'keepfilter', 'yes', ...
                          'keepmom', 'no', 'weightnorm', 'unitnoisegain', ...
                          'projectnoise', 'no');
    otherwise
        error('src_inverse:method', 'Unknown method %s.', method);
end

% ft_sourceanalysis and mkfilt_eloreta print every iteration
evalc('src = ft_sourceanalysis(cfg, tl);');
K = cat(1, src.avg.filter{:});
assert(isequal(size(K), [n m]), 'src_inverse:size', 'Unexpected filter size.');
end

function K = champagne(L, C, reg)
% Model: y = L*x + e, x_i ~ N(0, g_i), e ~ N(0, lam*I). The source variances
% g are learned from C by the convex-bounding (MM) update of Wipf et al.
% 2010 (NeuroImage 49:641), which drives the variances of inactive sources
% to zero. The noise lam is fixed at reg times the mean sensor variance.
% With g fixed the estimate is linear: K = G*L'*inv(Sy), Sy = lam*I + L*G*L'.
% ponytail: fixed noise and 200 iterations; learn lam (Hashemi et al.
% 2021) if the results depend on reg.
m   = size(L, 1);
lam = reg * trace(C) / m;
g   = ones(size(L, 2), 1) * trace(C) / sum(L(:).^2);  % model power = data power
for it = 1:200
    LS = (lam * eye(m) + (L .* g') * L') \ L;          % columns inv(Sy)*l_i
    z  = sum(L .* LS, 1)';                              % l_i'*inv(Sy)*l_i
    x2 = sum(LS .* (C * LS), 1)';                       % mean posterior x_i^2 / g_i^2
    gNew = g .* sqrt(x2 ./ z);
    done = max(abs(gNew - g)) < 1e-6 * max(g);
    g = gNew;
    if done, break; end
end
LS = (lam * eye(m) + (L .* g') * L') \ L;
K  = g .* LS';
end
