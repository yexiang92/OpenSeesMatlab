classdef MomentCurvature < handle
    % MomentCurvature
    %   Moment-curvature analysis and N-My-Mz interaction surface
    %   for fiber sections.
    %
    % Typical usage
    % -------------
    %     opsmat = OpenSeesMatlab();
    %     mc     = opsmat.anlys.MomentCurvature;
    %     mc.new(secTag, axialForce);
    %     mc.analyze('axis','y','maxPhi',0.05,'incrPhi',1e-4);
    %     mc.plotMPhi();
    %     [phiU, MU] = mc.getLimitState('matTag',1,'threshold',-0.003);
    %     mc.bilinearize(phiY, MY, phiU, 'plot', true);
    %
    %     mc.buildNMM('NList', linspace(-2000e3,0,10)', ...
    %                 'phiMax',0.05,'nTheta',36,'useParallel',true);
    %     mc.plotNMM();
    %

    % ------------------------------------------------------------------
    properties (SetAccess = private)
        secTag    (1,1) double = 1    % Previously defined section tag
        P         (1,1) double = 0    % Applied axial load (negative = compression)

        phi       (:,1) double = []   % Curvature array  [nStep x 1]
        M         (:,1) double = []   % Moment array     [nStep x 1]
        FiberData (:,:,:) double = [] % Fiber data       [nStep x nFiber x 6]
                                      %   cols: yCoord zCoord area matTag stress strain
        cyclePath (:,1) double = []   % Cyclic loading path (curvature targets)
        NMMresult struct = struct()   % N-My-Mz surface data; see buildNMM
    end

    properties (Access = private)
        ops       % OpenSees interpreter handle (OpenSeesMatlabCmds object)
    end

    % ------------------------------------------------------------------
    methods (Access = public)

        % Constructor
        % -----------
        function obj = MomentCurvature(opsHandle, secTag, axialForce)
            % Construct an instance.
            %
            % Parameters
            % ----------
            % opsHandle : OpenSeesMatlabCmds, optional
            %     OpenSees interpreter handle.  When omitted a stub is
            %     created; call new() or setOps() before analyzing.
            % secTag : double, optional
            %     Tag of the previously defined fiber section. Default 1.
            % axialForce : double, optional
            %     Constant axial load. Compression negative. Default 0.
            arguments
                opsHandle  = []
                secTag     (1,1) double = 1
                axialForce (1,1) double = 0
            end
            if ~isempty(opsHandle)
                mc_validateOps(opsHandle);
                obj.ops = opsHandle;
            end
            obj.secTag    = secTag;
            obj.P         = axialForce;
            obj.phi       = [];
            obj.M         = [];
            obj.FiberData = [];
            obj.cyclePath = [];
            obj.NMMresult = struct();
        end

        % new
        % ---
        function obj = new(obj, secTag, axialForce)
            % Re-initialise this instance with a new section and axial load.
            %
            % Parameters
            % ----------
            % secTag : double
            %     Tag of the previously defined fiber section.
            % axialForce : double, optional
            %     Constant axial load. Compression negative. Default 0.
            %
            % Returns
            % -------
            % obj : MomentCurvature
            %     The same handle object, re-initialised in place.
            %
            % Example
            % -------
            %     % Reuse the same ops handle for a new section / axial load.
            %     mc = mc.new(2, -500e3);
            arguments
                obj
                secTag     (1,1) double
                axialForce (1,1) double = 0
            end
            if isempty(obj.ops)
                error('MomentCurvature:new:noOps', ...
                    ['No OpenSees interpreter is bound. ', ...
                     'Use MomentCurvature.create(ops,secTag,P) or ', ...
                     'call setOps(ops) first.']);
            end
            obj = analysis.MomentCurvature(obj.ops, secTag, axialForce);
        end

        % setCyclePath
        % ------------
        function path = setCyclePath(obj, maxPhi, opts)
            % Build a symmetric incrementally-growing cyclic path.
            %
            % Parameters
            % ----------
            % maxPhi : double
            %     Peak curvature (sign ignored; both directions included).
            % nCycle : int, optional
            %     Number of amplitude levels. Default 20.
            % nHold : int, optional
            %     Repetitions at each amplitude level. Default 1.
            %
            % Returns
            % -------
            % path : double array, shape (1 + (nCycle-1)*2*nHold + 1,)
            %     Curvature target sequence, stored in obj.cyclePath.
            %     Starts and ends at 0.
            arguments
                obj
                maxPhi      (1,1) double
                opts.nCycle (1,1) double = 20
                opts.nHold  (1,1) double = 1
            end
            maxPhi = abs(maxPhi);
            % nC     = opts.nCycle - 1;
            nH     = opts.nHold;

            upper = linspace(0,  maxPhi, opts.nCycle); upper = upper(2:end);
            below = linspace(0, -maxPhi, opts.nCycle); below = below(2:end);

            % Interleave upper/below: [u1 b1 u2 b2 ... uNC bNC]
            % then repeat each pair nH times consecutively.
            pairs    = reshape([upper; below], 1, []);          % [1 x 2*nC]
            repeated = repelem(pairs, nH);                      % [1 x 2*nC*nH]
            % repelem repeats each element nH times; we need each pair repeated.
            % Reshape to (nH x 2*nC), transpose, then flatten to get the correct
            % order: [u1 b1 u1 b1 ... u2 b2 ...] when nH > 1.
            repeated = reshape(reshape(repeated, nH, []).', 1, []);

            pat           = [0, repeated, 0].';
            obj.cyclePath = pat;
            path          = pat;
        end

        % analyze
        % -------
        function analyze(obj, opts)
            % Run the moment-curvature analysis.
            %
            % Parameters
            % ----------
            % axis : {'y','z'}, optional
            %     Bending axis. Default 'y'.
            % maxPhi : double, optional
            %     Maximum target curvature. Default 0.05.
            % incrPhi : double, optional
            %     Base curvature increment. Default 1e-4.
            % limitPeakRatio : double, optional
            %     Post-peak stop ratio. Default 0.8.
            % cycleAnalyze : logical, optional
            %     Follow the path from setCyclePath. Default false.
            % smartAnalyze : logical, optional
            %     Adaptive step-halving + algorithm rotation. Default true.
            %
            % Notes
            % -----
            %   Results written to ``obj.phi``, ``obj.M``, ``obj.FiberData``.
            arguments
                obj
                opts.axis           (1,:) char    = 'y'
                opts.maxPhi         (1,1) double  = 0.05
                opts.incrPhi        (1,1) double  = 1e-4
                opts.limitPeakRatio (1,1) double  = 0.8
                opts.cycleAnalyze   (1,1) logical = false
                opts.smartAnalyze   (1,1) logical = true
            end
            obj.mc_requireOps();
            [obj.phi, obj.M, obj.FiberData] = mc_analyze( ...
                obj.ops, obj.secTag, obj.P, ...
                opts.axis, opts.maxPhi, opts.incrPhi, ...
                opts.limitPeakRatio, opts.cycleAnalyze, obj.cyclePath, ...
                opts.smartAnalyze);
            fprintf('MomentCurvature: analysis complete.\n');
        end

        % Accessors
        % ---------
        function [phi, M] = getMPhi(obj)
            % Return curvature and moment arrays.
            %
            % Returns
            % -------
            % phi : double array, shape (nStep,)
            % M   : double array, shape (nStep,)
            phi = obj.phi; M = obj.M;
        end

        function phi = getCurvature(obj)
            % Return the curvature array.
            %
            % Returns
            % -------
            % phi : double array, shape (nStep,)
            phi = obj.phi;
        end

        function M = getMoment(obj)
            % Return the moment array.
            %
            % Returns
            % -------
            % M : double array, shape (nStep,)
            M = obj.M;
        end

        % getLimitState
        % -------------
        function [phiU, MU, idxU] = getLimitState(obj, opts)
            % Locate the curvature and moment at a limit state.
            %
            % Two modes (mutually exclusive):
            %
            % Strain-threshold mode (default)
            %   First step at which any monitored fiber reaches the given
            %   strain threshold.
            %   Positive threshold -> tensile  strain limit.
            %   Negative threshold -> compressive strain limit.
            %
            % Peak-drop mode (peakDrop supplied)
            %   First post-peak step at which |M| <= (1-peakDrop)*|M_peak|.
            %   Both positive and negative moment directions handled via abs(M).
            %
            % Parameters
            % ----------
            % matTag : scalar or vector, optional
            %     Material tag(s) to monitor. Default 1.
            % threshold : scalar or vector, optional
            %     Strain threshold(s). Scalar is broadcast to all matTags.
            %     Default 0.0.
            % peakDrop : double in (0,1), optional
            %     Fractional strength drop, e.g. 0.20 = 20 % drop.
            %     When supplied, matTag / threshold are ignored.
            %
            % Returns
            % -------
            % phiU : double  - curvature at the limit state.
            % MU   : double  - moment at the limit state.
            % idxU : int     - step index (1-based).

            arguments
                obj
                opts.matTag    = 1
                opts.threshold = 0.0
                opts.peakDrop  = []
            end
            obj.mc_requireResult();

            phi_ = obj.phi(:);
            M_   = obj.M(:);
            fd   = obj.FiberData;

            if ~isempty(opts.peakDrop)
                [MU, idxU] = mc_extractMomentCapacity( ...
                    phi_, M_, fd, 'peakdrop', abs(opts.peakDrop), ...
                    opts.matTag, opts.threshold, NaN);
            else
                [MU, idxU] = mc_extractMomentCapacity( ...
                    phi_, M_, fd, 'strain', 0, ...
                    opts.matTag, opts.threshold, NaN);
            end
            phiU = phi_(idxU);
        end

        % bilinearize
        % -----------
        function [phiEq, MEq, idxU] = bilinearize(obj, phiY, MY, phiU, opts)
            % Equal-area bilinear approximation of M-phi.
            %
            % Elastic branch slope k = MY/phiY is preserved.  phiEq and MEq
            % are found by equating the area under the bilinear curve to the
            % area under the actual M-phi curve up to phiU.
            %
            % Both positive and negative loading directions are supported:
            % the calculation is performed in absolute-value space and
            % mapped back to the original sign convention on return.
            %
            % Parameters
            % ----------
            % phiY : double
            %   initial yield curvature (pos or neg).
            % MY   : double
            %   initial yield moment    (pos or neg).
            % phiU : double
            %   limit curvature         (pos or neg).
            % plot : logical, optional
            %   plot bilinear overlay. Default false.
            % ax   : Axes,   optional
            %   target axes; new figure if empty.
            %
            % Returns
            % -------
            % phiEq : double
            %   equivalent yield curvature.
            % MEq   : double
            %   equivalent yield moment.
            % idxU  : int
            %   index in obj.phi nearest to phiU on branch.
            %
            arguments
                obj
                phiY (1,1) double
                MY   (1,1) double
                phiU (1,1) double
                opts.plot (1,1) logical = false
                opts.ax   = []
            end
            obj.mc_requireResult();

            phi_ = obj.phi(:);
            M_   = obj.M(:);

            if phiY == 0 || MY == 0 || phiU == 0
                error('MomentCurvature:bilinearize:zeroInput', ...
                    'phiY, MY, and phiU must all be nonzero.');
            end

            % Determine loading direction; work in absolute-value space.
            sPhi = sign(phiU); if sPhi == 0, sPhi = sign(phiY); end
            if sPhi == 0, sPhi = 1; end
            sM   = sign(MY);   if sM   == 0, sM   = sPhi;       end

            phiYAbs = abs(phiY);
            MYAbs   = abs(MY);
            phiUAbs = abs(phiU);

            % Select monotonic branch in direction sPhi.
            if sPhi > 0
                mask = phi_ >= 0;
            else
                mask = phi_ <= 0;
            end
            phiBr  = phi_(mask);
            MBr    = M_(mask);
            idxBr  = find(mask);

            if numel(phiBr) < 2
                error('MomentCurvature:bilinearize:emptyBranch', ...
                    'Fewer than 2 points on the selected loading branch.');
            end

            % Sort by ascending |phi|; remove duplicate curvature values.
            [~, ord]     = sort(abs(phiBr), 'ascend');
            phiBr        = phiBr(ord);
            MBr          = MBr(ord);
            idxBr        = idxBr(ord);
            [phiAbs, ia] = unique(abs(phiBr), 'stable');
            MAbs         = abs(MBr(ia));
            idxBr        = idxBr(ia);

            if phiUAbs > max(phiAbs)
                warning('MomentCurvature:bilinearize:phiUOutsideRange', ...
                    'abs(phiU) exceeds available curvature range; last point used.');
                phiUAbs = max(phiAbs);
            end

            % Index in original phi_ nearest to phiU.
            [~, iLoc] = min(abs(phiAbs - phiUAbs));
            idxU      = idxBr(iLoc);

            % Build integration curve [0 .. phiU].
            mask2  = phiAbs <= phiUAbs;
            phiInt = phiAbs(mask2);
            MInt   = MAbs(mask2);

            if isempty(phiInt) || phiInt(1) > 0
                phiInt = [0; phiInt(:)];
                MInt   = [0; MInt(:)];
            end

            % Interpolate M at exactly phiU and append / replace endpoint.
            MU_abs = interp1(phiAbs, MAbs, phiUAbs, 'linear', 'extrap');
            if phiInt(end) < phiUAbs
                phiInt = [phiInt(:); phiUAbs];
                MInt   = [MInt(:);   MU_abs];
            else
                phiInt(end) = phiUAbs;
                MInt(end)   = MU_abs;
            end
            [phiInt, iUniq] = unique(phiInt(:), 'stable');
            MInt             = MInt(iUniq);

            if numel(phiInt) < 2
                error('MomentCurvature:bilinearize:notEnoughPoints', ...
                    'Not enough integration points after deduplication.');
            end

            % Equal-area formula:
            %   Q = trapz(M, phi)   [area under actual curve]
            %   k = MY / phiY       [elastic slope]
            %   phiEq = (k*phiU - sqrt((k*phiU)^2 - 2*k*Q)) / k
            Q    = trapz(phiInt, MInt);
            k    = MYAbs / phiYAbs;
            disc = (k * phiUAbs)^2 - 2.0 * k * Q;
            if disc < -1e-10 * max(1, (k*phiUAbs)^2)
                error('MomentCurvature:bilinearize:negativeDisc', ...
                    ['Negative discriminant. ', ...
                     'Check phiY, MY, phiU and the selected loading branch.']);
            end
            disc     = max(disc, 0);
            phiEqAbs = (k * phiUAbs - sqrt(disc)) / k;
            MEqAbs   = k * phiEqAbs;

            phiEq = sPhi * phiEqAbs;
            MEq   = sM   * MEqAbs;

            % Optional plot.
            if opts.plot
                ax = opts.ax;
                if isempty(ax)
                    figure('Position',[100 100 820 520],'Color','w');
                    ax = axes;
                end
                hold(ax,'on');
                plot(ax, sPhi*phiInt, sM*MInt, 'b-','LineWidth',1.5, ...
                    'DisplayName','M-\phi curve');
                plot(ax, [0,phiY,phiEq,phiU], [0,MY,MEq,MEq], 'r-', ...
                    'LineWidth',1.5,'DisplayName','Bilinear approx.');
                plot(ax, phiY, MY, 'o','MarkerSize',9, ...
                    'MarkerEdgeColor','k','MarkerFaceColor','#0099e5', ...
                    'DisplayName', ...
                    sprintf('Initial yield  \\phi_y=%.3g, M_y=%.3g',phiY,MY));
                plot(ax, phiEq, MEq, '*','MarkerSize',12, ...
                    'MarkerEdgeColor','k','MarkerFaceColor','#ff4c4c', ...
                    'DisplayName', ...
                    sprintf('Equiv. yield  \\phi_{eq}=%.3g, M_{eq}=%.3g',phiEq,MEq));
                xline(ax, phiU,'--g','LineWidth',0.8, ...
                    'DisplayName',sprintf('\\phi_u = %.3g',phiU));
                xlabel(ax,'\phi','FontSize',14);
                ylabel(ax,'M','FontSize',14);
                title(ax,'Moment-Curvature Bilinear Approximation','FontSize',15);
                legend(ax,'Location','best');
                grid(ax,'on'); box(ax,'on'); hold(ax,'off');
            end
        end

        % plotMPhi
        % --------
        function plotMPhi(obj, ax)
            % Plot the moment-curvature relationship.
            %
            % Parameters
            % ----------
            % ax : Axes, optional
            %   target axes; new figure if empty.
            arguments
                obj
                ax = []
            end
            obj.mc_requireResult();
            if isempty(ax)
                figure('Position',[100 100 800 500],'Color','w');
                ax = axes;
            end
            lw = 1.5;
            if ~isempty(obj.cyclePath), lw = 0.8; end
            plot(ax, obj.phi, obj.M, '-','Color','b','LineWidth',lw);
            xlabel(ax,'\phi','FontSize',16);
            ylabel(ax,'M','FontSize',16);
            title(ax,'M - \phi Curve','FontSize',18);
            grid(ax,'on');
        end

        % plotFiberResponses
        % ------------------
        function axs = plotFiberResponses(obj, opts)
            % Stress-strain histories by selected material tag(s).
            %
            % One subplot per selected material tag; all fibers of that material
            % are plotted in a single vectorised plot() call.
            %
            % Parameters
            % ----------
            % matTag : scalar or array, optional
            %     Material tag(s) to visualize. If empty, all material tags are used.
            %
            % lineWidth : double, optional
            %     Curve line width. Default 0.7.
            %
            % maxFibers : double, optional
            %     Maximum number of fibers per material. Uniform subsampling is used
            %     when the number of fibers exceeds this value. Default Inf.
            %
            % shareX / shareY : logical, optional
            %     Link subplot axes. Default true / false.
            %
            % Returns
            % -------
            % axs : Axes array, shape (nSelectedMaterials,)

            arguments
                obj
                opts.matTag              = []
                opts.lineWidth (1,1) double  = 1.0
                opts.maxFibers (1,1) double  = Inf
                opts.shareX    (1,1) logical = true
                opts.shareY    (1,1) logical = false
            end

            obj.mc_requireResult();

            fd = obj.FiberData;
            if isempty(fd) || ndims(fd) ~= 3 || size(fd,3) < 6
                error('MomentCurvature:plotFiberResponses:badFiberData', ...
                    'FiberData is missing or has unexpected shape.');
            end

            nStep = size(fd,1);

            % Material tags are assumed to be constant across steps.
            matIDrow = squeeze(fd(end,:,4));
            matIDrow = matIDrow(:).';

            validMat = isfinite(matIDrow) & matIDrow ~= 0;
            allMatTags = unique(matIDrow(validMat), 'stable');
            allMatTags = allMatTags(:);

            if isempty(allMatTags)
                error('MomentCurvature:plotFiberResponses:noMatTag', ...
                    'No valid material tags found in FiberData.');
            end

            % --------------------------------------------------------------
            % Select material tags.
            % If opts.matTag is empty, plot all materials.
            % If opts.matTag is scalar/vector, plot only requested tags.
            % --------------------------------------------------------------
            if isempty(opts.matTag)
                matTags = allMatTags;
            else
                reqTags = opts.matTag(:);

                if ~isnumeric(reqTags)
                    error('MomentCurvature:plotFiberResponses:invalidMatTag', ...
                        'matTag must be a numeric scalar or numeric array.');
                end

                reqTags = reqTags(isfinite(reqTags));

                if isempty(reqTags)
                    error('MomentCurvature:plotFiberResponses:emptyRequestedMatTag', ...
                        'The requested matTag list is empty or invalid.');
                end

                % Preserve user-specified order and remove duplicates.
                reqTags = unique(reqTags, 'stable');

                keep = false(numel(reqTags), 1);
                for i = 1:numel(reqTags)
                    keep(i) = any(abs(allMatTags - reqTags(i)) < 1e-6);
                end

                missingTags = reqTags(~keep);
                if ~isempty(missingTags)
                    warning('MomentCurvature:plotFiberResponses:matTagNotFound', ...
                        'The following requested material tags were not found and will be skipped: %s', ...
                        mat2str(missingTags(:).'));
                end

                matTags = reqTags(keep);

                if isempty(matTags)
                    error('MomentCurvature:plotFiberResponses:noRequestedMatTagFound', ...
                        'None of the requested material tags were found in FiberData.');
                end
            end

            nMat = numel(matTags);

            strainAll = fd(:,:,6);
            stressAll = fd(:,:,5);

            figH = max(280, 260*nMat);
            figure('Position',[100 100 720 figH], 'Color','w');

            axs = gobjects(nMat,1);
            colors = lines(nMat);

            for k = 1:nMat
                axs(k) = subplot(nMat,1,k);

                tag = matTags(k);
                idxF = find(validMat & abs(matIDrow - tag) < 1e-6);

                if isempty(idxF)
                    title(axs(k), sprintf('matTag = %g (no fibers)', tag), ...
                        'FontSize', 13);
                    grid(axs(k),'on');
                    box(axs(k),'on');
                    continue;
                end

                if isfinite(opts.maxFibers) && numel(idxF) > opts.maxFibers
                    pick = unique(round(linspace(1, numel(idxF), opts.maxFibers)));
                    idxF = idxF(pick);
                end

                strain = reshape(strainAll(:,idxF), nStep, []);
                stress = reshape(stressAll(:,idxF), nStep, []);

                % Keep curves with at least one valid point.
                good = any(isfinite(strain) & isfinite(stress), 1);
                strain = strain(:,good);
                stress = stress(:,good);

                if isempty(strain)
                    title(axs(k), sprintf('matTag = %g (no valid data)', tag), ...
                        'FontSize', 13);
                    grid(axs(k),'on');
                    box(axs(k),'on');
                    continue;
                end

                plot(axs(k), strain, stress, ...
                    'LineWidth', opts.lineWidth, ...
                    'Color', colors(k,:));

                hold(axs(k),'on');
                xline(axs(k), 0, ':', ...
                    'LineWidth', 0.6, ...
                    'HandleVisibility', 'off');
                yline(axs(k), 0, ':', ...
                    'LineWidth', 0.6, ...
                    'HandleVisibility', 'off');
                hold(axs(k),'off');

                title(axs(k), sprintf('matTag = %g,  nFiber = %d', tag, size(strain,2)), ...
                    'FontSize', 13);
                xlabel(axs(k), 'Strain', 'FontSize', 12);
                ylabel(axs(k), 'Stress', 'FontSize', 12);
                grid(axs(k),'on');
                box(axs(k),'on');
            end

            if nMat > 1
                if opts.shareX && opts.shareY
                    linkaxes(axs,'xy');
                elseif opts.shareX
                    linkaxes(axs,'x');
                elseif opts.shareY
                    linkaxes(axs,'y');
                end
            end
        end

        % buildNMM
        % --------
        function buildNMM(obj, opts)
            % Compute the approximate N-My-Mz interaction surface.
            %
            % Algorithm
            % ---------
            %   For each N_i two uniaxial analyses (axis-y, axis-z) yield
            %   $M_{y,Cap}(N_i)$ and $M_{z,Cap}(N_i)$.  The n Theta-point contour is then
            %   computed analytically from the ellipse formula:
            %   
            %   $$
            %   \left(\frac{M_y}{M_{y,Cap}}\right)^2 + \left(\frac{M_z}{M_{z,Cap}}\right)^2 = 1
            %   $$
            %
            % Capacity modes
            % --------------
            %   - 'peak'      max(|M|) over the full run.
            %   - 'peakDrop'  first post-peak point where |M|<=(1-drop)*|M_peak|.
            %   - 'strain'    first step where a fiber strain reaches threshold.
            %   - 'curvature' |M| at the curvature nearest to targetPhi.
            %   - 'manual'    user-supplied MyCapManual / MzCapManual.
            %
            % Parameters
            % ----------
            % NList          : double array (nN,)  
            %   axial loads, compression<0.
            % axis1/axis2    : char                
            %   bending axes. Default 'y','z'.
            % phiMax         : double              
            %   max curvature. Default 0.05.
            % incrPhi        : double              
            %   base increment. Default 1e-4.
            % nTheta         : int                 
            %   direction divisions. Default 36.
            % limitPeakRatio : double              
            %   stop ratio per run. Default 0.8.
            % smartAnalyze   : logical             
            %   adaptive step. Default true.
            % useParallel    : logical             
            %   parfor (PCT). Default false.
            % capacityMode   : char                
            %   see above. Default 'peak'.
            % peakDrop       : double              
            %   drop ratio. Default 0.20.
            % matTag         : scalar/vector       
            %   for 'strain' mode.
            % threshold      : scalar/vector       
            %   for 'strain' mode.
            % targetPhi      : double              
            %   for 'curvature' mode.
            % MyCapManual    : double (nN,)        
            %   for 'manual' mode.
            % MzCapManual    : double (nN,)        
            %   for 'manual' mode.
            arguments
                obj
                opts.NList          (:,1) double  = linspace(-1e6,0,8)'
                opts.axis1          (1,:) char    = 'y'
                opts.axis2          (1,:) char    = 'z'
                opts.phiMax         (1,1) double  = 0.05
                opts.incrPhi        (1,1) double  = 1e-4
                opts.nTheta         (1,1) double  = 36
                opts.limitPeakRatio (1,1) double  = 0.8
                opts.smartAnalyze   (1,1) logical = true
                opts.useParallel    (1,1) logical = false
                opts.capacityMode   (1,:) char    = 'peak'
                opts.peakDrop       (1,1) double  = 0.20
                opts.matTag                       = 1
                opts.threshold                    = 0.0
                opts.targetPhi      (1,1) double  = NaN
                opts.MyCapManual    (:,1) double  = []
                opts.MzCapManual    (:,1) double  = []
            end
            obj.mc_requireOps();

            NList   = opts.NList(:);
            nN      = numel(NList);
            nT      = opts.nTheta;
            capMode = lower(string(opts.capacityMode));

            validModes = ["peak","peakdrop","strain","curvature","manual"];
            if ~ismember(capMode, validModes)
                error('MomentCurvature:buildNMM:invalidCapacityMode', ...
                    'capacityMode must be one of: peak, peakDrop, strain, curvature, manual.');
            end
            if nT < 4
                error('MomentCurvature:buildNMM:invalidNTheta','nTheta must be >= 4.');
            end

            % FIX-6: request fiber data only when the mode actually needs it.
            needFd = (capMode == "strain");

            if capMode == "manual"
                if numel(opts.MyCapManual) ~= nN || numel(opts.MzCapManual) ~= nN
                    error('MomentCurvature:buildNMM:manualSizeMismatch', ...
                        'MyCapManual and MzCapManual must match the length of NList.');
                end
                MyCap = abs(opts.MyCapManual(:));
                MzCap = abs(opts.MzCapManual(:));
            else
                MyCap = zeros(nN,1);
                MzCap = zeros(nN,1);

                % Cache scalars for parfor broadcast.
                opsH  = obj.ops;
                sTag  = obj.secTag;
                pMax  = opts.phiMax;   dPhi = opts.incrPhi;
                sRat  = opts.limitPeakRatio; sAna = opts.smartAnalyze;
                ax1   = opts.axis1;    ax2  = opts.axis2;
                cMode = char(capMode);
                pDrop = opts.peakDrop;
                mTag  = opts.matTag;
                mThr  = opts.threshold;
                tPhi  = opts.targetPhi;

                fprintf('buildNMM: capacityMode=%s,  %d levels x 2 = %d analyses.\n', ...
                    cMode, nN, nN*2);

                if opts.useParallel
                    parfor iN = 1:nN
                        Ni = NList(iN);
                        if needFd
                            [p1,M1,f1] = mc_analyze(opsH,sTag,Ni,ax1,pMax,dPhi,sRat,false,[],sAna); %#ok<PFBNS>
                            [p2,M2,f2] = mc_analyze(opsH,sTag,Ni,ax2,pMax,dPhi,sRat,false,[],sAna);
                        else
                            [p1,M1] = mc_analyze(opsH,sTag,Ni,ax1,pMax,dPhi,sRat,false,[],sAna);
                            [p2,M2] = mc_analyze(opsH,sTag,Ni,ax2,pMax,dPhi,sRat,false,[],sAna);
                            f1=[]; f2=[];
                        end
                        [Mc1,~] = mc_extractMomentCapacity(p1,M1,f1,cMode,pDrop,mTag,mThr,tPhi); %#ok<PFBNS>
                        [Mc2,~] = mc_extractMomentCapacity(p2,M2,f2,cMode,pDrop,mTag,mThr,tPhi);
                        MyCap(iN) = abs(Mc1); %#ok<PFOUS>
                        MzCap(iN) = abs(Mc2);
                    end
                else
                    for iN = 1:nN
                        Ni = NList(iN);
                        fprintf('  N = %+.3e  (%d/%d)\n', Ni, iN, nN);
                        if needFd
                            [p1,M1,f1] = mc_analyze(opsH,sTag,Ni,ax1,pMax,dPhi,sRat,false,[],sAna);
                            [p2,M2,f2] = mc_analyze(opsH,sTag,Ni,ax2,pMax,dPhi,sRat,false,[],sAna);
                        else
                            [p1,M1] = mc_analyze(opsH,sTag,Ni,ax1,pMax,dPhi,sRat,false,[],sAna);
                            [p2,M2] = mc_analyze(opsH,sTag,Ni,ax2,pMax,dPhi,sRat,false,[],sAna);
                            f1=[]; f2=[];
                        end
                        [Mc1,~] = mc_extractMomentCapacity(p1,M1,f1,cMode,pDrop,mTag,mThr,tPhi);
                        [Mc2,~] = mc_extractMomentCapacity(p2,M2,f2,cMode,pDrop,mTag,mThr,tPhi);
                        MyCap(iN) = abs(Mc1);
                        MzCap(iN) = abs(Mc2);
                    end
                end
            end

            if any(~isfinite(MyCap)|MyCap<=0|~isfinite(MzCap)|MzCap<=0)
                error('MomentCurvature:buildNMM:invalidCapacity', ...
                    'All MyCap and MzCap entries must be positive and finite.');
            end

            % Vectorised ellipse broadcast [nN x 1] over [1 x nT].
            thetas = linspace(0,2*pi,nT+1); thetas = thetas(1:end-1);
            cosT   = cos(thetas); sinT = sin(thetas);
            denom  = (cosT./MyCap).^2 + (sinT./MzCap).^2;  % [nN x nT]
            r      = 1./sqrt(denom);
            MyGrid = [r.*cosT,  r(:,1).*cosT(1)];  % [nN x nT+1] closed
            MzGrid = [r.*sinT,  r(:,1).*sinT(1)];

            res            = struct();
            res.N          = NList;
            res.My         = MyGrid;
            res.Mz         = MzGrid;
            res.thetas     = [thetas, thetas(1)+2*pi];
            res.MyCap      = MyCap;
            res.MzCap      = MzCap;
            res.MyPeak     = MyCap;   % legacy alias
            res.MzPeak     = MzCap;
            res.capMode    = char(capMode);
            obj.NMMresult  = res;

            nAnalyses = mc_ternary(capMode=="manual", 0, nN*2);
            fprintf('buildNMM: done.  (%d OpenSees analyses)\n', nAnalyses);
        end

        % plotNMM
        % -------
        function axs = plotNMM(obj, opts)
            % Render the N-My-Mz interaction surface (up to 3 figures).
            %
            %  - Figure 1 (showSurface)  - 3-D surface + per-N contour rings + generatrix lines.
            %  - Figure 2 (showPlanView) - My-Mz plan view, one contour per N.
            %  - Figure 3 (showEnvelope) - Uniaxial N-MyCap and N-MzCap lines.
            %
            % Parameters
            % ----------
            % normalize    : logical
            %   normalise axes. Default false.
            % alpha        : double
            %   surface transparency. Default 0.5.
            % colormap     : char
            %   colormap name. Default 'turbo'.
            % showSurface  : logical
            %   toggle Fig 1. Default true.
            % showPlanView : logical
            %   toggle Fig 2. Default true.
            % showEnvelope : logical
            %   toggle Fig 3. Default true.
            %
            % Returns
            % -------
            % axs : struct  - fields: surface, plan, envelope.
            %     Suppressed figures have [].
            arguments
                obj
                opts.normalize    (1,1) logical = false
                opts.alpha        (1,1) double  = 0.5
                opts.colormap     (1,:) char    = 'turbo'
                opts.showSurface  (1,1) logical = true
                opts.showPlanView (1,1) logical = true
                opts.showEnvelope (1,1) logical = true
            end

            if isempty(fieldnames(obj.NMMresult))
                error('MomentCurvature:plotNMM:noData', ...
                    'Run buildNMM() before plotNMM().');
            end

            % FIX-8: always initialise all fields.
            axs = struct('surface',[], 'plan',[], 'envelope',[]);

            res    = obj.NMMresult;
            N      = res.N(:);
            My     = res.My;
            Mz     = res.Mz;
            nN     = numel(N);
            MyCap  = res.MyCap(:);
            MzCap  = res.MzCap(:);
            capMode = mc_ternary(isfield(res,'capMode'), res.capMode, 'peak');

            X = My; Y = Mz;
            Z = repmat(N, 1, size(My,2));
            xLbl='M_y'; yLbl='M_z'; zLbl='N';

            if opts.normalize
                sX=max(abs(X(:))); if sX<=0||~isfinite(sX), sX=1; end
                sY=max(abs(Y(:))); if sY<=0||~isfinite(sY), sY=1; end
                sZ=max(abs(N(:))); if sZ<=0||~isfinite(sZ), sZ=1; end
                X=X/sX; Y=Y/sY; Z=Z/sZ;
                MyCap=MyCap/sX; MzCap=MzCap/sY; N=N/sZ;
                xLbl='M_y/max|M_y|'; yLbl='M_z/max|M_z|'; zLbl='N/max|N|';
            end

            tmpFig = figure('Visible','off');
            cmap   = colormap(tmpFig, opts.colormap);
            close(tmpFig);
            cIdxs  = min(max(round(linspace(1,size(cmap,1),nN)),1),size(cmap,1));
            ttl    = sprintf('N-M_y-M_z Interaction Surface  [%s]', capMode);

            % --- Figure 1: 3-D surface ---
            if opts.showSurface
                figure('Position',[60 60 920 700],'Color','w');
                ax = axes; axs.surface = ax;
                hold(ax,'on');
                surf(ax,X,Y,Z,'FaceAlpha',opts.alpha,'EdgeColor','none','FaceColor','interp');
                colormap(ax,opts.colormap);
                cb=colorbar(ax); cb.Label.String=zLbl;
                for k=1:nN
                    plot3(ax,X(k,:),Y(k,:),Z(k,:),'-','Color',cmap(cIdxs(k),:),'LineWidth',1.2);
                end
                nT=size(X,2); stp=max(1,round(nT/12));
                for iT=1:stp:nT
                    plot3(ax,X(:,iT),Y(:,iT),Z(:,iT),'Color',[0 0 0 0.22],'LineWidth',0.4);
                end
                hold(ax,'off');
                xlabel(ax,xLbl,'FontSize',14); ylabel(ax,yLbl,'FontSize',14);
                zlabel(ax,zLbl,'FontSize',14);
                title(ax,ttl,'FontSize',15,'Interpreter','none');
                grid(ax,'on'); view(ax,-45,30); axis(ax,'tight');
            end

            % --- Figure 2: My-Mz plan view ---
            if opts.showPlanView
                figure('Position',[1000 60 520 520],'Color','w');
                ax2=axes; axs.plan=ax2; hold(ax2,'on');
                for k=1:nN
                    plot(ax2,X(k,:),Y(k,:),'-','Color',cmap(cIdxs(k),:),'LineWidth',1.4);
                end
                xline(ax2,0,':','LineWidth',0.7,'HandleVisibility','off');
                yline(ax2,0,':','LineWidth',0.7,'HandleVisibility','off');
                hold(ax2,'off');
                xlabel(ax2,xLbl,'FontSize',14); ylabel(ax2,yLbl,'FontSize',14);
                title(ax2,sprintf('M_y-M_z Contours  [%s]',capMode), ...
                    'FontSize',14,'Interpreter','none');
                axis(ax2,'equal'); grid(ax2,'on'); box(ax2,'on');
                colormap(ax2,opts.colormap);
                if min(N)~=max(N), clim(ax2,[min(N) max(N)]); end
                cb2=colorbar(ax2); cb2.Label.String=zLbl;
            end

            % --- Figure 3: Uniaxial N-M envelopes ---
            if opts.showEnvelope
                figure('Position',[1000 620 520 380],'Color','w');
                ax3=axes; axs.envelope=ax3;
                plot(ax3,MyCap,N,'b-o','LineWidth',1.5, ...
                    'MarkerFaceColor','b','DisplayName','M_y capacity');
                hold(ax3,'on');
                plot(ax3,MzCap,N,'r-s','LineWidth',1.5, ...
                    'MarkerFaceColor','r','DisplayName','M_z capacity');
                hold(ax3,'off');
                xlabel(ax3,'Moment capacity','FontSize',13);
                ylabel(ax3,zLbl,'FontSize',13);
                title(ax3,sprintf('Uniaxial N-M Envelope  [%s]',capMode), ...
                    'FontSize',14,'Interpreter','none');
                legend(ax3,'Location','best'); grid(ax3,'on'); box(ax3,'on');
            end
        end

    end % methods (Access = public)

    % ------------------------------------------------------------------
    methods (Access = private)

        function mc_requireOps(obj)
            % mc_requireOps  Raise an error if no interpreter is bound.
            if isempty(obj.ops)
                error('MomentCurvature:noOps', ...
                    ['No OpenSees interpreter is bound. ', ...
                     'Use MomentCurvature.create(ops,secTag,P) or ', ...
                     'call setOps(ops) first.']);
            end
        end

        function mc_requireResult(obj)
            % mc_requireResult  Raise an error if analyze() has not been run.
            if isempty(obj.phi) || isempty(obj.M)
                error('MomentCurvature:noResult', ...
                    'No analysis result available. Run analyze() first.');
            end
        end

    end % methods (Access = private)

end % classdef


% ======================================================================
%  File-level private functions (not class members)
% ======================================================================

function mc_validateOps(opsHandle)
% mc_validateOps  Guard against a null or wrong-type interpreter handle.
%
% Parameters
% ----------
% opsHandle : expected to be an OpenSeesMatlabCmds object.
    if isempty(opsHandle)
        error('MomentCurvature:validateOps:empty', ...
            'opsHandle must not be empty.');
    end
    % Check for at least one expected method to catch wrong-type objects.
    if ~(ismethod(opsHandle,'model') && ismethod(opsHandle,'node'))
        error('MomentCurvature:validateOps:wrongType', ...
            ['opsHandle does not look like an OpenSeesMatlabCmds object ', ...
             '(missing model() or node() methods).']);
    end
end


function [PHI, M, RESP] = mc_analyze(ops, secTag, P, axis, maxPhi, incrPhi, ...
                                      stopRatio, cycle, cyclePath, smartAnalyze)
% mc_analyze  Core moment-curvature analysis driver.
%
% Parameters
% ----------
% ops          : OpenSeesMatlabCmds  - OpenSees interpreter handle.
% secTag       : int                 - section tag (defined externally).
% P            : double              - axial load (negative = compression).
% axis         : char                - 'y' (DOF 5) or 'z' (DOF 6).
% maxPhi       : double              - maximum target curvature.
% incrPhi      : double              - base curvature increment.
% stopRatio    : double              - post-peak stop ratio.
% cycle        : logical             - true = follow cyclePath.
% cyclePath    : double array        - curvature targets (cyclic).
% smartAnalyze : logical             - use SmartAnalyze. Default true.
%
% Returns
% -------
% PHI  : double array (nStep,)
% M    : double array (nStep,)
% RESP : double array (nStep, nFiber, 6) or []
%     Returned only when nargout >= 3.
%
% Model assumption
% ----------------
% Materials and the fiber section are defined externally and must exist
% before this function is called.  The function detects whether a model
% (nodes + element) already exists.  If so it resets the domain state and
% removes any load patterns / time series from a prior run while keeping
% nodes, constraints, and the element intact.  If no model exists it
% builds a minimal zeroLengthSection model internally.
%
% SmartAnalyze
% ------------
% When smartAnalyze=true the function uses the SmartAnalyze class located
% in the same directory as this file.  When false a plain
% DisplacementControl loop is used.

    if nargin < 10, smartAnalyze = true; end
    needResp = (nargout >= 3);

    % ------------------------------------------------------------------
    % Model setup: detect existing model; build only when absent.
    % ------------------------------------------------------------------
    existingNodes = ops.getNodeTags();
    hasModel      = ~isempty(existingNodes);

    if hasModel
        % Keep nodes / constraints / element; clear domain state and any
        % load patterns / time series left by a previous analysis run.
        ops.reset();                        % zeroes displacements and state
        ops.remove('timeSeries', 1);
        ops.remove('timeSeries', 2);
        ops.remove('loadPattern', 1);
        ops.remove('loadPattern', 2);
    else
        % No model present: build a minimal one around the fiber section.
        ops.model('basic', '-ndm', 3, '-ndf', 6);
        ops.node(1, 0, 0, 0);
        ops.node(2, 0, 0, 0);
        ops.fix(1, 1, 1, 1, 1, 1, 1);   % fully fixed reference node
        ops.fix(2, 0, 1, 1, 1, 0, 0);   % free: axial (DOF1) + bending (DOF5,6)
        ops.element('zeroLengthSection', 1, 1, 2, secTag);
    end

    % ------------------------------------------------------------------
    % Constant axial load (load-control ramp, 10 equal steps).
    % ------------------------------------------------------------------
    if P ~= 0
        ops.timeSeries('Linear', 1);
        ops.pattern('Plain', 1, 1);
        ops.load(2, P, 0, 0, 0, 0, 0);
        ops.wipeAnalysis();
        ops.system('BandGeneral');
        ops.constraints('Plain');
        ops.numberer('Plain');
        ops.test('NormDispIncr', 1e-10, 10, 3);
        ops.algorithm('Newton');
        ops.integrator('LoadControl', 0.1);
        ops.analysis('Static');
        ops.analyze(10);
        ops.loadConst('-time', 0.0);
    end

    % ------------------------------------------------------------------
    % Unit moment load pattern on the controlled bending DOF.
    % ------------------------------------------------------------------
    dof   = mc_getDOF(axis);
    load6 = zeros(1, 6); load6(dof) = 1.0;
    ops.timeSeries('Linear', 2);
    ops.pattern('Plain', 2, 2);
    ops.load(2, load6(1), load6(2), load6(3), load6(4), load6(5), load6(6));

    % ------------------------------------------------------------------
    % Build displacement-control protocol.
    % ------------------------------------------------------------------
    if cycle && ~isempty(cyclePath)
        maxPhi   = max(abs(cyclePath));
        protocol = mc_buildCycleProtocol(cyclePath, incrPhi);
    else
        nStep    = max(1, round(abs(maxPhi / incrPhi)));
        protocol = repmat(maxPhi / nStep, nStep, 1);
    end
    nProt = numel(protocol);

    % ------------------------------------------------------------------
    % Pre-allocate result arrays to protocol upper bound.
    % ------------------------------------------------------------------
    PHI  = zeros(nProt + 1, 1);
    M    = zeros(nProt + 1, 1);
    if needResp
        fd0  = mc_getFiberData(ops, 1);
        nFib = size(fd0, 1);
        RESP = zeros(nProt + 1, nFib, 6);
    else
        RESP = [];
    end
    ptr   = 1;   % index 1 = initial state (all zeros)
    peakM = 0;

    % ------------------------------------------------------------------
    % Configure static analysis.
    % ------------------------------------------------------------------
    ops.wipeAnalysis();
    ops.system('BandGeneral');
    ops.constraints('Plain');
    ops.numberer('Plain');
    ops.test('EnergyIncr', 1e-10, 100, 3);
    ops.algorithm('Newton');
    ops.integrator('DisplacementControl', 2, dof, protocol(1));
    ops.analysis('Static');

    % ------------------------------------------------------------------
    % Set up SmartAnalyze (same-directory class).
    % ------------------------------------------------------------------
    if smartAnalyze
        sa = analysis.SmartAnalyze();
        sa.setOPS(ops);
        sa.configure( ...
            'analysis',          'Static',      ...
            'testType',          'EnergyIncr',  ...
            'testTol',           1e-10,         ...
            'testIterTimes',     100,           ...
            'tryAlterAlgoTypes', true,          ...
            'algoTypes',         [40, 20],      ...
            'tryRelaxStep',      true,          ...
            'relaxation',        0.5,           ...
            'minStep',           incrPhi / 1e5, ...
            'recordNormHistory', false,         ...
            'debugMode',         false);
    end

    % ------------------------------------------------------------------
    % Main loading loop (write-pointer; no dynamic growth).
    % ------------------------------------------------------------------
    for iStep = 1:nProt
        step = protocol(iStep);

        if smartAnalyze
            ok = sa.staticAnalyze(2, dof, step);
        else
            ops.integrator('DisplacementControl', 2, dof, step);
            ok = ops.analyze(1);
        end

        ptr      = ptr + 1;
        PHI(ptr) = ops.nodeDisp(2, dof);
        M(ptr)   = ops.getLoadFactor(2);
        if needResp, RESP(ptr, :, :) = mc_getFiberData(ops, 1); end

        peakM = max(peakM, abs(M(ptr)));

        % Early termination: post-peak drop or curvature limit.
        if ptr >= 3
            flip  = (M(ptr-1) - M(ptr)) * (PHI(ptr-1) - PHI(ptr)) < 0;
            decay = abs(M(ptr)) <= peakM * stopRatio;
            if (flip && decay) || abs(PHI(ptr)) >= maxPhi, break; end
        end

        if ok < 0
            warning('mc_analyze:nonConvergence', ...
                'Step %d did not converge; analysis terminated early.', iStep);
            break;
        end
    end

    % Truncate to actual step count.
    PHI = PHI(1:ptr);
    M   = M(1:ptr);
    if needResp, RESP = RESP(1:ptr, :, :); end
end


function dof = mc_getDOF(axis)
% mc_getDOF  Map axis name to OpenSees DOF index (5='y', 6='z').
    switch lower(axis)
        case 'y', dof = 5;
        case 'z', dof = 6;
        otherwise
            error('mc_getDOF:unknownAxis','axis must be ''y'' or ''z''.');
    end
end


function protocol = mc_buildCycleProtocol(cyclePath, incrPhi)
% mc_buildCycleProtocol  Discretise cyclic targets into signed increments.
%
% Returns
% -------
% protocol : double array (totalSteps,)
    diffs    = diff(cyclePath(:));
    steps    = max(1, round(abs(diffs / incrPhi)));
    total    = sum(steps);
    protocol = zeros(total, 1);
    ptr = 0;
    for i = 1:numel(diffs)
        ns  = steps(i);
        protocol(ptr+1:ptr+ns) = diffs(i) / ns;
        ptr = ptr + ns;
    end
end


function fd = mc_getFiberData(ops, eleTag)
% mc_getFiberData  Retrieve fiber section data from a zeroLengthSection.
%
% Returns
% -------
% fd : double array (nFibers, 6)
%     Columns: yCoord  zCoord  area  matTag  stress  strain.
%
% Notes
% -----
% FIX-3 (documentation): fiberData2 is a flat vector with 6 values per
% fiber packed consecutively: [y1 z1 A1 mat1 s1 e1  y2 z2 ...].
% reshape(raw,6,[]) groups them into 6-row columns; the transpose gives
% the [nFiber x 6] matrix with one fiber per row.  This is correct for
% MATLAB's column-major memory layout.
    raw = double(ops.eleResponse(eleTag, 'section', 'fiberData2'));
    raw = raw(:);
    if isempty(raw)
        fd = zeros(0,6); return;
    end
    if mod(numel(raw),6) ~= 0
        error('mc_getFiberData:badLength', ...
            'fiberData2 length must be a multiple of 6 (got %d).', numel(raw));
    end
    fd = reshape(raw, 6, []).';   % [nFiber x 6]
end


function [Mcap, idxCap] = mc_extractMomentCapacity( ...
        phi, M, fd, capMode, peakDrop, matTag, threshold, targetPhi)
% mc_extractMomentCapacity  Single authoritative capacity extraction routine.
%
% Shared by getLimitState and buildNMM (FIX-7).
%
% Parameters
% ----------
% phi       : double (nStep,)
% M         : double (nStep,)
% fd        : double (nStep, nFiber, 6) or []
% capMode   : char   - 'peak','peakdrop','strain','curvature'
% peakDrop  : double - drop ratio for 'peakdrop'
% matTag    : scalar/vector
% threshold : scalar/vector
% targetPhi : double
%
% Returns
% -------
% Mcap   : double  - moment at capacity point (signed).
% idxCap : int     - step index (1-based).
%
% Notes
% -----
% FIX-11: idxCap formula is (idxPeak + idxRel - 1) throughout, which is
%         the correct 1-based MATLAB result for a sub-array search starting
%         at idxPeak.

    phi   = phi(:);
    M     = M(:);
    nStep = numel(phi);
    absM  = abs(M);

    switch lower(string(capMode))

        case "peak"
            [~, idxCap] = max(absM);

        case "peakdrop"
            drop = abs(double(peakDrop));
            if ~isscalar(drop) || drop <= 0 || drop >= 1
                error('mc_extractMomentCapacity:badPeakDrop', ...
                    'peakDrop must be a scalar in (0,1).');
            end
            [peakM, idxPeak] = max(absM);
            limitM           = (1 - drop) * peakM;
            idxRel           = find(absM(idxPeak:end) <= limitM, 1, 'first');
            if isempty(idxRel)
                warning('mc_extractMomentCapacity:notReached', ...
                    'Moment has not dropped %.1f%%; last step used.', drop*100);
                idxCap = nStep;
            else
                idxCap = idxPeak + idxRel - 1;   % FIX-11
            end

        case "strain"
            if isempty(fd)
                error('mc_extractMomentCapacity:noFd', ...
                    'FiberData required for capacityMode="strain".');
            end
            matTags = matTag(:);
            thrs    = threshold(:);
            if isscalar(thrs) && numel(matTags) > 1
                thrs = repmat(thrs, numel(matTags), 1);
            end
            if numel(matTags) ~= numel(thrs)
                error('mc_extractMomentCapacity:lengthMismatch', ...
                    'matTag and threshold must have the same length.');
            end
            % FIX-9 applied here: use last-step row for matID.
            matIDrow  = squeeze(fd(end,:,4));
            strainAll = squeeze(fd(:,:,6));
            if isvector(strainAll)
                strainAll = reshape(strainAll, nStep, []);
            end
            idxList = zeros(numel(matTags),1);
            for k = 1:numel(matTags)
                idxF = abs(matIDrow - matTags(k)) < 1e-6;
                if ~any(idxF)
                    warning('mc_extractMomentCapacity:matNotFound', ...
                        'matTag %g not found; last step used.', matTags(k));
                    idxList(k) = nStep; continue;
                end
                sub = strainAll(:, idxF);
                eu  = thrs(k);
                if eu >= 0
                    env = max(sub,[],2);  idxRel = find(env >= eu, 1);
                else
                    env = min(sub,[],2);  idxRel = find(env <= eu, 1);
                end
                if isempty(idxRel)
                    warning('mc_extractMomentCapacity:strainNotReached', ...
                        'matTag %g strain %.3g not reached; last step used.', ...
                        matTags(k), thrs(k));
                    idxList(k) = nStep;
                else
                    idxList(k) = idxRel;  % find() returns 1-based index directly
                end
            end
            idxCap = min(idxList);

        case "curvature"
            if isnan(targetPhi) || targetPhi == 0
                error('mc_extractMomentCapacity:badTargetPhi', ...
                    'targetPhi must be nonzero for capacityMode="curvature".');
            end
            [~, idxCap] = min(abs(phi - targetPhi));

        otherwise
            error('mc_extractMomentCapacity:unknownMode', ...
                'Unknown capacityMode: %s.', capMode);
    end

    idxCap = min(max(1, idxCap), nStep);
    Mcap   = M(idxCap);
end


function v = mc_ternary(cond, a, b)
% mc_ternary  Inline conditional.
    if cond, v = a; else, v = b; end
end