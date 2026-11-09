function src_parcels_figure(atlas)
% SRC_PARCELS_FIGURE  The parcellation of the source validation on the brain.
%
%   src_parcels_figure()            DKT 62 (Mindboggle)
%   src_parcels_figure('coarse20')
%
% Parcels on the MNI pial surface of FieldTrip, numbered (homologous left
% and right regions share number and colour), with the near and far target
% triplets of src_triplets. Writes validation/results/source/parcels_<atlas>.png.

if nargin < 1, atlas = 'dkt62'; end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));          % validation/source -> repository
addpath(here, fullfile(fileparts(here), 'preprocessing'), root, fullfile(root, 'lib'));
src = src_config();
H = src_heads(src);
A = src_atlas(atlas, src, H);
trips = src_triplets(A, src, H.bst.pos);
region = regexprep(A.names, ' [LR]$', '');
[names, ~, num] = unique(region, 'stable');
nReg = numel(names);

% distinct colours: golden-angle hues, alternating lightness
h = mod((0:nReg-1)' * 0.381966, 1);
s = 0.55 + 0.25 * mod((0:nReg-1)', 2);
v = 0.95 - 0.25 * mod(floor((0:nReg-1)' / 2), 2);
col = hsv2rgb([h s v]);

anat = fullfile(root, 'lib', 'toolboxes', 'fieldtrip', 'template', 'anatomy');
srf = struct('both', load(fullfile(anat, 'surface_pial_both.mat')), ...
             'left', load(fullfile(anat, 'surface_pial_left.mat')), ...
             'right', load(fullfile(anat, 'surface_pial_right.mat')));
hemi = struct('both', true(size(A.names)), 'left', endsWith(A.names, ' L'), 'right', endsWith(A.names, ' R'));
for f = fieldnames(srf)'
    ok = find(A.bst > 0);
    ok = ok(hemi.(f{1})(A.bst(ok)));           % vertices of this hemisphere only
    [d, nn] = min(pdist2(srf.(f{1}).mesh.pos, H.bst.pos(ok, :)), [], 2);
    p = A.bst(ok(nn)); p(d > 8) = 0;
    srf.(f{1}).par = p;
end
% surface, view, camera direction (MNI), title
views = {'left', [-90 0], [-1 0 0], 'Left lateral'; 'left', [90 0], [1 0 0], 'Left medial'; ...
         'right', [-90 0], [-1 0 0], 'Right medial'; 'right', [90 0], [1 0 0], 'Right lateral'; ...
         'both', [0 90], [], 'Top'; 'both', [180 -90], [], 'Bottom'};

fig = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 30 19], 'Color', 'w');
try, fig.Theme = 'light'; catch, end
tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'tight', 'Padding', 'compact');
for vi = 1:size(views, 1)
    S = srf.(views{vi, 1});
    c = repmat([0.85 0.85 0.85], size(S.mesh.pos, 1), 1);
    in = S.par > 0;
    c(in, :) = col(num(S.par(in)), :);
    ax = draw(tl, S, c, views{vi, 2});
    title(ax, views{vi, 4}, 'FontWeight', 'normal', 'FontSize', 9);
    % number on every parcel whose most camera-facing point is on the visible hull
    dv = views{vi, 3};
    if isempty(dv), continue; end                 % no numbers on top and bottom
    proj = S.mesh.pos * dv';
    for p = unique(S.par(in))'
        vp = find(S.par == p);
        [mx, k] = max(proj(vp));
        near = vecnorm(S.mesh.pos(:, [1 2 3] ~= find(dv)) - S.mesh.pos(vp(k), [1 2 3] ~= find(dv)), 2, 2) < 10;
        if mx < max(proj(near)) - 3, continue; end   % hidden behind other cortex
        q = mean(S.mesh.pos(vp(proj(vp) > mx - 8), :), 1) + 20 * dv;
        text(ax, q(1), q(2), q(3), num2str(num(p)), 'FontSize', 6, 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'center', 'Clipping', 'off');
    end
end

% legend of region numbers
ax = nexttile(tl, [1 2]); axis(ax, 'off');
k = 0;
for r = 1:nReg
    k = k + 1;
    x = floor((k - 1) / 11) * 0.34; y = 1 - mod(k - 1, 11) * 0.09;
    patch(ax, x + [0 0.03 0.03 0], y + [0 0 0.06 0.06], col(r, :), 'EdgeColor', 'none');
    text(ax, x + 0.04, y + 0.03, sprintf('%d %s', r, names{r}), 'FontSize', 7);
end
xlim(ax, [0 1]); ylim(ax, [0 1.08]);

% target triplets
% near from the left; far from the top and the left medial side (V1)
tv = {'near', 'both', [-90 20], [0.16 0.45 0.84]; 'far', 'both', [0 90], [0.84 0.16 0.16]; ...
      'far', 'left', [90 0], [0.84 0.16 0.16]};
for ti = 1:size(tv, 1)
    S = srf.(tv{ti, 2});
    c = repmat([0.85 0.85 0.85], size(S.mesh.pos, 1), 1);
    on = ismember(S.par, trips.(tv{ti, 1}));
    c(on, :) = repmat(tv{ti, 4}, nnz(on), 1);
    ax = draw(tl, S, c, tv{ti, 3});
    title(ax, [string(capital(tv{ti, 1})) + " triplet"; string(A.names(trips.(tv{ti, 1})))'], ...
          'FontWeight', 'normal', 'FontSize', 7);
end
title(tl, sprintf('%s parcellation (%d parcels) on the MNI pial surface', upper(atlas), numel(A.names)), 'FontSize', 10);
exportgraphics(fig, fullfile(src.outRoot, sprintf('parcels_%s.png', atlas)), 'Resolution', 200);
close(fig);
end

function ax = draw(tl, S, c, vw)
ax = nexttile(tl);
patch(ax, 'Vertices', S.mesh.pos, 'Faces', S.mesh.tri, 'FaceVertexCData', c, ...
      'FaceColor', 'interp', 'EdgeColor', 'none');
axis(ax, 'equal', 'tight', 'off'); view(ax, vw);
camlight(ax, 'headlight'); lighting(ax, 'gouraud'); material(ax, 'dull');
end

function s = capital(s)
s = [upper(s(1)) s(2:end)];
end
