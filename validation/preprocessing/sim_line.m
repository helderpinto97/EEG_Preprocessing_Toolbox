function art = sim_line(lf, sim, seed)
% SIM_LINE  Power-line noise at sim.lineFreq and its harmonics below Nyquist.
%
%   art = sim_line(lf, sim, seed)
%
% Identical noise on every channel would be removed by the average
% reference alone, and the test would say nothing about line-noise removal.
% In real recordings the pickup differs per electrode with its impedance,
% so each channel gets its own gain (log-normal, about 0.6-1.6) and a small
% phase shift, and the amplitude drifts slowly over time.
%
% ART has the same fields as sim_eog: data, active, peak.

rng(seed);
pnts = round(sim.secs * sim.srate);
n    = numel(lf.chanlocs);
t    = (0:pnts-1) / sim.srate;

gain  = exp(0.3 * randn(n, 1));
phase = 0.2 * randn(n, 1);
drift = 1 + 0.2 * sin(2*pi*0.05*t + 2*pi*rand);

X = zeros(n, pnts);
for h = 1:3                                     % 50, 100, 150 Hz ...
    f = h * sim.lineFreq;
    if f >= sim.srate / 2, break, end
    X = X + (0.5^(h-1)) * sin(2*pi*f*t + phase);
end

art.data   = gain .* drift .* X;
art.active = true(1, pnts);
[~, art.peak] = max(gain);
end
