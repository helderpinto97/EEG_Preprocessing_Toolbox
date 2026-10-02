function tests = test_prep_chanlocs
% prep_chanlocs must attach positions WITHOUT reordering or relabelling.
tests = functiontests(localfunctions);
end

function cfg = base_cfg()
% The shipped defaults, taken from prep_config rather than retyped, so a
% changed default reaches these tests instead of passing them by.
cfg = prep_config();
end

function testTemplateLookupPreservesLabels(t)
% 'load' replaced chanlocs wholesale in file order and overwrote the labels;
% 'lookup' matches by label and touches only the coordinate fields.
EEG = prep_testdata('Secs', 5);
before = {EEG.chanlocs.labels};
[EEG2, qc] = chanlocs_quiet(EEG, base_cfg());
verifyEqual(t, {EEG2.chanlocs.labels}, before);
verifyEqual(t, qc.chanloc_source, "template");
verifyEqual(t, qc.nchan_with_locs, EEG.nbchan);
end

function testUnknownLabelsAreRejected(t)
% Positions that cannot be found must fail loudly, not silently degrade:
% clean_rawdata and ICLabel both need them.
EEG = prep_testdata('Labels', {'CH01','CH02','CH03','CH04'}, 'Secs', 5);
verifyError(t, @() prep_chanlocs(EEG, base_cfg()), 'prep_chanlocs:missing');
end

function testRenameThenLookup(t)
% cfg.renameChans exists so non-10-20 caps can be translated before lookup.
EEG = prep_testdata('Labels', {'A1','A2','A3','A4'}, 'Secs', 5);
cfg = base_cfg();
cfg.renameChans = {'A1','Fp1'; 'A2','Fp2'; 'A3','Cz'; 'A4','Pz'};
[EEG2, qc] = chanlocs_quiet(EEG, cfg);
verifyEqual(t, {EEG2.chanlocs.labels}, {'Fp1','Fp2','Cz','Pz'});
verifyEqual(t, qc.nchan_with_locs, 4);
end

function testMissingMontageFileErrors(t)
cfg = base_cfg();
cfg.chanlocFile = 'no/such/montage.ced';
EEG = prep_testdata('Secs', 5);
verifyError(t, @() prep_chanlocs(EEG, cfg), 'prep_chanlocs:noFile');
end

function testTemplateUseIsFlagged(t)
% Template positions are adequate for artifact rejection but a known error
% source for source reconstruction, so their use must be announced.
EEG = prep_testdata('Secs', 5);
verifyWarning(t, @() prep_chanlocs(EEG, base_cfg()), 'prep_chanlocs:template');
end

% -------------------------------------------------------------------------
function [EEG2, qc] = chanlocs_quiet(EEG, cfg)
c = prep_nowarn(); %#ok<NASGU>
[EEG2, qc] = prep_quiet(@prep_chanlocs, EEG, cfg);
end
