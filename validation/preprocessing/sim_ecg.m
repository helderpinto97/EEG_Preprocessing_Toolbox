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
% sim.heartRate beats per minute. The heart period series is an AR(4)
% process with a respiratory (HF) and a slower (LF) oscillation: poles of
% radius 0.9 at 0.3 cycles/beat and 0.8 at 0.1 cycles/beat, as in the
% benchmark models of cardiovascular variability, scaled to an SD of 5% of
% the mean heart period. When sim.beats holds R peak times (s, from
% sim_heart), those are used instead, so the artifact beats with the
% coupled EEG of sim_coupled.
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

rr = 60 / sim.heartRate;
nb = ceil(1.5 * sim.secs / rr) + 10;            % more beats than can fit
p  = [0.9 * exp([1 -1] * 1i*2*pi*0.3), 0.8 * exp([1 -1] * 1i*2*pi*0.1)];
v  = filter(1, real(poly(p)), randn(1, nb + 200));
v  = v(201:end);                                % drop the transient
v  = 0.05 * (v - mean(v)) / std(v);
tR = 0.5 + rand * rr;                           % first R peak, s
tR = tR + rr * [0 cumsum(1 + v)];
if isfield(sim, 'beats') && ~isempty(sim.beats)
    tR = sim.beats;                             % heart shared with the EEG (sim_heart)
end

s  = zeros(1, pnts);
for t = tR
    i = round((t + tb) * sim.srate) + 1;
    if i(end) > pnts, break, end
    s(i) = s(i) + beat;
end

art.data   = topo * s;
art.active = abs(s) > 0.1;                      % around each QRS
[~, art.peak] = max(abs(topo));
end
