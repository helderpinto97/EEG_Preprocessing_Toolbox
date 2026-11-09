function art = sim_eog(lf, sim, type, seed)
% SIM_EOG  Ocular artifact projected from the eye sources of the lead field.
%
%   art = sim_eog(lf, sim, type, seed)
%
% TYPE
%   'blink'       eye blinks, sim.blinkRate per minute, about 300 ms each
%   'vertical'    up/down eye movements: steps held between saccades
%   'horizontal'  left/right eye movements, same time course
%
% One source per eye is taken from the HArtMuT eye model (the one nearest
% the centre of the sources of that eye). Blinks and vertical movements rotate
% the corneo-retinal dipole in the vertical plane, horizontal movements in
% the horizontal plane; both eyes move together.
%
% ART is a struct:
%   data    channels x samples, unscaled (sim_inject sets the SNR)
%   topo    channels x 1 scalp projection
%   active  1 x samples, true where the artifact is present
%   peak    index of the channel where the artifact is largest

rng(seed);
pnts = round(sim.secs * sim.srate);

%% Scalp topography
eye = lf_get_source_all(lf, 'region', {'Eye.*'});
eye = eye(~contains(lf.atlas(eye), 'leftright', 'IgnoreCase', true));  % one eye each
assert(~isempty(eye), 'sim_eog:noEyeSources', ...
    'The lead field has no Eye sources; use a HArtMuT lead field.');
x    = lf.pos(eye, 1);                              % MNI x: negative = left
src  = [nearest_centre(lf, eye(x < 0)), nearest_centre(lf, eye(x > 0))];

switch type
    case {'blink', 'vertical'}, ori = [0 0 1];      % rotation up/down
    case 'horizontal',          ori = [1 0 0];      % rotation left/right
    otherwise
        error('sim_eog:type', 'Unknown EOG type "%s".', type);
end
topo = lf_get_projection(lf, src, 'orientation', [ori; ori])';
topo = orient_and_check(topo, {lf.chanlocs.labels}, type);

%% Time course
switch type
    case 'blink',      s = blinks(pnts, sim.srate, sim.blinkRate);
    otherwise,         s = saccades(pnts, sim.srate, sim.saccadeRate);
end

art.data   = topo * s;
[~, art.peak] = max(abs(topo));
art.active = abs(s) > 0.1 * max(abs(s));
art.topo   = topo;
end

% -------------------------------------------------------------------------
function idx = nearest_centre(lf, cand)
assert(~isempty(cand), 'sim_eog:oneEye', 'Eye sources found for one eye only.');
c = mean(lf.pos(cand, :), 1);
[~, k] = min(vecnorm(lf.pos(cand, :) - c, 2, 2));
idx = cand(k);
end

function topo = orient_and_check(topo, labels, type)
% Fix the sign so an upward or rightward movement is positive where it is
% seen in real EOG, and check the topography looks ocular at all. The check
% guards against a coordinate convention in the lead field other than the
% one assumed here (x = right, z = up), which would silently turn the
% "EOG" into some other field.
ch = @(l) find(strcmpi(labels, l), 1);
fp = mean(topo([ch('Fp1') ch('Fp2')]));
oz = mean(abs(topo([ch('O1') ch('Oz') ch('O2')])));
switch type
    case {'blink', 'vertical'}
        topo = topo * sign(fp);                     % positive at Fp
        assert(abs(fp) > 3 * oz, 'sim_eog:notOcular', ...
            'Vertical EOG is not frontal (|Fp| %.3g vs |O| %.3g).', abs(fp), oz);
    case 'horizontal'
        f7 = topo(ch('F7')); f8 = topo(ch('F8'));
        topo = topo * sign(f8);                     % positive at F8
        assert(sign(f7) ~= sign(f8), 'sim_eog:notOcular', ...
            'Horizontal EOG does not have opposite polarity at F7 and F8.');
end
end

function s = blinks(pnts, srate, perMin)
% Unit-peak blinks: 100 ms rise, 200 ms fall, amplitude 0.8-1.2.
up   = 0.5 - 0.5*cos(pi * (0:round(0.1*srate)-1) / round(0.1*srate));
down = 0.5 + 0.5*cos(pi * (1:round(0.2*srate))   / round(0.2*srate));
w    = [up down];
s    = zeros(1, pnts);
t    = srate * (1 + rand);                          % first blink after 1-2 s
while t + numel(w) <= pnts
    i = round(t);
    s(i:i+numel(w)-1) = s(i:i+numel(w)-1) + (0.8 + 0.4*rand) * w;
    t = t + srate * max(1, exprnd_(60 / perMin));   % at least 1 s apart
end
end

function s = saccades(pnts, srate, perMin)
% Gaze position: fixations at random levels in [-1 1], 40 ms transitions.
s = zeros(1, pnts);
t = 1; level = 0;
while t <= pnts
    dur = round(srate * max(0.3, exprnd_(60 / perMin)));
    s(t:min(pnts, t+dur-1)) = level;
    t = t + dur;
    level = 2*rand - 1;
end
n = round(0.04*srate);
k = 0.5 - 0.5*cos(2*pi * (1:n) / (n+1));           % Hann window
s = conv(s, k / sum(k), 'same');
s = s - mean(s);
end

function x = exprnd_(mu)
% Exponential draw without the Statistics Toolbox.
x = -mu * log(rand);
end
