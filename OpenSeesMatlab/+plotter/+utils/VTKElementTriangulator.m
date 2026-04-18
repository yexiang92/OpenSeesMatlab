classdef VTKElementTriangulator < handle
    %VTKELEMENTTRIANGULATOR Convert MATLAB cell-based element data to plot-ready mesh data.
    %
    % This class expands surface / solid VTK-style cells into a triangle mesh
    % and also provides reusable conversion utilities for line elements.
    %
    % Supported features
    % ------------------
    % 1) Surface / solid cell triangulation
    %    - triangle / quad / tetra / hexahedron
    %    - quadratic / biquadratic / triquadratic variants
    %
    % 2) Surface edge extraction
    %    - returns NaN-separated polyline points for direct line plotting
    %
    % 3) Line element conversion
    %    - converts line-type cells into NaN-separated polyline points
    %    - also returns segment connectivity for downstream reuse
    %
    % 4) Scalar attachment
    %    - node-wise scalars
    %    - element-wise scalars
    %
    % Important output fields
    % -----------------------
    % Surface results include:
    %   Points        : expanded triangle-mesh points
    %   Triangles     : triangle connectivity into Points
    %   EdgePoints    : NaN-separated surface edge polyline points
    %   MidPoints     : one midpoint per original input cell
    %   TriCellIds    : for each triangle, which original cell it belongs to
    %
    % If node-wise scalars are supplied:
    %   NodeScalars   : original node scalar array
    %   PointScalars  : expanded scalar array aligned with Points
    %   EdgeScalars   : expanded scalar array aligned with EdgePoints
    %
    % If element-wise scalars are supplied:
    %   CellScalars   : original element scalar array
    %
    % Author: OpenAI ChatGPT

    properties
        % Original nodal coordinates, size N x 2 or N x 3.
        Points double = zeros(0, 3)

        % Optional scalar values.
        Scalars = []

        % If true, Scalars are interpreted element-wise.
        % If false, Scalars are interpreted node-wise.
        ScalarsByElement logical = false
    end

    properties (SetAccess = private)
        % Expanded triangle-mesh vertices.
        FacePoints double = zeros(0, 3)

        % NaN-separated polyline points for surface edges.
        FaceLinePoints double = zeros(0, 3)

        % One midpoint per added surface/solid cell.
        FaceMidPoints double = zeros(0, 3)

        % Triangle connectivity into FacePoints, size Nt x 3.
        Triangles double = zeros(0, 3)

        % For each triangle, which original surface/solid cell it belongs to.
        TriCellIds double = zeros(0, 1)

        % Expanded scalar values for FacePoints.
        FaceScalars double = zeros(0, 1)

        % Expanded scalar values for FaceLinePoints.
        FaceLineScalars double = zeros(0, 1)

        % NaN-separated polyline points for line elements.
        LinePoints double = zeros(0, 3)

        % One midpoint per added line cell.
        LineMidPoints double = zeros(0, 3)

        % Segment connectivity into LineMeshPoints, size Ns x 2.
        LineSegments double = zeros(0, 2)

        % Expanded line-mesh vertices for LineSegments.
        LineMeshPoints double = zeros(0, 3)

        % Scalars attached to LineMeshPoints.
        LineScalars double = zeros(0, 1)

        % Scalars attached to NaN-separated LinePoints.
        LinePolylineScalars double = zeros(0, 1)
    end

    properties (Access = private)
        SurfaceScalarElementIndex double = 1
        LineScalarElementIndex double = 1
    end

    methods
        function obj = VTKElementTriangulator(points, varargin)
            %VTKELEMENTTRIANGULATOR Create a triangulation helper.
            %
            % Parameters
            % ----------
            % points : double matrix
            %     Nodal coordinates, size N x 2 or N x 3.
            %
            % Name-value options
            % ------------------
            % 'Scalars' : []
            %     Optional scalar array.
            %
            % 'ScalarsByElement' : false
            %     True for element-wise scalars, false for node-wise scalars.
            if nargin < 1 || isempty(points)
                return;
            end

            obj.Points = obj.ensure3DPoints(points);

            if ~isempty(varargin)
                for k = 1:2:numel(varargin)
                    name = lower(string(varargin{k}));
                    value = varargin{k + 1};
                    switch name
                        case "scalars"
                            obj.Scalars = value;
                        case "scalarsbyelement"
                            obj.ScalarsByElement = logical(value);
                        otherwise
                            error('VTKElementTriangulator:UnknownOption', ...
                                'Unknown option "%s".', varargin{k});
                    end
                end
            end
        end

        function resetSurfaceData(obj)
            %RESETSURFACEDATA Clear all accumulated surface / solid triangulation results.
            obj.FacePoints = zeros(0, 3);
            obj.FaceLinePoints = zeros(0, 3);
            obj.FaceMidPoints = zeros(0, 3);
            obj.Triangles = zeros(0, 3);
            obj.TriCellIds = zeros(0, 1);
            obj.FaceScalars = zeros(0, 1);
            obj.FaceLineScalars = zeros(0, 1);
            obj.SurfaceScalarElementIndex = 1;
        end

        function resetLineData(obj)
            %RESETLINEDATA Clear all accumulated line conversion results.
            obj.LinePoints = zeros(0, 3);
            obj.LineMidPoints = zeros(0, 3);
            obj.LineSegments = zeros(0, 2);
            obj.LineMeshPoints = zeros(0, 3);
            obj.LineScalars = zeros(0, 1);
            obj.LinePolylineScalars = zeros(0, 1);
            obj.LineScalarElementIndex = 1;
        end

        function addCells(obj, cellTypes, cells)
            %ADDCELLS Add multiple surface/solid cells.
            [cellTypes, cells] = obj.expandInput(cellTypes, cells);
            for i = 1:numel(cells)
                obj.addCell(cellTypes(i), cells{i});
            end
        end

        function addCell(obj, cellType, cellConn)
            %ADDCELL Add one surface/solid cell and triangulate it.
            conn = obj.normalizeConnectivity(cellConn);
            data = obj.Points(conn, :);

            baseIdx = size(obj.FacePoints, 1) + 1;

            obj.FacePoints = [obj.FacePoints; data]; %#ok<AGROW>
            obj.FaceMidPoints = [obj.FaceMidPoints; mean(data, 1)]; %#ok<AGROW>

            if ~isempty(obj.Scalars) && ~obj.ScalarsByElement
                vals = obj.extractScalars(conn, numel(conn), true);
                obj.FaceScalars = [obj.FaceScalars; vals(:)]; %#ok<AGROW>
            end

            obj.addSurfaceTriangles(cellType, baseIdx);
            obj.addSurfaceBoundaryLines(cellType, baseIdx);
        end

        function addLineCells(obj, cellTypes, cells)
            %ADDLINECELLS Add multiple line cells.
            [cellTypes, cells] = obj.expandInput(cellTypes, cells);
            for i = 1:numel(cells)
                obj.addLineCell(cellTypes(i), cells{i});
            end
        end

        function addLineCell(obj, cellType, cellConn)
            %ADDLINECELL Add one line cell and convert it for plotting/reuse.
            conn = obj.normalizeLineConnectivity(cellConn);

            seq = obj.getLineSequence(cellType, numel(conn));
            if isempty(seq)
                return;
            end

            orderedConn = conn(seq + 1);
            pts = obj.Points(orderedConn, :);

            obj.LineMidPoints = [obj.LineMidPoints; mean(pts, 1)]; %#ok<AGROW>

            baseIdx = size(obj.LineMeshPoints, 1) + 1;
            obj.LineMeshPoints = [obj.LineMeshPoints; pts]; %#ok<AGROW>

            if size(pts, 1) >= 2
                seg = [(baseIdx:baseIdx + size(pts, 1) - 2).', ...
                       (baseIdx + 1:baseIdx + size(pts, 1) - 1).'];
                obj.LineSegments = [obj.LineSegments; seg]; %#ok<AGROW>
            end

            nanRow = [nan, nan, nan];
            obj.LinePoints = [obj.LinePoints; pts; nanRow]; %#ok<AGROW>

            if ~isempty(obj.Scalars) && ~obj.ScalarsByElement
                vals = obj.extractScalars(orderedConn, numel(orderedConn), false);
                obj.LineScalars = [obj.LineScalars; vals(:)]; %#ok<AGROW>
                obj.LinePolylineScalars = [obj.LinePolylineScalars; vals(:); nan]; %#ok<AGROW>
            end
        end

        function out = getSurfaceResults(obj)
            %GETSURFACERESULTS Return triangulated surface/solid results.
            out = struct();
            out.Points     = obj.FacePoints;
            out.EdgePoints = obj.FaceLinePoints;
            out.MidPoints  = obj.FaceMidPoints;
            out.Triangles  = obj.Triangles;
            out.TriCellIds = obj.TriCellIds;

            if ~isempty(obj.Scalars)
                if obj.ScalarsByElement
                    out.CellScalars = obj.Scalars(:);
                else
                    out.NodeScalars  = obj.Scalars(:);
                    out.PointScalars = obj.FaceScalars;
                    out.EdgeScalars  = obj.FaceLineScalars;
                end
            end
        end

        function out = getLineResults(obj)
            %GETLINERESULTS Return converted line-element results.
            out = struct();
            out.Points     = obj.LinePoints;
            out.MeshPoints = obj.LineMeshPoints;
            out.MidPoints  = obj.LineMidPoints;
            out.Segments   = obj.LineSegments;

            if ~isempty(obj.Scalars)
                if obj.ScalarsByElement
                    out.CellScalars = obj.Scalars(:);
                else
                    out.MeshScalars  = obj.LineScalars;
                    out.PointScalars = obj.LinePolylineScalars;
                    out.NodeScalars  = obj.Scalars(:);
                end
            end
        end
    end

    methods (Static)
        function out = triangulate(points, cellTypes, cells, varargin)
            %TRIANGULATE Convenience static helper for one-shot triangulation.
            tri = plotter.utils.VTKElementTriangulator(points, varargin{:});
            tri.addCells(cellTypes, cells);
            out = tri.getSurfaceResults();
        end

        function out = convertLineElements(points, cellTypes, cells, varargin)
            %CONVERTLINEELEMENTS Convenience static helper for line conversion.
            tri = plotter.utils.VTKElementTriangulator(points, varargin{:});
            tri.addLineCells(cellTypes, cells);
            out = tri.getLineResults();
        end
    end

    methods (Access = private)
        function vals = extractScalars(obj, conn, nNode, isSurface)
            %EXTRACTSCALARS Expand node-wise or element-wise scalar data.
            if isempty(obj.Scalars)
                vals = zeros(0, 1);
                return;
            end

            if obj.ScalarsByElement
                if isSurface
                    idx = obj.SurfaceScalarElementIndex;
                    obj.SurfaceScalarElementIndex = obj.SurfaceScalarElementIndex + 1;
                else
                    idx = obj.LineScalarElementIndex;
                    obj.LineScalarElementIndex = obj.LineScalarElementIndex + 1;
                end
                vals = repmat(obj.Scalars(idx), nNode, 1);
            else
                vals = obj.Scalars(conn);
            end
        end

        function conn = normalizeConnectivity(obj, cellConn)
            %NORMALIZECONNECTIVITY Convert input connectivity to plain 1-based node ids.
            conn = double(cellConn(:).');
            conn = conn(~isnan(conn));

            if isempty(conn)
                error('VTKElementTriangulator:EmptyCell', ...
                    'Empty cell connectivity is not allowed.');
            end

            % Strip leading node count if present.
            if numel(conn) >= 2 && conn(1) == numel(conn) - 1
                conn = conn(2:end);
            end

            % Convert 0-based to 1-based if needed.
            if any(conn == 0)
                conn = conn + 1;
            end

            if any(conn < 1) || any(conn > size(obj.Points, 1))
                error('VTKElementTriangulator:IndexOutOfRange', ...
                    'Connectivity contains indices outside the valid point range.');
            end
        end

        function conn = normalizeLineConnectivity(obj, cellConn)
            %NORMALIZELINECONNECTIVITY Normalize VTK-style line connectivity.
            conn = double(cellConn(:).');
            conn = conn(~isnan(conn));

            if isempty(conn)
                error('VTKElementTriangulator:EmptyLineCell', ...
                    'Empty line cell connectivity is not allowed.');
            end

            % VTK-style line cell: [n, id1, id2, ..., idn]
            if numel(conn) >= 2
                nNode = conn(1);
                if isfinite(nNode) && nNode >= 1 && floor(nNode) == nNode && ...
                        numel(conn) >= nNode + 1
                    conn = conn(2:1+nNode);
                end
            end

            % Convert 0-based to 1-based if needed
            if any(conn == 0)
                conn = conn + 1;
            end

            if any(conn < 1) || any(conn > size(obj.Points, 1))
                error('VTKElementTriangulator:LineIndexOutOfRange', ...
                    'Line connectivity contains indices outside the valid point range.');
            end
        end

        function [cellTypes, cells] = expandInput(~, cellTypes, cells)
            %EXPANDINPUT Normalize input collection formats.
            if ~iscell(cells)
                if isempty(cells)
                    cells = {};
                else
                    tmp = cell(size(cells, 1), 1);
                    for i = 1:size(cells, 1)
                        row = cells(i, :);
                        row = row(~isnan(row));
                        tmp{i} = row;
                    end
                    cells = tmp;
                end
            else
                cells = cells(:);
            end

            if isscalar(cellTypes)
                cellTypes = repmat(cellTypes, numel(cells), 1);
            else
                cellTypes = cellTypes(:);
            end

            if numel(cellTypes) ~= numel(cells)
                error('VTKElementTriangulator:InputSizeMismatch', ...
                    'The number of cell types must match the number of cells.');
            end
        end

        function addSurfaceTriangles(obj, cellType, baseIdx)
            %ADDSURFACETRIANGLES Append triangle connectivity for one cell.
            conn = obj.getSurfaceTriangleTuples(cellType);
            if isempty(conn)
                return;
            end

            tri = [baseIdx + conn(:, 1), ...
                   baseIdx + conn(:, 2), ...
                   baseIdx + conn(:, 3)];

            obj.Triangles = [obj.Triangles; tri]; %#ok<AGROW>

            % The current cell id equals the current number of stored midpoints,
            % because addCell() appends FaceMidPoints before calling this function.
            cellId = size(obj.FaceMidPoints, 1);
            obj.TriCellIds = [obj.TriCellIds; repmat(cellId, size(tri, 1), 1)]; %#ok<AGROW>
        end

        function addSurfaceBoundaryLines(obj, cellType, baseIdx)
            %ADDSURFACEBOUNDARYLINES Append NaN-separated boundary polylines.
            loops = obj.getSurfaceBoundaryLoops(cellType);
            if isempty(loops)
                return;
            end

            for i = 1:numel(loops)
                seq = loops{i};
                idx = baseIdx + seq(:);
                pts = obj.FacePoints(idx, :);
                obj.FaceLinePoints = [obj.FaceLinePoints; pts; nan(1, 3)]; %#ok<AGROW>

                if ~isempty(obj.Scalars) && ~obj.ScalarsByElement
                    vals = obj.FaceScalars(idx);
                    obj.FaceLineScalars = [obj.FaceLineScalars; vals(:); nan]; %#ok<AGROW>
                end
            end
        end

        function conn = getSurfaceTriangleTuples(~, cellType)
            %GETSURFACETRIANGLETUPLES Local triangle patterns in zero-based form.
            switch cellType
                case 5  % VTK_TRIANGLE
                    conn = [0 1 2];

                case 22 % QUADRATIC_TRIANGLE
                    conn = [0 3 5;
                            1 4 3;
                            2 5 4;
                            3 4 5];

                case 34 % BIQUADRATIC_TRIANGLE
                    conn = [0 3 6;
                            3 4 6;
                            3 1 4;
                            0 6 5;
                            4 5 6;
                            2 5 4];

                case 9  % VTK_QUAD
                    conn = [0 1 2;
                            0 2 3];

                case 23 % QUADRATIC_QUAD
                    conn = [0 4 7;
                            1 5 4;
                            2 6 5;
                            3 7 6;
                            4 6 7;
                            4 5 6];

                case 28 % BIQUADRATIC_QUAD
                    conn = [0 4 7;
                            1 5 4;
                            2 6 5;
                            3 7 6;
                            6 7 8;
                            5 6 8;
                            7 4 8;
                            4 5 8];

                case 10 % VTK_TETRA
                    conn = [0 1 2;
                            0 1 3;
                            0 2 3;
                            1 2 3];

                case 24 % QUADRATIC_TETRA
                    conn = [0 4 7;
                            1 8 4;
                            3 7 8;
                            4 8 7;
                            1 8 5;
                            3 9 8;
                            2 5 9;
                            5 8 9;
                            0 7 6;
                            2 6 9;
                            3 9 7;
                            6 7 9;
                            0 4 6;
                            1 5 4;
                            2 6 5;
                            4 5 6];

                case 12 % VTK_HEXAHEDRON
                    conn = [0 1 2;
                            0 2 3;
                            0 3 7;
                            0 7 4;
                            0 1 5;
                            0 5 4;
                            1 2 6;
                            1 6 5;
                            2 6 3;
                            3 6 7;
                            4 5 6;
                            4 6 7];

                case 25 % QUADRATIC_HEXAHEDRON
                    conn = [0 8 11;
                            1 9 8;
                            2 10 9;
                            3 11 10;
                            9 10 11;
                            8 9 11;
                            0 16 8;
                            4 12 16;
                            5 17 12;
                            1 8 17;
                            8 12 17;
                            8 16 12;
                            0 16 11;
                            4 15 16;
                            7 19 15;
                            3 11 19;
                            11 19 16;
                            15 19 16;
                            4 12 15;
                            5 13 12;
                            6 14 13;
                            7 15 14;
                            12 14 15;
                            12 13 14;
                            3 19 10;
                            7 14 19;
                            6 18 14;
                            2 10 18;
                            10 19 18;
                            14 18 19;
                            1 17 9;
                            5 13 17;
                            6 18 13;
                            2 9 18;
                            9 13 18;
                            9 17 13];

                case 29 % TRIQUADRATIC_HEXAHEDRON
                    conn = [ ...
                        0 8 24;
                        8 1 24;
                        1 9 24;
                        9 2 24;
                        2 10 24;
                        10 3 24;
                        3 11 24;
                        11 0 24;
                        4 12 25;
                        12 5 25;
                        5 13 25;
                        13 6 25;
                        6 14 25;
                        14 7 25;
                        7 15 25;
                        15 4 25;
                        0 8 26;
                        8 1 26;
                        1 16 26;
                        16 5 26;
                        5 12 26;
                        12 4 26;
                        4 17 26;
                        17 0 26;
                        1 9 26;
                        9 2 26;
                        2 18 26;
                        18 6 26;
                        6 13 26;
                        13 5 26;
                        5 16 26;
                        16 1 26;
                        2 10 26;
                        10 3 26;
                        3 19 26;
                        19 7 26;
                        7 14 26;
                        14 6 26;
                        6 18 26;
                        18 2 26;
                        3 11 26;
                        11 0 26;
                        0 17 26;
                        17 4 26;
                        4 15 26;
                        15 7 26;
                        7 19 26;
                        19 3 26];

                otherwise
                    conn = zeros(0, 3);
            end
        end

        function loops = getSurfaceBoundaryLoops(~, cellType)
            %GETSURFACEBOUNDARYLOOPS Local edge loops in zero-based form.
            switch cellType
                case 5  % VTK_TRIANGLE
                    loops = {[0 1 2 0]};

                case 22 % QUADRATIC_TRIANGLE
                    loops = {[0 3 1 4 2 5 0]};

                case 34 % BIQUADRATIC_TRIANGLE
                    loops = {[0 3 1 4 2 5 0]};

                case 9  % VTK_QUAD
                    loops = {[0 1 2 3 0]};

                case 23 % QUADRATIC_QUAD
                    loops = {[0 4 1 5 2 6 3 7 0]};

                case 28 % BIQUADRATIC_QUAD
                    loops = {[0 4 1 5 2 6 3 7 0]};

                case 10 % VTK_TETRA
                    loops = { ...
                        [0 1 2 0], ...
                        [0 1 3 0], ...
                        [0 2 3 0], ...
                        [1 2 3 1]};

                case 24 % QUADRATIC_TETRA
                    loops = { ...
                        [0 4 1 5 2 6 0], ...
                        [0 4 1 8 3 7 0], ...
                        [0 7 3 9 2 6 0], ...
                        [1 8 3 9 2 5 1]};

                case 12 % VTK_HEXAHEDRON
                    loops = { ...
                        [0 1 2 3 0], ...
                        [0 1 5 4 0], ...
                        [0 3 7 4 0], ...
                        [1 2 6 5 1], ...
                        [2 3 7 6 2], ...
                        [4 5 6 7 4]};

                case 25 % QUADRATIC_HEXAHEDRON
                    loops = { ...
                        [0 8 1 9 2 10 3 11 0], ...
                        [0 16 4 12 5 17 1 8 0], ...
                        [0 16 4 15 7 19 3 11 0], ...
                        [4 12 5 13 6 14 7 15 4], ...
                        [3 19 7 14 6 18 2 10 3], ...
                        [1 17 5 13 6 18 2 9 1]};

                case 29 % TRIQUADRATIC_HEXAHEDRON
                    loops = { ...
                        [0 8 1 9 2 10 3 11 0], ...
                        [0 16 4 12 5 17 1 8 0], ...
                        [0 16 4 15 7 19 3 11 0], ...
                        [4 12 5 13 6 14 7 15 4], ...
                        [3 19 7 14 6 18 2 10 3], ...
                        [1 17 5 13 6 18 2 9 1]};

                otherwise
                    loops = {};
            end
        end

        function seq = getLineSequence(~, cellType, nNode)
            %GETLINESEQUENCE Return plotting order for line-type cells.
            % Returned indices are zero-based local indices.
            switch cellType
                case 3   % VTK_LINE
                    seq = [0 1];

                case 4   % VTK_POLY_LINE
                    seq = 0:(nNode - 1);

                case 21  % VTK_QUADRATIC_EDGE
                    if nNode >= 3
                        seq = [0 2 1];
                    else
                        seq = 0:(nNode - 1);
                    end

                otherwise
                    % Generic fallback: connect points in stored order.
                    seq = 0:(nNode - 1);
            end
        end

        function pts = ensure3DPoints(~, pts)
            %ENSURE3DPOINTS Convert input coordinates to N x 3.
            if isempty(pts)
                pts = zeros(0, 3);
                return;
            end

            pts = double(pts);
            if size(pts, 2) == 2
                pts = [pts, zeros(size(pts, 1), 1)];
            elseif size(pts, 2) ~= 3
                error('VTKElementTriangulator:InvalidPoints', ...
                    'Points must be an N x 2 or N x 3 numeric array.');
            end
        end
    end
end