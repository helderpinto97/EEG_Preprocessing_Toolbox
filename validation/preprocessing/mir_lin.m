function [mir, txy, tyx, inst] = mir_lin(x, y, p)
% MIR_LIN  Linear Gaussian Mutual Information Rate (nats) of x and y, order
% p, and its decomposition MIR = TE x->y + TE y->x + instantaneous term,
% from least-squares regressions on the past (restricted: own past; full:
% past of both).
%
%   [mir, txy, tyx, inst] = mir_lin(x, y, p)
%
% Under no coupling x -> y, 2 (N-p) txy is asymptotically chi-square with p
% degrees of freedom (N samples), so p_value = 1 - gammainc((N-p)*txy, p/2).
x = x(:); y = y(:);
N  = numel(y);
L  = @(v) cell2mat(arrayfun(@(k) v(p+1-k:N-k), 1:p, 'uni', 0));
X0 = x(p+1:N); Y0 = y(p+1:N);
o1 = ones(N-p, 1);
res = @(t, Z) t - Z * (Z \ t);
ex  = res(X0, [o1 L(x)]);            % own past
ey  = res(Y0, [o1 L(y)]);
Zf  = [o1 L(x) L(y)];                % past of both
ux  = res(X0, Zf);
uy  = res(Y0, Zf);
mir  = 0.5 * log(var(ex) * var(ey) / det(cov(ux, uy)));
txy  = 0.5 * log(var(ey) / var(uy));
tyx  = 0.5 * log(var(ex) / var(ux));
inst = mir - txy - tyx;
end
