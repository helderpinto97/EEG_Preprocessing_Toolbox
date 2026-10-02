function r = prep_rowcorr(A, B)
% PREP_ROWCORR  Pearson correlation of every row of A with every row of B.
%
%   r = prep_rowcorr(A, B)   size(A,1)-by-size(B,1)
%
% Base MATLAB only. A constant row correlates 0 with everything rather than
% giving NaN.
A = A - mean(A, 2);  A = A ./ max(sqrt(sum(A.^2, 2)), eps);
B = B - mean(B, 2);  B = B ./ max(sqrt(sum(B.^2, 2)), eps);
r = A * B';
end
