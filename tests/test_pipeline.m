function tests = test_pipeline
% End-to-end batch tests. Slower than the unit tests (each subject runs a
% full ICA), but this is the only layer that catches integration failures --
% it is what exposed clean_rawdata's missing private/ helpers.
tests = functiontests(localfunctions);
end

function setupOnce(t)
root = fileparts(fileparts(mfilename('fullpath')));
t.TestData.root = root;
% A small montage keeps runica quick while still exercising every step.
t.TestData.labels = {'Fp1','Fp2','F7','F3','Fz','F4','F8','C3','Cz','C4', ...
                     'P3','Pz','P4','O1','O2','T7'};
end

function inDir = write_subjects(t, n, stripCoords, extra)
% STRIPCOORDS removes the electrode coordinates before saving, so the batch
% has to fall back to the template lookup, which is what a real raw file
% usually needs. prep_testdata attaches coordinates for spatial data, so
% without this the template path is never exercised.
if nargin < 3, stripCoords = false; end
if nargin < 4, extra = {}; end
inDir = newdir();
for s = 1:n
    EEG = prep_testdata('Labels', t.TestData.labels, 'Secs', 60, ...
                        'Spatial', true, 'Seed', s, extra{:});
    % auxiliary channels prep_noneeg must drop
    EEG.data(end+1,:) = 60*sin(2*pi*0.3*(0:EEG.pnts-1)/EEG.srate);
    EEG.chanlocs(end+1).labels = 'VEOG'; EEG.chanlocs(end).type = '';
    EEG.data(end+1,:) = 0;
    EEG.chanlocs(end+1).labels = 'Status'; EEG.chanlocs(end).type = '';
    EEG.nbchan = size(EEG.data,1);
    if stripCoords
        for i = 1:numel(EEG.chanlocs)
            EEG.chanlocs(i).X = []; EEG.chanlocs(i).Y = []; EEG.chanlocs(i).Z = [];
        end
    end
    EEG = eeg_checkset(EEG);
    prep_quiet(@pop_saveset, EEG, 'filename', sprintf('sub-%02d.set', s), 'filepath', inDir);
end
end


function d = keep_dir(t)
% The one place test output is kept rather than thrown away.
%
% Only the real-recording test writes here. The synthetic tests use temp
% folders: their output is not worth looking at, and a folder per test just
% makes you hunt. This leaves a single tests/output/ holding one complete
% run on real data at production thresholds: the cleaned .set, the QC log,
% and all three figures. Gitignored.
%
% The wipe is best-effort. rmdir fails on Windows when the folder is open in
% Explorer, or while OneDrive has a handle on a file it is syncing, and a
% test must not fail because of that: the run would still have been valid.
% Stale files are cleared where possible and tolerated where not.
d = fullfile(t.TestData.root, 'tests', 'output');
if isfolder(d)
    old = dir(fullfile(d, '*'));
    old = old(~[old.isdir]);
    for k = 1:numel(old)
        try delete(fullfile(d, old(k).name)); catch, end   %#ok<CTCH>
    end
else
    [ok, msg] = mkdir(d);
    if ~ok && ~isfolder(d)
        error('test_pipeline:outDir', 'Could not create %s: %s', d, msg);
    end
end
end

function cfg = batch_cfg(inDir, outDir)
% Relaxed channel thresholds: simulated fields are not spatially rich enough
% for clean_channels at the production 0.80 / 0.10 defaults. The real
% recording in testRealRecordingAtProductionThresholds covers the defaults.
cfg = struct('inDir', inDir, 'outDir', outDir, ...
             'chanCorr', 0.5, 'maxBadFrac', 0.5);
end

function testBatchCompletesAndWritesOutputs(t)
inDir  = write_subjects(t, 2);
outDir = newdir();
T = run_quiet(batch_cfg(inDir, outDir));

verifyEqual(t, height(T), 2);
verifyTrue(t, all(T.status == "ok"));
verifyEqual(t, numel(dir(fullfile(outDir, '*_clean.set'))), 2);
verifyTrue(t, isfile(fullfile(outDir, 'qc_log.csv')));
verifyTrue(t, isfile(fullfile(outDir, 'config.json')));

