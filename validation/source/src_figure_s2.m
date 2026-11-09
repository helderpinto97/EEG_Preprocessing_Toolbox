function src_figure_s2(outDir, outBase)
% SRC_FIGURE_S2  Summary figure of a run_src_stage2 result folder.
%
%   src_figure_s2(outDir)
%   src_figure_s2(outDir, outBase)     write outBase.png and outBase.pdf instead
%
% Reads metrics.csv and writes summary.png and summary.pdf.
% Rows: dense and sparse source activity. Columns:
%   a  false positives: triplets with true O = 0 flagged by the bootstrap
%   b  target triplet, estimated against true O, per data variant
%   c  recovery: lowest correlation between a triplet parcel and its true
%      signal (0.5-45 Hz)
% Colour is the inverse method. Variants: clean or with artifacts, without
% (open) or with (filled) the preprocessing pipeline. Means over seeds.

if nargin < 2, outBase = fullfile(outDir, 'summary'); end
R = readtable(fullfile(outDir, 'metrics.csv'), 'TextType', 'string');
col  = struct('eloreta', [42 120 214]/255, 'lcmv', [235 104 52]/255, 'champagne', [0 158 115]/255);
name = struct('eloreta', 'eLORETA', 'lcmv', 'LCMV', 'champagne', 'Champagne');
meths = intersect(["eloreta", "lcmv", "champagne"], unique(R.method), 'stable')';
nm = numel(meths);
dens  = intersect(["dense", "sparse"], unique(R.density), 'stable');
conds = intersect(["red_near", "red_far", "syn_near", "syn_far"], unique(R.condition), 'stable');
vars  = ["raw", "clean_pipe", "art_raw", "art_pipe"];
vlab  = ["Clean", "Clean + pipeline", "Artifacts", "Artifacts + pipeline"];
mk    = ["o", "o", "s", "s"];                 % circle clean, square artifacts
piped = [false, true, false, true];           % filled = pipeline
clab  = replace(conds, ["red_", "syn_", "near", "far"], ["Red. ", "Syn. ", "near", "far"]);

f = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 18 5.5 * numel(dens) + 1.5], 'Color', 'w');
try, f.Theme = 'light'; catch, end   % R2025 figures follow the desktop theme
set(f, 'DefaultAxesFontName', 'Arial', 'DefaultAxesFontSize', 7, 'DefaultTextFontName', 'Arial', ...
       'DefaultAxesBox', 'off', 'DefaultLineLineWidth', 1.5, 'DefaultAxesTickDir', 'out', ...
       'DefaultAxesLineWidth', 0.75);
tl = tiledlayout(f, numel(dens), 3, 'TileSpacing', 'compact', 'Padding', 'compact');

for di = 1:numel(dens)
    d = R.density == dens(di);

    %% a: false positives per variant
    ax = nexttile(tl); hold(ax, 'on');
    eff = ismember('fpr_eff', R.Properties.VariableNames);
    w = 0.72 / nm; if eff, w = 0.4 / nm; end
    for mi = 1:nm
        me = meths(mi);
        v = arrayfun(@(x) 100 * mean(R.fpr(d & R.variant == x & R.method == me)), vars);
        x0 = (1:numel(vars)) + (mi - (nm + 1) / 2) * w * (1 + eff);
        bar(ax, x0 - eff * w / 2, v, w * 0.85, 'FaceColor', col.(me), ...
            'EdgeColor', 'none', 'DisplayName', name.(me));
        if eff   % open bars: |O| above s2.effMin, effect size rather than significance
            v = arrayfun(@(x) 100 * mean(R.fpr_eff(d & R.variant == x & R.method == me)), vars);
            bar(ax, x0 + w / 2, v, w * 0.85, 'FaceColor', 'w', 'EdgeColor', col.(me), ...
                'LineWidth', 0.75, 'DisplayName', name.(me) + ", |O| > 0.05");
        end
    end
    vo = 100 * mean(R.fpr(d & R.variant == "oracle"));
    yline(ax, vo, 'k-', 'LineWidth', 0.75, 'DisplayName', 'True sources');
    set(ax, 'XTick', 1:numel(vars), 'XTickLabel', vlab, 'XTickLabelRotation', 30, 'YLim', [0 100]);
    ylabel(ax, 'Independent triplets flagged (%)');
    title(ax, sprintf('%s activity: false positives', capital(dens(di))), 'FontWeight', 'normal', 'FontSize', 7);
    if di == 1, legend(ax, 'Box', 'off', 'Location', 'northoutside', 'NumColumns', 2); end

    %% b: target triplet
    ax = nexttile(tl); hold(ax, 'on');
    for ci = 1:numel(conds)
        s = d & R.condition == conds(ci);
        ot = mean(R.O_true(s & R.variant == "oracle"));
        plot(ax, ci + [-0.42 0.42], [ot ot], 'k-', 'LineWidth', 1);
        k = 0;
        for me = meths
            for vi = 1:numel(vars)
                k = k + 1;
                o = mean(R.O_est(s & R.method == me & R.variant == vars(vi)));
                face = 'w'; if piped(vi), face = col.(me); end
                plot(ax, ci + (k - (nm * numel(vars) + 1) / 2) * 0.72 / (nm * numel(vars)), o, mk(vi), 'Color', col.(me), ...
                     'MarkerFaceColor', face, 'MarkerSize', 4, 'LineWidth', 0.75);
            end
        end
    end
    yline(ax, 0, ':', 'LineWidth', 0.75);
    yl = ylim(ax); ylim(ax, [min(yl(1), -0.7), max(yl(2), 0.6)]);
    set(ax, 'XTick', 1:numel(conds), 'XTickLabel', clab, 'XLim', [0.4 numel(conds) + 0.6]);
    ylabel(ax, 'O-information (nats)');
    title(ax, 'Target triplet (black: true)', 'FontWeight', 'normal', 'FontSize', 7);
    if di == 1   % marker key
        h = gobjects(1, numel(vars));
        for vi = 1:numel(vars)
            face = 'w'; if piped(vi), face = [0.4 0.4 0.4]; end
            h(vi) = plot(ax, NaN, NaN, mk(vi), 'Color', [0.4 0.4 0.4], 'MarkerFaceColor', face, ...
                         'MarkerSize', 4, 'LineWidth', 0.75, 'DisplayName', vlab(vi));
        end
        legend(ax, h, 'Box', 'off', 'Location', 'northoutside', 'NumColumns', 2);
    end

    %% c: recovery of the triplet signals
    ax = nexttile(tl); hold(ax, 'on');
    sc = d & R.condition ~= "null";
    for mi = 1:nm
        me = meths(mi);
        v = arrayfun(@(x) mean(R.r_own_trip_min(sc & R.variant == x & R.method == me)), vars);
        bar(ax, (1:numel(vars)) + (mi - (nm + 1) / 2) * w, v, w * 0.85, 'FaceColor', col.(me), 'EdgeColor', 'none');
    end
    set(ax, 'XTick', 1:numel(vars), 'XTickLabel', vlab, 'XTickLabelRotation', 30, 'YLim', [0 1]);
    ylabel(ax, 'Weakest triplet parcel, |r| with truth');
    title(ax, 'Recovery of the triplet signals', 'FontWeight', 'normal', 'FontSize', 7);
end

exportgraphics(f, [outBase '.png'], 'Resolution', 300);
exportgraphics(f, [outBase '.pdf'], 'ContentType', 'vector');
close(f);
end

function s = capital(s)
s = upper(extractBefore(s, 2)) + extractAfter(s, 1);
end
