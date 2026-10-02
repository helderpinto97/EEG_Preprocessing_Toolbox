function fig = prep_newfig(w, h)
% PREP_NEWFIG  Off-screen figure for one QC sheet (works under -batch).

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 w h]);
try fig.Theme = 'light'; catch, end        % newer releases only
end
