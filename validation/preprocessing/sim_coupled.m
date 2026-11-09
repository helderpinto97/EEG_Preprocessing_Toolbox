function [X, info, parts] = sim_coupled(lf, sim, seed, bg, hb)
% SIM_COUPLED  Genuine interactions added to the clean EEG.
%
%   [X, info, parts] = sim_coupled(lf, sim, seed, bg, hb)
%
% BG is the clean EEG of sim_clean_eeg (the background), HB the heartbeats
% of sim_heart. X (channels x samples, uV) is added to BG and holds four
% structures, each from cortical sources at least sim.coupledSpacing mm
% apart:
%   red   3 sources, AR(2) oscillators with a common driver, x1 -> x2 and
%         x1 -> x3 (src_sources_var, sim.tripVar): redundancy
%   syn   3 sources with a common target, x1 -> x3 and x2 -> x3: synergy
%   bh    1 source of theta band noise (4-8 Hz) whose log amplitude in heart
%         period n is sim.bhDepth * hb.a(n), so it follows RR(n-1) with the
%         coupling of sim_heart (heart -> brain)
%   hep   1 source with a positive wave 0.3 s after each R peak (SD 50 ms),
%         sim.hepUv uV (positive) at its peak channel under the average
%         reference: a heartbeat-evoked potential
% Each triplet and the bh source are scaled to the mean channel power of BG
% times 10^(sim.coupledDb/10) and 10^(sim.bhDb/10).
%
% PARTS holds each structure alone (red, syn, bh, hep; X is their sum).
% INFO: source indices (red, syn, bh, hep), the exact source OIR of each
% triplet (src_sources_var), the peak channel and topography of bh and hep,
% and HB.

pnts = size(bg.data, 2);
fs   = sim.srate;
rng(seed);
idx  = lf_get_source_spaced(lf, 8, sim.coupledSpacing, 'region', {'Brain.*'});
idx  = idx(randperm(numel(idx)));
or   = lf.orientation(idx, :);
topo = zeros(numel(lf.chanlocs), 8);
for k = 1:8
    topo(:, k) = lf_project_signal(lf, 1, idx(k), or(k, :));
end
pw = mean(var(double(bg.data), 0, 2));
scale = @(Y, db) Y * sqrt(pw * 10^(db/10) / mean(var(Y, 0, 2)));

% Triplets, from the source validation generator (it sets the rng itself).
src   = struct('srate', fs, 'var', sim.tripVar);
trips = struct('near', [1 2 3]);
[Sr, tr] = src_sources_var('red_near', 3, pnts, trips, src, seed + 1, 1);
[Ss, ts] = src_sources_var('syn_near', 3, pnts, trips, src, seed + 2, 1);
parts.red = scale(topo(:, 1:3) * Sr, sim.coupledDb);
parts.syn = scale(topo(:, 4:6) * Ss, sim.coupledDb);

% Brain-heart source: theta band noise, amplitude set per heart period.
rng(seed + 3);
f = (0:pnts-1) * fs / pnts;  f = min(f, fs - f);
c = fft(randn(1, pnts));  c(f < 4 | f > 8) = 0;
c = real(ifft(c));  c = c / std(c);
r = round(hb.t * fs) + 1;                       % R peak samples
g = zeros(1, pnts);
g(1:r(1)-1) = hb.a(1);
for n = 1:numel(hb.a)
    g(r(n):r(n+1)-1) = hb.a(n);
end
g(r(end):end) = hb.a(end);
env = movmean(exp(sim.bhDepth * g), round(0.1 * fs));   % no steps at the R peaks
parts.bh = scale(topo(:, 7) * (c .* env), sim.bhDb);

% Heartbeat-evoked potential.
s  = zeros(1, pnts);
tw = -0.2 : 1/fs : 0.2;
w  = exp(-tw.^2 / (2 * 0.05^2));
for n = 1:numel(r)
    i = r(n) + round(0.3 * fs) + round(tw * fs);
    if i(end) > pnts, break, end
    s(i) = s(i) + w;
end
% Peak channels and the HEP amplitude refer to the average reference of the
% pipeline output; a broad topography loses most of its peak there.
ta = topo - mean(topo, 1);
[~, bhPeak]  = max(abs(ta(:, 7)));
[~, hepPeak] = max(abs(ta(:, 8)));
parts.hep = (sim.hepUv / ta(hepPeak, 8)) * topo(:, 8) * s;   % positive at its peak
X = parts.red + parts.syn + parts.bh + parts.hep;
info = struct('red', idx(1:3), 'syn', idx(4:6), 'bh', idx(7), 'hep', idx(8), ...
              'oirRed', tr.O, 'oirSyn', ts.O, 'bhPeak', bhPeak, 'hepPeak', hepPeak, ...
              'bhTopo', topo(:, 7), 'hepTopo', topo(:, 8), 'hb', hb);
end
