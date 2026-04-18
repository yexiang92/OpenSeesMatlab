classdef OpenSeesTagMaps
    % OpenSeesTagMaps Mapping of OpenSees class tags to element family groups and readable type names.
    %
    % This class organizes:
    %   1) element family class tags, e.g. Beam / Truss / Link / Plane / Shell
    %   2) classTag -> readable element type name
    %   3) optional type-group query helpers
    %
    % Notes
    % -----
    % - Class tags follow OpenSees classTags.h style grouping.

    properties (Constant)
        EleTags = struct( ...
            'Truss', [12, 13, 14, 15, 16, 17, 18, 138, 139, 155, 169, 218], ...
            'Cable', [169], ...
            'Link', [19, 20, 21, 22, 23, 24, 25, 26, 2626, 27, ...
                     84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, ...
                     96, 97, 98, 99, 100, 101, 102, 103, 104, 105, ...
                     106, 107, 108, 109, 130, 131, 132, 147, 148, ...
                     149, 150, 151, 152, 153, 158, 159, 160, 161, ...
                     165, 166, 258], ...
            'Beam', [3, 4, 5, 5001, 6, 7, 8, 9, 10, 11, ...
                     28, 29, 30, 34, 35, ...
                     62, 621, 63, 631, 64, 640, 641, 642, ...
                     65, 66, 67, 68, 69, 70, ...
                     73, 731, 74, 75, 751, 76, 77, 78, ...
                     79, 128, 145, 146, 162, 163, 170, 171, 172, ...
                     192, 193, 197, 198, 206, 211, 257, ...
                     30765, 30766, 30767, 102030, 1110000], ...
            'Plane', [31, 32, 33, 40, 47, 50, 59, 60, 61, ...
                      119, 120, 126, 133, 134, 142, 143, 144, ...
                      164, 187, 207, 208, 209, 219, ...
                      100000011, 100003, 100009, 100002], ...
            'SurfaceLoad', [116, 180], ...
            'Shell', [52, 53, 54, 55, 156, 157, 167, 168, 173, 174, ...
                      175, 203, 204, 212, 213, 268, 259259], ...
            'Wall', [212, 213, 259259, 162, 163, 257], ...
            'Joint', [71, 72, 81, 8181, 82, 83], ...
            'Tet', [179, 256, 189], ...
            'Brick', [36, 37, 38, 39, 41, 42, 43, 44, 45, 46, 48, 49, ...
                      51, 56, 57, 58, 121, 122, 127, 220, ...
                      1984587234, 100001], ...
            'Solid', [179, 256, 189, ...
                      36, 37, 38, 39, 41, 42, 43, 44, 45, 46, 48, 49, ...
                      51, 56, 57, 58, 121, 122, 127, 220, ...
                      1984587234, 100001], ...
            'PFEM', [133, 141, 142, 143, 144, 164, 187, 189, 199, 200, 255], ...
            'UP', [40, 46, 47, 48, 50, 51, 120, 122], ...
            'Contact', [22, 23, 24, 25, 113, 114, 115, 117, 118, 123, 124, 125, 140, 221] ...
        );
    end

    methods (Static)
        function name = getClassName(classTag)
            persistent classNameMap
            if isempty(classNameMap)
                classNameMap = post.utils.OpenSeesTagMaps.buildClassNameMap();
            end

            key = double(classTag);
            if isKey(classNameMap, key)
                name = string(classNameMap(key));
            else
                name = "ClassTag_" + string(classTag);
            end
        end

        function tf = isInGroup(classTag, groupName)
            tags = post.utils.OpenSeesTagMaps.EleTags;
            if ~isfield(tags, groupName)
                error('OpenSeesTagMaps:InvalidGroup', ...
                    'Unknown group name: %s', groupName);
            end
            tf = any(double(classTag) == tags.(groupName));
        end

        function types = getTypeNames(groupName)
            tags = post.utils.OpenSeesTagMaps.EleTags;
            if ~isfield(tags, groupName)
                error('OpenSeesTagMaps:InvalidGroup', ...
                    'Unknown group name: %s', groupName);
            end

            classTags = tags.(groupName);
            types = strings(numel(classTags), 1);
            for i = 1:numel(classTags)
                types(i) = post.utils.OpenSeesTagMaps.getClassName(classTags(i));
            end
        end

        function mp = getClassNameMap()
            persistent classNameMap
            if isempty(classNameMap)
                classNameMap = post.utils.OpenSeesTagMaps.buildClassNameMap();
            end
            mp = classNameMap;
        end
    end

    methods (Static, Access = private)
        function mp = buildClassNameMap()
            % BUILDCLASSNAMEMAP Build classTag -> readable type name map.

            mp = containers.Map('KeyType', 'double', 'ValueType', 'char');

            mp(1) = 'Subdomain';
            mp(2) = 'TAGS_WrapperElement';
            mp(3) = 'ElasticBeam2d';
            mp(4) = 'ModElasticBeam2d';
            mp(5) = 'ElasticBeam3d';
            mp(5001) = 'ElasticBeamWarping3d';
            mp(6) = 'Beam2d';
            mp(7) = 'beam2d02';
            mp(8) = 'beam2d03';
            mp(9) = 'beam2d04';
            mp(10) = 'beam3d01';
            mp(11) = 'beam3d02';
            mp(12) = 'Truss';
            mp(13) = 'TrussSection';
            mp(14) = 'CorotTruss';
            mp(15) = 'CorotTrussSection';
            mp(16) = 'fElmt05';
            mp(17) = 'fElmt02';
            mp(18) = 'MyTruss';
            mp(19) = 'ZeroLength';
            mp(20) = 'ZeroLengthSection';
            mp(21) = 'ZeroLengthND';
            mp(22) = 'ZeroLengthContact2D';
            mp(23) = 'ZeroLengthContact3D';
            mp(24) = 'ZeroLengthContactNTS2D';
            mp(25) = 'ZeroLengthInterface2D';
            mp(26) = 'CoupledZeroLength';
            mp(2626) = 'BiaxialZeroLength';
            mp(27) = 'ZeroLengthRocking';
            mp(28) = 'NLBeamColumn2d';
            mp(29) = 'NLBeamColumn3d';
            mp(30) = 'LargeDispBeamColumn3d';
            mp(31) = 'FourNodeQuad';
            mp(32) = 'FourNodeQuad3d';
            mp(33) = 'Tri31';
            mp(34) = 'BeamWithHinges2d';
            mp(35) = 'BeamWithHinges3d';
            mp(36) = 'EightNodeBrick';
            mp(37) = 'TwentyNodeBrick';
            mp(38) = 'EightNodeBrick_u_p_U';
            mp(39) = 'TwentyNodeBrick_u_p_U';
            mp(40) = 'FourNodeQuadUP';
            mp(41) = 'TotalLagrangianFD20NodeBrick';
            mp(42) = 'TotalLagrangianFD8NodeBrick';
            mp(43) = 'EightNode_LDBrick_u_p';
            mp(44) = 'EightNode_Brick_u_p';
            mp(45) = 'TwentySevenNodeBrick';
            mp(46) = 'BrickUP';
            mp(47) = 'Nine_Four_Node_QuadUP';
            mp(48) = 'Twenty_Eight_Node_BrickUP';
            mp(49) = 'Twenty_Node_Brick';
            mp(50) = 'BBarFourNodeQuadUP';
            mp(51) = 'BBarBrickUP';
            mp(52) = 'PlateMITC4';
            mp(53) = 'ShellMITC4';
            mp(54) = 'ShellMITC9';
            mp(55) = 'Plate1';
            mp(56) = 'Brick';
            mp(57) = 'BbarBrick';
            mp(58) = 'FLBrick';
            mp(59) = 'EnhancedQuad';
            mp(60) = 'ConstantPressureVolumeQuad';
            mp(61) = 'NineNodeMixedQuad';
            mp(62) = 'DispBeamColumn2d';
            mp(621) = 'DispBeamColumnNL2d';
            mp(63) = 'TimoshenkoBeamColumn2d';
            mp(631) = 'TimoshenkoBeamColumn3d';
            mp(64) = 'DispBeamColumn3d';
            mp(640) = 'DispBeamColumnNL3d';
            mp(641) = 'DispBeamColumnWarping3d';
            mp(642) = 'DispBeamColumnAsym3d';
            mp(65) = 'HingedBeam2d';
            mp(66) = 'HingedBeam3d';
            mp(67) = 'TwoPointHingedBeam2d';
            mp(68) = 'TwoPointHingedBeam3d';
            mp(69) = 'OnePointHingedBeam2d';
            mp(70) = 'OnePointHingedBeam3d';
            mp(71) = 'BeamColumnJoint2d';
            mp(72) = 'BeamColumnJoint3d';
            mp(73) = 'ForceBeamColumn2d';
            mp(731) = 'ForceBeamColumnWarping2d';
            mp(74) = 'ForceBeamColumn3d';
            mp(75) = 'ElasticForceBeamColumn2d';
            mp(751) = 'ElasticForceBeamColumnWarping2d';
            mp(76) = 'ElasticForceBeamColumn3d';
            mp(77) = 'ForceBeamColumnCBDI2d';
            mp(78) = 'ForceBeamColumnCBDI3d';
            mp(30766) = 'MixedBeamColumn2d';
            mp(30765) = 'MixedBeamColumn3d';
            mp(30767) = 'MixedBeamColumnAsym3d';
            mp(79) = 'DispBeamColumn2dInt';
            mp(80) = 'InternalSpring';
            mp(81) = 'SimpleJoint2D';
            mp(8181) = 'LehighJoint2d';
            mp(82) = 'Joint2D';
            mp(83) = 'Joint3D';
            mp(84) = 'ElastomericBearingPlasticity3d';
            mp(85) = 'ElastomericBearingPlasticity2d';
            mp(86) = 'TwoNodeLink';
            mp(87) = 'ActuatorCorot';
            mp(88) = 'Actuator';
            mp(89) = 'Adapter';
            mp(90) = 'ElastomericBearingBoucWen2d';
            mp(91) = 'ElastomericBearingBoucWen3d';
            mp(92) = 'FlatSliderSimple2d';
            mp(93) = 'FlatSliderSimple3d';
            mp(94) = 'FlatSlider2d';
            mp(95) = 'FlatSlider3d';
            mp(96) = 'SingleFPSimple2d';
            mp(97) = 'SingleFPSimple3d';
            mp(98) = 'SingleFP2d';
            mp(99) = 'SingleFP3d';
            mp(100) = 'DoubleFPSimple2d';
            mp(101) = 'DoubleFPSimple3d';
            mp(102) = 'DoubleFP2d';
            mp(103) = 'DoubleFP3d';
            mp(104) = 'TripleFPSimple2d';
            mp(105) = 'TripleFPSimple3d';
            mp(106) = 'TripleFP2d';
            mp(107) = 'TripleFP3d';
            mp(108) = 'MultiFP2d';
            mp(109) = 'MultiFP3d';
            mp(110) = 'GenericClient';
            mp(111) = 'GenericCopy';
            mp(112) = 'PY_MACRO2D';
            mp(113) = 'SimpleContact2D';
            mp(114) = 'SimpleContact3D';
            mp(115) = 'BeamContact3D';
            mp(116) = 'SurfaceLoad';
            mp(117) = 'BeamContact2D';
            mp(118) = 'BeamEndContact3D';
            mp(119) = 'SSPquad';
            mp(120) = 'SSPquadUP';
            mp(121) = 'SSPbrick';
            mp(122) = 'SSPbrickUP';
            mp(123) = 'BeamContact2Dp';
            mp(124) = 'BeamContact3Dp';
            mp(125) = 'BeamEndContact3Dp';
            mp(126) = 'Quad4FiberOverlay';
            mp(127) = 'Brick8FiberOverlay';
            mp(128) = 'DispBeamColumn2dThermal';
            mp(129) = 'TPB1D';
            mp(130) = 'TFP_Bearing';
            mp(131) = 'TFP_Bearing2d';
            mp(132) = 'TripleFrictionPendulum';
            mp(133) = 'PFEMElement2D';
            mp(134) = 'FourNodeQuad02';
            mp(135) = 'cont2d01';
            mp(136) = 'cont2d02';
            mp(137) = 'CST';
            mp(138) = 'Truss2';
            mp(139) = 'CorotTruss2';
            mp(140) = 'ZeroLengthImpact3D';
            mp(141) = 'PFEMElement3D';
            mp(142) = 'PFEMElement2DCompressible';
            mp(143) = 'PFEMElement2DBubble';
            mp(144) = 'PFEMElement2Dmini';
            mp(145) = 'ElasticTimoshenkoBeam2d';
            mp(146) = 'ElasticTimoshenkoBeam3d';
            mp(147) = 'ElastomericBearingUFRP2d';
            mp(148) = 'ElastomericBearingUFRP3d';
            mp(149) = 'RJWatsonEQS2d';
            mp(150) = 'RJWatsonEQS3d';
            mp(151) = 'HDR';
            mp(152) = 'ElastomericX';
            mp(153) = 'LeadRubberX';
            mp(154) = 'PileToe3D';
            mp(155) = 'N4BiaxialTruss';
            mp(156) = 'ShellDKGQ';
            mp(157) = 'ShellNLDKGQ';
            mp(158) = 'MultipleShearSpring';
            mp(159) = 'MultipleNormalSpring';
            mp(160) = 'KikuchiBearing';
            mp(161) = 'YamamotoBiaxialHDR';
            mp(162) = 'MVLEM';
            mp(163) = 'SFI_MVLEM';
            mp(164) = 'PFEMElement2DFIC';
            mp(165) = 'ElastomericBearingBoucWenMod3d';
            mp(166) = 'FPBearingPTV';
            mp(167) = 'ShellDKGT';
            mp(168) = 'ShellNLDKGT';
            mp(169) = 'CatenaryCable';
            mp(170) = 'DispBeamColumn3dThermal';
            mp(171) = 'ForceBeamColumn2dThermal';
            mp(172) = 'ForceBeamColumn3dThermal';
            mp(173) = 'ShellMITC4Thermal';
            mp(174) = 'ShellNLDKGQThermal';
            mp(175) = 'ShellANDeS';
            mp(178) = 'AxEqDispBeamColumn2d';
            mp(179) = 'FourNodeTetrahedron';
            mp(180) = 'TriSurfaceLoad';
            mp(181) = 'QuadBeamEmbedContact';
            mp(182) = 'EmbeddedBeamInterfaceL';
            mp(183) = 'EmbeddedBeamInterfaceP';
            mp(184) = 'EmbeddedEPBeamInterface';
            mp(185) = 'LysmerTriangle';
            mp(186) = 'TaylorHood2D';
            mp(187) = 'PFEMElement2DQuasi';
            mp(188) = 'MINI';
            mp(189) = 'PFEMElement3DBubble';
            mp(190) = 'LinearElasticSpring';
            mp(191) = 'Inerter';
            mp(192) = 'GradientInelasticBeamColumn2d';
            mp(193) = 'GradientInelasticBeamColumn3d';
            mp(194) = 'CohesiveZoneQuad';
            mp(195) = 'ComponentElement2d';
            mp(195195) = 'ComponentElement3d';
            mp(196) = 'InerterElement';
            mp(197) = 'BeamColumn2DwLHNMYS';
            mp(198) = 'BeamColumn3DwLHNMYS';
            mp(199) = 'PFEMLink';
            mp(200) = 'PFEMContact2D';
            mp(201) = 'PML3D';
            mp(202) = 'PML2D';
            mp(203) = 'ASDShellQ4';
            mp(204) = 'ASDShellT3';
            mp(205) = 'WheelRail';
            mp(206) = 'DispBeamColumn3dID';
            mp(207) = 'NineNodeQuad';
            mp(208) = 'EightNodeQuad';
            mp(209) = 'SixNodeTri';
            mp(210) = 'RockingBC';
            mp(211) = 'BeamColumn2DwLHNMYS_Damage';
            mp(212) = 'MVLEM_3D';
            mp(213) = 'SFI_MVLEM_3D';
            mp(214) = 'BeamGT';
            mp(215) = 'MasonPan12';
            mp(216) = 'MasonPan3D';
            mp(217) = 'ASDEmbeddedNodeElement';
            mp(218) = 'InertiaTruss';
            mp(219) = 'ASDAbsorbingBoundary2D';
            mp(220) = 'ASDAbsorbingBoundary3D';
            mp(221) = 'ZeroLengthContactASDimplex';
            mp(250) = 'IGALinePatch';
            mp(251) = 'IGASurfacePatch';
            mp(252) = 'IGAVolumePatch';
            mp(253) = 'IGAKLShell';
            mp(254) = 'IGAKLShell_BendingStrip';
            mp(255) = 'PFEMContact3D';
            mp(256) = 'TenNodeTetrahedron';
            mp(257) = 'E_SFI';
            mp(258) = 'TripleFrictionPendulumX';
            mp(259) = 'PML2D_3';
            mp(260) = 'PML2D_5';
            mp(261) = 'PML2D_12';
            mp(262) = 'PML2DVISCOUS';
            mp(268) = 'ShellNLDKGTThermal';
            mp(99990) = 'ExternalElement';
            mp(259259) = 'E_SFI_MVLEM_3D';
            mp(100000011) = 'FourNodeQuadWithSensitivity';
            mp(1984587234) = 'BbarBrickWithSensitivity';
            mp(102030) = 'DispBeamColumn2dWithSensitivity';
            mp(1110000) = 'DispBeamColumn3dWithSensitivity';
            mp(100003) = 'VS3D4QuadWithSensitivity';
            mp(100009) = 'AV3D4QuadWithSensitivity';
            mp(100001) = 'AC3D8HexWithSensitivity';
            mp(100002) = 'ASI3D8QuadWithSensitivity';
        end
    end
end