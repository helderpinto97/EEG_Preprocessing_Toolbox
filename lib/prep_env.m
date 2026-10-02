function env = prep_env(extraToolboxes)
% PREP_ENV  Software versions for the QC log, and startup checks.
%
% All fields are scalar strings or logicals, so they become columns of
% qc_log.csv. Required licences are checked out now rather than failing
% part-way through a batch.

if nargin < 1, extraToolboxes = {}; end

%% MATLAB
env.matlab = string(version('-release'));
needed = {'Signal_Toolbox',            'signal',   true;    % filtering, clean_rawdata
          'Statistics_Toolbox',        'stats',    true;
          'Distrib_Computing_Toolbox', 'parallel', false};  % optional
held = strings(0); missing = strings(0);
for k = 1:size(needed, 1)
    [feat, name, required] = needed{k, :};
    ok = license('test', feat);
    if ok && required
        ok = license('checkout', feat);     % reserve it for the session
        if ok, held(end+1) = feat; end %#ok<AGROW>
    end
    env.("has_" + name) = ok;
    if ~ok
        if required
            error('prep_env:licence', ...
                'Could not check out %s, which the pipeline needs (the licence pool may be full).', feat);
        end
        missing(end+1) = name; %#ok<AGROW>
    end
end
env.licences_held = join_or(held, "none");
if ~isempty(missing)
    warning('prep_env:toolbox', 'Missing optional MATLAB toolbox(es): %s', strjoin(missing, ', '));
end

%% EEGLAB
if ~exist('eeglab', 'file')
    error('prep_env:noEEGLAB', 'EEGLAB is not on the MATLAB path.');
end
env.eeglab = "unknown"; env.eeglab_release = "unknown";
try
    [v, ~, rel] = eeg_getversion();
    env.eeglab = string(v); env.eeglab_release = string(rel);
catch
    % older releases return fewer outputs
end
eeglabDir = fileparts(which('eeglab'));
env.eeglab_commit = git_id(eeglabDir);

% Plugins: folders with MATLAB code (top level first, recursive only if needed).
pluginDir = fullfile(eeglabDir, 'plugins');
d = dir(pluginDir);
d = d([d.isdir] & ~startsWith({d.name}, '.'));
hasCode = arrayfun(@(x) ~isempty(dir(fullfile(pluginDir, x.name, '*.m'))) || ...
                        ~isempty(dir(fullfile(pluginDir, x.name, '**', '*.m'))), d);
if any(~hasCode)
    warning('prep_env:emptyPlugin', 'Empty plugin folder(s) ignored: %s', strjoin({d(~hasCode).name}, ', '));
end
env.eeglab_plugins = string(strjoin(sort({d(hasCode).name}), '|'));

% Required plugins, checked by a function each provides.
required = {'clean_rawdata', 'clean_artifacts'; 'ICLabel', 'pop_iclabel'; 'firfilt', 'pop_eegfiltnew'};
for k = 1:size(required, 1)
    if isempty(which(required{k, 2}))
        warning('prep_env:plugin', ...
            'Required plugin "%s" is not usable: %s does not resolve.\nInstall via EEGLAB > File > Manage EEGLAB extensions.', ...
            required{k, :});
    end
end

% Fileio reads everything except .set; run_preprocessing stops if it is needed.
env.has_fileio = ~isempty(which('pop_fileio'));
if ~env.has_fileio
    warning('prep_env:fileio', 'Fileio plugin not found, so only .set input can be read.');
end

% ICLabel ships matconvnet as a git submodule, empty in a plain download.
icl = which('pop_iclabel');
if ~isempty(icl)
    mcn = fullfile(fileparts(icl), 'matconvnet');
    if ~isfolder(mcn) || numel(dir(mcn)) <= 2
        warning('prep_env:matconvnet', ...
            'The matconvnet folder of ICLabel is missing or empty; reinstall ICLabel via the plugin manager.');
    end
end

%% Other toolboxes to pin
parts = strings(0);
for k = 1:numel(extraToolboxes)
    p = extraToolboxes{k};
    if ~isfolder(p)
        warning('prep_env:toolboxPath', 'Not a folder: %s', p);
        continue
    end
    [~, name] = fileparts(strip(p, 'right', filesep));
    parts(end+1) = name + "@" + git_id(p); %#ok<AGROW>
end
env.toolboxes = join_or(parts, "none");
end

%% Auxiliary functions
function id = git_id(p)
% Short commit hash if P is a git repository (.git folder or file), else "nogit".
id = "nogit";
if isempty(p) || ~(isfolder(fullfile(p, '.git')) || isfile(fullfile(p, '.git'))), return, end
[st, out] = system(sprintf('git -C "%s" rev-parse --short HEAD', p));
if st == 0, id = string(strtrim(out)); end
end

function s = join_or(parts, dflt)
s = strjoin(parts, '|');
if s == "", s = dflt; end
end
