function EEG = sim_eegset(X, srate, labels, setname)
% SIM_EEGSET  Continuous EEGLAB dataset from a channels x samples matrix.
%
% Labels only, no coordinates: a raw recording rarely carries them, and
% leaving them out makes the pipeline take its usual template lookup.
EEG = eeg_emptyset();
EEG.data    = X;
EEG.srate   = srate;
EEG.nbchan  = size(X, 1);
EEG.pnts    = size(X, 2);
EEG.trials  = 1;
EEG.xmin    = 0;
EEG.xmax    = (EEG.pnts - 1) / srate;
EEG.setname = setname;
for i = 1:EEG.nbchan
    EEG.chanlocs(i).labels = labels{i};
    EEG.chanlocs(i).type   = 'EEG';
end
EEG = eeg_checkset(EEG);
end
