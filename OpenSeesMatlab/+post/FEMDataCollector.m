classdef FEMDataCollector < handle
    %FEMDATACOLLECTOR Access the native, cross-language FEMData model schema.
    %
    % This class intentionally contains no independent MATLAB model-collection
    % logic. The OpenSeesNexus native collector is the single source of truth
    % used by MATLAB, Python, and Julia. Consequently, getModelInfo and save
    % return exactly the MODEL structure produced by writeFEMModel.

    properties (Access = private)
        host
        data = struct()
    end

    methods
        function obj = FEMDataCollector(host, ~)
            if nargin < 1 || isempty(host)
                error('FEMDataCollector:InvalidInput', ...
                    'An OpenSeesNexus command host is required.');
            end
            obj.host = host;
        end

        function collect(obj)
            %COLLECT Capture the current Domain directly in native memory.
            obj.data = obj.host.getFEMModel();
            if ~isstruct(obj.data)
                error('FEMDataCollector:InvalidData', ...
                    'getFEMModel did not return a MATLAB structure.');
            end
        end

        function modelInfo = getModelInfo(obj)
            %GETMODELINFO Return the current native FEMData MODEL snapshot.
            obj.collect();
            modelInfo = obj.data;
        end

        function save(obj, filename)
            %SAVE Write a model-only FEMData file using writeFEMModel.
            arguments
                obj (1,1) post.FEMDataCollector
                filename {mustBeTextScalar}
            end
            obj.writeNativeModel(string(filename));
            obj.data = obj.readNativeModel(string(filename));
        end

        function data = readFile(obj, filename)
            %READFILE Read a native model snapshot; retain legacy-file support.
            arguments
                obj (1,1) post.FEMDataCollector
                filename {mustBeTextScalar}
            end
            try
                data = obj.readNativeModel(string(filename));
            catch nativeError
                % Older modelData_*.hdf5 files used MATLAB HDF5DataStore.
                try
                    store = post.utils.HDF5DataStore(char(filename), 'overwrite', false);
                    data = store.load();
                catch
                    rethrow(nativeError);
                end
            end
            if ~isstruct(data)
                error('FEMDataCollector:InvalidData', ...
                    'The model file did not contain a MATLAB structure.');
            end
        end
    end

    methods (Access = private)
        function writeNativeModel(obj, filename)
            status = obj.host.writeFEMModel(char(filename));
            if ~(isnumeric(status) && isscalar(status) && status == 0)
                error('FEMDataCollector:WriteFailed', ...
                    'writeFEMModel failed for "%s" (status %s).', ...
                    filename, string(status));
            end
        end

        function data = readNativeModel(obj, filename)
            data = obj.host.readFEMData(char(filename), "model");
            if ~isstruct(data)
                error('FEMDataCollector:InvalidData', ...
                    'No MODEL structure was found in "%s".', filename);
            end
        end
    end

end
