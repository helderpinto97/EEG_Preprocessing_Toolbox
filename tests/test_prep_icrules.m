function tests = test_prep_icrules
% The component rules ICLabel is known to need help with: cardiac (with and
% without a recorded ECG) and single-electrode. Built on a known mixing, so
% which component is which is not in doubt.
tests = functiontests(localfunctions);
end

function [EEG, S, heart, pop] = fixture()
% 8 channels, 8 sources: brain-like noise and alpha, one heartbeat, one
% component whose map sits on a single electrode.
rng(3);
fs = 250; n = 60 * fs; nc = 8;
S = zeros(nc, n);
for k = 1:nc
    S(k, :) = filter(1, [1 -0.95], randn(1, n));          % slow, brain-like
end
t = (0:n-1) / fs;
S(2, :) = S(2, :) + 3 * sin(2*pi*10*t) .* (1 + sin(2*pi*0.2*t)); % waxing alpha
heart = 5;  S(heart, :) = 20 * ecg_wave(n, fs, 70);
pop   = 7;
A = randn(nc) + 2;                                       % smooth-ish maps
A(:, pop) = 0.02 * randn(nc, 1);  A(3, pop) = 1;         % one electrode
S = S ./ std(S, 0, 2);

EEG = eeg_emptyset();
EEG.data = A * S; EEG.nbchan = nc; EEG.pnts = n; EEG.trials = 1;
EEG.srate = fs; EEG.xmin = 0; EEG.xmax = (n-1)/fs;
for i = 1:nc, EEG.chanlocs(i).labels = sprintf('E%d', i); end
EEG.icawinv = A; EEG.icaweights = inv(A); EEG.icasphere = eye(nc);
EEG.icachansind = 1:nc;
end

function s = ecg_wave(n, fs, bpm)
% PQRST beats at BPM with 5% beat-to-beat variation.
tb = -0.35:1/fs:0.55;
w  = [0.15 -0.20 0.025; -0.10 -0.04 0.010; 1 0 0.012; -0.25 0.04 0.012; 0.30 0.30 0.050];
beat = sum(w(:,1) .* exp(-(tb - w(:,2)).^2 ./ (2 * w(:,3).^2)), 1);
s = zeros(1, n); tt = 0.5;
while true
    i = round((tt + tb) * fs) + 1;
    if i(end) > n, break, end
    s(i) = s(i) + beat;
    tt = tt + 60/bpm * (1 + 0.05*randn);
end
end

function E = ecg_channel(EEG, S, heart)
% As prep_ecgref returns it: one channel, at the rate of the recording.
E = eeg_emptyset();
E.data = S(heart, :) + 0.2 * randn(1, EEG.pnts);
E.nbchan = 1; E.pnts = EEG.pnts; E.trials = 1; E.srate = EEG.srate;
E.xmin = 0; E.xmax = EEG.xmax; E.chanlocs = struct('labels', 'ECG');
end

function cfg = rules(varargin)
% Every rule off, then switch on the ones named, at their defaults.
cfg = prep_config(struct('ecgCorr', [], 'icaHeartbeat', false, 'icaSingleChan', []));
d   = prep_config();
for k = 1:numel(varargin), cfg.(varargin{k}) = d.(varargin{k}); end
end

function testEcgReferenceFindsTheHeart(t)
[EEG, S, heart] = fixture();
[flag, reason, qc] = prep_icrules(EEG, ecg_channel(EEG, S, heart), rules('ecgCorr'));
verifyEqual(t, find(flag), heart);
verifyTrue(t, startsWith(reason(heart), "ECG"));
verifyEqual(t, qc.n_ic_ecg, 1);
end

function testHeartbeatWithoutReference(t)
[EEG, ~, heart] = fixture();
[flag, reason, qc] = prep_icrules(EEG, [], rules('icaHeartbeat'));
verifyEqual(t, find(flag), heart);
verifyTrue(t, startsWith(reason(heart), "heartbeat"));
verifyEqual(t, qc.n_ic_heartbeat, 1);
end

function testHeartbeatSkippedWhenEcgExists(t)
% With a reference the detector is not needed, and not run.
[EEG, S, heart] = fixture();
[~, ~, qc] = prep_icrules(EEG, ecg_channel(EEG, S, heart), rules('ecgCorr', 'icaHeartbeat'));
verifyEqual(t, qc.n_ic_heartbeat, 0);
verifyEqual(t, qc.n_ic_ecg, 1);
end

function testSingleChannelMap(t)
[EEG, ~, ~, pop] = fixture();
[flag, reason] = prep_icrules(EEG, [], rules('icaSingleChan'));
verifyEqual(t, find(flag), pop);
verifyTrue(t, startsWith(reason(pop), "one channel"));
end

function testAllRulesOffFlagNothing(t)
[EEG, S, heart] = fixture();
flag = prep_icrules(EEG, ecg_channel(EEG, S, heart), rules());
verifyFalse(t, any(flag));
end

function testDefaultsFlagOnlyTheArtifacts(t)
[EEG, ~, heart, pop] = fixture();
flag = prep_icrules(EEG, [], prep_config());
verifyEqual(t, find(flag), sort([heart pop]));
end

function testEcgLengthMismatchWarns(t)
[EEG, S, heart] = fixture();
E = ecg_channel(EEG, S, heart);
E.data = E.data(1:end-10); E.pnts = EEG.pnts - 10;
flag = verifyWarning(t, @() prep_icrules(EEG, E, rules('ecgCorr')), 'prep_icrules:ecgLength');
verifyFalse(t, any(flag));
end

function testEcgRefByLabelAndType(t)
E = eeg_emptyset();
E.data = randn(4, 500); E.nbchan = 4; E.pnts = 500; E.trials = 1; E.srate = 250;
E.chanlocs = struct('labels', {'Fz','Cz','EKG','X1'}, 'type', {'','','','ECG'});
E = eeg_checkset(E);
[R, qc] = prep_ecgref(E, prep_config());
verifyEqual(t, R.nbchan, 2);
verifyEqual(t, qc.ecg_channels, "EKG|X1");
end

function testEcgRefNoneOrOff(t)
E = eeg_emptyset();
E.data = randn(3, 500); E.nbchan = 3; E.pnts = 500; E.trials = 1; E.srate = 250;
E.chanlocs = struct('labels', {'Fz','Cz','ECG'});
E = eeg_checkset(E);
verifyEmpty(t, prep_ecgref(E, prep_config(struct('ecgCorr', []))));
verifyEmpty(t, prep_ecgref(E, prep_config(struct('ecgChannels', {{}}))));
[R, qc] = prep_ecgref(pop_select(E, 'channel', [1 2]), prep_config());
verifyEmpty(t, R);
verifyEqual(t, qc.ecg_channels, "");
end
