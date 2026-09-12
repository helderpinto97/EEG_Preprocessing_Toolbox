function tests = test_prep_qcfig_epochs
% Rendering tests for prep_qcfig_epochs.
%
% Like test_prep_qcfig, these call the figure function directly with
% synthetic inputs, so a figure regression is caught without a Signal
% Processing Toolbox licence and without running a full ICA.
tests = functiontests(localfunctions);
end

function [EEG, qc] = fixture(varargin)
% Epoched data with a planted response, so the butterfly panel has
% something real to draw rather than noise.
p = inputParser;
p.addParameter('Types', {'S 1','S 2'});
p.addParameter('Reject', true);
p.parse(varargin{:});
o = p.Results;

raw = prep_testdata('Secs', 90, 'LineFreq', [], 'Seed', 3, ...
                    'Labels', {'Fp1','Fz','Cz','Pz','Oz','O1','O2','C3'}, ...
                    'Events', o.Types, 'EventEvery', 1.5);
cfg = prep_config(struct());
cfg.srate    = [];
cfg.events   = o.Types;
cfg.window   = [-0.2 0.8];
cfg.baseline = [-200 0];
[EEG, qc] = epoch_quiet(raw, cfg);

% A deflection at 300 ms on Cz, present on every trial, so the average is
% not an artefact of the noise.
k = find(EEG.times >= 250 & EEG.times <= 350);
EEG.data(3, k, :) = EEG.data(3, k, :) + 15;

if o.Reject
    qc.n_epochs_rejected = 4;
    qc.n_epochs_lost     = 2;
    qc.epoch_reject      = "thresh 150 uV + jointprob 5 SD";
end
end

function [EEG, qc] = epoch_quiet(EEG, cfg)
[EEG, qc] = prep_quiet(@prep_epoch, EEG, cfg);
end

function f = render(EEG, qc, d, base)
f = prep_quiet(@prep_qcfig_epochs, EEG, qc, d, base);
end

%% --------------------------------------------------------------------

function testWritesAPngForEpochedData(t)
[EEG, qc] = fixture();
d = newdir();
f = render(EEG, qc, d, 'sub-01');

verifyNotEmpty(t, f);
verifyTrue(t, isfile(f));
verifyTrue(t, endsWith(f, 'sub-01_qc_epochs.png'));
% A blank or near-blank page means the panels silently drew nothing.
info = dir(f);
verifyGreaterThan(t, info.bytes, 20000);
end

function testContinuousDataDrawsNothing(t)
% Continuous data has no trials to average, so the function returns '' and
% prep_subject records an empty path rather than writing a misleading page.
EEG = prep_testdata('Secs', 20, 'LineFreq', []);
d = newdir();
f = render(EEG, struct('epoch_events', "S 1"), d, 'sub-01');

verifyEmpty(t, f);
verifyEmpty(t, dir(fullfile(d, '*.png')));
end

function testMissingQcFieldsStillRender(t)
% qc comes from prep_epoch, but a caller may pass a trimmed struct. The
% figure should degrade rather than error: a QC figure that throws costs a
% successfully preprocessed recording its whole sheet.
[EEG, ~] = fixture('Reject', false);
d = newdir();
f = render(EEG, struct('epoch_events', "S 1|S 2"), d, 'sub-01');

verifyNotEmpty(t, f);
verifyTrue(t, isfile(f));
end

function testUnknownConditionsDrawNothing(t)
% epoch_events naming types that are not in the data leaves no condition to
% plot, so the function declines instead of drawing empty axes.
[EEG, ~] = fixture();
d = newdir();
f = render(EEG, struct('epoch_events', "nothing|matches"), d, 'sub-01');

verifyEmpty(t, f);
end

function testSingleConditionRenders(t)
% One condition must not fall over on the two-panel butterfly row.
[EEG, qc] = fixture('Types', {'S 1'});
d = newdir();
f = render(EEG, qc, d, 'sub-01');

verifyNotEmpty(t, f);
verifyTrue(t, isfile(f));
end

function testNoEventStructDrawsNothing(t)
% 3-D data that never went through pop_epoch has no EEG.epoch, so no trial
% can be assigned to a condition.
EEG = prep_testdata('Secs', 20, 'LineFreq', []);
EEG.data   = reshape(EEG.data(:, 1:5000), EEG.nbchan, 500, 10);
EEG.pnts   = 500;
EEG.trials = 10;
EEG.epoch  = [];
d = newdir();
f = render(EEG, struct('epoch_events', "S 1"), d, 'sub-01');

verifyEmpty(t, f);
end
