function P = beat_power(X, srate, range, rp)
% BEAT_POWER  Log mean power of each channel in band RANGE within each heart
% period (R peak samples RP; period n runs from rp(n) to rp(n+1)-1).
%
%   P = beat_power(X, srate, range, rp)      P is beats x channels
E = sim_eegset(X, srate, arrayfun(@(i) sprintf('c%d', i), 1:size(X,1), 'uni', 0), 'band');
[~, E] = evalc('pop_eegfiltnew(E, ''locutoff'', range(1), ''hicutoff'', range(2))');
Y = double(E.data).^2;
P = zeros(numel(rp) - 1, size(X, 1));
for b = 1:numel(rp) - 1
    P(b, :) = log(mean(Y(:, rp(b):rp(b+1)-1), 2));
end
end
