function tests = test_prep_qc
% Regression tests for the per-subject QC file and the merge step, which
% append-to-CSV that was O(n^2), lost the log on a crash, and raced.
tests = functiontests(localfunctions);
end

function q = okrow(subject)
q = struct('subject', string(subject), ...
           'datetime', "2026-01-01 00:00:00", ...
           'nchan_raw', 64, 'frac_rejected', 0.05, ...
           'asr_chandetect', false, 'interpolated', true, ...
           'status', "ok", 'error', "");
end

function testLogicalFieldsSurviveMerge(t)
% [logical; missing] is the one combination MATLAB refuses outright, and the
% QC struct carries seven logical fields. A failure row has none of them.
d = newdir();
prep_qc_write(okrow("sub-01"), d);
prep_qc_write(struct('subject', "sub-02", 'datetime', "2026-01-01 00:01:00", ...
                     'status', "failed", 'error', "boom"), d);
T = prep_qc_merge(d);
verifyEqual(t, height(T), 2);
verifyTrue(t, ismember('asr_chandetect', T.Properties.VariableNames));
verifyTrue(t, isnan(T.nchan_raw(T.subject == "sub-02")));
end

function testNewFieldAppearingMidStudy(t)
% The log must survive a QC field being introduced part-way through.
d = newdir();
prep_qc_write(okrow("sub-01"), d);
q = okrow("sub-02"); q.n_epochs = 120;
prep_qc_write(q, d);
T = prep_qc_merge(d);
verifyTrue(t, ismember('n_epochs', T.Properties.VariableNames));
verifyEqual(t, T.n_epochs(T.subject == "sub-02"), 120);
verifyTrue(t, isnan(T.n_epochs(T.subject == "sub-01")));
end

function testCorruptFileCostsOneRow(t)
% One damaged file must not take the whole log with it.
d = newdir();
prep_qc_write(okrow("sub-01"), d);
prep_qc_write(okrow("sub-02"), d);
fid = fopen(fullfile(d, 'qc', 'sub_99.mat'), 'w'); fwrite(fid, 'garbage'); fclose(fid);
T = verifyWarning(t, @() prep_qc_merge(d), 'prep_qc:badFile');
verifyEqual(t, height(T), 2);
end

function testMergeIsIdempotent(t)
d = newdir();
prep_qc_write(okrow("sub-01"), d);
T1 = prep_qc_merge(d);
T2 = prep_qc_merge(d);
verifyEqual(t, height(T2), height(T1));
end

function testEmptyDirWarnsNotErrors(t)
d = newdir();
T = verifyWarning(t, @() prep_qc_merge(d), 'prep_qc:noRows');
verifyEmpty(t, T);
end

function testStringTypesArePreserved(t)
% A .mat file keeps "" as "", where saving to CSV and back makes it missing.
d = newdir();
prep_qc_write(okrow("sub-01"), d);
T = prep_qc_merge(d);
verifyEqual(t, T.error(1), "");
end

function testCsvIsWritten(t)
d = newdir();
prep_qc_write(okrow("sub-01"), d);
prep_qc_merge(d);
verifyTrue(t, isfile(fullfile(d, 'qc_log.csv')));
end
