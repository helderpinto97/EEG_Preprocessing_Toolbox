function R = run_it_validation(runDir, opts)
% RUN_IT_VALIDATION  Information-theoretic measures under each artifact.
%
%   R = run_it_validation(runDir)                        defaults
%   R = run_it_validation(runDir, struct('nOIR', 100))   with overrides
%
% Runs on a finished run_validation folder, so the pipeline is not run
% again. For every dataset the measures are computed on the ground truth
% (true), the contaminated input (in) and the pipeline output (out). Truth
% and input get the band-pass, channels and reference of the output
% (sim_match), so differences come from the artifact and its removal only.
%
%   mi_*      Gaussian mutual information of every channel pair
%   o_*       Gaussian O-information of every channel triplet (src_oinfo3)
%   oir_*     O-information rate of nOIR random triplets, VAR(oirOrder)
%             (src_oir3); oirlag_* its lagged part
%   bh_*      brain-heart: Gaussian MI between each channel and the
%             simulated ECG waveform. The clean EEG is independent of the
%             heart, so any excess over the ground truth is spurious.
%             ecg_ref_r: correlation of the regenerated ECG with the ECG
%             part of the injected artifact (below 0.9: the injected part
%             is used as reference, see below; NaN: no ECG injected).
%   mir_<band>_*, te_rr2eeg_<band>_*, te_eeg2rr_<band>_*, inst_<band>_*
%             beat-to-beat brain-heart Mutual Information Rate between the
%             heart period series RR and the log band power of each channel
%             within each heart period, linear Gaussian (VAR of order
%             teOrder), decomposed into the transfer entropies in both
%             directions and the instantaneous term; mean over channels.
%             The R peaks come from the ECG reference. True value 0 up to
%             the small-sample bias (about 120 s at 70 bpm gives 140
%             beats), which the truth shows. Artifact power within a heart
%             period depends on that same period, so it acts first on the
%             instantaneous term.
%   hep_*     heartbeat-evoked potential: RMS over channels of the EEG
%             averaged 0.2 to 0.6 s after each R peak (uV). Without
%             coupling the clean EEG has none, so the truth gives the floor.
%
% Runs with sim.coupling (genuine interactions, sim_coupled; see tests/EEG
% Genuine Interactions Validation Plan.md) add, against the background
% alone (ground_truth/s<seed>_bg.set) to find what the coupling made:
%   n_red, n_syn          channel triplets with O_true - O_bg above oGen
%                         (genuine redundancy) or below -oGen (synergy)
%   o_red_*, o_syn_*      their mean O
%   o_red_ratio_*, ...    median of (O - O_bg) / (O_true - O_bg): 1 kept,
%                         0 lost, < 0 reversed
%   o_red_sign_*, ...     share of them with the sign of the truth
%   oir_red_*, oirlag_red_*, oir_syn_*, oirlag_syn_*
%                         OIR and its lagged part, nGen strongest triplets
%   *_bh_*                MIR, TE both ways and instantaneous term in band
%                         bhBand at the peak channel of the brain-heart
%                         source; te_*_bh_p_* asymptotic p values (true
%                         coupling heart -> brain only, so TE EEG -> RR is
%                         the null direction)
%   hep_pk_*              HEP at the peak channel of the HEP source, mean
%                         0.25 to 0.35 s after the R peak (uV)
%   bh_peak_kept, hep_peak_kept
%                         false when the pipeline rejected the peak channel;
%                         the strongest kept channel is used instead
%   hep_r_*               correlation of the HEP (all channels, 0.2 to 0.6
%                         s) with that of the truth
% The R peaks are then the true ones (sim_heart).
%
% Per measure: the mean over pairs, triplets or channels (_true, _in, _out)
% and the mean absolute error against the truth (_mae_in, _mae_out). Also
% o_flip_*: share of triplets with |O_true| > oMin whose sign flips;
% bh_max_*: largest brain-heart MI over channels; oir_nan_*: triplets
% whose fitted VAR has a unit root (line noise).
%
% The estimators are Gaussian, so they see linear dependence only. The
% finite-sample bias is the same for the three versions and cancels in
% the error against the truth.
%
% Output: it_metrics.csv in runDir (R, returned too).
%
% For one artifact at a time at every SNR, first run for example
%   run_validation(struct('runName', 'it', 'artifacts', ...
%       {{'eog_blink','eog_vertical','eog_horizontal','emg_temporal', ...
%         'emg_frontal','emg_neck','ecg','line','drift','pop'}}));

if nargin < 2, opts = struct(); end
o = struct('nOIR', 50, 'oirOrder', 10, 'teOrder', 2, 'oMin', 0.01, 'seed', 1, ...
           'overwrite', false, 'oGen', 0.05, 'nGen', 5, 'bhBand', 'theta');
for f = fieldnames(opts)'
    assert(isfield(o, f{1}), 'run_it_validation:unknownField', 'Unknown field %s.', f{1});
    o.(f{1}) = opts.(f{1});
