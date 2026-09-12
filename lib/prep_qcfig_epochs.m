function pngFile = prep_qcfig_epochs(EEG, qc, outDir, base)
% PREP_QCFIG_EPOCHS  What the epoching produced, per condition.
%
%   pngFile = prep_qcfig_epochs(EEG, qc, outDir, base)
%
% The QC columns say how many trials you kept, not whether they are any
% good. A count looks the same either way. Five panels:
%
%   butterfly    Every channel, mean over trials, one panel per condition.
%                Shows whether an evoked response exists at all.
%   GFP          Standard deviation across channels, conditions on one axis.
%                Shows when the conditions differ.
%   ERP image    Single trials at the peak channel, one row each. A real
%                response is a stripe across most rows; a few bright rows
%                carrying the mean is not.
%   amplitude    Largest value in each trial against session time. A rising
%                trend is an electrode drying out, a gap is removed trials.
%   counts       Built, rejected and kept, per condition.
%
% Returns '' for continuous data.

pngFile = '';
if ~isstruct(EEG) || EEG.trials < 2 || ismatrix(EEG.data)
    return
end

types = split_qc_list(getfielddef(qc, 'epoch_events', ""));
if isempty(types), return, end

lab = prep_epoch_labels(EEG, types);
present = types(arrayfun(@(k) any(lab == string(types{k})), 1:numel(types)));
if isempty(present), return, end
nC = numel(present);

% One mask and one count per condition, built once. Four panels need them,
% and re-deriving the comparison in each is how a title and a bar chart end
% up disagreeing about the same condition.
masks = arrayfun(@(k) lab == string(present{k}), 1:nC, 'UniformOutput', false);
nPer  = cellfun(@sum, masks);

t    = EEG.times;                      % ms
cols = lines(max(nC, 3));

fig = prep_newfig(1500, 420*2 + 160);
cleanup = onCleanup(@() close(fig));
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s   %d trials, %d channels   baseline: %s   rejection: %s', ...
      base, EEG.trials, EEG.nbchan, ...
      getfielddef(qc, 'baseline', "?"), getfielddef(qc, 'epoch_reject', "?")), ...
      'Interpreter', 'none', 'FontWeight', 'bold');

%% 1-2. Butterfly, one panel per condition (first two) ---------------------
erp  = cell(1, nC);
peak = zeros(1, nC);
for c = 1:nC
    % mean accumulates in double without ever holding a double copy of the
    % whole epoched array, which on a long resting-state file is gigabytes.
    erp{c} = mean(EEG.data(:, :, masks{c}), 3, 'double');
    [~, peak(c)] = max(max(abs(erp{c}), [], 2));
end

