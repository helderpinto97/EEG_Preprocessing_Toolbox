function [O, p, lo, hi] = src_boot(X, trip, nBoot, seed, block)
% SRC_BOOT  O-information of triplets with a percentile bootstrap.
%
%   [O, p, lo, hi] = src_boot(X, trip, nBoot, seed, block)
%
% X is parcels x samples, trip a k x 3 list of triplets. The bootstrap
% resamples blocks of BLOCK consecutive samples with replacement (moving
% block bootstrap). BLOCK = 1 resamples single samples, which is valid only
% for white signals; filtered or autocorrelated signals need longer blocks.
% p is the two-sided p-value for O = 0, lo and hi the 95% interval.

if nargin < 5, block = 1; end
O = src_oinfo3(corrcoef(X'), trip);
rng(seed + 999);
Tn = size(X, 2);
nb = floor(Tn / block);
B  = zeros(size(trip, 1), nBoot);
for b = 1:nBoot
    starts = randi(Tn - block + 1, nb, 1);
    idx = reshape(starts + (0:block-1), 1, []);
    B(:, b) = src_oinfo3(corrcoef(X(:, idx)'), trip);
end
p  = min(1, 2 * min(mean(B <= 0, 2), mean(B >= 0, 2)));
lo = prctile(B, 2.5, 2);
hi = prctile(B, 97.5, 2);
end