% Each subject gets all three QC sheets: summary, component topographies,
% and the traces. The traces one is the check a person actually makes, so
% its absence should fail rather than pass quietly.
verifyEqual(t, numel(dir(fullfile(outDir, '*_qc.png'))),      2);
verifyEqual(t, numel(dir(fullfile(outDir, '*_qc_data.png'))), 2);
verifyTrue(t, all(strlength(T.qc_figure_data) > 0), ...
    'qc_figure_data should record the path of the traces figure');
end

function testRecordedSettingsAndQcColumns(t)
inDir  = write_subjects(t, 1);
outDir = newdir();
T = run_quiet(batch_cfg(inDir, outDir));

for f = {'nchan_raw','nchan_nonEEG','nchan_eeg','chanloc_source','srate', ...
         'line_method','nchan_rejected','rank_before_ica','rank_final', ...
         'eeglab','eeglab_release','matlab','status','error'}
    verifyTrue(t, ismember(f{1}, T.Properties.VariableNames), ...
               sprintf('QC column "%s" is missing', f{1}));
end
verifyEqual(t, T.nchan_nonEEG(1), 2);          % VEOG and Status
% Coordinates survive from prep_testdata, so no lookup is needed and
% prep_chanlocs correctly leaves them alone. The template path is covered
% by testTemplateLookupWhenCoordinatesMissing.
verifyEqual(t, T.chanloc_source(1), "existing");
end

function testFailedSubjectStillGetsARow(t)
% A missing row would be ambiguous between failed, not-run and not-found.
inDir  = write_subjects(t, 1);
% a second recording with labels no template can place
EEG = prep_testdata('Labels', {'CH01','CH02','CH03','CH04'}, 'Secs', 20);
prep_quiet(@pop_saveset, EEG, 'filename', 'sub-99.set', 'filepath', inDir);

outDir = newdir();
T = run_quiet(batch_cfg(inDir, outDir));

verifyEqual(t, height(T), 2);
bad = T(T.subject == "sub-99", :);
verifyEqual(t, bad.status, "failed");
verifyTrue(t, contains(bad.error, 'prep_chanlocs:missing'));
verifyTrue(t, isfile(fullfile(outDir, 'sub-99_error.log')));
end

function testOverwriteFalseSkipsCompleted(t)
inDir  = write_subjects(t, 1);
outDir = newdir();
run_quiet(batch_cfg(inDir, outDir));
mt = dir(fullfile(outDir, 'sub-01_clean.set')); first = mt.datenum;

cfg = batch_cfg(inDir, outDir); cfg.overwrite = false;
run_quiet(cfg);
mt = dir(fullfile(outDir, 'sub-01_clean.set'));
verifyEqual(t, mt.datenum, first);   % untouched
end

% -------------------------------------------------------------------------
function T = run_quiet(cfg)
c = prep_nowarn(); %#ok<NASGU>
T = prep_quiet(@run_preprocessing, cfg);
end

function testTemplateLookupWhenCoordinatesMissing(t)
% The usual case for a raw file: labels but no positions. prep_chanlocs must
% fill them from the template, match by label, and say so in the QC row.
inDir  = write_subjects(t, 1, true);
outDir = newdir();
T = run_quiet(batch_cfg(inDir, outDir));

verifyEqual(t, T.status(1), "ok");
verifyEqual(t, T.chanloc_source(1), "template");
verifyEqual(t, T.nchan_with_locs(1), T.nchan_eeg(1));
end

function testRealRecordingAtProductionThresholds(t)
% The synthetic fixtures need chanCorr 0.5 / maxBadFrac 0.5, because
% simulated fields are not spatially rich enough for clean_channels at the
% real defaults. That leaves the production thresholds untested, and they
% are what every actual batch runs with.
%
% Uses the EEGLAB tutorial recording from sample_data/. Nothing is checked
% into this repository: no redistribution question, no binary in git
% history, and every EEGLAB install already has it.
%
% Structural and quality assertions are in one test deliberately. A full
% pipeline here is about a minute of ICA, and splitting them would run the
% same batch twice to ask two questions about one result. TestData does not
% persist between function-based tests, so a shared cache is not available.

