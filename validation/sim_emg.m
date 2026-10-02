function art = sim_emg(lf, sim, site, seed)
% SIM_EMG  Muscle artifact projected from the muscle sources of the lead field.
%
%   art = sim_emg(lf, sim, site, seed)
%
% SITE
%   'temporal'  temporalis and masseter, both sides (jaw clenching)
%   'frontal'   frontalis (raised eyebrows, frowning)
%   'neck'      splenius capitis, both sides, and trapezius (neck tension)
%
% Muscle activity comes in bursts of 1-4 s, sim.emgBurstRate per minute.
% sim.emgSources sources are drawn from each muscle, and every source gets
% its own broadband noise (20 Hz up to Nyquist) under a shared burst
% envelope: the muscle contracts as a whole, but its motor units fire
% independently. The artifact is therefore spatially spread, not one
% fixed topography, as in real EMG.
%
% ART has the same fields as sim_eog: data, active, peak.

rng(seed);
pnts = round(sim.secs * sim.srate);

switch site
    case 'temporal'
        muscles = {'Muscle_Temporalis_Temporoparietalis_left', 'Muscle_Temporalis_Temporoparietalis_right', ...
                   'Muscle_Masseter_left', 'Muscle_Masseter_right'};
    case 'frontal'
        muscles = {'Muscle_Occipitiofrontalis_FrontalBelly'};
    case 'neck'
        muscles = {'Muscle_SpleniusCapitis_left', 'Muscle_SpleniusCapitis_right', 'Muscle_Trapezius'};
    otherwise
        error('sim_emg:site', 'Unknown EMG site "%s".', site);
end

src = [];
for m = muscles
    cand = find(strcmp(lf.atlas, m{1}))';
    assert(numel(cand) >= sim.emgSources, 'sim_emg:noSources', ...
        'Muscle "%s" has %d sources in the lead field; %d wanted.', ...
        m{1}, numel(cand), sim.emgSources);
    src = [src, cand(randperm(numel(cand), sim.emgSources))]; %#ok<AGROW>
end

env = bursts(pnts, sim.srate, sim.emgBurstRate);
X   = zeros(numel(lf.chanlocs), pnts);
for s = src
    x = env .* sim_bandnoise(pnts, sim.srate, [20 Inf]);
    X = X + lf_project_signal(lf, x, s, lf.orientation(s,:));
end

art.data   = X;
art.active = env > 0.1;
[~, art.peak] = max(sqrt(mean(X.^2, 2)));
end

% -------------------------------------------------------------------------
function env = bursts(pnts, srate, perMin)
% 0-1 envelope: bursts of 1-4 s with 50 ms raised-cosine edges.
env  = zeros(1, pnts);
edge = round(0.05 * srate);
ramp = 0.5 - 0.5*cos(pi * (1:edge) / edge);
t    = round(srate * (1 + 2*rand));
while t < pnts
    len = round(srate * (1 + 3*rand));
    w   = [ramp, ones(1, max(0, len - 2*edge)), fliplr(ramp)];
    i   = t : min(pnts, t + numel(w) - 1);
    env(i) = max(env(i), w(1:numel(i)));
    t = t + numel(w) + round(srate * max(1, -60/perMin * log(rand)));
end
end
