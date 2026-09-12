function files = prep_find(inDir, fileExt, recursive, outDir)
% PREP_FIND  Locate the recordings a batch should process.
%
%   files = prep_find(inDir, fileExt, recursive, outDir)
%
% Recursive by default, because datasets are normally one folder per
% subject.
% For example PhysioNet ships S001/S001R01.edf, BIDS ships sub-01/eeg/ --
% and a flat search finds nothing there while still reporting a clean run,
% which is the worst kind of failure.


if recursive
    files = dir(fullfile(inDir, '**', fileExt));
else
    files = dir(fullfile(inDir, fileExt));
end
files = files(~[files.isdir]);

if isempty(files) || isempty(outDir), return, end
out = full_path(outDir);
if isempty(out), return, end

% Once per folder, not once per file. A recursive tree is many files spread
% over far fewer folders, and canonicalising a path is a filesystem call.
[folders, ~, back] = unique({files.folder});
insideFolder = cellfun(@(f) starts_with_path(full_path(f), out), folders);
inside       = insideFolder(back);

if any(inside)
    n     = sum(inside);
    files = files(~inside);
    warning('prep_find:skippedOutput', ...
        ['%d file(s) under cfg.outDir were ignored. Derivatives of a\n' ...
         'previous run should not be preprocessed again.'], n);
end
end

% -------------------------------------------------------------------------
function p = full_path(p)
% Absolute, normalised, no trailing separator. A folder that does not exist
% yet still needs comparing, so this is textual rather than using what().
if isempty(p), return; end
f = java.io.File(p);
if ~f.isAbsolute(), f = java.io.File(fullfile(pwd, p)); end
p = char(f.getCanonicalPath());
end

function tf = starts_with_path(child, parent)
% True when CHILD is PARENT or sits beneath it. Compared segment-wise, so
% "dataset_old" is not treated as being inside "dataset".
if isempty(parent) || isempty(child), tf = false; return; end
if ispc, child = lower(child); parent = lower(parent); end
tf = strcmp(child, parent) || startsWith(child, [parent filesep]);
end
