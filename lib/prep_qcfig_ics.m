function pngFile = prep_qcfig_ics(pre, outDir, base, margin)
% PREP_QCFIG_ICS  Scalp maps of the components the pipeline acted on.
%
%   pngFile = prep_qcfig_ics(pre, outDir, base, margin)
%
% The scatter panel in the main QC figure says whether the threshold rule
% fired. This says whether it was right: an eye component is frontal and
% bilateral, channel noise is a bullseye on one electrode, muscle is focal
% and at the rim, brain is smooth and dipolar. ICLabel is good but not
% always right, and a scalp map is how you check.
%
% Two groups, which are the decisions worth reviewing:
%   removed        red title    subtracted from the data
%   near-miss      grey title   kept, but within MARGIN of the threshold
%
% MARGIN defaults to 0.10, and prep_subject passes cfg.qcIcsMargin. Set it
% to 0 to show the removed components only.
%
% Returns '' when there is nothing to draw.

if nargin < 4 || isempty(margin), margin = 0.10; end
pngFile = '';

if ~isstruct(pre) || isempty(pre) || ~isfield(pre, 'ic') || ...
   ~isfield(pre.ic, 'winv') || isempty(pre.ic.winv)
    return
end
ic = pre.ic;

s    = prep_ic_summary(ic);
P    = s.probs;
pmax = s.pmax; winner = s.winner; flagged = s.flagged;

% Removable classes only, as prep_subject resolved them from cfg.icaRemove.
% The exempt classes carry NaN rows in pop_icflag, so a near-miss among them
% was never a decision.
removable = s.removable;
isRemovableClass = ismember(winner(:)', removable);
nearMiss = ~flagged & isRemovableClass & ...
           (max(P(:, removable), [], 2)' >= ic.thresh - margin);

show = find(flagged | nearMiss);
if isempty(show), return; end

% The channels the ICA actually ran on.
locs = ic.chanlocs;
if isfield(ic, 'chansind') && ~isempty(ic.chansind)
    locs = locs(ic.chansind);
end

n    = numel(show);
ncol = min(6, n);
nrow = ceil(n / ncol);

% Minimum width: with one or two components the tiles alone are narrower
% than the title, which then gets clipped at both ends.
figW = max(220*ncol + 120, 760);
fig = prep_newfig(figW, 240*nrow + 140);
cleanup = onCleanup(@() close(fig));

tl = tiledlayout(fig, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');
% Two lines, so a narrow sheet does not clip the title at both ends.
title(tl, {base, sprintf('%d removed, %d near-threshold kept   |   threshold %.2f', ...
      sum(flagged), sum(nearMiss), ic.thresh)}, ...
      'Interpreter', 'none', 'FontWeight', 'bold');

for k = 1:n
    c  = show(k);
    ax = nexttile(tl);
    try
        % topoplot draws into the current axes and accepts no handle, so
        % the per-tile axes() call is required.
        axes(ax); %#ok<LAXES>
        % 'both' is topoplot's own default: colour map plus contour lines. The
        % lines make the gradient readable, which is most of how a scalp map
        % is judged. A dipolar brain component has two smooth poles; a channel
        % noise component is rings tight around one electrode.
        topoplot(ic.winv(:, c), locs, 'electrodes', 'on', 'style', 'both', ...
                 'numcontour', 6, 'shading', 'interp', 'conv', 'on');
    catch ME
        text(ax, 0.5, 0.5, sprintf('topoplot failed:\n%s', ME.message), ...
             'HorizontalAlignment', 'center', 'FontSize', 7);
        axis(ax, 'off');
    end
    if flagged(c), col = [0.75 0.15 0.15]; tag = 'REMOVED';
    else,          col = [0.35 0.35 0.35]; tag = 'kept';
    end
    title(ax, sprintf('IC%d  %s  %.2f\n%s', c, ic.classes{winner(c)}, pmax(c), tag), ...
          'Color', col, 'FontSize', 9);
end

pngFile = prep_savefig(fig, outDir, base, 'qc_ics', 300);
end
