function qc = prep_qc_row(base, env)
% PREP_QC_ROW  The first columns of a QC row: subject, time, software.
%
%   qc = prep_qc_row(base)        subject and datetime only
%   qc = prep_qc_row(base, env)   plus the versions prep_env recorded
%
% Successful rows (prep_subject) and failed rows (run_preprocessing) both
% start here, so they carry the same identity and version columns. The
% failed rows are the ones that most need to say which version made them.

qc = struct('subject', string(base), ...
            'datetime', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
if nargin < 2 || isempty(env), return; end
f = fieldnames(env);
for k = 1:numel(f), qc.(f{k}) = env.(f{k}); end
end
