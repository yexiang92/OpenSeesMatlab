%% cuDSS: CPU/GPU sparse-solver comparison
% This example compares the optional NVIDIA cuDSS extension with several native 
% CPU solvers. Every solver receives the same elastic plane-stress model, constraints, 
% ordering, loading, and number of analysis steps.
% 
% Model construction, one-time GPU startup, the first |analyze(1)| call, and 
% repeated calls are reported separately. The measured crossover belongs to the 
% computer used for the test; it is not a universal solver threshold.

clear;
clc;
close all;
% 1. Choose the matrix type before the solver
% |CuDSS| is the safest GPU choice when the tangent matrix may become nonsymmetric. 
% |CuDSSGeneral| is an alias for the same implementation and is therefore not 
% timed twice. |CuDSSSymmetric| is a distinct symmetric-indefinite solver, while 
% |CuDSSSPD| requires a symmetric positive-definite matrix.
% 
% The panel used here is elastic, stable, and fully constrained, so all listed 
% matrix assumptions are valid. The table also records the CPU solver used as 
% the timing and accuracy reference for each command.


SolverGuide = table( ...
    ["CuDSS"; "CuDSSGeneral"; "CuDSSSymmetric"; "CuDSSSPD"; ...
     "UmfPack"; "SuperLU"; "BandGeneral"; "SparseSPD"; ...
     "ProfileSPD"; "BandSPD"], ...
    ["GPU"; "GPU"; "GPU"; "GPU"; "CPU"; "CPU"; "CPU"; ...
     "CPU"; "CPU"; "CPU"], ...
    ["general"; "general"; "symmetric indefinite"; ...
     "symmetric positive definite"; "general"; "general"; "general"; ...
     "symmetric positive definite"; "symmetric positive definite"; ...
     "symmetric positive definite"], ...
    repmat("UmfPack",10,1), ...
    'VariableNames',{'Command','Backend','MatrixAssumption','TimingReference'});
SolverGuide
% 2. Configure the runtime and benchmark
% Leave both paths empty to use automatic runtime discovery. If discovery fails, 
% enter the CUDA and cuDSS installation roots or DLL directories. CUDA and cuDSS 
% must target the same CUDA major version. CPU cases remain available without 
% an NVIDIA GPU.


cudaPath = "";
cudssPath = "";
% cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6";
% cudssPath = "C:\Program Files\NVIDIA cuDSS\v0.8";

CuDSSOptions = buildCuDSSOptions(cudaPath,cudssPath);

% The publication benchmark extends to one million active equations. At that
% size only the cuDSS variants and UmfPack are retained; the remaining CPU
% baselines stop at 100000 equations to control runtime and storage.
TargetDOFs = [100 500 1000 2000 5000 10000 20000 50000 100000 1000000];

% Keep the three cuDSS variants together in tables, plots, and legends.
Solvers = ["CuDSS" "CuDSSSymmetric" "CuDSSSPD" ...
    "UmfPack" "SuperLU" "BandGeneral" ...
    "SparseSPD" "ProfileSPD" "BandSPD"];
NumberOfLoadSteps = 4;

opsMat = OpenSeesMatlab();
ops = opsMat.opensees;
% 3. Measure one-time GPU startup separately
% The first cuDSS use in a MATLAB process loads the runtime, creates a CUDA 
% context, and selects a device. The smoke case records this one-time cost. |-verbose| 
% is used only here and is removed from the benchmark timings.


CuDSSAvailable = true;
CuDSSStartupCaseSeconds = NaN;
CuDSSFailureMessage = "";
try
    startupTimer = tic;
    runPlaneCase(ops,500,"CuDSS",1,[CuDSSOptions {"-verbose"}]);
    CuDSSStartupCaseSeconds = toc(startupTimer);
    fprintf("cuDSS startup plus 500-equation smoke case: %.3f s\n", ...
        CuDSSStartupCaseSeconds);