src     = fullfile(fileparts(which('eeglab')), 'sample_data');
setFile = fullfile(src, 'eeglab_data.set');
fdtFile = fullfile(src, 'eeglab_data.fdt');
assumeTrue(t, isfile(setFile) && isfile(fdtFile), ...
    'EEGLAB sample_data/eeglab_data.set not found');

% Both files: the .set is only a header, the samples live in the .fdt.
inDir = newdir();
copyfile(setFile, inDir);
copyfile(fdtFile, inDir);
outDir = keep_dir(t);

% Only dataset facts are overridden: 128 Hz, 60 Hz mains. Every threshold
% stays at its default, which is what this test is for.
T = run_quiet(struct('inDir', inDir, 'outDir', outDir, ...
                     'fileExt', 'eeglab_data.set', 'srate', [], 'lineFreq', 60));
d = prep_config();

verifyEqual(t, height(T), 1);
verifyEqual(t, T.status(1), "ok");

% The thresholds really were the defaults.
verifyEqual(t, T.ica_thresh(1), d.icaThresh);

% 32 channels, of which EOG1 and EOG2 are ocular.
verifyEqual(t, T.nchan_raw(1),    32);
verifyEqual(t, T.nchan_nonEEG(1),  2);
verifyEqual(t, T.nchan_eeg(1),    30);

% Real data must survive the production bad-channel criterion.
verifyLessThanOrEqual(t, T.frac_rejected(1), d.maxBadFrac);

% Average referencing costs exactly one dimension, and each subtracted
% component one more. Arithmetic on synthetic data; on a real recording it
% checks prep_rank against what the pipeline actually did.
verifyEqual(t, T.rank_before_ica(1), T.nchan_eeg(1) - T.nchan_rejected(1) - 1);
verifyEqual(t, T.rank_final(1),      T.rank_before_ica(1) - T.n_ic_flagged(1));

% Quality, not plumbing: this recording contains obvious blinks, so ICLabel
% should flag an artifact component above the default threshold. If that
% stops holding, something upstream is wrong in the rank, the electrode
% positions or the filter branches, even though every assertion above would
% pass.
verifyGreaterThanOrEqual(t, T.n_ic_flagged(1), 1, ...
    'no artifact component found in a recording that contains blinks');

verifyTrue(t, isfile(fullfile(outDir, 'eeglab_data_clean.set')));
verifyTrue(t, isfile(fullfile(outDir, 'eeglab_data_qc_ics.png')), ...
    'the topography sheet should exist when a component was removed');
end

function testEpochedBatchWritesTrialsAndCounts(t)
% Epoching is the last step before the file is saved, so it is also the one
% whose failure produces a plausible-looking derivative of the wrong shape.
% This checks the saved .set is actually 3-D and that the QC row says what
% happened to the trials.
inDir  = write_subjects(t, 1, false, {'Events', {'S 1','S 2'}});
outDir = newdir();

cfg = batch_cfg(inDir, outDir);
cfg.events      = {'S 1','S 2'};
cfg.window      = [-0.2 0.8];
cfg.baseline    = [-200 0];
cfg.epochReject = true;
cfg.epochThresh = 150;
cfg.epochProbSD = 5;
T = run_quiet(cfg);

verifyEqual(t, T.status(1), "ok");
for f = {'n_epochs','n_epochs_built','n_epochs_lost','n_epochs_rejected', ...
         'epoch_events','epoch_missing','epoch_counts','epoch_reject','baseline'}
    verifyTrue(t, ismember(f{1}, T.Properties.VariableNames), ...
               sprintf('QC column "%s" is missing', f{1}));
end
verifyEqual(t, T.epoch_events(1),  "S 1|S 2");
verifyEqual(t, T.baseline(1),      "-200 0 ms");
verifyEqual(t, T.epoch_missing(1), "");
verifyGreaterThan(t, T.n_epochs(1), 0);
verifyEqual(t, T.n_epochs(1), T.n_epochs_built(1) - T.n_epochs_rejected(1));

