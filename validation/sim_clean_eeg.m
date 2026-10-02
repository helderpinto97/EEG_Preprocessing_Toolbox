function [EEG, info] = sim_clean_eeg(lf, sim, seed)
% SIM_CLEAN_EEG  Artifact-free continuous EEG from SEREEGA. The ground truth.
%
%   [EEG, info] = sim_clean_eeg(lf, sim, seed)
%
% LF is a SEREEGA lead field restricted to sim.labels (see sim_leadfield).
% Three kinds of cortical source, all projected through the lead field:
%   background  sim.nBackground sources spread over cortex, pink + brown
%               noise, giving the 1/f background
%   alpha       sim.nAlpha posterior sources, 8-12 Hz band, waxing and waning
%   theta       sim.nTheta frontal midline sources, 4-7 Hz band
% The sum is scaled so the median channel SD is sim.eegRms uV, and white
% sensor noise is added. Only cortical ('Brain') sources are used here; eye
% and muscle sources of the same head model are left to the artifact layer.
%
% The data carry channel labels but no coordinates, like a raw recording, so
% the pipeline locates them from its template exactly as it would in use.
%
% INFO records the chosen sources, for plotting and for the stroke stage,
% which will change these same sources.

rng(seed);
epochs = struct('n', 1, 'srate', sim.srate, 'length', sim.secs * 1000);

brain = lf_get_source_all(lf, 'region', {'Brain.*'});
pos   = lf.pos;

% Background: spread over the whole cortex.
bgIdx = lf_get_source_spaced(lf, sim.nBackground, sim.bgSpacing, 'region', {'Brain.*'});
pink  = struct('type', 'noise', 'color', 'pink-unif',  'amplitude', 1);
brown = struct('type', 'noise', 'color', 'brown-unif', 'amplitude', 0.5);

% Alpha: posterior cortex (MNI y below -70 mm).
alphaIdx = pick(brain(pos(brain,2) < -70), sim.nAlpha, 'posterior');
alpha = struct('type', 'ersp', 'frequency', [7 8 12 13], 'amplitude', 4, ...
                'modulation', 'ampmod', 'modFrequency', 0.1, ...
                'modMinRelAmplitude', 0.2);

% Theta: frontal midline (|x| < 15, y 10..50, z > 20 mm).
fm = brain(abs(pos(brain,1)) < 15 & pos(brain,2) > 10 & pos(brain,2) < 50 & pos(brain,3) > 20);
thetaIdx = pick(fm, sim.nTheta, 'frontal midline');
theta = struct('type', 'ersp', 'frequency', [3 4 7 8], 'amplitude', 2, ...
                'modulation', 'ampmod', 'modFrequency', 0.05, ...
                'modMinRelAmplitude', 0.3);

% Stroke: the same brain as the healthy recording of this seed, with a
% lesion. Its sources are drawn from a separate random stream, and its
% delta generators are projected last, so everything the healthy recording
% has stays sample for sample the same apart from the lesion changes.
st = stroke_params(sim);
lesion = []; deltaIdx = [];
if st.on
    d      = vecnorm(pos(brain,:) - sim.lesionCentre, 2, 2);
    lesion = brain(d < sim.lesionRadius);
    state  = rng;
    rng(seed + 7777);
    deltaIdx = pick(lesion, st.nDelta, 'lesion');
    rng(state);
    brown.amplitude = st.brown;              % diffuse slowing
end

% A single class goes in as a struct: SEREEGA gives one struct to every
% component, but n classes in a cell to n components one each.
bg = utl_create_component(bgIdx, pink, lf);
bg = utl_check_component(utl_add_signal_tocomponent(brown, bg), lf);
comp = bg;
if ~isempty(alphaIdx), comp = [comp, utl_create_component(alphaIdx, alpha, lf)]; end
if ~isempty(thetaIdx), comp = [comp, utl_create_component(thetaIdx, theta, lf)]; end

if st.on
    % Loss of normal activity: background sources inside the lesion and
    % alpha sources on the side of the lesion are attenuated. Scaling the
    % orientation scales the projection and leaves the signal untouched.
    side = sign(sim.lesionCentre(1));
    for c = 1:numel(comp)
        g = 1;
        if ismember(comp(c).source, lesion), g = st.lesionGain; end
        if ismember(comp(c).source, alphaIdx) && sign(pos(comp(c).source, 1)) == side
            g = st.alphaGain;
        end
        comp(c).orientation = g * comp(c).orientation;
    end
    % Polymorphic delta from inside the lesion, waxing and waning.
    delta = struct('type', 'ersp', 'frequency', [0.5 1 4 5], 'amplitude', st.deltaAmp, ...
                   'modulation', 'ampmod', 'modFrequency', 0.15, 'modMinRelAmplitude', 0.2);
    comp = [comp, utl_create_component(deltaIdx, delta, lf)];
end

X = project(comp, lf, epochs);

% Scale to a plausible amplitude, then add sensor noise.
X = X - mean(X, 2);
X = X * (sim.eegRms / median(std(X, 0, 2)));
X = X + sim.sensorNoise * randn(size(X));

EEG = sim_eegset(X, sim.srate, {lf.chanlocs.labels}, 'clean');

info = struct('background', bgIdx, 'alpha', alphaIdx, 'theta', thetaIdx, ...
              'stroke', string(sim.stroke), 'lesion', lesion, 'delta', deltaIdx);
end

% -------------------------------------------------------------------------
function st = stroke_params(sim)
% How strongly each stroke stage changes the healthy EEG. Illustrative
% values: acute stroke shows marked focal attenuation, strong polymorphic
% delta and diffuse slowing; in the chronic stage these partly recover.
switch lower(sim.stroke)
    case 'none'
        st = struct('on', false, 'lesionGain', 1, 'alphaGain', 1, 'nDelta', 0, 'deltaAmp', 0, 'brown', 0.5);
    case 'acute'
        st = struct('on', true, 'lesionGain', 0.3, 'alphaGain', 0.4, 'nDelta', 6, 'deltaAmp', 4, 'brown', 0.65);
    case 'chronic'
        st = struct('on', true, 'lesionGain', 0.6, 'alphaGain', 0.7, 'nDelta', 4, 'deltaAmp', 2.5, 'brown', 0.5);
    otherwise
        error('sim_clean_eeg:stroke', 'sim.stroke must be none, acute or chronic, not "%s".', sim.stroke);
end
end

% -------------------------------------------------------------------------
function X = project(comp, lf, epochs)
% Sum of every component projected to the scalp.
%
% The same arithmetic as SEREEGA's generate_scalpdata, done serially.
% generate_scalpdata runs a parfor, and random numbers drawn on pool workers
% do not follow the rng of the client, so the same seed would give different
% "ground truth" on different runs.
X = zeros(numel(lf.chanlocs), floor(epochs.length/1000 * epochs.srate));
for c = 1:numel(comp)
    s = generate_signal_fromcomponent(comp(c), epochs);
    for k = 1:numel(comp(c).source)
        X = X + lf_project_signal(lf, s, comp(c).source(k), comp(c).orientation(k,:));
    end
end
end

function idx = pick(candidates, n, what)
% N distinct sources drawn at random from CANDIDATES.
if numel(candidates) < n
    error('sim_clean_eeg:fewSources', ...
        'Only %d %s cortical sources in the lead field; %d wanted.', ...
        numel(candidates), what, n);
end
idx = candidates(randperm(numel(candidates), n));
end
