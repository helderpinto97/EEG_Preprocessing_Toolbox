function src = src_config(overrides)
% SRC_CONFIG  Parameters of the source reconstruction validation (Stage 1).
%
%   src = src_config()
%   src = src_config(struct('seeds', 1:2, 'nBoot', 100))
%
% See tests/EEG Source Reconstruction Validation Plan.md, section 12.

if nargin < 1, overrides = struct(); end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % validation/source -> repository

%% Paths
src.sereegaPath = fullfile(root, 'lib', 'toolboxes', 'SEREEGA');
src.hartmutPath = fullfile(root, 'lib', 'toolboxes', 'HArtMuT');
src.bstDir      = fullfile(src.sereegaPath, 'leadfield', 'brainstorm');
src.outRoot     = fullfile(root, 'validation', 'results', 'source');
src.runName     = 'src_initial';

%% Montages
% Labels the HArtMuT New York Head provides. The 64-channel 10-10 cap lacks
% TP9 and TP10 in that head, so it has 62 channels.
src.montages.m32 = {'Fp1','Fp2','AF3','AF4','F7','F3','Fz','F4','F8', ...
    'FC5','FC1','FC2','FC6','T7','C3','Cz','C4','T8', ...
    'CP5','CP1','CP2','CP6','P7','P3','Pz','P4','P8', ...
    'PO3','PO4','O1','Oz','O2'};
src.montages.m62 = {'Fp1','Fp2','AF7','AF3','AFz','AF4','AF8', ...
    'F7','F5','F3','F1','Fz','F2','F4','F6','F8', ...
    'FT9','FT7','FC5','FC3','FC1','FCz','FC2','FC4','FC6','FT8','FT10', ...
    'T7','C5','C3','C1','Cz','C2','C4','C6','T8', ...
    'TP7','CP5','CP3','CP1','CPz','CP2','CP4','CP6','TP8', ...
    'P7','P5','P3','P1','Pz','P2','P4','P6','P8', ...
    'PO7','PO3','POz','PO4','PO8','O1','Oz','O2'};

%% Factors
src.atlases    = {'dkt62', 'coarse20'};  % src_atlas
src.methods    = {'eloreta', 'lcmv'};    % src_inverse; Stage 2 also takes 'champagne'
% 'template': simulate with the New York Head, invert with the ICBM152
%             OpenMEEG BEM of Brainstorm (different head, electrodes, sources)
% 'matched':  invert with the head that made the data; upper bound only
src.headmodels = {'template', 'matched'};
src.conditions = {'null', 'red_near', 'red_far', 'syn_near', 'syn_far'};
% Amplitude of the parcels outside the triplet: dense = every parcel as
% active as the triplet (whole-brain activity), sparse = 10%.
src.density    = struct('name', {'dense', 'sparse'}, 'amp', {1, 0.1});
src.seeds      = 1:5;

%% Sources (src_sources)
% One white Gaussian signal per parcel, on a cortical patch of the New York
% Head around the parcel centre. Independent unless in the multiplet.
src.patchRadius = 15;  % mm; 0 gives a single point source per parcel
src.secs    = 120;
src.srate   = 250;
src.redA    = 2;     % redundant: x_i = a*s + e_i     -> true O = +0.40 nats
src.synB    = 0.5;   % synergistic: x3 = x1 + x2 + b*e -> true O = -0.51 nats
src.snrDb   = 10;    % source projection over white sensor noise, all channels

% Multiplets, as MNI points (mm); each point picks the parcel that contains
% it. near: left M1 and the two parcels with the closest centres.
src.m1Left   = [-38 -20 58];
src.farPts   = [-38 -20 58; 38 -20 58; -8 -90 5];   % left M1, right M1, left V1

%% Inverse (src_inverse)
src.reg = 0.05;      % Tikhonov, fraction of mean sensor variance

%% O-information (src_oinfo3)
src.nBoot = 200;     % bootstrap resamples of time points
src.alpha = 0.05;
src.distEdges = 0:20:180;  % mm, mean pairwise parcel distance, null curve

%% Stage 2 (run_src_stage2): background, artifacts and the pipeline
% The regional signals of Stage 1 are added to the SEREEGA background EEG
% of the preprocessing validation (sim_clean_eeg), with and without
% artifacts, and analysed with and without the pipeline in lib/.
src.s2.runName   = 'src_stage2';
src.s2.montage   = 'm62';
src.s2.atlas     = 'dkt62';
src.s2.seeds     = 1:3;      % Stage 1 showed almost no variation over seeds
src.s2.secs      = 300;      % ICA wants >= 20*rank^2 samples: 72000 for rank 60, 75000 here
% raw:        regional signals + background, average reference only
% clean_pipe: the same, through the pipeline
% art_pipe:   + artifacts, through the pipeline
% art_raw:    + artifacts, average reference only
src.s2.variants  = {'raw', 'clean_pipe', 'art_pipe', 'art_raw'};
src.s2.parcelDb  = 0;        % power of the regional signals over the background, all channels
src.s2.artifacts = {'eog_blink', 'eog_horizontal', 'emg_temporal', 'ecg', 'line'};
src.s2.artSnrDb  = 5;        % each artifact against the clean EEG ("medium" in sim_config)
src.s2.blockSecs = 1;        % bootstrap block; background and filtered signals are autocorrelated
src.s2.band      = [0.5 45]; % Hz; true and reconstructed signals are compared in this band
src.s2.pipeline  = struct('qcFigures', false);  % production settings otherwise
% 'O':   white regional signals, static O-information (src_oinfo3)
% 'OIR': AR(2) oscillators with lagged coupling (src_sources_var), O-information
%        rate from a VAR per triplet (src_oir3, OIR toolbox of Faes et al. 2022)
src.s2.measure   = 'O';
% 'triplet': one VAR per triplet (lagged/instantaneous split, s2.oirNull triplets)
% 'full':    one VAR on all parcels, restricted to each triplet through the
%            spectral matrix (all triplets); needs data rank > parcels: coarse20
src.s2.oirFit    = 'triplet';
src.s2.oirOrder  = 10;       % 'triplet' VAR order (40 ms at 250 Hz); mixtures are not finite VARs
src.s2.oirPmax   = 15;       % 'full': maximum order, chosen by MDL
src.s2.oirNfft   = 128;      % 'full': frequency bins over 0..fs/2
src.s2.oirNull   = 200;      % triplets evaluated besides the target (one VAR each)
src.s2.effMin    = 0.05;     % nats; fpr_eff counts independent triplets with |O| above this

%% Dynamic sources (src_sources_var), used when src.s2.measure = 'OIR'
% Triplet: AR(2) oscillators at fTrip, coupled at lag samples with
% coefficient c (common driver: redundancy; common target: synergy).
% r = 0.95 and c = 0.6 give a true OIR of +0.38 and -0.38 nats.
src.var = struct('lag', 2, 'c', 0.6, 'r', 0.95, 'fTrip', 10, 'fRange', [4 30]);

%% Overrides
given = fieldnames(overrides);
bad   = given(~ismember(given, fieldnames(src)));
assert(isempty(bad), 'src_config:unknown', 'Unknown field(s): %s', strjoin(bad, ', '));
for k = 1:numel(given), src.(given{k}) = overrides.(given{k}); end
end