% Both conditions present, and their counts add up to the total.
parts = split(T.epoch_counts(1), '|');
verifyEqual(t, numel(parts), 2);
n = arrayfun(@(s) str2double(extractAfter(s, ':')), parts);
verifyEqual(t, sum(n), T.n_epochs(1));

f = fullfile(outDir, 'sub-01_clean.set');
verifyTrue(t, isfile(f));
EEG = load_quiet(f);
verifyEqual(t, EEG.trials, T.n_epochs(1));
verifyEqual(t, ndims(EEG.data), 3);
verifyEqual(t, EEG.xmax - EEG.xmin, 1, 'AbsTol', 2/EEG.srate);

% The QC figures must survive epoching. prep_subject swallows figure errors
% by design, so without this the spectra panel can fail on every epoched
% study and the batch still reports "ok". That is what happened: 3-D data
% reached pwelch and it refused.
verifyTrue(t, isfile(fullfile(outDir, 'sub-01_qc.png')), ...
    'the QC figure should be written for epoched data too');
verifyTrue(t, isfile(fullfile(outDir, 'sub-01_qc_data.png')));
verifyTrue(t, strlength(T.qc_figure(1)) > 0, ...
    'qc_figure is empty, so the figure failed and was swallowed');
end

function EEG = load_quiet(f)
EEG = prep_quiet(@pop_loadset, 'filename', f);
end

function testEdfRecordingFromAPublicDataset(t)
% One subject of PhysioNet EEGMMIDB, if it happens to be in data/.
%
% Everything else in this file feeds .set files, so this is the only test
% that imports through pop_fileio, and the only one at 160 Hz or with a
% 64-channel montage. Those three differences are what it is for: the same
% three exposed the missing Fileio plugin and the dot-padded channel labels
% when this pipeline first met a dataset it had not been developed against.
%
% Skipped rather than failed when the data is absent. PhysioNet recordings
% are not in this repository, so on any other machine this would otherwise
% fail for a reason that has nothing to do with the code.

root = t.TestData.root;
edf  = fullfile(root, 'data', 'S001', 'S001R01.edf');
assumeTrue(t, isfile(edf), ...
    sprintf('%s not found; download EEGMMIDB into data/ to run this', edf));
assumeTrue(t, exist('pop_fileio', 'file') == 2, ...
    'the Fileio plugin is needed to read .edf');

cfg = physionet_eegmmidb();          % the study file, so it is tested too
cfg.inDir   = fileparts(edf);
cfg.fileExt = 'S001R01.edf';
cfg.outDir  = newdir();

T = run_quiet(cfg);

verifyEqual(t, height(T), 1);
verifyEqual(t, T.status(1), "ok", ...
    sprintf('S001R01 failed: %s', T.error(1)));

% Dataset facts, which also prove pop_fileio read the header rather than
% something downstream inventing defaults.
verifyEqual(t, T.srate(1),     160);
verifyEqual(t, T.nchan_raw(1),  64);

% Positions came from the template, and every EEG channel got one. This is
% the assertion that catches the label problem: PhysioNet pads its labels
% with dots ('Fc5.', 'C3..'), cfg.renameChans strips them, and without that
% zero of the 64 match the montage and prep_chanlocs aborts the file.
verifyEqual(t, T.chanloc_source(1), "template");
verifyEqual(t, T.nchan_with_locs(1), T.nchan_eeg(1));

% Production thresholds, not relaxed ones: a real 64-channel recording
% should sit inside the default bad-channel limit.
d = prep_config();
verifyLessThanOrEqual(t, T.frac_rejected(1), d.maxBadFrac);

% Average reference costs one dimension, each removed component one more.
verifyEqual(t, T.rank_before_ica(1), T.nchan_eeg(1) - T.nchan_rejected(1) - 1);
verifyEqual(t, T.rank_final(1),      T.rank_before_ica(1) - T.n_ic_flagged(1));

% No dots left on any label in the saved file.
EEG = load_quiet(fullfile(cfg.outDir, 'S001R01_clean.set'));
verifyFalse(t, any(contains({EEG.chanlocs.labels}, '.')), ...
    'channel labels still carry PhysioNet dot padding');
end
