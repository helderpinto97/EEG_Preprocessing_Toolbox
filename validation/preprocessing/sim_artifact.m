function art = sim_artifact(lf, sim, name, seed)
% SIM_ARTIFACT  Unscaled artifact by name, e.g. 'eog_blink', 'emg_neck', 'ecg'.
%
% The part after the underscore selects the variant within a family. Bad
% channels are not an additive artifact and are made by sim_badchan. Every
% generator returns the same fields: data (channels x samples), active
% (1 x samples) and peak (channel index), which is all sim_inject and
% sim_eval need.
parts = split(string(name), '_');
switch parts(1)
    case 'eog',  art = sim_eog(lf, sim, char(parts(2)), seed);
    case 'emg',  art = sim_emg(lf, sim, char(parts(2)), seed);
    case 'ecg',  art = sim_ecg(lf, sim, seed);
    case 'line', art = sim_line(lf, sim, seed);
    case 'drift', art = sim_drift(lf, sim, seed);
    case 'pop',  art = sim_pop(lf, sim, seed);
    otherwise
        error('sim_artifact:name', 'Unknown artifact "%s".', name);
end
end
