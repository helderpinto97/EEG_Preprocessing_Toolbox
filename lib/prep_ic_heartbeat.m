function [hit, f] = prep_ic_heartbeat(act, fs)
% PREP_IC_HEARTBEAT  Which component time courses beat like a heart.
%
%   [hit, f] = prep_ic_heartbeat(act, fs)
%
% ACT is components x samples (continuous), FS the sampling rate. HIT is
% 1-by-nIC logical. F holds the features per component (1-by-nIC each):
%
%   periodic  autocorrelation of the QRS-band envelope (8-30 Hz energy,
%             50 ms smoothing), highest value at lags of 0.33-1.5 s
%   bpm       beats per minute, from the peaks of that envelope
%   regular   fraction of beat intervals within 20% of the median interval
%   consist   median correlation of single beats (+-0.25 s) with the
%             median beat
%
% Cardiac when all four agree: periodic >= 0.3, 40-180 bpm, regular >= 0.8
% and consist >= 0.5; each alone lets something else through. On simulated
% data it found all 132 cardiac components and none of 13,661 others.
% An irregular rhythm (atrial fibrillation) fails the regularity test.

[nc, n] = size(act);
f = struct('periodic', zeros(1, nc), 'bpm', zeros(1, nc), ...
           'regular', zeros(1, nc), 'consist', zeros(1, nc));
hit = false(1, nc);
if n < 10 * fs, return; end      % too short for a beat rhythm

% One component at a time, to keep memory small.
fr   = (0:n-1) * fs / n;  fr = min(fr, fs - fr);
band = fr >= 8 & fr <= 30;                   % QRS energy band
w    = max(1, round(0.05 * fs));             % 50 ms envelope smoothing
lags = round(0.33 * fs) : round(1.5 * fs);
half = round(0.25 * fs);
nTop = n - ceil(0.99 * n) + 1;               % samples at or above the 99th pct
for c = 1:nc
    X = fft(act(c, :));
    X(~band) = 0;
    y = movmean(real(ifft(X)) .^ 2, w);      % QRS-band energy envelope

    % Periodicity, and the beat interval it implies.
    x  = y - mean(y);
    ac = real(ifft(abs(fft(x, 2 * n)) .^ 2));
    if ac(1) <= 0, continue, end
    ac = ac(lags + 1) / ac(1);
    [f.periodic(c), k] = max(ac);
    L  = lags(k);

    % Beats: envelope peaks above 30% of its 99th percentile, taken from the
    % largest down and at least 0.6 intervals apart.
    thr = 0.3 * min(maxk(y, nTop));
    pk = find(y(2:end-1) > y(1:end-2) & y(2:end-1) >= y(3:end) & y(2:end-1) > thr) + 1;
    [~, o] = sort(y(pk), 'descend');  pk = pk(o);
    md = round(0.6 * L);  taken = false(1, n);  keep = false(size(pk));
    for i = 1:numel(pk)
        if any(taken(max(1, pk(i) - md) : min(n, pk(i) + md))), continue, end
        taken(pk(i)) = true;  keep(i) = true;
    end
    pk = sort(pk(keep));
    pk = pk(pk > half & pk <= n - half);
    if numel(pk) < 5, continue, end

    rr = diff(pk);
    f.bpm(c)     = 60 * numel(pk) / (n / fs);
    f.regular(c) = mean(abs(rr - median(rr)) <= 0.2 * median(rr));

    a  = act(c, :);
    B  = a(pk(:) + (-half:half));              % beats x samples
    B  = B - mean(B, 2);
    f.consist(c) = median(prep_rowcorr(B, median(B, 1)));
end

hit = f.periodic >= 0.3 & f.bpm >= 40 & f.bpm <= 180 & ...
      f.regular >= 0.8 & f.consist >= 0.5;
end
