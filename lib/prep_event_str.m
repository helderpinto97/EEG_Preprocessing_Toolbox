function s = prep_event_str(x, fallback)
% PREP_EVENT_STR  An event type (char, string or number) as char.
%
%   s = prep_event_str(x)            other types raise an error
%   s = prep_event_str(x, fallback)  other types return FALLBACK

if ischar(x)
    s = x;
elseif (isstring(x) || isnumeric(x)) && isscalar(x)
    s = char(string(x));
elseif nargin >= 2
    s = fallback;
else
    error('prep_event_str:badType', 'Event types must be text or numeric scalars; got a %s.', class(x));
end
end
