function out = prep_load(arg, ext)
% PREP_LOAD  Read one recording, or name the function that reads a format.
%
%   EEG    = prep_load(file)            read the file
%   reader = prep_load('reader', ext)   the reader for extension EXT
%
% The one place that maps formats to readers, so the startup checks test
% what the import will use: pop_loadset for .set, pop_fileio for the rest.

if ischar(arg) && strcmp(arg, 'reader')
    out = reader_for(ext);
    return
end
[~, ~, e] = fileparts(arg);
if strcmp(reader_for(e), 'pop_loadset')
    out = pop_loadset('filename', arg);
else
    out = pop_fileio(arg);
end
end

function fcn = reader_for(ext)
if strcmpi(ext, '.set'), fcn = 'pop_loadset'; else, fcn = 'pop_fileio'; end
end
