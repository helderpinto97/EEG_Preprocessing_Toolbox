function prep_saveconfig(cfg, outDir)
% PREP_SAVECONFIG  Record the parameters a batch ran with.
%
% Writes config.json (readable and diffable) and config.mat (exact types)
% next to the derivatives. Without this the QC log pins the software but not
% the parameters, which answers only half of "how was this produced".
%
% Existing files are timestamped rather than overwritten, so rerunning a
% batch with different parameters does not erase what the previous outputs
% were made with.

if ~isfolder(outDir), mkdir(outDir); end

base = fullfile(outDir, 'config');
if isfile([base '.json'])
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    movefile([base '.json'], [base '_' stamp '.json'], 'f');
    if isfile([base '.mat'])
        movefile([base '.mat'], [base '_' stamp '.mat'], 'f');
    end
end

save([base '.mat'], 'cfg', '-v7');

try
    txt = jsonencode(cfg, 'PrettyPrint', true);
    fid = fopen([base '.json'], 'w');
    if fid > 0
        fprintf(fid, '%s\n', txt);
        fclose(fid);
    end
catch ME
    % The .mat is the authoritative copy; JSON is the convenience.
    warning('prep_saveconfig:json', 'Could not write config.json: %s', ME.message);
end
end
