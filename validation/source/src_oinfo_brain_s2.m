function src_oinfo_brain_s2(outDir, density, variant, seed)
% SRC_OINFO_BRAIN_S2  True and estimated O-information on the brain.
%
%   src_oinfo_brain_s2(outDir)                          sparse, art_pipe, seed 1
%   src_oinfo_brain_s2(outDir, 'dense', 'raw', 1)
%
% For every condition of a run_src_stage2 folder, reconstructs the data
% again (template head, eLORETA and vertex LCMV, as in the run) and computes
% O for all triplets of parcels. Each parcel is coloured by the signed O of
% the triplet with the largest |O| it belongs to: red redundancy, blue
% synergy. The truth is nonzero only on the target triplet (any triplet
% with an independent parcel has O = 0), so colour elsewhere is spurious.
% Rows: conditions. Columns: truth, eLORETA, LCMV, each from the top, the
% left and the left medial side. Writes oinfo_brain_<density>_<variant>_sNN.png.

if nargin < 2, density = 'sparse'; end
if nargin < 3, variant = 'art_pipe'; end
if nargin < 4, seed = 1; end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));          % validation/source -> repository
addpath(here, fullfile(fileparts(here), 'preprocessing'), root, fullfile(root, 'lib'));
load(fullfile(outDir, 'setup.mat'), 'src', 'trips');
s2 = src.s2;
H = src_heads(src);
A = src_atlas(s2.atlas, src, H);
nPar = numel(A.names);
[~, allTrip] = src_triplets(A, src, H.bst.pos);
de = src.density(strcmp({src.density.name}, density));
T  = s2.secs * src.srate;
inPar = cell(nPar, 1);
for p = 1:nPar, inPar{p} = find(any(allTrip == p, 2)); end

%% Surfaces: both hemispheres (top view) and the left one (lateral, medial)
anat = fullfile(root, 'lib', 'toolboxes', 'fieldtrip', 'template', 'anatomy');
surf = {load(fullfile(anat, 'surface_pial_both.mat')), load(fullfile(anat, 'surface_pial_left.mat'))};
vpar = cell(1, 2);
for k = 1:2
    [d, nn] = min(pdist2(surf{k}.mesh.pos, H.bst.pos), [], 2);
    vpar{k} = A.bst(nn); vpar{k}(d > 8) = 0;
end
views = {1, [0 90]; 2, [-90 0]; 2, [90 0]};   % surface, view

%% O maps
conds = src.conditions;
maps = cell(numel(conds), 3);
for ci = 1:numel(conds)
    [~, Ctrue] = src_sources(conds{ci}, nPar, T, trips, src, seed*100 + ci, de.amp);
    maps{ci, 1} = parcel_max(src_oinfo3(corrcov(Ctrue), allTrip), inPar);
    name = sprintf('s%02d_%s_%s', seed, density, conds{ci});
    if startsWith(variant, 'art'), name = [name '_art']; else, name = [name '_cln']; end
    if endsWith(variant, 'pipe')
        E = pop_loadset('filename', [name '_clean.set'], 'filepath', fullfile(outDir, 'derivatives'));
    else
        E = pop_loadset('filename', [name '.set'], 'filepath', fullfile(outDir, 'sim'));
    end
    lab = {E.chanlocs.labels};
    [~, rowNy] = ismember(lab, H.ny.labels);
    m  = numel(lab);
    Hc = eye(m) - 1/m;
    Y  = Hc * double(E.data);
    Cy = (Y * Y') / size(Y, 2);
    Linv = Hc * src_interp(H.bst.chan, H.ny.chan(rowNy, :), mean(H.bst.pos, 1)) * H.bst.L;
    K = {src_inverse('eloreta', Linv, eye(m), src.reg, lab, H.bst.pos), ...
         src_inverse('lcmv', Linv, Cy, src.reg, lab, H.bst.pos)};
    for k = 1:2
        X = src_pc1(K{k}, A.bst, nPar, Cy) * Y;
        maps{ci, k + 1} = parcel_max(src_oinfo3(corrcoef(X'), allTrip), inPar);
    end
end

%% Figure
lim  = 1;                                     % nats; larger values saturate
cmap = interp1([-1 0 1], [42 120 214; 247 247 247; 214 40 40] / 255, linspace(-1, 1, 255));
cols = ["True O", "eLORETA", "LCMV"];
crow = replace(string(conds), ["red_", "syn_", "_"], ["Redundant ", "Synergistic ", " "]);
f = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 26 3.2 * numel(conds) + 2], 'Color', 'w');
try, f.Theme = 'light'; catch, end
tl = tiledlayout(f, numel(conds), 9, 'TileSpacing', 'none', 'Padding', 'compact');
for ci = 1:numel(conds)
    for k = 1:3
        for v = 1:3
            s = views{v, 1};
            c = repmat([0.8 0.8 0.8], size(surf{s}.mesh.pos, 1), 1);
            in = vpar{s} > 0;
            val = max(-1, min(1, maps{ci, k}(vpar{s}(in)) / lim));
            c(in, :) = cmap(round(1 + (val + 1) * 127), :);
            ax = nexttile(tl);
            patch(ax, 'Vertices', surf{s}.mesh.pos, 'Faces', surf{s}.mesh.tri, 'FaceVertexCData', c, ...
                  'FaceColor', 'interp', 'EdgeColor', 'none');
            axis(ax, 'equal', 'tight', 'off'); view(ax, views{v, 2});
            camlight(ax, 'headlight'); lighting(ax, 'gouraud'); material(ax, 'dull');
            if ci == 1 && v == 2, title(ax, cols(k), 'FontWeight', 'bold', 'FontSize', 9); end
            if k == 1 && v == 1
                text(ax, -0.1, 0.5, crow(ci), 'Units', 'normalized', 'Rotation', 90, ...
                     'HorizontalAlignment', 'center', 'FontSize', 8);
            end
        end
    end
end
colormap(f, cmap); clim(ax, [-lim lim]);
cb = colorbar(ax); cb.Layout.Tile = 'east';
cb.Label.String = 'Strongest triplet O of the parcel (nats): blue synergy, red redundancy';
title(tl, sprintf('%s activity, %s, seed %d. Views: top, left lateral, left medial', density, ...
      strrep(variant, '_', ' '), seed), 'FontSize', 9);
exportgraphics(f, fullfile(outDir, sprintf('oinfo_brain_%s_%s_s%02d.png', density, variant, seed)), 'Resolution', 200);
close(f);
end

function v = parcel_max(O, inPar)
% Signed O of the triplet with the largest |O| that contains each parcel.
v = zeros(numel(inPar), 1);
for p = 1:numel(inPar)
    [~, k] = max(abs(O(inPar{p})));
    v(p) = O(inPar{p}(k));
end
end
