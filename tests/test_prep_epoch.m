function tests = test_prep_epoch
% Epoching, baseline correction, and post-epoch rejection.
tests = functiontests(localfunctions);
end

function EEG = fixture(varargin)
% 60 s at 250 Hz with an event every second from t = 1 s. Two event types
% alternate, so the per-condition counts are known without measuring them.
EEG = prep_testdata('Secs', 60, 'LineFreq', [], ...
                    'Labels', {'Fp1','Fz','Cz','Pz','Oz','O1','O2','C3'}, ...
                    varargin{:});
end

function cfg = cfgWith(varargin)
% Fields set one at a time on purpose: struct('events', {'S 1'}) unwraps
% the cell and yields a field holding a char, not a cell.
s = struct();
for k = 1:2:numel(varargin), s.(varargin{k}) = varargin{k+1}; end
cfg = prep_config(s);
end

function [EEG, qc] = quiet(EEG, cfg)
% Named locally because this file calls it two dozen times; the evalc
% itself lives in prep_quiet.
[EEG, qc] = prep_quiet(@prep_epoch, EEG, cfg);
end

function call(EEG, cfg)
% Same, for verifyWarning and verifyError, which need a handle that returns
% nothing but still raises through the warning system. prep_quiet leaves
% warnings alone, which is what makes that work.
prep_quiet(@prep_epoch, EEG, cfg);
end

%% No events ---------------------------------------------------------------

function testEmptyEventsLeavesDataContinuous(t)
EEG = fixture();
[out, qc] = quiet(EEG, cfgWith('events', {}));
verifyEqual(t, out.trials, 1);
verifyEqual(t, out.data, EEG.data);
verifyTrue(t, isnan(qc.n_epochs));
verifyEqual(t, qc.epoch_events, "");
verifyEqual(t, qc.epoch_reject, "off");
end

%% Epoching ----------------------------------------------------------------

function testEpochLengthAndCount(t)
EEG = fixture('Events', {'S 1'});
cfg = cfgWith('events', {'S 1'}, 'window', [-0.2 0.8], 'baseline', []);
[out, qc] = quiet(EEG, cfg);

% A 1 s window at 250 Hz; assert the duration rather than the sample count,
% which depends on whether pop_epoch includes both endpoints.
verifyEqual(t, out.xmax - out.xmin, 1, 'AbsTol', 2/EEG.srate);
verifyEqual(t, qc.n_epochs, out.trials);
verifyEqual(t, qc.n_epochs_built, out.trials);
verifyEqual(t, qc.epoch_events, "S 1");
verifyEqual(t, qc.epoch_missing, "");

% Every matched event is accounted for: it became an epoch, or it is in
% n_epochs_lost. Nothing disappears between the two.
verifyEqual(t, qc.n_epochs_built + qc.n_epochs_lost, numel(EEG.event));
verifyEqual(t, qc.n_epochs_lost, 0);
end

function testEventTooCloseToTheEdgeIsCountedAsLost(t)
% pop_epoch drops an event that cannot carry a full window and says
% nothing. Uncounted, that is a subject quietly short of trials.
EEG = fixture('Events', {'S 1'});
k = numel(EEG.event) + 1;
EEG.event(k).type    = 'S 1';
EEG.event(k).latency = EEG.pnts;        % last sample: no room for +0.8 s
EEG.event(k).urevent = k;
EEG = eeg_checkset(EEG);

cfg = cfgWith('events', {'S 1'}, 'window', [-0.2 0.8], 'baseline', []);
verifyWarning(t, @() call(EEG, cfg), 'prep_epoch:epochsDropped');

c = prep_nowarn('prep_epoch:epochsDropped'); %#ok<NASGU>
[~, qc] = quiet(EEG, cfg);
verifyEqual(t, qc.n_epochs_lost, 1);
verifyEqual(t, qc.n_epochs_built + qc.n_epochs_lost, numel(EEG.event));
end

function testPerConditionCounts(t)
EEG = fixture('Events', {'S 1','S 2'});
cfg = cfgWith('events', {'S 1','S 2'}, 'baseline', []);
[~, qc] = quiet(EEG, cfg);

