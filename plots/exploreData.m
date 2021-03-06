function [dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts]=exploreData(jobTag,flyName,gmmk,frames,parentHighlightCluster,dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts)

% [dataNorm,cfsData,clusters,posts]=exploreData(jobTag,flyName,gmmk,frames,parentHighlightCluster,dataNorm,cfsData,clusters,posts)
% Plot the raw and prepped data for the given fly
%
% Inputs:
% jobTag [string]: folder where PCA20 GMM results are stored
% flyName [string]: tag for fly whose data we want to load
% gmmk [double]: PCA20 GMM k value for which we plot posteriors and cluster assignments
% frames [NPlotFrames x 1]: frames we want to plot, defaults to entire experiment
% parentHighlightCluster [double]: if non-zero, we show child posterior traces for the given parent cluster
% dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts: if provided this will speed up the render
%
% Outputs:
% dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts: returned so they can be provided to speed up subsequent calls
%
% Figure 5F: exploreData('swRound1','f37_1',72,243000:245000,70,dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts)
% Figure 5G: exploreData('swRound1','f37_1',72,48500:50500,66,dataNorm,cfsData,clusters,mappedClusterMeans,posts,parentPosts)

% Load the given fly's raw and frame-normalized high variance data, expand with zeros for low-variance frames
if ~exist('dataNorm','var')
    dataNorm=loadFlyData(flyName);
    NFrames=size(dataNorm,1);
    hvfnData=loadHighVarFNData(flyName);
    cfsData=zeros(NFrames,size(hvfnData,2));
    iHighVarFrames=loadVarThreshold(flyName);
    cfsData(iHighVarFrames,:)=hvfnData;

    % Load our GMM model and compute posterior probabilities
    vars=load(sprintf('~/results/%s/%s_pca20gmmswmapped_%s_%d.mat',jobTag,jobTag,flyName,gmmk));
    gmm=vars.gmm;
    mappedClusterMeans=vars.mappedClusterMeans;
    hvclusters=vars.finalClusters;
    clusters=expandClusters(flyName,hvclusters,true);
    cfspcData=loadCFSPCData(flyName);
    NHighVarFrames=size(cfspcData,1);
    hvposts=gmm.posterior(cfspcData);
    
    % Combine posterior probabilities which map to the same cluster
    uniqueMappedClusterMeans=unique(mappedClusterMeans);
    mappedK=length(uniqueMappedClusterMeans);
    assert(max(clusters)<=length(uniqueMappedClusterMeans));
    hvparentPosts=zeros(NHighVarFrames,mappedK);
    for iParent=1:length(uniqueMappedClusterMeans)
        % Find child clusters which map to this parent cluster
        parentCluster=uniqueMappedClusterMeans(iParent);
        childClusters=find(mappedClusterMeans==parentCluster);
        hvparentPosts(:,iParent)=sum(hvposts(:,childClusters),2); %#ok<FNDSB>
    end
    
    posts=zeros(NFrames,gmm.NumComponents);
    posts(iHighVarFrames,:)=hvposts;
    parentPosts=zeros(NFrames,gmmk);
    parentPosts(iHighVarFrames,:)=hvparentPosts;
end

if ~exist('frames','var') || isempty(frames)
    frames=1:size(dataNorm,1);
end

% Prepare color assignments for each cluster
if gmmk < 8
    idx_frames_colors=jet(gmmk);
else
    idx_frames_colors=colorcube(gmmk);
end

% Plot fly data
hfigure=figure;
ax=[];
ax(1)=axes();
plotFlyData(flyName,dataNorm,cfsData,frames,ax(1));
title(ax(1),sprintf('%s frames %d-%d',flyName,min(frames),max(frames)));

% Plot posteriors
ax(2)=axes();
hold on;
for iCluster=1:gmmk
    plot(frames,parentPosts(frames,iCluster),'Color',idx_frames_colors(iCluster,:));
end
% Plot child posteriors if necessary
if parentHighlightCluster>0
    uniqueMappedClusterMeans=unique(mappedClusterMeans);
    assert(max(clusters)<=length(uniqueMappedClusterMeans));
    expandedParentCluster=uniqueMappedClusterMeans(parentHighlightCluster);
    childClusters=find(mappedClusterMeans==expandedParentCluster);
    for childCluster=childClusters
        plot(frames,posts(frames,childCluster),'Color',[.5 .5 .5],'LineWidth',1,'LineStyle',':');
    end