catch exception
    CuDSSAvailable = false;
    CuDSSFailureMessage = string(exception.message);
    warning("cuDSS is unavailable; CPU cases will continue.\n%s", ...
        CuDSSFailureMessage);
end
% 4. Run the same model with every solver
% |ModelBuildSeconds| includes domain construction only. |FirstAnalyzeSeconds| 
% is the first |analyze(1)| call for a newly created system. |RepeatedAnalyzeSeconds| 
% is the median of the remaining calls. Because the tangent is unchanged in this 
% linear example, repeated cuDSS calls demonstrate the extension's normal factorization-reuse 
% behavior.
% 
% Add |"-noReuseFactorization"| to |CuDSSOptions| only when the purpose is to 
% measure raw refactorization rather than normal application performance.


numberOfCases = numel(TargetDOFs)*numel(Solvers);
records = repmat(emptyResult(),numberOfCases,1);
recordIndex = 0;

for targetDOF = TargetDOFs
    for solver = Solvers
        recordIndex = recordIndex + 1;

        if shouldSkipLargeCpuCase(targetDOF,solver)
            records(recordIndex) = skippedResult(targetDOF,solver, ...
                "Publication curve ends at 100000 equations for this CPU solver.");
            continue;
        end

        if startsWith(solver,"CuDSS") && ~CuDSSAvailable
            records(recordIndex) = failedResult(targetDOF,solver, ...
                "cuDSS runtime unavailable: " + CuDSSFailureMessage);
            continue;
        end

        fprintf("Running %-14s at a target of %d equations...\n",solver,targetDOF);
        try
            records(recordIndex) = runPlaneCase(ops,targetDOF,solver, ...
                NumberOfLoadSteps,CuDSSOptions);
        catch exception
            records(recordIndex) = failedResult(targetDOF,solver, ...
                string(exception.message));
        end
    end
end

Results = struct2table(records);
Results = addPairwiseComparisons(Results);
% 5. Check numerical agreement first
% All solvers use |UmfPack| as one common reference, matching the convention 
% used in the publication figures. A speedup greater than one means that the selected 
% solver was faster than |UmfPack| for the measured phase.


ResultSummary = Results(:,{ ...
    'TargetDOF','ActualDOF','Solver','ReferenceSolver','Status', ...
    'FirstAnalyzeSeconds','RepeatedAnalyzeSeconds', ...
    'FirstSpeedup','RepeatedSpeedup','RelativeTipError'});
ResultSummary

IncompleteCases = Results(Results.Status ~= "ok", ...
    {'TargetDOF','Solver','Status','Message'});
if ~isempty(IncompleteCases)
    disp("Cases that were not completed:");
    disp(IncompleteCases);
end
% 6. Publication-style solution-time figure
% This follows the original manuscript layout: first and repeated solutions 
% are shown side by side, the equation count is logarithmic, and solution time 
% remains linear. The large canvas and common legend preserve readable type and 
% markers when the figure is reduced to journal width.


fontName = "Times New Roman";
fontSize = 12;
lineWidth = 1.6;
markerSize = 7;
axisLineWidth = 0.9;
PlotStyle = solverPlotStyle(Solvers);

figTime = figure( ...
    "Name","Sparse-solver solution time", ...
    "Color","w", ...
    "Units","pixels", ...
    "Position",[60 80 1600 720]);
timeLayout = tiledlayout(figTime,1,2, ...
    "TileSpacing","compact","Padding","compact");

axFirst = nexttile(timeLayout);
plotSolverMetric(axFirst,Results,Solvers,"FirstAnalyzeSeconds", ...
    PlotStyle,lineWidth,markerSize,false);
setPublicationAxes(axFirst,fontName,fontSize,axisLineWidth);
title(axFirst,"(a) First solution of each system","FontWeight","normal");
ylabel(axFirst,"Solution time (s)");

axRepeated = nexttile(timeLayout);
plotSolverMetric(axRepeated,Results,Solvers,"RepeatedAnalyzeSeconds", ...
    PlotStyle,lineWidth,markerSize,false);
