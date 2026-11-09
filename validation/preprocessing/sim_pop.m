function art = sim_pop(lf, sim, seed)
% SIM_POP  Electrode pops: sudden jumps on single electrodes that relax back.
%
%   art = sim_pop(lf, sim, seed)
%
% A pop is a sudden change of the electrode potential (a loose contact
% touching and releasing), seen as a near-vertical step that decays over a
% few hundred milliseconds. Each pop has a rise of 10 ms, an exponential
% decay with a time constant of 0.3 s, a random sign and an amplitude of
% 0.7-1.3. sim.popRate pops per minute fall on sim.popChannels electrodes
% drawn at random.
%
% ART has the same fields as sim_eog (data, active, peak), plus chans:
% the affected electrodes.

rng(seed);
pnts = round(sim.secs * sim.srate);
n    = numel(lf.chanlocs);
ch   = randperm(n, sim.popChannels);

t    = (0:round(1.5 * sim.srate) - 1) / sim.srate;
rise = min(t / 0.01, 1);
w    = rise .* exp(-max(t - 0.01, 0) / 0.3);        % one pop, peak 1

X      = zeros(n, pnts);
active = false(1, pnts);
tp     = sim.srate * (1 + rand);
while tp + numel(w) <= pnts
    i = round(tp) + (0:numel(w) - 1);
    c = ch(randi(numel(ch)));
    X(c, i) = X(c, i) + sign(randn) * (0.7 + 0.6 * rand) * w;
    active(i(1:round(0.9 * sim.srate))) = true;     % about three time constants
    tp = tp + sim.srate * max(1, -60 / sim.popRate * log(rand));
end

art.data   = X;
art.chans  = ch;                                  % the electrodes affected
art.active = active;
[~, k]     = max(std(X(ch, :), 0, 2));
art.peak   = ch(k);
end
