function pngFile = prep_qcfig(EEG, pre, qc, outDir, base)
% PREP_QCFIG  One diagnostic figure per recording.
%
%   pngFile = prep_qcfig(EEG, pre, qc, outDir, base)
%
% EEG   the cleaned dataset
% pre   snapshot taken before filtering (see prep_snapshot)
% qc    the QC row, for the annotations
%
% A QC number says a step ran. A spectrum says whether it was right. Each
% panel can only look correct if one particular step worked:
%
%   1  mean PSD before/after   high-pass, low-pass rolloff, and whether the
%                              mains peak is gone
%   2  per-channel PSD after   one odd channel that got past the bad-channel
%                              step, which the mean PSD hides
%   3  per-channel RMS         which channels were dropped, and whether what
%                              remains is uniform
%   4  ICLabel outcome         what the classifier saw and what was cut
%
% Rendered off-screen, so this works under -batch and on a cluster node.

fig = prep_newfig(1400, 900);
cleanup = onCleanup(@() close(fig));

tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ttl = sprintf('%s   |   %d->%d chan, rank %d->%d, %d IC removed, line: %s', ...
    base, qc.nchan_raw, qc.nchan_final, qc.rank_before_ica, qc.rank_final, ...
    qc.n_ic_flagged, qc.line_method);
title(tl, ttl, 'Interpreter', 'none', 'FontWeight', 'bold');

%% Mean spectrum, Before vs After 
% One Welch pass serves both spectrum panels. The mean is the per-channel
% result averaged, so computing it separately would run the same transform
% over the same samples twice. prep_psd caps how much of the recording it
% reads and converts only that much to double.
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
set(ax, 'XScale', 'log');
xlim(ax, [0.1 min(EEG.srate/2, 120)]);
xlabel(ax, 'Hz'); ylabel(ax, 'dB');
title(ax, 'Mean PSD: before (red) vs after (blue)');
legend(ax, h, names, 'Location', 'best'); grid(ax, 'off');

%% Per-channel spectrum, After 
ax = nexttile(tl);
plot(ax, fA, P, 'LineWidth', 0.5);
set(ax, 'XScale', 'log');
xlim(ax, [0.1 min(EEG.srate/2, 120)]);
xlabel(ax, 'Hz'); ylabel(ax, 'dB');
title(ax, sprintf('Per-channel PSD after (%d channels)', size(P,2)));
grid(ax, 'on');

%% Per-channel RMS
ax = nexttile(tl);
% Flattened, so this works on epoched data too. RMS involves no windowing,
% so concatenating the epochs costs nothing here. The spectra above are
% different: prep_psd averages those per epoch.
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
% RMS per channel, accumulated over blocks of columns. Converting a whole
% recording to double allocates several gigabytes on a long file, and
% squaring it allocates as much again, to end up with nbchan numbers.
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
% Everything drawn here is what ICLabel decided BEFORE the flagged
% components were subtracted, which prep_subject kept in pre.ic. It cannot
% be read back off EEG afterwards: pop_subcomp trims etc.ic_classification
% to the components that survived, so the removed ones are simply gone.

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

    % The key is drawn once per class, in one fixed style, off the visible
    % axes. Colour identifies the class and fill identifies what was
    % removed, and those are separate questions. Taking the key from
    % whichever of the two plots above happened to run last made the swatch
    % filled for any class holding a single removed component, which reads
    % as the whole class having been removed.
    h(c)     = plot(ax, NaN, NaN, 'o', 'Color', cols(c,:), ...
                    'MarkerSize', 7, 'LineWidth', 1.2, 'LineStyle', 'none');
    names{c} = ic.classes{c};
    shown(c) = true;
end
h     = h(shown);
names = names(shown);

yline(ax, ic.thresh, '--', sprintf('threshold %.2f', ic.thresh), ...
      'Color', [0.35 0.35 0.35], 'LabelHorizontalAlignment', 'left');

ylim(ax, [0 1]); xlim(ax, [0 nIC+1]);
xlabel(ax, 'component'); ylabel(ax, 'probability of the top class');
% The exempt classes are named from the class list this run actually used,
% not from the default cfg.icaRemove. Stating the default here would print a
% sheet that contradicts its own markers whenever a study changes the list.
title(ax, sprintf('ICLabel: %d of %d removed (filled)   |   never removed: %s', ...
      qc.n_ic_flagged, nIC, strjoin(ic.classes(s.exempt), ', ')));
if ~isempty(h), legend(ax, h, names, 'Location', 'eastoutside', 'FontSize', 8); end
grid(ax, 'on');
end

function s = blank_if_empty(v)
s = char(string(v));
if isempty(s) || strcmp(s, ""), s = 'none'; end
end
