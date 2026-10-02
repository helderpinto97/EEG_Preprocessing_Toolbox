function tests = test_prep_rank
% Regression tests for prep_rank. Every case here is a bug that shipped.
tests = functiontests(localfunctions);
end

function testContinuous(t)
% Baseline: duplicate channel plus average reference costs two dimensions.
EEG = prep_testdata('Secs', 60, 'DupChan', [4 5]);
EEG.data = EEG.data - mean(EEG.data, 1);
verifyEqual(t, prep_rank(EEG), EEG.nbchan - 2);
end

function testFlatOpeningSegment(t)
% Was returning 0, which then reached pop_runica as 'pca', 0. The estimate
% must be taken across the recording, not from the first N samples.
EEG = prep_testdata('Secs', 200, 'DupChan', [4 5], 'FlatHead', 120);
EEG.data(:, 30001:end) = EEG.data(:, 30001:end) - mean(EEG.data(:, 30001:end), 1);
verifyEqual(t, prep_rank(EEG), EEG.nbchan - 2);
end

function testEpochedUsesAllTrials(t)
% size(EEG.data,2) is pnts, not pnts*trials, so the old code ranked a
% 64-channel montage from a single 200-sample epoch.
EEG = prep_testdata('Labels', tenten64(), 'Secs', 200, 'DupChan', [4 5]);
EEG.data = EEG.data - mean(EEG.data, 1);
n = EEG.nbchan;
EEG.data   = reshape(EEG.data(:, 1:50000), n, 200, 250);
EEG.pnts   = 200;
EEG.trials = 250;
verifyEqual(t, prep_rank(EEG), n - 2);
end

function testScaleInvariant(t)
% EEGLAB's absolute 1e-7 covariance criterion returns 0 on volt-scaled data.
% The answer must not depend on the units.
EEG = prep_testdata('Secs', 60, 'DupChan', [4 5]);
EEG.data = EEG.data - mean(EEG.data, 1);
want = prep_rank(EEG);
EEG.data = EEG.data * 1e-6;
verifyWarning(t, @() prep_rank(EEG), 'prep:rankUnits');
verifyEqual(t, rank_nowarn(EEG), want);
end

function testTooFewSamplesWarns(t)
EEG = prep_testdata('Secs', 60);
EEG.data = EEG.data(:, 1:40);
EEG.pnts = 40;
verifyWarning(t, @() prep_rank(EEG), 'prep:rankSamples');
end

function testAllZeroDataErrors(t)
EEG = prep_testdata('Secs', 10);
EEG.data = zeros(size(EEG.data));
verifyError(t, @() prep_rank(EEG), 'prep:rankEmpty');
end

% -------------------------------------------------------------------------
function r = rank_nowarn(EEG)
% Not an evalc wrapper: prep_rank prints nothing. This only silences the
% units warning the caller is deliberately provoking.
c = prep_nowarn(); %#ok<NASGU>
r = prep_rank(EEG);
end

function L = tenten64()
L = {'Fp1','Fpz','Fp2','AF7','AF3','AFz','AF4','AF8','F7','F5','F3','F1', ...
     'Fz','F2','F4','F6','F8','FT7','FC5','FC3','FC1','FCz','FC2','FC4', ...
     'FC6','FT8','T7','C5','C3','C1','Cz','C2','C4','C6','T8','TP7','CP5', ...
     'CP3','CP1','CPz','CP2','CP4','CP6','TP8','P7','P5','P3','P1','Pz', ...
     'P2','P4','P6','P8','PO7','PO3','POz','PO4','PO8','O1','Oz','O2', ...
     'AF5','AF6','F9'};
end
