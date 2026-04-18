All OpenSees commands use the same input format as ``OpenSees`` and ``OpenSeesPy``. 
For example:

```matlab
opsMat = OpenSeesMatlab();  % Get Instance
ops = opsmat.opensees;  % Get the OpenSees command interface

ops.wipe();
ops.model('basic', '-ndm', 2, '-ndf', 3);
...
ops.node(1, 0.0, 0.0);
ops.node(2, 5.0, 0.0);
ops.fix(1, 1, 1, 1);
ops.element(...);
```



For details, please refer to their official documentation.

[OpenSeesPy](https://openseespydoc.readthedocs.io/en/latest/index.html)

[OpenSees](https://opensees.github.io/OpenSeesDocumentation/)

[OpenSees Command Manual](https://opensees.berkeley.edu/wiki/index.php/OpenSees_User)

📌 A few notes:

- ✨ Both ``char`` and ``string`` inputs are supported. However, using ``char`` is recommended.
- ✨ Commands do not support passing ``numeric array`` directly; please pass **scalar arguments one by one**. When needed, you can unpack ``cell`` inputs like this: ``ops.node(1, coords{:})``, where coords is a ``cell`` array. If coords is a numeric array, you can first convert it to a cell array with ``coords = num2cell(coords)``. One exception is the ``Path``-type ``timeSeries``, where a numeric array can be passed to ``"-values"``.
- ✨ Commands with return values will return MATLAB data. If a command has no return value, an empty array ``[]`` will be returned.
- ✨ The additional post-processing provided by OpenSeesMatlab may be slow or buggy. If you think so, you can use only the OpenSees command interface and use ``recorder`` or other output commands to post-process the analysis results.