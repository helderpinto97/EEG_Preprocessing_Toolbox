%% Preprocess Cairo_Dataset
% Raw .edf files in data/Cairo_Dataset -> cleaned .set files, QC sheets and
% qc_log.csv in derivatives/cairo_dataset. Settings: config/cairo_dataset.m.
% Section 2 makes raw-data figures per recording (bad channels, flat
% stretches, correlation, spectra) in derivatives/cairo_dataset/raw_figures.

clear; clc;
root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'lib'), fullfile(root, 'config'));

cfg = prep_config(fullfile(root, 'config', 'cairo_dataset.m'));
if ~exist('eeglab', 'file'), addpath(cfg.eeglabPath); end
evalc('eeglab nogui');

%% 1. Preprocessing
T = run_preprocessing(fullfile(root, 'config', 'cairo_dataset.m'));
disp(T(:, intersect({'subject','status','nchan_rejected','chans_rejected', ...
                     'n_ic_flagged','rank_final','reref_final','error'}, ...
                    T.Properties.VariableNames, 'stable')));

%% 2. Raw-data figures
figDir = fullfile(cfg.outDir, 'raw_figures');
if ~isfolder(figDir), mkdir(figDir); end
files = dir(fullfile(cfg.inDir, cfg.fileExt));

for k = 1:numel(files)
    [~, base] = fileparts(files(k).name);

    % Same import, channel selection and positions as the pipeline
    EEG = prep_load(fullfile(files(k).folder, files(k).name));
    EEG = prep_noneeg(EEG, cfg);
    EEG = prep_chanlocs(EEG, cfg);
    F   = pop_eegfiltnew(EEG, 'locutoff', 1, 'hicutoff', 45);

    % Channels clean_rawdata flags with the pipeline settings
    C = clean_artifacts(F, 'FlatlineCriterion', cfg.flatlineSec, ...
        'ChannelCriterion', cfg.chanCorr, 'LineNoiseCriterion', cfg.lineNoiseSD, ...
        'Highpass', 'off', 'BurstCriterion', 'off', 'WindowCriterion', 'off', ...
        'BurstRejection', 'off');
    bad = ~logical(C.etc.clean_channel_mask(:)');

    X   = double(F.data);  fs = F.srate;  lab = {F.chanlocs.labels};  nc = numel(lab);
    t   = (0:size(X,2)-1) / fs;
    Xa  = X - mean(X, 1);                              % average reference
    rb  = [linspace(0,1,128)' linspace(0,1,128)' ones(128,1); ...
           ones(128,1) linspace(1,0,128)' linspace(1,0,128)'];  % blue-white-red

    % Figure 1: RMS over time, flat stretches, correlation
    f1 = figure('Color', 'w', 'Position', [50 50 1500 900],'Theme','Light');
    tl = tiledlayout(f1, 2, 2, 'TileSpacing', 'compact');

    nexttile(tl);
    w = fs; nb = floor(size(X,2) / w);
    R = squeeze(sqrt(mean(reshape(X(:,1:nb*w).^2, nc, w, nb), 2)));
    imagesc((0:nb-1)/60, 1:nc, log10(R + eps)); colormap(gca, parula);
    cb = colorbar; cb.Label.String = 'log_{10} RMS (\muV)';
    set(gca, 'YTick', 1:nc, 'YTickLabel', lab); xlabel('Time (min)');
    title('1 s RMS, 1-45 Hz, recording reference');
    hold on; plot(zeros(1, nnz(bad)) - 0.3, find(bad), 'r<', 'MarkerFaceColor', 'r');

    nexttile(tl);
    fl = movmean(double(abs(diff(X, 1, 2)) < 1e-6), 5*fs, 2) > 0.95;
    imagesc(t(2:end)/60, 1:nc, fl, [0 1]); colormap(gca, [1 1 1; 0.8 0.1 0.1]);
    set(gca, 'YTick', 1:nc, 'YTickLabel', lab); xlabel('Time (min)');
    title('Flat signal (red = flat over a 5 s window)');

    nexttile(tl);
    imagesc(corrcoef(X'), [-1 1]); colormap(gca, rb); colorbar; axis square
    set(gca, 'XTick', 1:nc, 'XTickLabel', lab, 'YTick', 1:nc, 'YTickLabel', lab, 'XTickLabelRotation', 90);
    title('Channel correlation, recording reference');

    nexttile(tl);
    imagesc(corrcoef(Xa'), [-1 1]); colormap(gca, rb); colorbar; axis square
    set(gca, 'XTick', 1:nc, 'XTickLabel', lab, 'YTick', 1:nc, 'YTickLabel', lab, 'XTickLabelRotation', 90);
    title('Channel correlation, average reference');

    title(tl, sprintf('%s raw: red markers = flagged (%s)', strrep(base, '_', '\_'), ...
          strjoin(lab(bad), ', ')));
    exportgraphics(f1, fullfile(figDir, [base '_overview.png']), 'Resolution', 110);

    % Figure 2: 10 s of traces and spectra
    f2 = figure('Color', 'w', 'Position', [50 50 1500 900],'Theme','Light');
    tl = tiledlayout(f2, 1, 2, 'TileSpacing', 'compact');

    nexttile(tl); hold on
    idx = round(size(X,2)/2) + (0:10*fs);  sp = 150;
    for c = 1:nc
        col = [0.2 0.2 0.2]; if bad(c), col = [0.85 0.1 0.1]; end
        plot(t(idx), Xa(c,idx) - (c-1)*sp, 'Color', col, 'LineWidth', 0.6);
    end
    set(gca, 'YTick', -(nc-1:-1:0)*sp, 'YTickLabel', fliplr(lab), 'Box', 'off'); axis tight
    xlabel('Time (s)'); title('10 s mid-recording, average reference (red = flagged)');

    nexttile(tl); hold on
    [P, fr] = pwelch(Xa', 4*fs, 2*fs, [], fs);
    for c = find(~bad)
        plot(fr, 10*log10(P(:,c)), 'Color', [0.6 0.6 0.6], 'LineWidth', 0.6, 'HandleVisibility', 'off');
    end
    for c = find(bad)
        plot(fr, 10*log10(P(:,c)), 'LineWidth', 1.5, 'DisplayName', lab{c});
    end
    xlim([1 45]); grid on; xlabel('Frequency (Hz)'); ylabel('PSD (dB \muV^2/Hz)');
    if any(bad), legend('Location', 'northeast'); end
    title('Spectra, average reference (grey = kept)');
    exportgraphics(f2, fullfile(figDir, [base '_traces_psd.png']), 'Resolution', 110);
end
fprintf('Raw-data figures in %s\n', figDir);
