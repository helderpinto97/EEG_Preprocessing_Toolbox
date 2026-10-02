function pngFile = prep_qcfig_ics(pre, outDir, base, margin)
% PREP_QCFIG_ICS  Removed components and near-misses: map, time course, spectrum.
%
%   pngFile = prep_qcfig_ics(pre, outDir, base, margin)
%
% Near-misses are kept components of a removable class within MARGIN
% (default 0.10) of its threshold. Eye is frontal, channel noise sits on one
% electrode, muscle is focal at the rim and has power rising above 20 Hz,
% heartbeats and pops show in the time course, brain is smooth and dipolar
% with an alpha peak. Without pre.ic.act only the maps are drawn. Returns ''
% when there is nothing to draw.

if nargin < 4 || isempty(margin), margin = 0.10; end
pngFile = '';
if ~isstruct(pre) || isempty(pre) || ~isfield(pre, 'ic') || ...
   ~isfield(pre.ic, 'winv') || isempty(pre.ic.winv)
    return
end
ic = pre.ic;
s  = prep_ic_summary(ic);

nearMiss = ~s.flagged & ismember(s.winner(:)', s.removable) & ...
           any(s.probs(:, s.removable) >= s.thresh(s.removable) - margin, 2)';
show = find(s.flagged | nearMiss);
if isempty(show), return, end

locs = ic.chanlocs;                        % the channels ICA ran on
if isfield(ic, 'chansind') && ~isempty(ic.chansind), locs = locs(ic.chansind); end
act = [];
if isfield(ic, 'act') && ~isempty(ic.act), act = ic.act; end

% Maps only: up to 6 per row. With activity: one component per row, as
% map (2 tiles), time course (4) and spectrum (2).
n = numel(show);
if isempty(act)
    ncol = min(6, n); nrow = ceil(n / ncol);
    fig  = prep_newfig(max(220*ncol + 120, 760), 240*nrow + 140);
else
    ncol = 8; nrow = n;
    fig  = prep_newfig(1600, 230*nrow + 120);
end
cleanup = onCleanup(@() close(fig));
tl = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, {base, sprintf('%d removed, %d near-threshold kept   |   threshold %s', ...
      sum(s.flagged), sum(nearMiss), s.threshText)}, 'Interpreter', 'none', 'FontWeight', 'bold');

for i = 1:n
    c = show(i);
    if isempty(act)
        ax = nexttile(tl);
    else
        first = ncol*(i - 1) + 1;
        ax = nexttile(tl, first, [1 2]);
    end
    try
        axes(ax); %#ok<LAXES> topoplot takes no axes handle
        topoplot(ic.winv(:, c), locs, 'electrodes', 'on', 'style', 'both', ...
                 'numcontour', 6, 'shading', 'interp', 'conv', 'on');
    catch ME
        text(ax, 0.5, 0.5, sprintf('topoplot failed:\n%s', ME.message), ...
             'HorizontalAlignment', 'center', 'FontSize', 7);
        axis(ax, 'off');
    end
    % Named by the rule that removed it, else by its ICLabel class.
    why = sprintf('%s  %.2f', ic.classes{s.winner(c)}, s.pmax(c));
    if strlength(s.reason(c)) > 0, why = char(s.reason(c)); end
    if s.flagged(c), col = [0.75 0.15 0.15]; tag = 'REMOVED'; else, col = [0.35 0.35 0.35]; tag = 'kept'; end
    title(ax, sprintf('IC%d  %s\n%s', c, why, tag), 'Color', col, 'FontSize', 9);

    if isempty(act), continue, end
    ax = nexttile(tl, first + 2, [1 4]);
    t  = act.t0 + (0:size(act.trace, 2) - 1) / act.srate;
    plot(ax, t, act.trace(c, :), 'Color', col, 'LineWidth', 0.5);
    axis(ax, 'tight'); box(ax, 'off'); ax.YTick = []; ax.FontSize = 7;
    xlabel(ax, 'Time (s)');

    ax = nexttile(tl, first + 6, [1 2]);
    plot(ax, act.f, act.psd(:, c), 'Color', col, 'LineWidth', 1);
    xlim(ax, [act.f(1) act.f(end)]); box(ax, 'off'); ax.FontSize = 7;
    ax.YScale = 'log';                     % 1/f would hide the high band
    xlabel(ax, 'Frequency (Hz)'); ylabel(ax, 'Power (a.u.)');
end
pngFile = prep_savefig(fig, outDir, base, 'qc_ics', 300 - 100*~isempty(act));
end
