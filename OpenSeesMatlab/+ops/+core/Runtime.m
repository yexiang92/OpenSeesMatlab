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
            if nargin >= 2 && ~isempty(mexName)
                obj.MexName = string(mexName);
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
                    ["ops.core.Runtime could not locate %s for %s. " ...
                     "Pass its directory to ops.core.Runtime or set " ...
                     "OPENSEES_NEXUS_MATLAB_DIR."], ...
                    obj.MexName, ops.core.Runtime.platformKey());
            end
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
            candidates = strings(0, 1);
            if nargin >= 2 && strlength(string(requested)) > 0
                candidates(end + 1) = string(requested);
            end

            configured = string(getenv("OPENSEES_NEXUS_MATLAB_DIR"));
            if strlength(configured) > 0
                candidates(end + 1) = configured;
            end

            coreRoot = fileparts(mfilename("fullpath"));
            candidates(end + 1) = fullfile(coreRoot, "derived", ...
                ops.core.Runtime.platformKey());

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
