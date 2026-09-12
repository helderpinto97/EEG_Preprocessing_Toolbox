function T = prep_qc_merge(outDir, qcFile)

if nargin < 2 || isempty(qcFile), qcFile = fullfile(outDir, 'qc_log.csv'); end

qcDir = fullfile(outDir, 'qc');
d     = dir(fullfile(qcDir, '*.mat'));

rows = {};
for k = 1:numel(d)
    try
        S = load(fullfile(qcDir, d(k).name), 'qc');
        rows{end+1} = S.qc;
    catch ME
        % A truncated or unreadable file costs one row, not the whole log.
        warning('prep_qc:badFile', 'Skipping %s: %s', d(k).name, ME.message);
    end
end

if isempty(rows)
    warning('prep_qc:noRows', 'No QC files found in %s', qcDir);
    T = table();
    return
end

% Union of field names in first-seen order, so columns stay stable as new QC
% fields are introduced.
fn    = cellfun(@fieldnames, rows, 'UniformOutput', false);
names = unique(vertcat(fn{:}), 'stable');

T = table();
for j = 1:numel(names)
    vals = cell(numel(rows), 1);
    for k = 1:numel(rows)
        if isfield(rows{k}, names{j})
            vals{k} = rows{k}.(names{j});
        else
            vals{k} = missing;
        end
    end
    T.(names{j}) = combine_column(vals);
end

if ismember('subject', T.Properties.VariableNames)
    T = sortrows(T, 'subject');
end

writetable(T, qcFile);
end

% -------------------------------------------------------------------------
function col = combine_column(vals)
% Concatenate one column across rows, filling gaps.
%
% [logical; missing] is the one combination MATLAB refuses outright, so
% logicals are demoted to double first, which is what writetable does to
% them anyway. Empty values become missing so they do not silently vanish
% from a vertcat.
for k = 1:numel(vals)
    v = vals{k};
    if islogical(v)
        vals{k} = double(v);
    elseif isempty(v) && ~isa(v, 'missing')
        vals{k} = missing;
    elseif ~isscalar(v) && ~isstring(v) && ~ischar(v)
        vals{k} = missing;          % non-scalar QC values are not columns
    elseif ischar(v)
        vals{k} = string(v);
    end
end

try
    col = vertcat(vals{:});
catch
    % A field that was numeric for one subject and text for another cannot
    % be reconciled numerically. Fall back to text rather than drop the row.
    col = strings(numel(vals), 1);
    for k = 1:numel(vals)
        if isa(vals{k}, 'missing'), col(k) = missing;
        else,                       col(k) = string(vals{k});
        end
    end
end
end
