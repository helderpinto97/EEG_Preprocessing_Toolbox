function fig = prep_newfig(w, h)
% PREP_NEWFIG  An off-screen figure for one QC sheet.
%
%   fig = prep_newfig(width, height)   in pixels
%
% Off-screen, so the sheets render under -batch and on a cluster node.
%
% Theme is a figure property of newer releases only, and setting it is not
% the same as setting Color: it themes the axes too, which is what decides
% whether tick labels come out readable on an exported PNG. Assigned inside
% a try so an older release simply keeps its own defaults.

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 w h]);
try fig.Theme = 'light'; catch, end
end
