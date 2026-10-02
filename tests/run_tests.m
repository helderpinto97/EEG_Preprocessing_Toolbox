function results = run_tests(varargin)
% Test Pipeline
%   run_tests              everything
%   run_tests('unit')      unit tests only, no ICA. Seconds, not minutes.
%   run_tests('pipeline')  end-to-end batch tests only
%   run_tests('name', 'rank')   only tests whose file matches 'rank'

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);                      % run_preprocessing lives at the toolbox root
addpath(fullfile(root, 'lib'));
addpath(fullfile(root, 'tests'));
addpath(fullfile(root, 'config'));  % so a test can run a real study file

if ~exist('eeglab', 'file')
    p = fullfile(root, 'lib', 'toolboxes', 'eeglab');
    assert(isfolder(p), 'run_tests:noEEGLAB', ...
        'EEGLAB not found at %s. The suite needs it for eeg_emptyset and pop_*.', p);
    addpath(p);
    evalc('eeglab nogui');
end

sel = 'all';
if nargin >= 1 && ~strcmpi(varargin{1}, 'name'), sel = lower(varargin{1}); end

switch sel
    case 'unit'
        files = setdiff(test_files(root), {'test_pipeline'});
    case 'pipeline'
        files = {'test_pipeline'};
    case 'all'
        files = test_files(root);
    otherwise
        error('run_tests:badSelector', 'Unknown selector "%s".', sel);
end

if nargin >= 2 && strcmpi(varargin{end-1}, 'name')
    files = files(contains(files, varargin{end}));
end
assert(~isempty(files), 'run_tests:noTests', 'No test files matched.');

fprintf('running %d test file(s): %s\n\n', numel(files), strjoin(files, ', '));
suite = [];
for k = 1:numel(files)
    suite = [suite, matlab.unittest.TestSuite.fromFile( ...
        fullfile(root, 'tests', [files{k} '.m']))]; 
end

runner  = matlab.unittest.TestRunner.withTextOutput();
results = runner.run(suite);

fprintf('\n%s\n', repmat('-', 1, 60));
fprintf('%d passed | %d failed | %d incomplete | %.1f s\n', ...
        nnz([results.Passed]), nnz([results.Failed]), ...
        nnz([results.Incomplete]), sum([results.Duration]));

if any([results.Failed])
    fprintf(2, '\nFAILED:\n');
    for r = results([results.Failed]), fprintf(2, '  %s\n', r.Name); end
    if isdeployed || ~usejava('desktop'), exit(1); end
end
end


function names = test_files(root)
d = dir(fullfile(root, 'tests', 'test_*.m'));
names = erase({d.name}, '.m');
end
