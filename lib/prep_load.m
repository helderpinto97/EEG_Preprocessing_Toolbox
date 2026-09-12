function out = prep_load(arg, ext)
% PREP_LOAD  Read one recording, or name the function that would read it.
%
%   EEG    = prep_load(file)            read the file
%   reader = prep_load('reader', ext)   the function that reads EXT
%
% One place decides which reader an extension gets. The startup check in
% run_preprocessing asks this function rather than restating the rule, so it
% tests the mapping the import will actually use. Written out separately at
% each call site, the check could pass while the import it was guarding had
% no reader at all.
%
% pop_fileio reads everything that is not a .set: bdf, edf, vhdr, cnt and
% the rest. To use a different reader for a format, add a case below and put
% its plugin on the path.

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


% -------------------------------------------------------------------------
function fcn = reader_for(ext)
if strcmpi(ext, '.set'), fcn = 'pop_loadset'; else, fcn = 'pop_fileio'; end
end
