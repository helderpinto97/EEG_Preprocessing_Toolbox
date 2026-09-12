function tests = test_prep_qcfig
% Rendering tests for prep_qcfig.
%
% These call the figure function directly with synthetic inputs. They prove
% the figure code works: panels render, the PNG is written, missing data
% does not throw. They do NOT prove the pipeline works; test_pipeline
% does that, and it needs a Signal Processing Toolbox licence. Keeping these
% separate means figure regressions are caught even when the licence pool is
% full.
tests = functiontests(localfunctions);
end

function [EEG, pre, qc] = fixture(withICLabel, spatial)
if nargin < 1, withICLabel = true; end
if nargin < 2, spatial = false; end
EEG = prep_testdata('Secs', 30, 'LineFreq', [], 'Spatial', spatial);
EEG.data = EEG.data - mean(EEG.data, 1);

% "before": same data plus mains and drift, as a spectrum only
raw = prep_testdata('Secs', 30, 'LineFreq', 50, 'Spatial', spatial);
t   = (0:raw.pnts-1) / raw.srate;
raw.data = raw.data + 40 * sin(2*pi*0.05*t);          % slow drift
[f, P]   = prep_psd(raw.data, raw.srate);
pre = struct('f', f, 'psd', mean(P, 2), 'srate', raw.srate, 'lineFreq', 50);

thresh  = 0.80;
nFlag   = 0;
if withICLabel
    nIC = EEG.nbchan;
    C.classes = {'Brain','Muscle','Eye','Heart','Line Noise','Channel Noise','Other'};

    % A plausible decomposition rather than uniform noise: mostly brain,
    % a few confident artifacts above threshold, a couple of borderline ones
    % just below it. The borderline cases are the point of the panel.
    % Rows are written as exact probabilities that already sum to 1, rather
    % than normalised afterwards. Otherwise the "borderline" cases
    % drift away from the threshold and stop testing what they are for.
    rng(11);
    p = 0.05 * rand(nIC, 7);
    p(:,1) = p(:,1) + 0.7;
    C.classifications = p ./ sum(p, 2);

    C.classifications(2,:)  = exact_row(3, 0.93);   % confident Eye    -> removed
    C.classifications(5,:)  = exact_row(2, 0.88);   % confident Muscle -> removed
    C.classifications(7,:)  = exact_row(6, 0.84);   % Channel Noise    -> removed
    C.classifications(9,:)  = exact_row(3, 0.74);   % near-miss Eye    -> kept
    C.classifications(12,:) = exact_row(2, 0.72);   % near-miss Muscle -> kept
    C.classifications(4,:)  = exact_row(4, 0.91);   % Heart: exempt, never removed

    % Mirror the pipeline's rule, and resolve it the way prep_subject does,
    % by name against the class list rather than by row number.
    removable = find(ismember(C.classes, ...
                     {'Muscle', 'Eye', 'Line Noise', 'Channel Noise'}));
    flagged = any(C.classifications(:, removable) >= thresh, 2)';
    nFlag   = sum(flagged);

    EEG.etc.ic_classification.ICLabel = C;
    pre.ic = struct('classifications', C.classifications, 'classes', {C.classes}, ...
                    'flagged', flagged, 'thresh', thresh, 'removable', removable);
end

qc = struct('nchan_raw', 21, 'nchan_final', EEG.nbchan, ...
            'rank_before_ica', EEG.nbchan-1, 'rank_final', EEG.nbchan-4, ...
            'n_ic_flagged', nFlag, 'ica_thresh', thresh, 'line_method', "zapline-plus", ...
            'chans_rejected', "T7|P8", 'chans_nonEEG', "VEOG|Status");
end

function testWritesAPng(t)
[EEG, pre, qc] = fixture();
d = newdir();
f = prep_qcfig(EEG, pre, qc, d, 'sub-01');
verifyTrue(t, isfile(f));
verifyGreaterThan(t, dir(f).bytes, 20000);   % a real plot, not a blank canvas
end

function testWorksWithoutPreSnapshot(t)
% If the pre-filter spectrum failed, the figure must still render.
[EEG, ~, qc] = fixture();
d = newdir();
f = prep_qcfig(EEG, struct([]), qc, d, 'sub-02');
verifyTrue(t, isfile(f));
end

function testWorksWithoutICLabel(t)
% cfg.icaMode = 'flag' or an ICLabel failure must not break the figure.
[EEG, pre, qc] = fixture(false);
d = newdir();
f = prep_qcfig(EEG, pre, qc, d, 'sub-03');
verifyTrue(t, isfile(f));
end

function testLeavesNoOpenFigures(t)
% The figure is closed by onCleanup; a batch of 100 subjects must not end
% with 100 hidden figures held in memory.
before = numel(findall(0, 'Type', 'figure'));
[EEG, pre, qc] = fixture();
d = newdir();
prep_qcfig(EEG, pre, qc, d, 'sub-04');
verifyEqual(t, numel(findall(0, 'Type', 'figure')), before);
end

