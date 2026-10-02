function R = run_validation(overrides)
% RUN_VALIDATION  Validate the preprocessing pipeline on simulated EEG.
%
%   R = run_validation()                   defaults from sim_config
%   R = run_validation(struct('secs', 60)) with overrides
%
% Per seed: simulate clean EEG (SEREEGA), add each artifact in sim.artifacts
% at every severity, run all datasets through run_preprocessing with the
% production settings, and compare each output with the ground truth.
%
% Output in validation/results/<timestamp>[_runName]/:
%   sim/             the simulated inputs, s<seed>_<condition>.set
%   ground_truth/    the clean EEG, s<seed>.set
%   derivatives/     the pipeline output and QC log
%   metrics.csv      one row per seed and dataset (R, returned too)
%   simulation.mat   sim parameters and the chosen sources per seed
%
% Needs EEGLAB with the pipeline plugins, SEREEGA and the HArtMuT lead field.

if nargin < 1, overrides = struct(); end
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here, root, fullfile(root, 'lib'));

sim = sim_config(overrides);

%% EEGLAB
if ~exist('eeglab', 'file')
    addpath(fullfile(root, 'lib', 'toolboxes', 'eeglab'));
end
evalc('eeglab nogui');

%% Output folders
stamp    = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
if ~isempty(sim.runName), stamp = [stamp '_' sim.runName]; end
outDir   = fullfile(sim.outRoot, stamp);
simDir   = fullfile(outDir, 'sim');
truthDir = fullfile(outDir, 'ground_truth');
derivDir = fullfile(outDir, 'derivatives');
mkdir(simDir); mkdir(truthDir);

%% Simulation
% All seeds go into one input folder, so the pipeline starts once.
lf   = sim_leadfield(sim);
cond = struct('file', {}, 'seed', {}, 'name', {}, 'artifact', {}, 'severity', {}, ...
              'snr_target_db', {}, 'alpha', {}, 'art', {});
info = cell(1, numel(sim.seeds));
for si = 1:numel(sim.seeds)
    seed = sim.seeds(si);
    [clean, info{si}] = sim_clean_eeg(lf, sim, seed);
    pop_saveset(clean, 'filename', sprintf('s%02d.set', seed), 'filepath', truthDir);

    cond(end+1) = make_cond(seed, 'clean', "none", "none", Inf, 0, []); %#ok<AGROW>
    save_input(clean, clean.data, cond(end).file, simDir);
    for ti = 1:numel(sim.artifacts)
        name  = sim.artifacts{ti};
        parts = split(string(name), '+')';
        % One time course per part and seed, reused at every severity and
        % seeded by name, so runs with different artifact lists are paired.
        arts = {};
        for p = find(parts ~= "badchan")
            arts{end+1} = sim_artifact(lf, sim, char(parts(p)), artifact_seed(seed, parts(p))); %#ok<AGROW>
        end
        for k = 1:numel(sim.snrDb)
            [X, a, meta] = contaminate(clean, arts, any(parts == "badchan"), k, ...
                                       sim.snrDb(k), artifact_seed(seed, "badchan"));
            cond(end+1) = make_cond(seed, sprintf('%s_%s', name, sim.severity{k}), ...
                string(name), string(sim.severity{k}), sim.snrDb(k), a, meta); %#ok<AGROW>
            save_input(clean, X, cond(end).file, simDir);
        end
    end
end
save(fullfile(outDir, 'simulation.mat'), 'sim', 'info');

%% Pipeline
pipe = sim.pipeline;
pipe.inDir  = simDir;
pipe.outDir = derivDir;
T   = run_preprocessing(pipe);
cfg = prep_config(pipe);

