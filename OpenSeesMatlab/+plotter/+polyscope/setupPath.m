function added = setupPath(polyscopeMatlabRoot)
%SETUPPATH Ensure the polyscope-matlab MATLAB package is on the path.
%
%   plotter.polyscope.setupPath() adds the local vendor directory containing
%   +polyscope to the MATLAB path. It is safe to call multiple times.
%
%   plotter.polyscope.setupPath(polyscopeMatlabRoot) uses an explicit root
%   directory for an external polyscope-matlab installation.

    if nargin >= 1 && ~isempty(polyscopeMatlabRoot)
        packageParent = resolvePackageParent_(char(string(polyscopeMatlabRoot)));
    else
        packageParent = fullfile(fileparts(mfilename('fullpath')), 'vendor');
    end

    packageDir = fullfile(packageParent, '+polyscope');
    if ~isfolder(packageDir) || ~isfile(fullfile(packageDir, 'Polyscope.m'))
        error('plotter:polyscope:setupPath:NotFound', ...
            'Cannot find polyscope MATLAB package at "%s".', packageDir);
    end

    pathParts = split(string(path), pathsep);
    if ~any(strcmpi(pathParts, string(packageParent)))
        addpath(packageParent);
        added = true;
    else
        added = false;
    end
end

function packageParent = resolvePackageParent_(rootDir)
    if isfolder(fullfile(rootDir, '+polyscope'))
        packageParent = rootDir;
    elseif isfolder(fullfile(rootDir, 'src', 'matlab', '+polyscope'))
        packageParent = fullfile(rootDir, 'src', 'matlab');
    else
        packageParent = rootDir;
    end
end
