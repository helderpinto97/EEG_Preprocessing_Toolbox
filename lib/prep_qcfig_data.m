function pngFile = prep_qcfig_data(EEG, pre, outDir, base)
% PREP_QCFIG_DATA  The traces themselves, every channel, before and after.
%
%   pngFile = prep_qcfig_data(EEG, pre, outDir, base)
%
% Spectra and summary statistics can look fine while the data is visibly
% wrong: a channel railing, a drift the high-pass missed, an amplifier
% saturation, a step where a segment was spliced.
%
% Both panels share one amplitude scale and one time window, so they are
% comparable instead of each auto-scaled. Channels are matched by label,
% since the after set has had bad channels removed.
%
% Event markers come from pre.events, which prep_snapshot captured in the
% same clock as the snippet.
%
% Returns '' when there is no segment to draw.

pngFile = '';
if ~isstruct(pre) || isempty(pre) || ~isfield(pre, 'snippet') || isempty(pre.snippet)
    return
end

srate = EEG.srate;
labAfter  = {EEG.chanlocs.labels};
labBefore = pre.labels;

% Same window, same channels, in the order the cleaned data has them.
% Index first, convert second. reshape shares the buffer, so only the drawn
% window is ever converted to double, not the whole recording.
D      = reshape(EEG.data, size(EEG.data,1), []);
w      = size(pre.snippet, 2);
n      = size(D, 2);
i0     = max(1, min(round(pre.t0 * srate) + 1, n - min(w,n) + 1));
w      = min(w, n - i0 + 1);
Xafter = double(D(:, i0:i0+w-1));
Xbefore = pre.snippet(:, 1:w);

% ismember leaves loc at 0 wherever the label is absent, which is the only
% test draw needs.
[~, loc] = ismember(labAfter, labBefore);
nCh = numel(labAfter);

% One spacing for both panels, from the cleaned data. Robust to outliers so
% a single bad channel does not flatten the rest.
sd = median(median(abs(Xafter - median(Xafter,2)), 2)) * 1.4826;
if ~isfinite(sd) || sd <= 0, sd = 1; end
spacing = 6 * sd;

t = pre.t0 + (0:w-1) / srate;

fig = prep_newfig(1500, max(700, 22*nCh + 220));
cleanup = onCleanup(@() close(fig));

ev = window_events(pre, t(1), t(end));

tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, {base, sprintf('%g s from t = %.0f s   |   spacing %.0f uV/division   |   %d channels   |   %d event(s)', ...
      w/srate, pre.t0, spacing, nCh, numel(ev))}, ...
      'Interpreter', 'none', 'FontWeight', 'bold');

axB = nexttile(tl);
draw(axB, t, Xbefore, loc, labAfter, spacing, ...
     'before  (pre-filter)', [0.70 0.25 0.25]);
axA = nexttile(tl);
draw(axA, t, Xafter, 1:nCh, labAfter, spacing, ...
     'after  (cleaned)', [0.15 0.35 0.70]);

% Both panels, so the trace around a trigger can be read before and after
% cleaning. Drawn last, over the traces.
mark_events(axB, ev);
mark_events(axA, ev);

pngFile = prep_savefig(fig, outDir, base, 'qc_data', 120);
end

% -------------------------------------------------------------------------
function draw(ax, t, X, idx, labels, spacing, ttl, col)
hold(ax, 'on');
n = numel(labels);
for k = 1:n
    y = (n - k) * spacing;                   % first label at the top
    if idx(k) > 0 && idx(k) <= size(X,1)
        plot(ax, t, X(idx(k), :) + y, 'Color', col, 'LineWidth', 0.4);
    else
        % Present after but absent before, or the reverse. Labelled
        % rather than left as a blank row.
        text(ax, t(1), y, ' (not present)', 'Color', [0.6 0.6 0.6], ...
             'FontSize', 7, 'VerticalAlignment', 'middle');
    end
end
% Channel k is drawn at (n-k)*spacing, so channel 1 is at the top. YTick
% must be ASCENDING, hence ascending positions with the labels reversed.
set(ax, 'YTick', (0:(n-1)) * spacing, 'YTickLabel', flip(labels), 'FontSize', 7);
ylim(ax, [-spacing, n*spacing]);
xlim(ax, [t(1) t(end)]);
xlabel(ax, 'time (s)');
title(ax, ttl, 'FontSize', 10);
grid(ax, 'on');
box(ax, 'on');
end

% -------------------------------------------------------------------------
function ev = window_events(pre, t0, t1)
% The events inside the drawn window, in the order they occur.
ev = struct('type', {}, 'time', {});
if ~isfield(pre, 'events') || isempty(pre.events), return, end

keep = [pre.events.time] >= t0 & [pre.events.time] <= t1;
ev   = pre.events(keep);
if isempty(ev), return, end

[~, order] = sort([ev.time]);
ev = ev(order);
for k = 1:numel(ev), ev(k).type = prep_event_str(ev(k).type, '?'); end
end

% -------------------------------------------------------------------------
function mark_events(ax, ev)
% A vertical line per event, coloured by type, with a legend below the
% panel. No per-event text: rotated labels along the top clip against the
% axes border, and a legend under the panel covers no traces.
if isempty(ev), return, end

types = unique({ev.type}, 'stable');
cols  = lines(max(numel(types), 3));
yl    = ylim(ax);
h     = gobjects(1, numel(types));

for k = 1:numel(ev)
    ti = find(strcmp(types, ev(k).type), 1);
    ln = line(ax, [ev(k).time ev(k).time], yl, 'Color', [cols(ti,:) 0.55], ...
              'LineStyle', ':', 'LineWidth', 1.0);
    % Keep the first line of each type as the legend's handle rather than
    % drawing a second one on top of it.
    if ~isgraphics(h(ti)), h(ti) = ln; end
end

legend(ax, h(isgraphics(h)), types(isgraphics(h)), ...
       'Location', 'southoutside', 'Orientation', 'horizontal', ...
       'FontSize', 7, 'Interpreter', 'none', 'Box', 'off');
end

