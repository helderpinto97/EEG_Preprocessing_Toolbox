function prep_qc_write(qc, outDir)

qcDir = fullfile(outDir, 'qc');
if ~isfolder(qcDir)
    [ok, msg] = mkdir(qcDir);
    if ~ok && ~isfolder(qcDir)
        error('prep_qc:mkdir', 'Could not create %s: %s', qcDir, msg);
    end
end

name = matlab.lang.makeValidName(char(qc.subject));
f    = fullfile(qcDir, [name '.mat']);

% Write to a temporary name and rename into place. An interrupted save then
% leaves a .tmp behind rather than a half-written file that the merge
% would have to skip.
tmp = [f '.tmp'];
save(tmp, 'qc', '-v7');
movefile(tmp, f, 'f');
end
