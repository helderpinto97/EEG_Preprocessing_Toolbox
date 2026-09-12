function [f, P] = prep_psd(X, srate)
% PREP_PSD  Welch power spectrum, in dB, one column per channel.
%
%   [f, P] = prep_psd(X, srate)   X is channels-by-samples,
%                                 or channels-by-samples-by-trials
%
% At most MAXSECS of the recording is read. A long file then costs the same
% as a short one, and only the part that is read is converted to double.

maxSecs = 120;

if ndims(X) == 3
    % Epoched data. Average the per-epoch spectra rather than concatenating
    % the epochs first: a Welch window is several seconds long and an epoch
    % is typically about one, so a window laid across the joins turns the
    % step at each boundary into broadband power that is not in the data.
    [~, pnts, ntr] = size(X);
    sel = unique(round(linspace(1, ntr, ...
                max(1, min(ntr, floor(srate * maxSecs / pnts))))));
    acc = 0;
    for k = sel
        [f, pxx] = welch_lin(double(X(:, :, k)), srate);
        acc = acc + pxx;
    end
    P = 10*log10(acc / numel(sel) + eps);
    return
end

n = min(size(X, 2), round(srate * maxSecs));
[f, pxx] = welch_lin(double(X(:, 1:n)), srate);
P = 10*log10(pxx + eps);
end

% Auxiliary functions
function [f, pxx] = welch_lin(X, srate)
% Linear power, so the epoched path can average across trials before the dB
% conversion. Averaging dB gives the geometric mean, not the mean spectrum.
win = min(size(X, 2), round(srate * 4));
[pxx, f] = pwelch(X', hamming(win), [], [], srate);
end
