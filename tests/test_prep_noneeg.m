function tests = test_prep_noneeg
% Regression tests for prep_noneeg. The old exact-string ismember missed
% whole families of auxiliary channels.
tests = functiontests(localfunctions);
end

function cfg = base_cfg()
% The shipped defaults, taken from prep_config rather than retyped. Copied
% out, these tests would keep passing against a list prep_config no longer
% has, which is the one case a test of the defaults has to catch.
cfg = prep_config();
end

function E = mk(labels, types)
E = eeg_emptyset();
n = numel(labels);
E.data = randn(n, 500); E.nbchan = n; E.pnts = 500; E.trials = 1;
E.srate = 250; E.xmin = 0; E.xmax = 499/250;
for i = 1:n
    E.chanlocs(i).labels = labels{i};
    if nargin > 1, E.chanlocs(i).type = types{i}; else, E.chanlocs(i).type = ''; end
end
E = eeg_checkset(E);
end

function verifyDropped(t, E, cfg, want)
[~, qc] = drop_quiet(E, cfg);
if qc.chans_nonEEG == "", got = strings(0,1); else, got = sort(split(qc.chans_nonEEG, "|")); end
verifyEqual(t, got, sort(string(want(:))));
end

function [E2, qc] = drop_quiet(E, cfg)
[E2, qc] = prep_quiet(@prep_noneeg, E, cfg);
end

function testBioSemiExternals(t)
% EXG1..EXG8 and the BioSemi auxiliaries: eight labels one pattern covers.
E = mk({'Fp1','Fp2','Cz','Pz','EXG1','EXG2','EXG8','GSR1','Erg1','Resp','Plet','Temp','Status'});
verifyDropped(t, E, base_cfg(), ...
    {'EXG1','EXG2','EXG8','GSR1','Erg1','Resp','Plet','Temp','Status'});
end

function testEogNamingVariants(t)
% HEOG_L, EOGv: none of these matched the old exact list.
E = mk({'Fp1','Fz','Cz','HEOG_L','HEOG_R','VEOG','EOGv','ECG'});
verifyDropped(t, E, base_cfg(), {'HEOG_L','HEOG_R','VEOG','EOGv','ECG'});
end

function testMastoidsAreKept(t)
% M1/M2 and A1/A2 are often the reference. Dropping them silently would be
% worse than keeping an extra channel, so they stay out of the defaults.
E = mk({'Fp1','Cz','M1','M2','A1','A2','TP9','TP10'});
verifyDropped(t, E, base_cfg(), {});
end

function testMatchesByChannelType(t)
% Labels give nothing away; chanlocs.type does.
E = mk({'Fp1','Cz','AUX1','AUX2'}, {'EEG','EEG','EOG','TRIG'});
verifyDropped(t, E, base_cfg(), {'AUX1','AUX2'});
end

function testRegexMetacharactersAreLiteral(t)
% 'EOG+' and 'C3.' must not be treated as patterns.
E = mk({'Fp1','C3.','EOG+','A1'});
verifyDropped(t, E, base_cfg(), {'EOG+'});
end

function testCaseInsensitive(t)
E = mk({'Fp1','veog','sTaTuS'});
verifyDropped(t, E, base_cfg(), {'veog','sTaTuS'});
end

function testDroppingEverythingErrors(t)
% A bad pattern must not silently leave an empty dataset.
E = mk({'EXG1','EXG2','Status'});
verifyError(t, @() prep_noneeg(E, base_cfg()), 'prep_noneeg:allDropped');
end

function testMissingLabelsErrors(t)
E = mk({'Fp1','Cz'});
E.chanlocs = struct([]);
verifyError(t, @() prep_noneeg(E, base_cfg()), 'prep_noneeg:noLabels');
end

function testQcCountsAreRecorded(t)
E = mk({'Fp1','Fp2','Cz','VEOG','Status'});
[~, qc] = drop_quiet(E, base_cfg());
verifyEqual(t, qc.nchan_nonEEG, 2);
verifyEqual(t, qc.nchan_eeg, 3);
end