% The types alternate, so the conditions must come out within one of each
% other. A single total would hide a condition that lost its trials.
parts = split(qc.epoch_counts, '|');
verifyEqual(t, numel(parts), 2);
verifyTrue(t, startsWith(parts(1), "S 1:"));
n = arrayfun(@(s) str2double(extractAfter(s, ':')), parts);
verifyEqual(t, sum(n), qc.n_epochs);
verifyLessThanOrEqual(t, abs(n(1) - n(2)), 1);
end

function testBaselineCorrectionRemovesThePrestimulusMean(t)
EEG = fixture('Events', {'S 1'});
cfg = cfgWith('events', {'S 1'}, 'window', [-0.2 0.8], 'baseline', [-200 0]);
out = quiet(EEG, cfg);

pre = out.times >= -200 & out.times <= 0;
verifyLessThan(t, max(abs(mean(double(out.data(:, pre, :)), 2)), [], 'all'), 1e-4);
end

function testNoBaselineLeavesTheMeanAlone(t)
EEG = fixture('Events', {'S 1'});
[a, qa] = quiet(EEG, cfgWith('events', {'S 1'}, 'baseline', []));
[b, qb] = quiet(EEG, cfgWith('events', {'S 1'}, 'baseline', [-200 0]));
verifyNotEqual(t, a.data, b.data);

% Skipping it must be a recorded decision, not an absence. Six months on,
% qc_log.csv has to answer "was this baselined" without config.json, which
% is per batch and so cannot distinguish a study run in two passes.
verifyEqual(t, qa.baseline, "none");
verifyEqual(t, qb.baseline, "-200 0 ms");
end

function testBaselineOffIsByteIdenticalToNotCallingRmbase(t)
% The same guarantee prep_reref makes for cfg.reref = 'none': off means
% untouched, not "corrected by zero".
EEG = fixture('Events', {'S 1'});
cfg = cfgWith('events', {'S 1'}, 'baseline', []);
[out, ~] = quiet(EEG, cfg);

verifyEqual(t, out.data, epoch_only(EEG, cfg).data);
end

function EEG = epoch_only(EEG, cfg)
% A bare pop_epoch, to compare against what prep_epoch produced.
EEG = prep_quiet(@pop_epoch, EEG, cfg.events, cfg.window, 'epochinfo', 'yes');
end

function testContinuousDataReportsNoBaseline(t)
% Not epoched, so the field is empty rather than "none": the question did
% not arise, which is different from having been answered no.
EEG = fixture();
[~, qc] = quiet(EEG, cfgWith('events', {}));
verifyEqual(t, qc.baseline, "");
end

%% Events that are not there

function testMissingTypeWarnsAndUsesTheRest(t)
% A study file asking for two conditions against a subject whose second
% trigger was never written. Silently, that subject shows up with half the
% trials and no explanation.
EEG = fixture('Events', {'S 1'});
cfg = cfgWith('events', {'S 1','S 2'}, 'baseline', []);

verifyWarning(t, @() call(EEG, cfg), 'prep_epoch:missingEvents');

c = prep_nowarn('prep_epoch:missingEvents'); %#ok<NASGU>
[~, qc] = quiet(EEG, cfg);
verifyEqual(t, qc.epoch_events,  "S 1");
verifyEqual(t, qc.epoch_missing, "S 2");
verifyGreaterThan(t, qc.n_epochs, 0);
end

function testNoMatchingTypesErrors(t)
EEG = fixture('Events', {'S 1'});
verifyError(t, @() call(EEG, cfgWith('events', {'S 9'}, 'baseline', [])), ...
            'prep_epoch:noMatchingEvents');
end

function testNoEventStructErrors(t)
EEG = fixture();                      % no events written at all
verifyError(t, @() call(EEG, cfgWith('events', {'S 1'}, 'baseline', [])), ...
            'prep_epoch:noEventStruct');
end

function testNumericEventTypesAreMatched(t)
% Some importers write numeric event types. pop_epoch accepts both, so the
% counting here has to as well.
EEG = fixture('Events', {'S 1'});
for k = 1:numel(EEG.event), EEG.event(k).type = 7; end
[~, qc] = quiet(EEG, cfgWith('events', {7}, 'baseline', []));
verifyGreaterThan(t, qc.n_epochs, 0);
verifyEqual(t, qc.epoch_missing, "");
end

