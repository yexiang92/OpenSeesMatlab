function backend = getBackend()
%GETBACKEND Return the backend selected for the next native initialization.

key = "OpenSeesBindingsBackend";
if isappdata(0, key)
    backend = string(getappdata(0, key));
else
    backend = string(getenv("OPENSEES_BACKEND"));
    if strlength(backend) == 0
        backend = "serial";
    end
end

backend = lower(strtrim(backend));
if any(backend == ["default", "serial"])
    backend = "serial";
elseif any(backend == ["mpi", "openseessp", "sp"])
    backend = "sp";
else
    error("ops:InvalidBackend", ...
        "Backend must be 'serial' or 'sp', not '%s'.", backend);
end
end
