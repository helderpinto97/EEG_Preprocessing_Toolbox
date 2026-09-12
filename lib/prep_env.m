function env = prep_env(extraToolboxes)
% PREP_ENV  Capture software versions for the QC log.
%
% Returned fields are all scalar strings, so the struct drops straight into
% struct2table and becomes columns in qc_log.csv. Called once per batch by
% run_preprocessing.m; the result is copied into every QC row.
%
% clean_rawdata and ICLabel have both changed default behaviour between
% releases, and MATLAB has no lockfile. Without this, "which version
% produced this derivative" has no answer.


if nargin < 1, extraToolboxes = {}; end

%% MATLAB
env.matlab = string(version('-release'));
needed = { 'Signal_Toolbox',           'signal',   true  ; ...  % filtering, resampling, clean_rawdata
           'Statistics_Toolbox',       'stats',    true ; ...  % misc
           'Distrib_Computing_Toolbox','parallel', false };     % optional, parfor

missing = strings(0);
held    = strings(0);
for k = 1:size(needed,1)
    feat     = needed{k,1};
    required = needed{k,3};
    ok       = license('test', feat);

    if ok && required
        ok = license('checkout', feat);   % reserve it for the whole session
        if ok, held(end+1) = string(feat); end %#ok<AGROW>
    end

    env.("has_" + needed{k,2}) = ok;
    if ~ok
        missing(end+1) = string(needed{k,2}); %#ok<AGROW>
        if required
            error('prep_env:licence', ...
                ['Could not check out %s, which this pipeline cannot run\n' ...
                 'without. On a shared network licence this usually means the\n' ...
                 'pool is full; try again later. Failing now rather than\n' ...
                 'part-way through a batch.'], feat);
        end
    end
end
env.licences_held = join_or(held, "none");

if ~isempty(missing)
    warning('prep_env:toolbox', 'Missing optional MATLAB toolbox(es): %s', ...
            strjoin(missing, ', '));
end

%% EEGLAB
if ~exist('eeglab','file')
    error('prep_env:noEEGLAB', 'EEGLAB is not on the MATLAB path.');
end
env.eeglab         = "unknown";
env.eeglab_release = "unknown";
try
    [v, ~, rel]        = eeg_getversion();
    env.eeglab         = string(v);
    env.eeglab_release = string(rel);
catch
    % older EEGLAB releases return fewer outputs; the fields stay "unknown"
end
env.eeglab_commit = git_id(fileparts(which('eeglab')));

% Plugins
pluginDir = fullfile(fileparts(which('eeglab')), 'plugins');
d = dir(pluginDir);
d = d([d.isdir] & ~startsWith({d.name}, '.'));

if ~isempty(d)
    % Top level first. A plugin normally has its .m files right there, so
    % the recursive walk almost never runs. Asking '**' straight away
    % enumerates every plugin subtree at startup, which on a synced folder
    % is thousands of entries to answer a yes or no.
    hasCode = arrayfun(@(x) has_code(fullfile(pluginDir, x.name)), d);
    if any(~hasCode)
        warning('prep_env:emptyPlugin', 'Empty plugin folder(s) ignored: %s', ...
                strjoin({d(~hasCode).name}, ', '));
    end
    d = d(hasCode);
end
env.eeglab_plugins = string(strjoin(sort({d.name}), '|'));

% Warn loudly about the ones this pipeline cannot run without. Checked by
% resolving a function each one provides, not by matching a folder name: an
% empty or partial install still matches the name and the check would pass.
required = { 'clean_rawdata', 'clean_artifacts' ; ...
             'ICLabel',       'pop_iclabel'     ; ...
             'firfilt',       'pop_eegfiltnew'  };
for k = 1:size(required,1)
    if isempty(which(required{k,2}))
        warning('prep_env:plugin', ...
            ['Required plugin "%s" is not usable: %s does not resolve.\n' ...
             'Install via EEGLAB > File > Manage EEGLAB extensions.'], ...
            required{k,1}, required{k,2});
    end
end

% Fileio reads every format except .set: edf, bdf, vhdr, cnt. Not required
% for a .set-only batch, so this records and warns; run_preprocessing turns
% it into an error when cfg.fileExt needs it. Otherwise the failure lands
% per subject at import, well into a batch, instead of at startup.
env.has_fileio = ~isempty(which('pop_fileio'));
if ~env.has_fileio
    warning('prep_env:fileio', ...
        ['Fileio plugin not found, so only .set input can be read.\n' ...
         'Install it via EEGLAB > File > Manage EEGLAB extensions if you\n' ...
         'need edf, bdf, vhdr or cnt.']);
end

% ICLabel bundles matconvnet as a git submodule. A ZIP download or a plain
% clone leaves it empty and pop_iclabel then fails at runtime, not at
% startup. Cheaper to catch it here.
icl = which('pop_iclabel');
if ~isempty(icl)
    mcn = fullfile(fileparts(icl), 'matconvnet');
    if ~isfolder(mcn) || numel(dir(mcn)) <= 2
        warning('prep_env:matconvnet', ...
            ['ICLabel''s matconvnet folder is missing or empty. Reinstall\n' ...
             'ICLabel through the EEGLAB plugin manager, or clone with\n' ...
             '--recurse-submodules.']);
    end
end

%% Other toolboxes
% Anything else you want pinned: FieldTrip, RELAX .....
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

% -------------------------------------------------------------------------
function id = git_id(p)
% Short commit hash if P is a git repository, "nogit" otherwise.
% .git is a FILE rather than a folder in worktrees and submodules, so both
% are accepted. Needs git on the system PATH; absence is not an error, just
% less detail in the record of what ran.
id = "nogit";
if isempty(p), return; end
g = fullfile(p, '.git');
if ~isfolder(g) && ~isfile(g), return; end
[st, out] = system(sprintf('git -C "%s" rev-parse --short HEAD', p));
if st == 0
    id = string(strtrim(out));
end
end

% -------------------------------------------------------------------------
function s = has_code(p)
% Does this plugin folder contain any MATLAB code? Checked at the top level
% first, and only walked recursively when that finds nothing.
s = ~isempty(dir(fullfile(p, '*.m')));
if ~s
    s = ~isempty(dir(fullfile(p, '**', '*.m')));
end
end

% -------------------------------------------------------------------------
function s = join_or(parts, dflt)
% Pipe-joined, or DFLT when there is nothing to join. A blank cell in the QC
% log reads the same as a column that was never filled in.
s = strjoin(parts, '|');
if s == "", s = dflt; end
end
