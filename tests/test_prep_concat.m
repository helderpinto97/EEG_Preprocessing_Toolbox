function tests = test_prep_concat
% Tests for prep_concat, which had none.
%
% Every case here uses .set input, so pop_loadset does the reading and no
% plugin is needed. That keeps the suite independent of whether Fileio is
% installed, which is the very thing prep_concat now checks for.
tests = functiontests(localfunctions);
end

% -------------------------------------------------------------------------
function d = write_runs(names)
% One .set per entry of NAMES, all with the same montage and rate so they
% are mergeable.
d = newdir();
for k = 1:numel(names)
    EEG = prep_testdata('Secs', 5, 'LineFreq', [], 'Seed', k, ...
                        'Labels', {'Fp1','Fz','Cz','Pz','Oz'});
    prep_quiet(@pop_saveset, EEG, 'filename', [names{k} '.set'], 'filepath', d);
end
end

function T = concat(varargin)
T = prep_quiet(@prep_concat, varargin{:});
end

%% Preconditions ----------------------------------------------------------

function testGroupByIsRequired(t)
% No default, because run naming belongs to the dataset. Guessing it wrong
% merges two subjects into one file, which looks like a valid result.
d = write_runs({'sub-01_run-1'});
verifyError(t, @() concat(d, newdir(), 'FileExt', '*.set'), ...
            'prep_concat:noGroupBy');
end

function testMissingInputFolderIsRejected(t)
verifyError(t, @() concat(fullfile(tempdir, 'no_such_folder_xyz'), newdir(), ...
            'GroupBy', '^(sub-\d+)'), 'prep_concat:noInDir');
end

function testNoMatchingFilesIsRejected(t)
d = write_runs({'sub-01_run-1'});
verifyError(t, @() concat(d, newdir(), 'FileExt', '*.bdf', ...
            'GroupBy', '^(sub-\d+)'), 'prep_concat:noFiles');
end

% NOT TESTED HERE: prep_concat:noReader, which fires when the function that
% reads FileExt is not on the path. That state is "EEGLAB has not been
% started", and this suite cannot reach it: run_tests starts EEGLAB before
% anything runs, and every test below needs eeg_emptyset and pop_saveset to
% build its fixtures at all. Removing the reader is not a smaller change
% than that either, since pop_fileio and pop_loadset live in EEGLAB core,
% in the same folder as eeg_emptyset, so taking it off the path takes the
% fixtures with it. Verified by hand instead: calling prep_concat on EDF
% input from a session that has only addpath('lib') raises it.

%% Merging ----------------------------------------------------------------