%% Rejection 

function testRejectionIsOffByDefault(t)
EEG = fixture('Events', {'S 1'});
[~, qc] = quiet(EEG, cfgWith('events', {'S 1'}, 'baseline', []));
verifyEqual(t, qc.epoch_reject, "off");
verifyTrue(t, isnan(qc.n_epochs_rejected));
end

function testAmplitudeThresholdRemovesTheSpikedEpochs(t)
EEG  = fixture('Events', {'S 1'});
% 400 uV on one channel at three known events. The fixture is pink noise at
% roughly 15 uV, so nothing else comes near the 200 uV limit. Events are
% 250 samples apart and the spike is 21 samples long, so it cannot reach
% into a neighbouring epoch.
hits = [5 12 20];
for k = hits, EEG.data(1, EEG.event(k).latency + (0:20)) = 400; end

cfg = cfgWith('events', {'S 1'}, 'baseline', [], ...
              'epochReject', true, 'epochThresh', 200, 'epochProbSD', []);
[out, qc] = quiet(EEG, cfg);

verifyEqual(t, qc.n_epochs_rej_thresh, numel(hits));
verifyEqual(t, qc.n_epochs_rejected,   numel(hits));
verifyEqual(t, qc.n_epochs, qc.n_epochs_built - numel(hits));
verifyEqual(t, out.trials, qc.n_epochs);
verifyLessThan(t, max(abs(double(out.data)), [], 'all'), 200);
verifyEqual(t, qc.epoch_rej_frac, numel(hits)/qc.n_epochs_built, 'AbsTol', 1e-9);
verifyTrue(t, contains(qc.epoch_reject, "thresh"));
verifyTrue(t, isnan(qc.n_epochs_rej_prob));   % criterion disabled
end

function testAnEpochCaughtByBothCriteriaIsRemovedOnce(t)
% Marking first and removing once is what guarantees this. Letting each
% pop_ call reject on its own would renumber the epochs in between, so the
% second criterion's indices would point into data the first had changed.
EEG = fixture('Events', {'S 1'});
EEG.data(:, EEG.event(8).latency + (0:20)) = 500;   % all channels: both fire

cfg = cfgWith('events', {'S 1'}, 'baseline', [], ...
              'epochReject', true, 'epochThresh', 200, 'epochProbSD', 3);
c = prep_nowarn('prep_epoch:highRejection'); %#ok<NASGU>
[out, qc] = quiet(EEG, cfg);

verifyGreaterThanOrEqual(t, qc.n_epochs_rej_thresh, 1);
verifyEqual(t, qc.n_epochs_rejected, qc.n_epochs_built - out.trials);
% The union, never the sum: an epoch both criteria flag is one epoch.
verifyLessThanOrEqual(t, qc.n_epochs_rejected, ...
                      qc.n_epochs_rej_thresh + qc.n_epochs_rej_prob);
verifyGreaterThanOrEqual(t, qc.n_epochs_rejected, ...
                         max(qc.n_epochs_rej_thresh, qc.n_epochs_rej_prob));
end

function testHighRejectionWarns(t)
% Two thirds of the epochs spiked, against cfg.epochMaxRejFrac = 0.4.
EEG  = fixture('Events', {'S 1'});
hits = 1:2:round(2*numel(EEG.event)/3)*2;
hits = hits(hits <= numel(EEG.event));
for k = hits, EEG.data(1, EEG.event(k).latency + (0:20)) = 400; end

cfg = cfgWith('events', {'S 1'}, 'baseline', [], ...
              'epochReject', true, 'epochThresh', 200, 'epochProbSD', [], ...
              'epochMaxRejFrac', 0.4);
verifyWarning(t, @() call(EEG, cfg), 'prep_epoch:highRejection');
end

function testEveryEpochRejectedErrors(t)
% A subject with nothing left is not a subject with zero trials; it is a
% preprocessing failure, and the batch should log it as one.
EEG = fixture('Events', {'S 1'});
cfg = cfgWith('events', {'S 1'}, 'baseline', [], ...
              'epochReject', true, 'epochThresh', 0.001, 'epochProbSD', []);
