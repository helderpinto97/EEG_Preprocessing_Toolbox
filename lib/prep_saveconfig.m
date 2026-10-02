function prep_saveconfig(cfg, outDir)
% PREP_SAVECONFIG  Save the parameters of a batch next to its outputs.
%
% config.mat (exact) and config.json (readable). Existing files are renamed
% with a timestamp rather than overwritten.

if ~isfolder(outDir), mkdir(outDir); end
base = fullfile(outDir, 'config');
if isfile([base '.json'])
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    movefile([base '.json'], [base '_' stamp '.json'], 'f');
    if isfile([base '.mat']), movefile([base '.mat'], [base '_' stamp '.mat'], 'f'); end
end
save([base '.mat'], 'cfg', '-v7');
try
    fid = fopen([base '.json'], 'w');
    fprintf(fid, '%s\n', jsonencode(cfg, 'PrettyPrint', true));
    fclose(fid);
catch ME
    warning('prep_saveconfig:json', 'Could not write config.json: %s', ME.message);
end
end
