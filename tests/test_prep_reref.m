function tests = test_prep_reref
% cfg.reref: average, none, or named channels.
tests = functiontests(localfunctions);
end

function [A, B] = pair(labels)
% Two branches with identical channels, as prep_subject guarantees.
A = prep_testdata('Labels', labels, 'Secs', 10, 'LineFreq', []);
B = A;
end

function [A, B, qc] = quiet(A, B, cfg)
[A, B, qc] = prep_quiet(@prep_reref, A, B, cfg);
end

function testAverageIsTheDefault(t)
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
[A2, B2, qc] = quiet(A, B, prep_config());
verifyEqual(t, qc.reref, "average");
verifyEqual(t, A2.nbchan, A.nbchan);        % average keeps every channel
% Every sample now sums to ~zero across channels: that is what average
% referencing means, and it is why the data loses one rank.
verifyLessThan(t, max(abs(sum(double(A2.data), 1))), 1e-3);
verifyEqual(t, B2.nbchan, A2.nbchan);
end

function testAverageCostsOneRank(t)
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz','O1','O2','C3'});
r0 = prep_rank(A);
[A2, ~, ~] = quiet(A, B, prep_config());
verifyEqual(t, prep_rank(A2), r0 - 1);
end

function testNoneLeavesDataUntouched(t)
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
[A2, ~, qc] = quiet(A, B, prep_config(struct('reref', 'none')));
verifyEqual(t, qc.reref, "none");
verifyEqual(t, A2.nbchan, A.nbchan);
verifyEqual(t, A2.data, A.data);
end

function testNamedChannelIsSubtractedAndRemoved(t)
% pop_reref's 'keepref' defaults to 'off', so the reference channel is
% removed. Channel count must drop, and the remaining data must equal the
% original minus the reference channel.
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
before = double(A.data);
[A2, B2, qc] = quiet(A, B, prep_config(struct('reref', 'Cz')));

verifyEqual(t, qc.reref, "Cz");
verifyEqual(t, A2.nbchan, A.nbchan - 1);
verifyEqual(t, B2.nbchan, A2.nbchan);
verifyFalse(t, ismember('Cz', {A2.chanlocs.labels}));

iCz = 3;
keep = setdiff(1:5, iCz);
expected = before(keep,:) - before(iCz,:);
verifyEqual(t, double(A2.data), expected, 'AbsTol', 1e-3);
end

function testLinkedMastoids(t)
[A, B] = pair({'Fp1','Fz','Cz','M1','M2'});
[A2, ~, qc] = quiet(A, B, prep_config(struct('reref', {{'M1','M2'}})));
verifyEqual(t, qc.reref, "M1|M2");
verifyEqual(t, A2.nbchan, 3);               % both reference channels removed
verifyEqual(t, sort({A2.chanlocs.labels}), {'Cz','Fp1','Fz'});
end

function testBothBranchesGetTheSameReference(t)
% The ICA weights are estimated on one branch and applied to the other. A
% different reference on each would make that transfer invalid.
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
[A2, B2, ~] = quiet(A, B, prep_config(struct('reref', 'Pz')));
verifyEqual(t, {A2.chanlocs.labels}, {B2.chanlocs.labels});
verifyEqual(t, A2.nbchan, B2.nbchan);
end

function testMissingReferenceChannelErrors(t)
% Usually because it was dropped as non-EEG or rejected as bad. Silently
% falling back to the average would change the result without saying so.
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
verifyError(t, @() prep_reref(A, B, prep_config(struct('reref', 'M1'))), ...
            'prep_reref:missingRef');
end

function testCaseInsensitiveLabels(t)
[A, B] = pair({'Fp1','Fz','Cz','Pz','Oz'});
[A2, ~, ~] = quiet(A, B, prep_config(struct('reref', 'cz')));
verifyEqual(t, A2.nbchan, 4);
end
