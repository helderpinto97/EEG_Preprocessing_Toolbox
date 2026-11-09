function tests = test_src_oinfo3
% Checks src_oinfo3 against the general definition of O-information.
%   runtests('validation/source/test_src_oinfo3')
tests = functiontests(localfunctions);
end

function testMatchesDefinition(t)
rng(1);
A = randn(3); C = A*A' + eye(3);
D = diag(1 ./ sqrt(diag(C)));
verifyEqual(t, src_oinfo3(D*C*D, [1 2 3]), oinfo_def(C), 'AbsTol', 1e-12);
end

function testKnownSigns(t)
% Common driver gives redundancy, a sum of two independent sources synergy,
% independent sources zero. Values match the comments in src_config.
a = 2; Cr = a^2*ones(3) + eye(3);
b = 0.5; Cs = [1 0 1; 0 1 1; 1 1 2 + b^2];
verifyEqual(t, oinfo_def(Cr),  0.40, 'AbsTol', 0.01);
verifyEqual(t, oinfo_def(Cs), -0.51, 'AbsTol', 0.01);
verifyEqual(t, oinfo_def(eye(3)), 0, 'AbsTol', 1e-12);
end

function O = oinfo_def(C)
% (n-2) H(X) + sum_j [H(X_j) - H(X_-j)], Gaussian entropies.
n = size(C, 1);
H = @(S) 0.5 * log((2*pi*exp(1))^size(S, 1) * det(S));
O = (n - 2) * H(C);
for j = 1:n
    rest = setdiff(1:n, j);
    O = O + H(C(j, j)) - H(C(rest, rest));
end
end
