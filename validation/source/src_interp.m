function W = src_interp(from, to, centre)
% SRC_INTERP  Natural-neighbour interpolation matrix between electrode sets.
%
%   W = src_interp(from, to, centre)
%
% W (targets x electrodes) interpolates scalp values at the positions FROM
% to the positions TO, on a polar projection of the scalp around CENTRE
% (radius = angle from the top). Used to put the template lead field at
% the exact 10-10 sites; the HydroCel cap has no electrode at Cz.

proj = @(P) polar2d(P - centre);
F = scatteredInterpolant(proj(from), zeros(size(from, 1), 1), 'natural', 'none');
q = proj(to);
W = zeros(size(to, 1), size(from, 1));
for k = 1:size(from, 1)
    F.Values = double((1:size(from, 1))' == k);
    W(:, k) = F(q);
end
assert(~any(isnan(W), 'all'), 'src_interp:outside', 'Target site outside the source cap.');
end

function xy = polar2d(P)
[az, el] = cart2sph(P(:, 1), P(:, 2), P(:, 3));
r  = pi/2 - el;
xy = [r .* cos(az), r .* sin(az)];
end