setPublicationAxes(axRepeated,fontName,fontSize,axisLineWidth);
title(axRepeated,"(b) Repeated tangent solution","FontWeight","normal");
ylabel(axRepeated,"Median solution time (s)");

timeLegend = legend(axRepeated,"Location","southoutside", ...
    "NumColumns",3,"Box","off","FontName",fontName, ...
    "FontSize",fontSize-1);
timeLegend.Layout.Tile = "south";
drawnow;

% Vector export for a manuscript:
% exportgraphics(figTime,"CUDSSSolverTime.pdf","ContentType","vector");
% 7. Publication-style displacement-accuracy figure
% Accuracy is kept as a separate figure, matching the manuscript example. Every 
% curve is measured relative to the |UmfPack| solution. Exact zero is replaced 
% by |eps| only for display on the logarithmic axis; the results table retains 
% zero.


figAccuracy = figure( ...
    "Name","Sparse-solver displacement accuracy", ...
    "Color","w", ...
    "Units","pixels", ...
    "Position",[120 100 940 720]);
axError = axes(figAccuracy);
plotComparisonMetric(axError,Results,Solvers,"RelativeTipError", ...
    PlotStyle,lineWidth,markerSize,true);
setPublicationAxes(axError,fontName,fontSize,axisLineWidth);
ylabel(axError,"Relative displacement error");
accuracyLegend = legend(axError,"Location","northoutside", ...
    "NumColumns",3,"Box","off","FontName",fontName, ...
    "FontSize",fontSize-1);
drawnow;

% Vector export for a manuscript:
% exportgraphics(figAccuracy,"CUDSSSolverAccuracy.pdf", ...
%     "ContentType","vector");
% 8. Optional speedup figure
% Speedup is useful for interpretation but is kept separate so it does not reduce 
% the plotting area available to the accuracy figure. All values use the same 
% |UmfPack| reference.


figSpeedup = figure( ...
    "Name","Sparse-solver repeated-solution speedup", ...
    "Color","w", ...
    "Units","pixels", ...
    "Position",[150 120 940 720]);
axSpeedup = axes(figSpeedup);
plotComparisonMetric(axSpeedup,Results,Solvers,"RepeatedSpeedup", ...
    PlotStyle,lineWidth,markerSize,false);
yline(axSpeedup,1,"--","UmfPack reference", ...
    "Color",[0.25 0.25 0.25],"LineWidth",1.0, ...
    "LabelHorizontalAlignment","right","HandleVisibility","off");
setPublicationAxes(axSpeedup,fontName,fontSize,axisLineWidth);
ylabel(axSpeedup,"Speedup");
speedupLegend = legend(axSpeedup,"Location","northoutside", ...
    "NumColumns",3,"Box","off","FontName",fontName, ...
    "FontSize",fontSize-1);
drawnow;

% Vector export for a manuscript:
% exportgraphics(figSpeedup,"CUDSSSolverSpeedup.pdf", ...
%     "ContentType","vector");
% 9. Interpret the result
% Confirm displacement agreement before using any timing result. Then distinguish 
% the first solution from repeated solutions: GPU initialization, matrix analysis, 
% factorization, transfer, and reuse affect the two measurements differently.
% 
% Band and profile solvers are useful baselines for small, regularly ordered 
% problems, but their storage and factorization costs can grow quickly. For a 
% nonlinear production model, repeat this comparison with the same convergence 
% test, algorithm, load history, and recorders. Start with |CuDSS|; select a symmetric 
% variant only when the corresponding property is guaranteed for every tangent 
% matrix.


