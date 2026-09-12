function tests = test_prep_config
% Config defaults, override merging and value validation.
tests = functiontests(localfunctions);
end

function testDefaultsValidate(t)
verifyWarningFree(t, @() prep_checkcfg(prep_config()));
end

function testOverrideApplied(t)
c = prep_config(struct('lp', 100));
verifyEqual(t, c.lp, 100);
verifyEqual(t, c.hpAnalysis, 0.1);   % untouched fields keep the default
end

function testTypoIsRejected(t)
% cfg.hpAnalyis must fail here, not deep inside a filter.
verifyError(t, @() prep_config(struct('hpAnalyis', 0.1)), 'prep_config:unknownField');
end

function testStudyFileLoads(t)
root = fileparts(fileparts(mfilename('fullpath')));
f = fullfile(root, 'config', 'example_study.m');
assumeTrue(t, isfile(f));
c = prep_config(f);
verifyEqual(t, c.lp, 100);
end

function testMissingStudyFileErrors(t)
verifyError(t, @() prep_config('no/such/file.m'), 'prep_config:noStudyFile');
end

function testIcaModeValidated(t)
verifyError(t, @() prep_checkcfg(prep_config(struct('icaMode', 'delete'))), ...
            'prep_checkcfg:icaMode');
end

function testIcaTypeValidated(t)
verifyError(t, @() prep_checkcfg(prep_config(struct('icaType', 'fastica'))), ...
            'prep_checkcfg:icaType');
end

function testFractionsValidated(t)
verifyError(t, @() prep_checkcfg(prep_config(struct('icaThresh', 80))), ...
            'prep_checkcfg:fraction');
end

function testLowpassAboveNyquist(t)
% srate named here rather than left to the default: the Nyquist check only
% runs when the rate is known, and cfg.srate defaults to [] to leave the
% recording's own rate alone.
verifyError(t, @() prep_checkcfg(prep_config(struct('srate', 250, 'lp', 200))), ...
            'prep_checkcfg:lpNyquist');
end

function testLineFreqAboveNyquist(t)
% lp must be lowered too, or the lp check fires first.
verifyError(t, @() prep_checkcfg(prep_config(struct('srate', 80, 'lp', 30))), ...
            'prep_checkcfg:lineNyquist');
end

function testIcaBranchMustBeHigherPassed(t)
% hpICA below hpAnalysis inverts the two-branch design.
verifyError(t, @() prep_checkcfg(prep_config(struct('hpICA', 0.05))), ...
            'prep_checkcfg:hpOrder');
end

function testBaselineOutsideWindow(t)
% window is SECONDS, baseline is MILLISECONDS; pop_rmbase would silently do
% nothing rather than complain.
c = prep_config(struct('events', {{'S 1'}}, 'baseline', [-500 0]));
verifyError(t, @() prep_checkcfg(c), 'prep_checkcfg:baselineRange');
end

function testBaselineInSecondsIsAccepted(t)
% [-0.2 0] ms sits inside [-0.2 0.8] s, so this is legal even though the
% user probably meant seconds. Documented, not enforced.
c = prep_config(struct('events', {{'S 1'}}, 'baseline', [-0.2 0]));
verifyWarningFree(t, @() prep_checkcfg(c));
end

function testFlagsMustBeLogical(t)
verifyError(t, @() prep_checkcfg(prep_config(struct('interpolate', 1))), ...
            'prep_checkcfg:flag');
end

function testMissingInputDir(t)
verifyError(t, @() prep_checkcfg(prep_config(struct('inDir', 'Z:/nope'))), ...
            'prep_checkcfg:noInDir');
end

function testSaveConfigArchivesPrevious(t)
% A rerun with different parameters must not erase what the existing
% derivatives were produced with.
d = newdir();
c = prep_config(struct('outDir', d));
prep_saveconfig(c, d);
prep_saveconfig(c, d);
verifyEqual(t, numel(dir(fullfile(d, 'config*.json'))), 2);
end
