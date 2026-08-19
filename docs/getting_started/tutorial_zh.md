# OpenSeesMatlab 中文入门教程

这篇教程面向第一次使用 OpenSeesMatlab 的读者。我们先用一个两节点桁架跑通“建模、加载、求解、读取结果”的完整过程，再介绍结果记录和绘图。示例采用 SI 单位制，可以直接复制到 MATLAB 脚本中运行。

## 安装与验证

OpenSeesMatlab 目前支持 Windows 和 MATLAB R2023a 及以上版本。可以从以下任一地址下载发布包：

- [GitHub Releases](https://github.com/yexiang92/OpenSeesMatlab/releases)
- [Gitee Releases（国内镜像）](https://gitee.com/yexiang-yan/opensees-interface-for-matlab/releases)

下载后解压到一个具有写入权限的目录。在 MATLAB 中进入该目录并运行安装脚本：

```matlab
cd('D:\path\to\OpenSeesMatlab');
installOpenSeesMatlab;
```

将示例路径换成实际的解压目录。如果安装程序提示重启 MATLAB，请先重启再继续。安装完成后，在新的 MATLAB 会话中运行：

```matlab
opsMAT = OpenSeesMatlab();
opsMAT.version
which OpenSeesMatlab -all
```

能看到版本号，且 `which` 指向当前安装目录，就说明工具箱可以使用。若列出了多个路径，最好从 MATLAB 路径中移除旧版本，以免脚本调用到错误的 MEX 文件。

OpenSeesMatlab 的常用功能都挂在 `opsMAT` 对象下：

| 对象 | 用途 |
| --- | --- |
| `opsMAT.opensees` | 建模和分析命令，写法与 OpenSees 接近 |
| `opsMAT.pre` | 前处理工具 |
| `opsMAT.anlys` | 分析辅助工具 |
| `opsMAT.post` | ODB、响应读取和结果导出 |
| `opsMAT.vis` | MATLAB 绘图和交互式可视化 |

通常会先给命令接口取一个短名字：

```matlab
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
```

后面写 `ops.node(...)`，就是调用 OpenSees 的 `node` 命令。

## OpenSees 的一般工作流程

OpenSees 的脚本通常沿着一条固定主线展开。无论计算的是一根桁架、一栋框架还是土体模型，基本顺序都差不多：

```text
清空旧模型
    ↓
声明模型维数和节点自由度
    ↓
建立节点、约束、材料、截面和单元
    ↓
定义时间序列、荷载模式和荷载
    ↓
配置约束处理、编号、方程求解器、收敛检验、算法和积分器
    ↓
执行静力或动力分析
    ↓
检查返回码，读取、保存并绘制结果
```

对应到常用命令，大致是：

```matlab
ops.wipe();
ops.model(...);

ops.node(...);
ops.fix(...);
ops.uniaxialMaterial(...);  % 也可能使用 nDMaterial
ops.section(...);           % 仅在所选单元需要截面时定义
ops.element(...);

ops.timeSeries(...);
ops.pattern(...);
ops.load(...);              % 或 eleLoad、groundMotion 等

ops.constraints(...);
ops.numberer(...);
ops.system(...);
ops.test(...);              % 非线性分析通常需要
ops.algorithm(...);
ops.integrator(...);
ops.analysis(...);

ok = ops.analyze(...);
```

前半部分描述“模型是什么”，后半部分决定“怎样求解”。建模命令正确并不代表分析设置一定合适；反过来，频繁更换算法也无法修复错误的边界条件或材料参数。

静力分析中的“时间”通常是荷载因子或伪时间；动力分析中的“时间”才对应实际时间。`timeSeries` 描述荷载如何随时间变化，`pattern` 把时间序列与一组荷载联系起来，`integrator` 决定每一步如何推进。理解这三者的关系，比单纯记住命令顺序更重要。

分析完成后，可以直接用 `nodeDisp`、`eleResponse` 等命令读取当前状态，也可以在分析前创建 ODB，记录完整时程。小算例直接查询比较方便，多步分析和后处理通常更适合使用 ODB。

## 第一个算例：受拉弹性桁架

模型很简单：一根长 1 m 的水平杆，左端固定，右端施加 100 kN 水平拉力。杆件截面积为 0.002 m²，弹性模量为 200 GPa。理论位移为：

\[
u=\frac{PL}{AE}=2.5\times10^{-4}\ \mathrm{m}
\]

### 清空旧模型

```matlab
ops.wipe();
```

建议每个独立脚本都从 `wipe` 开始。否则上一次运行留下的节点、材料或荷载可能与新模型发生冲突。

### 建立模型空间

```matlab
ops.model('basic', '-ndm', 2, '-ndf', 2);
```

- `-ndm 2` 表示二维模型；
- `-ndf 2` 表示每个节点有两个自由度，即 X、Y 两个方向的平移。

若是二维梁柱模型，节点通常有 `ux`、`uy` 和 `rz` 三个自由度，因此常用 `-ndf 3`。模型维数和节点自由度必须与所选单元匹配。

### 定义参数、节点和约束

```matlab
L = 1.0;       % 杆长，m
A = 2.0e-3;    % 截面积，m^2
E = 200.0e9;   % 弹性模量，Pa
P = 100.0e3;   % 荷载，N

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);

ops.fix(1, 1, 1);
ops.fix(2, 0, 1);
```

节点命令的第一个数字是节点标签，后面是坐标。标签不要求连续，但不能重复。

`fix` 中的 `1` 表示约束，`0` 表示自由。节点 1 的两个方向都固定；节点 2 的 X 方向自由、Y 方向固定。这里约束节点 2 的 Y 方向，是因为单根水平桁架没有竖向刚度，放开后会产生刚度矩阵奇异。

### 定义材料和单元

```matlab
ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);
```

第一行建立标签为 1 的弹性单轴材料。第二行建立标签为 1 的桁架单元，连接节点 1 和节点 2，最后一个参数 `1` 是材料标签。

OpenSees 通过整数标签关联节点、材料、截面和单元。模型较大时，最好把标签集中定义，避免同一类对象重复编号。

### 先看一眼模型

```matlab
opsMAT.vis.plotModel();
```

绘图不是求解的必要步骤，但很适合检查节点位置、单元连接和约束。确认模型无误后再分析，通常比分析失败后逐行排查更省时间。

如果需要旋转、选择和更多显示选项，可以使用交互式 Polyscope 窗口：

```matlab
opsMAT.vis.polyscope.plotModel();
```

### 施加荷载

```matlab
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);
```

这三行依次定义时间序列、荷载模式，以及节点 2 上的 X、Y 方向荷载。`load` 后面的分量数应与节点自由度数一致。本例节点有两个自由度，所以写两个荷载分量。

### 配置静力分析

```matlab
ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');
```

这些命令分别选择方程求解器、自由度编号方式、约束处理方法、增量方式、求解算法和分析类型。弹性线性问题用上面的组合即可。

非线性分析还要设置收敛检验，例如：

```matlab
ops.test('NormDispIncr', 1.0e-8, 30);
ops.algorithm('Newton');
```

不要在不收敛时一次更换所有设置。先检查边界条件、材料参数和单位，再逐项调整步长、算法及收敛容限。

### 求解并检查返回值

```matlab
ok = ops.analyze(1);
assert(ok == 0, 'OpenSees 分析未收敛，返回码为 %d。', ok);
```

OpenSees 返回 `0` 表示分析成功，非零值表示失败。正式计算脚本中应始终检查返回码，否则后续程序可能继续处理无效结果。

### 读取节点位移

```matlab
ux = ops.nodeDisp(2, 1);
uxTheory = P * L / (A * E);

fprintf('OpenSees 计算值：%.6e m\n', ux);
fprintf('理论值：        %.6e m\n', uxTheory);
fprintf('相对误差：      %.3e\n', abs(ux - uxTheory) / uxTheory);
```

`nodeDisp(2, 1)` 表示读取节点 2 的第 1 个自由度。对于本例，第 1 个自由度就是 X 向位移。

## 可以直接运行的完整脚本

```matlab
opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
ops.wipe();

% 模型
ops.model('basic', '-ndm', 2, '-ndf', 2);
L = 1.0;
A = 2.0e-3;
E = 200.0e9;
P = 100.0e3;

ops.node(1, 0.0, 0.0);
ops.node(2, L,   0.0);
ops.fix(1, 1, 1);
ops.fix(2, 0, 1);
ops.uniaxialMaterial('Elastic', 1, E);
ops.element('Truss', 1, 1, 2, A, 1);

% 荷载
ops.timeSeries('Linear', 1);
ops.pattern('Plain', 1, 1);
ops.load(2, P, 0.0);

% 分析
ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 1.0);
ops.algorithm('Linear');
ops.analysis('Static');

ok = ops.analyze(1);
assert(ok == 0, 'OpenSees 分析未收敛，返回码为 %d。', ok);

% 结果
ux = ops.nodeDisp(2, 1);
uxTheory = P * L / (A * E);
fprintf('ux = %.6e m，理论值 = %.6e m\n', ux, uxTheory);

opsMAT.vis.plotModel();
ops.wipe();
```

第一次运行时，建议整段执行。确认结果正确后，再逐节运行并修改参数。

## 记录多步分析结果

`nodeDisp` 适合读取当前时刻的结果。如果要保存多步静力分析或动力分析的完整时程，可以在分析前创建 ODB。ODB 会自动记录后续 `analyze` 产生的响应。

下面把前面的荷载分成 10 步：

```matlab
% 建模和加载命令与前面相同，此处省略

ops.system('BandSPD');
ops.numberer('RCM');
ops.constraints('Plain');
ops.integrator('LoadControl', 0.1);
ops.algorithm('Linear');
ops.analysis('Static');

odbTag = "truss_demo";
ODB = opsMAT.post.createODB(odbTag);

ok = ops.analyze(10);
assert(ok == 0, '分析未完成。');

ODB.close();
ops.wipe();
```

ODB 默认保存在：

```text
.openseesmatlab.output/Responses-truss_demo.odb/output.h5
```

读取节点响应：

```matlab
nodeResp = opsMAT.post.getNodalResponse("truss_demo");

idx = nodeResp.nodeTags == 2;
uxHistory = nodeResp.disp.ux(:, idx);

figure;
plot(nodeResp.time, uxHistory, 'LineWidth', 1.5);
xlabel('荷载因子');
ylabel('节点 2 的 X 向位移 / m');
grid on;
```

应在分析完成或调用 `ODB.close()` 后读取结果。读取响应会结束对应 ODB 的记录，不要一边分析一边调用 `getNodalResponse`。

## 按标签处理响应数据

ODB 返回普通 MATLAB 结构体，现有绘图函数直接使用这种结构。若想按节点、时间或单元标签选择数据，可以另外转换为 `ResponseDataset`：

```matlab
ds = opsMAT.post.toResponseDataset(nodeResp);

ds.names()           % 查看可用变量
ux = ds.get("disp.ux");

node2 = ux.sel("node", 2);       % 按节点标签选择
first10 = ux.isel("time", 1:10); % 按数组位置选择
```

常用响应还支持点操作。例如 `ds.disp.ux` 可以直接取得位移的 X 分量。`sel` 使用坐标标签，`isel` 使用从 1 开始的 MATLAB 索引，两者不要混用。

转换得到的对象只是便于查询，不会改变原来的 `nodeResp`。可视化时仍可直接传入原结构体：

```matlab
opsMAT.vis.plotNodalResponse( ...
    nodeResp, stepIdx="absMax", ...
    respType="disp", respComponent="ux");

opsMAT.vis.polyscope.plotNodalResponse(nodeResp);
```

## 一个实用的脚本组织方式

模型变大以后，不建议把所有代码堆在一个脚本中。可以按下面的方式拆分：

```text
my_model/
├─ main.m               % 参数、调用顺序和工况
├─ buildModel.m         % 节点、约束、材料、截面和单元
├─ applyLoads.m         % 荷载与时间序列
├─ configureAnalysis.m  % 求解器、算法和收敛设置
└─ plotResults.m        % 结果整理与绘图
```

建议把长度、力、质量等基本单位写在主脚本开头，并在变量注释中注明单位。OpenSees 不会替用户检查量纲；只要输入数值在数学上可计算，单位混用也可能得到一个看似正常但实际错误的结果。

## 常见问题

### 出现刚度矩阵奇异

先检查以下几项：

- 是否遗漏支座约束；
- 单元是否真正连接到预期节点；
- 节点自由度是否与单元类型匹配；
- 是否存在没有刚度贡献的自由度；
- 材料、截面参数是否为零或数量级错误。

对于本教程中的水平桁架，如果节点 2 的 Y 向自由度没有约束，就会出现这一问题。

### `analyze` 返回非零值

先保存返回码，并检查最后一个成功步。非线性分析可尝试减小步长，但减小步长不是万能办法。模型本身不合理时，更换算法通常只会掩盖问题。

### 找不到命令或 MEX 文件

```matlab
which OpenSeesMatlab -all
which OpenSeesMex -all
```

确认 MATLAB 没有同时加载多个版本。更新或重新安装后，建议重启 MATLAB。

### Polyscope 窗口无法打开

先用普通 MATLAB 绘图确认模型数据正常：

```matlab
opsMAT.vis.plotModel();
```

核心分析不依赖 Polyscope。交互窗口异常时仍可继续建模、分析和读取结果。

### 结果数量级不对

OpenSees 本身没有固定单位制。只要所有输入保持一致，N-m-Pa、N-mm-MPa 等单位制都可以使用。最常见的错误是几何尺寸用 mm、弹性模量却按 Pa 输入，或者质量与重量混淆。

## 接下来可以看什么

- [OpenSees 命令接口](opensees.md)：MATLAB 参数传递方式和常用命令写法；
- [前后处理与可视化](post.md)：ODB、节点和单元响应、导出及 GUI；
- [扩展功能](extensions.md)：自适应分析、求解器和其他扩展；
- [示例目录](../examples/index.md)：结构、岩土、动力和并行计算示例。

学习新单元时，推荐从现有示例中找到相近模型，先保持材料、自由度和分析设置不变，只修改几何和参数。能稳定得到预期结果后，再逐步加入非线性、动力荷载和复杂后处理。
