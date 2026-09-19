classdef Runtime < handle
    %RUNTIME Minimal MATLAB adapter for the OpenSees native binding.

    properties (SetAccess = private)
        MexName = "OpenSeesMATLAB"
        NativeDirectory = ""
    end

    properties (Access = private)
        MexHandle
    end

    methods
        function obj = Runtime(nativeDirectory, mexName)
            if nargin >= 2 && strlength(string(mexName)) > 0
                obj.MexName = string(mexName);
                if endsWith(obj.MexName, "SP")
                    nexus.setBackend("sp");
                else
                    nexus.setBackend("serial");
                end
            else
                obj.MexName = nexus.Runtime.defaultMexName();
            end
            if nargin < 1
                nativeDirectory = "";
            end

            obj.NativeDirectory = obj.resolveNativeDirectory(nativeDirectory);
            if strlength(obj.NativeDirectory) > 0
                addpath(char(obj.NativeDirectory), "-begin");
                rehash;
            end
            obj.MexHandle = str2func(char(obj.MexName));

            if isempty(which(char(obj.MexName)))
                error("ops:NativeLibraryNotFound", ...
                    ["nexus.Runtime could not locate %s for %s. " ...
                     "Pass its directory to nexus.Runtime or set " ...
                     "OPENSEES_MATLAB_DIR."], ...
                    obj.MexName, nexus.Runtime.platformKey());
            end

            if endsWith(obj.MexName, "SP")
                loadedBackend = "sp";
            else
                loadedBackend = "serial";
            end
            setappdata(0, "OpenSeesBindingsLoadedBackend", loadedBackend);
        end

        function varargout = invoke(obj, command, varargin)
            [varargout{1:nargout}] = obj.MexHandle(char(string(command)), varargin{:});
        end

        function handle = getHandle(obj)
            % Return the direct MEX handle for low-overhead command wrappers.
            handle = obj.MexHandle;
        end

        function path = nativePath(obj)
            path = string(which(char(obj.MexName)));
        end
    end

    methods (Access = private)
        function directory = resolveNativeDirectory(obj, requested)
            roots = strings(0, 1);
            if nargin >= 2 && strlength(string(requested)) > 0
                roots(end + 1) = string(requested);
            end

            configured = string(getenv("OPENSEES_MATLAB_DIR"));
            if strlength(configured) > 0
                roots(end + 1) = configured;
            end

            % Backward compatibility with packages released before the
            % environment variable was given its language-specific name.
            configured = string(getenv("OPENSEES_NEXUS_MATLAB_DIR"));
            if strlength(configured) > 0
                roots(end + 1) = configured;
            end

            % The normal distribution layout is resolved relative to this
            % file, so the toolbox can be installed at any location.
            implementationRoot = fileparts(mfilename("fullpath"));
            libraryRoot = fileparts(implementationRoot);
            roots(end + 1) = string(libraryRoot);

            platform = nexus.Runtime.platformKey();
            candidates = strings(3 * numel(roots), 1);
            for index = 1:numel(roots)
                root = roots(index);
                % Accept the library root, a derived root, or the native
                % platform directory itself.
                first = 3 * (index - 1) + 1;
                candidates(first:first + 2) = [
                    fullfile(root, "derived", platform)
                    fullfile(root, platform)
                    root
                ];
            end

            extension = string(mexext);
            for index = 1:numel(candidates)
                absoluteCandidate = candidates(index);
                if isfolder(absoluteCandidate) && ...
                        isfile(fullfile(absoluteCandidate, obj.MexName + "." + extension))
                    directory = absoluteCandidate;
                    return
                end
            end

            existing = string(which(char(obj.MexName)));
            if strlength(existing) > 0
                directory = string(fileparts(existing));
                return
            end
            directory = "";
        end
    end

    methods (Static)
        function name = defaultMexName()
            if nexus.getBackend() == "sp"
                name = "OpenSeesMATLABSP";
            else
                name = "OpenSeesMATLAB";
            end
        end

        function key = platformKey()
            if ispc && strcmp(computer("arch"), "win64")
                key = "windows-x86_64";
            elseif ismac && strcmp(computer("arch"), "maca64")
                key = "macos-aarch64";
            else
                error("ops:UnsupportedPlatform", ...
                    "MATLAB binding does not support %s.", computer("arch"));
            end
        end
    end
end
