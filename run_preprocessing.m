function T = run_preprocessing(cfgIn)
% RUN_PREPROCESSING  Automated EEG preprocessing (EEGLAB). Batch entry point.
%
%   run_preprocessing()                      defaults from prep_config
%   run_preprocessing('config/my_study.m')   defaults + that study's overrides
%   run_preprocessing(struct('lp',100))      defaults + inline overrides
%   T = run_preprocessing(...)               returns the QC table
%
% Parameters live in lib/prep_config.m, not here, so a study is a small
% override file that can be committed and diffed rather than an edited copy
% of this script. See config/example_study.m.
%
% Requires EEGLAB with the clean_rawdata, ICLabel, firfilt and dipfit
% plugins, and optionally zapline-plus.

if nargin < 1, cfgIn = struct(); end

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'lib'));   % NOT genpath: eeglab builds its own path

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
    error('run_preprocessing:eeglabStart', ...
          'EEGLAB failed to start: %s', ME.message);
end

if ~isfolder(cfg.outDir), mkdir(cfg.outDir); end

%% Version EEGLAB and Plugins 
% Kept out of cfg. prep_config rejects any field it does not list, so a cfg
% carrying an env field is one it would refuse, and config.mat could then not
% be fed back in to reproduce the run it documents. The environment has its
% own home in the QC log, where every row carries it.
env = prep_env(cfg.extraToolboxes);
fprintf('MATLAB %s | EEGLAB %s (%s)\n', env.matlab, env.eeglab, env.eeglab_release);
fprintf('plugins:   %s\n', env.eeglab_plugins);
fprintf('toolboxes: %s\n', env.toolboxes);

% Ask prep_load which function reads this extension, then check it is there.
% Without this the batch starts happily and fails on every subject at import,
% which on a long run means finding out well after you walked away. Asking
% prep_load rather than restating its rule is what keeps the check and the
% import in agreement.
[~, ~, wantExt] = fileparts(cfg.fileExt);
reader = prep_load('reader', wantExt);
if isempty(which(reader))
    error('run_preprocessing:noReader', ...
        ['cfg.fileExt is "%s", which is read with %s, and that function is\n' ...
         'not on the path. For pop_fileio, install the Fileio plugin via\n' ...
         'EEGLAB > File > Manage EEGLAB extensions, or use .set input.'], ...
         cfg.fileExt, reader);
end

% The parameters themselves, alongside the derivatives.
prep_saveconfig(cfg, cfg.outDir);

%% Run Batch
files  = prep_find(cfg.inDir, cfg.fileExt, cfg.recursive, cfg.outDir);
qcFile = fullfile(cfg.outDir, 'qc_log.csv');
fprintf('\n%d file(s) found in %s\n\n', numel(files), cfg.inDir);

for k = 1:numel(files)
    f         = fullfile(files(k).folder, files(k).name);
    [~, base] = fileparts(files(k).name);

    if ~cfg.overwrite && isfile(fullfile(cfg.outDir, [base '_clean.set']))
        fprintf('%-28s skipped (output exists)\n', base);
        continue
    end

    try
        qc = prep_subject(f, cfg.outDir, cfg, env);   % the pipeline, see lib/
        qc.status = "ok";
        qc.error  = "";
    catch ME
        fprintf(2, 'FAILED %s : %s\n', files(k).name, ME.message);
        fid = fopen(fullfile(cfg.outDir, [base '_error.log']), 'w');
        if fid > 0
            fprintf(fid, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            fclose(fid);
        end
        msg = string(regexprep(ME.message, '\s+', ' '));
        if ~isempty(ME.identifier), msg = string(ME.identifier) + ": " + msg; end
        % Same identity and the same env columns a successful row carries.
        % Without env here, the rows that most need "which version produced
        % this" are the ones that do not say.
        qc = struct('subject',  string(base), ...
                    'datetime', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        f = fieldnames(env);
        for j = 1:numel(f), qc.(f{j}) = env.(f{j}); end
        qc.status = "failed";
        qc.error  = msg;
    end
    prep_qc_write(qc, cfg.outDir);   % one per subject, crash-safe
end

%% Append in the end (reduce computation cost)
% Kept out of the loop so a batch costs one merge rather than one rewrite per
% subject. Rerun prep_qc_merge by hand any time, including from another
% session while a batch is still going.
T = prep_qc_merge(cfg.outDir, qcFile);
if ~isempty(T) && ismember('status', T.Properties.VariableNames)
    fprintf('\n%d subject(s) logged, %d failed.\n', height(T), sum(T.status == "failed"));
end
fprintf('\nDone. Cleaned files and qc_log.csv are in %s\n', cfg.outDir);
end
