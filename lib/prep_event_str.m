function s = prep_event_str(x, fallback)
% PREP_EVENT_STR  An event type as char.
%
%   s = prep_event_str(x)            unusable types raise an error
%   s = prep_event_str(x, fallback)  unusable types return FALLBACK
%
% EEG.event.type is char in most importers, numeric in some, and a string
% scalar in a few. Anything that compares or prints event types has to take
% all three.
%
% Which failure is right depends on the caller. In the pipeline an unusable
% type means epochs would be cut on a comparison that cannot be made, so it
% is an error. A figure passes a fallback: a label it cannot read costs a
% title, not the recording.

if ischar(x)
    s = x;
elseif isstring(x) && isscalar(x)
    s = char(x);
elseif isnumeric(x) && isscalar(x)
    s = num2str(x);
elseif nargin >= 2
    s = fallback;
else
    error('prep_event_str:badType', ...
        'Event types must be text or numeric scalars; got a %s.', class(x));
end
end