%% Local functions
function result = runPlaneCase(ops,targetDOF,solver,numberOfSteps,cudssOptions)
    [nx,ny,actualDOF] = balancedMesh(targetDOF);
    cleanup = onCleanup(@() ops.wipe());

    modelTimer = tic;
    ops.wipe();
    ops.model("basic","-ndm",2,"-ndf",2);
    ops.nDMaterial("ElasticIsotropic",1,2.0e11,0.30,7850.0);
    ops.block2D(nx,ny,1,1,"quad",0.10,"PlaneStress",1, ...
        1,0,0, 2,10,0, 3,10,10, 4,0,10);
    ops.fixX(0.0,1,1);
    ops.timeSeries("Linear",1);
    ops.pattern("Plain",1,1);

    rightEdgeTags = (0:ny)*(nx+1)+nx+1;
    verticalLoad = -1.0e6/numel(rightEdgeTags);
    for nodeTag = rightEdgeTags
        ops.load(nodeTag,0.0,verticalLoad);
    end
    modelBuildSeconds = toc(modelTimer);

    ops.constraints("Plain");
    ops.numberer("RCM");
    selectSystem(ops,solver,cudssOptions);
    ops.integrator("LoadControl",1/numberOfSteps);
    ops.algorithm("Linear");
    ops.analysis("Static");

    analyzeSeconds = zeros(1,numberOfSteps);
    for step = 1:numberOfSteps
        solveTimer = tic;
        returnCode = ops.analyze(1);
        analyzeSeconds(step) = toc(solveTimer);
        if returnCode ~= 0
            error("CuDSSExample:AnalyzeFailed", ...
                "analyze(1) returned %d at load step %d.",returnCode,step);
        end
    end

    middleRightTag = floor(ny/2)*(nx+1)+nx+1;
    tipDisplacement = ops.nodeDisp(middleRightTag);

    result = emptyResult();
    result.TargetDOF = targetDOF;
    result.ActualDOF = actualDOF;
    result.Nx = nx;
    result.Ny = ny;
    result.Solver = solver;
    result.Family = solverFamily(solver);
    result.ReferenceSolver = referenceSolver(solver);
    result.Status = "ok";
    result.ModelBuildSeconds = modelBuildSeconds;
    result.FirstAnalyzeSeconds = analyzeSeconds(1);
    if numberOfSteps > 1
        result.RepeatedAnalyzeSeconds = median(analyzeSeconds(2:end));
    end
    result.TotalAnalyzeSeconds = sum(analyzeSeconds);
    result.TipUx = tipDisplacement(1);
    result.TipUy = tipDisplacement(2);
end

function selectSystem(ops,solver,cudssOptions)
    switch solver
        case "CuDSS"
            ops.system("CuDSS",cudssOptions{:});
        case "CuDSSSymmetric"
            ops.system("CuDSSSymmetric",cudssOptions{:});
        case "CuDSSSPD"
            ops.system("CuDSSSPD",cudssOptions{:});
        case "UmfPack"
            ops.system("UmfPack");
        case "SuperLU"
            ops.system("SuperLU");
        case "BandGeneral"
            ops.system("BandGeneral");
        case "SparseSPD"
            ops.system("SparseSPD");
        case "ProfileSPD"
            ops.system("ProfileSPD");
        case "BandSPD"
            ops.system("BandSPD");
        otherwise
            error("CuDSSExample:UnknownSolver","Unknown solver: %s",solver);
    end
end

function options = buildCuDSSOptions(cudaPath,cudssPath)
    options = {};
    if strlength(cudaPath) > 0
        options = [options {"-cudaPath",cudaPath}];
    end
    if strlength(cudssPath) > 0
        options = [options {"-cudssPath",cudssPath}];
    end
end

function tf = shouldSkipLargeCpuCase(targetDOF,solver)
    extendedCpuSolver = solver == "UmfPack";
    tf = targetDOF > 100000 && ~startsWith(solver,"CuDSS") && ...
        ~extendedCpuSolver;
end

