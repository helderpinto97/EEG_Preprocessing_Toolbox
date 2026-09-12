function pngFile = prep_savefig(fig, outDir, base, suffix, res)
% PREP_SAVEFIG  Write one QC sheet to <outDir>/<base>_<suffix>.png.
%
% The resolution is per sheet rather than fixed: the component sheet is
% read by looking at small scalp maps and needs the detail, the trace
% sheets are read at a glance and would only get larger.
%
% Closing the figure is left to the caller, which does it through onCleanup
% so that a sheet failing half-drawn is closed as well as one that finished.

if ~isfolder(outDir), mkdir(outDir); end
pngFile = fullfile(outDir, [base '_' suffix '.png']);
exportgraphics(fig, pngFile, 'Resolution', res);
end
