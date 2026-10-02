function T = run_preprocessing(cfgIn)
% RUN_PREPROCESSING  Automated EEG preprocessing (EEGLAB). Batch entry point.
%
%   run_preprocessing()                      defaults from prep_config
%   run_preprocessing('config/my_study.m')   defaults + that study's overrides
%   run_preprocessing(struct('lp',100))      defaults + inline overrides
%   T = run_preprocessing(...)               returns the QC table
%
% Requires EEGLAB with the clean_rawdata, ICLabel, firfilt and dipfit
% plugins, and optionally zapline-plus.

if nargin < 1, cfgIn = struct(); end
addpath(fullfile(fileparts(mfilename('fullpath')), 'lib'));   % not genpath

cfg = prep_config(cfgIn);
prep_checkcfg(cfg);

%% EEGLAB
if ~exist('eeglab', 'file')
    if ~isfolder(cfg.eeglabPath)
        error('run_preprocessing:noEEGLAB', ...
              'EEGLAB is not on the path and not at %s.', cfg.eeglabPath);
    end
    addpath(cfg.eeglabPath);
end
try
    evalc('eeglab nogui');
catch ME
    error('run_preprocessing:eeglabStart', 'EEGLAB failed to start: %s', ME.message);
end
if ~isfolder(cfg.outDir), mkdir(cfg.outDir); end

% Software versions go in every QC row, not in cfg, so config.mat can be
% fed back in unchanged.
env = prep_env(cfg.extraToolboxes);
fprintf('MATLAB %s | EEGLAB %s (%s)\n', env.matlab, env.eeglab, env.eeglab_release);
fprintf('plugins:   %s\n', env.eeglab_plugins);
fprintf('toolboxes: %s\n', env.toolboxes);

% Fail now, not on every subject, if the reader for this format is missing.
[~, ~, wantExt] = fileparts(cfg.fileExt);
reader = prep_load('reader', wantExt);
if isempty(which(reader))
    error('run_preprocessing:noReader', ...
        ['cfg.fileExt is "%s", which is read with %s, and that function is\n' ...
         'not on the path. For pop_fileio, install the Fileio plugin via\n' ...
         'EEGLAB > File > Manage EEGLAB extensions, or use .set input.'], ...
         cfg.fileExt, reader);
end
prep_saveconfig(cfg, cfg.outDir);

%% Batch
files = prep_find(cfg.inDir, cfg.fileExt, cfg.recursive, cfg.outDir);
fprintf('\n%d file(s) found in %s\n\n', numel(files), cfg.inDir);

for k = 1:numel(files)
    [~, base] = fileparts(files(k).name);
    if ~cfg.overwrite && isfile(fullfile(cfg.outDir, [base '_clean.set']))
        fprintf('%-28s skipped (output exists)\n', base);
        continue
    end
    try
        qc = prep_subject(fullfile(files(k).folder, files(k).name), cfg.outDir, cfg, env);
        qc.status = "ok";
        qc.error  = "";
    catch ME
        % One failed subject never stops the batch; the full report goes
        % to <subject>_error.log and a failed row to the QC log.
        fprintf(2, 'FAILED %s : %s\n', files(k).name, ME.message);
        fid = fopen(fullfile(cfg.outDir, [base '_error.log']), 'w');
        if fid > 0
            fprintf(fid, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            fclose(fid);
        end
        msg = string(regexprep(ME.message, '\s+', ' '));
        if ~isempty(ME.identifier), msg = string(ME.identifier) + ": " + msg; end
        qc = prep_qc_row(base, env);
        qc.status = "failed";
        qc.error  = msg;
    end
    prep_qc_write(qc, cfg.outDir);          % one file per subject, crash-safe
end

% One merge at the end. prep_qc_merge can also be rerun by hand.
T = prep_qc_merge(cfg.outDir, fullfile(cfg.outDir, 'qc_log.csv'));
if ~isempty(T) && ismember('status', T.Properties.VariableNames)
    fprintf('\n%d subject(s) logged, %d failed.\n', height(T), sum(T.status == "failed"));
end
fprintf('\nDone. Cleaned files and qc_log.csv are in %s\n', cfg.outDir);
end
