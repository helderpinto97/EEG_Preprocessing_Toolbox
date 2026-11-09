function F = src_pc1(K, lab, nPar, Cy)
% SRC_PC1  Spatial filter of each parcel: its first principal component.
%
%   F = src_pc1(K, lab, nPar, Cy)
%
% K is the inverse operator (sources x channels), lab the parcel of each
% source, Cy the data covariance. F*Y gives one time series per parcel:
% the first principal component of the source time courses inside it.

F = zeros(nPar, size(K, 2));
for p = 1:nPar
    Kp = K(lab == p, :);
    [V, e] = eig(Kp * Cy * Kp', 'vector');
    [~, k] = max(e);
    F(p, :) = V(:, k)' * Kp;
end
end
