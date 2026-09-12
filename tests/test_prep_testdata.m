function tests = test_prep_testdata
% The fixture generator itself needs testing: if simulated data stops
% looking like EEG, every test built on it silently becomes less meaningful.
tests = functiontests(localfunctions);
end

function testAperiodicSlopeIsAsRequested(t)
% What the 1/f shaping is for. A boxcar moving average (the previous
% implementation) puts periodic nulls in the spectrum instead.
for expo = [1 1.5 2]
    EEG = prep_testdata('Secs', 120, 'LineFreq', [], 'Alpha', 0, ...
                        'Exponent', expo, 'Seed', 7);
    [f, P] = prep_psd(EEG.data, EEG.srate);
    keep = f > 2 & f < 40;
    p = polyfit(log10(f(keep)), mean(P(keep,:), 2), 1);
    verifyEqual(t, -p(1)/10, expo, 'AbsTol', 0.15, ...
        sprintf('aperiodic slope for Exponent=%.1f', expo));
end
end

function testSpectrumHasNoCombNulls(t)
% Regression: the boxcar fixture produced deep periodic notches. Adjacent
% frequency bins should not swing wildly in a smooth 1/f spectrum.
EEG = prep_testdata('Secs', 120, 'LineFreq', [], 'Alpha', 0, 'Seed', 3);
[f, P] = prep_psd(EEG.data, EEG.srate);
keep = f > 5 & f < 60;
p = mean(P(keep,:), 2);
verifyLessThan(t, max(abs(diff(p))), 6, 'bin-to-bin dB jump suggests comb nulls');
end

function testAlphaPeakIsPresent(t)
EEG = prep_testdata('Secs', 120, 'LineFreq', [], 'Alpha', 40, 'Seed', 5);
[f, P] = prep_psd(EEG.data, EEG.srate);
p = mean(P, 2);
band = f > 8 & f < 12;
verifyGreaterThan(t, max(p(band)), median(p(f > 2 & f < 40)) + 5);
end

function testLineNoiseIsInjected(t)
EEG = prep_testdata('Secs', 120, 'LineFreq', 50, 'Alpha', 0, 'Seed', 5);
[f, P] = prep_psd(EEG.data, EEG.srate);
p = mean(P, 2);
[~, i] = min(abs(f - 50));
verifyGreaterThan(t, p(i), median(p(f > 30 & f < 70)) + 10);
end

function testDupChanCostsOneDimension(t)
a = prep_testdata('Secs', 30, 'Seed', 2);
b = prep_testdata('Secs', 30, 'Seed', 2, 'DupChan', [4 5]);
verifyEqual(t, prep_rank(b), prep_rank(a) - 1);
end

function testFlatHeadIsActuallyFlat(t)
EEG = prep_testdata('Secs', 60, 'FlatHead', 10, 'Seed', 1);
n = 10 * EEG.srate;
% double(): eeg_checkset stores data as single, and verifyEqual is strict
% about class, so single(0) would not compare equal to 0.
verifyEqual(t, double(max(abs(EEG.data(:, 1:n)), [], 'all')), 0);
verifyGreaterThan(t, max(abs(EEG.data(:, n+1:end)), [], 'all'), 0);
end

function testNoSignalToolboxNeeded(t)
% The fixture must build with the Signal Toolbox unavailable: on a shared
% network licence the pool can be exhausted, and the unit suite should still
% run. Verified by shadowing the functions it must not use.
d = fullfile(tempdir, ['nosig_' char(java.util.UUID.randomUUID)]);
mkdir(d);
for fn = {'filtfilt','pwelch','resample','firls'}
    fid = fopen(fullfile(d, [fn{1} '.m']), 'w');
    fprintf(fid, 'function varargout = %s(varargin)\nerror("toolbox unavailable");\nend\n', fn{1});
    fclose(fid);
end
addpath(d, '-begin'); rehash;
c = onCleanup(@() restore(d));
EEG = prep_testdata('Secs', 20, 'Seed', 1);
verifyEqual(t, size(EEG.data, 1), EEG.nbchan);
end

function restore(d)
rmpath(d); rmdir(d, 's'); rehash;
end
