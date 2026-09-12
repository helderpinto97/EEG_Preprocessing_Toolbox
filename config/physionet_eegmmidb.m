function cfg = physionet_eegmmidb()
% PHYSIONET_EEGMMIDB  EEG Motor Movement/Imagery Database (PhysioNet).
%
%   run_preprocessing('config/physionet_eegmmidb.m')
%
% https://physionet.org/content/eegmmidb/1.0.0/
% 64 channels, 160 Hz, EDF. Put the .edf files in data/.

root = fileparts(fileparts(mfilename('fullpath')));

cfg.inDir   = fullfile(root, 'data');
% Its own subfolder, so this study's qc_log.csv stays separate from another
% config's results. prep_qc_merge reads every QC file in outDir.
cfg.outDir  = fullfile(root, 'derivatives', 'physionet_eegmmidb');
cfg.fileExt = '*.edf';

cfg.srate    = [];     % 160 Hz already; do not resample
cfg.lineFreq = 60;

% Strip the dot padding so the labels match the montage template.
labs = {'Fc5.','Fc3.','Fc1.','Fcz.','Fc2.','Fc4.','Fc6.','C5..','C3..','C1..', ...
        'Cz..','C2..','C4..','C6..','Cp5.','Cp3.','Cp1.','Cpz.','Cp2.','Cp4.', ...
        'Cp6.','Fp1.','Fpz.','Fp2.','Af7.','Af3.','Afz.','Af4.','Af8.','F7..', ...
        'F5..','F3..','F1..','Fz..','F2..','F4..','F6..','F8..','Ft7.','Ft8.', ...
        'T7..','T8..','T9..','T10.','Tp7.','Tp8.','P7..','P5..','P3..','P1..', ...
        'Pz..','P2..','P4..','P6..','P8..','Po7.','Po3.','Poz.','Po4.','Po8.', ...
        'O1..','Oz..','O2..','Iz..'};
cfg.renameChans = [labs(:), regexprep(labs(:), '\.+$', '')];
end