end
outFile = fullfile(runDir, 'it_metrics.csv');
assert(o.overwrite || ~isfile(outFile), 'run_it_validation:exists', ...
    '%s exists; pass struct(''overwrite'', true) to replace it.', outFile);

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));          % validation/preprocessing -> repository
addpath(here, root, fullfile(root, 'lib'), fullfile(fileparts(here), 'source'));
if ~exist('eeglab', 'file')
    addpath(fullfile(root, 'lib', 'toolboxes', 'eeglab'));
end
evalc('eeglab nogui');

S    = load(fullfile(runDir, 'simulation.mat'), 'sim', 'info');
sim  = S.sim;
coupled = isfield(sim, 'coupling') && sim.coupling;
cfg  = prep_config(sim.pipeline);
cfgF = cfg; cfgF.reref = 'none';            % band-pass only, for the ECG waveform
lf   = sim_leadfield(sim);

M = readtable(fullfile(runDir, 'metrics.csv'), 'TextType', 'string');
M = M(M.status == "ok", :);

tag  = {'true', 'in', 'out'};
rows = cell(height(M), 1);
clean = [];
for i = 1:height(M)
    m    = M(i, :);
    file = sprintf('s%02d_%s', m.seed, m.dataset);
    if isempty(clean) || clean.seed ~= m.seed       % one ground truth per seed
        clean = pop_loadset('filename', sprintf('s%02d.set', m.seed), ...
                            'filepath', fullfile(runDir, 'ground_truth'));
        clean.seed = m.seed;
        % The ECG of this seed: same seed as artifact_seed(seed, "ecg") in
        % run_validation, so it matches the injected artifact beat by beat
        % in runs made with the current seed codes.
        simA = sim;
        if coupled                                  % the heart shared with the EEG
            heart = sim_heart(sim, 1000*m.seed + 10*7);
            simA.beats = heart.t;
            ci = S.info{sim.seeds == m.seed}.coupling;
            bg = pop_loadset('filename', sprintf('s%02d_bg.set', m.seed), ...
                             'filepath', fullfile(runDir, 'ground_truth'));
        end
        a    = sim_ecg(lf, simA, 1000*m.seed + 10*7);
        sEcg = a.data(a.peak, :);
        [~, j] = max(abs(sEcg));
        topo = a.data(:, j);                        % the same for every seed
    end
    cont = pop_loadset('filename', [file '.set'], 'filepath', fullfile(runDir, 'sim'));
    % With ECG injected, check the regenerated waveform against the ECG part
    % of the injected artifact (its projection on the ECG topography). Runs
    % with other seed codes do not match; there the projection is used,
    % which also carries what other artifacts project on that topography.
    ref = sEcg; refR = NaN;
    if contains(m.artifact, "ecg")
        proj = topo' * (double(cont.data) - double(clean.data)) / (topo' * topo);
        c = corrcoef(proj, sEcg);
        refR = c(1, 2);
        if abs(refR) < 0.9, ref = proj; end         % the sign of topo is arbitrary
    end
    ecg = sim_match(ref, clean.srate, 1, cfgF);
    P    = pop_loadset('filename', [file '_clean.set'], 'filepath', fullfile(runDir, 'derivatives'));
    [~, keep] = ismember({P.chanlocs.labels}, {clean.chanlocs.labels});
    X = {sim_match(clean.data, clean.srate, keep, cfg), ...
         sim_match(cont.data,  clean.srate, keep, cfg), ...
         double(P.data)};

    n     = numel(keep);
    pairs = nchoosek(1:n, 2);
    trip  = nchoosek(1:n, 3);
    rng(o.seed);
    tOIR  = trip(randperm(size(trip, 1), min(o.nOIR, size(trip, 1))), :);
    if coupled
        % What the coupling made: truth against the background alone.
        Obg = src_oinfo3(corrcoef(sim_match(bg.data, clean.srate, keep, cfg)'), trip);
        dO  = src_oinfo3(corrcoef(X{1}'), trip) - Obg;
        gR  = dO > o.oGen;
        gS  = dO < -o.oGen;
        [~, iR] = maxk(dO, o.nGen);  [~, iS] = mink(dO, o.nGen);
        tG  = {trip(iR(dO(iR) > o.oGen), :), trip(iS(dO(iS) < -o.oGen), :)};
    end

    v = struct('mi', {cell(1,3)}, 'o', {cell(1,3)}, 'oir', {cell(1,3)}, ...
               'oirlag', {cell(1,3)}, 'bh', {cell(1,3)});
    for k = 1:3
        C = corrcoef([X{k}; ecg]');                 % last row: the ECG
        rb = C(1:n, end);
        C  = C(1:n, 1:n);
        v.mi{k} = -0.5 * log(1 - C(sub2ind(size(C), pairs(:,1), pairs(:,2))).^2);
        v.o{k}  = src_oinfo3(C, trip);
        [v.oir{k}, v.oirlag{k}] = src_oir3(X{k}, tOIR, o.oirOrder);
        v.bh{k} = -0.5 * log(1 - rb.^2);
    end

    r = struct('seed', m.seed, 'dataset', m.dataset, 'artifact', m.artifact, ...
               'severity', m.severity, 'snr_target_db', m.snr_target_db, 'nchan', n, ...
               'ecg_ref_r', refR);
    for f = fieldnames(v)'
        x = v.(f{1});
        for k = 1:3, r.([f{1} '_' tag{k}]) = mean(x{k}, 'omitnan'); end
        for k = 2:3, r.([f{1} '_mae_' tag{k}]) = mean(abs(x{k} - x{1}), 'omitnan'); end
    end
    big = abs(v.o{1}) > o.oMin;
    for k = 2:3
        r.(['o_flip_' tag{k}])   = mean(sign(v.o{k}(big)) ~= sign(v.o{1}(big)));
        r.(['oir_nan_' tag{k}])  = sum(isnan(v.oir{k}));
    end
    for k = 1:3, r.(['bh_max_' tag{k}]) = max(v.bh{k}); end
    if coupled
        r.n_red = sum(gR); r.n_syn = sum(gS);
        gn = {'red', 'syn'}; gm = {gR, gS};
        for g = 1:2
            for k = 1:3
                r.(['o_' gn{g} '_' tag{k}]) = mean(v.o{k}(gm{g}));
                [oi, ol] = src_oir3(X{k}, tG{g}, o.oirOrder);
                r.(['oir_' gn{g} '_' tag{k}])    = mean(oi, 'omitnan');
                r.(['oirlag_' gn{g} '_' tag{k}]) = mean(ol, 'omitnan');
            end
            for k = 2:3
                r.(['o_' gn{g} '_ratio_' tag{k}]) = median((v.o{k}(gm{g}) - Obg(gm{g})) ./ dO(gm{g}));
                r.(['o_' gn{g} '_sign_' tag{k}])  = mean(sign(v.o{k}(gm{g})) == sign(v.o{1}(gm{g})));
            end
        end
    end

    % Beat-to-beat brain-heart measures, R peaks from the ECG reference.
    e = ecg;
    if max(e) < -min(e), e = -e; end                % R wave up
    rp = find(islocalmax(e, 'MinSeparation', round(0.33 * clean.srate)) & e > 0.5 * max(e));
    if coupled, rp = round(heart.t * clean.srate) + 1; end     % the true R peaks
    rr = diff(rp)' / clean.srate;                   % heart period n: rp(n) to rp(n+1)
    hw = round(0.2 * clean.srate) : round(0.6 * clean.srate);
    hb = rp(rp + hw(end) <= clean.pnts);
    for k = 1:3
        for b = sim.bands(:)'
            Pw = beat_power(X{k}, clean.srate, b.range, rp);       % beats x channels
            d = zeros(n, 4);                 % MIR, TE rr->eeg, TE eeg->rr, instantaneous
            for ch = 1:n
                [d(ch,1), d(ch,2), d(ch,3), d(ch,4)] = mir_lin(rr, Pw(:, ch), o.teOrder);
            end
            nm = {'mir', 'te_rr2eeg', 'te_eeg2rr', 'inst'};
            for q = 1:4
                r.([nm{q} '_' b.name '_' tag{k}]) = mean(d(:, q));
            end
            if coupled && strcmp(b.name, o.bhBand)  % at the brain-heart source
                ch = peak_kept(ci.bhTopo, keep);
                dc = nan(1, 4); pv = nan(1, 2);
                r.bh_peak_kept = ismember(ci.bhPeak, keep);
                if ~isempty(ch)
                    dc = d(ch, :);
                    Ne = numel(rr) - o.teOrder;
                    pv = 1 - gammainc(Ne * dc(2:3), o.teOrder / 2);
                end
                for q = 1:4, r.([nm{q} '_bh_' tag{k}]) = dc(q); end
                r.(['te_rr2eeg_bh_p_' tag{k}]) = pv(1);
                r.(['te_eeg2rr_bh_p_' tag{k}]) = pv(2);
            end
        end
        hep = mean(reshape(X{k}(:, hb + hw'), n, numel(hw), []), 3);   % channels x time
        r.(['hep_' tag{k}]) = sqrt(mean(hep.^2, 'all'));
        if coupled
            hc  = peak_kept(ci.hepTopo, keep);
            win = hw / clean.srate >= 0.25 & hw / clean.srate <= 0.35;
            r.hep_peak_kept = ismember(ci.hepPeak, keep);
            if ~isempty(hc), r.(['hep_pk_' tag{k}]) = mean(hep(hc, win)); end
            if k == 1, hep1 = hep; end
            if k > 1, c = corrcoef(hep(:), hep1(:)); r.(['hep_r_' tag{k}]) = c(1, 2); end
        end
    end
    rows{i} = r;
    fprintf('%s done (%d/%d)\n', file, i, height(M));
end
R = struct2table([rows{:}], 'AsArray', true);
writetable(R, outFile);
fprintf('\nIT validation done. Results in %s\n', outFile);
end

% -------------------------------------------------------------------------
function ch = peak_kept(topo, keep)
% Index (into KEEP) of the kept channel where TOPO, under the average
% reference, is largest: the peak channel itself unless the pipeline
% rejected it, then the next best.
ta = topo - mean(topo);
[~, ch] = max(abs(ta(keep)));
end
