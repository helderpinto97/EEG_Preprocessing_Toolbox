function prep_qc_write(qc, outDir)
% PREP_QC_WRITE  Save one QC row to <outDir>/qc/<subject>.mat.
%
% Written to a temporary name and renamed, so an interrupted save never
% leaves a half-written file for prep_qc_merge.

qcDir = fullfile(outDir, 'qc');
if ~isfolder(qcDir)
    [ok, msg] = mkdir(qcDir);
    if ~ok && ~isfolder(qcDir)
        error('prep_qc:mkdir', 'Could not create %s: %s', qcDir, msg);
    end
end
f = fullfile(qcDir, [matlab.lang.makeValidName(char(qc.subject)) '.mat']);
save([f '.tmp'], 'qc', '-v7');
movefile([f '.tmp'], f, 'f');
end
