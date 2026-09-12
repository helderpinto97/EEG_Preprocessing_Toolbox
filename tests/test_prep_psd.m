function tests = test_prep_psd
% Spectrum tests. prep_psd is what every QC spectrum panel is drawn from, so
% a wrong peak or a wrong shape here is wrong on every sheet in a batch.
tests = functiontests(localfunctions);
end

function testFindsAKnownPeak(t)
% A 10 Hz sine must peak at 10 Hz.
srate = 250; n = srate*30;
x = sin(2*pi*10*(0:n-1)/srate);
[f, P] = prep_psd([x; x], srate);
[~, i] = max(P(:,1));
verifyEqual(t, f(i), 10, 'AbsTol', 0.5);
end

function testShape(t)
srate = 250; n = srate*30;
X = randn(4, n);
[f, P] = prep_psd(X, srate);
verifyEqual(t, size(P, 2), 4);
verifyEqual(t, numel(f), size(P, 1));
verifyEqual(t, f(1), 0);
verifyEqual(t, f(end), srate/2, 'AbsTol', 1e-6);
end

function testSeparatesTwoTones(t)
% Two channels with different frequencies must not bleed into each other.
srate = 250; n = srate*30; tt = (0:n-1)/srate;
X = [sin(2*pi*8*tt); sin(2*pi*40*tt)];
[f, P] = prep_psd(X, srate);
[~, i1] = max(P(:,1)); [~, i2] = max(P(:,2));
verifyEqual(t, f(i1), 8,  'AbsTol', 0.5);
verifyEqual(t, f(i2), 40, 'AbsTol', 0.5);
end

function testHandlesShortInput(t)
% Fewer samples than the nominal window must not error.
srate = 250;
X = randn(2, 100);
[f, P] = prep_psd(X, srate);
verifyGreaterThan(t, numel(f), 1);
verifyEqual(t, size(P,2), 2);
end
function testEpochedInputIsAccepted(t)
% 3-D input used to reach pwelch untouched and fail with "Inputs must be
% 2-D", which took out the whole QC figure for every epoched study.
srate = 128; pnts = 128; ntr = 40;
tt = (0:pnts-1)/srate;
X = repmat(sin(2*pi*10*tt), 3, 1, ntr) + 0.05*randn(3, pnts, ntr);

[f, P] = prep_psd(X, srate);
verifyEqual(t, size(P, 2), 3);
verifyEqual(t, numel(f), size(P, 1));
verifyTrue(t, all(isfinite(P), 'all'));

% The 10 Hz tone every epoch carries must survive the trial averaging.
[~, pk] = max(P(:,1));
verifyEqual(t, f(pk), 10, 'AbsTol', 1);
end

function testEpochedAveragesPowerNotDecibels(t)
% Averaging dB would give the geometric mean. Two epochs differing by a
% factor of 100 in power must average to their arithmetic mean in power.
srate = 128; pnts = 256;
tt = (0:pnts-1)/srate;
base = sin(2*pi*20*tt);
X = cat(3, base, 10*base);              % power ratio 1 : 100

[f, P] = prep_psd(X, srate);
[~, pk] = max(P(:,1));

lin  = 10.^(P(pk,1)/10);
[~, p1] = prep_psd(base,    srate);
[~, p2] = prep_psd(10*base, srate);
expect = (10.^(p1(pk)/10) + 10.^(p2(pk)/10)) / 2;

verifyEqual(t, lin, expect, 'RelTol', 1e-6);
verifyEqual(t, f(pk), 20, 'AbsTol', 1);
end

function testEpochedAndContinuousAgreeOnASteadyTone(t)
% The same signal cut into epochs or left continuous should put its peak in
% the same place; only the resolution differs.
srate = 128; pnts = 128; ntr = 30;
tt = (0:pnts*ntr-1)/srate;
x  = sin(2*pi*12*tt);

[fc, Pc] = prep_psd(x, srate);
[fe, Pe] = prep_psd(reshape(x, 1, pnts, ntr), srate);
[~, ic] = max(Pc); [~, ie] = max(Pe);
verifyEqual(t, fc(ic), 12, 'AbsTol', 1);
verifyEqual(t, fe(ie), 12, 'AbsTol', 1);
end
