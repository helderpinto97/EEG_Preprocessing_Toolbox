function tests = test_prep_find
% Input discovery. The non-recursive version found zero files in a
% per-subject layout and the batch still reported a clean run, which is the
% worst kind of failure: it looks like success.
tests = functiontests(localfunctions);
end

function d = tree(varargin)
% Build a temp folder containing the given relative file paths.
d = newdir();
for k = 1:numel(varargin)
    f = fullfile(d, varargin{k});
    p = fileparts(f);
    if ~isfolder(p), mkdir(p); end
    fid = fopen(f, 'w'); fwrite(fid, 'x'); fclose(fid);
end
end

function testFindsFilesInSubfolders(t)
% The PhysioNet and BIDS layout: one folder per subject.
d = tree(fullfile('S001','S001R01.edf'), fullfile('S001','S001R02.edf'), ...
         fullfile('S002','S002R01.edf'));
verifyEqual(t, numel(prep_find(d, '*.edf', true, '')), 3);
end

function testNonRecursiveFindsNothingThere(t)
% The old behaviour, kept available but no longer the default.
d = tree(fullfile('S001','S001R01.edf'), fullfile('S002','S002R01.edf'));
verifyEmpty(t, prep_find(d, '*.edf', false, ''));
end

function testFindsFilesAtTheTopLevelEitherWay(t)
d = tree('a.set', 'b.set');
verifyEqual(t, numel(prep_find(d, '*.set', true,  '')), 2);
verifyEqual(t, numel(prep_find(d, '*.set', false, '')), 2);
end

function testRecursiveIncludesTopLevelAndSubfolders(t)
d = tree('top.edf', fullfile('sub','deep.edf'));
verifyEqual(t, numel(prep_find(d, '*.edf', true, '')), 2);
end

function testExtensionFilterIsRespected(t)
d = tree(fullfile('s','a.edf'), fullfile('s','b.set'), fullfile('s','c.txt'));
verifyEqual(t, numel(prep_find(d, '*.edf', true, '')), 1);
end

function testOutputFolderInsideInputIsExcluded(t)
% Otherwise a second run discovers the first run's derivatives and
% preprocesses them again. Recursion is what makes this possible.
d = tree(fullfile('S001','S001R01.edf'), fullfile('derivatives','S001_clean.edf'));
out = fullfile(d, 'derivatives');
f = verifyWarning(t, @() prep_find(d, '*.edf', true, out), 'prep_find:skippedOutput');
verifyEqual(t, numel(f), 1);
verifyEqual(t, f(1).name, 'S001R01.edf');
end

function testSimilarlyNamedSiblingIsNotExcluded(t)
% "dataset_old" must not be treated as being inside "dataset". The
% comparison is segment-wise, not a plain string prefix.
d = tree(fullfile('dataset_old','a.edf'), fullfile('dataset','b.edf'));
f = prep_find(d, '*.edf', true, fullfile(d, 'dataset'));
verifyEqual(t, numel(f), 1);
verifyEqual(t, f(1).name, 'a.edf');
end

function testOutputFolderElsewhereChangesNothing(t)
d = tree(fullfile('S001','a.edf'));
other = newdir();
verifyEqual(t, numel(prep_find(d, '*.edf', true, other)), 1);
end

function testNoMatchesReturnsEmpty(t)
d = tree(fullfile('S001','a.edf'));
verifyEmpty(t, prep_find(d, '*.bdf', true, ''));
end

function testDirectoriesAreNotReturned(t)
% A folder called "something.set" must not be mistaken for a recording.
d = tempname; mkdir(fullfile(d, 'decoy.set'));
verifyEmpty(t, prep_find(d, '*.set', true, ''));
end
