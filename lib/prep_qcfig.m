function pngFile = prep_qcfig(EEG, pre, qc, outDir, base)
% PREP_QCFIG  One diagnostic figure per recording.
%
%   pngFile = prep_qcfig(EEG, pre, qc, outDir, base)
%
% EEG is the cleaned dataset, pre the snapshot from before filtering
% (prep_snapshot), qc the QC row. Each panel checks one step:
%
%   1  mean PSD before/after   high-pass, low-pass rolloff, and whether the
%                              mains peak is gone
%   2  per-channel PSD after   one odd channel that got past the bad-channel
%                              step, which the mean PSD hides
%   3  per-channel RMS         which channels were dropped, and whether what
%                              remains is uniform
%   4  component outcome       what ICLabel saw, and what it or a rule in
%                              prep_icrules cut

fig = prep_newfig(1400, 900);
cleanup = onCleanup(@() close(fig));

tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ttl = sprintf('%s   |   %d->%d chan, rank %d->%d, %d IC removed, line: %s', ...
    base, qc.nchan_raw, qc.nchan_final, qc.rank_before_ica, qc.rank_final, ...
    qc.n_ic_flagged, qc.line_method);
title(tl, ttl, 'Interpreter', 'none', 'FontWeight', 'bold');

%% Mean spectrum, Before vs After 
% One Welch pass serves both spectrum panels.
[fA, P] = prep_psd(EEG.data, EEG.srate);
pA = mean(P, 2);

ax = nexttile(tl);
hold(ax, 'on');
h = gobjects(0); names = {};
if ~isempty(pre) && isfield(pre, 'psd') && ~isempty(pre.psd)
    h(end+1) = plot(ax, pre.f, pre.psd, 'Color', [0.75 0.30 0.30], 'LineWidth', 1.2);
    names{end+1} = 'before';
end
h(end+1) = plot(ax, fA, pA, 'Color', [0.15 0.35 0.70], 'LineWidth', 1.4);
names{end+1} = 'after';
if isfield(pre, 'lineFreq') && ~isempty(pre.lineFreq)
    xline(ax, pre.lineFreq, ':', sprintf('%g Hz', pre.lineFreq), ...
          'Color', [0.4 0.4 0.4], 'LabelVerticalAlignment', 'bottom');
end
set(ax, 'XScale', 'log', 'YScale', 'log');
xlim(ax, [0.1 min(EEG.srate/2, 120)]);
xlabel(ax, 'Hz'); ylabel(ax, 'Power (\muV^2/Hz)');
title(ax, 'Mean PSD: before (red) vs after (blue)');
legend(ax, h, names, 'Location', 'best'); grid(ax, 'off');

%% Per-channel spectrum, After 
ax = nexttile(tl);
plot(ax, fA, P, 'LineWidth', 0.5);
set(ax, 'XScale', 'log', 'YScale', 'log');
xlim(ax, [0.1 min(EEG.srate/2, 120)]);
xlabel(ax, 'Hz'); ylabel(ax, 'Power (\muV^2/Hz)');
title(ax, sprintf('Per-channel PSD after (%d channels)', size(P,2)));
grid(ax, 'on');

%% Per-channel RMS
ax = nexttile(tl);
rms_after = channel_rms(EEG.data, EEG.nbchan);
bar(ax, rms_after, 'FaceColor', [0.15 0.35 0.70], 'EdgeColor', 'none');
set(ax, 'XTick', 1:EEG.nbchan, 'XTickLabel', {EEG.chanlocs.labels}, ...
        'XTickLabelRotation', 90, 'FontSize', 7);
ylabel(ax, '\muV RMS');
dropped = qc.chans_rejected;
nonEEG  = qc.chans_nonEEG;
title(ax, sprintf('Channel RMS, the ones kept   [dropped: %s]  [non-EEG: %s]', ...
      blank_if_empty(dropped), blank_if_empty(nonEEG)), 'Interpreter', 'none');
grid(ax, 'on');

%% ICLabel Outcome
ax = nexttile(tl);
plot_iclabel(ax, qc, pre);

pngFile = prep_savefig(fig, outDir, base, 'qc', 130);
end

%% Auxiliary functions
function r = channel_rms(X, nbchan)
% RMS per channel, in blocks, without a double copy of the recording.
D   = reshape(X, nbchan, []);
n   = size(D, 2);
acc = zeros(nbchan, 1);
for i0 = 1:200000:n
    blk = double(D(:, i0:min(i0 + 199999, n)));
    acc = acc + sum(blk.^2, 2);
end
r = sqrt(acc / max(n, 1));
end

function plot_iclabel(ax, qc, pre)
% Drawn from pre.ic, kept before the flagged components were subtracted.

if ~isstruct(pre) || isempty(pre) || ~isfield(pre, 'ic')
    text(ax, 0.5, 0.5, 'ICLabel not run', 'HorizontalAlignment', 'center');
    axis(ax, 'off'); return
end
ic = pre.ic;

s   = prep_ic_summary(ic);
pmax = s.pmax; winner = s.winner; nIC = s.nIC; flagged = s.flagged;

nCls  = numel(ic.classes);
cols  = lines(nCls);
h     = gobjects(1, nCls);
names = cell(1, nCls);
shown = false(1, nCls);

hold(ax, 'on');
for c = 1:nCls
    m = (winner == c)';
    if ~any(m), continue; end

    % open marker = kept, filled = removed
    kept = m & ~flagged;
    rem  = m &  flagged;
    if any(kept)
        plot(ax, find(kept), pmax(kept), 'o', 'Color', cols(c,:), ...
             'MarkerSize', 7, 'LineWidth', 1.2, 'LineStyle', 'none');
    end
    if any(rem)
        plot(ax, find(rem), pmax(rem), 'o', 'Color', cols(c,:), ...
             'MarkerFaceColor', cols(c,:), 'MarkerSize', 8, ...
             'LineWidth', 1.2, 'LineStyle', 'none');
    end

    % Legend key in one fixed (open) style: colour is the class, fill is removal.
    h(c)     = plot(ax, NaN, NaN, 'o', 'Color', cols(c,:), ...
                    'MarkerSize', 7, 'LineWidth', 1.2, 'LineStyle', 'none');
    names{c} = ic.classes{c};
    shown(c) = true;
end
h     = h(shown);
names = names(shown);

% One line per distinct threshold of the removable classes.
th = unique(s.thresh(s.removable));
for k = 1:numel(th)
    who = ic.classes(s.removable(s.thresh(s.removable) == th(k)));
    lbl = sprintf('threshold %.2f', th(k));
    if numel(th) > 1, lbl = sprintf('%s (%s)', lbl, strjoin(who, ', ')); end
    yline(ax, th(k), '--', lbl, 'Color', [0.35 0.35 0.35], ...
          'LabelHorizontalAlignment', 'left');
end

ylim(ax, [0 1]); xlim(ax, [0 nIC+1]);
xlabel(ax, 'component'); ylabel(ax, 'probability of the top class');
title(ax, sprintf('%d of %d components removed (filled)   |   classes ICLabel keeps: %s', ...
      qc.n_ic_flagged, nIC, strjoin(ic.classes(s.exempt), ', ')));
if ~isempty(h), legend(ax, h, names, 'Location', 'eastoutside', 'FontSize', 8); end
grid(ax, 'on');
end

function s = blank_if_empty(v)
s = char(string(v));
if isempty(s) || strcmp(s, ""), s = 'none'; end
end
