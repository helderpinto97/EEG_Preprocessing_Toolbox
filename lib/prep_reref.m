function [EEG, EEGica, qc] = prep_reref(EEG, EEGica, cfg)
% PREP_REREF  Apply cfg.reref to both filter branches.
%
%   [] average | 'none' keep the existing reference | 'Cz' | {'M1','M2'}
%
% Both copies get the same reference, so the ICA weights estimated on
% EEGica remain valid on EEG. Named reference channels are removed.

ref = cfg.reref;
if (ischar(ref) || (isstring(ref) && isscalar(ref))) && ismember(lower(char(ref)), {'none','off'})
    qc.reref = "none";
    qc.nchan_reref = EEG.nbchan;
    return
end

if isempty(ref)
    idx = [];
    qc.reref = "average";
else
    if ischar(ref) || isstring(ref), ref = cellstr(ref); end
    if ~iscellstr(ref)
        error('prep_reref:badRef', ...
            'cfg.reref must be [] for average, ''none'', or a channel label / cell array of labels.');
    end
    labels    = {EEG.chanlocs.labels};
    [tf, idx] = ismember(lower(ref), lower(labels));
    if ~all(tf)
        error('prep_reref:missingRef', ...
            ['Reference channel(s) %s not in the data. They may have been dropped by\n' ...
             'cfg.nonEEG or rejected as bad channels. Available: %s'], ...
            strjoin(compose('"%s"', string(ref(~tf))), ', '), strjoin(labels, ', '));
    end
    qc.reref = string(strjoin(ref, '|'));
end
EEG    = pop_reref(EEG,    idx);
EEGica = pop_reref(EEGica, idx);
qc.nchan_reref = EEG.nbchan;
end
