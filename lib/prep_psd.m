function [f, P] = prep_psd(X, srate)
% PREP_PSD  Welch power spectrum (linear power), one column per channel.
%
%   [f, P] = prep_psd(X, srate)   X is channels x samples [x trials]
%
% Reads at most 120 s, so a long file costs the same as a short one.
% Epoched data: the spectra of the epochs are averaged, rather than a
% Welch window laid across the joins between epochs.

maxSecs = 120;
if ndims(X) == 3
    [~, pnts, ntr] = size(X);
    sel = unique(round(linspace(1, ntr, max(1, min(ntr, floor(srate * maxSecs / pnts))))));
    P = 0;
    for k = sel
        [f, pxx] = welch(double(X(:, :, k)), srate);
        P = P + pxx;
    end
    P = P / numel(sel);
else
    [f, P] = welch(double(X(:, 1:min(size(X, 2), round(srate * maxSecs)))), srate);
end
end

function [f, pxx] = welch(X, srate)
% 4 s Hamming windows.
[pxx, f] = pwelch(X', hamming(min(size(X, 2), round(srate * 4))), [], [], srate);
end
