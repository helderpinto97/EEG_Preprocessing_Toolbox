function cfg = example_study()
% EXAMPLE_STUDY  A per-study config, holding overrides only.
%
% Everything not listed here comes from prep_config. Keep one of these per
% study, commit it, and run:
%
%   run_preprocessing('config/example_study.m')
%
% With only the differences listed, the diff between two studies is the
% scientific difference, not 90 lines of identical defaults.

cfg.inDir  = fullfile('D:','data','study_x','raw');
cfg.outDir = fullfile('D:','data','study_x','derivatives');

cfg.lp     = 100;              % gamma of interest, so keep the band
cfg.events = {'S1','S2'};    % epoch around these events 
cfg.window = [-0.2 0.8];
end