function testFlaggedCountMatchesThresholdRule(t)
% The fixture's flag list must follow the same rule the pipeline uses, or
% the panel would be validated against a contradiction.
[~, pre, qc] = fixture();
P = pre.ic.classifications;
want = sum(any(P(:, pre.ic.removable) >= pre.ic.thresh, 2));
verifyEqual(t, qc.n_ic_flagged, want);
verifyEqual(t, sum(pre.ic.flagged), want);
end

function testBrainAndHeartAreNeverFlagged(t)
% Brain, Heart and Other carry NaN rows in pop_icflag, so a confident Heart
% component must survive. The fixture includes one at P = 0.91.
[~, pre, ~] = fixture();
P = pre.ic.classifications;
[~, winner] = max(P, [], 2);
exempt = ~ismember(winner, pre.ic.removable);
verifyFalse(t, any(pre.ic.flagged(exempt)));
verifyTrue(t, any(winner == 4));             % a Heart component exists
end

function testIcTopoSheetRenders(t)
% The topography sheet needs the scalp maps captured before pop_subcomp;
% without them there is nothing to draw and it must return '' rather than
% error.
[EEG, pre, ~] = fixture(true, true);
pre.ic.winv     = randn(EEG.nbchan, size(pre.ic.classifications, 1));
pre.ic.chansind = 1:EEG.nbchan;
pre.ic.chanlocs = EEG.chanlocs;
d = newdir();
f = prep_qcfig_ics(pre, d, 'sub-01');
verifyTrue(t, isfile(f));
verifyGreaterThan(t, dir(f).bytes, 20000);
end

function testIcTopoSheetEmptyWhenNothingToShow(t)
[EEG, pre, ~] = fixture(true, true);
pre.ic.winv     = randn(EEG.nbchan, size(pre.ic.classifications, 1));
pre.ic.chansind = 1:EEG.nbchan;
pre.ic.chanlocs = EEG.chanlocs;
pre.ic.flagged(:) = false;
pre.ic.thresh     = 1.01;          % nothing can reach it, no near-misses
d = newdir();
f = prep_qcfig_ics(pre, d, 'sub-02', 0);
verifyEmpty(t, f);
end

function testIcTopoSheetWithoutWinvReturnsEmpty(t)
[~, pre, ~] = fixture();
d = newdir();
verifyEmpty(t, prep_qcfig_ics(pre, d, 'sub-03'));
end

function r = exact_row(cls, p)
% One class at probability P, the remainder spread evenly. Sums to 1.
r = ones(1,7) * (1-p)/6;
r(cls) = p;
end

%% prep_qcfig_data: event markers -----------------------------------------
% These build pre with prep_snapshot rather than the fixture above, which
% keeps only a spectrum: prep_qcfig_data returns '' without a snippet, so a
% fixture without one would make every assertion below pass vacuously.

function [EEG, pre] = trace_fixture(varargin)
raw = prep_testdata('Secs', 60, 'LineFreq', [], 'Seed', 5, ...
                    'Labels', {'Fp1','Fz','Cz','Pz','Oz'}, varargin{:});
pre = prep_quiet(@prep_snapshot, raw, struct('lineFreq', 50, 'qcTraceSecs', 10));
EEG = raw;
end

function f = render_data(EEG, pre)
d = newdir();
f = prep_quiet(@prep_qcfig_data, EEG, pre, d, 'sub-01');
end

function testDataSheetDrawsEventMarkers(t)
[EEG, pre] = trace_fixture('Events', {'S 1','S 2'}, 'EventEvery', 1);
% The window really does contain events, otherwise this proves nothing.
t1 = pre.t0 + (size(pre.snippet,2) - 1) / EEG.srate;
verifyGreaterThan(t, sum([pre.events.time] >= pre.t0 & [pre.events.time] <= t1), 0);

f = render_data(EEG, pre);
verifyNotEmpty(t, f);
verifyTrue(t, isfile(f));
end

function testDataSheetWithoutEventsStillRenders(t)
% A resting-state recording has no events, and a pre struct saved before
% they were captured has no such field. Neither may cost the sheet.
[EEG, pre] = trace_fixture();
verifyEmpty(t, pre.events);
verifyNotEmpty(t, render_data(EEG, pre));

pre = rmfield(pre, 'events');
verifyNotEmpty(t, render_data(EEG, pre));
end

function testDataSheetIgnoresEventsOutsideTheWindow(t)
% Events far outside the drawn segment must not stretch the axis or throw.
[EEG, pre] = trace_fixture();
pre.events = struct('type', {'S 1','S 1'}, 'time', {-500, 1e6});
verifyNotEmpty(t, render_data(EEG, pre));
end

function testDataSheetLeavesNoOpenFigures(t)
% prep_qcfig_data closes its figure through onCleanup; the marker code runs
% after that is armed, so a failure there must not leak a figure either.
[EEG, pre] = trace_fixture('Events', {'S 1'}, 'EventEvery', 1);
before = numel(findall(0, 'Type', 'figure'));
render_data(EEG, pre);
verifyEqual(t, numel(findall(0, 'Type', 'figure')), before);
end
