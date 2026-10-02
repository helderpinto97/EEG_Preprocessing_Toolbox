function art = sim_ecg(lf, sim, seed)
% SIM_ECG  Cardiac artifact: a synthetic ECG with a far-field topography.
%
%   art = sim_ecg(lf, sim, seed)
%
% The head model has no heart, so the topography is the far field of a
% distant dipole: over the head it is close to a linear gradient along the
% cardiac axis, here pointing left and down. Channel positions are those of
% the lead field (EEGLAB axes: X front, Y left, Z up).
%
% The time course is a PQRST complex built from Gaussians, at
% sim.heartRate beats per minute with 5% beat-to-beat variability.
%
% ART has the same fields as sim_eog: data, active, peak.

rng(seed);
pnts = round(sim.secs * sim.srate);

pos  = [[lf.chanlocs.X]' [lf.chanlocs.Y]' [lf.chanlocs.Z]'];
pos  = pos ./ vecnorm(pos, 2, 2);
axisDir = [0.2 0.6 -0.8];                       % slightly front, left, down
topo = pos * (axisDir / norm(axisDir))';

% One beat: P, Q, R, S, T waves as [amplitude, latency s, width s].
waves = [ 0.15 -0.20 0.025;
         -0.10 -0.04 0.010;
          1.00  0     0.012;
         -0.25  0.04 0.012;
          0.30  0.30 0.050];
tb   = -0.35 : 1/sim.srate : 0.55;
beat = zeros(size(tb));
for w = waves'
    beat = beat + w(1) * exp(-(tb - w(2)).^2 / (2 * w(3)^2));
end

s  = zeros(1, pnts);
rr = 60 / sim.heartRate;
t  = 0.5 + rand * rr;                           % first R peak, s
while true
    i = round((t + tb) * sim.srate) + 1;
    if i(end) > pnts, break, end
    s(i) = s(i) + beat;
    t = t + rr * (1 + 0.05 * randn);
end

art.data   = topo * s;
art.active = abs(s) > 0.1;                      % around each QRS
[~, art.peak] = max(abs(topo));
end