yl = max(cellfun(@(E) max(abs(E(:))), erp)) * 1.05;
for c = 1:min(nC, 2)
    ax = nexttile(tl);
    plot(ax, t, erp{c}', 'LineWidth', 0.4, 'Color', [0.45 0.45 0.45 0.5]);
    hold(ax, 'on');
    % Peak channel on top, as a reference line for the rest.
    plot(ax, t, erp{c}(peak(c), :), 'Color', cols(c,:), 'LineWidth', 1.6);
    ylim(ax, [-yl yl]); xlim(ax, [t(1) t(end)]);
    mark_zero(ax);
    xlabel(ax, 'ms'); ylabel(ax, '\muV');
    title(ax, sprintf('%s   n = %d   (peak: %s)', present{c}, ...
          nPer(c), EEG.chanlocs(peak(c)).labels), ...
          'Interpreter', 'none');
    grid(ax, 'on');
end
for c = nC+1:2, nexttile(tl); axis off; end  % keep the 2x3 grid shape

%% 3. Global field power, conditions overlaid ------------------------------
ax = nexttile(tl);
hold(ax, 'on'); h = gobjects(1, nC); gfp = cell(1, nC);
for c = 1:nC
    gfp{c} = std(erp{c}, 0, 1);
    h(c)   = plot(ax, t, gfp{c}, 'Color', cols(c,:), 'LineWidth', 1.5);
end
gfpMax = max(cellfun(@max, gfp));
ylim(ax, [0 gfpMax * 1.05]);
xlim(ax, [t(1) t(end)]);
mark_zero(ax);
xlabel(ax, 'ms'); ylabel(ax, '\muV');
title(ax, 'Global field power');
legend(ax, h, present, 'Location', 'best', 'Interpreter', 'none');
grid(ax, 'on');

%% 4. ERP image, busiest condition -----------------------------------------
ax = nexttile(tl);
[~, big] = max(nPer);
sel = find(masks{big});
% One channel of one condition, indexed before it is converted.
img = double(squeeze(EEG.data(peak(big), :, sel)))';
imagesc(ax, t, 1:numel(sel), img);
clim(ax, [-1 1] * max(abs(img(:))) * 0.8);
colormap(ax, parula); colorbar(ax);
mark_zero(ax);
xlabel(ax, 'ms'); ylabel(ax, 'trial');
title(ax, sprintf('Single trials, %s at %s', present{big}, ...
      EEG.chanlocs(peak(big)).labels), 'Interpreter', 'none');

%% 5. Amplitude against time in the session --------------------------------
% Trial number against latency is a straight line by construction. Amplitude
% against session time shows whether the recording got worse as it went: a
% rising trend is an electrode drying out, a gap is removed trials.
ax = nexttile(tl);
lat  = prep_trial_time(EEG) / 60;
% Largest absolute value per trial, taken from the two signed extremes so no
% full-size abs() temporary is built over the whole epoched array.
ampl = double(squeeze(max(max(max(EEG.data, [], 1), [], 2), ...
                          max(max(-EEG.data, [], 1), [], 2))))';
hold(ax, 'on'); h = gobjects(1, nC);
for c = 1:nC
    m = masks{c};
    h(c) = plot(ax, lat(m), ampl(m), 'o', 'MarkerSize', 4, ...
                'MarkerFaceColor', cols(c,:), 'MarkerEdgeColor', 'none');
end
xlabel(ax, 'minutes into the recording'); ylabel(ax, 'max |\muV| in trial');
title(ax, 'Amplitude over the session');
legend(ax, h, present, 'Location', 'best', 'Interpreter', 'none');
grid(ax, 'on');

%% 6. Trial budget ----------------------------------------------------------
ax = nexttile(tl);
kept = nPer;
rej  = getfielddef(qc, 'n_epochs_rejected', NaN);
lost = getfielddef(qc, 'n_epochs_lost', NaN);
% Rejected and lost trials no longer carry a condition label, so they go in
% one bar rather than being split across conditions on a guess.
vals   = [kept(:)', nan_to_zero(rej), nan_to_zero(lost)];
labels = [present(:)', {'rejected'}, {'lost'}];
b = bar(ax, vals, 'FaceColor', 'flat');
for c = 1:nC, b.CData(c,:) = cols(c,:); end
b.CData(nC+1,:) = [0.75 0.25 0.25];
b.CData(nC+2,:) = [0.55 0.55 0.55];
set(ax, 'XTick', 1:numel(vals), 'XTickLabel', labels, 'XTickLabelRotation', 30);
ylabel(ax, 'trials'); title(ax, 'Trials kept');
text(ax, 1:numel(vals), vals, compose('%d', vals), ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
grid(ax, 'on');

pngFile = prep_savefig(fig, outDir, base, 'qc_epochs', 150);
end


% =========================================================================
function mark_zero(ax)
% Dotted line at t = 0, spanning whatever the axis shows. Call it after the
% ylim is set.
line(ax, [0 0], ylim(ax), 'Color', 'k', 'LineStyle', ':', 'LineWidth', 0.8);
end


% =========================================================================
function c = split_qc_list(s)
c = {};
if strlength(s) == 0, return, end
c = cellstr(split(string(s), '|'))';
end


% =========================================================================
function v = nan_to_zero(x)
if isempty(x) || isnan(x), v = 0; else, v = x; end
end


% =========================================================================
function v = getfielddef(s, f, d)
% This sheet is drawn from a qc row a caller hands in, and a caller may hand
% in a trimmed one. Degrading to a "?" in a title costs a label; throwing
% costs the sheet. See testMissingQcFieldsStillRender.
if isstruct(s) && isfield(s, f), v = s.(f); else, v = d; end
end