%% Evaluation
rows  = cell(numel(cond), 1);
clean = [];
for i = 1:numel(cond)
    c = cond(i);
    if isempty(clean) || clean.seed ~= c.seed      % one ground truth per seed
        clean = pop_loadset('filename', sprintf('s%02d.set', c.seed), 'filepath', truthDir);
        clean.seed = c.seed;
    end
    r = struct('seed', c.seed, 'dataset', string(c.name), 'artifact', c.artifact, ...
               'severity', c.severity, 'snr_target_db', c.snr_target_db, ...
               'alpha', c.alpha);
    q = T(T.subject == c.file, :);
    if height(q) ~= 1
        error('run_validation:qc', 'Expected one QC row for %s, found %d.', ...
              c.file, height(q));
    end
    r.status         = string(q.status);
    r.nchan_rejected = qcval(q, 'nchan_rejected', NaN);
    r.chans_rejected = string(qcval(q, 'chans_rejected', ""));
    r.n_ic_flagged   = qcval(q, 'n_ic_flagged', NaN);
    r.n_ic_iclabel   = qcval(q, 'n_ic_iclabel', NaN);     % by ICLabel alone
    r.n_ic_ecg       = qcval(q, 'n_ic_ecg', NaN);         % by the rules in prep_icrules
    r.n_ic_heartbeat = qcval(q, 'n_ic_heartbeat', NaN);
    r.n_ic_singlechan = qcval(q, 'n_ic_singlechan', NaN);
    r.error          = string(qcval(q, 'error', ""));

    % Bad channels detected, and good channels rejected as well.
    injected = strings(0, 1);
    if isstruct(c.art) && isfield(c.art, 'badLabels'), injected = string(c.art.badLabels(:)); end
    rejected = split(r.chans_rejected, '|');
    rejected = rejected(strlength(rejected) > 0 & ~ismissing(rejected));
    r.bad_injected  = numel(injected);
    r.bad_detected  = sum(ismember(injected, rejected));
    % Drift and pop electrodes still record EEG: counted separately.
    local = strings(0, 1);
    if isstruct(c.art) && isfield(c.art, 'localLabels'), local = string(c.art.localLabels(:)); end
    local = setdiff(local, injected);
    r.local_affected = numel(local);
    r.local_rejected = sum(ismember(local, rejected));
    r.good_rejected  = sum(~ismember(rejected, [injected; local]));

    if r.status == "ok"
        cont = pop_loadset('filename', [c.file '.set'], 'filepath', simDir);
        m = sim_eval(fullfile(derivDir, [c.file '_clean.set']), clean, cont, ...
                     c.art, cfg, sim.bands);
        for n = fieldnames(m)', r.(n{1}) = m.(n{1}); end
    end
    rows{i} = r;
end
R = rows_to_table(rows);
writetable(R, fullfile(outDir, 'metrics.csv'));

fprintf('\nValidation done. Results in %s\n', outDir);
end

% -------------------------------------------------------------------------
function [X, alpha, meta] = contaminate(clean, arts, withBad, nBad, snrDb, badSeed)
% Clean EEG plus each artifact scaled to SNRDB, then NBAD channels replaced
% by bad-channel signals when WITHBAD. ALPHA is the gain of a single
% artifact (NaN for several); META holds the active samples, the peak
% channel and the labels of the replaced and locally affected channels.
X      = double(clean.data);
added  = zeros(size(X));
active = false(1, size(X, 2));
alpha  = NaN;
local  = [];                             % electrodes with drift or pops
for i = 1:numel(arts)
    [~, a] = sim_inject(clean, arts{i}.data, snrDb);
    added  = added + a * arts{i}.data;
    active = active | arts{i}.active;
    if isfield(arts{i}, 'chans'), local = union(local, arts{i}.chans); end
    if isscalar(arts), alpha = a; end
end
X = X + added;
meta.localLabels = {clean.chanlocs(local).labels};

meta.badLabels = {};
bad = [];
if withBad
    E = clean; E.data = X;
    bad = sim_badchan(E, nBad, badSeed);
    X(bad.chans, :) = bad.data;
    meta.badLabels = {clean.chanlocs(bad.chans).labels};
    meta.badTypes  = bad.types;
end

rmsAdded = sqrt(mean(added.^2, 2));
if ~isempty(bad), rmsAdded(bad.chans) = -Inf; end
if isempty(arts)                         % bad channels only
    meta.active = true(1, size(X, 2));
    meta.peak   = bad.chans(1);
else
    meta.active = active;
    [~, meta.peak] = max(rmsAdded);
end
end

function s = artifact_seed(seed, part)
% Random seed of one artifact type, fixed per name (a new type needs a code).
names = ["eog_blink", "eog_vertical", "eog_horizontal", "emg_temporal", "emg_frontal", ...
         "emg_neck", "ecg", "line", "drift", "pop", "badchan"];
code = find(names == string(part), 1);
if isempty(code)
    error('run_validation:artifactSeed', 'No seed code for artifact "%s".', part);
end
s = 1000*seed + 10*code;
end

function c = make_cond(seed, name, artifact, severity, snr, alpha, art)
c = struct('file', sprintf('s%02d_%s', seed, name), 'seed', seed, 'name', name, ...
           'artifact', artifact, 'severity', severity, 'snr_target_db', snr, ...
           'alpha', alpha, 'art', art);
end

function save_input(clean, X, name, simDir)
E = clean;
E.data    = X;
E.setname = name;
pop_saveset(E, 'filename', [name '.set'], 'filepath', simDir);
end

function v = qcval(q, name, default)
% A QC column, or DEFAULT when no dataset got far enough to write it.
if ismember(name, q.Properties.VariableNames)
    v = q.(name);
else
    v = default;
end
end

function T = rows_to_table(rows)
% One table from rows with different fields (failed datasets have no metrics).
names = {};
for i = 1:numel(rows)
    names = [names, setdiff(fieldnames(rows{i})', names, 'stable')]; %#ok<AGROW>
end
for i = 1:numel(rows)
    for n = setdiff(names, fieldnames(rows{i})')
        rows{i}.(n{1}) = NaN;
    end
    rows{i} = orderfields(rows{i}, names);
end
T = struct2table([rows{:}], 'AsArray', true);
end
