function src_figure(outDir, atlas, montage)
% SRC_FIGURE  Summary figure of a run_src_validation result folder.
%
%   src_figure(outDir)                     panels b and c for 62 channels, DKT 62
%   src_figure(outDir, 'coarse20', 'm32')  another reference configuration
%
% Reads metrics.csv and distance.csv and writes summary.png and summary.pdf.
% Rows: dense and sparse source activity. Columns:
%   a  false positives: triplets with true O = 0 flagged by the bootstrap
%   b  target triplet, estimated against true O (reference configuration)
%   c  O under the null against mean parcel distance (reference configuration)
% Colour is the inverse method; filled or solid is the template head,
% open or dashed the matched head (upper bound).

if nargin < 2, atlas = "dkt62"; montage = "m62"; end
R = readtable(fullfile(outDir, 'metrics.csv'), 'TextType', 'string');
D = readtable(fullfile(outDir, 'distance.csv'), 'TextType', 'string');
col  = struct('eloreta', [42 120 214]/255, 'lcmv', [235 104 52]/255);
name = struct('eloreta', 'eLORETA', 'lcmv', 'LCMV');
heads = ["template", "matched"];
meths = ["eloreta", "lcmv"];
dens  = ["dense", "sparse"];
conds = ["red_near", "red_far", "syn_near", "syn_far"];
ref   = R.montage == montage & R.atlas == atlas;

f = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 18 11], 'Color', 'w');
try, f.Theme = 'light'; catch, end   % R2025 figures follow the desktop theme
set(f, 'DefaultAxesFontName', 'Arial', 'DefaultAxesFontSize', 7, 'DefaultTextFontName', 'Arial', ...
       'DefaultAxesBox', 'off', 'DefaultLineLineWidth', 1.5, 'DefaultAxesTickDir', 'out', ...
       'DefaultAxesLineWidth', 0.75);
tl = tiledlayout(f, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

for di = 1:2
    d = R.density == dens(di);

    %% a: false positives
    ax = nexttile(tl); hold(ax, 'on');
    cfgs = unique(R.atlas + " " + R.montage, 'stable')';
    w = 0.18; k = 0;
    for me = meths
        for hd = heads
            k = k + 1;
            v = arrayfun(@(c) 100 * mean(R.fpr(d & R.atlas + " " + R.montage == c & ...
                                               R.method == me & R.head == hd)), cfgs);
            face = col.(me); if hd == "matched", face = 'w'; end
            bar(ax, (1:numel(cfgs)) + (k - 2.5) * w, v, w * 0.85, 'FaceColor', face, ...
                'EdgeColor', col.(me), 'LineWidth', 0.75, ...
                'DisplayName', sprintf('%s, %s', name.(me), hd));
        end
    end
    vo = arrayfun(@(c) 100 * mean(R.fpr(d & R.atlas + " " + R.montage == c & R.head == "oracle")), cfgs);
    plot(ax, 1:numel(cfgs), vo, 'k_', 'MarkerSize', 8, 'LineWidth', 1, 'DisplayName', 'True sources');
    set(ax, 'XTick', 1:numel(cfgs), 'XTickLabel', cfg_label(cfgs), 'YLim', [0 100]);
    ylabel(ax, 'Independent triplets flagged (%)');
    title(ax, sprintf('%s activity', capital(dens(di))), 'FontWeight', 'normal', 'FontSize', 7);
    if di == 1, legend(ax, 'Box', 'off', 'Location', 'southoutside', 'NumColumns', 2); end

    %% b: target triplet
    ax = nexttile(tl); hold(ax, 'on');
    for ci = 1:numel(conds)
        s = ref & d & R.condition == conds(ci);
        ot = mean(R.O_true(s & R.head == "oracle"));
        plot(ax, ci + [-0.4 0.4], [ot ot], 'k-', 'LineWidth', 1);
        k = 0;
        for me = meths
            for hd = heads
                k = k + 1;
                o = R.O_est(s & R.method == me & R.head == hd);
                face = col.(me); if hd == "matched", face = 'w'; end
                errorbar(ax, ci + (k - 2.5) * 0.16, mean(o), std(o), 'o', 'Color', col.(me), ...
                         'MarkerFaceColor', face, 'MarkerSize', 4, 'LineWidth', 0.75, 'CapSize', 0);
            end
        end
    end
    yline(ax, 0, ':', 'LineWidth', 0.75);
    yl = ylim(ax); ylim(ax, [min(yl(1), -0.7), max(yl(2), 0.6)]);
    set(ax, 'XTick', 1:numel(conds), 'XTickLabel', ["Red. near", "Red. far", "Syn. near", "Syn. far"], ...
        'XLim', [0.4 numel(conds) + 0.6]);
    ylabel(ax, 'O-information (nats)');
    title(ax, 'Target triplet (black: true)', 'FontWeight', 'normal', 'FontSize', 7);

    %% c: null against distance
    ax = nexttile(tl); hold(ax, 'on');
    dd = D.density == dens(di) & D.montage == montage & D.atlas == atlas;
    for me = meths
        for hd = heads
            s = dd & D.method == me & D.head == hd;
            if ~any(s), continue; end
            [g, x] = findgroups(D.dist_mm(s));
            ls = '-'; if hd == "matched", ls = '--'; end
            plot(ax, x, splitapply(@mean, D.O_mean(s), g), ls, 'Color', col.(me));
        end
    end
    yline(ax, 0, ':', 'LineWidth', 0.75);
    xlabel(ax, 'Mean distance between parcels (mm)');
    ylabel(ax, 'Mean O, independent sources (nats)');
    title(ax, 'Leakage under the null', 'FontWeight', 'normal', 'FontSize', 7);
end

exportgraphics(f, fullfile(outDir, 'summary.png'), 'Resolution', 300);
exportgraphics(f, fullfile(outDir, 'summary.pdf'), 'ContentType', 'vector');
close(f);
end

function s = cfg_label(cfgs)
s = replace(cfgs, ["dkt62 ", "coarse20 ", "m32", "m62"], ["62 par, ", "20 par, ", "32 ch", "62 ch"]);
end

function s = capital(s)
s = upper(extractBefore(s, 2)) + extractAfter(s, 1);
end
