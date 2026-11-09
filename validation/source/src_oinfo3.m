function O = src_oinfo3(R, trip)
% SRC_OINFO3  Gaussian O-information (nats) of triplets, from correlations.
%
%   O = src_oinfo3(R, trip)
%
% R is a correlation matrix, trip a k x 3 list of variable indices.
% For three Gaussian variables
%   O = 1/2 [ log det R_123 - sum over pairs log(1 - r_ab^2) ]
% (the 2*pi*e terms cancel). O > 0 means redundancy, O < 0 synergy. O is
% unchanged by the scale and sign of each variable, so the sign ambiguity
% of parcel time series does not matter.

r12 = R(sub2ind(size(R), trip(:,1), trip(:,2)));
r13 = R(sub2ind(size(R), trip(:,1), trip(:,3)));
r23 = R(sub2ind(size(R), trip(:,2), trip(:,3)));
d3  = 1 + 2*r12.*r13.*r23 - r12.^2 - r13.^2 - r23.^2;
O   = 0.5 * (log(d3) - log(1 - r12.^2) - log(1 - r13.^2) - log(1 - r23.^2));
end
