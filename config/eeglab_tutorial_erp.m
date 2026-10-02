function cfg = eeglab_tutorial_erp()
% EEGLAB_TUTORIAL_ERP  The tutorial dataset, cut into epochs.
%
%   run_preprocessing('config/eeglab_tutorial_erp.m')
%
% Same recording and same cleaning as eeglab_tutorial, with epoching added,
% so the two configs differ by exactly the thing being demonstrated. The
% continuous version stays the simpler example.
%
% The recording carries two event types: 'square', the stimulus, 80 of them,
% and 'rt', the button press, 74 of them. Epoching on both is what fills the
% per-condition panels of <subject>_qc_epochs.png, which is the sheet that
% never renders on continuous data.
%
% What a correct run looks like here, for comparison when something changes:
%   30 EEG channels after EOG1 and EOG2 are dropped, no bad channels
%   rank 29 before ICA, 28 after one Eye component is removed
%   154 epochs built, none lost, 2 rejected by joint probability
%   a P300 at F4 peaking near 380 ms in the 'square' panel
%
% CAVEAT on the 'rt' condition. Its baseline runs from -200 to 0 ms before
% the button press, and the stimulus has already happened by then, so that
% window carries evoked activity rather than rest. The 'rt' trace therefore
% starts high in the global field power panel. Response-locked averaging
% wants a pre-stimulus baseline or none at all. Both types are epoched here
% to exercise the figure, not as a recommendation for how to analyse a
% response.

cfg = eeglab_tutorial();
cfg.outDir = fullfile(fileparts(cfg.outDir), 'eeglab_tutorial_erp');

cfg.events   = {'square', 'rt'};
cfg.window   = [-0.2 0.8];   % s
cfg.baseline = [-200 0];     % ms, and read the caveat above

% On this recording the amplitude criterion never fires and joint
% probability removes 2 trials of 154. Left on so the trial-budget panel
% reports a real number rather than a column of zeros.
cfg.epochReject = true;
cfg.epochThresh = 150;       % uV
cfg.epochProbSD = 5;         % SD
end