c = prep_nowarn('prep_epoch:highRejection'); %#ok<NASGU>
verifyError(t, @() call(EEG, cfg), 'prep_epoch:allEpochsRejected');
end

%% Config validation
function testRejectWithoutCriteriaIsRejected(t)
verifyError(t, @() prep_checkcfg(cfgWith('events', {'S 1'}, ...
    'epochReject', true, 'epochThresh', [], 'epochProbSD', [])), ...
    'prep_checkcfg:epochReject');
end

function testRejectWithoutEventsIsRejected(t)
verifyError(t, @() prep_checkcfg(cfgWith('events', {}, 'epochReject', true)), ...
    'prep_checkcfg:epochReject');
end

function testNegativeThresholdIsRejected(t)
verifyError(t, @() prep_checkcfg(cfgWith('epochThresh', -50)), ...
    'prep_checkcfg:epochThresh');
end

function testRejFractionMustBeAFraction(t)
verifyError(t, @() prep_checkcfg(cfgWith('epochMaxRejFrac', 1.5)), ...
    'prep_checkcfg:epochMaxRejFrac');
end

function testDefaultsPassValidation(t)
verifyWarningFree(t, @() prep_checkcfg(prep_config()));
end

%% Fixed-length epoching ---------------------------------------------------

function testFixedLengthCutsContiguousEpochs(t)
% 60 s at 250 Hz into 2 s epochs: 30 of them, each 2 s long, and no events
% needed anywhere.
EEG = fixture();                          % no events written
[out, qc] = quiet(EEG, cfgWith('epochLength', 2, 'baseline', []));

verifyEqual(t, qc.epoch_mode, "fixed 2 s");
verifyEqual(t, out.trials, 30);
verifyEqual(t, qc.n_epochs, 30);
verifyEqual(t, out.xmax - out.xmin, 2, 'AbsTol', 2/EEG.srate);
verifyEqual(t, qc.epoch_events, "fixed");
verifyEqual(t, qc.epoch_counts, "fixed:30");
verifyEqual(t, qc.baseline, "none");
end

function testFixedLengthNeedsNoEvents(t)
% A resting recording has no usable triggers, and the time-locked path
% errors on it with prep_epoch:noEventStruct.
EEG = fixture();
verifyEmpty(t, EEG.event);
verifyError(t, @() call(EEG, cfgWith('events', {'S 1'}, 'baseline', [])), ...
            'prep_epoch:noEventStruct');
[~, qc] = quiet(EEG, cfgWith('epochLength', 4, 'baseline', []));
verifyEqual(t, qc.n_epochs, 15);
end

function testFixedLengthPreservesTheSamples(t)
% Contiguous, non-overlapping epochs from the start of the recording: the
% first epoch must be the first samples of the continuous data, not a
% shifted or resampled copy.
EEG = fixture();
[out, ~] = quiet(EEG, cfgWith('epochLength', 2, 'baseline', []));
n = out.pnts;
verifyEqual(t, double(out.data(:,:,1)), double(EEG.data(:, 1:n)), 'AbsTol', 1e-6);
end

function testOverlapProducesMoreEpochs(t)
% Half an epoch of step instead of a whole one, so roughly twice as many.
EEG = fixture();
[~, q0] = quiet(EEG, cfgWith('epochLength', 2, 'epochOverlap', 0,   'baseline', []));
[~, q5] = quiet(EEG, cfgWith('epochLength', 2, 'epochOverlap', 0.5, 'baseline', []));

verifyEqual(t, q5.epoch_mode, "fixed 2 s, 50% overlap");
verifyGreaterThan(t, q5.n_epochs, 1.8 * q0.n_epochs);
verifyLessThanOrEqual(t, q5.n_epochs, 2 * q0.n_epochs + 1);
end

function testEpochLongerThanTheRecordingErrors(t)
EEG = prep_testdata('Secs', 5, 'LineFreq', []);
verifyError(t, @() call(EEG, cfgWith('epochLength', 30, 'baseline', [])), ...
            'prep_epoch:epochTooLong');
