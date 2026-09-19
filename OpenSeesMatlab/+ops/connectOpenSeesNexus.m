function libraryRoot = connectOpenSeesNexus()
%CONNECTOPENSEESNEXUS Make the embedded OpenSeesNexus sublibrary available.

    opsDirectory = fileparts(mfilename("fullpath"));
    libraryRoot = fullfile(opsDirectory, "OpenSeesNexus");
    entryPoint = fullfile(libraryRoot, "OpenSeesNexus.m");
    assert(isfile(entryPoint), ...
        "OpenSeesMatlab:OpenSeesNexusMissing", ...
        "The embedded OpenSeesNexus library is missing: %s", libraryRoot);

    located = string(which("OpenSeesNexus"));
    if ~strcmpi(located, entryPoint)
        addpath(libraryRoot, "-begin");
        rehash;
    end
    located = string(which("OpenSeesNexus"));
    assert(strcmpi(located, entryPoint), ...
        "OpenSeesMatlab:OpenSeesNexusUnavailable", ...
        "MATLAB selected %s instead of the embedded library %s.", ...
        located, entryPoint);
end
