function X = sim_match(X, srate, keep, cfg)
% SIM_MATCH  Apply the non-cleaning steps of the pipeline to a channels x samples
% matrix: the analysis band-pass (same call as prep_subject), the channels
% the pipeline kept (indices KEEP), and its reference.
%
% Used on the ground truth and the contaminated input, so they can be
% compared sample by sample with the pipeline output.
E = sim_eegset(X, srate, arrayfun(@(i) sprintf('c%d', i), 1:size(X,1), 'uni', 0), 'match');
[~, E] = evalc('pop_eegfiltnew(E, ''locutoff'', cfg.hpAnalysis, ''hicutoff'', cfg.lp)');
X = double(E.data(keep, :));
if isempty(cfg.reref)
    X = X - mean(X, 1);                         % average reference
elseif ~(ischar(cfg.reref) && ismember(lower(cfg.reref), {'none','off'}))
    error('sim_match:reref', ...
        'Only average or no reference is supported here, not "%s".', ...
        strjoin(cellstr(cfg.reref), ','));
end
end
