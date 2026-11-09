function [trips, allTrip, tripDist] = src_triplets(A, src, vpos)
% SRC_TRIPLETS  Target triplets, all triplets and their mean parcel distance.
%
%   [trips, allTrip, tripDist] = src_triplets(A, src, vpos)
%
% trips.near  the parcel of left M1 and the two parcels with the closest centres
% trips.far   the parcels of src.farPts
% Each point goes to the parcel of the nearest labelled template vertex
% (vpos). allTrip lists every triplet of parcels, tripDist the mean of the
% three distances between their centres (mm).

c = find(A.bst > 0);
lab = @(P) arrayfun(@(i) A.bst(c(nearest(vpos(c, :), P(i, :)))), 1:size(P, 1));
m1 = lab(src.m1Left);
[~, order] = sort(vecnorm(A.centre - A.centre(m1, :), 2, 2));
trips.near = sort(order(1:3))';
trips.far  = sort(lab(src.farPts));
assert(numel(unique(trips.far)) == 3, 'src_triplets:far', 'Two far points fall in one parcel.');

allTrip = nchoosek(1:numel(A.names), 3);
d = pdist2(A.centre, A.centre);
tripDist = (d(sub2ind(size(d), allTrip(:,1), allTrip(:,2))) + ...
            d(sub2ind(size(d), allTrip(:,1), allTrip(:,3))) + ...
            d(sub2ind(size(d), allTrip(:,2), allTrip(:,3)))) / 3;
end

function i = nearest(P, x)
[~, i] = min(vecnorm(P - x, 2, 2));
end
