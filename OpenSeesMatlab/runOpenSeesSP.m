function [status, output] = runOpenSeesSP(processes, scriptFile, options)
%RUNOPENSEESSP Run a MATLAB model in a new OpenSeesSP MPI job.
%
%   runOpenSeesSP(processes, scriptFile) starts one MATLAB rank and
%   processes-1 native OpenSeesSP workers. The bundled launcher selects the
%   SP backend and discovers the matching MPI runtime without changing the
%   current MATLAB session or its persistent environment.
%
%   runOpenSeesSP(..., MpiExecutable=path) selects a specific MPI launcher.
%   This is useful when several MPI implementations are installed.
%   Figures created by the model are transferred back to this MATLAB
%   session and displayed after the MPI job finishes. Set ShowFigures=false
%   to disable this behavior.
%
%   [status, output] = runOpenSeesSP(...) also returns the child process exit
%   status and its combined console output. A nonzero status raises an error.
%
% Example
% -------
%   runOpenSeesSP(4, ...
%       "examples/parallel_openseessp_nonlinear_pushover.m");

    arguments
        processes (1,1) double ...
            {mustBeInteger, mustBeGreaterThanOrEqual(processes, 2)}
        scriptFile {mustBeTextScalar}
        options.MpiExecutable {mustBeTextScalar} = ""
        options.MatlabExecutable {mustBeTextScalar} = ""
        options.Echo (1,1) logical = true
        options.ShowFigures (1,1) logical = true
    end

    scriptPath = localResolveScript(scriptFile);
    toolboxDirectory = fileparts(mfilename("fullpath"));
    nexusDirectory = fullfile(toolboxDirectory, "+ops", "OpenSeesNexus");

    matlabExecutable = string(options.MatlabExecutable);
    if strlength(matlabExecutable) == 0
        if ispc
            matlabExecutable = fullfile(matlabroot, "bin", "matlab.exe");
        else
            matlabExecutable = fullfile(matlabroot, "bin", "matlab");
        end
    end
    assert(isfile(matlabExecutable), ...
        "OpenSeesMatlab:SPMatlabMissing", ...
        "MATLAB executable not found: %s", matlabExecutable);

    figureDirectory = "";
    if options.ShowFigures
        figureDirectory = string(tempname);
        [created, message] = mkdir(figureDirectory);
        assert(created, "OpenSeesMatlab:SPFigureDirectory", ...
            "Unable to create the temporary figure directory: %s", message);
        figureCleanup = onCleanup(@() localDeleteFigures(figureDirectory));
    end

    if ispc
        launcher = fullfile(nexusDirectory, "OpenSeesSPMatlab.ps1");
        assert(isfile(launcher), ...
            "OpenSeesMatlab:SPLauncherMissing", ...
            "OpenSeesSP launcher not found: %s", launcher);

        systemRoot = string(getenv("SystemRoot"));
        powershell = fullfile(systemRoot, "System32", ...
            "WindowsPowerShell", "v1.0", "powershell.exe");
        if ~isfile(powershell)
            powershell = "powershell.exe";
        end

        command = localWindowsQuote(powershell) + ...
            " -NoProfile -ExecutionPolicy Bypass -File " + ...
            localWindowsQuote(launcher) + " " + string(processes) + " " + ...
            localWindowsQuote(scriptPath) + " -MatlabExecutable " + ...
            localWindowsQuote(matlabExecutable);

        mpiExecutable = string(options.MpiExecutable);
        if strlength(mpiExecutable) > 0
            assert(isfile(mpiExecutable), ...
                "OpenSeesMatlab:SPMpiMissing", ...
                "MPI executable not found: %s", mpiExecutable);
            command = command + " -MpiExecutable " + ...
                localWindowsQuote(mpiExecutable);
        end
        if strlength(figureDirectory) > 0
            command = command + " -FigureDirectory " + ...
                localWindowsQuote(figureDirectory);
        end
    else
        launcher = fullfile(nexusDirectory, "OpenSeesSPMatlab.sh");
        assert(isfile(launcher), ...
            "OpenSeesMatlab:SPLauncherMissing", ...
            "OpenSeesSP launcher not found: %s", launcher);

        command = "OPENSEES_MATLAB_EXECUTABLE=" + ...
            localShellQuote(matlabExecutable) + " ";
        mpiExecutable = string(options.MpiExecutable);
        if strlength(mpiExecutable) > 0
            assert(isfile(mpiExecutable), ...
                "OpenSeesMatlab:SPMpiMissing", ...
                "MPI executable not found: %s", mpiExecutable);
            command = command + "OPENSEES_MPIEXEC=" + ...
                localShellQuote(mpiExecutable) + " ";
        end
        if strlength(figureDirectory) > 0
            command = command + "OPENSEES_MATLAB_FIGURE_DIRECTORY=" + ...
                localShellQuote(figureDirectory) + " ";
        end
        command = command + localShellQuote(launcher) + " " + ...
            string(processes) + " " + localShellQuote(scriptPath);
    end

    if options.Echo
        [status, output] = system(command, "-echo");
    else
        [status, output] = system(command);
    end
    if status ~= 0
        error("OpenSeesMatlab:SPRunFailed", ...
            "OpenSeesSP exited with status %d.\n%s", status, output);
    end
    if strlength(figureDirectory) > 0
        localOpenFigures(figureDirectory);
    end
    clear figureCleanup
end

function localOpenFigures(figureDirectory)
    figureFiles = dir(fullfile(figureDirectory, "*.fig"));
    [~, order] = sort({figureFiles.name});
    for index = order
        openfig(fullfile(figureFiles(index).folder, ...
            figureFiles(index).name), "new", "visible");
    end
    if ~isempty(figureFiles)
        drawnow;
    end
end

function localDeleteFigures(figureDirectory)
    if ~isfolder(figureDirectory)
        return
    end
    figureFiles = dir(fullfile(figureDirectory, "*.fig"));
    for index = 1:numel(figureFiles)
        delete(fullfile(figureFiles(index).folder, figureFiles(index).name));
    end
    rmdir(figureDirectory);
end

function scriptPath = localResolveScript(scriptFile)
    scriptFile = string(scriptFile);
    assert(strlength(scriptFile) > 0 && ...
        ~contains(scriptFile, ["*", "?"]), ...
        "OpenSeesMatlab:InvalidSPScript", ...
        "scriptFile must name one MATLAB file without wildcards.");

    scriptInfo = dir(scriptFile);
    if isempty(scriptInfo)
        located = string(which(scriptFile));
        if strlength(located) > 0
            scriptInfo = dir(located);
        end
    end
    assert(isscalar(scriptInfo) && ~scriptInfo.isdir, ...
        "OpenSeesMatlab:SPScriptMissing", ...
        "OpenSeesSP script not found: %s", scriptFile);
    scriptPath = string(fullfile(scriptInfo.folder, scriptInfo.name));
end

function quoted = localWindowsQuote(value)
    value = string(value);
    assert(~contains(value, """"), ...
        "OpenSeesMatlab:InvalidSPPath", ...
        "A launcher path cannot contain a double-quote character: %s", value);
    quoted = """" + value + """";
end

function quoted = localShellQuote(value)
    value = string(value);
    assert(~contains(value, "'"), ...
        "OpenSeesMatlab:InvalidSPPath", ...
        "A launcher path cannot contain an apostrophe: %s", value);
    quoted = "'" + value + "'";
end