end

function testFixedLengthRejectionStillApplies(t)
% Rejection is shared between the two modes, so it has to work here too.
EEG  = fixture();
spikeAt = [3 7 11] * 2 * EEG.srate;       % inside epochs 4, 8 and 12
for s = spikeAt, EEG.data(1, s + (1:20)) = 400; end

cfg = cfgWith('epochLength', 2, 'baseline', [], ...
              'epochReject', true, 'epochThresh', 200, 'epochProbSD', []);
[out, qc] = quiet(EEG, cfg);

verifyEqual(t, qc.n_epochs_rej_thresh, 3);
verifyEqual(t, qc.n_epochs, qc.n_epochs_built - 3);
verifyEqual(t, out.trials, qc.n_epochs);
end

function testFixedLengthBaselineInsideTheEpochApplies(t)
% Fixed epochs run [0 L], so a baseline has to sit inside that. Removing
% the first 200 ms mean is legal; the default [-200 0] is not.
EEG = fixture();
[out, qc] = quiet(EEG, cfgWith('epochLength', 2, 'baseline', [0 200]));
verifyEqual(t, qc.baseline, "0 200 ms");
pre = out.times >= 0 & out.times <= 200;
verifyLessThan(t, max(abs(mean(double(out.data(:, pre, :)), 2)), [], 'all'), 1e-4);
end

function testAlreadyEpochedDataErrors(t)
EEG = fixture('Events', {'S 1'});
[ep, ~] = quiet(EEG, cfgWith('events', {'S 1'}, 'baseline', []));
verifyError(t, @() call(ep, cfgWith('epochLength', 2, 'baseline', [])), ...
            'prep_epoch:alreadyEpoched');
end

%% Choosing between the two modes ------------------------------------------

function testBothModesAtOnceIsRejected(t)
% Not a fallback order: a config asking for both has a mistake in it.
verifyError(t, @() prep_checkcfg(cfgWith('events', {'S 1'}, 'epochLength', 2)), ...
            'prep_checkcfg:epochMode');
end

function testNeitherModeLeavesDataContinuous(t)
EEG = fixture();
[out, qc] = quiet(EEG, cfgWith());
verifyEqual(t, out.trials, 1);
verifyEqual(t, qc.epoch_mode, "");
verifyTrue(t, isnan(qc.n_epochs));
end

function testEventModeRecordsItsWindow(t)
EEG = fixture('Events', {'S 1'});
[~, qc] = quiet(EEG, cfgWith('events', {'S 1'}, 'window', [-0.2 0.8], 'baseline', []));
verifyEqual(t, qc.epoch_mode, "events [-0.2 0.8] s");
end

function testDefaultBaselineWithFixedEpochsIsRejected(t)
% cfg.baseline defaults to [-200 0], which cannot sit inside an epoch that
% starts at 0. The message has to say so.
verifyError(t, @() prep_checkcfg(cfgWith('epochLength', 2)), ...
            'prep_checkcfg:baselineRange');

% And the message has to name the fix. verifyError returns the called
% function's outputs, not the exception, so the message comes from a catch.
msg = '';
try
    prep_checkcfg(cfgWith('epochLength', 2));
catch ME
    msg = ME.message;
end
verifyTrue(t, contains(msg, 'cfg.baseline = []'), ...
    'the error should tell the user to clear cfg.baseline');
end

function testOverlapOutOfRangeIsRejected(t)
verifyError(t, @() prep_checkcfg(cfgWith('epochLength', 2, 'epochOverlap', 1)), ...
            'prep_checkcfg:epochOverlap');
verifyError(t, @() prep_checkcfg(cfgWith('epochLength', 2, 'epochOverlap', -0.1)), ...
            'prep_checkcfg:epochOverlap');
end

function testNegativeEpochLengthIsRejected(t)
verifyError(t, @() prep_checkcfg(cfgWith('epochLength', -2)), ...
            'prep_checkcfg:epochLength');
end

function testRejectionWithFixedEpochsPassesValidation(t)
verifyWarningFree(t, @() prep_checkcfg(cfgWith('epochLength', 2, 'baseline', [], ...
                  'epochReject', true)));
end
