function lf = sim_leadfield(sim)
% SIM_LEADFIELD  HArtMuT New York Head lead field for sim.labels.
%
% HArtMuT extends the New York Head with eye and muscle sources, so the
% clean EEG and the ocular and muscular artifacts come from one volume
% conductor. Needs SEREEGA and HArtMuT_NYhead_small.mat on the path, and
% EEGLAB started (lf_generate_fromhartmut calls pop_chanedit).

if ~exist('lf_generate_fromhartmut', 'file')
    assert(isfolder(sim.sereegaPath), 'sim_leadfield:noSEREEGA', ...
        'SEREEGA not found at %s.', sim.sereegaPath);
    addpath(genpath(sim.sereegaPath));
end
if ~exist('HArtMuT_NYhead_small.mat', 'file')
    assert(isfile(fullfile(sim.hartmutPath, 'HArtMuT_NYhead_small.mat')), ...
        'sim_leadfield:noHArtMuT', ...
        ['HArtMuT_NYhead_small.mat not found in %s.\n' ...
         'Download it from https://github.com/harmening/HArtMuT (HArtMuTmodels).'], ...
        sim.hartmutPath);
    addpath(sim.hartmutPath);
end

lf = lf_generate_fromhartmut('NYhead_small', 'labels', sim.labels);

got = {lf.chanlocs.labels};
if ~isequal(got(:), sim.labels(:))
    error('sim_leadfield:labels', 'Lead field lacks channel(s): %s', ...
          strjoin(setdiff(sim.labels, got), ', '));
end
end
