function T = prep_concat(inDir, outDir, varargin)
% PREP_CONCAT  Merge the separate runs of one subject into one file.
%
%   T = prep_concat(inDir, outDir, 'GroupBy', pattern, ...)
%
%   GroupBy   REQUIRED. A regexp whose first capture group is the subject
%             id, applied to each file name. For files named
%             sub-01_run-1.edf that is '^(sub-\d+)'. There is no default:
%             run naming is a property of the dataset, not of this toolbox,
%             and guessing it wrong merges two subjects into one file.
%   FileExt   pattern selecting the recordings      (default '*.edf')
%   Recursive search subfolders, so a per-subject layout can be kept as
%             published (default true)
%
% Returns a table of what was written, one row per subject.
%
% ICA needs roughly 20*rank^2 samples, which a short run does not have. The
% pipeline says so per subject via qc.ica_underpowered. Merging the runs of
% one subject buys those samples, and costs less compute overall, since the
% fixed per-run overhead of ICA is then paid once per subject.
%
% pop_mergeset inserts boundary events at the joins, which EEGLAB's filters
% and epoching respect, so discontinuities are not treated as signal.
%
% Dataset preparation, separate from the pipeline: run_preprocessing stays
% one input file to one output.

p = inputParser;
p.addParameter('FileExt', '*.edf');
p.addParameter('GroupBy', '');
p.addParameter('Recursive', true);
p.parse(varargin{:});
o = p.Results;

assert(~isempty(o.GroupBy), 'prep_concat:noGroupBy', ...
    ['GroupBy is required: a regexp whose first capture group is the\n' ...
     'subject id in a file name, such as ''^(sub-\d+)''.']);
assert(isfolder(inDir), 'prep_concat:noInDir', 'Not a folder: %s', inDir);

% The reader has to exist before the first file is opened. merge_runs sits
% inside the per-subject try, so without this a missing reader is caught
% once per subject and reported as that many separate data problems, when
% it is one startup problem. run_preprocessing makes the same check for the
% same reason; the difference is that it starts EEGLAB first and this does
% not, because dataset preparation runs on its own.
%
% Checking the reader rather than EEGLAB itself is deliberate. Both readers
% live in subfolders of EEGLAB that eeglab adds when it RUNS, not when its
% root folder is put on the path, so `exist('eeglab','file')` can be true
% while pop_fileio is still missing. That is the case this catches.
[~, ~, wantExt] = fileparts(o.FileExt);
reader = prep_load('reader', wantExt);
assert(~isempty(which(reader)), 'prep_concat:noReader', ...
    ['FileExt is "%s", which is read with %s, and that function is not on\n' ...
     'the MATLAB path.\n\n' ...
     'prep_concat does not start EEGLAB, because it is dataset preparation\n' ...
     'and runs on its own. Run "eeglab nogui" first: that is what builds\n' ...
     'the EEGLAB path, and adding the EEGLAB folder alone does not.\n\n' ...
     'If it is still missing afterwards, pop_fileio needs the Fileio plugin\n' ...
     'to do the actual reading; install it via EEGLAB > File > Manage\n' ...
     'EEGLAB extensions, or use .set input, which pop_loadset handles.'], ...
     o.FileExt, reader);

if ~isfolder(outDir), mkdir(outDir); end

% Recursive, so the source layout can be kept as published: datasets are
% normally one folder per subject.
files = prep_find(inDir, o.FileExt, o.Recursive, outDir);
assert(~isempty(files), 'prep_concat:noFiles', ...
    'No files matching %s in %s', o.FileExt, inDir);

%% group by subject -------------------------------------------------------
names = {files.name};
% Full paths, because recursive discovery means the file is not necessarily
% directly inside inDir.
paths = fullfile({files.folder}, {files.name});
key   = cell(size(names));
for k = 1:numel(names)
    tok = regexp(names{k}, o.GroupBy, 'tokens', 'once');
    if isempty(tok)
        warning('prep_concat:noMatch', ...
            'GroupBy did not match "%s"; the file is skipped.', names{k});
        key{k} = '';
    else
        key{k} = tok{1};
    end
end
keep  = ~cellfun(@isempty, key);
paths = paths(keep);
names = names(keep); key = key(keep);
subs  = unique(key, 'stable');

fprintf('%d file(s) in %d subject(s)\n\n', numel(names), numel(subs));

% One row struct per subject, with the failure values as its starting point
% and the success path overwriting three of them. Written as six parallel
% arrays grown in both branches, a new column meant six declarations and two
% blocks that could drift out of order without anything saying so.
rows = repmat(struct('subject', "", 'n_runs', 0, 'n_samples', NaN, ...
                     'status', "failed", 'file', "", 'error', ""), 1, numel(subs));

for s = 1:numel(subs)
    sel      = strcmp(key, subs{s});
    runPaths = paths(sel);
    [~, ord] = sort(names(sel));                  % in run order
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
        % One bad subject must not stop the rest, same as the pipeline.
        fprintf(2, '%-10s FAILED: %s\n', subs{s}, ME.message);
        rows(s).error = string(ME.message);
    end
end

T = struct2table(rows);
writetable(T, fullfile(outDir, 'concat_log.csv'));
fprintf('\n%d subject(s), %d failed\n', height(T), sum(T.status == "failed"));
end

% -------------------------------------------------------------------------
function EEG = merge_runs(runPaths)
ALLEEG = [];
for k = 1:numel(runPaths)
    f = runPaths{k};
    E = eeg_checkset(prep_load(f));

    % Runs must agree before they can be concatenated. Merging mismatched
    % montages or sampling rates would produce a file that looks valid and
    % is not.
    if k == 1
        srate  = E.srate;
        labels = {E.chanlocs.labels};
    else
        assert(E.srate == srate, 'prep_concat:srate', ...
            '%s is %g Hz but the first run is %g Hz.', runPaths{k}, E.srate, srate);
        assert(isequal({E.chanlocs.labels}, labels), 'prep_concat:channels', ...
            '%s has different channels from the first run.', runPaths{k});
    end

    if isempty(ALLEEG), ALLEEG = E; else, ALLEEG(end+1) = E; end %#ok<AGROW>
end

if isscalar(ALLEEG)
    EEG = ALLEEG;
else
    EEG = pop_mergeset(ALLEEG, 1:numel(ALLEEG), 0);
end
EEG = eeg_checkset(EEG);
end
