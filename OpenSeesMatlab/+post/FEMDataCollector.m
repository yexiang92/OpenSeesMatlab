classdef FEMDataCollector < handle
    % FEMDataCollector
    %
    % Collect model/domain information from an OpenSees/OpenSeesMATLAB host.
    %
    % Robust version for model updates with node/element deletion/addition.

    properties (Access = private)
        host
        maps
        data

        nodeSortedTags
        nodeSortedIdx

        cachedNodeTags
        nodeStaticData

        cachedEleTags
        topoData

        familyCache
        classNameCache
        classFieldCache
        axisModeCache
    end

    properties (Constant, Access = private)
        LINE_CELL_TYPE_VTK  = struct('n2', int32(3))

        PLANE_CELL_TYPE_VTK = struct( ...
            'n3', int32(5), 'n4', int32(9), ...
            'n6', int32(22), 'n8', int32(23), 'n9', int32(28))

        SOLID_CELL_TYPE_VTK = struct( ...
            'n4', int32(10), 'n8', int32(12), ...
            'n10', int32(24), 'n20', int32(25), 'n27', int32(29))
    end

    methods
        function obj = FEMDataCollector(host, maps)
            if nargin < 1 || isempty(host)
                error('FEMDataCollector:InvalidInput', 'A host object is required.');
            end
            if nargin < 2 || isempty(maps)
                error('FEMDataCollector:InvalidInput', 'A tag map object is required.');
            end

            obj.host = host;
            obj.maps = maps;

            obj.familyCache     = containers.Map('KeyType','double','ValueType','char');
            obj.classNameCache  = containers.Map('KeyType','double','ValueType','char');
            obj.classFieldCache = containers.Map('KeyType','double','ValueType','char');
            obj.axisModeCache   = containers.Map('KeyType','double','ValueType','double');

            obj.cachedNodeTags = [];
            obj.nodeStaticData = [];
            obj.cachedEleTags  = [];
            obj.topoData       = [];

            obj.resetDomainData();
        end

        function collect(obj)
            obj.resetDomainData();
            obj.collectNodeInfo();
            obj.collectBounds();
            obj.collectFixedNodes();
            obj.collectMPConstraints();
            obj.collectElements();
            obj.collectNodalLoads();
            obj.collectElementLoads();
        end

        function modelInfo = getModelInfo(obj)
            obj.collect();
            modelInfo = struct( ...
                'Nodes',       obj.data.Nodes, ...
                'Fixed',       obj.data.Fixed, ...
                'MPConstraint',obj.data.MPConstraint, ...
                'Loads',       obj.data.Loads, ...
                'Elements',    obj.data.Elements, ...
                'NumNode',     numel(obj.data.Nodes.Tags), ...
                'NumElement',  numel(obj.data.Elements.Summary.Tags));
        end

        function save(obj, filename)
            modelInfo = obj.getModelInfo();
            store = post.utils.HDF5DataStore(filename, 'overwrite', true);
            store.write('/', modelInfo);
            store.writeAttributes('/', struct( ...
                'created_by', "OpenSeesMatlab", ...
                'num_node', modelInfo.NumNode, ...
                'num_element', modelInfo.NumElement));
        end

        function data = readFile(~, filename)
            store = post.utils.HDF5DataStore(filename, 'overwrite', false);
            data = store.load();
            if ~isstruct(data)
                error('FEMDataCollector:InvalidData', 'Data read from file is not a struct.');
            end
        end
    end

    methods (Access = private)
        function resetDomainData(obj)
            obj.nodeSortedTags = [];
            obj.nodeSortedIdx  = [];

            obj.data = struct();

            obj.data.Nodes = struct( ...
                'Tags',         zeros(0,1), ...
                'Coords',       zeros(0,3,'single'), ...
                'Ndm',          zeros(0,1), ...
                'Ndf',          zeros(0,1), ...
                'UnusedTags',   zeros(0,1), ...
                'Bounds',       zeros(1,6,'single'), ...
                'MinBoundSize', single(0), ...
                'MaxBoundSize', single(0));

            obj.data.Fixed = struct( ...
                'NodeTags',  zeros(0,1), ...
                'NodeIndex', zeros(0,1), ...
                'Coords',    zeros(0,3,'single'), ...
                'Dofs',      zeros(0,6,'uint8'));

            obj.data.MPConstraint = struct( ...
                'PairNodeTags', zeros(0,2), ...
                'Cells',        zeros(0,3), ...
                'MidCoords',    zeros(0,3,'single'), ...
                'Dofs',         zeros(0,6,'uint8'));

            obj.data.Loads = struct( ...
                'PatternTags', zeros(0,1), ...
                'Node', struct( ...
                    'PatternNodeTags', zeros(0,2), ...
                    'Values', zeros(0,3,'single')), ...
                'Element', struct( ...
                    'Beam', struct( ...
                        'PatternElementTags', zeros(0,2), ...
                        'Values', zeros(0,10,'single')), ...
                    'Surface', struct( ...
                        'PatternElementTags', zeros(0,2), ...
                        'Values', zeros(0,0,'single'))));

            obj.data.Elements = struct( ...
                'Summary', struct( ...
                    'Tags', zeros(0,1), ...
                    'ClassTags', zeros(0,1), ...
                    'CenterCoords', zeros(0,3,'single')), ...
                'Families', obj.emptyFamilies(), ...
                'Classes', struct());
        end

        function S = emptyFamilies(~)
            S = struct( ...
                'Truss', struct('Tags',zeros(0,1),'Cells',zeros(0,3)), ...
                'Beam', struct('Tags',zeros(0,1),'Cells',zeros(0,3), ...
                    'Midpoints',zeros(0,3,'single'),'Lengths',zeros(0,1,'single'), ...
                    'XAxis',zeros(0,3,'single'),'YAxis',zeros(0,3,'single'),'ZAxis',zeros(0,3,'single')), ...
                'Link', struct('Tags',zeros(0,1),'Cells',zeros(0,3), ...
                    'Midpoints',zeros(0,3,'single'),'Lengths',zeros(0,1,'single'), ...
                    'XAxis',zeros(0,3,'single'),'YAxis',zeros(0,3,'single'),'ZAxis',zeros(0,3,'single')), ...
                'Line', struct('Tags',zeros(0,1),'Cells',zeros(0,3)), ...
                'Plane', struct('Tags',zeros(0,1),'Cells',zeros(0,0),'CellTypes',zeros(0,1,'int32')), ...
                'Shell', struct('Tags',zeros(0,1),'Cells',zeros(0,0),'CellTypes',zeros(0,1,'int32')), ...
                'Solid', struct('Tags',zeros(0,1),'Cells',zeros(0,0),'CellTypes',zeros(0,1,'int32')), ...
                'Joint', struct('Tags',zeros(0,1)), ...
                'Contact', struct('Tags',zeros(0,1),'Cells',zeros(0,3)), ...
                'Unstructured', struct('Tags',zeros(0,1),'Cells',zeros(0,0),'CellTypes',zeros(0,1,'int32')));
        end

        function collectNodeInfo(obj)
            nodeTags = obj.bulkDouble('getNodeTags');
            nNode = numel(nodeTags);
            if nNode == 0
                obj.data.Nodes.Tags   = zeros(0,1);
                obj.data.Nodes.Coords = zeros(0,3,'single');
                obj.data.Nodes.Ndm    = zeros(0,1);
                obj.data.Nodes.Ndf    = zeros(0,1);
                return;
            end

            tagsCached = ~isempty(obj.cachedNodeTags) && ...
                         numel(obj.cachedNodeTags) == nNode && ...
                         all(obj.cachedNodeTags == nodeTags(:));

            if tagsCached
                ndm = obj.nodeStaticData.ndm;
                ndf = obj.nodeStaticData.ndf;
                obj.nodeSortedTags = obj.nodeStaticData.nodeSortedTags;
                obj.nodeSortedIdx  = obj.nodeStaticData.nodeSortedIdx;
            else
                ndm = zeros(nNode,1);
                ndf = zeros(nNode,1);

                for i = 1:nNode
                    tag = nodeTags(i);
                    ndm(i) = obj.scalarDouble(obj.callOps('getNDM', tag));
                    ndf(i) = obj.scalarDouble(obj.callOps('getNDF', tag));
                end

                [sortedTags, sortOrder] = sort(nodeTags(:));
                obj.nodeSortedTags = sortedTags;
                obj.nodeSortedIdx  = sortOrder;

                obj.cachedNodeTags = nodeTags(:);
                obj.nodeStaticData = struct( ...
                    'ndm', ndm, ...
                    'ndf', ndf, ...
                    'nodeSortedTags', sortedTags, ...
                    'nodeSortedIdx', sortOrder);
            end

            coords = zeros(nNode,3,'single');
            for i = 1:nNode
                tag = nodeTags(i);
                coord = double(obj.callOps('nodeCoord', tag));
                coords(i,:) = single(obj.padCoord3(coord, ndm(i)));
            end

            obj.data.Nodes.Tags   = nodeTags(:);
            obj.data.Nodes.Coords = coords;
            obj.data.Nodes.Ndm    = ndm(:);
            obj.data.Nodes.Ndf    = ndf(:);
        end

        function collectBounds(obj)
            coords = obj.data.Nodes.Coords;
            if isempty(coords)
                obj.data.Nodes.Bounds = zeros(1,6,'single');
                obj.data.Nodes.MinBoundSize = single(0);
                obj.data.Nodes.MaxBoundSize = single(0);
                return;
            end

            mn = min(coords,[],1);
            mx = max(coords,[],1);
            span = mx - mn;

            obj.data.Nodes.Bounds = single([mn(1) mx(1) mn(2) mx(2) mn(3) mx(3)]);
            obj.data.Nodes.MinBoundSize = single(min(span));
            obj.data.Nodes.MaxBoundSize = single(max(span));
        end

        function collectFixedNodes(obj)
            fixedTags = obj.bulkDouble('getFixedNodes');
            obj.collectFixedNodesBulk(fixedTags);
        end

        function collectFixedNodesBulk(obj, fixedTags)
            nMax = numel(fixedTags);
            fixedCoords  = zeros(nMax,3,'single');
            fixedDofs    = zeros(nMax,6,'uint8');
            fixedIdx     = zeros(nMax,1);
            fixedTagsOut = zeros(nMax,1);

            nFixed = 0;

            for i = 1:nMax
                tag = fixedTags(i);
                idx = obj.nodeIndex(tag);

                if isempty(idx) || idx < 1 || idx > size(obj.data.Nodes.Coords,1)
                    continue;
                end

                dofs = obj.bulkDouble('getFixedDOFs', tag);
                dofs = dofs(dofs >= 1 & dofs <= 6);

                mask = zeros(1,6,'uint8');
                if ~isempty(dofs)
                    mask(dofs) = 1;
                end

                nFixed = nFixed + 1;
                fixedTagsOut(nFixed)  = tag;
                fixedCoords(nFixed,:) = obj.data.Nodes.Coords(idx,:);
                fixedDofs(nFixed,:)   = mask;
                fixedIdx(nFixed)      = idx;
            end

            obj.data.Fixed.NodeTags  = fixedTagsOut(1:nFixed);
            obj.data.Fixed.NodeIndex = fixedIdx(1:nFixed);
            obj.data.Fixed.Coords    = fixedCoords(1:nFixed,:);
            obj.data.Fixed.Dofs      = fixedDofs(1:nFixed,:);
        end

        function collectMPConstraints(obj)
            rNodes = obj.bulkDouble('getRetainedNodes');
            if isempty(rNodes)
                return;
            end

            nEst = max(numel(rNodes) * 8, 64);
            pairTags = zeros(nEst,2);
            cells    = zeros(nEst,3);
            mids     = zeros(nEst,3,'single');
            dofs     = zeros(nEst,6,'uint8');
            nPair    = 0;

            for i = 1:numel(rNodes)
                rNode = rNodes(i);
                cNodesList = obj.bulkDouble('getConstrainedNodes', rNode);
                if isempty(cNodesList)
                    continue;
                end

                for j = 1:numel(cNodesList)
                    cNode = cNodesList(j);

                    idx1 = obj.nodeIndex(cNode);
                    idx2 = obj.nodeIndex(rNode);

                    if idx1 < 1 || idx2 < 1 || ...
                            idx1 > size(obj.data.Nodes.Coords,1) || idx2 > size(obj.data.Nodes.Coords,1)
                        continue;
                    end

                    d = obj.bulkDouble('getRetainedDOFs', rNode, cNode);
                    d = d(d >= 1 & d <= 6);

                    mask = zeros(1,6,'uint8');
                    if ~isempty(d)
                        mask(d) = 1;
                    end

                    p1 = obj.data.Nodes.Coords(idx1,:);
                    p2 = obj.data.Nodes.Coords(idx2,:);

                    nPair = nPair + 1;
                    pairTags(nPair,:) = [cNode, rNode];
                    cells(nPair,:)    = [2, idx1, idx2];
                    mids(nPair,:)     = single((p1 + p2)/2);
                    dofs(nPair,:)     = mask;
                end
            end

            obj.data.MPConstraint.PairNodeTags = pairTags(1:nPair,:);
            obj.data.MPConstraint.Cells        = cells(1:nPair,:);
            obj.data.MPConstraint.MidCoords    = mids(1:nPair,:);
            obj.data.MPConstraint.Dofs         = dofs(1:nPair,:);
        end

        function collectElements(obj)
            eleTags = obj.bulkDouble('getEleTags');
            nEle = numel(eleTags);

            if nEle == 0
                obj.cachedEleTags = [];
                obj.topoData = [];
                obj.data.Elements = struct( ...
                    'Summary', struct('Tags',zeros(0,1),'ClassTags',zeros(0,1),'CenterCoords',zeros(0,3,'single')), ...
                    'Families', obj.emptyFamilies(), ...
                    'Classes', struct());
                return;
            end

            if ~isempty(obj.cachedEleTags) && ...
                    numel(obj.cachedEleTags) == nEle && ...
                    all(obj.cachedEleTags == eleTags(:))
                obj.applyCachedTopo(eleTags);
                return;
            end

            obj.cachedEleTags = eleTags(:);
            obj.buildElementTopo(eleTags, nEle);
        end

        function applyCachedTopo(obj, eleTags)
            topo = obj.topoData;
            if isempty(topo) || ~isfield(topo,'elements') || ~isfield(topo,'eleNodeIdx')
                obj.buildElementTopo(eleTags, numel(eleTags));
                return;
            end

            nEleOld = numel(topo.eleNodeIdx);
            nEleNow = numel(eleTags);
            if nEleOld ~= nEleNow
                obj.buildElementTopo(eleTags, nEleNow);
                return;
            end

            centers = zeros(nEleNow,3,'single');
            validEle = false(nEleNow,1);

            for k = 1:nEleNow
                nodeIdx = topo.eleNodeIdx{k};
                nodeIdx = nodeIdx(nodeIdx >= 1 & nodeIdx <= size(obj.data.Nodes.Coords,1));

                if isempty(nodeIdx)
                    continue;
                end

                centers(k,:) = mean(obj.data.Nodes.Coords(nodeIdx,:),1);
                validEle(k) = true;
            end

            E = topo.elements;

            if isfield(E,'Summary')
                E.Summary.Tags         = E.Summary.Tags(validEle);
                E.Summary.ClassTags    = E.Summary.ClassTags(validEle);
                E.Summary.CenterCoords = centers(validEle,:);
            end

            E.Families = obj.filterFamiliesByValidSummary(E.Families, E.Summary.Tags);
            E.Classes  = obj.filterClassesByValidSummary(E.Classes, E.Summary.Tags);

            obj.data.Elements = E;
        end

        function buildElementTopo(obj, eleTags, nEle)
            sumTags      = zeros(nEle,1);
            sumClassTags = zeros(nEle,1);
            sumCenters   = zeros(nEle,3,'single');

            tBuf = obj.makeFamilyBuffers(nEle);
            classBuffers = struct();
            eleNodeIdx = cell(nEle,1);

            nValidEle = 0;

            for k = 1:nEle
                e = eleTags(k);

                classTag = obj.scalarDouble(obj.callOps('getEleClassTags', e));
                if isempty(classTag)
                    continue;
                end

                nodeTags = obj.bulkDouble('eleNodes', e);

                if isempty(nodeTags)
                    continue;
                end

                [idxs, xyz, ~] = obj.nodeTagsToIdxCoords(nodeTags);
                if isempty(idxs)
                    continue;
                end

                numNodes = numel(idxs);
                if size(xyz,1) ~= numNodes || isempty(xyz)
                    continue;
                end

                nValidEle = nValidEle + 1;
                eleNodeIdx{nValidEle} = idxs;

                center = single(mean(xyz,1));
                sumTags(nValidEle)      = e;
                sumClassTags(nValidEle) = classTag;
                sumCenters(nValidEle,:) = center;

                family     = obj.getFamily(classTag);
                classField = obj.getClassField(classTag);

                if numNodes == 2
                    lineCell = [2, idxs(1), idxs(2)];
                    classBuffers = obj.appendVTKCell(classBuffers, classField, lineCell, obj.LINE_CELL_TYPE_VTK.n2, e);

                    tBuf.nLine = tBuf.nLine + 1;
                    n = tBuf.nLine;
                    tBuf.lineTags(n) = e;
                    tBuf.lineCells(n,:) = lineCell;
                else
                    lineCell = [];
                end

                switch family
                    case 'truss'
                        tBuf.nTruss = tBuf.nTruss + 1;
                        n = tBuf.nTruss;
                        tBuf.trussTags(n) = e;
                        tBuf.trussCells(n,:) = lineCell;

                    case 'beam'
                        [mid,len,xA,yA,zA] = obj.lineGeom(xyz, e, classTag);
                        tBuf.nBeam = tBuf.nBeam + 1;
                        n = tBuf.nBeam;
                        tBuf.beamTags(n) = e;
                        tBuf.beamCells(n,:) = lineCell;
                        tBuf.beamMid(n,:) = mid;
                        tBuf.beamLen(n) = len;
                        tBuf.beamX(n,:) = xA;
                        tBuf.beamY(n,:) = yA;
                        tBuf.beamZ(n,:) = zA;

                    case 'link'
                        [mid,len,xA,yA,zA] = obj.lineGeom(xyz, e, classTag);
                        tBuf.nLink = tBuf.nLink + 1;
                        n = tBuf.nLink;
                        tBuf.linkTags(n) = e;
                        tBuf.linkCells(n,:) = lineCell;
                        tBuf.linkMid(n,:) = mid;
                        tBuf.linkLen(n) = len;
                        tBuf.linkX(n,:) = xA;
                        tBuf.linkY(n,:) = yA;
                        tBuf.linkZ(n,:) = zA;

                    case {'plane','shell','solid'}
                        [vtkCell, vtkType] = obj.makeSurfaceSolidCell(family, classTag, idxs, numNodes);
                        classBuffers = obj.appendVTKCell(classBuffers, classField, vtkCell, vtkType, e);
                        tBuf = obj.appendSurfaceSolid(tBuf, family, e, vtkCell, vtkType);

                    case 'joint'
                        [cellsJ, typesJ] = obj.makeJointCells(idxs);
                        tBuf.nJoint = tBuf.nJoint + 1;
                        tBuf.jointTags(tBuf.nJoint) = e;
                        for j = 1:numel(cellsJ)
                            classBuffers = obj.appendVTKCell(classBuffers, classField, cellsJ{j}, typesJ(j), e);
                            tBuf = obj.appendUnstru(tBuf, e, cellsJ{j}, typesJ(j));
                        end

                    case 'contact'
                        [contactCells, unusedTag, vtkCells] = obj.makeContactCells(classTag, nodeTags);
                        if ~isempty(unusedTag)
                            obj.data.Nodes.UnusedTags(end+1,1) = unusedTag;
                        end

                        nSeg = size(contactCells,1);
                        if nSeg > 0
                            idx0 = tBuf.nContact + 1;
                            idx1 = tBuf.nContact + nSeg;
                            tBuf.contactTags(idx0:idx1) = e;
                            tBuf.contactCells(idx0:idx1,:) = contactCells;
                            tBuf.nContact = idx1;
                        end

                        for j = 1:numel(vtkCells)
                            classBuffers = obj.appendVTKCell(classBuffers, classField, vtkCells{j}, obj.LINE_CELL_TYPE_VTK.n2, e);
                        end
                end
            end

            E = struct();
            E.Summary = struct( ...
                'Tags', sumTags(1:nValidEle), ...
                'ClassTags', sumClassTags(1:nValidEle), ...
                'CenterCoords', sumCenters(1:nValidEle,:));

            E.Families = obj.packFamilies(tBuf, nEle);
            E.Families = obj.filterFamiliesByValidSummary(E.Families, E.Summary.Tags);
            E.Classes  = obj.finalizeVTKBuffers(classBuffers);
            E.Classes  = obj.filterClassesByValidSummary(E.Classes, E.Summary.Tags);

            obj.data.Elements = E;

            obj.topoData = struct( ...
                'elements', E, ...
                'eleNodeIdx', {eleNodeIdx(1:nValidEle)});
        end

        function buf = makeFamilyBuffers(~, nEle)
            buf = struct();

            buf.nTruss = 0;
            buf.trussTags = zeros(nEle,1);
            buf.trussCells = zeros(nEle,3);

            buf.nBeam = 0;
            buf.beamTags = zeros(nEle,1);
            buf.beamCells = zeros(nEle,3);
            buf.beamMid = zeros(nEle,3,'single');
            buf.beamLen = zeros(nEle,1,'single');
            buf.beamX = zeros(nEle,3,'single');
            buf.beamY = zeros(nEle,3,'single');
            buf.beamZ = zeros(nEle,3,'single');

            buf.nLink = 0;
            buf.linkTags = zeros(nEle,1);
            buf.linkCells = zeros(nEle,3);
            buf.linkMid = zeros(nEle,3,'single');
            buf.linkLen = zeros(nEle,1,'single');
            buf.linkX = zeros(nEle,3,'single');
            buf.linkY = zeros(nEle,3,'single');
            buf.linkZ = zeros(nEle,3,'single');

            buf.nLine = 0;
            buf.lineTags = zeros(nEle,1);
            buf.lineCells = zeros(nEle,3);

            buf.nPlane = 0;
            buf.planeTags = zeros(nEle,1);
            buf.planeCells = cell(nEle,1);
            buf.planeTypes = zeros(nEle,1,'int32');

            buf.nShell = 0;
            buf.shellTags = zeros(nEle,1);
            buf.shellCells = cell(nEle,1);
            buf.shellTypes = zeros(nEle,1,'int32');

            buf.nSolid = 0;
            buf.solidTags = zeros(nEle,1);
            buf.solidCells = cell(nEle,1);
            buf.solidTypes = zeros(nEle,1,'int32');

            buf.nJoint = 0;
            buf.jointTags = zeros(nEle,1);

            buf.nContact = 0;
            buf.contactTags = zeros(4*nEle,1);
            buf.contactCells = zeros(4*nEle,3);

            buf.nUnstru = 0;
            buf.unstruTags = zeros(2*nEle,1);
            buf.unstruCells = cell(2*nEle,1);
            buf.unstruTypes = zeros(2*nEle,1,'int32');
        end

        function buf = appendSurfaceSolid(obj, buf, family, e, vtkCell, vtkType)
            switch family
                case 'plane'
                    buf.nPlane = buf.nPlane + 1;
                    n = buf.nPlane;
                    buf.planeTags(n) = e;
                    buf.planeCells{n} = vtkCell;
                    buf.planeTypes(n) = vtkType;
                case 'shell'
                    buf.nShell = buf.nShell + 1;
                    n = buf.nShell;
                    buf.shellTags(n) = e;
                    buf.shellCells{n} = vtkCell;
                    buf.shellTypes(n) = vtkType;
                case 'solid'
                    buf.nSolid = buf.nSolid + 1;
                    n = buf.nSolid;
                    buf.solidTags(n) = e;
                    buf.solidCells{n} = vtkCell;
                    buf.solidTypes(n) = vtkType;
            end
            buf = obj.appendUnstru(buf, e, vtkCell, vtkType);
        end

        function buf = appendUnstru(~, buf, e, vtkCell, vtkType)
            buf.nUnstru = buf.nUnstru + 1;
            n = buf.nUnstru;
            buf.unstruTags(n) = e;
            buf.unstruCells{n} = vtkCell;
            buf.unstruTypes(n) = int32(vtkType);
        end

        function Fam = packFamilies(obj, buf, ~)
            trim = @(v,n) v(1:n,:);

            Fam = struct();
            Fam.Truss = struct( ...
                'Tags', trim(buf.trussTags,buf.nTruss), ...
                'Cells', trim(buf.trussCells,buf.nTruss));

            Fam.Beam = struct( ...
                'Tags', trim(buf.beamTags,buf.nBeam), ...
                'Cells', trim(buf.beamCells,buf.nBeam), ...
                'Midpoints', trim(buf.beamMid,buf.nBeam), ...
                'Lengths', buf.beamLen(1:buf.nBeam), ...
                'XAxis', trim(buf.beamX,buf.nBeam), ...
                'YAxis', trim(buf.beamY,buf.nBeam), ...
                'ZAxis', trim(buf.beamZ,buf.nBeam));

            Fam.Link = struct( ...
                'Tags', trim(buf.linkTags,buf.nLink), ...
                'Cells', trim(buf.linkCells,buf.nLink), ...
                'Midpoints', trim(buf.linkMid,buf.nLink), ...
                'Lengths', buf.linkLen(1:buf.nLink), ...
                'XAxis', trim(buf.linkX,buf.nLink), ...
                'YAxis', trim(buf.linkY,buf.nLink), ...
                'ZAxis', trim(buf.linkZ,buf.nLink));

            Fam.Line = struct( ...
                'Tags', trim(buf.lineTags,buf.nLine), ...
                'Cells', trim(buf.lineCells,buf.nLine));

            Fam.Plane = struct( ...
                'Tags', buf.planeTags(1:buf.nPlane), ...
                'Cells', obj.padJagged(buf.planeCells(1:buf.nPlane),'double'), ...
                'CellTypes', buf.planeTypes(1:buf.nPlane));

            Fam.Shell = struct( ...
                'Tags', buf.shellTags(1:buf.nShell), ...
                'Cells', obj.padJagged(buf.shellCells(1:buf.nShell),'double'), ...
                'CellTypes', buf.shellTypes(1:buf.nShell));

            Fam.Solid = struct( ...
                'Tags', buf.solidTags(1:buf.nSolid), ...
                'Cells', obj.padJagged(buf.solidCells(1:buf.nSolid),'double'), ...
                'CellTypes', buf.solidTypes(1:buf.nSolid));

            Fam.Joint = struct('Tags', buf.jointTags(1:buf.nJoint));

            Fam.Contact = struct( ...
                'Tags', buf.contactTags(1:buf.nContact), ...
                'Cells', buf.contactCells(1:buf.nContact,:));

            Fam.Unstructured = struct( ...
                'Tags', buf.unstruTags(1:buf.nUnstru), ...
                'Cells', obj.padJagged(buf.unstruCells(1:buf.nUnstru),'double'), ...
                'CellTypes', buf.unstruTypes(1:buf.nUnstru));
        end

        function Fam = filterFamiliesByValidSummary(~, Fam, validTags)
            if isempty(validTags)
                Fam.Truss.Tags = zeros(0,1); Fam.Truss.Cells = zeros(0,3);
                Fam.Beam.Tags = zeros(0,1); Fam.Beam.Cells = zeros(0,3); Fam.Beam.Midpoints = zeros(0,3,'single'); Fam.Beam.Lengths = zeros(0,1,'single'); Fam.Beam.XAxis = zeros(0,3,'single'); Fam.Beam.YAxis = zeros(0,3,'single'); Fam.Beam.ZAxis = zeros(0,3,'single');
                Fam.Link.Tags = zeros(0,1); Fam.Link.Cells = zeros(0,3); Fam.Link.Midpoints = zeros(0,3,'single'); Fam.Link.Lengths = zeros(0,1,'single'); Fam.Link.XAxis = zeros(0,3,'single'); Fam.Link.YAxis = zeros(0,3,'single'); Fam.Link.ZAxis = zeros(0,3,'single');
                Fam.Line.Tags = zeros(0,1); Fam.Line.Cells = zeros(0,3);
                Fam.Plane.Tags = zeros(0,1); Fam.Plane.Cells = zeros(0,0); Fam.Plane.CellTypes = zeros(0,1,'int32');
                Fam.Shell.Tags = zeros(0,1); Fam.Shell.Cells = zeros(0,0); Fam.Shell.CellTypes = zeros(0,1,'int32');
                Fam.Solid.Tags = zeros(0,1); Fam.Solid.Cells = zeros(0,0); Fam.Solid.CellTypes = zeros(0,1,'int32');
                Fam.Joint.Tags = zeros(0,1);
                Fam.Contact.Tags = zeros(0,1); Fam.Contact.Cells = zeros(0,3);
                Fam.Unstructured.Tags = zeros(0,1); Fam.Unstructured.Cells = zeros(0,0); Fam.Unstructured.CellTypes = zeros(0,1,'int32');
                return;
            end

            fnames = fieldnames(Fam);
            for i = 1:numel(fnames)
                fn = fnames{i};
                S = Fam.(fn);

                if ~isstruct(S) || ~isfield(S,'Tags')
                    continue;
                end

                mask = ismember(S.Tags, validTags);
                S.Tags = S.Tags(mask);

                if isfield(S,'Cells') && ~isempty(S.Cells)
                    if size(S.Cells,1) >= numel(mask)
                        S.Cells = S.Cells(mask,:);
                    end
                end
                if isfield(S,'CellTypes') && ~isempty(S.CellTypes)
                    if numel(S.CellTypes) >= numel(mask)
                        S.CellTypes = S.CellTypes(mask);
                    end
                end
                if isfield(S,'Midpoints') && ~isempty(S.Midpoints)
                    if size(S.Midpoints,1) >= numel(mask)
                        S.Midpoints = S.Midpoints(mask,:);
                    end
                end
                if isfield(S,'Lengths') && ~isempty(S.Lengths)
                    if numel(S.Lengths) >= numel(mask)
                        S.Lengths = S.Lengths(mask);
                    end
                end
                if isfield(S,'XAxis') && ~isempty(S.XAxis)
                    if size(S.XAxis,1) >= numel(mask)
                        S.XAxis = S.XAxis(mask,:);
                    end
                end
                if isfield(S,'YAxis') && ~isempty(S.YAxis)
                    if size(S.YAxis,1) >= numel(mask)
                        S.YAxis = S.YAxis(mask,:);
                    end
                end
                if isfield(S,'ZAxis') && ~isempty(S.ZAxis)
                    if size(S.ZAxis,1) >= numel(mask)
                        S.ZAxis = S.ZAxis(mask,:);
                    end
                end

                Fam.(fn) = S;
            end
        end

        function C = filterClassesByValidSummary(~, C, validTags)
            if isempty(C)
                return;
            end
            fns = fieldnames(C);
            for i = 1:numel(fns)
                fn = fns{i};
                S = C.(fn);
                if ~isstruct(S) || ~isfield(S,'ElementTags')
                    continue;
                end

                mask = ismember(S.ElementTags, validTags);
                S.ElementTags = S.ElementTags(mask);

                if isfield(S,'Cells') && ~isempty(S.Cells) && size(S.Cells,1) >= numel(mask)
                    S.Cells = S.Cells(mask,:);
                end
                if isfield(S,'CellTypes') && ~isempty(S.CellTypes) && numel(S.CellTypes) >= numel(mask)
                    S.CellTypes = S.CellTypes(mask);
                end

                C.(fn) = S;
            end
        end

        function [mid,len,xA,yA,zA] = lineGeom(obj, xyz, eleTag, classTag)
            mid = single((xyz(1,:) + xyz(2,:))/2);
            len = single(norm(xyz(2,:) - xyz(1,:)));
            [xA,yA,zA] = obj.getLocalAxis(eleTag, classTag);
        end

        function [vtkCell, vtkType] = makeSurfaceSolidCell(obj, family, classTag, idxs, numNodes)
            if any(classTag == obj.maps.EleTags.Wall) && numNodes >= 4
                idxs = idxs([1,2,4,3]);
            end

            vtkCell = [numel(idxs), idxs];
            switch family
                case {'plane','shell'}
                    vtkType = obj.planeCellType(numNodes);
                otherwise
                    vtkType = obj.solidCellType(numNodes);
            end
        end

        function [cellsJ, typesJ] = makeJointCells(obj, idxs)
            vtkType = obj.planeCellType(4);
            cellsJ = {[4, idxs(1:4)]};
            typesJ = int32(vtkType);
            if numel(idxs) == 7
                cellsJ{2,1} = [4, idxs(5), idxs(2), idxs(6), idxs(4)];
                typesJ(2,1) = int32(vtkType);
            end
        end

        function [cellsMat, unusedTag, vtkCells] = makeContactCells(obj, classTag, nodeTags)
            unusedTag = [];
            vtkCells  = {};
            cellsMat  = zeros(0,3);

            if ismember(classTag, [22,23,24,25,140])
                if numel(nodeTags) > 2
                    mid = floor(numel(nodeTags)/2);
                    part1 = nodeTags(1:mid);
                    part2 = fliplr(nodeTags(mid+1:end));
                    nPair = min(numel(part1), numel(part2));

                    tmp = zeros(nPair,3);
                    nSeg = 0;

                    for i = 1:nPair
                        i1 = obj.nodeIndex(part1(i));
                        i2 = obj.nodeIndex(part2(i));

                        if i1 < 1 || i2 < 1
                            continue;
                        end

                        nSeg = nSeg + 1;
                        c = [2, i1, i2];
                        tmp(nSeg,:) = c;
                        vtkCells{end+1,1} = c; %#ok<AGROW>
                    end

                    cellsMat = tmp(1:nSeg,:);
                end
            else
                if numel(nodeTags) < 2
                    return;
                end

                cNode = nodeTags(end-1);
                rNodes = nodeTags(1:end-2);
                unusedTag = nodeTags(end);

                idx1 = obj.nodeIndex(cNode);
                if idx1 < 1
                    return;
                end

                tmp = zeros(numel(rNodes),3);
                nSeg = 0;

                for i = 1:numel(rNodes)
                    idx2 = obj.nodeIndex(rNodes(i));
                    if idx2 < 1
                        continue;
                    end

                    nSeg = nSeg + 1;
                    c = [2, idx1, idx2];
                    tmp(nSeg,:) = c;
                    vtkCells{end+1,1} = c; %#ok<AGROW>
                end

                cellsMat = tmp(1:nSeg,:);
            end
        end

        function collectNodalLoads(obj)
            patternTags = obj.safeCall('getPatterns');
            obj.data.Loads.PatternTags = patternTags(:);
            if isempty(patternTags)
                return;
            end

            nMax = numel(patternTags) * 64;
            pairRows = zeros(nMax,2);
            valRows = zeros(nMax,3,'single');
            nRow = 0;

            for iPat = 1:numel(patternTags)
                pat = patternTags(iPat);

                nlTags = obj.bulkDouble('getNodeLoadTags', pat);
                if isempty(nlTags)
                    continue;
                end

                nlTags = nlTags(ismember(nlTags, obj.data.Nodes.Tags));
                if isempty(nlTags)
                    continue;
                end

                nlData = double(obj.callOps('getNodeLoadData', pat));

                nNL = numel(nlTags);

                if isempty(nlData)
                    for j = 1:nNL
                        nRow = nRow + 1;
                        pairRows(nRow,:) = [pat, nlTags(j)];
                    end
                else
                    flat = nlData(:);
                    ndof = max(1, floor(numel(flat)/nNL));
                    M = reshape(flat(1:nNL*ndof), ndof, nNL).';
                    take = min(3,size(M,2));

                    for j = 1:nNL
                        nRow = nRow + 1;
                        pairRows(nRow,:) = [pat, nlTags(j)];
                        valRows(nRow,1:take) = single(M(j,1:take));
                    end
                end
            end

            obj.data.Loads.Node.PatternNodeTags = pairRows(1:nRow,:);
            obj.data.Loads.Node.Values = valRows(1:nRow,:);
        end

        function collectElementLoads(obj)
            patternTags = obj.data.Loads.PatternTags;
            if isempty(patternTags)
                return;
            end

            nMax = numel(patternTags) * 64;
            bPairs = zeros(nMax,2);
            bVals  = zeros(nMax,10,'single');
            nBeam  = 0;

            sPairs = zeros(nMax,2);
            sVals  = cell(nMax,1);
            nSurf  = 0;

            currentEleTags = obj.data.Elements.Summary.Tags;

            for iPat = 1:numel(patternTags)
                pat = patternTags(iPat);

                elTags = double(obj.bulkDouble('getEleLoadTags', pat));
                if isempty(elTags)
                    continue;
                end

                elTags = elTags(ismember(elTags, currentEleTags));
                if isempty(elTags)
                    continue;
                end

                elCls = double(obj.bulkDouble('getEleLoadClassTags', pat));

                elData = double(obj.callOps('getEleLoadData', pat));

                loc = 1;

                for j = 1:numel(elTags)
                    tag = elTags(j);

                    if ~any(currentEleTags == tag)
                        continue;
                    end

                    cls = 0;
                    if j <= numel(elCls)
                        cls = elCls(j);
                    end

                    ntags = double(obj.callOps('eleNodes', tag));

                    if numel(ntags) == 2
                        wya = 0.0; wyb = 0.0;
                        wza = 0.0; wzb = 0.0;
                        wxa = 0.0; wxb = 0.0;
                        xa  = 0.0; xb  = 1.0;
                        rawNcol = 0;

                        if isempty(elData)
                        elseif cls == 3
                            vals = elData(loc:min(loc+1, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); wyb = vals(1); end
                            if numel(vals) >= 2, wxa = vals(2); wxb = vals(2); end
                            rawNcol = 2;
                            loc = loc + 2;

                        elseif cls == 5
                            vals = elData(loc:min(loc+2, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); wyb = vals(1); end
                            if numel(vals) >= 2, wza = vals(2); wzb = vals(2); end
                            if numel(vals) >= 3, wxa = vals(3); wxb = vals(3); end
                            rawNcol = 3;
                            loc = loc + 3;

                        elseif cls == 4
                            vals = elData(loc:min(loc+2, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); end
                            if numel(vals) >= 2, xa  = vals(2); end
                            if numel(vals) >= 3, wxa = vals(3); end
                            xb = -10000;
                            rawNcol = 3;
                            loc = loc + 3;

                        elseif cls == 6
                            vals = elData(loc:min(loc+3, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); end
                            if numel(vals) >= 2, wza = vals(2); end
                            if numel(vals) >= 3, xa  = vals(3); end
                            if numel(vals) >= 4, wxa = vals(4); end
                            xb = -10000;
                            rawNcol = 4;
                            loc = loc + 4;

                        elseif cls == 12
                            vals = elData(loc:min(loc+5, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); end
                            if numel(vals) >= 2, wyb = vals(2); end
                            if numel(vals) >= 3, wxa = vals(3); end
                            if numel(vals) >= 4, wxb = vals(4); end
                            if numel(vals) >= 5, xa  = vals(5); end
                            if numel(vals) >= 6, xb  = vals(6); end
                            rawNcol = 6;
                            loc = loc + 6;

                        elseif cls == 121
                            vals = elData(loc:min(loc+7, numel(elData)));
                            if numel(vals) >= 1, wya = vals(1); end
                            if numel(vals) >= 2, wza = vals(2); end
                            if numel(vals) >= 3, wxa = vals(3); end
                            if numel(vals) >= 4, xa  = vals(4); end
                            if numel(vals) >= 5, xb  = vals(5); end
                            if numel(vals) >= 6, wyb = vals(6); end
                            if numel(vals) >= 7, wzb = vals(7); end
                            if numel(vals) >= 8, wxb = vals(8); end
                            rawNcol = 8;
                            loc = loc + 8;
                        else
                            rawNcol = 0;
                        end

                        nBeam = nBeam + 1;
                        bPairs(nBeam,:) = [pat, tag];
                        bVals(nBeam,:) = single([wya, wyb, wza, wzb, wxa, wxb, xa, xb, cls, rawNcol]);

                    elseif numel(ntags) == 3 || numel(ntags) == 4
                        nSurf = nSurf + 1;
                        sPairs(nSurf,:) = [pat, tag];
                        sVals{nSurf} = single([]);
                    end
                end
            end

            obj.data.Loads.Element.Beam.PatternElementTags = bPairs(1:nBeam,:);
            obj.data.Loads.Element.Beam.Values = bVals(1:nBeam,:);
            obj.data.Loads.Element.Beam.Types = {'wya','wyb','wza','wzb','wxa','wxb','xa','xb','clsTag','rawNcol'};

            obj.data.Loads.Element.Surface.PatternElementTags = sPairs(1:nSurf,:);
            obj.data.Loads.Element.Surface.Values = obj.padJagged(sVals(1:nSurf), 'single');
        end

        function family = getFamily(obj, classTag)
            if isKey(obj.familyCache, classTag)
                family = obj.familyCache(classTag);
                return;
            end

            m = obj.maps.EleTags;
            if any(classTag == m.Truss)
                family = 'truss';
            elseif any(classTag == m.Beam)
                family = 'beam';
            elseif any(classTag == m.Link)
                family = 'link';
            elseif any(classTag == m.Plane)
                family = 'plane';
            elseif any(classTag == m.Shell)
                family = 'shell';
            elseif any(classTag == m.Solid)
                family = 'solid';
            elseif any(classTag == m.Joint)
                family = 'joint';
            elseif any(classTag == m.Contact)
                family = 'contact';
            else
                family = 'other';
            end
            obj.familyCache(classTag) = family;
        end

        function fn = getClassField(obj, classTag)
            if isKey(obj.classFieldCache, classTag)
                fn = obj.classFieldCache(classTag);
                return;
            end

            if isKey(obj.classNameCache, classTag)
                name = obj.classNameCache(classTag);
            else
                name = char(string(obj.maps.getClassName(classTag)));
                obj.classNameCache(classTag) = name;
            end

            fn = char(matlab.lang.makeValidName(string(name)));
            obj.classFieldCache(classTag) = fn;
        end

        function [xA,yA,zA] = getLocalAxis(obj, eleTag, classTag)
            mode = 0;
            if isKey(obj.axisModeCache, classTag)
                mode = obj.axisModeCache(classTag);
            end

            if mode == 1
                xA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'xaxis')));
                yA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'yaxis')));
                zA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'zaxis')));
            elseif mode == 2
                xA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'xlocal')));
                yA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'ylocal')));
                zA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'zlocal')));
            else
                xA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'xaxis')));
                yA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'yaxis')));
                zA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'zaxis')));
                if any(xA ~= 0) || any(yA ~= 0) || any(zA ~= 0)
                    obj.axisModeCache(classTag) = 1;
                else
                    xA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'xlocal')));
                    yA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'ylocal')));
                    zA = single(obj.normalize3(obj.bulkDouble('eleResponse', eleTag, 'zlocal')));
                    obj.axisModeCache(classTag) = 2;
                end
            end
        end

        function classBuffers = appendVTKCell(~, classBuffers, fn, cellData, cellType, eleTag)
            if ~isfield(classBuffers, fn)
                classBuffers.(fn) = struct( ...
                    'Cells', {{cellData}}, ...
                    'CellTypes', int32(cellType), ...
                    'ElementTags', eleTag);
            else
                classBuffers.(fn).Cells{end+1,1} = cellData;
                classBuffers.(fn).CellTypes(end+1,1) = int32(cellType);
                classBuffers.(fn).ElementTags(end+1,1) = eleTag;
            end
        end

        function S = finalizeVTKBuffers(obj, S)
            fns = fieldnames(S);
            for i = 1:numel(fns)
                fn = fns{i};
                S.(fn).Cells = obj.padJagged(S.(fn).Cells, 'double');
                S.(fn).CellTypes = int32(S.(fn).CellTypes(:));
                S.(fn).ElementTags = S.(fn).ElementTags(:);
            end
        end

        function out = planeCellType(obj, n)
            key = sprintf('n%d', n);
            if isfield(obj.PLANE_CELL_TYPE_VTK, key)
                out = obj.PLANE_CELL_TYPE_VTK.(key);
            elseif n == 3
                out = obj.PLANE_CELL_TYPE_VTK.n3;
            else
                out = obj.PLANE_CELL_TYPE_VTK.n4;
            end
        end

        function out = solidCellType(obj, n)
            key = sprintf('n%d', n);
            if isfield(obj.SOLID_CELL_TYPE_VTK, key)
                out = obj.SOLID_CELL_TYPE_VTK.(key);
            elseif n <= 4
                out = obj.SOLID_CELL_TYPE_VTK.n4;
            else
                out = obj.SOLID_CELL_TYPE_VTK.n8;
            end
        end

        function idx = nodeIndex(obj, tag)
            pos = obj.bsearch(obj.nodeSortedTags, tag);
            if pos == 0
                idx = 0;
            else
                idx = obj.nodeSortedIdx(pos);
            end
        end

        function [idxs, xyz, valid] = nodeTagsToIdxCoords(obj, nodeTags)
            n = numel(nodeTags);
            idxs = zeros(1,n);
            for i = 1:n
                idxs(i) = obj.nodeIndex(nodeTags(i));
            end

            valid = idxs >= 1 & idxs <= size(obj.data.Nodes.Coords,1);
            idxs = idxs(valid);

            if isempty(idxs)
                xyz = zeros(0,3,'single');
            else
                xyz = obj.data.Nodes.Coords(idxs,:);
            end
        end

        function out = callOps(obj, method, varargin)
            out = obj.host.call(method, varargin{:});
        end

        function v = bulkDouble(obj, method, varargin)
            raw = obj.callOps(method, varargin{:});
            if isempty(raw)
                v = zeros(1,0);
            else
                v = double(raw(:).');
            end
        end

        function x = scalarDouble(~, x)
            if isempty(x)
                x = [];
                return;
            end
            x = double(x(1));
        end

        function tags = safeCall(obj, method, varargin)
            try
                tags = obj.bulkDouble(method, varargin{:});
            catch
                tags = [];
            end
        end

        function coord = padCoord3(~, coord, ndim)
            coord = double(coord(:).');
            if isempty(coord)
                coord = [0 0 0];
                return;
            end
            switch ndim
                case 1
                    coord = [coord(1), 0, 0];
                case 2
                    coord = [coord(1), coord(2), 0];
                otherwise
                    coord = coord(1:min(3,numel(coord)));
                    if numel(coord) < 3
                        coord(end+1:3) = 0;
                    end
            end
        end

        function v = normalize3(~, v)
            v = double(v(:).');
            if isempty(v)
                v = zeros(1,3);
                return;
            end
            if numel(v) < 3
                v(3) = 0;
            else
                v = v(1:3);
            end
            n = norm(v);
            if n > 0
                v = v / n;
            end
        end

        function M = padJagged(~, C, typeName)
            if nargin < 3
                typeName = 'double';
            end
            if isempty(C)
                M = zeros(0,0,typeName);
                return;
            end

            n = numel(C);
            maxLen = 0;
            for i = 1:n
                maxLen = max(maxLen, numel(C{i}));
            end

            M = zeros(n, maxLen, typeName);
            for i = 1:n
                row = C{i};
                if ~isempty(row)
                    row = row(:).';
                    M(i,1:numel(row)) = cast(row, typeName);
                end
            end
        end

        function pos = bsearch(~, sortedVec, target)
            lo = 1;
            hi = numel(sortedVec);
            pos = 0;

            while lo <= hi
                mid = floor((lo + hi) / 2);
                v = sortedVec(mid);
                if v == target
                    pos = mid;
                    return;
                elseif v < target
                    lo = mid + 1;
                else
                    hi = mid - 1;
                end
            end
        end
    end
end