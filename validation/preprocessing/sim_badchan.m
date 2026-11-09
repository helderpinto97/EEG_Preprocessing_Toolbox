function bad = sim_badchan(clean, n, seed)
% SIM_BADCHAN  Replace N channels of the clean EEG with bad-channel signals.
%
%   bad = sim_badchan(clean, n, seed)
%
% Unlike the other artifacts, a bad channel is not added to the EEG: the
% electrode no longer records it. Each chosen channel is replaced by one of
% four failure types, taken in this order:
%   noisy          white noise at 5 times the median channel SD
%   flat           a constant (a disconnected electrode)
%   uncorrelated   1/f noise at a normal amplitude, but unrelated to the
%                  neighbours (the case only the correlation criterion sees)
%   intermittent   the true signal, with bursts of large noise 20% of the time
%
% BAD is a struct:
%   chans   indices of the replaced channels
%   types   their failure types
%   data    n x samples replacement signals
% With the severity index as N, the levels mean 1, 2, 3 and 4 bad channels
% out of 32; 4 is above the 10% limit of the pipeline, so that level tests
% that the pipeline stops rather than cleaning a recording it cannot trust.

types = {'noisy', 'flat', 'uncorrelated', 'intermittent'};
rng(seed);
X    = double(clean.data);
pnts = size(X, 2);
sd   = median(std(X, 0, 2));

bad.chans = randperm(size(X, 1), n);
bad.types = types(mod(0:n-1, numel(types)) + 1);
bad.data  = zeros(n, pnts);
for k = 1:n
    switch bad.types{k}
        case 'noisy'
            bad.data(k, :) = 5 * sd * randn(1, pnts);
        case 'flat'
            bad.data(k, :) = 0;
        case 'uncorrelated'
            bad.data(k, :) = sd * pinknoise(pnts);
        case 'intermittent'
            on = bursts(pnts, clean.srate);
            bad.data(k, :) = X(bad.chans(k), :) + on .* (8 * sd * randn(1, pnts));
    end
end
end

function x = pinknoise(pnts)
F = fft(randn(1, pnts));
f = [1, 1:floor(pnts/2), floor((pnts-1)/2):-1:1];   % |frequency| index per bin
F = F ./ sqrt(f(1:pnts));
F(1) = 0;
x = real(ifft(F));
x = x / std(x);
end

function on = bursts(pnts, srate)
% Noise bursts of 0.5-2 s covering about 20% of the recording.
on = zeros(1, pnts);
t  = round(srate * rand);
while t < pnts
    len = round(srate * (0.5 + 1.5 * rand));
    on(t + 1 : min(pnts, t + len)) = 1;
    t = t + round(len / 0.2 * (0.5 + rand));
end
end
