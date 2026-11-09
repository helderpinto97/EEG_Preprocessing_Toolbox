function [O, Olag, Oinst] = src_oir3(X, trip, p, Am, Su)
% SRC_OIR3  O-information rate of triplets from a VAR model (Faes et al. 2022).
%
%   [O, Olag, Oinst] = src_oir3(X, trip, p)        estimated from data
%   [O, Olag, Oinst] = src_oir3([], [], [], Am, Su) exact, from a known VAR
%
% X is parcels x samples, trip a k x 3 list of triplets, p the VAR order.
% For each triplet a VAR(p) is fitted by least squares (oir_idVAR) and the
% OIR is computed in the time domain through state-space submodels
% (oir_ar2iss, oir_deltaO of the OIR toolbox, github.com/danielemarinazzo/OIR).
% For three processes the OIR equals the gradient obtained by adding the
% third process to the other two, which splits into
%   Olag   lagged (Granger-causal) parts, both directions
%   Oinst  instantaneous part
% so O = Olag + Oinst. In nats; > 0 redundancy, < 0 synergy.
% Zero-lag mixing (volume conduction, leakage) acts first on Oinst.
% NaN for a triplet whose fitted VAR has a root on the unit circle.

if isempty(which('oir_deltaO'))
    addpath(fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'lib', 'toolboxes', 'OIR'));
end
nfft = 8;                                     % spectra unused: time domain via submodels
if nargin > 3
    [O, Olag, Oinst] = one(Am, Su);
    return
end
k = size(trip, 1);
O = zeros(k, 1); Olag = O; Oinst = O;
for i = 1:k
    [Am, Su] = oir_idVAR(X(trip(i, :), :), p);
    [O(i), Olag(i), Oinst(i)] = one(Am, Su);
end

    function [o, ol, oi] = one(Am, Su)
        % NaN for a fitted root at or near the unit circle (line noise, a
        % pure sinusoid: the entropy rate goes to -Inf) and when the
        % submodel Riccati equation has no stable solution
        o = NaN; ol = NaN; oi = NaN;
        [A, C, K, rho] = oir_ar2iss(Am);
        if rho > 0.999, return; end
        w = warning('off', 'all');
        try
            out = oir_deltaO(A, C, K, Su, [1 1 1], [1 2 3], 3, 1, nfft, 'y');
        catch
            warning(w);
            return
        end
        warning(w);
        o  = out.dO12;
        ol = out.dO1_2 + out.dO2_1;
        oi = out.dO1o2;
    end
end
