function tests = test_prep_env
% prep_env had no coverage, and a deleted local function (git_id) went
% unnoticed until the slow end-to-end tests ran. These are cheap and catch
% that class of breakage immediately.
tests = functiontests(localfunctions);
end

function env = quiet_env(varargin)
c = prep_nowarn(); %#ok<NASGU>
env = prep_quiet(@prep_env, varargin{:});
end

function assume_licence(t)
% prep_env deliberately errors when the Signal Toolbox cannot be checked
% out. On a shared network licence that is an environment state, not a code
% fault, so skip rather than fail.
assumeTrue(t, license('test', 'Signal_Toolbox') == 1 && ...
              license('checkout', 'Signal_Toolbox') == 1, ...
              'Signal Processing Toolbox licence unavailable');
end

function testRunsAndReturnsDocumentedFields(t)
% The smoke test that would have caught the missing git_id.
assume_licence(t);
env = quiet_env({});
for f = {'matlab','eeglab','eeglab_release','eeglab_commit','eeglab_plugins', ...
         'toolboxes','licences_held','has_signal','has_stats','has_parallel'}
    verifyTrue(t, isfield(env, f{1}), sprintf('missing field "%s"', f{1}));
end
end

function testAllFieldsAreScalar(t)
% Every field becomes a column in qc_log.csv, so a non-scalar would break
% the QC merge for every subject in the batch.
assume_licence(t);
env = quiet_env({});
f = fieldnames(env);
for k = 1:numel(f)
    verifyTrue(t, isscalar(env.(f{k})), ...
        sprintf('field "%s" is not scalar', f{k}));
end
end

function testGitIdResolvesThisRepository(t)
% Exercises the local git_id through extraToolboxes. This toolbox is itself
% a git repository, so the hash must come back rather than "nogit".
assume_licence(t);
root = fileparts(fileparts(mfilename('fullpath')));
assumeTrue(t, isfolder(fullfile(root, '.git')), 'not a git checkout');
env = quiet_env({root});
verifyTrue(t, contains(env.toolboxes, '@'));
verifyFalse(t, contains(env.toolboxes, 'nogit'));
end

function testNonRepoFolderReportsNogit(t)
assume_licence(t);
d = newdir();
env = quiet_env({d});
verifyTrue(t, contains(env.toolboxes, 'nogit'));
end

function testMissingToolboxPathWarns(t)
% No warning('off') here: it would suppress the warning under test.
assume_licence(t);
verifyWarning(t, @() prep_env({'Z:\definitely\not\here'}), 'prep_env:toolboxPath');
end

function testNoExtraToolboxesReportsNone(t)
assume_licence(t);
env = quiet_env({});
verifyEqual(t, env.toolboxes, "none");
end
