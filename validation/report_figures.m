function report_figures(runDirs, outDir, revisedDirs, threshDirs)
% REPORT_FIGURES  Publication figures and a summary table from validation runs.
%
%   report_figures({'validation/results/<run1>', 'validation/results/<run2>'})
%   report_figures(runDirs, outDir)
%   report_figures(runDirs, outDir, revisedDirs)
%   report_figures(runDirs, outDir, revisedDirs, {baseDirs, newDirs})
%
% Pools the metrics.csv of one or more run_validation runs (the clean
% condition is taken from the first run that has it) and writes to OUTDIR
% (default validation/results/report_<timestamp>/):
%
%   fig1_simulation      artifact scalp maps and example traces
%   fig2_performance     artifact removed, SNR after, correlation, by severity
%   fig3_spectral        band power error per artifact, band and severity
%   fig4_pipeline        components removed and channels rejected
%   fig5_iclabel         ICLabel threshold trade-off, Eye, Muscle and Heart
%   fig6_electrode       drift, pops and bad channels (if present)
%   fig7_combined        combined artifacts (if present)
%   fig8_stroke          error of the stroke measures (if stroke runs present)
%   fig9_revision        previous against revised pipeline (if REVISEDDIRS given):
%                        the conditions present in both, healthy EEG
%   fig10_revision_stroke  the same for the stroke measures
%   fig11_muscle_threshold  two ICLabel settings compared (if THRESHDIRS
%                        given: {runs at the old setting, runs at the new})
%   fig12_muscle_stroke  the same for the stroke measures with temporal EMG
%   summary_table.csv    median, min and max per artifact and severity
%
% Every figure is saved as vector PDF and 600 dpi PNG, in Nature style at
% double-column width (18.3 cm). Colours are a fixed, colour-blind-safe order
% (each series also has its own marker, for grayscale print).

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here, fullfile(root, 'lib'));
if ~exist('eeglab', 'file'), addpath(fullfile(root, 'lib', 'toolboxes', 'eeglab')); end
evalc('eeglab nogui');

