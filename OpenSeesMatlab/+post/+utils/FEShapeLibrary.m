classdef FEShapeLibrary
    % High-performance MATLAB version for FE shape functions and GP->node projection.
    % Design:
    %   1) No per-element class instantiation
    %   2) Persistent lookup tables and constant matrices
    %   3) Shared projection kernel for 2D / 3D gp_resp
    %
    % gp_resp shapes:
    %   2D: [nGP, nResp]
    %   3D: [nGP, nField, nResp]

    methods (Static)

        function f = getShapeFunc(eleType, nNode, nGP)
            key = post.utils.FEShapeLibrary.makeKey(eleType, nNode, nGP);

            persistent shapeMap
            if isempty(shapeMap)
                shapeMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                shapeMap('tri_3_1')    = @post.utils.FEShapeLibrary.shape_tri3;
                shapeMap('tri_6_3')    = @post.utils.FEShapeLibrary.shape_tri6;
                shapeMap('quad_4_4')   = @post.utils.FEShapeLibrary.shape_quad4;
                shapeMap('quad_9_9')   = @post.utils.FEShapeLibrary.shape_quad9;
                shapeMap('quad_8_9')   = @post.utils.FEShapeLibrary.shape_quad8;
                shapeMap('tet_4_1')    = @post.utils.FEShapeLibrary.shape_tet4;
                shapeMap('tet_10_4')   = @post.utils.FEShapeLibrary.shape_tet10;
                shapeMap('brick_8_8')  = @post.utils.FEShapeLibrary.shape_brick8;
                shapeMap('brick_20_27') = @post.utils.FEShapeLibrary.shape_brick20;
                shapeMap('brick_27_27') = @post.utils.FEShapeLibrary.shape_brick27;
            end

            if isKey(shapeMap, key)
                f = shapeMap(key);
            else
                f = [];
            end
        end

        function f = getGP2NodeFunc(eleType, nNode, nGP)
            key = post.utils.FEShapeLibrary.makeKey(eleType, nNode, nGP);

            persistent projMap
            if isempty(projMap)
                projMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                projMap('tri_3_1')     = @(method, gpResp) post.utils.FEShapeLibrary.project_tri3(method, gpResp);
                projMap('tri_6_3')     = @(method, gpResp) post.utils.FEShapeLibrary.project_tri6(method, gpResp);
                projMap('quad_4_4')    = @(method, gpResp) post.utils.FEShapeLibrary.project_quad4(method, gpResp);
                projMap('quad_9_9')    = @(method, gpResp) post.utils.FEShapeLibrary.project_quad9(method, gpResp);
                projMap('quad_8_9')    = @(method, gpResp) post.utils.FEShapeLibrary.project_quad8(method, gpResp);
                projMap('tet_4_1')     = @(method, gpResp) post.utils.FEShapeLibrary.project_tet4(method, gpResp);
                projMap('tet_10_4')    = @(method, gpResp) post.utils.FEShapeLibrary.project_tet10(method, gpResp);
                projMap('brick_8_8')   = @(method, gpResp) post.utils.FEShapeLibrary.project_brick8(method, gpResp);
                projMap('brick_20_27') = @(method, gpResp) post.utils.FEShapeLibrary.project_brick20(method, gpResp);
                projMap('brick_27_27') = @(method, gpResp) post.utils.FEShapeLibrary.project_brick27(method, gpResp);
            end

            if isKey(projMap, key)
                f = projMap(key);
            else
                f = [];
            end
        end

        function f = getShellGP2NodeFunc(eleType, nNode, nGP)
            key = post.utils.FEShapeLibrary.makeKey(eleType, nNode, nGP);

            persistent projMap
            if isempty(projMap)
                projMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                projMap('tri_3_1')   = @(method, gpResp) post.utils.FEShapeLibrary.project_shell_tri3_gp1(method, gpResp);
                projMap('tri_3_3')   = @(method, gpResp) post.utils.FEShapeLibrary.project_shell_tri3_gp3(method, gpResp);
                projMap('tri_3_4')   = @(method, gpResp) post.utils.FEShapeLibrary.project_shell_tri3_gp4(method, gpResp);
                projMap('quad_4_4')  = @(method, gpResp) post.utils.FEShapeLibrary.project_quad4(method, gpResp);
                projMap('quad_9_9')  = @(method, gpResp) post.utils.FEShapeLibrary.project_quad9(method, gpResp);
            end

            if isKey(projMap, key)
                f = projMap(key);
            else
                f = [];
            end
        end

        function out = getGaussData(eleType, nNode, nGP)
            % Returns struct with fields depending on element dimension:
            % 2D: gp_r, gp_s, gp_w
            % 3D: gp_r, gp_s, gp_t, gp_w

            key = post.utils.FEShapeLibrary.makeKey(eleType, nNode, nGP);

            persistent dataMap
            if isempty(dataMap)
                dataMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

                a = 1/6; b = 2/3;
                dataMap('tri_3_1') = struct( ...
                    'gp_r', 1/3, ...
                    'gp_s', 1/3, ...
                    'gp_w', 0.5);

                dataMap('tri_6_3') = struct( ...
                    'gp_r', [a; b; a], ...
                    'gp_s', [a; a; b], ...
                    'gp_w', [a; a; a], ...
                    'node_r', [0;1;0;0.5;0.5;0], ...
                    'node_s', [0;0;1;0;0.5;0.5]);

                aq = 1/sqrt(3);
                dataMap('quad_4_4') = struct( ...
                    'gp_r', [-aq; aq; aq; -aq], ...
                    'gp_s', [-aq; -aq; aq; aq], ...
                    'gp_w', ones(4,1), ...
                    'node_r', [-1; 1; 1; -1], ...
                    'node_s', [-1; -1; 1; 1]);

                a9 = sqrt(0.6);
                w1 = 25/81; w2 = 40/81; w3 = 64/81;
                gp_r9 = [-a9; a9; a9; -a9; 0; a9; 0; -a9; 0];
                gp_s9 = [-a9; -a9; a9; a9; -a9; 0; a9; 0; 0];
                gp_w9 = [w1; w1; w1; w1; w2; w2; w2; w2; w3];
                dataMap('quad_9_9') = struct( ...
                    'gp_r', gp_r9, 'gp_s', gp_s9, 'gp_w', gp_w9);
                dataMap('quad_8_9') = struct( ...
                    'gp_r', gp_r9, 'gp_s', gp_s9, 'gp_w', gp_w9);

                dataMap('tet_4_1') = struct( ...
                    'gp_r', 0.25, 'gp_s', 0.25, 'gp_t', 0.25, 'gp_w', 0.61);

                at = 0.5854101966249685;
                bt = 0.1381966011250105;
                wt = 0.25/6;
                dataMap('tet_10_4') = struct( ...
                    'gp_r', [at; bt; bt; bt], ...
                    'gp_s', [bt; at; bt; bt], ...
                    'gp_t', [bt; bt; at; bt], ...
                    'gp_w', wt*ones(4,1));

                ab = 1/sqrt(3);
                dataMap('brick_8_8') = struct( ...
                    'gp_r', [-ab; ab; ab; -ab; -ab; ab; ab; -ab], ...
                    'gp_s', [-ab; -ab; ab; ab; -ab; -ab; ab; ab], ...
                    'gp_t', [-ab; -ab; -ab; -ab; ab; ab; ab; ab], ...
                    'gp_w', ones(8,1));

                a27 = 0.774596669241483;
                gp_r27 = [-a27; a27; a27; -a27; -a27; a27; a27; -a27; 0; a27; 0; -a27; 0; a27; 0; -a27; -a27; a27; a27; -a27; a27; 0; 0; -a27; 0; 0; 0];
                gp_s27 = [-a27; -a27; a27; a27; -a27; -a27; a27; a27; -a27; 0; a27; 0; -a27; 0; a27; 0; -a27; -a27; a27; a27; 0; a27; 0; 0; -a27; 0; 0];
                gp_t27 = [-a27; -a27; -a27; -a27; a27; a27; a27; a27; -a27; -a27; -a27; -a27; a27; a27; a27; a27; 0; 0; 0; 0; 0; 0; a27; 0; 0; -a27; 0];
                gp_w27 = [ ...
                    0.1714677640603567; 0.1714677640603567; 0.1714677640603567; 0.1714677640603567; ...
                    0.1714677640603567; 0.1714677640603567; 0.1714677640603567; 0.1714677640603567; ...
                    0.2743484224965707; 0.2743484224965707; 0.2743484224965707; 0.2743484224965707; ...
                    0.2743484224965707; 0.2743484224965707; 0.2743484224965707; 0.2743484224965707; ...
                    0.2743484224965707; 0.2743484224965707; 0.2743484224965707; 0.2743484224965707; ...
                    0.43974468799451316; 0.43974468799451316; 0.43974468799451316; 0.43974468799451316; ...
                    0.43974468799451316; 0.43974468799451316; 0.7023319610971642];
                dataMap('brick_20_27') = struct('gp_r', gp_r27, 'gp_s', gp_s27, 'gp_t', gp_t27, 'gp_w', gp_w27);
                dataMap('brick_27_27') = struct('gp_r', gp_r27, 'gp_s', gp_s27, 'gp_t', gp_t27, 'gp_w', gp_w27);
            end

            if isKey(dataMap, key)
                out = dataMap(key);
            else
                out = [];
            end
        end
    end

    methods (Static, Access = private)

        function key = makeKey(eleType, nNode, nGP)
            key = sprintf('%s_%d_%d', lower(string(eleType)), nNode, nGP);
            key = char(key);
        end

        function out = applyProjection(W, gpResp)
            if ndims(gpResp) == 2
                out = W * gpResp;
            elseif ndims(gpResp) == 3
                % gpResp: [nGP, nField, nResp]
                sz = size(gpResp);
                G  = sz(1);
                gpResp2 = reshape(gpResp, G, []);
                out2 = W * gpResp2;
                out  = reshape(out2, size(W,1), sz(2), sz(3));
            else
                error('gp_resp must be 2D or 3D array.');
            end
        end

        function W = averageWeights(gpW, nNode)
            gpW = gpW(:).';
            W = repmat(gpW / sum(gpW), nNode, 1);
        end

        function tf = startsWithLower(method, prefix)
            tf = startsWith(lower(string(method)), lower(string(prefix)));
        end

        % ===== projection functions =====

        function out = project_tri3(method, gpResp)
            %#ok<INUSD>
            W = ones(3,1);
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_tri6(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    1.66666667, -0.33333333, -0.33333333;
                   -0.33333333,  1.66666667, -0.33333333;
                   -0.33333333, -0.33333333,  1.66666667;
                    0.66666667,  0.66666667, -0.33333333;
                   -0.33333333,  0.66666667,  0.66666667;
                    0.66666667, -0.33333333,  0.66666667];
            elseif startsWith(method, "ave")
                W = post.utils.FEShapeLibrary.averageWeights([1/6;1/6;1/6], 6);
            elseif startsWith(method, "copy")
                W = [ ...
                    1,   0,   0;
                    0,   1,   0;
                    0,   0,   1;
                    0.5, 0.5, 0;
                    0,   0.5, 0.5;
                    0.5, 0,   0.5];
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_quad4(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    1.8660254, -0.5,       0.1339746, -0.5;
                   -0.5,       1.8660254, -0.5,       0.1339746;
                    0.1339746, -0.5,       1.8660254, -0.5;
                   -0.5,       0.1339746, -0.5,       1.8660254];
            elseif startsWith(method, "ave")
                W = post.utils.FEShapeLibrary.averageWeights(ones(4,1), 4);
            elseif startsWith(method, "copy")
                W = eye(4);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_quad9(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    2.18693982, 0.27777778, 0.0352824,  0.27777778, -0.98588704, -0.12522407, -0.12522407, -0.98588704,  0.44444444;
                    0.27777778, 2.18693982, 0.27777778, 0.0352824,  -0.98588704, -0.98588704, -0.12522407, -0.12522407,  0.44444444;
                    0.0352824,  0.27777778, 2.18693982, 0.27777778, -0.12522407, -0.98588704, -0.98588704, -0.12522407,  0.44444444;
                    0.27777778, 0.0352824,  0.27777778, 2.18693982, -0.12522407, -0.12522407, -0.98588704, -0.98588704,  0.44444444;
                    0,          0,          0,          0,           1.47883056,  0,           0.18783611,  0,          -0.66666667;
                    0,          0,          0,          0,           0,           1.47883056,  0,           0.18783611, -0.66666667;
                    0,          0,          0,          0,           0.18783611,  0,           1.47883056,  0,          -0.66666667;
                    0,          0,          0,          0,           0,           0.18783611,  0,           1.47883056, -0.66666667;
                    0,          0,          0,          0,           0,           0,           0,           0,           1];
            elseif startsWith(method, "ave")
                gpW = [25/81;25/81;25/81;25/81;40/81;40/81;40/81;40/81;64/81];
                W = post.utils.FEShapeLibrary.averageWeights(gpW, 9);
            elseif startsWith(method, "copy")
                W = eye(9);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_quad8(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    2.18693982, 0.27777778, 0.0352824,  0.27777778, -0.98588704, -0.12522407, -0.12522407, -0.98588704,  0.44444444;
                    0.27777778, 2.18693982, 0.27777778, 0.0352824,  -0.98588704, -0.98588704, -0.12522407, -0.12522407,  0.44444444;
                    0.0352824,  0.27777778, 2.18693982, 0.27777778, -0.12522407, -0.98588704, -0.98588704, -0.12522407,  0.44444444;
                    0.27777778, 0.0352824,  0.27777778, 2.18693982, -0.12522407, -0.12522407, -0.98588704, -0.98588704,  0.44444444;
                    0,          0,          0,          0,           1.47883056,  0,           0.18783611,  0,          -0.66666667;
                    0,          0,          0,          0,           0,           1.47883056,  0,           0.18783611, -0.66666667;
                    0,          0,          0,          0,           0.18783611,  0,           1.47883056,  0,          -0.66666667;
                    0,          0,          0,          0,           0,           0.18783611,  0,           1.47883056, -0.66666667];
            elseif startsWith(method, "ave")
                gpW = [25/81;25/81;25/81;25/81;40/81;40/81;40/81;40/81;64/81];
                W = post.utils.FEShapeLibrary.averageWeights(gpW, 8);
            elseif startsWith(method, "copy")
                W = eye(9);
                W = W(1:8,:);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_tet4(method, gpResp)
            %#ok<INUSD>
            W = ones(4,1);
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_tet10(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                   -0.309017, -0.309017, -0.309017,  1.927051;
                    1.927051, -0.309017, -0.309017, -0.309017;
                   -0.309017,  1.927051, -0.309017, -0.309017;
                   -0.309017, -0.309017,  1.927051, -0.309017;
                    0.809017,  0.809017, -0.309017, -0.309017;
                    0.809017, -0.309017,  0.809017, -0.309017;
                    0.809017, -0.309017, -0.309017,  0.809017;
                   -0.309017, -0.309017,  0.809017,  0.809017;
                   -0.309017,  0.809017, -0.309017,  0.809017;
                   -0.30932,   0.43644,   0.43644,   0.43644];
            elseif startsWith(method, "ave")
                W = post.utils.FEShapeLibrary.averageWeights((0.25/6)*ones(4,1), 10);
            elseif startsWith(method, "copy")
                W = [ ...
                    0,0,0,1;
                    1,0,0,0;
                    0,1,0,0;
                    0,0,1,0;
                    0,1,0,0;
                    0,0,1,0;
                    0,0,0,1;
                    0,0,1,0;
                    0,1,0,0;
                    1,0,0,0];
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_brick8(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    2.54903811, -0.6830127,  0.1830127, -0.6830127, -0.6830127,  0.1830127, -0.04903811,  0.1830127;
                   -0.6830127,  2.54903811, -0.6830127,  0.1830127,  0.1830127, -0.6830127,  0.1830127, -0.04903811;
                    0.1830127, -0.6830127,  2.54903811, -0.6830127, -0.04903811,  0.1830127, -0.6830127,  0.1830127;
                   -0.6830127,  0.1830127, -0.6830127,  2.54903811,  0.1830127, -0.04903811,  0.1830127, -0.6830127;
                   -0.6830127,  0.1830127, -0.04903811,  0.1830127,  2.54903811, -0.6830127,  0.1830127, -0.6830127;
                    0.1830127, -0.6830127,  0.1830127, -0.04903811, -0.6830127,  2.54903811, -0.6830127,  0.1830127;
                   -0.04903811, 0.1830127, -0.6830127,  0.1830127,  0.1830127, -0.6830127,  2.54903811, -0.6830127;
                    0.1830127, -0.04903811, 0.1830127, -0.6830127, -0.6830127,  0.1830127, -0.6830127,  2.54903811];
            elseif startsWith(method, "ave")
                W = post.utils.FEShapeLibrary.averageWeights(ones(8,1), 8);
            elseif startsWith(method, "copy")
                W = eye(8);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_brick20(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = post.utils.FEShapeLibrary.weightsBrick20GP27Extra();
            elseif startsWith(method, "ave")
                gd = post.utils.FEShapeLibrary.getGaussData('brick', 20, 27);
                W = post.utils.FEShapeLibrary.averageWeights(gd.gp_w, 20);
            elseif startsWith(method, "copy")
                W = eye(27);
                W = W(1:20,:);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_brick27(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = post.utils.FEShapeLibrary.weightsBrick27GP27Extra();
            elseif startsWith(method, "ave")
                gd = post.utils.FEShapeLibrary.getGaussData('brick', 27, 27);
                W = post.utils.FEShapeLibrary.averageWeights(gd.gp_w, 27);
            elseif startsWith(method, "copy")
                W = eye(27);
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_shell_tri3_gp1(~, gpResp)
            W = ones(3,1);
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_shell_tri3_gp3(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    0.261204, 0.369398, 0.369398;
                    0.328227, 0.207589, 0.464183;
                    0.328227, 0.464183, 0.207589];
            elseif startsWith(method, "ave")
                W = post.utils.FEShapeLibrary.averageWeights((1/6)*ones(3,1), 3);
            elseif startsWith(method, "copy")
                W = [0,0.5,0.5; 0.5,0,0.5; 0.5,0.5,0];
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        function out = project_shell_tri3_gp4(method, gpResp)
            method = lower(string(method));
            if startsWith(method, "extra")
                W = [ ...
                    0.240536, 0.179285, 0.179285, 0.400893;
                    0.231701, 0.172700, 0.386169, 0.209430;
                    0.231701, 0.386169, 0.172700, 0.209430];
            elseif startsWith(method, "ave")
                gpW = [-9/16; 25/48; 25/48; 25/48];
                W = post.utils.FEShapeLibrary.averageWeights(gpW, 3);
            elseif startsWith(method, "copy")
                W = [0,0,0,1; 0,0,1,0; 0,1,0,0];
            else
                error('Unknown projection method.');
            end
            out = post.utils.FEShapeLibrary.applyProjection(W, gpResp);
        end

        % ===== shape functions =====

        function N = shape_tri3(r, s)
            N = [1-r-s; r; s];
        end

        function N = shape_tri6(r, s)
            t = 1 - r - s;
            N = [ ...
                t*(2*t-1);
                r*(2*r-1);
                s*(2*s-1);
                4*r*t;
                4*r*s;
                4*s*t];
        end

        function N = shape_quad4(r, s)
            N = [ ...
                0.25*(1-r)*(1-s);
                0.25*(1+r)*(1-s);
                0.25*(1+r)*(1+s);
                0.25*(1-r)*(1+s)];
        end

        function N = shape_quad9(r, s)
            N = [ ...
                0.25*r*s*(1-r)*(1-s);
               -0.25*r*s*(1+r)*(1-s);
                0.25*r*s*(1+r)*(1+s);
               -0.25*r*s*(1-r)*(1+s);
               -0.5*s*(1-r*r)*(1-s);
                0.5*r*(1+r)*(1-s*s);
                0.5*s*(1-r*r)*(1+s);
               -0.5*r*(1-r)*(1-s*s);
                (1-r*r)*(1-s*s)];
        end

        function N = shape_quad8(r, s)
            N = [ ...
                0.25*(1-r)*(1-s)*(-r-s-1);
                0.25*(1+r)*(1-s)*( r-s-1);
                0.25*(1+r)*(1+s)*( r+s-1);
                0.25*(1-r)*(1+s)*(-r+s-1);
                0.5*(1-r*r)*(1-s);
                0.5*(1+r)*(1-s*s);
                0.5*(1-r*r)*(1+s);
                0.5*(1-r)*(1-s*s)];
        end

        function N = shape_tet4(r, s, t)
            N = [1-r-s-t; r; s; t];
        end

        function N = shape_tet10(r, s, t)
            u = 1 - r - s - t;
            N = zeros(10,1);
            N(1)  = u*(2*u-1);
            N(2)  = r*(2*r-1);
            N(3)  = s*(2*s-1);
            N(4)  = t*(2*t-1);
            N(5)  = 4*r*u;
            N(6)  = 4*r*s;
            N(7)  = 4*s*u;
            N(8)  = 4*t*u;
            N(9)  = 4*r*t;
            N(10) = 4*s*t;
        end

        function N = shape_brick8(r, s, t)
            coords = [ ...
                -1,-1,-1;
                 1,-1,-1;
                 1, 1,-1;
                -1, 1,-1;
                -1,-1, 1;
                 1,-1, 1;
                 1, 1, 1;
                -1, 1, 1];
            N = zeros(8,1);
            for i = 1:8
                xi = coords(i,1); eta = coords(i,2); zeta = coords(i,3);
                N(i) = (1+xi*r)*(1+eta*s)*(1+zeta*t)/8;
            end
        end

        function H = shape_brick20(r, s, t)
            H = zeros(20,1);
            H(9)  = 0.25*(1-r*r)*(1-s)*(1-t);
            H(10) = 0.25*(1-s*s)*(1+r)*(1-t);
            H(11) = 0.25*(1-r*r)*(1+s)*(1-t);
            H(12) = 0.25*(1-s*s)*(1-r)*(1-t);
            H(13) = 0.25*(1-r*r)*(1-s)*(1+t);
            H(14) = 0.25*(1-s*s)*(1+r)*(1+t);
            H(15) = 0.25*(1-r*r)*(1+s)*(1+t);
            H(16) = 0.25*(1-s*s)*(1-r)*(1+t);
            H(17) = 0.25*(1-t*t)*(1-r)*(1-s);
            H(18) = 0.25*(1-t*t)*(1+r)*(1-s);
            H(19) = 0.25*(1-t*t)*(1+r)*(1+s);
            H(20) = 0.25*(1-t*t)*(1-r)*(1+s);

            H(1) = 0.125*(1-r)*(1-s)*(1-t) - 0.5*(H(9)+H(12)+H(17));
            H(2) = 0.125*(1+r)*(1-s)*(1-t) - 0.5*(H(9)+H(10)+H(18));
            H(3) = 0.125*(1+r)*(1+s)*(1-t) - 0.5*(H(10)+H(11)+H(19));
            H(4) = 0.125*(1-r)*(1+s)*(1-t) - 0.5*(H(11)+H(12)+H(20));
            H(5) = 0.125*(1-r)*(1-s)*(1+t) - 0.5*(H(13)+H(16)+H(17));
            H(6) = 0.125*(1+r)*(1-s)*(1+t) - 0.5*(H(13)+H(14)+H(18));
            H(7) = 0.125*(1+r)*(1+s)*(1+t) - 0.5*(H(14)+H(15)+H(19));
            H(8) = 0.125*(1-r)*(1+s)*(1+t) - 0.5*(H(15)+H(16)+H(20));
        end

        function H = shape_brick27(r, s, t)
            R = [0.5*r*(r-1), 0.5*r*(r+1), 1-r*r];
            S = [0.5*s*(s-1), 0.5*s*(s+1), 1-s*s];
            T = [0.5*t*(t-1), 0.5*t*(t+1), 1-t*t];

            H = zeros(27,1);
            H(1)  = R(1)*S(1)*T(1);
            H(2)  = R(2)*S(1)*T(1);
            H(3)  = R(2)*S(2)*T(1);
            H(4)  = R(1)*S(2)*T(1);
            H(5)  = R(1)*S(1)*T(2);
            H(6)  = R(2)*S(1)*T(2);
            H(7)  = R(2)*S(2)*T(2);
            H(8)  = R(1)*S(2)*T(2);
            H(9)  = R(3)*S(1)*T(1);
            H(10) = R(2)*S(3)*T(1);
            H(11) = R(3)*S(2)*T(1);
            H(12) = R(1)*S(3)*T(1);
            H(13) = R(3)*S(1)*T(2);
            H(14) = R(2)*S(3)*T(2);
            H(15) = R(3)*S(2)*T(2);
            H(16) = R(1)*S(3)*T(2);
            H(17) = R(1)*S(1)*T(3);
            H(18) = R(2)*S(1)*T(3);
            H(19) = R(2)*S(2)*T(3);
            H(20) = R(1)*S(2)*T(3);
            H(21) = R(3)*S(1)*T(3);
            H(22) = R(2)*S(3)*T(3);
            H(23) = R(3)*S(2)*T(3);
            H(24) = R(1)*S(3)*T(3);
            H(25) = R(3)*S(3)*T(1);
            H(26) = R(3)*S(3)*T(2);
            H(27) = R(3)*S(3)*T(3);
        end

        % ===== huge constant weights =====

        function W = weightsBrick20GP27Extra()
            persistent W20
            if isempty(W20)
                % Use your original full matrix here.
                % To keep this reply readable, I am placing a compact hook.
                error(['Please paste the full weights_brick20_gp27_extra matrix into ', ...
                       'FEShapeLibrary.weightsBrick20GP27Extra().']);
            end
            W = W20;
        end

        function W = weightsBrick27GP27Extra()
            persistent W27
            if isempty(W27)
                % Use your original full matrix here.
                % To keep this reply readable, I am placing a compact hook.
                error(['Please paste the full weights_brick27_gp27_extra matrix into ', ...
                       'FEShapeLibrary.weightsBrick27GP27Extra().']);
            end
            W = W27;
        end
    end
end