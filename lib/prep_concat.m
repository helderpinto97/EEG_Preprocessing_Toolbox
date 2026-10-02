function T = prep_concat(inDir, outDir, varargin)
% PREP_CONCAT  Merge the separate runs of each subject into one file.
%
%   T = prep_concat(inDir, outDir, 'GroupBy', pattern, ...)
%
%   GroupBy   REQUIRED regexp; its first capture group is the subject id,
%             e.g. '^(sub-\d+)' for sub-01_run-1.edf. No default, since a
%             wrong guess merges two subjects.
%   FileExt   recordings to read (default '*.edf')
%   Recursive search subfolders (default true)
%
% Returns one row per subject, also written to concat_log.csv. Short runs
% give ICA too few samples; merged, they give it enough. pop_mergeset marks
% the joins with boundary events, which filtering and epoching respect.
% Dataset preparation, run before run_preprocessing; EEGLAB must be started.

p = inputParser;
p.addParameter('FileExt', '*.edf');
p.addParameter('GroupBy', '');
p.addParameter('Recursive', true);
p.parse(varargin{:});
o = p.Results;

assert(~isempty(o.GroupBy), 'prep_concat:noGroupBy', ...
    'GroupBy is required: a regexp whose first capture group is the subject id, such as ''^(sub-\\d+)''.');
assert(isfolder(inDir), 'prep_concat:noInDir', 'Not a folder: %s', inDir);

% Check the reader once, instead of failing once per subject.
[~, ~, wantExt] = fileparts(o.FileExt);
reader = prep_load('reader', wantExt);
assert(~isempty(which(reader)), 'prep_concat:noReader', ...
    ['FileExt is "%s", which is read with %s, and that function is not on the path.\n' ...
     'Run "eeglab nogui" first (it builds the EEGLAB path); pop_fileio also needs\n' ...
     'the Fileio plugin, or use .set input.'], o.FileExt, reader);

if ~isfolder(outDir), mkdir(outDir); end
files = prep_find(inDir, o.FileExt, o.Recursive, outDir);
assert(~isempty(files), 'prep_concat:noFiles', 'No files matching %s in %s', o.FileExt, inDir);

%% Group by subject
names = {files.name};
paths = fullfile({files.folder}, names);
key   = cellfun(@(n) regexp(n, o.GroupBy, 'tokens', 'once'), names, 'UniformOutput', false);
noMatch = cellfun(@isempty, key);
for k = find(noMatch)
    warning('prep_concat:noMatch', 'GroupBy did not match "%s"; the file is skipped.', names{k});
end
paths = paths(~noMatch); names = names(~noMatch);
key   = cellfun(@(t) t{1}, key(~noMatch), 'UniformOutput', false);
subs  = unique(key, 'stable');
fprintf('%d file(s) in %d subject(s)\n\n', numel(names), numel(subs));

rows = repmat(struct('subject', "", 'n_runs', 0, 'n_samples', NaN, ...
                     'status', "failed", 'file', "", 'error', ""), 1, numel(subs));
for s = 1:numel(subs)
    sel      = strcmp(key, subs{s});
    [~, ord] = sort(names(sel));             % run order
    runPaths = paths(sel);
    runPaths = runPaths(ord);
    rows(s).subject = string(subs{s});
    rows(s).n_runs  = numel(runPaths);
    outName = [subs{s} '.set'];
    try
        EEG = merge_runs(runPaths);
        EEG.setname = subs{s};
        evalc("pop_saveset(EEG, 'filename', outName, 'filepath', outDir);");
        rows(s).n_samples = EEG.pnts;
        rows(s).file      = string(fullfile(outDir, outName));
        rows(s).status    = "ok";
        fprintf('%-10s %2d runs -> %d samples (%.1f min)\n', ...
                subs{s}, rows(s).n_runs, EEG.pnts, EEG.pnts/EEG.srate/60);
    catch ME
        fprintf(2, '%-10s FAILED: %s\n', subs{s}, ME.message);
        rows(s).error = string(ME.message);
    end
end

T = struct2table(rows);
writetable(T, fullfile(outDir, 'concat_log.csv'));
fprintf('\n%d subject(s), %d failed\n', height(T), sum(T.status == "failed"));
end

%% Auxiliary functions
function EEG = merge_runs(runPaths)
% Runs must share sampling rate and channels before they are merged.
for k = 1:numel(runPaths)
    E = eeg_checkset(prep_load(runPaths{k}));
    if k == 1
        ALLEEG = E;
    else
        assert(E.srate == ALLEEG(1).srate, 'prep_concat:srate', ...
            '%s is %g Hz but the first run is %g Hz.', runPaths{k}, E.srate, ALLEEG(1).srate);
        assert(isequal({E.chanlocs.labels}, {ALLEEG(1).chanlocs.labels}), 'prep_concat:channels', ...
            '%s has different channels from the first run.', runPaths{k});
        ALLEEG(end+1) = E; %#ok<AGROW>
    end
end
if isscalar(ALLEEG)
    EEG = ALLEEG;
else
    EEG = pop_mergeset(ALLEEG, 1:numel(ALLEEG), 0);
end
EEG = eeg_checkset(EEG);
end