end
title(ax(2),'PCA_2_0 GMM posterior probabilities');

% Plot cluster assignments
ax(3)=axes();
ylim([0 1]);
set(gca,'YTick',[]);
hassignments=0;
title(ax(3),sprintf('k=%d assignments',gmmk));

% Link axes, zoom horizontally only, do this before setting up highlights so we can override the zoom/pan callbacks
setFigureZoomMode(hfigure, 'h');
setIntegralXAxisLabels(ax);
linkaxes(ax,'x');

% Initialize our highlight, update on zoom/pan. Delete highlights before zoom/pan to avoid rendering them offscreen
%hhighlights=[0 0];
%updateHighlight(true);
%updateHighlight(false);
set(zoom(hfigure), 'ActionPostCallback', @zoomPanPostCallback);
set(pan(hfigure), 'ActionPostCallback', @zoomPanPostCallback);

% Update our axis layout on figure size changes
set(gcf,'ResizeFcn',@updateLayout);

    function updateAssignments()
        % Update bars for our cluster assignments
        
        % Remove old frames if we have them
        if hassignments > 0
            delete(hassignments);
            hassignments=0;
        end
    
        % Plot color bars for cluster assignments if we're sufficiently zoomed in
        xlims=xlim(ax(1));
        minFrame=max(floor(xlims(1)),min(frames));
        maxFrame=min(ceil(xlims(2)),max(frames));
        NVisibleFrames=length(minFrame:maxFrame);
        if NVisibleFrames < 100000
            xs=zeros(NVisibleFrames,1);
            ys=zeros(NVisibleFrames,1);
            colors=zeros(NVisibleFrames,3);
            ylims=ylim(ax(3));
            yBlock=(ylims(2)-ylims(1))/5;
            yMin=ylims(1) + yBlock;
            yHeight=yBlock*3;
            for iFrame=1:NVisibleFrames
                frame=minFrame+iFrame-1;
                xs(iFrame)=frame;
                ys(iFrame)=yMin;
                assignment=clusters(frame);
                if assignment==0
                    colors(iFrame,:)=[1 1 1];
                else
                    colors(iFrame,:)=idx_frames_colors(assignment,:);
                end
            end
            xWidth=0.8; % don't shade the entire frame so we can see frame boundaries
            axes(ax(3));
            hassignments=patchRects(xs,ys,xWidth,yHeight,colors);
        end
    end

	function updateLayout(~,~)
		% Make bottom axes smaller, be sure to line up bottom axes with top ones horizontally
		leftPercent=.80;
		bottomPercent1=.12;
		bottomPercent2=.12;
        bottomTotalPercent=bottomPercent1+bottomPercent2;

        set(ax(1),'OuterPosition',[0 bottomTotalPercent leftPercent 1-bottomTotalPercent]);
		ax1Pos=get(ax(1),'Position');

        set(ax(2),'OuterPosition',[0 bottomPercent1 leftPercent bottomPercent2]);
		ax2Pos=get(ax(2),'Position');
        if ax2Pos(4) > 0
			set(ax(2),'Position',[ax1Pos(1) ax2Pos(2) ax1Pos(3) ax2Pos(4)]);
        end
        
        set(ax(3),'OuterPosition',[0 0 leftPercent bottomPercent2]);
		ax3Pos=get(ax(3),'Position');
		if ax3Pos(4) > 0
			set(ax(3),'Position',[ax1Pos(1) ax3Pos(2) ax1Pos(3) ax3Pos(4)]);
		end
		
		% Update our plot to match the visible frames, also update axis labels
        updateAssignments();
		%updateHighlights();
		setIntegralXAxisLabels(hfigure, 'update');
    end

	function zoomPanPostCallback(~,~)
        
		%deleteHighlights();
		% Update our patches and axis labels after zoom/pan
        updateAssignments();
		%updateHighlights();
		setIntegralXAxisLabels(hfigure, 'update');
	end

% Initialize layout
updateLayout();

end
