function tests = test_prep_trial_time
% When each trial happened, in seconds from the start of the recording.
%
% This exists because of a real bug. The logic lived inside
% prep_qcfig_epochs as a local function, returned early when EEG.urevent was
% missing, and so skipped its own fallback: every latency came back NaN and
% the amplitude panel rendered empty. The figure tests all passed, because
% they only checked that a PNG was written. Pulling the function out is what
% makes the edge case testable.
tests = functiontests(localfunctions);
end

function EEG = epoched(varargin)
raw = prep_testdata('Secs', 60, 'LineFreq', [], ...
                    'Labels', {'Fp1','Fz','Cz','Pz','Oz'}, ...
                    'Events', {'S 1'}, 'EventEvery', 2, 'EventStart', 1, ...
                    varargin{:});
cfg = prep_config(struct());
cfg.srate = []; cfg.events = {'S 1'}; cfg.window = [-0.2 0.8]; cfg.baseline = [];
EEG = epoch_quiet(raw, cfg);
end

function EEG = epoch_quiet(EEG, cfg)
EEG = prep_quiet(@prep_epoch, EEG, cfg);
end

%% --------------------------------------------------------------------

function testReturnsOnePerTrial(t)
EEG = epoched();
lat = prep_trial_time(EEG);
verifySize(t, lat, [1 EEG.trials]);
end

function testNeverReturnsNaN(t)
% A NaN here plots nothing, and a panel that draws nothing looks the same as
% one with no data to show.
EEG = epoched();
verifyTrue(t, all(isfinite(prep_trial_time(EEG))), ...
    'every trial needs a time, or its marker is silently dropped');
end

function testWithoutAUreventTableStillGivesFiniteTimes(t)
% The exact shape of the bug: no urevent table, so the real latencies are
% unavailable and the fallback has to run.
EEG = epoched();
EEG.urevent = [];
lat = prep_trial_time(EEG);

verifySize(t, lat, [1 EEG.trials]);
verifyTrue(t, all(isfinite(lat)));
verifyTrue(t, all(lat > 0));
end

function testWithoutAnEpochTableStillGivesFiniteTimes(t)
EEG = epoched();
EEG.epoch = [];
verifyTrue(t, all(isfinite(prep_trial_time(EEG))));
end

function testTimesIncreaseWithTrialNumber(t)
% Trials come out in the order they were recorded, either way it is derived.
EEG = epoched();
verifyTrue(t, issorted(prep_trial_time(EEG)), ...
    'trial times should not go backwards');

EEG.urevent = [];
verifyTrue(t, issorted(prep_trial_time(EEG)));
end

function testRealLatenciesMatchTheEventsTheyCameFrom(t)
% Events every 2 s from t = 1 s, so with a urevent table to read, the
% answers must be the real event times rather than the fallback's estimate.
EEG = epoched();
lat = prep_trial_time(EEG);

verifyEqual(t, lat(1), 1, 'AbsTol', 2/EEG.srate);
verifyEqual(t, lat(2), 3, 'AbsTol', 2/EEG.srate);
verifyEqual(t, median(diff(lat)), 2, 'AbsTol', 2/EEG.srate);
end

function testFallbackSpansAPlausibleRange(t)
% The fallback is approximate by construction, but it still has to land
% inside the recording rather than somewhere arbitrary.
EEG = epoched();
EEG.urevent = [];
lat = prep_trial_time(EEG);

verifyLessThanOrEqual(t, max(lat), EEG.trials * EEG.pnts / EEG.srate);
verifyGreaterThan(t, min(lat), 0);
end

function testAPartlyResolvedSetFallsBackWholesale(t)
% Mixing measured and estimated times on one axis would place some points
% correctly and the rest at a guess, with nothing to distinguish them. One
% unresolvable trial has to send the whole vector to the fallback.
EEG = epoched();
real = prep_trial_time(EEG);

EEG.epoch(5).eventurevent = {[]};      % one trial that cannot be placed
mixed = prep_trial_time(EEG);

verifyTrue(t, all(isfinite(mixed)));
verifyNotEqual(t, mixed, real);
% Evenly spaced, which is the fallback's signature and not the real timing.
verifyEqual(t, std(diff(mixed)), 0, 'AbsTol', 1e-9);
end
