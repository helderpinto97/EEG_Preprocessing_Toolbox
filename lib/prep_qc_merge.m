function T = prep_qc_merge(outDir, qcFile)
% PREP_QC_MERGE  Merge the per-subject QC files into one table and CSV.
%
%   T = prep_qc_merge(outDir)            writes <outDir>/qc_log.csv
%   T = prep_qc_merge(outDir, qcFile)
%
% Columns are the union of all fields in first-seen order; a missing value
% becomes missing, and a column mixing numbers and text becomes text.

if nargin < 2 || isempty(qcFile), qcFile = fullfile(outDir, 'qc_log.csv'); end
qcDir = fullfile(outDir, 'qc');
d = dir(fullfile(qcDir, '*.mat'));

rows = {};
for k = 1:numel(d)
    try
        S = load(fullfile(qcDir, d(k).name), 'qc');
        rows{end+1} = S.qc; %#ok<AGROW>
    catch ME
        warning('prep_qc:badFile', 'Skipping %s: %s', d(k).name, ME.message);
    end
end
T = table();
if isempty(rows)
    warning('prep_qc:noRows', 'No QC files found in %s', qcDir);
    return
end

fn    = cellfun(@fieldnames, rows, 'UniformOutput', false);
names = unique(vertcat(fn{:}), 'stable');
for j = 1:numel(names)
    vals = cellfun(@(r) field_or_missing(r, names{j}), rows, 'UniformOutput', false);
    T.(names{j}) = combine_column(vals);
end
if ismember('subject', T.Properties.VariableNames)
    T = sortrows(T, 'subject');
end
writetable(T, qcFile);
end

function v = field_or_missing(s, name)
if isfield(s, name), v = s.(name); else, v = missing; end
end

function col = combine_column(vals)
% Logicals become double ([logical; missing] does not concatenate), text
% becomes string, and empty or non-scalar values become missing.
for k = 1:numel(vals)
    v = vals{k};
    if islogical(v)
        vals{k} = double(v);
    elseif (isempty(v) && ~isa(v, 'missing')) || (~isscalar(v) && ~isstring(v) && ~ischar(v))
        vals{k} = missing;
    elseif ischar(v)
        vals{k} = string(v);
    end
end
try
    col = vertcat(vals{:});
catch
    col = strings(numel(vals), 1);
    for k = 1:numel(vals)
        if ~isa(vals{k}, 'missing'), col(k) = string(vals{k}); else, col(k) = missing; end
    end
end
end
