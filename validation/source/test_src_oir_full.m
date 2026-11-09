function tests = test_src_oir_full
% TEST_SRC_OIR_FULL  src_oir_full against sir_deltaO and the exact OIR.
%   runtests('test_src_oir_full')
tests = functiontests(localfunctions);
end

function testMatchesSirDeltaO(tc)
% same spectral matrix, closed form against the SIR toolbox
rng(3);
X = filter(1, [1 -0.5], randn(5, 4000), [], 2);
X(3, :) = X(3, :) + 0.7 * [0 X(1, 1:end-1)] + 0.7 * [0 X(2, 1:end-1)];
trip = nchoosek(1:5, 3);
O = src_oir_full(X, trip, 3, 1, 64);
[Am, Su] = oir_idVAR(X, 3);
S = sir_VARspectra(Am, Su, 64, 1);
for k = 1:size(trip, 1)
    ref = sir_deltaO(S, ones(1, 5), trip(k, :), trip(k, 3));
    verifyEqual(tc, O(k), ref.dO, 'AbsTol', 1e-10);
end
end

function testRecoversTruth(tc)
% synergistic triplet among independent oscillators: full-VAR estimate
% close to the exact OIR of the true model
src = src_config();
trips.near = [2 4 6]; trips.far = [1 3 5];
[S, tr] = src_sources_var('syn_near', 8, 30000, trips, src, 1, 1);
O = src_oir_full(S, [2 4 6; 1 3 5], 2, src.srate, 256);
verifyEqual(tc, O(1), tr.O, 'AbsTol', 0.02);
verifyEqual(tc, O(2), 0, 'AbsTol', 0.01);
end
