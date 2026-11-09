function [P, srcIdx, off, nPatch] = src_patches(A, H, src)
% SRC_PATCHES  The true source of each parcel in the New York Head.
%
%   [P, srcIdx, off, nPatch] = src_patches(A, H, src)
%
% A patch of New York Head sources of the parcel within src.patchRadius of
% the source nearest the parcel centre, all with the same time course.
% P (head sources x parcels) maps parcel signals to head sources, srcIdx is
% the central source, off its distance to the parcel centre (mm), nPatch the
% number of sources in the patch.

nPar = numel(A.names);
off = zeros(nPar, 1); srcIdx = zeros(nPar, 1); nPatch = zeros(nPar, 1);
P = sparse(size(H.ny.pos, 1), nPar);
for p = 1:nPar
    c = find(A.ny == p);
    [off(p), k] = min(vecnorm(H.ny.pos(c, :) - A.centre(p, :), 2, 2));
    srcIdx(p) = c(k);
    patch = c(vecnorm(H.ny.pos(c, :) - H.ny.pos(c(k), :), 2, 2) <= src.patchRadius);
    P(patch, p) = 1; %#ok<SPRIX>
    nPatch(p) = numel(patch);
end
end