runDirs = cellstr(runDirs);
if nargin < 2 || isempty(outDir)
    outDir = fullfile(here, 'results', ['report_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
end
if ~isfolder(outDir), mkdir(outDir); end

[Rall, sim] = load_runs(runDirs);
cfg = prep_config(sim.pipeline);
S   = style(sim, unique(Rall.artifact));
R   = Rall(Rall.stroke == "none", :);             % healthy EEG
single = ismember(R.artifact, ["none", S.order]);

writetable(summary_table(Rall, S), fullfile(outDir, 'summary_table.csv'));

save_fig(fig_simulation(R, sim, cfg, S, runDirs), outDir, 'fig1_simulation', 'image');
save_fig(fig_performance(R, S, present_families(R, S)), outDir, 'fig2_performance', 'vector');
save_fig(fig_spectral(R, sim, S),                outDir, 'fig3_spectral',    'vector');
save_fig(fig_pipeline(R, S),                     outDir, 'fig4_pipeline',    'vector');
save_fig(fig_iclabel(R(single, :), cfg, S, runDirs, outDir), outDir, 'fig5_iclabel', 'vector');
if any(ismember(R.artifact, S.electrode))
    save_fig(fig_electrode(R, S), outDir, 'fig6_electrode', 'vector');
end
if any(contains(R.artifact, "+"))
    n    = arrayfun(@(c) numel(split(c, "+")), S.combos);
    fams = struct('name', {'Two artifacts', 'Three or more'}, 'types', {S.combos(n == 2), S.combos(n > 2)});
    save_fig(fig_performance(R, S, fams(arrayfun(@(f) ~isempty(f.types), fams))), outDir, 'fig7_combined', 'vector');
end
if any(Rall.stroke ~= "none")
    save_fig(fig_stroke(Rall(Rall.stroke ~= "none", :), S), outDir, 'fig8_stroke', 'vector');
end

% Previous against revised pipeline, for the conditions rerun with it.
if nargin >= 3 && ~isempty(revisedDirs)
    R1 = load_runs(cellstr(revisedDirs));
    writetable(summary_table(R1, style(sim, unique(R1.artifact))), ...
               fullfile(outDir, 'summary_table_revised.csv'));
    save_fig(fig_revision(Rall, R1, S), outDir, 'fig9_revision', 'vector');
    if any(R1.stroke ~= "none")
        save_fig(fig_revision_stroke(Rall, R1, S), outDir, 'fig10_revision_stroke', 'vector');
    end
end

% Muscle threshold 0.80 against 0.50, same revised pipeline otherwise.
if nargin >= 4 && ~isempty(threshDirs)
    Rb = load_runs(cellstr(threshDirs{1}));
    Rn = load_runs(cellstr(threshDirs{2}));
    names = ["Muscle 0.80", "Muscle 0.50"];
    want  = ["emg_temporal", "emg_frontal", "emg_neck", "eog_blink+emg_temporal", "emg_temporal+ecg"];
    save_fig(fig_revision(Rb, Rn, S, want, names), outDir, 'fig11_muscle_threshold', 'vector');
    if any(Rn.stroke ~= "none")
        save_fig(fig_revision_stroke(Rb, Rn, S, "emg_temporal", names), outDir, 'fig12_muscle_stroke', 'vector');
    end
end

fprintf('Report figures in %s\n', outDir);
end

%% ========================================================================
%  Data
%  ========================================================================
function [R, sim] = load_runs(runDirs)
% All runs in one table, with the stroke stage of each run as a column.
% Runs made before a metric existed get it as NaN (or "" for text), rather
% than the metric being dropped from every run.
R = table();
for i = 1:numel(runDirs)
    T = readtable(fullfile(runDirs{i}, 'metrics.csv'), 'TextType', 'string');
    s = saved_sim(runDirs{i});
    T.run    = repmat(string(runDirs{i}), height(T), 1);
    T.stroke = repmat(string(s.stroke), height(T), 1);
    if ~isempty(R)                               % clean condition once per seed and stage
        done = R(R.artifact == "none", {'seed', 'stroke'});
        dup  = T.artifact == "none" & ismember(T(:, {'seed', 'stroke'}), done);
        T    = T(~dup, :);
    end
    R = stack(R, T);
    if i == 1, sim = s; end
end

% "Artifact removed" compares the error left after cleaning with the error
% before it. When the artifact, after the filter of the pipeline, is already
% smaller than the distortion the pipeline causes on clean data (SNR after
% of the clean condition, same seed and stage), that ratio compares noise
% with noise and swings far past +-100%. Those values are blanked.
R.removed_undefined = false(height(R), 1);
for s = unique(R.seed)'
    for st = unique(R.stroke)'
        floorDb = R.snr_after_db(R.artifact == "none" & R.seed == s & R.stroke == st);
        if isempty(floorDb), continue, end
        sel = R.seed == s & R.stroke == st & R.artifact ~= "none" & R.snr_before_db > floorDb(1);
        R.removed_undefined(sel) = true;
    end
end
R.artifact_removed_pct(R.removed_undefined) = NaN;

% Units a reader can use without converting from decibels:
%   residual error as % of EEG amplitude (RMS): 100 * 10^(-SNR/20)
%   band power change in %:                     100 * (10^(dB/10) - 1)
R.resid_pct_before = 100 * 10.^(-R.snr_before_db / 20);
R.resid_pct_after  = 100 * 10.^(-R.snr_after_db  / 20);
for b = ["delta", "theta", "alpha", "beta", "gamma"]
    R.("pow_change_pct_" + b) = 100 * (10.^(R.("pow_err_db_" + b) / 10) - 1);
end
% Stroke measures as the error of the output, in % of the true value.
for m = ["dar", "dtabr", "bsi", "dasym"]
    if ismember(m + "_true", R.Properties.VariableNames)
        R.(m + "_err_pct") = 100 * (R.(m + "_out") - R.(m + "_true")) ./ abs(R.(m + "_true"));
    end
end
end

function R = stack(R, T)
% Vertical concatenation of tables with different columns: a column one
% side lacks is added to it, NaN for numbers and "" for text.
if isempty(R), R = T; return, end
R = add_missing(R, T);
T = add_missing(T, R);
% readtable reads a text column that happens to be empty in one run as
% numbers; such a column is text in both.
for v = R.Properties.VariableNames
    if ~strcmp(class(R.(v{1})), class(T.(v{1})))
        R.(v{1}) = string(R.(v{1})); T.(v{1}) = string(T.(v{1}));
    end
end
R = [R; T(:, R.Properties.VariableNames)];
end

function A = add_missing(A, B)
for v = setdiff(B.Properties.VariableNames, A.Properties.VariableNames)
    if isstring(B.(v{1})), A.(v{1}) = repmat("", height(A), 1);
    else,                  A.(v{1}) = NaN(height(A), 1);
    end
end
end

function T = summary_table(R, S)
% Median, min and max over seeds, per stroke stage, artifact and severity.
cols = {'artifact_removed_pct','resid_pct_before','resid_pct_after','r_median', ...
        'n_ic_flagged','nchan_rejected','bad_injected','bad_detected','good_rejected', ...
        'local_affected','local_rejected', ...
        'pow_change_pct_delta','pow_change_pct_theta','pow_change_pct_alpha', ...
        'pow_change_pct_beta','pow_change_pct_gamma', ...
        'dar_err_pct','dtabr_err_pct','bsi_err_pct','dasym_err_pct'};
cols = cols(ismember(cols, R.Properties.VariableNames));
rows = {};
for st = unique(R.stroke, 'stable')'
    for a = ["none", S.order, S.combos]
        for k = 1:numel(S.snr)
            if a == "none"
                if k > 1, break, end
                sel = R.stroke == st & R.artifact == a; amp = NaN;
            else
                sel = R.stroke == st & R.artifact == a & R.snr_target_db == S.snr(k);
                amp = S.amp(k);
            end
            if ~any(sel), continue, end
            r = struct('stroke', st, 'artifact', S.label(a), 'artifact_x_eeg', amp, ...
                       'n_seeds', sum(sel), 'n_failed', sum(R.status(sel) ~= "ok"));
            for c = cols
                v = R.(c{1})(sel); v = v(isfinite(v));
                if isempty(v), v = NaN; end
                r.([c{1} '_median']) = median(v);
                r.([c{1} '_min'])    = min(v);
                r.([c{1} '_max'])    = max(v);
            end
            rows{end+1} = r; %#ok<AGROW>
        end
    end
end
T = struct2table([rows{:}]);
end

%% ========================================================================
%  Figure 1: simulation
%  ========================================================================
function fig = fig_simulation(R, sim, cfg, S, runDirs)
fig = new_fig(S, S.width, 10.5);
tl  = tiledlayout(fig, 7, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% A: scalp maps, RMS of each artifact over time, scaled to its maximum
lf    = sim_leadfield(sim);
types = S.order(1:8);                             % scalp fields; electrode artifacts: fig 6
types = types(ismember(types, unique(R.artifact)));
tm    = tiledlayout(tl, 1, numel(types), 'TileSpacing', 'tight', 'Padding', 'tight');
tm.Layout.Tile = 1; tm.Layout.TileSpan = [2 1];
for i = 1:numel(types)
    art = sim_artifact(lf, sim, char(types(i)), 1100 + i);
    v   = sqrt(mean(art.data.^2, 2));
    ax  = nexttile(tm);
    axes(ax); %#ok<LAXES>  topoplot draws into the current axes
    evalc(['topoplot(v / max(v), lf.chanlocs, ''maplimits'', [0 1], ''electrodes'', ''on'', ' ...
           '''emarker'', {''.'', S.ink2, 3, 0.5}, ''whitebk'', ''on'', ''numcontour'', 0, ' ...
           '''colormap'', S.seq, ''hcolor'', S.ink2)']);
    colormap(ax, S.seq); clim(ax, [0 1]);
    title(ax, S.short(types(i)), 'FontSize', S.fs, 'FontWeight', 'normal', 'Color', S.ink);
    if i == 1, panel_letter(ax, 'a', S, [-0.3 1.1]); end
end
cb = colorbar(ax, 'FontSize', S.fs, 'Color', S.ink, 'Ticks', [0 1], 'TickLabels', {'0', 'Max'}, ...
              'LineWidth', S.lwAxis);
cb.Layout.Tile = 'east';
cb.Label.String = 'RMS'; cb.Label.FontSize = S.fs;

% B: example traces at 0 dB, first seed: ground truth, contaminated, cleaned
ex   = ["eog_blink", "emg_temporal", "ecg"];
ex   = ex(ismember(ex, types));
sev0 = lower(S.sev(S.snr == 0));
seed = min(R.seed);
tt = tiledlayout(tl, 1, numel(ex), 'TileSpacing', 'compact', 'Padding', 'tight');
tt.Layout.Tile = 3; tt.Layout.TileSpan = [5 1];
for i = 1:numel(ex)
    ax = nexttile(tt); style_ax(ax, S); hold(ax, 'on');
    [G, C, Y, lab, fs] = example_data(sprintf('s%02d_%s_%s', seed, ex(i), sev0), seed, runDirs, cfg);
    [~, ch] = max(var(C - G, 0, 2));
    [~, pk] = max(abs(C(ch,:) - G(ch,:)));
    w0 = min(max(1, pk - 2*fs), size(G,2) - 4*fs);          % a full 4 s window
    w  = w0 : w0 + 4*fs - 1;
    t  = (w - w0) / fs;
    plot(ax, t, G(ch,w), 'Color', S.grey, 'LineWidth', 3, 'DisplayName', 'Truth');
    plot(ax, t, C(ch,w), 'Color', S.col(2,:), 'LineWidth', 1, 'DisplayName', 'Contaminated');
    plot(ax, t, Y(ch,w), 'Color', S.col(1,:), 'LineWidth', 1.1, 'DisplayName', 'Cleaned');
    xlim(ax, [0 4]);
    rm = R.artifact_removed_pct(R.seed == seed & R.artifact == ex(i) & R.snr_target_db == 0);
    title(ax, sprintf('%s (%s), %.0f%% removed', S.short(ex(i)), lab{ch}, max(rm, 0)), ...
          'FontSize', S.fs, 'FontWeight', 'normal', 'Color', S.ink);
    xlabel(ax, 'Time (s)');
    if i == 1
        ylabel(ax, 'Amplitude (\muV)');
        lg = legend(ax, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', S.fs);
        lg.ItemTokenSize = [18 8];
        lg.Layout.Tile = 'south';                  % below the traces, clear of the data
        panel_letter(ax, 'b', S);
    end
end
end

function [G, C, Y, lab, fs] = example_data(name, seed, runDirs, cfg)
% Ground truth and contaminated input brought to the filter of the output,
% channels and reference, so the three traces are directly comparable.
d = runDirs(cellfun(@(r) isfile(fullfile(r, 'sim', [char(name) '.set'])), runDirs));
assert(~isempty(d), 'report_figures:noExample', 'No run contains %s.', name);
d = d{1};
[~, P]  = evalc('pop_loadset(''filename'', [char(name) ''_clean.set''], ''filepath'', fullfile(d, ''derivatives''))');
[~, Ci] = evalc('pop_loadset(''filename'', [char(name) ''.set''], ''filepath'', fullfile(d, ''sim''))');
[~, Gi] = evalc('pop_loadset(''filename'', sprintf(''s%02d.set'', seed), ''filepath'', fullfile(d, ''ground_truth''))');
[~, keep] = ismember({P.chanlocs.labels}, {Gi.chanlocs.labels});
fs  = Gi.srate;
G   = sim_match(Gi.data, fs, keep, cfg);
C   = sim_match(Ci.data, fs, keep, cfg);
Y   = double(P.data);
lab = {P.chanlocs.labels};
end

%% ========================================================================
%  Figure 2: suppression and preservation
%  ========================================================================
function fig = fig_performance(R, S, fams)
% Artifact removed, residual error and correlation, one column per family
% (artifact families, or the combined conditions for Figure 7).
rows = {'artifact_removed_pct', 'Artifact removed (%)'; ...
        'resid_pct_after',      'Residual error (% of EEG)'; ...
        'r_median',             'Correlation with truth (r)'};
fig  = new_fig(S, S.width, 16);
[tl, axAt] = family_grid(fig, fams, size(rows, 1), S, ...
                         {'--', 'No artifact'; ':', 'Before cleaning'});
for r = 1:size(rows, 1)
    for f = 1:numel(fams)
        ax = axAt(r, f);
        metric_panel(ax, R, fams(f).types, rows{r,1}, S, r ~= 1);
        if r == 2, before_lines(ax, R, fams(f).types, S); end
        if f == 1, ylabel(ax, rows{r,2}); panel_letter(ax, char('a' + r - 1), S); end
        if r < size(rows, 1), set(ax, 'XTickLabel', {}); end
    end
end
amp_xlabel(tl, S);
end

function before_lines(ax, R, types, S)
% Residual before cleaning, same colour as the series, dotted.
for i = 1:numel(types)
    [med, x] = medians(R(R.artifact == types(i), :), 'resid_pct_before', S, i, numel(types));
    plot(ax, x, med, ':', 'Color', S.col(i,:), 'LineWidth', 1.25, 'HandleVisibility', 'off');
end
end

function [tl, axAt] = family_grid(fig, fams, nRows, S, refKeys)
% One column per artifact family. The top row holds the family name and a
% legend, so no legend sits on the data; each metric row is three times
% taller than it. REFKEYS names the grey reference lines, once, in a key
% below the grid: {'--', 'No artifact'; ':', 'Before cleaning'}.
if nargin < 5, refKeys = cell(0, 2); end
nF = numel(fams);
tl = tiledlayout(fig, 1 + 3*nRows, nF, 'TileSpacing', 'compact', 'Padding', 'compact');
for f = 1:nF
    axL = nexttile(tl, f); hold(axL, 'on');
    for i = 1:numel(fams(f).types)
        plot(axL, NaN, NaN, '-', 'Color', S.col(i,:), 'LineWidth', S.lw, 'Marker', S.mk{i}, ...
             'MarkerSize', S.ms, 'MarkerFaceColor', S.col(i,:), 'MarkerEdgeColor', 'w', ...
             'DisplayName', S.legend(fams(f).types(i)));
    end
    lg = legend(axL, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', S.fs, ...
                'Location', 'south', 'TextColor', S.ink);
    lg.ItemTokenSize = [16 8];
    if numel(fams(f).types) > 3, lg.NumColumns = 2; end   % wrap long keys
    lg.Title.String = fams(f).name;          % the column heading, stacked above the keys
    lg.Title.FontSize = S.fs;
    lg.Title.FontWeight = 'bold';
    lg.Title.Color = S.ink;
    axL.Visible = 'off';
end
axAt = gobjects(nRows, nF);
for r = 1:nRows
    for f = 1:nF
        axAt(r, f) = nexttile(tl, (1 + 3*(r-1))*nF + f, [3 1]);
    end
end
if ~isempty(refKeys)
    ax = axAt(end, 1); hold(ax, 'on');
    h = gobjects(1, size(refKeys, 1));
    for k = 1:size(refKeys, 1)
        h(k) = plot(ax, NaN, NaN, refKeys{k,1}, 'Color', S.muted, 'LineWidth', 1.25, ...
                    'DisplayName', refKeys{k,2});
    end
    lg = legend(h, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', S.fs, 'TextColor', S.ink, ...
                'AutoUpdate', 'off');                % the data drawn later is not a key
    lg.ItemTokenSize = [22 8];
    lg.Layout.Tile = 'south';
end
end

%% ========================================================================
%  Figure 3: spectral preservation
%  ========================================================================
function fig = fig_spectral(R, sim, S)
bands = {sim.bands.name};
types = ["none", S.order(ismember(S.order, unique(R.artifact)))];
M = NaN(numel(types), numel(bands), numel(S.snr));
for a = 1:numel(types)
    for k = 1:numel(S.snr)
        sel = R.artifact == types(a);
        if types(a) ~= "none", sel = sel & R.snr_target_db == S.snr(k); end
        for b = 1:numel(bands)
            M(a,b,k) = mean(R.(['pow_change_pct_' bands{b}])(sel), 'omitnan');
        end
    end
end
L = max(10, ceil(prctile(abs(M(:)), 90) / 10) * 10);   % colour limit, %

fig = new_fig(S, S.width, 8.5);
tl  = tiledlayout(fig, 1, numel(S.snr), 'TileSpacing', 'compact', 'Padding', 'compact');
greek = {'\delta', '\theta', '\alpha', '\beta', '\gamma'};   % delta ... gamma
for k = 1:numel(S.snr)
    ax = nexttile(tl);
    h = imagesc(ax, M(:,:,k), [-L L]);
    h.AlphaData = ~isnan(M(:,:,k));             % no data: left blank, not coloured
    colormap(ax, S.div);
    hold(ax, 'on');
    for x = 1.5:numel(bands), xline(ax, x, 'Color', 'w', 'LineWidth', 2); end
    for y = 1.5:numel(types), yline(ax, y, 'Color', 'w', 'LineWidth', 2); end
    % Only cells beyond the colour limit get a number: their colour is clipped.
    [ri, ci] = find(abs(M(:,:,k)) > L);
    for j = 1:numel(ri)
        text(ax, ci(j), ri(j), sprintf('%.0f', M(ri(j),ci(j),k)), 'FontSize', 6, ...
             'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold');
    end
    set(ax, 'FontName', S.font, 'FontSize', S.fs, 'XColor', S.ink, 'YColor', S.ink, ...
        'TickLength', [0 0], 'Box', 'off', 'XTick', 1:numel(bands), ...
        'XTickLabel', greek(1:numel(bands)), 'TickLabelInterpreter', 'tex', ...
        'XTickLabelRotation', 0, 'YTick', 1:numel(types), 'XAxisLocation', 'top');
    if k == 1
        set(ax, 'YTickLabel', arrayfun(@(t) S.label(t), types, 'uni', 0));
    else
        set(ax, 'YTickLabel', {});
    end
    xlabel(ax, S.ampTicks{k}, 'FontWeight', 'bold');
end
amp_xlabel(tl, S);
cb = colorbar(ax, 'FontSize', S.fs, 'Color', S.ink, 'LineWidth', S.lwAxis);
cb.Layout.Tile = 'east';
cb.Label.String = 'Band power change (%)';
cb.Label.FontSize = S.fs;
end

%% ========================================================================
%  Figure 4: pipeline behaviour
%  ========================================================================
function fig = fig_pipeline(R, S)
fams = present_families(R, S);
rows = {'n_ic_flagged',   'ICs removed'; ...
        'nchan_rejected', 'Channels rejected'};
fig  = new_fig(S, S.width, 11);
[tl, axAt] = family_grid(fig, fams, size(rows, 1), S, {'--', 'No artifact'});
for r = 1:size(rows, 1)
    top = max(3, max(R.(rows{r,1})(ismember(R.artifact, [fams.types]))));
    for f = 1:numel(fams)
        ax = axAt(r, f);
        metric_panel(ax, R, fams(f).types, rows{r,1}, S, true);
        set(ax, 'YLim', [-0.3, top + 0.5], 'YTick', 0:max(1, ceil(top/6)):top);
        if f == 1, ylabel(ax, rows{r,2}); panel_letter(ax, char('a' + r - 1), S); end
        if r < size(rows, 1), set(ax, 'XTickLabel', {}); end
    end
end
amp_xlabel(tl, S);
end

%% ========================================================================
%  Figure 5: ICLabel threshold trade-off
%  ========================================================================
function fig = fig_iclabel(R, cfg, S, runDirs, outDir)
cache = fullfile(outDir, 'ic_components.mat');
if isfile(cache)
    load(cache, 'IC');
else
    IC = ic_components(R, cfg, runDirs);
    save(cache, 'IC');
end
% ICLabel class, the artifact family it should catch, and a short name
classes = {'Eye', 'eog', 'EOG'; 'Muscle', 'emg', 'EMG'; 'Heart', 'ecg', 'ECG'};
classes = classes(cellfun(@(f) any(startsWith(IC.artifact, f)), classes(:,2)), :);
th  = 0.30:0.05:0.80;
fig = new_fig(S, S.width, 7);
tl  = tiledlayout(fig, 1, size(classes, 1), 'TileSpacing', 'compact', 'Padding', 'compact');
for c = 1:size(classes, 1)
    removable = ismember(lower(classes{c,1}), lower(cfg.icaRemove));
    isArt  = IC.share >= 0.5 & startsWith(IC.artifact, classes{c,2});
    isFree = IC.share < 0.1;
    p      = IC.(lower(classes{c,1}));
    caught = arrayfun(@(t) sum(isArt  & p >= t), th);
    extra  = arrayfun(@(t) sum(isFree & p >= t), th);
    ax = nexttile(tl); style_ax(ax, S); hold(ax, 'on');
    plot(ax, th, caught, '-o', 'Color', S.col(1,:), 'LineWidth', S.lw, 'MarkerSize', S.ms, ...
         'MarkerFaceColor', S.col(1,:), 'MarkerEdgeColor', 'w', 'DisplayName', 'Artifact ICs');
    plot(ax, th, extra, '-s', 'Color', S.col(2,:), 'LineWidth', S.lw, 'MarkerSize', S.ms, ...
         'MarkerFaceColor', S.col(2,:), 'MarkerEdgeColor', 'w', 'DisplayName', 'Other ICs');
    top = max([caught extra 1]) * 1.12;
    if removable
        xline(ax, cfg.icaThresh, '--', 'Color', S.muted, 'LineWidth', 1, 'HandleVisibility', 'off');
        text(ax, cfg.icaThresh - 0.012, top, 'Current', 'FontSize', S.fs, ...
             'Color', S.ink2, 'VerticalAlignment', 'top');
    end
    set(ax, 'XDir', 'reverse', 'XLim', [th(1)-0.02 th(end)+0.02], 'XTick', 0.3:0.1:0.8);
    ylim(ax, [0 top]);
    xlabel(ax, 'ICLabel threshold');
    title(ax, sprintf('%s (%s)', classes{c,1}, classes{c,3}), 'FontWeight', 'bold');
    if c == 1, ylabel(ax, 'ICs removed'); end
    panel_letter(ax, char('a' + c - 1), S);
end
lg = legend(ax, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', S.fs);
lg.ItemTokenSize = [18 8];
lg.Layout.Tile = 'south';
end

%% ========================================================================
%  Figure 6: electrode artifacts
%  ========================================================================
function fig = fig_electrode(R, S)
% Drift and pops are added to the EEG like the other artifacts, so they are
% shown against amplitude. Bad channels replace the EEG, and their severity
% is the number of bad channels, so they get their own x-axis.
fig = new_fig(S, S.width, 12);
tl  = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'loose');
loc = ["drift", "pop"];
loc = loc(ismember(loc, R.artifact));

% a: residual error for drift and pops, before (dotted) and after
ax = nexttile(tl);
metric_panel(ax, R, loc, 'resid_pct_after', S, true);
before_lines(ax, R, loc, S);
ylabel(ax, 'Residual error (% of EEG)'); xlabel(ax, S.sevLabel);
legend(ax, 'Location', 'northwest', 'Box', 'off', 'FontSize', S.fs, 'AutoUpdate', 'off');
panel_letter(ax, 'a', S);

% b: share of the affected electrodes that the pipeline rejected
R.local_rej_pct = 100 * R.local_rejected ./ R.local_affected;
ax = nexttile(tl);
metric_panel(ax, R, loc, 'local_rej_pct', S, false);
set(ax, 'YLim', [-5 105]);
ylabel(ax, 'Affected electrodes rejected (%)'); xlabel(ax, S.sevLabel);
panel_letter(ax, 'b', S);

% c, d: bad channels against their number
B = R(R.artifact == "badchan", :);
[~, B.nbad] = ismember(B.snr_target_db, S.snr);
nb = 1:numel(S.snr);
ax = nexttile(tl); style_ax(ax, S); hold(ax, 'on');
plot(ax, [0.5 nb(end)+0.5], [0.5 nb(end)+0.5], '--', 'Color', S.muted, 'LineWidth', 1, ...
     'DisplayName', 'All detected');
series_by_count(ax, B, 'bad_detected', 1, 'Bad detected', S);
series_by_count(ax, B, 'good_rejected', 2, 'Good rejected', S);
stopped(ax, B, nb, S);
set(ax, 'XLim', [0.5 nb(end)+0.5], 'XTick', nb, 'YLim', [-0.3 nb(end)+0.8], 'YTick', 0:nb(end));
xlabel(ax, 'Bad channels injected'); ylabel(ax, 'Channels');
legend(ax, 'Location', 'northwest', 'Box', 'off', 'FontSize', S.fs, 'AutoUpdate', 'off');
panel_letter(ax, 'c', S);

ax = nexttile(tl); style_ax(ax, S); hold(ax, 'on');
series_by_count(ax, B, 'r_median', 1, '', S);
v = median(R.r_median(R.artifact == "none"), 'omitnan');
yline(ax, v, '--', 'Color', S.muted, 'LineWidth', 1);
stopped(ax, B, nb, S);
set(ax, 'XLim', [0.5 nb(end)+0.5], 'XTick', nb);
xlabel(ax, 'Bad channels injected'); ylabel(ax, 'Correlation with truth (r)');
panel_letter(ax, 'd', S);
end

function series_by_count(ax, B, col, i, name, S)
x = 1:numel(S.snr); med = NaN(size(x));
for k = x
    v = B.(col)(B.nbad == k & B.status == "ok");
    v = v(isfinite(v));
    if isempty(v), continue, end
    med(k) = median(v);
    scatter(ax, k + linspace(-0.04, 0.04, numel(v)), v, 14, S.col(i,:), 'filled', ...
            'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
end
h = plot(ax, x, med, '-', 'Color', S.col(i,:), 'LineWidth', S.lw, 'Marker', S.mk{i}, ...
         'MarkerSize', S.ms, 'MarkerFaceColor', S.col(i,:), 'MarkerEdgeColor', 'w');
if isempty(name), h.HandleVisibility = 'off'; else, h.DisplayName = name; end
end

function stopped(ax, B, nb, S)
% Mark the counts at which the pipeline stopped recordings.
for k = nb
    n = sum(B.nbad == k & B.status ~= "ok");
    if n == 0, continue, end
    text(ax, k, ax.YLim(2), sprintf('%d/%d\nstopped', n, sum(B.nbad == k)), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontSize', S.fs, 'Color', S.ink2);
end
end

%% ========================================================================
%  Figure 8: stroke measures
%  ========================================================================
function fig = fig_stroke(R, S)
% Error of each quantitative stroke measure, output against truth, in % of
% the true value. The dashed line is the uncontaminated recording: what
% preprocessing alone does to the measure.
meas = {'dar',   'DAR error (%)'; ...
        'dtabr', 'DTABR error (%)'; ...
        'bsi',   'pdBSI error (%)'; ...
        'dasym', 'Delta asymmetry error (%)'};
stages = intersect(["acute", "chronic"], unique(R.stroke), 'stable');
stages = stages(:)';
types  = S.order(ismember(S.order, R.artifact));
fams   = struct('name', cellstr(upper(extractBefore(stages, 2)) + extractAfter(stages, 1) + " stroke"), ...
                'types', repmat({types}, 1, numel(stages)));
fig = new_fig(S, S.width, 20);
[tl, axAt] = family_grid(fig, fams, size(meas, 1), S, {'--', 'No artifact'});
for m = 1:size(meas, 1)
    lim = [0 0];
    for f = 1:numel(stages)
        ax = axAt(m, f);
        metric_panel(ax, R(R.stroke == stages(f), :), types, [meas{m,1} '_err_pct'], S, true);
        yline(ax, 0, '-', 'Color', S.ink, 'LineWidth', 0.5, 'HandleVisibility', 'off');
        lim = [min(lim(1), ax.YLim(1)), max(lim(2), ax.YLim(2))];
        if f == 1, ylabel(ax, meas{m,2}); panel_letter(ax, char('a' + m - 1), S); end
        if m < size(meas, 1), set(ax, 'XTickLabel', {}); end
    end
    set(axAt(m, :), 'YLim', lim);                % same scale for acute and chronic
end
amp_xlabel(tl, S);
end

function IC = ic_components(R, cfg, runDirs)
% Every component the pipeline KEPT, with its Eye, Muscle and Heart probability
% and the share of its variance that is injected artifact:
%   share = var(W * artifact) / var(W * contaminated input)
% both brought to the filter, channels and reference of the output.
art = strings(0,1); share = []; eye = []; muscle = []; heart = [];
R = R(R.status == "ok", :);
for i = 1:height(R)
    name = sprintf('s%02d_%s', R.seed(i), R.dataset(i));
    d = char(R.run(i));
    [~, P]  = evalc('pop_loadset(''filename'', [name ''_clean.set''], ''filepath'', fullfile(d, ''derivatives''))');
    cls = P.etc.ic_classification.ICLabel;
    W   = P.icaweights * P.icasphere;
    if R.artifact(i) == "none"
        s = zeros(size(W, 1), 1);
    else
        [~, Ci] = evalc('pop_loadset(''filename'', [name ''.set''], ''filepath'', fullfile(d, ''sim''))');
        [~, Gi] = evalc('pop_loadset(''filename'', sprintf(''s%02d.set'', R.seed(i)), ''filepath'', fullfile(d, ''ground_truth''))');
        [~, keep] = ismember({P.chanlocs.labels}, {Gi.chanlocs.labels});
        G = sim_match(Gi.data, Gi.srate, keep, cfg);
        C = sim_match(Ci.data, Gi.srate, keep, cfg);
        ch = P.icachansind;
        s  = var(W * (C(ch,:) - G(ch,:)), 0, 2) ./ var(W * C(ch,:), 0, 2);
    end
    n = size(W, 1);
    art    = [art;    repmat(R.artifact(i), n, 1)]; %#ok<AGROW>
    share  = [share;  s]; %#ok<AGROW>
    eye    = [eye;    cls.classifications(:, strcmp(cls.classes, 'Eye'))]; %#ok<AGROW>
    muscle = [muscle; cls.classifications(:, strcmp(cls.classes, 'Muscle'))]; %#ok<AGROW>
    heart  = [heart;  cls.classifications(:, strcmp(cls.classes, 'Heart'))]; %#ok<AGROW>
end
IC = table(art, share, eye, muscle, heart, 'VariableNames', {'artifact','share','eye','muscle','heart'});
end

%% ========================================================================
%  Figures 9 and 10: previous against revised pipeline
%  ========================================================================
function fig = fig_revision(R0, R1, S, want, names)
% One column per condition rerun with the revised pipeline, healthy EEG.
% WANT lists the conditions to compare, NAMES the two versions in the key.
if nargin < 4, want = ["ecg", "eog_blink+ecg", "emg_temporal+ecg", "drift", "pop"]; end
if nargin < 5, names = ["Previous", "Revised"]; end
% Grey: previous pipeline; blue: revised. Dashed: the uncontaminated
% recording, per pipeline, in the same colour.
R0 = R0(R0.stroke == "none", :);  R1 = R1(R1.stroke == "none", :);
types = want(ismember(want, R0.artifact) & ismember(want, R1.artifact));
rows  = {'artifact_removed_pct', 'Artifact removed (%)'; ...
         'resid_pct_after',      'Residual error (% of EEG)'; ...
         'r_median',             'Correlation with truth (r)'};
fig = new_fig(S, S.width, 13);
tl  = tiledlayout(fig, size(rows, 1), numel(types), 'TileSpacing', 'compact', 'Padding', 'compact');
for r = 1:size(rows, 1)
    lim = [Inf -Inf]; axs = gobjects(1, numel(types));
    for c = 1:numel(types)
        ax = nexttile(tl);
        version_panel(ax, {R0, R1}, types(c), rows{r,1}, S, r ~= 1);
        if r == 1, title(ax, S.short(types(c)), 'FontWeight', 'bold'); end
        if c == 1, ylabel(ax, rows{r,2}); panel_letter(ax, char('a' + r - 1), S); end
        if r < size(rows, 1), set(ax, 'XTickLabel', {}); end
        lim = [min(lim(1), ax.YLim(1)), max(lim(2), ax.YLim(2))];
        axs(c) = ax;
    end
    set(axs, 'YLim', lim);                       % one scale per row
end
version_legend(ax, S, names);
amp_xlabel(tl, S);
end

function fig = fig_revision_stroke(R0, R1, S, type, names)
% Stroke measures with ECG, previous against revised pipeline.
if nargin < 4, type = "ecg"; end
if nargin < 5, names = ["Previous", "Revised"]; end
meas = {'dar',   'DAR error (%)'; ...
        'dtabr', 'DTABR error (%)'; ...
        'bsi',   'pdBSI error (%)'; ...
        'dasym', 'Delta asymmetry error (%)'};
Rs = {R0, R1};
stages = intersect(["acute", "chronic"], unique(R1.stroke), 'stable');
stages = stages(:)';
fig = new_fig(S, S.width * 0.6, 17);
tl  = tiledlayout(fig, size(meas, 1), numel(stages), 'TileSpacing', 'compact', 'Padding', 'compact');
for m = 1:size(meas, 1)
    lim = [Inf -Inf]; axs = gobjects(1, numel(stages));
    for f = 1:numel(stages)
        ax = nexttile(tl);
        sub = cellfun(@(T) T(T.stroke == stages(f), :), Rs, 'uni', 0);
        version_panel(ax, sub, type, [meas{m,1} '_err_pct'], S, true);
        yline(ax, 0, '-', 'Color', S.ink, 'LineWidth', 0.5, 'HandleVisibility', 'off');
        if m == 1
            title(ax, upper(extractBefore(stages(f), 2)) + extractAfter(stages(f), 1) + " stroke, " + S.short(type), ...
                  'FontWeight', 'bold');
        end
        if f == 1, ylabel(ax, meas{m,2}); panel_letter(ax, char('a' + m - 1), S); end
        if m < size(meas, 1), set(ax, 'XTickLabel', {}); end
        lim = [min(lim(1), ax.YLim(1)), max(lim(2), ax.YLim(2))];
        axs(f) = ax;
    end
    set(axs, 'YLim', lim);
end
version_legend(ax, S, names);
amp_xlabel(tl, S);
end

function version_panel(ax, Rs, type, col, S, withRef)
% One condition, one series per pipeline version: seeds as faint dots, the
% median as a line, and the uncontaminated recording as a dashed line.
style_ax(ax, S); hold(ax, 'on');
[colr, mk] = version_style(S);
for v = 1:numel(Rs)
    T = Rs{v};
    series(ax, T(T.artifact == type, :), col, S, v, numel(Rs), colr(v,:), mk{v});
    if withRef
        ref = median(T.(col)(T.artifact == "none"), 'omitnan');
        if isfinite(ref)
            yline(ax, ref, '--', 'Color', colr(v,:), 'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end
end
set(ax, 'XLim', [0.5 numel(S.snr) + 0.5], 'XTick', 1:numel(S.snr), ...
    'XTickLabel', S.ampTicks, 'XTickLabelRotation', 0);
end

function version_legend(ax, S, names)
% One key below the grid. The keys are drawn as empty lines in AX, and the
% legend is moved to the south tile of its layout.
[colr, mk] = version_style(S);
h = gobjects(1, 3);
for v = 1:2
    h(v) = plot(ax, NaN, NaN, '-', 'Color', colr(v,:), 'LineWidth', S.lw, 'Marker', mk{v}, ...
                'MarkerSize', S.ms, 'MarkerFaceColor', colr(v,:), 'MarkerEdgeColor', 'w', ...
                'DisplayName', names(v));
end
h(3) = plot(ax, NaN, NaN, '--', 'Color', S.muted, 'LineWidth', 1, 'DisplayName', 'No artifact');
lg = legend(h, 'Orientation', 'horizontal', 'Box', 'off', 'FontSize', S.fs, 'TextColor', S.ink, ...
            'AutoUpdate', 'off');
lg.ItemTokenSize = [22 8];
lg.Layout.Tile = 'south';
end

function [colr, mk] = version_style(S)
colr = [S.muted; S.col(1,:)];                % previous grey, revised blue
mk   = {'s', 'o'};
end

%% ========================================================================
%  Shared drawing
%  ========================================================================
function metric_panel(ax, R, types, col, S, withRef)
% Seeds as faint dots, the median across seeds as a line; series dodged
% sideways so their dots do not overlap.
style_ax(ax, S); hold(ax, 'on');
for i = 1:numel(types)
    h = series(ax, R(R.artifact == types(i), :), col, S, i, numel(types), S.col(i,:), S.mk{i});
    h.DisplayName = S.label(types(i));
end
if withRef                                   % named in the legend row
    v = median(R.(col)(R.artifact == "none"), 'omitnan');
    if isfinite(v)
        yline(ax, v, '--', 'Color', S.muted, 'LineWidth', 1, 'HandleVisibility', 'off');
    end
end
set(ax, 'XLim', [0.5 numel(S.snr) + 0.5], 'XTick', 1:numel(S.snr), ...
    'XTickLabel', S.ampTicks, 'XTickLabelRotation', 0);
end

function h = series(ax, T, col, S, i, n, colr, mk)
% Seeds as faint dots and the median as a line, dodged sideways as series I of N.
[med, x, pts] = medians(T, col, S, i, n);
for k = 1:numel(pts)
    if isempty(pts{k}), continue, end
    scatter(ax, x(k) + linspace(-0.035, 0.035, numel(pts{k})), pts{k}, 14, colr, ...
            'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
end
h = plot(ax, x, med, '-', 'Color', colr, 'LineWidth', S.lw, 'Marker', mk, ...
         'MarkerSize', S.ms, 'MarkerFaceColor', colr, 'MarkerEdgeColor', 'w');
end

function [med, x, pts] = medians(T, col, S, i, n)
x   = (1:numel(S.snr)) + ((i - (n+1)/2) * 0.16);
med = NaN(1, numel(S.snr));
pts = cell(1, numel(S.snr));
for k = 1:numel(S.snr)
    v = T.(col)(T.snr_target_db == S.snr(k));
    v = v(isfinite(v));
    pts{k} = v;
    if ~isempty(v), med(k) = median(v); end
end
end

function fams = present_families(R, S)
fams = S.families;
keep = arrayfun(@(f) any(ismember(f.types, unique(R.artifact))), fams);
fams = fams(keep);
for f = 1:numel(fams)
    fams(f).types = fams(f).types(ismember(fams(f).types, unique(R.artifact)));
end
end

function style_ax(ax, S)
% Open axes: no box, no grid, ticks outward.
set(ax, 'FontName', S.font, 'FontSize', S.fs, 'Color', 'w', ...
    'XColor', S.ink, 'YColor', S.ink, 'LineWidth', S.lwAxis, 'TickDir', 'out', ...
    'TickLength', [0.02 0.02], 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', ...
    'Layer', 'top');
ax.Title.Color = S.ink;
ax.Title.FontSize = S.fs;
ax.XLabel.FontSize = S.fs;
ax.YLabel.FontSize = S.fs;
end

function panel_letter(ax, letter, S, pos)
% Nature style: bold lowercase, 8 pt, top left.
if isempty(letter), return, end
if nargin < 4, pos = [-0.15 1.02]; end
text(ax, pos(1), pos(2), lower(letter), 'Units', 'normalized', 'FontName', S.font, ...
     'FontSize', S.fsLetter, 'FontWeight', 'bold', 'Color', S.ink, 'VerticalAlignment', 'bottom');
end

function amp_xlabel(tl, S)
% Shared x-axis label of a tiled layout: artifact amplitude.
xlabel(tl, S.sevLabel, 'FontSize', S.fs, 'Color', S.ink, 'FontName', S.font);
end

function fig = new_fig(S, w, h)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
             'Position', [1 1 w h], 'PaperUnits', 'centimeters', 'PaperSize', [w h]);
try fig.Theme = 'light'; catch, end
set(fig, 'DefaultAxesFontName', S.font, 'DefaultTextFontName', S.font, ...
         'DefaultLegendFontName', S.font, 'DefaultTextColor', S.ink, ...
         'DefaultAxesFontSize', S.fs, 'DefaultTextFontSize', S.fs);
end

function save_fig(fig, outDir, name, content)
exportgraphics(fig, fullfile(outDir, [name '.pdf']), 'ContentType', content, 'Resolution', 600);
exportgraphics(fig, fullfile(outDir, [name '.png']), 'Resolution', 600);
close(fig);
end

%% ========================================================================
%  Style
%  ========================================================================
function S = style(sim, present)
% Nature figure conventions: Arial, 5-7 pt text at final size (7 pt here,
% the maximum), 8 pt bold lowercase panel letters, 18.3 cm double column,
% open axes (no box, no grid) with ticks outward.
S.font  = 'Arial';
S.width = 18.3;                  % cm, double column
S.fs    = 7;                     % all text
S.fsLetter = 8;                  % panel letters
S.lw    = 1.75;                  % data lines
S.lwAxis = 0.75;                 % axes and ticks
S.ms    = 5.5;                   % markers
S.ink   = hex('#0b0b0b');        % text and axes
S.ink2  = hex('#52514e');        % secondary text
S.muted = hex('#898781');        % reference lines
S.grey  = hex('#c3c2b7');        % ground-truth trace
% Categorical slots 1-4 of the reference palette: blue, orange, aqua,
% yellow. The first three are validated for all pairs; the fourth only
% next to aqua, so it is used for lines (not scatter) and always with its
% own marker.
S.col = [hex('#2a78d6'); hex('#eb6834'); hex('#1baf7a'); hex('#eda100')];
S.mk  = {'o', 's', '^', 'd'};

% Sequential (single hue, light to dark) and diverging (blue - grey - red).
S.seq = ramp({'#cde2fb', '#86b6ef', '#3987e5', '#1c5cab', '#0d366b'}, 256);
S.div = ramp({'#104281', '#3987e5', '#f0efec', '#e34948', '#8f1f1f'}, 256);

[S.snr, o] = sort(sim.snrDb, 'descend');       % low severity first
S.sev = string(sim.severity(o));
S.sev = arrayfun(@(s) upper(extractBefore(s, 2)) + extractAfter(s, 1), S.sev);
S.amp = 10.^(-S.snr / 20);                     % artifact RMS / EEG RMS
S.ampTicks = cellstr(compose('%.1f×', S.amp));
S.sevLabel = 'Artifact amplitude (× EEG)';

S.order = ["eog_blink", "eog_vertical", "eog_horizontal", ...
           "emg_temporal", "emg_frontal", "emg_neck", "ecg", "line", ...
           "drift", "pop", "badchan"];
S.electrode = S.order(9:11);
S.families = struct( ...
    'name',  {'Ocular (EOG)', 'Muscle (EMG)', 'Cardiac and line noise'}, ...
    'types', {S.order(1:3), S.order(4:6), S.order(7:8)});
long  = ["No artifact", "Blink", "Vertical eye movement", "Horizontal eye movement", ...
         "Temporal/jaw EMG", "Frontal EMG", "Neck EMG", "ECG", "Line noise", ...
         "Electrode drift", "Electrode pops", "Bad channels"];
short = ["No artifact", "Blink", "Vertical EOG", "Horizontal EOG", "Temporal EMG", ...
         "Frontal EMG", "Neck EMG", "ECG", "Line noise", "Drift", "Pops", "Bad channels"];
leg   = ["No artifact", "Blink", "Vertical", "Horizontal", "Temporal/jaw", "Frontal", ...
         "Neck", "ECG", "Line noise", "Drift", "Pops", "Bad channels"];
% Combined conditions: their parts, joined, in the short form.
part = dictionary(["eog_blink", "eog_vertical", "eog_horizontal", "emg_temporal", ...
                   "emg_frontal", "emg_neck", "ecg", "line", "drift", "pop", "badchan"], ...
                  ["Blink", "VEOG", "HEOG", "EMG", "EMG", "EMG", "ECG", "Line", ...
                   "Drift", "Pops", "Bad ch."]);
keys = ["none", S.order];
combos = setdiff(string(present), keys, 'stable');
combos = combos(contains(combos, "+"));
for c = combos(:)'
    p = split(c, "+");
    if numel(p) > 4, lbl = "All artifacts"; else, lbl = strjoin(part(p), " + "); end
    keys = [keys, c]; long = [long, lbl]; short = [short, lbl]; leg = [leg, lbl]; %#ok<AGROW>
end
S.combos = combos(:)';
names = dictionary(keys, long);
shrt  = dictionary(keys, short);
lgd   = dictionary(keys, leg);
S.label  = @(a) names(string(a));
S.short  = @(a) shrt(string(a));
S.legend = @(a) lgd(string(a));     % inside a family column the family is already named
end

function c = hex(h)
c = sscanf(h(2:end), '%2x%2x%2x')' / 255;
end

function m = ramp(hexes, n)
% Colormap through the given anchors, interpolated in CIELAB so lightness
% changes evenly.
lab = cell2mat(cellfun(@(h) rgb2lab(hex(h)), hexes(:), 'uni', 0));
x   = linspace(0, 1, numel(hexes));
m   = lab2rgb(interp1(x, lab, linspace(0, 1, n)));
m   = min(max(m, 0), 1);
end

function sim = saved_sim(runDir)
% The settings saved with the run, on top of the current defaults: a run saved before a
% parameter existed still gets a value for it (for example the EMG ones,
% needed to draw example maps).
S   = load(fullfile(runDir, 'simulation.mat'), 'sim');
sim = sim_config();
for f = intersect(fieldnames(sim), fieldnames(S.sim))'
    sim.(f{1}) = S.sim.(f{1});
end
end
