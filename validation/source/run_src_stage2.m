function R = run_src_stage2(overrides)
% RUN_SRC_STAGE2  Stage 2 of the source reconstruction validation.
%
%   R = run_src_stage2()
%   R = run_src_stage2(struct('nBoot', 50))      quicker
%
% The regional signals of Stage 1 (known covariance, so known O-information)
% are added to realistic background EEG (sim_clean_eeg: 1/f background,
% alpha, theta, sensor noise), with and without artifacts (sim_artifact),
% and analysed with and without the preprocessing pipeline in lib/. The
% source reconstruction is the Stage 1 one: template head, eLORETA and LCMV
% through FieldTrip, first principal component per parcel. See
% tests/EEG Source Reconstruction Validation Plan.md, Stage 2.
%
% The true O-information refers to the regional signals only; the
% background is independent of them and acts as brain noise.
%
% Output in validation/results/source/<timestamp>_src_stage2/:
%   sim/           simulated inputs, <seed>_<density>_<condition>_<cln|art>.set
%   derivatives/   pipeline output and QC log
%   metrics.csv    one row per dataset, variant and analysis
%   distance.csv   null condition: O-information against parcel distance
%   summary.png    src_figure_s2

if nargin < 1, overrides = struct(); end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));          % validation/source -> repository
addpath(here, fullfile(fileparts(here), 'preprocessing'), root, fullfile(root, 'lib'));
src = src_config(overrides);
s2  = src.s2;

stamp    = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir   = fullfile(src.outRoot, [stamp '_' s2.runName]);
simDir   = fullfile(outDir, 'sim');
derivDir = fullfile(outDir, 'derivatives');
mkdir(simDir);

%% Head models, parcels and the true sources (as in Stage 1)
H = src_heads(src);                          % also starts EEGLAB
A = src_atlas(s2.atlas, src, H);
nPar = numel(A.names);
[trips, allTrip, tripDist] = src_triplets(A, src, H.bst.pos);
P = src_patches(A, H, src);
labels = src.montages.(s2.montage);
[~, rowNy] = ismember(labels, H.ny.labels);
Lf = H.ny.L(rowNy, :) * P;                   % regional signals to scalp
T  = s2.secs * src.srate;
block = round(s2.blockSecs * src.srate);

%% Simulated datasets
sim = sim_config(struct('labels', {labels}, 'secs', s2.secs, 'srate', src.srate));
lf  = sim_leadfield(sim);
names = {};
for seed = s2.seeds
    bg = sim_clean_eeg(lf, sim, seed);
    arts = cell(size(s2.artifacts));
    for k = 1:numel(s2.artifacts)
        arts{k} = sim_artifact(lf, sim, s2.artifacts{k}, 1000*seed + 10*k);
    end
    for de = src.density
        for ci = 1:numel(src.conditions)
            S = sources(s2, src.conditions{ci}, nPar, T, trips, src, seed*100 + ci, de.amp, allTrip);
            Yp = Lf * S;
            Yp = Yp * sqrt(mean(var(double(bg.data), 0, 2)) * 10^(s2.parcelDb/10) / mean(var(Yp, 0, 2)));
            Xc = double(bg.data) + Yp;
            E  = bg; E.data = Xc;
            Xa = Xc;
            for k = 1:numel(arts)
                [~, a] = sim_inject(E, arts{k}.data, s2.artSnrDb);
                Xa = Xa + a * arts{k}.data;
            end
            name = sprintf('s%02d_%s_%s', seed, de.name, src.conditions{ci});
            pop_saveset(sim_eegset(Xc, src.srate, labels, [name '_cln']), ...
                        'filename', [name '_cln.set'], 'filepath', simDir);
            pop_saveset(sim_eegset(Xa, src.srate, labels, [name '_art']), ...
                        'filename', [name '_art.set'], 'filepath', simDir);
            names{end+1} = struct('name', name, 'seed', seed, 'density', de, 'ci', ci); %#ok<AGROW>
        end
    end
end

%% Pipeline, once over all inputs
pipe = s2.pipeline;
pipe.inDir  = simDir;
pipe.outDir = derivDir;
Q = run_preprocessing(pipe);

