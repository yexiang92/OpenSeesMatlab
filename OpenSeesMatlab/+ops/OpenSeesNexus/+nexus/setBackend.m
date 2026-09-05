function backend = setBackend(value)
%SETBACKEND Select the serial or SP backend before creating an ops object.

arguments
    value {mustBeTextScalar}
end

backend = lower(strtrim(string(value)));
if any(backend == ["default", "serial"])
    backend = "serial";
elseif any(backend == ["mpi", "openseessp", "sp"])
    backend = "sp";
else
    error("ops:InvalidBackend", ...
        "Backend must be 'serial' or 'sp', not '%s'.", backend);
end

loadedKey = "OpenSeesBindingsLoadedBackend";
if isappdata(0, loadedKey) && string(getappdata(0, loadedKey)) ~= backend
    error("ops:BackendAlreadyLoaded", ...
        "The %s backend is already initialized. Restart MATLAB before changing to %s.", ...
        string(getappdata(0, loadedKey)), backend);
end
setappdata(0, "OpenSeesBindingsBackend", backend);
end
