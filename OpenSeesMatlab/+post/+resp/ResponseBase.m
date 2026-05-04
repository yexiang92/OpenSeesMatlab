classdef (Abstract) ResponseBase < handle
    %RESPONSEBASE High-efficiency base class for step-wise response data.
    %
    % Design
    % ------
    % 1) Store each step as one scalar struct.
    % 2) Merge all stored steps only once when final data is requested.
    % 3) Delegate generic fixed-schema nested-struct merge to StructMerger.
    %
    % Merge semantics
    % ---------------
    % Each stored step is one time step.
    % Final merging therefore uses Mode = 'prepend':
    %   input per step  : [nEntity, nComp, ...]
    %   merged response : [nStep, nEntity, nComp, ...]
    %
    % Pre-allocation strategy (stepSize)
    % ------------------------------------
    % When stepSize is a positive integer, stepData and times are
    % pre-allocated to that length at construction / reset time.
    % The internal counter stepWritePos tracks the next write slot.
    % On buildDataset, any trailing slots whose struct is empty (never
    % written) are dropped before merging.
    %
    % When stepSize is empty (default), stepData grows dynamically via
    % cell array append, matching the original behaviour.
    %
    % Trailing-NaN trimming
    % ----------------------
    % After merging, if the last time entry is NaN, it indicates an
    % un-committed slot and is removed together with the corresponding
    % first-dimension slice of every numeric field.

    properties
        kargs
        dtype
        stepSize
        respName
        respTypes
        modelUpdate
        haveInitialStateDone
    end

    properties (Access = protected)
        ops
        mex_
        respDataInternal
        stepData          % cell(maxSteps,1) or growing cell
        stepWritePos      % next write index (used only when stepSize set)
        stepTrack
        times
    end

    properties (Dependent)
        respData
        currentTime
        currentStep
    end

    methods
        function obj = ResponseBase(ops, varargin)
            obj.ops = ops;
            obj.mex_ = ops.getMexHandle();
            obj.initialize(varargin{:});
        end

        function initialize(obj, varargin)
            %INITIALIZE Reset internal state and parse options.

            modelUpdateValue = false;
            dtypeValue       = struct();
            stepsizeValue    = [];

            nArgs = numel(varargin);
            if mod(nArgs, 2) ~= 0
                error('ResponseBase:InvalidInput', ...
                    'Optional arguments must be provided as key-value pairs.');
            end

            for i = 1:2:nArgs
                key = varargin{i};
                val = varargin{i + 1};
                if isstring(key); key = char(key); end

                switch lower(key)
                    case 'modelupdate'
                        modelUpdateValue = logical(val);
                    case 'dtype'
                        dtypeValue = val;
                    case 'stepsize'
                        stepsizeValue = val;
                end
            end

            obj.kargs = struct( ...
                'modelUpdate', modelUpdateValue, ...
                'dtype',       dtypeValue, ...
                'stepSize',    stepsizeValue);

            obj.dtype = struct('intType','int32','floatType','single');
            if ~isempty(dtypeValue) && isstruct(dtypeValue)
                names = fieldnames(dtypeValue);
                for i = 1:numel(names)
                    obj.dtype.(names{i}) = dtypeValue.(names{i});
                end
            end

            obj.respName             = '';
            obj.respTypes            = {};
            obj.stepSize             = stepsizeValue;
            obj.modelUpdate          = modelUpdateValue;
            obj.haveInitialStateDone = false;

            obj.respDataInternal = struct();
            obj.stepTrack        = 0;
            obj.stepWritePos     = 0;

            % Pre-allocate or initialise empty depending on stepSize
            if ~isempty(stepsizeValue) && isnumeric(stepsizeValue) && stepsizeValue > 0
                n             = double(stepsizeValue);
                obj.stepData  = cell(n, 1);   % pre-allocated; slots are []
                obj.times     = NaN(n, 1);    % NaN = not yet written
            else
                obj.stepData  = cell(0, 1);
                obj.times     = zeros(0, 1);
            end
        end

        function reset(obj)
            %RESET Reset object while preserving initialisation options.
            obj.initialize( ...
                'modelUpdate', obj.kargs.modelUpdate, ...
                'dtype',       obj.kargs.dtype, ...
                'stepSize',    obj.kargs.stepSize);
        end

        function moveOneStep(obj, timeValue)
            %MOVEONESTEP Advance internal step tracker and append time.
            if nargin < 2; timeValue = 0.0; end

            if obj.haveInitialStateDone
                obj.stepTrack = obj.stepTrack + 1;
            else
                obj.haveInitialStateDone = true;
                obj.stepTrack = 0;
            end

            % Write time into pre-allocated slot or append dynamically
            if ~isempty(obj.stepSize)
                pos = obj.stepWritePos;
                if pos >= 1 && pos <= numel(obj.times)
                    obj.times(pos) = timeValue;
                end
                % pos is advanced in addStepData after the struct is stored
            else
                obj.times(end + 1, 1) = timeValue;
            end
        end

        function addStepData(obj, stepStruct, timeValue)
            %ADDSTEPDATA Add one complete step as a scalar struct.
            %
            %   addStepData(stepStruct)            -- uses getCurrentOpsTime()
            %   addStepData(stepStruct, timeValue) -- uses supplied time

            if nargin < 3
                timeValue = obj.getCurrentOpsTime();
            end

            if isempty(stepStruct)
                stepStruct = struct();
            elseif ~isstruct(stepStruct) || ~isscalar(stepStruct)
                error('ResponseBase:InvalidStepData', ...
                    'stepStruct must be a scalar struct.');
            end

            if ~isempty(obj.stepSize)
                % ---- pre-allocated path ---------------------------------
                obj.stepWritePos = obj.stepWritePos + 1;
                pos = obj.stepWritePos;

                if pos > numel(obj.stepData)
                    % Overflow: grow by 25 % to avoid frequent resizing
                    extra          = max(ceil(numel(obj.stepData) * 0.25), 1);
                    obj.stepData   = [obj.stepData;   cell(extra, 1)];
                    obj.times      = [obj.times;      NaN(extra, 1)];
                end

                obj.stepData{pos} = stepStruct;
                obj.times(pos)    = timeValue;
            else
                % ---- dynamic-growth path --------------------------------
                obj.stepData{end + 1, 1} = stepStruct;
                obj.times(end + 1, 1)    = timeValue;
            end

            % Advance step tracker
            if obj.haveInitialStateDone
                obj.stepTrack = obj.stepTrack + 1;
            else
                obj.haveInitialStateDone = true;
                obj.stepTrack = 0;
            end
        end

        function resetRespStepData(obj)
            %RESETRESPSTEPDATA Reset collected step data and merged data.
            obj.respDataInternal     = struct();
            obj.stepTrack            = 0;
            obj.stepWritePos         = 0;
            obj.haveInitialStateDone = false;

            if ~isempty(obj.stepSize) && isnumeric(obj.stepSize) && obj.stepSize > 0
                n            = double(obj.stepSize);
                obj.stepData = cell(n, 1);
                obj.times    = NaN(n, 1);
            else
                obj.stepData = cell(0, 1);
                obj.times    = zeros(0, 1);
            end
        end

        function tf = checkDatasetEmpty(obj)
            %CHECKDATASETEMPTY True if no step data has been stored.
            if ~isempty(obj.stepSize)
                tf = obj.stepWritePos == 0;
            else
                tf = isempty(obj.stepData);
            end
        end

        function out = getRespStepData(obj)
            %GETRESPSTEPDATA Return merged response dataset.
            if isempty(fieldnames(obj.respDataInternal))
                obj.addRespDataToResults();
            end
            out = obj.respDataInternal;
        end

        function setRespStepData(obj, data)
            %SETRESPSTEPDATA Set merged dataset directly.
            obj.respDataInternal = data;
        end

        function t = getCurrentTime(obj)
            if isempty(obj.times)
                t = 0.0;
            else
                % Ignore trailing NaN slots
                vals = obj.times(~isnan(obj.times));
                if isempty(vals); t = 0.0; else; t = vals(end); end
            end
        end

        function s = getCurrentStep(obj)
            s = obj.stepTrack;
        end

        function t = getCurrentOpsTime(obj)
            t = obj.mex_('getTime');
        end

        function out = get.respData(obj)
            out = obj.getRespStepData();
        end
        function out = get.currentTime(obj)
            out = obj.getCurrentTime();
        end
        function out = get.currentStep(obj)
            out = obj.getCurrentStep();
        end
    end

    methods
        function addRespDataToResults(obj)
            obj.respDataInternal = obj.buildDataset();
        end
    end

    methods (Abstract)
        addRespDataOneStep(obj, varargin)
    end

    methods (Access = protected)

        function [parts, metaFields] = preProcessParts(obj, parts) %#ok<INUSL>
            metaFields = struct();
        end

        % -----------------------------------------------------------------
        function out = buildDataset(obj)
            %BUILDDATASET Build final merged dataset from stored steps.

            out              = struct();
            out.ModelUpdate  = obj.modelUpdate;

            % ---- determine the active slice of stepData / times ---------
            if ~isempty(obj.stepSize)
                nWritten  = obj.stepWritePos;
                activeCells = obj.stepData(1:nWritten);
                activeTimes = obj.times(1:nWritten);
            else
                activeCells = obj.stepData;
                activeTimes = obj.times;
            end

            % ---- trim trailing empty / NaN time slots -------------------
            % Remove the last slot if its time is NaN (un-committed slot
            % or a slot that was never written in pre-alloc mode).
            while ~isempty(activeTimes) && isnan(activeTimes(end))
                activeTimes = activeTimes(1:end-1);
                activeCells = activeCells(1:end-1);
            end

            out.time = activeTimes;

            if isempty(activeCells)
                return;
            end

            mask   = ~cellfun(@isempty, activeCells);
            if ~any(mask)
                return;
            end

            parts  = activeCells(mask);
            nParts = numel(parts);

            if nParts == 1 && strcmp(obj.RESP_NAME, 'ModelInfo')
                merged = parts{1};
            else
                wrapped = cell(nParts, 1);
                for i = 1:nParts
                    Ti              = parts{i};
                    Ti.modelUpdate  = obj.modelUpdate;
                    wrapped{i}      = Ti;
                end

                [wrapped, metaFields] = obj.preProcessParts(wrapped);

                merged = post.utils.StructMerger.mergeParts( ...
                    wrapped, ...
                    'ModelUpdateField', 'modelUpdate', ...
                    'Mode', 'prepend');

                if isfield(merged, 'modelUpdate')
                    merged = rmfield(merged, 'modelUpdate');
                end

                metaNames = fieldnames(metaFields);
                for i = 1:numel(metaNames)
                    name         = metaNames{i};
                    merged.(name) = metaFields.(name);
                end
            end

            % ---- copy merged fields into output -------------------------
            mergedNames = fieldnames(merged);
            for i = 1:numel(mergedNames)
                name     = mergedNames{i};
                out.(name) = merged.(name);
            end

            % ---- trim last time step if its time is NaN -----------------
            % (Defensive: handles the case where StructMerger inserts a NaN
            % time row even though activeTimes was already trimmed above.)
            out = obj.trimTrailingNaNStep(out);
        end

        % -----------------------------------------------------------------
        function out = trimTrailingNaNStep(~, ds)
            %TRIMTRAILINGNNANSTEP Remove the last time step if time is NaN.
            %
            % Operates on the merged dataset struct.
            % The time dimension is always dimension 1 after 'prepend' merge.

            out = ds;

            if ~isfield(ds, 'time') || isempty(ds.time)
                return;
            end

            if ~isnan(ds.time(end))
                return;   % nothing to trim
            end

            % Trim time vector
            nKeep   = find(~isnan(ds.time), 1, 'last');
            if isempty(nKeep); nKeep = 0; end
            out.time = ds.time(1:nKeep);

            % Trim every numeric/logical field whose first dimension equals
            % the original number of time steps.
            nTotal = numel(ds.time);
            fnames = fieldnames(ds);
            for k = 1:numel(fnames)
                fn = fnames{k};
                if strcmp(fn, 'time'); continue; end
                v  = ds.(fn);
                if (~isnumeric(v) && ~islogical(v)) || isempty(v)
                    continue;
                end
                if size(v, 1) ~= nTotal
                    continue;
                end
                nd   = ndims(v);
                subs = repmat({':'}, 1, nd);
                subs{1} = 1:nKeep;
                out.(fn) = v(subs{:});
            end
        end

        % -----------------------------------------------------------------
        function [parts, metaFields] = alignPartsByTags(obj, parts, tagField)
            %ALIGNPARTSBYTAGS Align per-step arrays to the global tag union.

            metaFields = struct();
            if isempty(parts); return; end

            % Build global tag union (first-seen order)
            allTags = zeros(1, 0);
            for i = 1:numel(parts)
                p = parts{i};
                if ~isfield(p, tagField) || isempty(p.(tagField)); continue; end
                tmp = p.(tagField);
                localTags = double(tmp(:).');
                if isempty(allTags)
                    allTags = localTags;
                else
                    isNew = ~ismember(localTags, allTags);
                    if any(isNew)
                        allTags = [allTags, localTags(isNew)]; %#ok<AGROW>
                    end
                end
            end

            if isempty(allTags); return; end
            metaFields.(tagField) = allTags(:);

            % Fast path: no model update
            if ~obj.modelUpdate
                for i = 1:numel(parts)
                    p = parts{i};
                    if isfield(p, tagField)
                        p = rmfield(p, tagField);
                        parts{i} = p;
                    end
                end
                return;
            end

            % Model-update path: expand all tag-aligned arrays to global union
            floatType = obj.getMergeFloatType();
            nGlobal   = numel(allTags);

            for i = 1:numel(parts)
                p = parts{i};
                if ~isfield(p, tagField) || isempty(p.(tagField))
                    parts{i} = p;
                    continue;
                end

                tmp = p.(tagField);
                localTags  = double(tmp(:).');
                [~, globalIdx] = ismember(localTags, allTags);
                nLocal     = numel(localTags);
                fieldNames = fieldnames(p);

                for j = 1:numel(fieldNames)
                    fn = fieldNames{j};
                    if strcmp(fn, tagField); continue; end
                    v = p.(fn);
                    if (~isnumeric(v) && ~islogical(v)) || isempty(v) || size(v,1) ~= nLocal
                        continue;
                    end
                    oldSize  = size(v);
                    tailSize = oldSize(2:end);
                    v2       = reshape(v, nLocal, []);
                    vGlobal  = nan(nGlobal, size(v2,2), floatType);
                    vGlobal(globalIdx, :) = cast(v2, floatType);
                    p.(fn)   = reshape(vGlobal, [nGlobal, tailSize]);
                end

                p = rmfield(p, tagField);
                parts{i} = p;
            end
        end

        % -----------------------------------------------------------------
        function [parts, metaFields] = alignPartsByTagGroups(obj, parts, groupSpecs)
            %ALIGNPARTSBYTAGGROUPS Align explicit field groups by their tag axes.

            metaFields = struct();
            if isempty(parts) || isempty(groupSpecs)
                return;
            end

            for i = 1:numel(groupSpecs)
                spec = groupSpecs(i);
                [parts, groupMeta] = obj.alignPartsByFieldGroup( ...
                    parts, spec.tagField, spec.alignedFields);

                metaNames = fieldnames(groupMeta);
                for j = 1:numel(metaNames)
                    name = metaNames{j};
                    metaFields.(name) = groupMeta.(name);
                end
            end
        end

        % -----------------------------------------------------------------
        function [parts, metaFields] = alignPartsByFieldGroup(obj, parts, tagField, alignedFields)
            %ALIGNPARTSBYFIELDGROUP Align selected fields to a specific tag union.

            metaFields = struct();
            if isempty(parts)
                return;
            end

            allTags = obj.collectTagUnion(parts, tagField);
            if isempty(allTags)
                return;
            end

            metaFields.(tagField) = allTags(:);

            for i = 1:numel(parts)
                p = parts{i};
                if ~isfield(p, tagField)
                    parts{i} = p;
                    continue;
                end

                tmp = p.(tagField);
                localTags = double(tmp(:).');
                if isempty(localTags)
                    p = rmfield(p, tagField);
                    parts{i} = p;
                    continue;
                end

                if obj.modelUpdate
                    p = obj.expandPartFieldsByTags(p, localTags, allTags, alignedFields);
                end

                p = rmfield(p, tagField);
                parts{i} = p;
            end
        end

        % -----------------------------------------------------------------
        function allTags = collectTagUnion(~, parts, tagField)
            %COLLECTTAGUNION Build a first-seen-order union for one tag axis.

            allTags = zeros(1, 0);
            for i = 1:numel(parts)
                p = parts{i};
                if ~isfield(p, tagField) || isempty(p.(tagField))
                    continue;
                end

                tmp = p.(tagField);
                localTags = double(tmp(:).');
                if isempty(allTags)
                    allTags = localTags;
                    continue;
                end

                isNew = ~ismember(localTags, allTags);
                if any(isNew)
                    allTags = [allTags, localTags(isNew)]; %#ok<AGROW>
                end
            end
        end

        % -----------------------------------------------------------------
        function part = expandPartFieldsByTags(obj, part, localTags, allTags, alignedFields)
            %EXPANDPARTFIELDSBYTAGS Expand selected fields to the global tag union.

            nLocal = numel(localTags);
            nGlobal = numel(allTags);
            [~, globalIdx] = ismember(localTags, allTags);
            floatType = obj.getMergeFloatType();

            for i = 1:numel(alignedFields)
                fn = alignedFields{i};
                if ~isfield(part, fn)
                    continue;
                end

                v = part.(fn);
                if (~isnumeric(v) && ~islogical(v)) || isempty(v) || size(v, 1) ~= nLocal
                    continue;
                end

                oldSize = size(v);
                tailSize = oldSize(2:end);
                v2 = reshape(v, nLocal, []);

                if islogical(v)
                    vGlobal = false(nGlobal, size(v2, 2));
                    vGlobal(globalIdx, :) = v2;
                else
                    vGlobal = nan(nGlobal, size(v2, 2), floatType);
                    vGlobal(globalIdx, :) = cast(v2, floatType);
                end

                part.(fn) = reshape(vGlobal, [nGlobal, tailSize]);
            end
        end

        % -----------------------------------------------------------------
        function stepName = makeStepName(~, stepId)
            stepName = sprintf('Step_%08d', stepId);
        end

        function dims = prependTimeDim(~, S)
            if isfield(S, 'dims') && ~isempty(S.dims)
                dims = [{'time'}, S.dims];
            else
                dims = {'time'};
            end
        end

        function out = selectNodeTags(obj, ds, nodeTags)
            out = ds;
            if isempty(ds) || ~isstruct(ds) || ~isfield(ds,'tags') || isempty(nodeTags)
                return;
            end
            idx = obj.resolveSelectionIndices(ds.tags, nodeTags);
            out = obj.subsetStructByIndex(ds, idx);
        end

        function out = selectEleTags(obj, ds, eleTags)
            out = ds;
            if isempty(ds) || ~isstruct(ds) || ~isfield(ds,'tags') || isempty(eleTags)
                return;
            end
            idx = obj.resolveSelectionIndices(ds.tags, eleTags);
            out = obj.subsetStructByIndex(ds, idx);
        end

        function idx = resolveSelectionIndices(~, tags, selector)
            if islogical(selector)
                idx = find(selector);
                return;
            end
            if isnumeric(selector)
                if isempty(selector); idx = selector; return; end
                if all(selector >= 1) && all(selector == floor(selector)) && ...
                        all(selector <= numel(tags))
                    idx = selector(:).';
                    return;
                end
                [~, idx] = ismember(selector, tags);
                idx = idx(idx > 0);
                return;
            end
            [~, idx] = ismember(selector, tags);
            idx = idx(idx > 0);
        end

        function out = subsetStructByIndex(~, ds, idx)
            out = ds;
            if isempty(idx)
                if isfield(out,'data')
                    if isempty(out.data)
                        out.data = [];
                    else
                        sz = size(out.data); sz(1) = 0;
                        if isnumeric(out.data) || islogical(out.data)
                            out.data = nan(sz, 'like', double(out.data));
                        else
                            out.data = [];
                        end
                    end
                end
                for fn = {'tags','nodeTags','eleTags'}
                    if isfield(out, fn{1}); out.(fn{1}) = []; end
                end
                return;
            end
            if isfield(out,'data') && ~isempty(out.data)
                nd   = ndims(out.data);
                subs = repmat({':'}, 1, nd); subs{1} = idx;
                out.data = out.data(subs{:});
            end
            for fn = {'tags','nodeTags','eleTags'}
                f = fn{1};
                if isfield(out,f) && ~isempty(out.(f))
                    tmp = out.(f);
                    out.(f) = tmp(idx);
                end
            end
        end

        function result = expandToUniformArray(obj, arrayList, dtype)
            if nargin < 3 || isempty(dtype)
                dtype = obj.getMergeFloatType();
            end
            if isempty(arrayList); result = []; return; end
            n     = numel(arrayList);
            parts = cell(n, 1);
            for i = 1:n
                parts{i} = struct('modelUpdate', true, 'value', arrayList{i});
            end
            merged = post.utils.StructMerger.mergeParts( ...
                parts, 'ModelUpdateField', 'modelUpdate', 'Mode', 'prepend');
            result = merged.value;
            if ~strcmp(class(result), dtype)
                result = cast(result, dtype);
            end
        end

        function outType = getMergeFloatType(obj)
            outType = 'single';
            if isstruct(obj.dtype) && isfield(obj.dtype,'floatType') && ...
                    ~isempty(obj.dtype.floatType)
                outType = obj.dtype.floatType;
            end
        end
    end

    methods (Static, Access = protected)
        function respTypes = resolveRespTypes(allRespTypes, requestedRespType)
            if strlength(requestedRespType) > 0
                rt = char(requestedRespType);
                if ~ismember(rt, allRespTypes)
                    error('readResponse:InvalidRespType', ...
                        'Unknown respType "%s". Valid: %s', rt, strjoin(allRespTypes, ', '));
                end
                respTypes = {rt};
            else
                respTypes = allRespTypes;
            end
        end

        function [selectedTags, tagIdx] = resolveTagSelection(allTags, queryTags, errorId, entityLabel)
            allTags = double(allTags(:).');
            if isempty(queryTags)
                selectedTags = allTags;
                tagIdx = [];
                return;
            end

            queryTags = double(queryTags(:).');
            [tf, tagIdx] = ismember(queryTags, allTags);
            if ~all(tf)
                error(errorId, '%s tags not found: %s', entityLabel, mat2str(queryTags(~tf)));
            end
            selectedTags = allTags(tagIdx);
        end

        function [hasTags, selectedTags, tagIdx] = resolveOptionalDataTagSelection(data, tagField, queryTags, respTypes, dependentRespTypes, missingDataId, invalidQueryId, entityLabel)
            hasTags = isfield(data, tagField) && ~isempty(data.(tagField));
            selectedTags = [];
            tagIdx = [];

            requiresTags = ~isempty(queryTags) && any(ismember(respTypes, dependentRespTypes));
            if requiresTags && ~hasTags
                error(missingDataId, 'This dataset does not contain %s response tags.', lower(entityLabel));
            end

            if ~hasTags
                return;
            end

            tmp = data.(tagField);
            allTags = double(tmp(:).');
            [selectedTags, tagIdx] = post.resp.ResponseBase.resolveTagSelection( ...
                allTags, queryTags, invalidQueryId, entityLabel);
        end

        function out = subsetSecondDim(in, idx)
            nd = ndims(in);
            subs = repmat({':'}, 1, nd);
            subs{2} = idx;
            out = in(subs{:});
        end
    end
end