%% Source reconstruction and O-information
R = table(); D = table();
Kel = containers.Map();                      % eLORETA per channel set
nT = size(allTrip, 1);
rng(12345);
sub = randperm(nT, min(s2.oirNull, nT))';   % OIR: triplets evaluated besides the target
for i = 1:numel(names)
    nm = names{i};
    cond = src.conditions{nm.ci};
    [S, Otrue, trip, tr] = sources(s2, cond, nPar, T, trips, src, nm.seed*100 + nm.ci, nm.density.amp, allTrip);
    t = find(ismember(allTrip, sort(trip), 'rows'));
    ev = [t; setdiff(sub, t)];
    Sb = bandpass_fft(S, s2.band, src.srate);

    runs = [{'oracle', 'none'}; cell(0, 2)];
    for v = s2.variants
        for me = src.methods
            runs(end+1, :) = {v{1}, me{1}}; %#ok<AGROW>
        end
    end
    for rr = 1:size(runs, 1)
        variant = runs{rr, 1}; me = runs{rr, 2};
        info = struct('nchan', numel(labels), 'nIC', NaN, 'status', "ok");
        if strcmp(me, 'none')
            X = S;
        else
            [Y, kept, info] = load_variant(variant, nm.name, simDir, derivDir, Q, labels);
            if info.status ~= "ok"
                fprintf('%s %s: %s\n', nm.name, variant, info.status);
                continue
            end
            m  = numel(kept);
            Hc = eye(m) - 1/m;
            Y  = Hc * Y;
            Cy = (Y * Y') / size(Y, 2);
            Linv = Hc * src_interp(H.bst.chan, H.ny.chan(rowNy(kept), :), mean(H.bst.pos, 1)) * H.bst.L;
            key = strjoin(labels(kept), ',');
            if strcmp(me, 'eloreta')
                if ~isKey(Kel, key)
                    Kel(key) = src_inverse('eloreta', Linv, eye(m), src.reg, labels(kept), H.bst.pos);
                end
                K = Kel(key);
            else
                K = src_inverse(me, Linv, Cy, src.reg, labels(kept), H.bst.pos);
            end
            X = src_pc1(K, A.bst, nPar, Cy) * Y;
            lam = eig(Cy);
            info.rank = sum(lam > 1e-6 * max(lam));
        end
        Ol = nan(nT, 1); Oi = Ol; pVar = NaN; nFail = 0;
        if strcmp(s2.measure, 'OIR')
            % 'triplet': VAR per triplet on the target and s2.oirNull other
            %   triplets, with the lagged/instantaneous split.
            % 'full': one VAR on all parcels (order by MDL), restricted to
            %   every triplet through its spectral matrix; total OIR only.
            % Target: moving block bootstrap. Others: flagged when |OIR|
            % exceeds the 95th percentile of the oracle estimates of the
            % independent triplets (estimation noise), so oracle fpr = 5%.
            Oest = nan(nT, 1); lo = Oest; hi95 = Oest; sig = false(nT, 1);
            if strcmp(s2.oirFit, 'full')
                ev = [t; setdiff((1:nT)', t)];
                [Oest(ev), pVar] = src_oir_full(X, allTrip(ev, :), [], src.srate, s2.oirNfft, s2.oirPmax);
                est = @(Z) src_oir_full(Z, allTrip(t, :), pVar, src.srate, s2.oirNfft);
            else
                [Oest(ev), Ol(ev), Oi(ev)] = src_oir3(X, allTrip(ev, :), s2.oirOrder);
                pVar = s2.oirOrder;
                est = @(Z) src_oir3(Z, allTrip(t, :), s2.oirOrder);
            end
            if rr == 1, thr = prctile(abs(Oest(ev(2:end))), 95); end
            nFail = mean(isnan(Oest(ev)));          % unit-circle VAR fits, OIR undefined
            sig(ev) = abs(Oest(ev)) > thr;
            rng(nm.seed + 999);
            nb = floor(size(X, 2) / block); B = zeros(src.nBoot, 1);
            for b = 1:src.nBoot
                idx = reshape(randi(size(X, 2) - block + 1, nb, 1) + (0:block-1), 1, []);
                B(b) = est(X(:, idx));
            end
            lo(t) = prctile(B, 2.5); hi95(t) = prctile(B, 97.5);
            sig(t) = lo(t) > 0 || hi95(t) < 0;
        else
            [Oest, p, lo, hi95] = src_boot(X, allTrip, src.nBoot, nm.seed, block);
            sig = p < src.alpha;
        end
        zero = abs(Otrue) < 1e-12 & ~isnan(Oest);
        rOwn = abs(diag(corr(bandpass_fft(X, s2.band, src.srate)', Sb')));
        if ~isfield(info, 'rank'), info.rank = NaN; end

        R = [R; table(nm.seed, string(nm.density.name), string(cond), string(variant), string(me), ...
            info.nchan, info.nIC, info.rank, Otrue(t), Oest(t), lo(t), hi95(t), sig(t), ...
            sig(t) && sign(Oest(t)) == sign(Otrue(t)), mean(sig(zero)), ...
            mean(sig(zero) & Oest(zero) > 0), mean(sig(zero) & Oest(zero) < 0), ...
            median(Oest(zero)), prctile(abs(Oest(zero)), 95), median(rOwn), min(rOwn(trip)), ...
            mean(abs(Oest(zero)) > s2.effMin), tr.Olag, Ol(t), tr.Oinst, Oi(t), ...
            prctile(abs(Ol(zero)), 95), prctile(abs(Oi(zero)), 95), pVar, nFail, ...
            'VariableNames', {'seed','density','condition','variant','method', ...
            'nchan','n_ic_removed','data_rank','O_true','O_est','ci_lo','ci_hi','sig','sign_ok', ...
            'fpr','fpr_red','fpr_syn','O0_median','O0_abs_p95','r_own_median','r_own_trip_min', ...
            'fpr_eff','O_lag_true','O_lag_est','O_inst_true','O_inst_est','O0_lag_p95','O0_inst_p95','var_order','oir_failed'})]; %#ok<AGROW>

        if strcmp(cond, 'null')
            [~, ~, bin] = histcounts(tripDist, src.distEdges);
            for b = unique(bin(bin > 0))'
                in = bin == b & ~isnan(Oest);
                if ~any(in), continue; end
                D = [D; table(nm.seed, string(nm.density.name), string(variant), string(me), ...
                    mean(src.distEdges(b:b+1)), sum(in), mean(Oest(in)), mean(sig(in)), ...
                    'VariableNames', {'seed','density','variant','method','dist_mm','n','O_mean','fpr'})]; %#ok<AGROW>
            end
        end
    end
    fprintf('%s done\n', nm.name);
end

writetable(R, fullfile(outDir, 'metrics.csv'));
writetable(D, fullfile(outDir, 'distance.csv'));
save(fullfile(outDir, 'setup.mat'), 'src', 'trips');
src_figure_s2(outDir);
fprintf('Results in %s\n', outDir);
end

% -------------------------------------------------------------------------
function [S, Otrue, trip, tr] = sources(s2, cond, nPar, T, trips, src, seed, amp, allTrip)
% Regional signals and the true O of every triplet.
% 'O':   white signals (src_sources), static O-information
% 'OIR': AR(2) oscillators with lagged coupling (src_sources_var), O-information
%        rate; only the target triplet is nonzero, since every other triplet
%        contains an independent parcel
if strcmp(s2.measure, 'OIR')
    [S, tr, trip] = src_sources_var(cond, nPar, T, trips, src, seed, amp);
    Otrue = zeros(size(allTrip, 1), 1);
    Otrue(ismember(allTrip, sort(trip), 'rows')) = tr.O;
else
    [S, Ctrue, trip] = src_sources(cond, nPar, T, trips, src, seed, amp);
    Otrue = src_oinfo3(corrcov(Ctrue), allTrip);
    tr = struct('Olag', NaN, 'Oinst', NaN);
end
end

function [Y, kept, info] = load_variant(variant, name, simDir, derivDir, Q, labels)
% Data of one variant, with the indices of the channels it kept.
% raw and art_raw: the simulated input; *_pipe: the pipeline output.
info = struct('nchan', NaN, 'nIC', NaN, 'status', "ok");
Y = []; kept = [];
switch variant
    case 'raw',        file = [name '_cln']; piped = false;
    case 'art_raw',    file = [name '_art']; piped = false;
    case 'clean_pipe', file = [name '_cln']; piped = true;
    case 'art_pipe',   file = [name '_art']; piped = true;
end
if piped
    q = Q(string(Q.subject) == string(file), :);
    if height(q) ~= 1 || string(q.status) ~= "ok"
        info.status = "pipeline failed";
        return
    end
    if ismember('n_ic_flagged', Q.Properties.VariableNames), info.nIC = q.n_ic_flagged; end
    E = pop_loadset('filename', [file '_clean.set'], 'filepath', derivDir);
else
    E = pop_loadset('filename', [file '.set'], 'filepath', simDir);
end
[ok, kept] = ismember({E.chanlocs.labels}, labels);
assert(all(ok), 'run_src_stage2:labels', 'Output has unknown channels.');
Y = double(E.data);
info.nchan = numel(kept);
end

function Y = bandpass_fft(X, band, fs)
% Ideal band-pass by zeroing FFT bins, for comparing true and reconstructed
% signals in the band the pipeline keeps. Comparison only, not filtering
% of the analysed data.
n = size(X, 2);
f = (0:n-1) * fs / n;
f = min(f, fs - f);                          % two-sided frequencies
F = fft(X, [], 2);
F(:, f < band(1) | f > band(2)) = 0;
Y = real(ifft(F, [], 2));
end
