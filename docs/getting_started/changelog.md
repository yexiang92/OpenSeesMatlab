# Changes Log

## v3.8.0.1

- By adding a new recorder object to the OpenSees C++ side, response post-processing can be implemented in C++, significantly improving post-processing performance.
- Enable proper error reporting and termination for OpenSees on the MATLAB side (bug); 
- Improve the performance of ``plotFrameResponse``; 
- Enhance the efficiency and capabilities of ``SmartAnalyze``.
- Some commands, such as ``node``, ``element``, ``section``, ``recorder``, and ``fix``, support passing in ``double`` or ``cell`` arrays.
- Add ``pre.FiberSectionMesh`` to the ``pre`` package for creating fiber section meshes.
- Add ``anlys.MomentCurvature`` to perform moment-curvature analysis of arbitrary OpenSees cross-section.