function results = addPairwiseComparisons(results)
    for rowIndex = 1:height(results)
        if results.Status(rowIndex) ~= "ok"
            continue;
        end

        referenceRows = results.TargetDOF == results.TargetDOF(rowIndex) & ...
            results.Solver == results.ReferenceSolver(rowIndex) & ...
            results.Status == "ok";
        if ~any(referenceRows)
            continue;
        end

        referenceRow = find(referenceRows,1);
        referenceMagnitude = hypot(results.TipUx(referenceRow), ...
            results.TipUy(referenceRow));
        results.RelativeTipError(rowIndex) = hypot( ...
            results.TipUx(rowIndex)-results.TipUx(referenceRow), ...
            results.TipUy(rowIndex)-results.TipUy(referenceRow)) / ...
            max(referenceMagnitude,eps);
        results.FirstSpeedup(rowIndex) = ...
            results.FirstAnalyzeSeconds(referenceRow) / ...
            results.FirstAnalyzeSeconds(rowIndex);
        results.RepeatedSpeedup(rowIndex) = ...
            results.RepeatedAnalyzeSeconds(referenceRow) / ...
            results.RepeatedAnalyzeSeconds(rowIndex);
    end
end

function style = solverPlotStyle(solvers)
    knownSolvers = ["CuDSS" "CuDSSSymmetric" "CuDSSSPD" ...
        "UmfPack" "SuperLU" "BandGeneral" ...
        "SparseSPD" "ProfileSPD" "BandSPD"];
    colors = [ ...
        0.000 0.318 0.620
        0.000 0.576 0.659
        0.443 0.204 0.678
        0.902 0.380 0.000
        0.000 0.620 0.451
        0.800 0.118 0.235
        0.941 0.702 0.000
        0.337 0.706 0.914
        0.250 0.250 0.250];
    markers = ["o" "s" "^" "d" "v" ">" "<" "p" "h"];
    lineStyles = ["-" "-" "-" "--" "-." ":" "--" "-." ":"];

    [found,locations] = ismember(solvers,knownSolvers);
    if ~all(found)
        error("CuDSSExample:MissingPlotStyle", ...
            "A plot style is not defined for: %s",strjoin(solvers(~found),", "));
    end

    style = table(colors(locations,:),markers(locations)',lineStyles(locations)', ...
        'VariableNames',{'Color','Marker','LineStyle'});
end

function plotSolverMetric(ax,results,solvers,metric,style, ...
        lineWidth,markerSize,useLogY)
    hold(ax,"on");
    values = results.(metric);
    for solverIndex = 1:numel(solvers)
        solver = solvers(solverIndex);
        rows = results.Solver == solver & results.Status == "ok";
        data = sortrows(table(results.ActualDOF(rows),values(rows), ...
            'VariableNames',{'DOF','Value'}),'DOF');
        valid = isfinite(data.DOF) & isfinite(data.Value) & ...
            data.DOF > 0 & data.Value > 0;
        plot(ax,data.DOF(valid),data.Value(valid), ...
            "LineStyle",style.LineStyle(solverIndex), ...
            "Color",style.Color(solverIndex,:), ...
            "Marker",style.Marker(solverIndex), ...
            "MarkerSize",markerSize,"MarkerFaceColor","w", ...
            "LineWidth",lineWidth,"DisplayName",solver);
    end
    set(ax,"XScale","log");
    if useLogY
        set(ax,"YScale","log");
    else
        set(ax,"YScale","linear");
        ylim(ax,[0 max(ylim(ax))*1.03]);
    end
    xlabel(ax,"Number of active equations");
end

function plotComparisonMetric(ax,results,solvers,metric,style, ...
        lineWidth,markerSize,useLogY)
    hold(ax,"on");
    values = results.(metric);
    for solverIndex = 1:numel(solvers)
        solver = solvers(solverIndex);
        rows = results.Solver == solver & results.Status == "ok";
        plotValues = values(rows);
        if useLogY
            plotValues = max(abs(plotValues),eps);
        end
        data = sortrows(table(results.ActualDOF(rows),plotValues, ...
            'VariableNames',{'DOF','Value'}),'DOF');
        valid = isfinite(data.DOF) & isfinite(data.Value) & ...
            data.DOF > 0 & data.Value > 0;
        plot(ax,data.DOF(valid),data.Value(valid), ...
            "LineStyle",style.LineStyle(solverIndex), ...
            "Color",style.Color(solverIndex,:), ...
            "Marker",style.Marker(solverIndex), ...
            "MarkerSize",markerSize,"MarkerFaceColor","w", ...
            "LineWidth",lineWidth,"DisplayName",solver);
    end
    set(ax,"XScale","log");
    if useLogY
        set(ax,"YScale","log");
    end
    xlabel(ax,"Number of active equations");
