function runSPModel(scriptFile)
%RUNSPMODEL Execute one OpenSeesSP script and release the native runtime.
%   This function is used by the platform launchers. The nested execution
%   scope ensures objects created by the user script are destroyed before
%   the SP MEX module shuts down its actor workers.

    scriptError = executeScript(scriptFile);
    if isempty(scriptError)
        saveFigures();
    end
    cleanupError = [];
    try
        OpenSeesMATLABSP("wipe");
    catch exception
        cleanupError = exception;
    end
    clear OpenSeesMATLABSP;

    if ~isempty(scriptError)
        rethrow(scriptError);
    end
    if ~isempty(cleanupError)
        rethrow(cleanupError);
    end
end

function saveFigures()
% Persist child-process figures for a calling MATLAB session when requested.
    figureDirectory = string(getenv("OPENSEES_MATLAB_FIGURE_DIRECTORY"));
    if strlength(figureDirectory) == 0
        return
    end
    assert(isfolder(figureDirectory), ...
        "OpenSeesMatlab:SPFigureDirectory", ...
        "The SP figure directory does not exist: %s", figureDirectory);

    figures = findall(groot, "Type", "figure");
    figures = flip(figures);
    for index = 1:numel(figures)
        figureFile = fullfile(figureDirectory, ...
            sprintf("figure-%03d.fig", index));
        savefig(figures(index), figureFile);
    end
end

function scriptError = executeScript(scriptFile)
% Keep variables created by RUN, including OpenSeesNexus objects, local.
    try
        run(scriptFile);
    catch exception
        scriptError = exception;
        return
    end
    % Assign after RUN because a normal script may begin with CLEAR.
    scriptError = [];
end
