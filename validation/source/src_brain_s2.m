function src_brain_s2(outDir, density, cond, variant, seed)
% SRC_BRAIN_S2  Brain maps of one Stage 2 dataset.
%
%   src_brain_s2(outDir)                                   sparse, syn_near, art_pipe, seed 1
%   src_brain_s2(outDir, 'dense', 'red_far', 'raw', 1)
%
% Reconstructs one dataset of a run_src_stage2 folder again (template head,
% eLORETA and LCMV, as in the run) and draws parcel values on the MNI pial
% surface of FieldTrip. Rows:
%   truth     the three parcels of the target triplet
%   leakage   per parcel, max |r| with the true triplet signals: where the
%             triplet appears after reconstruction (on the triplet itself
%             this is its recovery; elsewhere it is spurious)
%   recovery  per parcel, |r| with its own true signal
% Correlations in the band src.s2.band. Writes brain_<...>.png.

if nargin < 2, density = 'sparse'; end
if nargin < 3, cond = 'syn_near'; end
if nargin < 4, variant = 'art_pipe'; end
if nargin < 5, seed = 1; end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));          % validation/source -> repository
addpath(here, fullfile(fileparts(here), 'preprocessing'), root, fullfile(root, 'lib'));
load(fullfile(outDir, 'setup.mat'), 'src', 'trips');
s2 = src.s2;

%% Truth
H = src_heads(src);
A = src_atlas(s2.atlas, src, H);
nPar = numel(A.names);
de = src.density(strcmp({src.density.name}, density));
ci = find(strcmp(src.conditions, cond));
T  = s2.secs * src.srate;
[S, ~, trip] = src_sources(cond, nPar, T, trips, src, seed*100 + ci, de.amp);
Sb = bandpass_fft(S, s2.band, src.srate);

%% Data of the variant
name = sprintf('s%02d_%s_%s', seed, density, cond);
if startsWith(variant, 'art'), name = [name '_art']; else, name = [name '_cln']; end
if endsWith(variant, 'pipe')
    E = pop_loadset('filename', [name '_clean.set'], 'filepath', fullfile(outDir, 'derivatives'));
else
    E = pop_loadset('filename', [name '.set'], 'filepath', fullfile(outDir, 'sim'));
end
[~, rowNy] = ismember({E.chanlocs.labels}, H.ny.labels);
m  = numel(rowNy);
Hc = eye(m) - 1/m;
Y  = Hc * double(E.data);
Cy = (Y * Y') / size(Y, 2);
Linv = Hc * src_interp(H.bst.chan, H.ny.chan(rowNy, :), mean(H.bst.pos, 1)) * H.bst.L;

%% Surface: parcel of every pial vertex from the nearest Brainstorm vertex
s = load(fullfile(root, 'lib', 'toolboxes', 'fieldtrip', 'template', 'anatomy', 'surface_pial_both.mat'));
mesh = s.mesh;
[d, nn] = min(pdist2(mesh.pos, H.bst.pos), [], 2);
vpar = A.bst(nn);
vpar(d > 8) = 0;                              % medial wall and others: grey

%% Maps
meths = ["eloreta", "lcmv"];
mname = ["eLORETA", "LCMV"];
maps = {double(ismember(1:nPar, trip))'};
rows = "True triplet parcels";
for k = 1:2
    K = src_inverse(char(meths(k)), Linv, eye(m) * (meths(k) == "eloreta") + Cy * (meths(k) == "lcmv"), ...
                    src.reg, {E.chanlocs.labels}, H.bst.pos);
    X = bandpass_fft(src_pc1(K, A.bst, nPar, Cy) * Y, s2.band, src.srate);
    r = abs(corr(X', Sb'));
    maps(end+1:end+2) = {max(r(:, trip), [], 2), diag(r)};
    rows(end+1:end+2) = [mname(k) + ": leakage of the triplet", mname(k) + ": recovery of own signal"];
end

%% Figure
cmap = interp1([0 0.5 1], [1 0.97 0.88; 0.93 0.45 0.2; 0.45 0.05 0.1], linspace(0, 1, 256));
views = {[-90 0], [0 90], [90 0]};
f = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 15 4 * numel(maps)], 'Color', 'w');
try, f.Theme = 'light'; catch, end
tl = tiledlayout(f, numel(maps), 3, 'TileSpacing', 'none', 'Padding', 'compact');
for i = 1:numel(maps)
    c = repmat([0.8 0.8 0.8], size(mesh.pos, 1), 1);
    in = vpar > 0;
    c(in, :) = cmap(1 + round(255 * min(1, maps{i}(vpar(in)))), :);
    for v = 1:3
        ax = nexttile(tl);
        patch(ax, 'Vertices', mesh.pos, 'Faces', mesh.tri, 'FaceVertexCData', c, ...
              'FaceColor', 'interp', 'EdgeColor', 'none');
        axis(ax, 'equal', 'tight', 'off'); view(ax, views{v});
        camlight(ax, 'headlight'); lighting(ax, 'gouraud'); material(ax, 'dull');
        if v == 1, title(ax, rows(i), 'FontWeight', 'normal', 'FontSize', 8, 'HorizontalAlignment', 'left', ...
                         'Units', 'normalized', 'Position', [0 1]); end
    end
end
colormap(f, cmap);
cb = colorbar(ax); cb.Layout.Tile = 'east'; cb.Label.String = '|r| with true signal (0.5-45 Hz)';
title(tl, sprintf('%s activity, %s, %s, seed %d (views: left, top, right)', density, strrep(cond, '_', ' '), ...
      strrep(variant, '_', ' '), seed), 'FontSize', 9);
exportgraphics(f, fullfile(outDir, sprintf('brain_%s_%s_%s_s%02d.png', density, cond, variant, seed)), 'Resolution', 200);
close(f);
end

function Y = bandpass_fft(X, band, fs)
% Ideal band-pass by zeroing FFT bins (as in run_src_stage2).
n = size(X, 2);
f = (0:n-1) * fs / n;
f = min(f, fs - f);
F = fft(X, [], 2);
F(:, f < band(1) | f > band(2)) = 0;
Y = real(ifft(F, [], 2));
end