end

function setPublicationAxes(ax,fontName,fontSize,axisLineWidth)
    box(ax,"on");
    grid(ax,"on");
    ax.XMinorGrid = "off";
    ax.YMinorGrid = "off";
    ax.GridAlpha = 0.16;
    ax.GridLineStyle = "-";
    set(ax, ...
        "FontName",fontName, ...
        "FontSize",fontSize, ...
        "LineWidth",axisLineWidth, ...
        "TickDir","in", ...
        "TickLength",[0.012 0.012], ...
        "XMinorTick","on", ...
        "YMinorTick","on", ...
        "Layer","top");
    ax.XLabel.FontName = fontName;
    ax.YLabel.FontName = fontName;
    ax.Title.FontName = fontName;
    ax.XLabel.FontSize = fontSize+1;
    ax.YLabel.FontSize = fontSize+1;
    ax.Title.FontSize = fontSize+1;
end

function family = solverFamily(solver)
    if ismember(solver,["CuDSSSPD" "SparseSPD" "ProfileSPD" "BandSPD"])
        family = "SPD";
    elseif solver == "CuDSSSymmetric"
        family = "symmetric indefinite";
    else
        family = "general";
    end
end

function reference = referenceSolver(~)
    reference = "UmfPack";
end

function result = failedResult(targetDOF,solver,message)
    result = statusResult(targetDOF,solver,"failed",message);
end

function result = skippedResult(targetDOF,solver,message)
    result = statusResult(targetDOF,solver,"skipped",message);
end

function result = statusResult(targetDOF,solver,status,message)
    result = emptyResult();
    result.TargetDOF = targetDOF;
    result.Solver = solver;
    result.Family = solverFamily(solver);
    result.ReferenceSolver = referenceSolver(solver);
    result.Status = status;
    result.Message = string(message);
end

function result = emptyResult()
    result = struct( ...
        'TargetDOF',NaN, ...
        'ActualDOF',NaN, ...
        'Nx',NaN, ...
        'Ny',NaN, ...
        'Solver',"", ...
        'Family',"", ...
        'ReferenceSolver',"", ...
        'Status',"", ...
        'ModelBuildSeconds',NaN, ...
        'FirstAnalyzeSeconds',NaN, ...
        'RepeatedAnalyzeSeconds',NaN, ...
        'TotalAnalyzeSeconds',NaN, ...
        'TipUx',NaN, ...
        'TipUy',NaN, ...
        'FirstSpeedup',NaN, ...
        'RepeatedSpeedup',NaN, ...
        'RelativeTipError',NaN, ...
        'Message',"");
end

function [nx,ny,actualDOF] = balancedMesh(targetDOF)
    center = max(1,round(sqrt(targetDOF/2)));
    best = [Inf Inf 1 1];
    for nxCandidate = max(1,center-20):center+20
        estimatedNy = max(1,round(targetDOF/(2*nxCandidate)-1));
        for nyCandidate = max(1,estimatedNy-1):estimatedNy+1
            candidateDOF = 2*nxCandidate*(nyCandidate+1);
            score = [abs(candidateDOF-targetDOF), ...
                abs(nxCandidate-nyCandidate),nxCandidate,nyCandidate];
            changedIndex = find(score ~= best,1);
            if ~isempty(changedIndex) && score(changedIndex) < best(changedIndex)
                best = score;
            end
        end
    end
    nx = best(3);
    ny = best(4);
    actualDOF = 2*nx*(ny+1);
end