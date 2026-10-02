function tests = test_prep_snapshot
% What prep_snapshot keeps for the QC figures, and in which clock.
tests = functiontests(localfunctions);
end

function EEG = fixture(varargin)
EEG = prep_testdata('Secs', 60, 'LineFreq', [], ...
                    'Labels', {'Fp1','Fz','Cz','Pz','Oz'}, varargin{:});
end

function pre = snap(EEG, cfg)
pre = prep_quiet(@prep_snapshot, EEG, cfg);
end

function cfg = base_cfg()
cfg = struct('lineFreq', 50, 'qcTraceSecs', 10);
end

function EEG = resample_quiet(EEG, rate)
% Both arguments are used inside the evaluated string, which checkcode
% cannot see; passing them in keeps that visible at the call site.
EEG = prep_quiet(@pop_resample, EEG, rate);
end

%% --------------------------------------------------------------------

function testKeepsASpectrumAndASegment(t)
EEG = fixture();
pre = snap(EEG, base_cfg());

verifyNotEmpty(t, pre.psd);
verifyNotEmpty(t, pre.f);
verifyEqual(t, size(pre.snippet, 1), EEG.nbchan);
verifyEqual(t, size(pre.snippet, 2), 10 * EEG.srate);
verifyEqual(t, pre.labels, {EEG.chanlocs.labels});
end

function testNoEventsGivesAnEmptyEventList(t)
EEG = fixture();
pre = snap(EEG, base_cfg());
verifyEmpty(t, pre.events);
verifyTrue(t, isstruct(pre.events));           % shape stays usable
verifyTrue(t, all(ismember({'type','time'}, fieldnames(pre.events))));
end

function testEventTimesAreSecondsInTheSnippetClock(t)
% The alignment guarantee the markers depend on: pre.events(k).time and
% pre.t0 are the same clock, so a marker drawn at time T sits on the sample
% the event actually points at.
EEG = fixture('Events', {'S 1'}, 'EventEvery', 2, 'EventStart', 1);
pre = snap(EEG, base_cfg());

verifyEqual(t, numel(pre.events), numel(EEG.event));
% First event was written at 1 s, then every 2 s.
verifyEqual(t, pre.events(1).time, 1, 'AbsTol', 1/EEG.srate);
verifyEqual(t, pre.events(2).time, 3, 'AbsTol', 1/EEG.srate);

% And each one matches its own latency, not just the first.
for k = 1:numel(EEG.event)
    verifyEqual(t, pre.events(k).time, ...
        (double(EEG.event(k).latency) - 1) / EEG.srate, 'AbsTol', 1e-9);
end
end

function testEventTimesLandInsideTheSnippetWindow(t)
% The segment starts a quarter of the way in, so some events fall inside it
% and some outside. Both must be expressible on the same axis.
EEG = fixture('Events', {'S 1'}, 'EventEvery', 1);
pre = snap(EEG, base_cfg());

t0 = pre.t0;
t1 = pre.t0 + (size(pre.snippet, 2) - 1) / EEG.srate;
inWindow = [pre.events.time] >= t0 & [pre.events.time] <= t1;

verifyGreaterThan(t, sum(inWindow), 0, ...
    'the 10 s window should contain events written once a second');
verifyGreaterThan(t, sum(~inWindow), 0, ...
    'a 60 s recording should also have events outside the window');
end

function testNumericEventTypesSurvive(t)
EEG = fixture('Events', {'S 1'}, 'EventEvery', 5);
for k = 1:numel(EEG.event), EEG.event(k).type = 42; end
pre = snap(EEG, base_cfg());

verifyEqual(t, numel(pre.events), numel(EEG.event));
verifyEqual(t, pre.events(1).type, 42);
end

function testResamplingDoesNotDesynchroniseTheMarkers(t)
% The reason the times are captured here rather than read off EEG later.
% pop_resample rescales event latencies; a snapshot taken after it must
% report seconds that still agree with its own snippet.
EEG = fixture('Events', {'S 1'}, 'EventEvery', 2, 'EventStart', 1);
pre = snap(resample_quiet(EEG, 125), base_cfg());

verifyEqual(t, pre.srate, 125);
verifyEqual(t, pre.events(1).time, 1, 'AbsTol', 2/125);
verifyEqual(t, pre.events(2).time, 3, 'AbsTol', 2/125);
end