function testMergesTheRunsOfOneSubject(t)
d   = write_runs({'sub-01_run-1', 'sub-01_run-2', 'sub-01_run-3'});
out = newdir();
T   = concat(d, out, 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

verifyEqual(t, height(T), 1);
verifyEqual(t, T.subject(1), "sub-01");
verifyEqual(t, T.status(1), "ok");
verifyEqual(t, T.n_runs(1), 3);
verifyTrue(t, isfile(fullfile(out, 'sub-01.set')));

% Three 5 s runs at one rate, so the merged file is the sum of their
% samples. A merge that silently kept one run would still look plausible
% in the log without this.
EEG = prep_quiet(@pop_loadset, 'filename', fullfile(out, 'sub-01.set'));
verifyEqual(t, T.n_samples(1), EEG.pnts);
verifyEqual(t, EEG.pnts, 3 * 5 * EEG.srate);
end

function testSubjectsAreKeptApart(t)
d   = write_runs({'sub-01_run-1', 'sub-01_run-2', 'sub-02_run-1'});
out = newdir();
T   = concat(d, out, 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

verifyEqual(t, height(T), 2);
verifyEqual(t, sort(T.subject), ["sub-01"; "sub-02"]);
verifyEqual(t, T.n_runs(T.subject == "sub-01"), 2);
verifyEqual(t, T.n_runs(T.subject == "sub-02"), 1);
verifyEqual(t, numel(dir(fullfile(out, '*.set'))), 2);
end

function testBoundaryEventsMarkTheJoins(t)
% pop_mergeset inserts a boundary at each join, and EEGLAB's filtering and
% epoching respect those. Without them a discontinuity is treated as signal.
d   = write_runs({'sub-01_run-1', 'sub-01_run-2', 'sub-01_run-3'});
out = newdir();
concat(d, out, 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

EEG  = prep_quiet(@pop_loadset, 'filename', fullfile(out, 'sub-01.set'));
ty   = arrayfun(@(e) string(prep_event_str(e.type, '')), EEG.event);
verifyEqual(t, sum(ty == "boundary"), 2, ...
    'three runs joined end to end leave two boundaries');
end

function testAFileGroupByCannotMatchIsSkipped(t)
% Not fatal: one stray file in the folder should not stop the dataset. Not
% silent either, or it drops out of the merge with nothing to show it.
d = write_runs({'sub-01_run-1', 'sub-01_run-2', 'notes'});
verifyWarning(t, ...
    @() concat(d, newdir(), 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)'), ...
    'prep_concat:noMatch');
end

%% One bad subject does not stop the rest ---------------------------------

function testMismatchedChannelsFailThatSubjectOnly(t)
% Merging runs with different montages would produce a file that looks
% valid and is not, so it has to fail. The other subject still has to run.
d = write_runs({'sub-01_run-1', 'sub-02_run-1', 'sub-02_run-2'});
EEG = prep_testdata('Secs', 5, 'LineFreq', [], ...
                    'Labels', {'Fp1','Fz','Cz','Pz','O1'});   % O1, not Oz
prep_quiet(@pop_saveset, EEG, 'filename', 'sub-01_run-2.set', 'filepath', d);

out = newdir();
T = concat(d, out, 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

bad = T(T.subject == "sub-01", :);
verifyEqual(t, bad.status, "failed");
verifyTrue(t, contains(bad.error, 'different channels'));
verifyTrue(t, ismissing(bad.n_samples) || isnan(bad.n_samples));

good = T(T.subject == "sub-02", :);
verifyEqual(t, good.status, "ok");
verifyTrue(t, isfile(fullfile(out, 'sub-02.set')));
end

%% The log ----------------------------------------------------------------

function testReturnsOneRowPerSubject(t)
% The returned table is the contract a caller reads, so it is asserted on
% directly rather than through the file it also happens to write.
d = write_runs({'sub-01_run-1', 'sub-01_run-2'});
T = concat(d, newdir(), 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

verifyEqual(t, sort(T.Properties.VariableNames), sort(log_columns()));
verifyEqual(t, height(T), 1);
end

function testWritesAConcatLog(t)
% The CSV is checked as text, not through readtable.
%
% readtable infers a type per column and may rename variables to suit
% MATLAB, so asserting on what it returns answers a question about its own
% import rules as much as about the file. An earlier version of this test
% did that and failed once in a full suite run and never again, which is
% the worst kind of test: it cost a real investigation and proved nothing.
% The header line is what actually has to be right, and reading it is one
% fileread with no inference in the way.
d   = write_runs({'sub-01_run-1', 'sub-01_run-2'});
out = newdir();
concat(d, out, 'FileExt', '*.set', 'GroupBy', '^(sub-\d+)');

f = fullfile(out, 'concat_log.csv');
verifyTrue(t, isfile(f));

lines = strtrim(splitlines(fileread(f)));
lines = lines(~cellfun(@isempty, lines));
verifyEqual(t, numel(lines), 2, 'a header line and one subject');
verifyEqual(t, sort(strsplit(lines{1}, ',')), sort(log_columns()));
end

function c = log_columns()
c = {'subject', 'n_runs', 'n_samples', 'status', 'file', 'error'};
end
