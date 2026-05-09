classdef FiberSectionMesh < handle
    % Cross-section meshing, geometric property computation, and OpenSees
    % fiber section definition via the OpenSees MATLAB interface.
    %
    % This class accepts an assembly of user-defined section *parts*, each
    % described by a ``polyshape`` geometry object and an OpenSees material
    % tag.  Parts are independent and can represent distinct materials (e.g.
    % confined core, unconfined cover, steel plate).  The class meshes each
    % part with a raster (rectangular grid) strategy, computes section
    % properties from the resulting fiber discretisation, and writes the
    % section definition directly into an OpenSees model through a shared
    % OpenSees MATLAB interface object (``ops``).
    %
    %
    %     % Access static helpers through the stub
    %     ps = opsmat.pre.fiberSectionMesh.rectShape(400, 600);
    %
    %     % Construct a real section
    %     sec = opsmat.pre.fiberSectionMesh.new(parts, rebars, secTag);
    %
    % Rebar groups may also be registered.  They contribute fiber calls
    % to the ``build`` output but are **excluded** from all geometric
    % property calculations; the caller is responsible for rebar geometry.
    %
    % This class belongs to the ``pre`` package.  Static utility methods
    % must therefore be called as ``pre.FiberSectionMesh.<method>``.
    %
    % Parameters
    % ----------
    % parts : struct array
    %     Array of solid-region descriptors.  Each element must contain the
    %     following fields:
    %
    %     * **name**      *(char)*   – Human-readable label for the part.
    %     * **matTag**    *(int)*    – OpenSees uniaxial material tag.
    %     * **geometry**  *(polyshape)* – Closed polygon defining the region
    %       boundary.  Holes and multi-region shapes (created with
    %       ``subtract``, ``intersect``, etc.) are fully supported.
    %     * **meshSize**  *(double, optional)* – Target raster cell size.
    %       Defaults to ``20`` when the field is absent or empty.
    %     * **secTag**    *(double, optional)* – Per-part OpenSees section
    %       tag.  Defaults to ``NaN``; the class-level ``secTag`` property
    %       takes precedence when set.
    %
    % rebars : struct array, optional
    %     Array of rebar-group descriptors.  Each element must contain:
    %
    %     * **name**    *(char)*         – Human-readable label.
    %     * **matTag**  *(int)*          – OpenSees uniaxial material tag.
    %     * **coords**  *(N-by-2 double)* – Bar centre coordinates; each row
    %       is ``[y, z]``.
    %     * **area**    *(double)*        – Cross-sectional area of one bar
    %       (scalar) or individual areas for each bar (N-by-1 vector).
    %
    % secTag : double, optional
    %     Global OpenSees section tag applied to the entire assembly.
    %     Overrides any ``secTag`` values stored in individual parts.
    %     Defaults to ``NaN`` (must be set before calling ``build``).
    %
    % Properties
    % ----------
    % parts : struct array
    %     Solid-region descriptors as provided by the caller.
    % rebars : struct array
    %     Rebar-group descriptors as provided by the caller.
    % secTag : double
    %     Global OpenSees section tag.
    % meshFibers : struct array
    %     Fiber cells produced by the last call to ``mesh``.  Each element
    %     has fields ``y``, ``z``, ``area``, ``hw``, ``hh``, ``matTag``,
    %     and ``partName``.  Empty until ``mesh`` has been called.
    % sectionProps : struct
    %     Geometric properties produced by the last call to
    %     ``computeProps``.  Fields: ``A``, ``Cy``, ``Cz``, ``Iy``,
    %     ``Iz``, ``Iyz``, ``ry``, ``rz``, ``I1``, ``I2``, ``theta``.
    %     Empty until ``computeProps`` has been called.
    %
    % Examples
    % --------
    % Recommended workflow via the ``opsmat.pre.fiberSection`` stub::
    %
    %     opsmat = OpenSeesMatlab();
    %     fs     = opsmat.pre.fiberSectionMesh;   % grab the stub once (optional)
    %
    %     % --- geometry via stub static helpers ---
    %     outer = fs.rectShape(400, 600);     % same as pre.FiberSectionMesh.rectShape(...)
    %     inner = fs.rectShape(340, 540);
    %
    %     parts(1).name     = 'Confined core';
    %     parts(1).matTag   = 1;
    %     parts(1).geometry = inner;
    %     parts(1).meshSize = 30;
    %
    %     parts(2).name     = 'Cover concrete';
    %     parts(2).matTag   = 2;
    %     parts(2).geometry = subtract(outer, inner);
    %     parts(2).meshSize = 30;
    %
    %     coords = fs.rectRebars(400, 600, 50, 'gap', 120);
    %     rebars(1).name   = 'HRB400';
    %     rebars(1).matTag = 3;
    %     rebars(1).coords = coords;
    %     rebars(1).area   = pi * 12^2;
    %
    %     % --- construct real section: ops injected automatically ---
    %     sec = fs.new(parts, rebars=rebars, secTag=101);
    %     sec.mesh();
    %     sec.computeProps();
    %     sec.printProps();
    %     sec.build();               % calls ops.section / ops.fiber internally
    %
    % Notes
    % -----
    % * The coordinate system follows the OpenSees convention: ``y`` is the
    %   horizontal axis and ``z`` is the vertical axis in the section plane.
    % * Always create sections via ``opsmat.pre.fiberSection.new(...)``
    %   rather than directly with ``pre.FiberSectionMesh(...)``; the former
    %   injects ``ops`` automatically so ``build`` works without extra steps.
    % * The ``opsmat.pre.fiberSectionMesh`` stub is a shell instance with no
    %   parts or rebars.  It is safe to call static helpers on it at any
    %   time; only ``new`` produces a real, usable section.
    % * Rebar fibers are written last inside the ``section Fiber`` block
    %   but contribute nothing to ``sectionProps``.
    % * Calling ``mesh`` again after changing ``parts`` invalidates the
    %   previously computed ``sectionProps``; ``computeProps`` must be
    %   re-called.
    %
    % See Also
    % --------
    %   [Polygonal Shapes](https://www.mathworks.com/help/matlab/elementary-polygons.html)

    % ====================================================================
    properties
        parts         % (struct array) Solid-region descriptors
        rebars        % (struct array) Rebar-group descriptors
        secTag        % (double) Global OpenSees section tag
        meshFibers    % (struct array) Fiber cells after meshing
        sectionProps  % (struct) Computed cross-section geometric properties
    end

    properties (Access = private)
        ops        = []    % OpenSees MATLAB interface object (set via constructor or new())
    end

    properties (Access = private)
        isMeshed   = false
        isComputed = false
    end

    % ====================================================================
    %  Constructor
    % ====================================================================
    methods
        function obj = FiberSectionMesh(parts, rebars, secTag, opsObj)
            % Construct a FiberSectionMesh object.
            %
            % Parameters
            % ----------
            % parts : struct array
            %     Solid-region descriptors.  See class documentation for
            %     required fields.
            % rebars : struct array, optional
            %     Rebar-group descriptors.  Pass ``[]`` to omit.
            % secTag : double, optional
            %     Global OpenSees section tag.  Defaults to ``NaN``.
            %     Must be set (here or via ``obj.secTag``) before
            %     calling ``build``.
            %
            % Returns
            % -------
            % obj : FiberSectionMesh
            %     Constructed object (not yet meshed).
            %
            % Raises
            % ------
            % error
            %     If ``parts`` is empty or missing required fields.
            %
            % Examples
            % --------
            % Minimal construction with one part::
            %
            %     ps  = pre.FiberSectionMesh.rectShape(300, 500);
            %     p.name = 'concrete'; p.matTag = 1; p.geometry = ps;
            %     sec = pre.FiberSectionMesh(p);
            %
            % With rebars and section tag::
            %
            %     sec = pre.FiberSectionMesh(parts, rebars, 101);

            if nargin < 1 || isempty(parts)
                error('FiberSectionMesh:missingInput', ...
                    'At least one part must be provided.');
            end
            obj.parts = parts;

            if nargin < 2 || isempty(rebars)
                obj.rebars = [];
            else
                obj.rebars = rebars;
            end

            if nargin < 3 || isempty(secTag)
                obj.secTag = NaN;
            else
                obj.secTag = secTag;
            end

            if nargin >= 4 && ~isempty(opsObj)
                obj.ops = opsObj;
            end

            obj = obj.validateParts();
        end
    end

    % ====================================================================
    %  Public methods
    % ====================================================================
    methods

        function sec = new(obj, parts, opts)
            % Create a fully configured FiberSectionMesh with ops injected.
            %
            % Call this on the ``opsmat.pre.fiberSection`` stub rather than
            % using the constructor directly.  The ``ops`` object stored in
            % the stub is automatically transferred to the new section so
            % that ``build`` works without any extra setup.
            %
            % Parameters
            % ----------
            % parts : struct array
            %     Solid-region descriptors.  See class documentation for
            %     required fields (``name``, ``matTag``, ``geometry``).
            % rebars : struct array, optional keyword
            %     Rebar-group descriptors.  Omit entirely when the section
            %     has no reinforcement.  Default ``[]``.
            % secTag : double, optional keyword
            %     OpenSees section tag (positive integer).  Can also be
            %     assigned later via ``sec.secTag = value`` before calling
            %     ``build``.  Default ``NaN``.
            %
            % Returns
            % -------
            % sec : FiberSectionMesh
            %     New section object with ``ops`` already injected.
            %     Ready for ``mesh``, ``computeProps``, and ``build``.

            arguments
                obj    (1,1) pre.FiberSectionMesh
                parts        struct
                opts.rebars  {mustBeA(opts.rebars, {'struct','double'})} = []
                opts.secTag  (1,1) double = NaN
            end

            if isempty(obj.ops)
                error('FiberSectionMesh:noOps', ...
                    ['fiberSection stub has no ops set.  ' ...
                     'Access it via opsmat.pre.fiberSection, not by direct construction.']);
            end

            sec = pre.FiberSectionMesh(parts, opts.rebars, opts.secTag, obj.ops);
        end

        function mesh(obj)
            % Discretise all section parts into triangular fiber cells.
            %
            % This method must be called before ``computeProps`` or
            % ``build``.  Calling ``mesh`` again discards
            % the previous fiber set and resets ``isComputed``.
            %
            % Parameters
            % ----------
            % None
            %
            % Returns
            % -------
            % None
            %     ``meshFibers`` is updated in place (handle semantics).
            %
            % Notes
            % -----
            %   The Partial Differential Equation Toolbox - MATLAB is required.

            allFibers = [];

            for k = 1 : numel(obj.parts)
                p  = obj.parts(k);
                ms = obj.getMeshSize(p);
                fibers = obj.meshPolyshape(p.geometry, ms, p.matTag, p.name);
                if isempty(allFibers)
                    allFibers = fibers;
                else
                    allFibers = [allFibers, fibers]; %#ok<AGROW>
                end
            end

            obj.meshFibers = allFibers;
            obj.isMeshed   = true;
            obj.isComputed = false;
            fprintf('Meshing complete: %d fiber cells generated.\n', numel(allFibers));
        end

        % -----------------------------------------------------------------

        function computeProps(obj)
            % Compute cross-section geometric properties.
            %
            % Evaluates the following properties from the current fiber mesh
            % using the standard fiber-integration formulas.  Rebar fibers
            % are **not** included.
            %
            % ``mesh`` is called automatically if it has not yet been
            % invoked.
            %
            % Notes
            % -----
            %   Computed quantities stored in ``obj.sectionProps``:
            %
            % | Field | Description |
            % |-------|-------------|
            % | A | Total cross-sectional area. |
            % | Cy | y-coordinate of the centroid. |
            % | Cz | z-coordinate of the centroid. |
            % | Iy | Second moment of area about the horizontal centroidal axis (integral of z^2 dA). |
            % | Iz | Second moment of area about the vertical centroidal axis (integral of y^2 dA). |
            % | Iyz | Product of inertia (integral of y*z dA). |
            % | ry | Radius of gyration about the horizontal centroidal axis. |
            % | rz | Radius of gyration about the vertical centroidal axis. |
            % | I1 | Larger principal second moment of area. |
            % | I2 | Smaller principal second moment of area. |
            % | theta | Angle (degrees) from the z-axis to the principal axis corresponding to I1. |

            if ~obj.isMeshed
                obj.mesh();
            end
            if isempty(obj.meshFibers)
                error('FiberSectionMesh:emptyMesh', ...
                    'Fiber mesh is empty; cannot compute properties.');
            end

            areas = [obj.meshFibers.area]';
            ys    = [obj.meshFibers.y]';
            zs    = [obj.meshFibers.z]';

            A  = sum(areas);
            Cy = sum(areas .* ys) / A;
            Cz = sum(areas .* zs) / A;

            dy  = ys - Cy;
            dz  = zs - Cz;
            Iy  = sum(areas .* dz.^2);
            Iz  = sum(areas .* dy.^2);
            Iyz = sum(areas .* dy .* dz);

            ry = sqrt(Iy / A);
            rz = sqrt(Iz / A);

            I_avg  = (Iy + Iz) / 2;
            I_diff = (Iz - Iy) / 2;
            I1 = I_avg + sqrt(I_diff^2 + Iyz^2);
            I2 = I_avg - sqrt(I_diff^2 + Iyz^2);

            if abs(Iz - Iy) < eps
                % Degenerate case: Iz == Iy (e.g. circular/square section).
                % Principal axes are undefined; return angle based on Iyz sign.
                if Iyz >= 0
                    theta = 45;
                else
                    theta = -45;
                end
            else
                theta = 0.5 * atan2d(2 * Iyz, Iz - Iy);
            end

            obj.sectionProps = struct( ...
                'A', A, 'Cy', Cy, 'Cz', Cz, ...
                'Iy', Iy, 'Iz', Iz, 'Iyz', Iyz, ...
                'ry', ry, 'rz', rz, ...
                'I1', I1, 'I2', I2, 'theta', theta);
            obj.isComputed = true;
        end

        % -----------------------------------------------------------------

        function printProps(obj)
            % Print a formatted summary of section properties.
            %

            if ~obj.isComputed
                error('FiberSectionMesh:notComputed', ...
                    'Call computeProps() before printProps().');
            end
            sp = obj.sectionProps;
            fprintf('\n========== Cross-Section Properties ==========\n');
            fprintf('  Total area         A     = %.4f\n',       sp.A);
            fprintf('  Centroid           Cy    = %.4f\n',       sp.Cy);
            fprintf('                     Cz    = %.4f\n',       sp.Cz);
            fprintf('  2nd moment (horiz) Iy    = %.4f\n',       sp.Iy);
            fprintf('  2nd moment (vert)  Iz    = %.4f\n',       sp.Iz);
            fprintf('  Product of inertia Iyz   = %.4f\n',       sp.Iyz);
            fprintf('  Radius of gyration ry    = %.4f\n',       sp.ry);
            fprintf('                     rz    = %.4f\n',       sp.rz);
            fprintf('  Principal inertia  I1    = %.4f\n',       sp.I1);
            fprintf('                     I2    = %.4f\n',       sp.I2);
            fprintf('  Principal angle    theta = %.4f  deg\n',  sp.theta);
            fprintf('===============================================\n\n');
        end

        % -----------------------------------------------------------------

    end % public methods

    % ====================================================================
    %  Public methods (continued)
    % ====================================================================
    methods

        function build(obj, opts)
            % Write the fiber section definition into the OpenSees model.
            %
            % Parameters
            % ----------
            % secType : char or string, optional
            %     OpenSees section type. Default is ``'Fiber'``.
            %     You can specify any valid OpenSees fiber section type, e.g, "FiberThermal".
            % GJ : double, optional
            %     Torsional stiffness passed through the ``'-GJ'`` option.
            %     Default is ``1.0e12``.
            %     Only used for 3D case.
            %
            % Examples
            % --------
            %     % Default Fiber section with GJ = 1e12::
            %     sec.build();
            %     % Specify torsional stiffness::
            %     sec.build(GJ=5.0e10);
            %     % Specify section type and torsional stiffness::
            %     sec.build(secType='Fiber', GJ=5.0e10);

            arguments
                obj
                opts.secType {mustBeTextScalar} = 'Fiber'
                opts.GJ (1,1) double = 1.0e12
            end

            secType = char(opts.secType);

            if isempty(obj.ops)
                error('FiberSectionMesh:noOps', ...
                    ['No ops object set. Create sections via ' ...
                    'opsmat.pre.fiberSection.new(...) to have ops injected automatically.']);
            end

            if ~obj.isMeshed
                obj.mesh();
            end

            if ~isnan(obj.secTag)
                tag = obj.secTag;
            else
                tag = obj.getFirstSecTag();
            end

            if isnan(tag)
                error('FiberSectionMesh:noSecTag', ...
                    'No secTag set. Assign obj.secTag before calling build().');
            end
            ndm = obj.ops.getNDM();
            if ndm == 3
                obj.ops.section(secType, tag, '-GJ', opts.GJ);
            else
                obj.ops.section(secType, tag);
            end

            partNames = unique({obj.meshFibers.partName}, 'stable');

            for k = 1:numel(partNames)
                idx = strcmp({obj.meshFibers.partName}, partNames{k});
                fibs = obj.meshFibers(idx);

                for i = 1:numel(fibs)
                    obj.ops.fiber( ...
                        fibs(i).y, ...
                        fibs(i).z, ...
                        fibs(i).area, ...
                        fibs(i).matTag);
                end
            end

            hasRebars = isstruct(obj.rebars) && numel(obj.rebars) > 0 ...
                        && isfield(obj.rebars, 'coords') ...
                        && isfield(obj.rebars, 'area');

            nRbTotal = 0;

            if hasRebars
                for k = 1:numel(obj.rebars)
                    rb = obj.rebars(k);
                    n = size(rb.coords, 1);

                    aVec = double(rb.area(:));

                    if isscalar(aVec)
                        aRb = repmat(aVec, n, 1);
                    else
                        aRb = aVec;

                        if numel(aRb) ~= n
                            error('FiberSectionMesh:badRebarArea', ...
                                'rebar area must be scalar or have one value per bar.');
                        end
                    end

                    for i = 1:n
                        obj.ops.fiber( ...
                            rb.coords(i, 1), ...
                            rb.coords(i, 2), ...
                            aRb(i), ...
                            rb.matTag);
                    end

                    nRbTotal = nRbTotal + n;
                end
            end

            fprintf('build: section %s %d written to ops (%d solid fibers', ...
                secType, tag, numel(obj.meshFibers));

            if hasRebars
                fprintf(', %d rebar fibers', nRbTotal);
            end

            fprintf(', GJ = %.6g).\n', opts.GJ);
        end

        % -----------------------------------------------------------------

        function plot(obj, opts)
            % Visualize the triangular section mesh, rebars, and centroid.
            %
            % Parameters
            % ----------
            % color : double array, shape (1, 3), optional
            %     Single RGB color applied to all parts. If empty, colors are
            %     assigned automatically from a colormap.
            % partColors : cell array, optional
            %     One RGB or hex color per part. This overrides ``color`` and the colormap.
            % alpha : double, optional
            %     Face transparency for filled mesh patches. Default is 0.92.
            % fill : logical, optional
            %     If false, only colored mesh lines are shown. If true, filled
            %     triangular mesh patches are shown. Default is false.
            % showEdges : logical, optional
            %     Show mesh edges when ``fill`` is true. Default is true.
            % showRebars : logical, optional
            %     Show rebar groups. Default is true.
            % showCentroid : logical, optional
            %     Show centroid marker if section properties have been computed.
            %     Default is false.
            % ax : axes, optional
            %     Target axes. If empty, a new figure is created.

            arguments
                obj
                opts.color double = []
                opts.partColors cell = {}
                opts.alpha (1,1) double = 0.92
                opts.fill (1,1) logical = false
                opts.showEdges (1,1) logical = true
                opts.showRebars (1,1) logical = true
                opts.showCentroid (1,1) logical = false
                opts.ax = []
            end

            if ~obj.isMeshed
                warning('FiberSectionMesh:notMeshed', ...
                    'Section not yet meshed. Call mesh() first.');
                return;
            end

            if isempty(opts.ax)
                figure('Name', 'FiberSectionMesh', 'Color', 'w');
                ax = gca;
            else
                ax = opts.ax;
            end

            hold(ax, 'on');
            axis(ax, 'equal');
            grid(ax, 'on');
            xlabel(ax, 'y');
            ylabel(ax, 'z');
            title(ax, 'Section triangular mesh');

            %% Resolve part colors
            partNames = {obj.parts.name};
            nParts = numel(partNames);

            if ~isempty(opts.color)
                if ~isnumeric(opts.color) || numel(opts.color) ~= 3
                    error('FiberSectionMesh:badColor', ...
                        'color must be an RGB vector with 3 elements.');
                end

                partRGB = repmat(reshape(double(opts.color), 1, 3), nParts, 1);

            elseif ~isempty(opts.partColors)
                if numel(opts.partColors) < nParts
                    error('FiberSectionMesh:colorMismatch', ...
                        'partColors must have at least one entry per part.');
                end

                partRGB = zeros(nParts, 3);

                for k = 1:nParts
                    c = opts.partColors{k};

                    if ~isnumeric(c) || numel(c) ~= 3
                        error('FiberSectionMesh:badPartColor', ...
                            'Each partColors entry must be an RGB vector with 3 elements.');
                    end

                    partRGB(k, :) = reshape(double(c), 1, 3);
                end

            else
                cmap = flipud(winter(64));
                idx = round(linspace(1, size(cmap, 1), nParts));
                partRGB = cmap(idx, :);
            end

            %% Plot mesh by part
            legendHandles = gobjects(0);
            legendNames = {};

            meshPartNames = {obj.meshFibers.partName};

            for k = 1:nParts
                pName = partNames{k};
                col = partRGB(k, :);

                idx = strcmp(meshPartNames, pName);
                nElem = nnz(idx);
                if nElem == 0
                    continue;
                end

                % Pre-allocate: clipped fibers may have >3 vertices.
                % First pass: determine max vertex count for this part.
                elems = obj.meshFibers(idx);
                maxNv = 0;
                for i = 1:nElem
                    vy = elems(i).verticesY;
                    if ~isempty(vy)
                        maxNv = max(maxNv, numel(vy));
                    end
                end
                if maxNv < 3
                    continue;
                end

                Xv = nan(maxNv, nElem);
                Yv = nan(maxNv, nElem);
                j = 0;

                for i = 1:nElem
                    vy = elems(i).verticesY;
                    vz = elems(i).verticesZ;
                    if isempty(vy) || numel(vy) < 3
                        continue;
                    end
                    j = j + 1;
                    nv = numel(vy);
                    Xv(1:nv, j) = vy(:);
                    Yv(1:nv, j) = vz(:);
                end

                if j == 0
                    continue;
                end
                if j < nElem
                    Xv = Xv(:, 1:j);
                    Yv = Yv(:, 1:j);
                end

                if opts.fill
                    if opts.showEdges
                        edgeColor = '#d8dcd6';
                        edgeAlpha = 1;
                    else
                        edgeColor = 'none';
                        edgeAlpha = 0.0;
                    end

                    h = patch(ax, Xv, Yv, col, ...
                        'FaceAlpha', opts.alpha, ...
                        'EdgeColor', edgeColor, ...
                        'EdgeAlpha', edgeAlpha, ...
                        'LineWidth', 0.35);
                else
                    h = patch(ax, Xv, Yv, col, ...
                        'FaceColor', 'none', ...
                        'EdgeColor', col, ...
                        'EdgeAlpha', 0.95, ...
                        'LineWidth', 0.45);
                end

                legendHandles(end + 1, 1) = h; %#ok<AGROW>
                legendNames{end + 1, 1} = pName; %#ok<AGROW>
            end

            %% Plot rebars by rebar group
            hasRebars = isstruct(obj.rebars) && numel(obj.rebars) > 0 ...
                        && isfield(obj.rebars, 'coords') ...
                        && isfield(obj.rebars, 'area');

            if opts.showRebars && hasRebars
                tc = linspace(0, 2*pi, 32).';  % column vector
                cosTc = cos(tc);
                sinTc = sin(tc);

                for k = 1:numel(obj.rebars)
                    rb = obj.rebars(k);

                    if isfield(rb, 'name') && ~isempty(rb.name)
                        rbName = rb.name;
                    else
                        rbName = sprintf('Rebar group %d', k);
                    end

                    coords = rb.coords;
                    nRb = size(coords, 1);

                    if nRb == 0
                        continue;
                    end

                    aVec = rb.area(:);

                    if isscalar(aVec)
                        rVec = repmat(sqrt(aVec / pi), nRb, 1);
                    else
                        rVec = sqrt(aVec / pi);

                        if numel(rVec) ~= nRb
                            error('FiberSectionMesh:badRebarArea', ...
                                'rebar area must be scalar or have one value per bar.');
                        end
                    end

                    % Vectorised circle generation.
                    % Xrb(i,j) = coords(j,1) + rVec(j)*cos(tc(i))
                    % Use implicit expansion: (nT×1) + (nT×nRb)
                    Xrb = coords(:,1).' + rVec.' .* cosTc;
                    Yrb = coords(:,2).' + rVec.' .* sinTc;

                    hRb = patch(ax, Xrb, Yrb, [0 0 0], ...
                        'FaceColor', 'k', ...
                        'EdgeColor', 'k', ...
                        'LineWidth', 0.8, ...
                        'FaceAlpha', 1.0);

                    legendHandles(end + 1, 1) = hRb; %#ok<AGROW>
                    legendNames{end + 1, 1} = rbName; %#ok<AGROW>
                end
            end

            %% Plot centroid
            if opts.showCentroid && obj.isComputed
                sp = obj.sectionProps;

                plot(ax, sp.Cy, sp.Cz, 'r+', ...
                    'MarkerSize', 14, ...
                    'LineWidth', 2, ...
                    'HandleVisibility', 'off');

                text(ax, sp.Cy, sp.Cz, ...
                    sprintf('  centroid (%.1f, %.1f)', sp.Cy, sp.Cz), ...
                    'Color', 'r', ...
                    'FontSize', 9, ...
                    'HandleVisibility', 'off');
            end

            %% Legend
            if ~isempty(legendHandles)
                legend(ax, legendHandles, legendNames, ...
                    'Location', 'best', ...
                    'Box', 'off', ...
                    'Interpreter', 'none');
            end

            hold(ax, 'off');
        end
    end % public methods

    % ====================================================================
    %  Private methods
    % ====================================================================
    methods (Access = private)

        function obj = validateParts(obj)
            % validateParts  Check that every part has the required fields.
            required = {'name', 'matTag', 'geometry'};
            for k = 1 : numel(obj.parts)
                for r = 1 : numel(required)
                    if ~isfield(obj.parts(k), required{r})
                        error('FiberSectionMesh:missingField', ...
                            'parts(%d) is missing required field "%s".', ...
                            k, required{r});
                    end
                end
                if ~isa(obj.parts(k).geometry, 'polyshape')
                    error('FiberSectionMesh:badGeometry', ...
                        'parts(%d).geometry must be a polyshape object.', k);
                end
                if ~isfield(obj.parts(k), 'secTag');  obj.parts(k).secTag  = NaN; end
                if ~isfield(obj.parts(k), 'meshSize'); obj.parts(k).meshSize = []; end
            end
        end

        % -----------------------------------------------------------------

        function ms = getMeshSize(~, part)
            % getMeshSize  Resolve the mesh cell size for a part.
            if isfield(part, 'meshSize') && ~isempty(part.meshSize) && part.meshSize > 0
                ms = part.meshSize;
            else
                ms = 20;
            end
        end

        % -----------------------------------------------------------------

        function tag = getFirstSecTag(obj)
            % getFirstSecTag  Return the first non-NaN secTag found in parts.
            tag = NaN;
            for k = 1 : numel(obj.parts)
                if isfield(obj.parts(k), 'secTag') && ~isnan(obj.parts(k).secTag)
                    tag = obj.parts(k).secTag;
                    return;
                end
            end
        end

        % -----------------------------------------------------------------

        function fibers = meshPolyshape(~, ps, meshSize, matTag, partName)
            % meshPolyshape  Mesh a polyshape using PDE Toolbox triangular mesh.

            hasPDE = license('test', 'PDE_Toolbox') && ...
                     ~isempty(ver('pde'));

            if ~hasPDE
                error('FiberSectionMesh:noPDEToolbox', ...
                    'Partial Differential Equation Toolbox is required but not available/licensed.');
            end

            fibers = struct('y',{},'z',{},'area',{},'hw',{},'hh',{}, ...
                            'matTag',{},'partName',{}, ...
                            'verticesY',{},'verticesZ',{},'shapeType',{});

            % Convert polyshape to triangulation-compatible geometry.
            tr = triangulation(ps);

            if isempty(tr.Points) || isempty(tr.ConnectivityList)
                return;
            end

            % Create PDE model from triangulated polyshape boundary.
            model = createpde();

            % polyshape -> boundary facets -> geometry.
            [bx, bz] = boundary(ps);
            bx = bx(:);
            bz = bz(:);

            nanId = isnan(bx) | isnan(bz);
            splitId = [0; find(nanId); numel(bx) + 1];

            gd = [];
            nsNames = strings(0);
            sfTerms = strings(0);

            for k = 1:numel(splitId)-1
                id1 = splitId(k) + 1;
                id2 = splitId(k+1) - 1;

                y = bx(id1:id2);
                z = bz(id1:id2);

                if numel(y) < 3
                    continue;
                end

                if y(1) == y(end) && z(1) == z(end)
                    y(end) = [];
                    z(end) = [];
                end

                n = numel(y);

                % decsg polygon column:
                % [2; n; x1...xn; y1...yn]
                col = [2; n; y(:); z(:)];

                if isempty(gd)
                    gd = col;
                else
                    maxLen = max(size(gd,1), numel(col));
                    gd(end+1:maxLen, :) = 0;
                    col(end+1:maxLen, 1) = 0;
                    gd(:, end+1) = col;
                end

                name = "P" + k;
                nsNames(end+1) = name; %#ok<AGROW>
                sfTerms(end+1) = name; %#ok<AGROW>
            end

            if isempty(gd)
                return;
            end

            ns = char(cellstr(nsNames(:)));
            ns = ns';

            % For polyshape with holes, decsg with all polygons summed may not always
            % infer holes correctly. Therefore, use the polyshape triangulation
            % fallback if decsg fails.
            sf = strjoin(sfTerms, '+');

            try
                g = decsg(gd, char(sf), ns);
                geometryFromEdges(model, g);

                msh = generateMesh(model, ...
                    'Hmax', meshSize, ...
                    'GeometricOrder', 'linear');

                pts = msh.Nodes';
                tri = msh.Elements';

            catch
                % Robust fallback: use polyshape triangulation and subdivide quality
                % indirectly through the polyshape triangulation. This avoids crashing
                % but may be coarser.
                warning('FiberSectionMesh:pdeGeometryFailed', ...
                    'PDE geometry creation failed. Falling back to polyshape triangulation.');

                pts = tr.Points;
                tri = tr.ConnectivityList;
            end

            areaTol = meshSize^2 * 1.0e-10;

            nTri = size(tri, 1);
            for i = 1:nTri
                id = tri(i, :);

                vy = pts(id, 1);
                vz = pts(id, 2);

                % Fast signed-area test instead of polyshape creation.
                a = 0.5 * abs((vy(2)-vy(1))*(vz(3)-vz(1)) - (vy(3)-vy(1))*(vz(2)-vz(1)));

                if a <= areaTol || ~isfinite(a)
                    continue;
                end

                % For sections with holes, the PDE mesh may produce triangles
                % outside the original polyshape.  Use the triangle centroid
                % as a cheap point-in-polyshape test.
                cy = sum(vy) / 3;
                cz = sum(vz) / 3;

                if ~isinterior(ps, cy, cz)
                    continue;
                end

                f.y = cy;
                f.z = cz;

                % For triangles that straddle a hole boundary, the PDE mesh
                % triangle may extend into the hole.  Clip it with the original
                % polyshape to get the correct area and vertices.
                triPs = polyshape(vy, vz, 'Simplify', false);
                inter = intersect(ps, triPs);
                a = area(inter);
                if a <= areaTol || ~isfinite(a)
                    continue;
                end
                f.area = a;

                [py, pz] = boundary(inter);
                valid = isfinite(py) & isfinite(pz);
                py = py(valid);
                pz = pz(valid);
                if numel(py) < 3
                    continue;
                end

                % Kept for compatibility with old rectangular mesh fields.
                f.hw = NaN;
                f.hh = NaN;

                f.matTag = matTag;
                f.partName = partName;

                % Mesh visualization fields (clipped polygon vertices).
                f.verticesY = py(:).';
                f.verticesZ = pz(:).';
                f.shapeType = 'triangle';

                fibers(end+1) = f; %#ok<AGROW>
            end
        end

    end % private methods

    % ====================================================================
    %  Static utility methods  (call as  pre.FiberSectionMesh.<name>)
    % ====================================================================
    %
    % Geometry builders
    % -----------------
    %   rectShape          Solid rectangle.
    %   hollowRectShape    Hollow rectangle (box section).
    %   circleShape        Solid circle.
    %   annulusShape       Hollow circle (annulus / pipe).
    %   polygonShape       Arbitrary closed polygon from vertex list.
    %   IShape             Doubly-symmetric I / H section.
    %   TShape             T-section (flange + web).
    %   LShape             L-section (angle).
    %
    % Rebar layout builders
    % ---------------------
    %   lineRebars         Bars along a straight line; control by n or gap.
    %   rectRebars         Perimeter cage of a rectangle; control by n or gap.
    %   circRebars         Bars on a circle; control by n or gap; open/closed.
    %   arcRebars          Bars along a circular arc; control by n or gap.
    %   polygonRebars      Bars along an arbitrary polygon path; n or gap;
    %                      open/closed.
    %
    % Miscellaneous
    % -------------
    %   demo               Self-contained usage demonstration.
    % ====================================================================
    methods (Static)

        % ==================================================================
        %  GEOMETRY BUILDERS
        % ==================================================================

        function ps = rectShape(b, h, cy, cz)
            % rectShape  Create a solid rectangular polyshape.
            %
            % Parameters
            % ----------
            % b : double
            %     Width in the y-direction.
            % h : double
            %     Height in the z-direction.
            % cy : double, optional
            %     y-coordinate of the centroid.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the centroid.  Default ``0``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     Axis-aligned solid rectangle.
            %
            % Examples
            % --------
            %     % Centred at origin::
            %     ps = pre.FiberSectionMesh.rectShape(400, 600);
            %
            %     % Offset centroid::
            %     ps = pre.FiberSectionMesh.rectShape(200, 300, 100, 0);

            if nargin < 3; cy = 0; cz = 0; end
            ps = polyshape( ...
                [cy-b/2, cy+b/2, cy+b/2, cy-b/2], ...
                [cz-h/2, cz-h/2, cz+h/2, cz+h/2]);
        end

        % -----------------------------------------------------------------

        function ps = hollowRectShape(bo, ho, bi, hi, cy, cz)
            % Create a hollow rectangular (box) polyshape.
            %
            % The inner rectangle is concentrically subtracted from the
            % outer rectangle.  Both rectangles share the same centroid.
            % To model eccentric voids use ``subtract`` directly on two
            % ``rectShape`` results.
            %
            % Parameters
            % ----------
            % bo : double
            %     Outer width (y-direction).
            % ho : double
            %     Outer height (z-direction).
            % bi : double
            %     Inner (void) width (y-direction).  Must be ``< bo``.
            % hi : double
            %     Inner (void) height (z-direction).  Must be ``< ho``.
            % cy : double, optional
            %     y-coordinate of the shared centroid.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the shared centroid.  Default ``0``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     Hollow rectangular polygon (outer minus inner).
            %
            % Examples
            % --------
            %     % Steel box section 200 × 300, wall thickness 10::
            %     ps = pre.FiberSectionMesh.hollowRectShape(200, 300, 180, 280);
            %
            %     % Concrete hollow pier 1200 × 1600, wall 200::
            %     ps = pre.FiberSectionMesh.hollowRectShape(1200, 1600, 800, 1200);

            if nargin < 5; cy = 0; cz = 0; end
            if bi >= bo || hi >= ho
                error('FiberSectionMesh:invalidDimension', ...
                    'Inner dimensions (bi, hi) must be strictly less than outer (bo, ho).');
            end
            ps = subtract(pre.FiberSectionMesh.rectShape(bo, ho, cy, cz), ...
                          pre.FiberSectionMesh.rectShape(bi, hi, cy, cz));
        end

        % -----------------------------------------------------------------

        function ps = circleShape(r, cy, cz, n)
            % circleShape  Create a solid circular polyshape.
            %
            % The circle is approximated by a regular n-gon.  The default
            % of 64 vertices is sufficient for typical section meshes; use
            % 128 or higher for very fine meshes or large radii.
            %
            % Parameters
            % ----------
            % r : double
            %     Radius of the circle.
            % cy : double, optional
            %     y-coordinate of the centre.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the centre.  Default ``0``.
            % n : int, optional
            %     Number of polygon vertices.  Default ``64``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     Regular n-gon approximating the circle.
            %
            % Examples
            % --------
            %     ps = pre.FiberSectionMesh.circleShape(250);
            %     ps = pre.FiberSectionMesh.circleShape(250, 0, 0, 128);

            if nargin < 2; cy = 0; cz = 0; end
            if nargin < 4; n  = 64; end
            t  = linspace(0, 2*pi, n+1);  t(end) = [];
            ps = polyshape(cy + r*cos(t), cz + r*sin(t));
        end

        % -----------------------------------------------------------------

        function ps = annulusShape(Ro, Ri, cy, cz, n)
            % annulusShape  Create an annular (hollow circular) polyshape.
            %
            % Useful for circular steel tubes, pipe piles, or circular
            % concrete sections with a central void.
            %
            % Parameters
            % ----------
            % Ro : double
            %     Outer radius.
            % Ri : double
            %     Inner radius.  Must satisfy ``0 < Ri < Ro``.
            % cy : double, optional
            %     y-coordinate of the centre.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the centre.  Default ``0``.
            % n : int, optional
            %     Number of polygon vertices on each boundary circle.
            %     Default ``64``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     Annular polygon (outer circle minus inner circle).
            %
            % Examples
            % --------
            %     % Steel circular hollow section, outer diameter 600, thickness 20::
            %     ps = pre.FiberSectionMesh.annulusShape(300, 280);
            %
            %     % Concrete annular pier, outer r = 1500, inner r = 1200::
            %     ps = pre.FiberSectionMesh.annulusShape(1500, 1200);

            if nargin < 3; cy = 0; cz = 0; end
            if nargin < 5; n  = 64; end
            if Ri <= 0 || Ri >= Ro
                error('FiberSectionMesh:invalidRadius', ...
                    'Inner radius Ri must satisfy 0 < Ri < Ro.');
            end
            t     = linspace(0, 2*pi, n+1);  t(end) = [];
            outer = polyshape(cy + Ro*cos(t), cz + Ro*sin(t));
            inner = polyshape(cy + Ri*cos(t), cz + Ri*sin(t));
            ps    = subtract(outer, inner);
        end

        % -----------------------------------------------------------------

        function ps = polygonShape(yVerts, zVerts)
            % polygonShape  Create an arbitrary closed polygon polyshape.
            %
            % Convenience wrapper around the ``polyshape`` constructor for
            % user-supplied vertex lists.  The polygon is automatically
            % closed; do not repeat the first vertex at the end.  Holes can
            % be created afterwards with ``subtract``.
            %
            % Parameters
            % ----------
            % yVerts : (N,) double
            %     y-coordinates of the polygon vertices in order (CW or CCW).
            % zVerts : (N,) double
            %     z-coordinates of the polygon vertices in the same order.
            %     Must have the same length as ``yVerts``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     Closed polygon built from the supplied vertices.
            %
            % Examples
            % --------
            %     % Trapezoidal section::
            %     y = [-300, 300, 200, -200];
            %     z = [   0,   0, 600,  600];
            %     ps = pre.FiberSectionMesh.polygonShape(y, z);
            %
            %     % Diamond::
            %     y = [0, 200, 0, -200];
            %     z = [-300, 0, 300, 0];
            %     ps = pre.FiberSectionMesh.polygonShape(y, z);

            yVerts = yVerts(:);
            zVerts = zVerts(:);
            if numel(yVerts) ~= numel(zVerts)
                error('FiberSectionMesh:sizeMismatch', ...
                    'yVerts and zVerts must have the same number of elements.');
            end
            if numel(yVerts) < 3
                error('FiberSectionMesh:tooFewVertices', ...
                    'At least 3 vertices are required to define a polygon.');
            end
            ps = polyshape(yVerts, zVerts);
        end

        % -----------------------------------------------------------------

        function ps = IShape(bf, tf, hw, tw, cy, cz)
            % IShape  Create a doubly-symmetric I- or H-section polyshape.
            %
            % The section is assembled from three rectangles (top flange,
            % web, bottom flange) combined with ``union``.  The centroid is
            % placed at the intersection of the two axes of symmetry.
            %
            %   ┌──────────────┐  ─ z = +H/2  (top of top flange)
            %
            %   │  top flange  │
            %
            %   └───┬──────┬───┘  ─ z = +hw/2
            %
            %       │  web │
            %
            %   ┌───┴──────┴───┐  ─ z = -hw/2
            %
            %   │ bottom flange│
            %
            %   └──────────────┘  ─ z = -H/2
            %
            % Parameters
            % ----------
            % bf : double
            %     Flange width (y-direction).
            % tf : double
            %     Flange thickness (z-direction, both flanges identical).
            % hw : double
            %     Clear web height (z-direction, between flanges).
            % tw : double
            %     Web thickness (y-direction).
            % cy : double, optional
            %     y-coordinate of the section centroid.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the section centroid.  Default ``0``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     I-section polygon.  Total height = ``hw + 2*tf``.
            %
            % Examples
            % --------
            %     % HN400 (approximate)::
            %     ps = pre.FiberSectionMesh.IShape(200, 13, 374, 8);
            %
            %     % Steel H-pile 300 x 300::
            %     ps = pre.FiberSectionMesh.IShape(300, 15, 270, 10);

            if nargin < 5; cy = 0; cz = 0; end
            web  = pre.FiberSectionMesh.rectShape(tw,  hw, cy,  cz);
            topF = pre.FiberSectionMesh.rectShape(bf,  tf, cy,  cz + hw/2 + tf/2);
            botF = pre.FiberSectionMesh.rectShape(bf,  tf, cy,  cz - hw/2 - tf/2);
            ps   = union([web; topF; botF]);
        end

        % -----------------------------------------------------------------

        function ps = TShape(bf, tf, hw, tw, cy, cz)
            % TShape  Create a T-section (flange + web) polyshape.
            %
            % The web hangs below the flange.  The reference centroid
            % ``(cy, cz)`` is placed at the centre of the flange's top face
            % (i.e. z = 0 is the top of the section).  The overall depth is
            % ``tf + hw``.
            %
            %   ┌──────────────┐  z = 0         (top of flange / reference)
            %
            %   │   flange     │
            %
            %   └───┬──────┬───┘  z = -tf
            %
            %       │  web │
            %
            %       │      │
            %
            %       └──────┘      z = -(tf + hw)
            %
            % Parameters
            % ----------
            % bf : double
            %     Flange width (y-direction).
            % tf : double
            %     Flange thickness (z-direction).
            % hw : double
            %     Web height below the flange (z-direction).
            % tw : double
            %     Web thickness (y-direction).
            % cy : double, optional
            %     y-coordinate of the section centreline.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the top of the flange.  Default ``0``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     T-section polygon.  Total depth = ``tf + hw``.
            %
            % Examples
            % --------
            % T-beam 600 wide flange, 120 thick, 600 web height, 100 thick::
            %
            %     ps = pre.FiberSectionMesh.TShape(600, 120, 600, 100);

            if nargin < 5; cy = 0; cz = 0; end
            flange = pre.FiberSectionMesh.rectShape(bf, tf, cy, cz - tf/2);
            web    = pre.FiberSectionMesh.rectShape(tw, hw, cy, cz - tf - hw/2);
            ps     = union([flange; web]);
        end

        % -----------------------------------------------------------------

        function ps = LShape(b, h, t, cy, cz)
            % LShape  Create an L-section (equal- or unequal-leg angle) polyshape.
            %
            % The horizontal leg extends in the +y direction and the
            % vertical leg extends in the +z direction from the heel at
            % ``(cy, cz)``.
            %
            %   ┌──┐             z = cz + h     (top of vertical leg)
            %
            %   │  │
            %
            %   │  ├────────┐    z = cz + t
            %
            %   └──┴────────┘    z = cz          (bottom / heel)
            %
            %   cy             cy + b
            %
            % Parameters
            % ----------
            % b : double
            %     Total width of the horizontal leg (y-direction).
            % h : double
            %     Total height of the vertical leg (z-direction).
            % t : double
            %     Leg thickness (applied to both legs; for unequal thickness
            %     use ``polygonShape`` directly).
            % cy : double, optional
            %     y-coordinate of the heel corner.  Default ``0``.
            % cz : double, optional
            %     z-coordinate of the heel corner.  Default ``0``.
            %
            % Returns
            % -------
            % ps : polyshape
            %     L-section polygon.
            %
            % Examples
            % --------
            %     % Equal-leg angle L150 × 150 × 12::
            %     ps = pre.FiberSectionMesh.LShape(150, 150, 12);
            %
            %     % Unequal-leg angle, heel at origin::
            %     ps = pre.FiberSectionMesh.LShape(200, 100, 10, 0, 0);

            if nargin < 4; cy = 0; cz = 0; end
            if t >= b || t >= h
                error('FiberSectionMesh:invalidDimension', ...
                    'Thickness t must be strictly less than both b and h.');
            end
            % Define vertices of the L in CCW order
            yv = [cy,   cy+b, cy+b, cy+t, cy+t, cy  ];
            zv = [cz,   cz,   cz+t, cz+t, cz+h, cz+h];
            ps = polyshape(yv, zv);
        end

        % ==================================================================
        %  REBAR LAYOUT BUILDERS
        % ==================================================================

        function coords = lineRebars(yPath, zPath, opts)
            % Generate rebar coordinates along a polyline or closed polygonal path.
            %
            % Path vertices are always occupied by rebars. Each path segment is
            % then independently interpolated using either a target spacing ``gap``
            % or an approximate total bar count ``n``.
            %
            % Parameters
            % ----------
            % yPath : double array, shape (n, 1)
            %     y-coordinates of the path vertices.
            % zPath : double array, shape (n, 1)
            %     z-coordinates of the path vertices.
            % n : double, optional
            %     Approximate total number of bars along the whole path.
            % gap : double, optional
            %     Target spacing along each segment.
            % closed : logical, optional
            %     If true, connect the last point back to the first point.
            % removeDuplicateEnd : logical, optional
            %     Remove repeated final point if identical to the first point.
            % tol : double, optional
            %     Tolerance for duplicate and zero-length points.
            %
            % Returns
            % -------
            % coords : double array, shape (m, 2)
            %     Rebar coordinates. Each row is [y, z].

            arguments
                yPath (:,1) double
                zPath (:,1) double
                opts.n double = []
                opts.gap double = []
                opts.closed (1,1) logical = false
                opts.removeDuplicateEnd (1,1) logical = true
                opts.tol (1,1) double = 1.0e-10
            end

            if numel(yPath) ~= numel(zPath)
                error('FiberSectionMesh:sizeMismatch', ...
                    'yPath and zPath must have the same number of elements.');
            end

            if numel(yPath) < 2
                error('FiberSectionMesh:tooFewPoints', ...
                    'At least two path points are required.');
            end

            hasN = ~isempty(opts.n);
            hasGap = ~isempty(opts.gap);

            if hasN && hasGap
                error('FiberSectionMesh:ambiguousInput', ...
                    'Specify either n or gap, not both.');
            end

            if ~hasN && ~hasGap
                error('FiberSectionMesh:missingSpacing', ...
                    'Specify either n or gap.');
            end

            if hasN
                if numel(opts.n) ~= 1 || opts.n < 2 || abs(opts.n - round(opts.n)) > opts.tol
                    error('FiberSectionMesh:invalidN', ...
                        'n must be a scalar integer greater than or equal to 2.');
                end
                opts.n = round(opts.n);
            end

            if hasGap
                if numel(opts.gap) ~= 1 || opts.gap <= 0
                    error('FiberSectionMesh:invalidGap', ...
                        'gap must be a positive scalar.');
                end
            end

            yPath = yPath(:);
            zPath = zPath(:);

            % Remove repeated end point. Closure is handled explicitly below.
            if opts.removeDuplicateEnd && numel(yPath) > 2
                if abs(yPath(1) - yPath(end)) <= opts.tol && ...
                   abs(zPath(1) - zPath(end)) <= opts.tol
                    yPath(end) = [];
                    zPath(end) = [];
                end
            end

            % Build working path.
            if opts.closed
                yWork = [yPath; yPath(1)];
                zWork = [zPath; zPath(1)];
            else
                yWork = yPath;
                zWork = zPath;
            end

            % Remove zero-length segments.
            ds = hypot(diff(yWork), diff(zWork));
            keepPoint = [true; ds > opts.tol];

            yWork = yWork(keepPoint);
            zWork = zWork(keepPoint);

            ds = hypot(diff(yWork), diff(zWork));
            totalLength = sum(ds);

            if totalLength <= opts.tol
                coords = zeros(0, 2);
                return;
            end

            coords = [];

            for i = 1:numel(yWork)-1
                y1 = yWork(i);
                z1 = zWork(i);
                y2 = yWork(i+1);
                z2 = zWork(i+1);

                Lseg = hypot(y2 - y1, z2 - z1);

                if Lseg <= opts.tol
                    continue;
                end

                if hasGap
                    nSeg = max(2, floor(Lseg / opts.gap) + 1);
                else
                    nSeg = max(2, round(opts.n * Lseg / totalLength) + 1);
                end

                t = linspace(0, 1, nSeg).';

                ySeg = y1 + t * (y2 - y1);
                zSeg = z1 + t * (z2 - z1);

                coords = [coords; ySeg, zSeg]; %#ok<AGROW>
            end

            coords = uniquetol(coords, opts.tol, 'ByRows', true);
        end

        % -----------------------------------------------------------------

        function coords = rectRebars(b, h, cover, varargin)
            % Bar centres around the perimeter of a rectangle.
            %
            % Distributes bars around all four faces of a rectangle.  The
            % spacing is controlled by ``nY`` + ``nZ`` (bars per face) or
            % by a uniform centre-to-centre ``gap``.  Corner bars are always
            % present and are counted only once.
            %
            % Parameters
            % ----------
            % b : double
            %     Section width (y-direction).
            % h : double
            %     Section height (z-direction).
            % cover : double
            %     Distance from the face to the bar centre.
            % nY : int, keyword
            %     Number of bars along the top / bottom faces (corners
            %     included).  Must be supplied together with ``nZ``.
            % nZ : int, keyword
            %     Number of bars along the left / right faces (corners
            %     included).  Must be supplied together with ``nY``.
            % gap : double, keyword
            %     Uniform target spacing; the same gap is applied to all
            %     four faces independently.  Cannot be combined with
            %     ``nY`` / ``nZ``.
            % cy : double, optional keyword
            %     y-coordinate of the section centroid.  Default ``0``.
            % cz : double, optional keyword
            %     z-coordinate of the section centroid.  Default ``0``.
            %
            % Returns
            % -------
            % coords : (N, 2) double
            %     Unique bar centre coordinates sorted by angle; each row
            %     is ``[y, z]``.
            %
            % Examples
            % --------
            %     % Specify bars per face::
            %     c = pre.FiberSectionMesh.rectRebars(400, 600, 50, 'nY',4, 'nZ',5);
            %
            %     % Uniform gap::
            %     c = pre.FiberSectionMesh.rectRebars(400, 600, 50, 'gap',120);
            %
            %     % Offset section centroid::
            %     c = pre.FiberSectionMesh.rectRebars(400,600,50,'gap',120,'cy',100,'cz',0);

            ip = inputParser;
            addParameter(ip, 'nY',  [], @(x) isscalar(x) && x >= 2);
            addParameter(ip, 'nZ',  [], @(x) isscalar(x) && x >= 2);
            addParameter(ip, 'gap', [], @(x) isscalar(x) && x > 0);
            addParameter(ip, 'cy',  0,  @isnumeric);
            addParameter(ip, 'cz',  0,  @isnumeric);
            parse(ip, varargin{:});
            r = ip.Results;

            useGap = ~isempty(r.gap);
            useN   = ~isempty(r.nY) && ~isempty(r.nZ);
            if useGap && useN
                error('FiberSectionMesh:ambiguousInput', ...
                    'Specify either gap or (nY, nZ), not both.');
            end
            if ~useGap && ~useN
                error('FiberSectionMesh:missingSpacing', ...
                    'Specify either gap or both nY and nZ.');
            end

            y1 = r.cy - b/2 + cover;  y2 = r.cy + b/2 - cover;
            z1 = r.cz - h/2 + cover;  z2 = r.cz + h/2 - cover;
            if useN
                nY = r.nY;  nZ = r.nZ;
            else
                nY = max(2, floor((y2-y1)/r.gap) + 1);
                nZ = max(2, floor((z2-z1)/r.gap) + 1);
            end

            bot  = pre.FiberSectionMesh.lineRebars(y1, z1, y2, z1, 'n', nY);
            top  = pre.FiberSectionMesh.lineRebars(y1, z2, y2, z2, 'n', nY);
            left = pre.FiberSectionMesh.lineRebars(y1, z1, y1, z2, 'n', nZ);
            rgt  = pre.FiberSectionMesh.lineRebars(y2, z1, y2, z2, 'n', nZ);

            coords = unique([bot; top; left; rgt], 'rows');
        end

        % -----------------------------------------------------------------

        function coords = circRebars(R, varargin)
            % circRebars  Bar centres arranged on a full circle.
            %
            % Distributes bars uniformly on a circle of radius ``R``.
            % The spacing is controlled by ``n`` (number of bars) or by the
            % target arc ``gap``.  The ``closed`` option selects whether the
            % layout is treated as a closed loop (default) — spacing is
            % ``2*pi*R / n`` — or open, which has no practical difference
            % for a full circle but is provided for API consistency.
            %
            % Parameters
            % ----------
            % R : double
            %     Radius of the bar circle (to bar centres).
            % n : int, keyword
            %     Number of bars equally spaced around the full circle.
            %     Must be ``>= 2``.
            % gap : double, keyword
            %     Target arc-length spacing between adjacent bar centres.
            %     ``n = round(2*pi*R / gap)``.
            % cy : double, optional keyword
            %     y-coordinate of the circle centre.  Default ``0``.
            % cz : double, optional keyword
            %     z-coordinate of the circle centre.  Default ``0``.
            % startAngle : double, optional keyword
            %     Angle (degrees) of the first bar, measured CCW from the
            %     +y axis.  Default ``90`` (bar at the top).
            %
            % Returns
            % -------
            % coords : (N, 2) double
            %     Bar centre coordinates; each row is ``[y, z]``.
            %
            % Examples
            % --------
            %     % bars on a 250 mm radius circle::
            %     c = pre.FiberSectionMesh.circRebars(250, 'n', 8);
            %
            %     % Bars at 150 mm arc spacing::
            %     c = pre.FiberSectionMesh.circRebars(250, 'gap', 150);
            %
            %     % Starting from the bottom (270 deg)::
            %     c = pre.FiberSectionMesh.circRebars(250, 'n', 12, 'startAngle', 270);

            ip = inputParser;
            addParameter(ip, 'n',          [], @(x) isscalar(x) && x >= 2);
            addParameter(ip, 'gap',        [], @(x) isscalar(x) && x > 0);
            addParameter(ip, 'cy',          0, @isnumeric);
            addParameter(ip, 'cz',          0, @isnumeric);
            addParameter(ip, 'startAngle', 90, @isnumeric);
            parse(ip, varargin{:});
            r = ip.Results;

            p = pre.FiberSectionMesh.parseNorGap('n', r.n, 'gap', r.gap);
            if p.useN
                if p.n < 2
                    error('FiberSectionMesh:invalidN','n must be >= 2.');
                end
                nBars = p.n;
            else
                if p.gap <= 0
                    error('FiberSectionMesh:invalidGap','gap must be > 0.');
                end
                nBars = max(2, round(2*pi*R / p.gap));
            end
            theta  = linspace(0, 2*pi, nBars+1);
            theta(end) = [];
            theta  = theta + deg2rad(r.startAngle);
            coords = [r.cy + R*cos(theta(:)),  r.cz + R*sin(theta(:))];
        end

        % -----------------------------------------------------------------

        function coords = arcRebars(R, angStart, angEnd, varargin)
            % arcRebars  Bar centres along a circular arc.
            %
            % Distributes bars from angle ``angStart`` to ``angEnd`` along
            % an arc of radius ``R``.  By default the two end angles are
            % included (``closed = true``).  Set ``closed = false`` to
            % place bars strictly between the end angles.
            %
            % Parameters
            % ----------
            % R : double
            %     Arc radius (to bar centres).
            % angStart : double
            %     Start angle in degrees, measured CCW from the +y axis.
            % angEnd : double
            %     End angle in degrees, measured CCW from the +y axis.
            %     May be less than ``angStart`` to sweep CW.
            % n : int, keyword
            %     Number of bars including end bars (when ``closed = true``)
            %     or excluding them (when ``closed = false``).  Must be
            %     ``>= 2`` when ``closed = true``, ``>= 1`` otherwise.
            % gap : double, keyword
            %     Target arc-length spacing.  The actual bar count is
            %     determined from the arc length and the gap.
            % closed : logical, optional keyword
            %     ``true`` (default) – bars placed at ``angStart`` and
            %     ``angEnd`` as well as in between.
            %     ``false`` – bars placed strictly between the two angles,
            %     evenly spaced.
            % cy : double, optional keyword
            %     y-coordinate of the arc centre.  Default ``0``.
            % cz : double, optional keyword
            %     z-coordinate of the arc centre.  Default ``0``.
            %
            % Returns
            % -------
            % coords : (N, 2) double
            %     Bar centre coordinates; each row is ``[y, z]``.
            %
            % Examples
            % --------
            %     % 6 bars over the top half (0° to 180°)::
            %     c = pre.FiberSectionMesh.arcRebars(250, 0, 180, 'n', 6);
            %
            %     % Bars at 100 mm spacing over bottom 180°, open ends::
            %     c = pre.FiberSectionMesh.arcRebars(250, 180, 360, 'gap', 100, 'closed', false);

            ip = inputParser;
            addParameter(ip, 'n',      [], @(x) isscalar(x) && x >= 1);
            addParameter(ip, 'gap',    [], @(x) isscalar(x) && x > 0);
            addParameter(ip, 'closed', true, @islogical);
            addParameter(ip, 'cy',     0,    @isnumeric);
            addParameter(ip, 'cz',     0,    @isnumeric);
            parse(ip, varargin{:});
            r = ip.Results;

            a1    = deg2rad(angStart);
            a2    = deg2rad(angEnd);
            dAng  = a2 - a1;
            arcL  = abs(dAng) * R;

            p = pre.FiberSectionMesh.parseNorGap('n', r.n, 'gap', r.gap);
            if p.useN
                nBars = p.n;
            else
                nBars = max(2, round(arcL / p.gap) + double(r.closed));
            end

            if r.closed
                theta = linspace(a1, a2, nBars);
            else
                theta = linspace(a1, a2, nBars+2);
                theta = theta(2:end-1);
            end
            coords = [r.cy + R*cos(theta(:)),  r.cz + R*sin(theta(:))];
        end

        % -----------------------------------------------------------------

        function coords = polygonRebars(yPath, zPath, varargin)
            % polygonRebars  Bar centres along an arbitrary polygon path.
            %
            % Traverses the edges of a polygon (given as an ordered vertex
            % list) and places bars at uniform arc-length spacing along the
            % path.  The polygon can be treated as open (a poly-line) or
            % closed (the last vertex connects back to the first).
            %
            % This is useful for non-rectangular or non-circular cages,
            % such as hexagonal columns, wall boundary elements, or custom
            % shapes.
            %
            % Parameters
            % ----------
            % yPath : (M,) double
            %     y-coordinates of the polygon vertices in traversal order.
            % zPath : (M,) double
            %     z-coordinates of the polygon vertices in traversal order.
            % n : int, keyword
            %     Total number of bars distributed along the full path
            %     (including the start point; end point included only if
            %     ``closed = true``).
            % gap : double, keyword
            %     Target arc-length spacing between adjacent bars.
            % closed : logical, optional keyword
            %     ``true`` (default) – the last vertex connects back to the
            %     first vertex, forming a closed loop.
            %     ``false`` – the path is open; bars run from the first to
            %     the last vertex only.
            %
            % Returns
            % -------
            % coords : (N, 2) double
            %     Bar centre coordinates; each row is ``[y, z]``.
            %
            % Notes
            % -----
            % Bar positions are determined by uniform arc-length
            % parameterisation of the polyline.  Vertices of the path are
            % not necessarily bar positions.
            %
            % Examples
            % --------
            % Hexagonal cage, 18 bars, closed::
            %
            %     ang   = (0:5) * 60;
            %     yHex  = 250 * cosd(ang);
            %     zHex  = 250 * sind(ang);
            %     c = pre.FiberSectionMesh.polygonRebars(yHex, zHex, 'n', 18);
            %
            % Open poly-line, bars at 80 mm::
            %
            %     c = pre.FiberSectionMesh.polygonRebars( ...
            %             [-200,0,200], [0,300,0], 'gap', 80, 'closed', false);

            ip = inputParser;
            addParameter(ip, 'n',      [], @(x) isscalar(x) && x >= 2);
            addParameter(ip, 'gap',    [], @(x) isscalar(x) && x > 0);
            addParameter(ip, 'closed', true, @islogical);
            parse(ip, varargin{:});
            r = ip.Results;

            yPath = yPath(:);  zPath = zPath(:);
            if numel(yPath) ~= numel(zPath) || numel(yPath) < 2
                error('FiberSectionMesh:invalidPath', ...
                    'yPath and zPath must be equal-length vectors with >= 2 elements.');
            end

            % Build closed or open path
            if r.closed
                yPth = [yPath; yPath(1)];
                zPth = [zPath; zPath(1)];
            else
                yPth = yPath;
                zPth = zPath;
            end

            % Cumulative arc length
            dSeg  = hypot(diff(yPth), diff(zPth));
            sCum  = [0; cumsum(dSeg)];
            Ltot  = sCum(end);

            % Determine n
            p = pre.FiberSectionMesh.parseNorGap('n', r.n, 'gap', r.gap);
            if p.useN
                nBars = p.n;
            else
                nBars = max(2, round(Ltot / p.gap) + double(r.closed));
            end

            if r.closed
                sBar = linspace(0, Ltot, nBars+1);
                sBar(end) = [];
            else
                sBar = linspace(0, Ltot, nBars);
            end

            % Interpolate positions along path
            yBar = interp1(sCum, yPth, sBar, 'linear');
            zBar = interp1(sCum, zPth, sBar, 'linear');
            coords = [yBar(:), zBar(:)];
        end

        % ==================================================================
        %  MISCELLANEOUS
        % ==================================================================

        function demo()
            % demo  Run a self-contained demonstration of FiberSectionMesh.
            %
            % Constructs a 400 x 600 mm rectangular reinforced-concrete
            % section with a confined core (matTag 1), unconfined cover
            % (matTag 2), and a perimeter rebar cage of D24 HRB400 bars
            % (matTag 3).  The section is meshed, properties are computed
            % and printed, the mesh is visualised.  The ``build`` step is
            % shown with a mock ops object; replace it with a real
            % ``OpenSees`` instance in production use.
            %
            % Examples
            % --------
            % ::
            %
            %     pre.FiberSectionMesh.demo();

            fprintf('========== FiberSectionMesh Demo ==========\n');

            % --- Geometry ------------------------------------------------
            outer      = pre.FiberSectionMesh.rectShape(400, 600);
            inner      = pre.FiberSectionMesh.rectShape(340, 540);
            coverShape = subtract(outer, inner);

            % --- Parts ---------------------------------------------------
            parts(1).name     = 'Confined core';
            parts(1).matTag   = 1;
            parts(1).geometry = inner;
            parts(1).meshSize = 30;

            parts(2).name     = 'Cover concrete';
            parts(2).matTag   = 2;
            parts(2).geometry = coverShape;
            parts(2).meshSize = 30;

            % --- Rebars (gap-based) --------------------------------------
            coords = pre.FiberSectionMesh.rectRebars(400, 600, 50, 'gap', 120);
            rebars(1).name   = 'HRB400 D24';
            rebars(1).matTag = 3;
            rebars(1).coords = coords;
            rebars(1).area   = pi * 12^2;

            % --- Assemble -----------------------------------------------
            sec = pre.FiberSectionMesh(parts, rebars, 101);
            sec.mesh();
            sec.computeProps();
            sec.printProps();
            sec.plot();

            % --- Build into OpenSees ------------------------------------
            % In real use, create via opsmat.pre.fiberSection.new()
            % so that ops is injected automatically:
            %   sec = opsmat.pre.fiberSection.new(parts, rebars, 101);
            %   sec.mesh();
            %   sec.build();
            fprintf('\n[demo] build() skipped: use opsmat.pre.fiberSection.new(...) in production.\n');
            fprintf('\n========== Demo complete ==========\n');
        end

    end % static methods

    % ====================================================================
    %  Private static helpers
    % ====================================================================
    methods (Static, Access = private)

        function p = parseNorGap(varargin)
            % parseNorGap  Parse mutually exclusive 'n' / 'gap' keyword pair.
            %
            % Accepts the raw varargin from caller methods and returns a
            % struct with fields:
            %   p.useN  – true if 'n' was supplied (and non-empty)
            %   p.n     – value of n  ([] if not supplied)
            %   p.gap   – value of gap ([] if not supplied)

            ip = inputParser;
            addParameter(ip, 'n',   [], @(x) isempty(x) || (isscalar(x) && x >= 1));
            addParameter(ip, 'gap', [], @(x) isempty(x) || (isscalar(x) && x > 0));
            parse(ip, varargin{:});

            hasN   = ~isempty(ip.Results.n);
            hasGap = ~isempty(ip.Results.gap);

            if hasN && hasGap
                error('FiberSectionMesh:ambiguousInput', ...
                    'Specify either n or gap, not both.');
            end
            if ~hasN && ~hasGap
                error('FiberSectionMesh:missingSpacing', ...
                    'Specify either n or gap.');
            end

            p.useN = hasN;
            p.n    = ip.Results.n;
            p.gap  = ip.Results.gap;
        end

    end % private static methods

end % classdef
