function [EEG, EEGica, qc] = prep_reref(EEG, EEGica, cfg)
% PREP_REREF  Apply the configured reference to both filter branches.
%
%   cfg.reref = []                 average reference
%   cfg.reref = 'none'             leave the existing reference alone
%   cfg.reref = 'Cz'               single channel
%   cfg.reref = {'M1','M2'}        linked mastoids
%
% Applied to BOTH branches with the same channels, because the ICA weights
% are estimated on EEGica and transferred to EEG: a different reference on
% the two copies would make that transfer invalid.
%
% Referencing to named channels REMOVES them (pop_reref's 'keepref' default
% is 'off'), so the channel count drops by the number of reference
% channels. Average referencing keeps every channel but costs one rank.

ref = cfg.reref;

%% none -------------------------------------------------------------------
if (ischar(ref) || (isstring(ref) && isscalar(ref))) && ...
        ismember(lower(char(ref)), {'none','off'})
    qc.reref       = "none";
    qc.nchan_reref = EEG.nbchan;
    return
end

%% average ----------------------------------------------------------------
if isempty(ref)
    EEG    = pop_reref(EEG,    []);
    EEGica = pop_reref(EEGica, []);
    qc.reref       = "average";
    qc.nchan_reref = EEG.nbchan;
    return
end

%% named channels ---------------------------------------------------------
if ischar(ref) || isstring(ref), ref = cellstr(ref); end
if ~iscellstr(ref)
    error('prep_reref:badRef', ...
        ['cfg.reref must be [] for average, ''none'' to leave the data\n' ...
         'alone, or a channel label / cell array of labels.']);
end

labels    = {EEG.chanlocs.labels};
[tf, idx] = ismember(lower(ref), lower(labels));
if ~all(tf)
    % The usual cause is that the channel was rejected as bad earlier, or
    % dropped as non-EEG, so say so rather than just "not found". Every
    % missing label at once, so a linked-mastoid pair that lost both is one
    % error rather than two runs.
    error('prep_reref:missingRef', ...
        ['Reference channel(s) %s not in the data.\n' ...
         'They may have been dropped by cfg.nonEEG, or rejected as bad\n' ...
         'channels before this step. Available: %s'], ...
        strjoin(compose('"%s"', string(ref(~tf))), ', '), ...
        strjoin(labels, ', '));
end

EEG    = pop_reref(EEG,    idx);
EEGica = pop_reref(EEGica, idx);

qc.reref       = string(strjoin(ref, '|'));
qc.nchan_reref = EEG.nbchan;
end
