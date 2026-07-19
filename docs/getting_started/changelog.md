# Changes Log

## v3.8.0.2

- Add MATLAB callback-backed uniaxial materials through ``ops.uniaxialMaterial("MatlabUniaxialMaterial", ...)``. User-defined callbacks can provide stress, tangent and history-dependent state while supporting OpenSees trial, commit and revert semantics for failed-step recovery.
- Add MATLAB numerical substructure analysis through ``ops.matlabSubstructure``. A MATLAB callback can provide the resisting force, current tangent, mass and damping matrices for an OpenSees Element while OpenSees manages the global analysis. Support arbitrary substructure interfaces defined by ``[nodeTag, DOF]`` pairs, including a single condensed interface node or multiple physical end nodes.
- Add the optional NVIDIA cuDSS sparse direct solver through ``ops.system("CuDSS")``. The GPU backend is loaded on demand, supports automatic CUDA and GPU discovery, and does not affect CPU solvers on systems without CUDA or cuDSS.
- Add ``post.transformResponseStruct`` to convert model-update response struct arrays from ``getNodalResponse`` and ``getElementResponse`` into one scalar struct, merging ``time``, ``nodeTags`` and ``eleTags`` while padding missing response data with ``NaN``.
- Add ``ops.updateMaterials`` as a MATLAB wrapper for the OpenSees ``UpdateMaterials`` command.
- Add support for ``Link`` element response queries in ``post.getElementResponse``.
- Add a [Polyscope](https://polyscope.run/)-based GUI visualization backend for interactive model, eigenmode, frame-response, nodal-response and unstructured-response viewing.
- Extend frame, nodal and unstructured response plotters to support custom response fields and explicit response-location handling.
- Response GUIs now list user-defined response fields and components directly from response data, including scalar fields, ``.data``/``.dofs`` layouts and Layout-C numeric subfields.
- Update post-processing documentation and examples, including ODB response retrieval, quick plotting and visualization workflows.

## v3.8.0.1

- By adding a new recorder object to the OpenSees C++ side, response post-processing can be implemented in C++, significantly improving post-processing performance.
- Enable proper error reporting and termination for OpenSees on the MATLAB side (bug); 
- Improve the performance of ``plotFrameResponse``; 
- Enhance the efficiency and capabilities of ``SmartAnalyze``.
- Some commands, such as ``node``, ``element``, ``section``, ``recorder``, and ``fix``, support passing in ``double`` or ``cell`` arrays.
- Add ``pre.FiberSectionMesh`` to the ``pre`` package for creating fiber section meshes.
- Add ``anlys.MomentCurvature`` to perform moment-curvature analysis of arbitrary OpenSees cross-section.
