function T = check_coupled_truth(overrides)
% CHECK_COUPLED_TRUTH  Test T0 of the genuine interactions plan: is the
% coupling of sim_coupled visible in the clean scalp EEG, before any
% artifact or pipeline?
%
%   T = check_coupled_truth()                              defaults
%   T = check_coupled_truth(struct('coupledDb', 3, 'seeds', 1:3))
%
% Overrides go to sim_config; sim.coupling is set on. Per seed, the clean
% EEG with coupling (truth) is compared with the background alone, both
% with the band-pass and average reference of the pipeline (sim_match):
%   n_red, n_syn       channel triplets with O_truth - O_bg > 0.05 nats
%                      (genuine redundancy) or < -0.05 (synergy); pass: >= 10
%   dO_max, dO_min     the largest and smallest of these differences
%   te_src             TE RR -> log amplitude at the source (sim_heart)
%   te_rr2eeg, te_eeg2rr, inst, p_rr2eeg, p_eeg2rr
%                      theta band, peak channel of the brain-heart source,
%                      order 2; pass: p_rr2eeg < 0.05 (TE EEG -> RR is the
%                      null direction)
%   te_rr2eeg_bg       the same on the background alone
%   hep_pk, hep_floor  HEP at its peak channel (mean 0.25 to 0.35 s) and the
%                      RMS of everything but the HEP, averaged on the same
%                      beats (0.2 to 0.6 s); pass: hep_pk > 2 * hep_floor
% Needs EEGLAB, SEREEGA and HArtMuT as run_validation.

if nargin < 1 || isempty(overrides), overrides = struct(); end
overrides.coupling = true;
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here, root, fullfile(root, 'lib'), fullfile(fileparts(here), 'source'));
sim = sim_config(overrides);
if ~exist('eeglab', 'file')
    addpath(fullfile(root, 'lib', 'toolboxes', 'eeglab'));
end
evalc('eeglab nogui');
lf  = sim_leadfield(sim);
cfg = prep_config(sim.pipeline);
fs  = sim.srate;
n   = numel(sim.labels);
trip = nchoosek(1:n, 3);
hw  = round(0.2 * fs) : round(0.6 * fs);
win = hw / fs >= 0.25 & hw / fs <= 0.35;

rows = cell(numel(sim.seeds), 1);
for si = 1:numel(sim.seeds)
    seed  = sim.seeds(si);
    bg    = sim_clean_eeg(lf, sim, seed);
    heart = sim_heart(sim, 1000*seed + 70);       % artifact_seed(seed, "ecg")
    [Xg, ci, parts] = sim_coupled(lf, sim, seed, bg, heart);
    B  = sim_match(double(bg.data), fs, 1:n, cfg);
    X  = sim_match(double(bg.data) + Xg, fs, 1:n, cfg);
    N  = sim_match(double(bg.data) + Xg - parts.hep, fs, 1:n, cfg);   % all but the HEP
    dO = src_oinfo3(corrcoef(X'), trip) - src_oinfo3(corrcoef(B'), trip);

    rp = round(heart.t * fs) + 1;
    rr = diff(rp)' / fs;
    [~, te_src] = mir_lin(heart.rr, heart.a, 2);
    Pw = beat_power(X(ci.bhPeak, :), fs, [4 8], rp);
    [mir, t12, t21, inst] = mir_lin(rr, Pw, 2);
    [~, t12bg] = mir_lin(rr, beat_power(B(ci.bhPeak, :), fs, [4 8], rp), 2);
    Ne = numel(rr) - 2;
    pv = 1 - gammainc(Ne * [t12 t21], 1);

    hb = rp(rp + hw(end) <= size(X, 2));
    hx = mean(reshape(X(ci.hepPeak, hb + hw'), numel(hw), []), 2);
    hbg = mean(reshape(N(ci.hepPeak, hb + hw'), numel(hw), []), 2);

    r = struct('seed', seed, 'n_red', sum(dO > 0.05), 'n_syn', sum(dO < -0.05), ...
               'dO_max', max(dO), 'dO_min', min(dO), 'oir_src_red', ci.oirRed, ...
               'oir_src_syn', ci.oirSyn, 'n_beats', numel(rp), 'te_src', te_src, ...
               'mir', mir, 'te_rr2eeg', t12, 'te_eeg2rr', t21, 'inst', inst, ...
               'p_rr2eeg', pv(1), 'p_eeg2rr', pv(2), 'te_rr2eeg_bg', t12bg, ...
               'hep_pk', mean(hx(win)), 'hep_floor', sqrt(mean(hbg.^2)), ...
               'bh_chan', string(sim.labels{ci.bhPeak}), 'hep_chan', string(sim.labels{ci.hepPeak}));
    r.pass = r.n_red >= 10 && r.n_syn >= 10 && r.p_rr2eeg < 0.05 && r.hep_pk > 2 * r.hep_floor;
    rows{si} = r;
    fprintf('seed %d: %d red, %d syn triplets; TE RR->EEG %.3f (p %.3g), EEG->RR %.3f (p %.3g); HEP %.2f uV, floor %.2f\n', ...
            seed, r.n_red, r.n_syn, t12, pv(1), t21, pv(2), r.hep_pk, r.hep_floor);
end
T = struct2table([rows{:}], 'AsArray', true);
end
