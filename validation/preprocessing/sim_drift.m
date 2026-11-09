function art = sim_drift(lf, sim, seed)
% SIM_DRIFT  Slow baseline drift on a few electrodes.
%
%   art = sim_drift(lf, sim, seed)
%
% Electrode drift comes from changes at the skin-electrode junction (sweat,
% movement of the cap), so it is local to single electrodes, not a field
% projected from a source. sim.driftChannels electrodes, drawn at random,
% each get their own slow wander: random noise limited to 0.05-0.5 Hz.
%
% ART has the same fields as sim_eog (data, active, peak), plus chans:
% the affected electrodes.

rng(seed);
pnts = round(sim.secs * sim.srate);
n    = numel(lf.chanlocs);
ch   = randperm(n, sim.driftChannels);

X = zeros(n, pnts);
for c = ch
    X(c, :) = sim_bandnoise(pnts, sim.srate, [0.05 0.5]);
end

art.data   = X;
art.chans  = ch;                                  % the electrodes affected
art.active = true(1, pnts);
[~, k]     = max(std(X(ch, :), 0, 2));
art.peak   = ch(k);
end
