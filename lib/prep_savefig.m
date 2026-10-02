function pngFile = prep_savefig(fig, outDir, base, suffix, res)
% PREP_SAVEFIG  Write a QC sheet to <outDir>/<base>_<suffix>.png at RES dpi.
% The caller closes the figure (through onCleanup).

if ~isfolder(outDir), mkdir(outDir); end
pngFile = fullfile(outDir, [base '_' suffix '.png']);
exportgraphics(fig, pngFile, 'Resolution', res);
end
