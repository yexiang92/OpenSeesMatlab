classdef MVLEMGeometry
    %MVLEMGEOMETRY Geometry helpers for MVLEM macro-fiber lines.

    methods (Static)
        function [V,E] = internalLines(P,cells,fiberWidths,fiberCounts)
            V=zeros(0,3); E=zeros(0,2);
            if nargin<3,fiberWidths=[];end
            if nargin<4,fiberCounts=[];end
            for e=1:size(cells,1)
                ids=plotter.polyscope.MVLEMGeometry.quadIds(P,cells(e,:));
                if isempty(ids),continue;end
                fw=plotter.polyscope.MVLEMGeometry.widthsForElement( ...
                    fiberWidths,fiberCounts,e);
                if numel(fw)<2,continue;end
                xi=cumsum(fw(1:end-1))/sum(fw);
                q=P(ids,:);
                for j=1:numel(xi)
                    a=xi(j);
                    lower=(1-a)*q(1,:)+a*q(2,:);
                    upper=(1-a)*q(4,:)+a*q(3,:);
                    i0=size(V,1);V=[V;lower;upper]; %#ok<AGROW>
                    E=[E;i0+[1 2]]; %#ok<AGROW>
                end
            end
        end

        function fw=widthsForElement(fiberWidths,fiberCounts,e)
            fw=[];
            if ~isempty(fiberWidths)
                if iscell(fiberWidths)
                    fw=double(fiberWidths{min(e,numel(fiberWidths))}(:).');
                elseif isvector(fiberWidths)
                    fw=double(fiberWidths(:).');
                else
                    row=double(fiberWidths(min(e,size(fiberWidths,1)),:));
                    fw=row(isfinite(row)&row>0);
                end
            end
            if isempty(fw)
                n=0;
                if ~isempty(fiberCounts),n=double(fiberCounts(min(e,numel(fiberCounts))));end
                if n>0,fw=ones(1,round(n));end
            end
            fw=fw(isfinite(fw)&fw>0);
        end

        function ids=quadIds(P,row)
            row=double(row);row=row(isfinite(row));ids=[];
            if numel(row)>=5&&round(row(1))==4,ids=round(row(2:5));
            elseif numel(row)>=4,ids=round(row(1:4));end
            if numel(ids)~=4||any(ids<1|ids>size(P,1)),ids=[];return;end
            q=P(ids,:);l0=sum(vecnorm(q([2 3 4 1],:)-q,2,2));
            alt=ids([1 2 4 3]);qa=P(alt,:);
            l1=sum(vecnorm(qa([2 3 4 1],:)-qa,2,2));
            if l1+eps(max(l0,l1))<l0,ids=alt;end
        end
    end
end
