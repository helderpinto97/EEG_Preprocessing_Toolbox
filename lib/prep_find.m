function files = prep_find(inDir, fileExt, recursive, outDir)
% PREP_FIND  Locate the recordings a batch should process.
%
%   files = prep_find(inDir, fileExt, recursive, outDir)
%
% Recursive by default, since datasets usually have one folder per subject.
% Files under outDir (derivatives of an earlier run) are skipped.

if recursive
    files = dir(fullfile(inDir, '**', fileExt));
else
    files = dir(fullfile(inDir, fileExt));
end
files = files(~[files.isdir]);
if isempty(files) || isempty(outDir), return, end

out = full_path(outDir);
[folders, ~, back] = unique({files.folder});          % once per folder
inside = cellfun(@(f) is_inside(full_path(f), out), folders);
inside = inside(back);
if any(inside)
    files = files(~inside);
    warning('prep_find:skippedOutput', ...
        '%d file(s) under cfg.outDir were ignored; derivatives are not preprocessed again.', sum(inside));
end
end

function p = full_path(p)
% Absolute and canonical, also for a folder that does not exist yet.
f = java.io.File(p);
if ~f.isAbsolute(), f = java.io.File(fullfile(pwd, p)); end
p = char(f.getCanonicalPath());
end

function tf = is_inside(child, parent)
% Segment-wise, so "dataset_old" is not inside "dataset".
if ispc, child = lower(child); parent = lower(parent); end
tf = strcmp(child, parent) || startsWith(child, [parent filesep]);
end
