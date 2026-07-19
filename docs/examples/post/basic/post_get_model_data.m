%% *Retrieval Model and Eigenvalue Analysis Data*
% This live script is written as a guided walkthrough for a post-processing 
% workflow. It focuses on retrieving, organizing, and visualizing model or response 
% data after an OpenSees analysis. Read the text cells first, then run each code 
% cell in order so that the variables, model state, and recorded results are available 
% for the later sections.

clc; clear; close all;
% Model Data
% First, instantiate the OpenSeesMatlab interface class. This class provides 
% native OpenSees commands, as well as additional visualization, pre/post-processing, 
% and utility methods.

opsMAT = OpenSeesMatlab();
ops = opsMAT.opensees;
%% 
% For example, the |tool| property provides a function |loadExamples| to run 
% some built-in models. Of course, you can run your own model; the built-in model 
% is used here for demonstration purposes only.

opsMAT.utils.loadExamples("Frame3D");
% or your model here
%% 
% We can visualize the model using the |plotModel| function in the |vis| attribute.

figure;
h = opsMAT.vis.plotModel();
%% 
% We can retrieve data from the current model, which returns a nested |struct|. 
% You can view the data using MATLAB's workspace variables.

modelData = opsMAT.post.getModelData();
disp(modelData)
%% 
% Finally, we can print the information for each field.

S = modelData;

stack = {{'S', S}};

while ~isempty(stack)
    item = stack{end};
    stack(end) = [];

    name = item{1};
    val  = item{2};

    if isstruct(val)
        fns = fieldnames(val);
        for i = numel(fns):-1:1
            f = fns{i};
            stack{end+1} = {sprintf('%s.%s', name, f), val.(f)};
        end
    else
        sz = strjoin(string(size(val)), 'x');
        fprintf('%s : %s\n', name, sz);
    end
end
% Eigen Data
% First, we need to save the eigenvalue analysis results data for future reuse.

tag = 1;
opsMAT.post.saveEigenData(tag, 10, solver='-genBandArpack');
%% 
% Then, data is retrieved from the file, returning a nested |structure| that 
% stores the various results of the eigenvalue analysis.

eigenData = opsMAT.post.getEigenData(odbTag=tag);
disp(eigenData)
%% 
% Using this data, we can visualize the first modal shapes.

figure;
opsMAT.vis.plotEigen(6, eigenData);
axis off
S = eigenData;

stack = {{'S', S}};

while ~isempty(stack)
    item = stack{end};
    stack(end) = [];

    name = item{1};
    val  = item{2};

    if isstruct(val)
        fns = fieldnames(val);
        for i = numel(fns):-1:1
            f = fns{i};
            stack{end+1} = {sprintf('%s.%s', name, f), val.(f)};
        end
    else
        sz = strjoin(string(size(val)), 'x');
        fprintf('%s : %s\n', name, sz);
    end
end
%% 
% 
% 
% Let's look at the period of each mode.

S.ModalProps.raw.eigenPeriod
%% 
% Let's look at the *cumulative participation mass ratio (%)* in each direction.

S.ModalProps.raw.partiMassRatiosCumuMX
S.ModalProps.raw.partiMassRatiosCumuMY
S.ModalProps.raw.partiMassRatiosCumuMZ
S.ModalProps.raw.partiMassRatiosCumuRMX
S.ModalProps.raw.partiMassRatiosCumuRMY
S.ModalProps.raw.partiMassRatiosCumuRMZ
%% 
%