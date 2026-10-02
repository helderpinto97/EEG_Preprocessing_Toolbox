function act = prep_ic_act(EEG, secs, fmax)
% PREP_IC_ACT  Component time courses and spectra for the component sheet.
%
%   act = prep_ic_act(EEG, secs, fmax)
%
% SECS of every component activation, starting a quarter of the way in, and
% its Welch power spectrum up to FMAX Hz (from at most 120 s, as prep_psd).
% Heartbeats, blinks and pops show in the time course; muscle shows as power
% rising above 20 Hz, brain often as an alpha peak.

W  = double(EEG.icaweights) * double(EEG.icasphere);
ci = EEG.icachansind;
if isempty(ci), ci = 1:EEG.nbchan; end

D  = reshape(EEG.data(ci, :, :), numel(ci), []);   % epochs joined
n  = size(D, 2);
w  = min(round(secs * EEG.srate), n);
i0 = max(1, min(round(0.25*n), n - w + 1));
act.srate = EEG.srate;
act.t0    = (i0 - 1) / EEG.srate;
act.trace = W * double(D(:, i0:i0+w-1));

if EEG.trials > 1
    ntr = EEG.trials;
    sel = unique(round(linspace(1, ntr, max(1, min(ntr, floor(EEG.srate * 120 / EEG.pnts))))));
    X   = double(EEG.data(ci, :, sel));
    X   = reshape(W * reshape(X, numel(ci), []), [], EEG.pnts, numel(sel));
else
    X   = W * double(D(:, 1:min(n, round(EEG.srate * 120))));
end
[f, P]  = prep_psd(X, EEG.srate);
keep    = f >= 1 & f <= fmax;
act.f   = f(keep);
act.psd = P(keep, :);
end
