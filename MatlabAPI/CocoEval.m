classdef CocoEval < handle
    % Interface for evaluating detection on the Microsoft COCO dataset.
    %
    % The usage for CocoEval is as follows:
    %  cocoGt=..., cocoDt=...             % load dataset and results
    %  E = CocoEval(cocoGt,cocoDt);       % initialize CocoEval object
    %  E.params.recThresholds = ...;      % set parameters as desired
    %  E.evaluate();                      % run per image evaluation
    %  disp( E.evalImgs )                 % inspect per image results
    %  E.accumulate();                    % accumulate per image results
    %  disp( E.eval )                     % inspect accumulated results
    %  E.summarize();                     % display summary metrics of results
    %  E.analyze();                       % plot detailed analysis of errors (slow)
    % For example usage see evalDemo.m and http://mscoco.org/.
    %
    % The evaluation parameters are as follows (defaults in brackets):
    %  imgIds           - [all] N img ids to use for evaluation
    %  catIds           - [all] K cat ids to use for evaluation
    %  iouThresholds    - [.5:.05:.95] T=10 IoU thresholds for evaluation
    %  recThresholds    - [0:.01:1] R=101 recall thresholds for evaluation
    %  areaRange        - [...] A=4 object area ranges for evaluation
    %  maxDetections    - [1 10 100] M=3 thresholds on max detections per image
    %  iouType          - ['segm'] set iouType to 'segm', 'bbox' or 'keypoints'
    %  useCats          - [1] if true use category labels for evaluation
    % Note: iouType replaced the now DEPRECATED useSegm parameter.
    % Note: if useCats=0 category labels are ignored as in proposal scoring.
    % Note: by default areaRange=[0 1e5; 0 32; 32 96; 96 1e5].^2. These A=4
    % settings correspond to all, small, medium, and large objects, resp.
    %
    % evaluate(): evaluates detections on every image and setting and concats
    % the results into the KxA struct array "evalImgs" with fields:
    %  dtIds      - [1xD] id for each of the D detections (dt)
    %  gtIds      - [1xG] id for each of the G ground truths (gt)
    %  dtImgIds   - [1xD] image id for each dt
    %  gtImgIds   - [1xG] image id for each gt
    %  dtMatches  - [TxD] matching gt id at each IoU or 0
    %  gtMatches  - [TxG] matching dt id at each IoU or 0
    %  dtScores   - [1xD] confidence of each dt
    %  dtIgnore   - [TxD] ignore flag for each dt at each IoU
    %  gtIgnore   - [1xG] ignore flag for each gt
    %
    % accumulate(): accumulates the per-image, per-category evaluation
    % results in "evalImgs" into the struct "eval" with fields:
    %  params     - parameters used for evaluation
    %  date       - date evaluation was performed
    %  counts     - [T,R,K,A,M] parameter dimensions (see above)
    %  precision  - [TxRxKxAxM] precision for every evaluation setting
    %  recall     - [TxKxAxM] max recall for every evaluation setting
    % Note: precision and recall==-1 for settings with no gt objects.
    %
    % summarize(): computes and displays 12 summary metrics based on the
    % "eval" struct. Note that summarize() assumes the evaluation was
    % computed with certain default params (including default area ranges),
    % if not, the display may show NaN outputs for certain metrics. Results
    % of summarize() are stored in a 12 element vector "stats".
    %
    % analyze(): generates plots with detailed breakdown of false positives.
    % Inspired by "Diagnosing Error in Object Detectors" by D. Hoiem et al.
    % Generates one plot per category (80), supercategory (12), and overall
    % (1), multiplied by 4 scales, for a total of (80+12+1)*4=372 plots. Each
    % plot contains a series of precision recall curves where each PR curve
    % is guaranteed to be strictly higher than the previous as the evaluation
    % setting becomes more permissive. These plots give insight into errors
    % made by a detector. A more detailed description is given at mscoco.org.
    % Note: analyze() is quite slow as it calls evaluate() multiple times.
    % Note: if pdfcrop is not found then set pdfcrop path appropriately e.g.:
    %   setenv('PATH',[getenv('PATH') ':/Library/TeX/texbin/']);
    %
    % See also CocoApi, MaskApi, cocoDemo, evalDemo
    %
    % Microsoft COCO Toolbox.      version 2.0
    % Data, paper, and tutorials available at:  http://mscoco.org/
    % Code written by Piotr Dollar and Tsung-Yi Lin, 2015.
    % Licensed under the Simplified BSD License [see coco/license.txt]
    
    properties
        cocoGt      % ground truth COCO API
        cocoDt      % detections COCO API
        params      % evaluation parameters
        evalImgs    % per-image per-category evaluation results
        eval        % accumulated evaluation results
        stats       % evaluation summary statistics
    end
    
    methods
        function ev = CocoEval( cocoGt, cocoDt, iouType )
            % Initialize CocoEval using coco APIs for gt and dt.
            if(nargin>0)
                ev.cocoGt = cocoGt; 
                ev.params.imgIds = sort(ev.cocoGt.getImgIds());
                ev.params.catIds = sort(ev.cocoGt.getCatIds());
            end
            if(nargin>1), ev.cocoDt = cocoDt; end
            if(nargin<3), iouType='segm'; end
            ev.params.iouThresholds = .5:.05:.95;
            ev.params.recThresholds = 0:.01:1;
            if( any(strcmp(iouType,{'bbox','segm'})) )
                ev.params.areaRange = [0 1e5; 0 32; 32 96; 96 1e5].^2;
                ev.params.maxDetections = [1 10 100];
            elseif( strcmp(iouType,'keypoints') )
                ev.params.areaRange = [0 1e5; 32 96; 96 1e5].^2;
                ev.params.maxDetections = 20;
            else
                error('unknown iouType: %s',iouType);
            end
            ev.params.iouType = iouType;
            ev.params.useCats = 1;
        end
        
        function evaluate( ev )
            % Run per image evaluation on given images.
            fprintf('Running per image evaluation...      '); 
            clk=clock;
            parameters=ev.params; 
            if(~parameters.useCats)
                parameters.catIds=1; 
            end
            t={'bbox','segm'};
            if(isfield(parameters,'useSegm'))
                parameters.iouType=t{parameters.useSegm+1};
            end
            parameters.imgIds=unique(parameters.imgIds);
            parameters.catIds=unique(parameters.catIds);
            ev.params=parameters;
            numImage=length(parameters.imgIds);
            numCategory=length(parameters.catIds);
            numAreaRange=size(parameters.areaRange,1);
            [numGt,idxGt]=getAnnCounts(ev.cocoGt,parameters.imgIds,parameters.catIds,parameters.useCats);
            [numDt,idxDt]=getAnnCounts(ev.cocoDt,parameters.imgIds,parameters.catIds,parameters.useCats);
            [category_idx,img_idx]=ndgrid(1:numCategory,1:numImage);
            ev.evalImgs=cell(numImage,numCategory,numAreaRange);
            for i=1:numCategory*numImage
                if(numGt(i)==0 && numDt(i)==0)
                    continue;
                end
                gt=ev.cocoGt.data.annotations(idxGt(i):idxGt(i)+numGt(i)-1);
                dt=ev.cocoDt.data.annotations(idxDt(i):idxDt(i)+numDt(i)-1);
                if(~isfield(gt,'ignore'))
                    [gt(:).ignore]=deal(0); 
                end
                if( strcmp(parameters.iouType,'segm') )
                    im=ev.cocoGt.loadImgs(parameters.imgIds(img_idx(i))); 
                    h=im.height; 
                    w=im.width;
                    for g=1:numGt(i) 
                        s=gt(g).segmentation; 
                        if(~isstruct(s))
                            gt(g).segmentation=MaskApi.frPoly(s,h,w); 
                        end
                    end
                    f='segmentation'; 
                    if(isempty(dt))
                        [dt(:).(f)]=deal(); 
                    end
                    if(~isfield(dt,f))
                        s=MaskApi.frBbox(cat(1,dt.bbox),h,w);
                        for dt_idx=1:numDt(i)
                            dt(dt_idx).(f)=s(dt_idx); 
                        end
                    end
                elseif( strcmp(parameters.iouType,'bbox') )
                    f='bbox'; 
                    if(isempty(dt))
                        [dt(:).(f)]=deal(); 
                    end
                    if(~isfield(dt,f))
                        s=MaskApi.toBbox([dt.segmentation]);
                        for dt_idx=1:numDt(i)
                            dt(dt_idx).(f)=s(dt_idx,:); 
                        end
                    end
                elseif( strcmp(parameters.iouType,'keypoints') )
                    gtIg=[gt.ignore]|[gt.num_keypoints]==0;
                    for g=1:numGt(i)
                        gt(g).ignore=gtIg(g); 
                    end
                else
                    error('unknown iouType: %s',parameters.iouType);
                end
                parameters_copy=parameters; 
                parameters_copy.imgIds=parameters.imgIds(img_idx(i)); 
                parameters_copy.maxDetections=max(parameters.maxDetections);
                for areaRange_idx=1:numAreaRange
                    parameters_copy.areaRange=parameters.areaRange(areaRange_idx,:);
                    ev.evalImgs{img_idx(i),category_idx(i),areaRange_idx}=CocoEval.evaluateImg(gt,dt,parameters_copy); 
                end
            end
            evaluation_results=ev.evalImgs;
            nms={'dtIds','gtIds','dtImgIds','gtImgIds',...
                'dtMatches','gtMatches','dtScores','dtIgnore','gtIgnore'};
            ev.evalImgs=repmat(cell2struct(cell(9,1),nms,1),numCategory,numAreaRange);
            for category_idx=1:numCategory
                % for every category, find indices of all images of that
                % category that has at least 1 ground truth or 1 detection
                img_idx=find(numGt(category_idx,:)>0|numDt(category_idx,:)>0);
                if(~isempty(img_idx))
                    for areaRange_idx=1:numAreaRange
                        E0=[evaluation_results{img_idx,category_idx,areaRange_idx}]; 
                        for k=1:9
                            ev.evalImgs(category_idx,areaRange_idx).(nms{k})=[E0{k:9:end}]; 
                        end
                    end
                end
            end
            fprintf('DONE (t=%0.2fs).\n',etime(clock,clk));
            
            function [ns,is] = getAnnCounts( coco, imgIds, catIds, useCats )
                % Return ann counts and indices for given imgIds and catIds.
                category_ids=sort(coco.getCatIds()); 
                [~,a]=ismember(coco.inds.annCatIds,category_ids);
                image_ids=sort(coco.getImgIds()); 
                [~,b]=ismember(coco.inds.annImgIds,image_ids);
                if(~useCats)
                    a(:)=1; 
                    category_ids=1; 
                end
                ns=zeros(length(category_ids),length(image_ids));
                for ind=1:length(a)
                    ns(a(ind),b(ind))=ns(a(ind),b(ind))+1; 
                end
                is=reshape(cumsum([0 ns(1:end-1)])+1,size(ns));
                [~,a]=ismember(catIds,category_ids); 
                [~,b]=ismember(imgIds,image_ids);
                ns=ns(a,b); 
                is=is(a,b);
            end
        end
        
        function accumulate( ev )
            % Accumulate per image evaluation results.
            fprintf('Accumulating evaluation results...   '); 
            clk=clock;
            if(isempty(ev.evalImgs))
                error('Please run evaluate() first'); 
            end
            parameters=ev.params; 
            T=length(parameters.iouThresholds); 
            R=length(parameters.recThresholds);
            K=length(parameters.catIds); 
            A=size(parameters.areaRange,1); 
            M=length(parameters.maxDetections);
            precision=-ones(T,R,K,A,M); 
            recall=-ones(T,K,A,M);
            [category_idx,area_range_idx,max_det_idx]=ndgrid(1:K,1:A,1:M);
            for k=1:K*A*M
                % ev.evalImgs has [category_idx by areaRange_idx] number of
                % structs that contain nms={'dtIds','gtIds','dtImgIds','gtImgIds',...
                % 'dtMatches','gtMatches','dtScores','dtIgnore','gtIgnore'};
                E=ev.evalImgs(category_idx(k),area_range_idx(k)); 
                dt_img_ids=E.dtImgIds; 
                max_dt=parameters.maxDetections(max_det_idx(k));
                % nnz() returns number of nonzero elements, so 
                % np = number of gt not ignored. 
                gt_not_ignored=nnz(~E.gtIgnore); 
                % if all gt are ignored then move on to the next setting
                if(gt_not_ignored==0)
                    continue; 
                end
                t=[0 find(diff(dt_img_ids)) length(dt_img_ids)]; 
                t=t(2:end)-t(1:end-1); 
                dt_img_ids=dt_img_ids<0;
                r=0; 
                for i=1:length(t)
                    dt_img_ids(r+1:r+min(max_dt,t(i)))=1; 
                    r=r+t(i); 
                end
                % dtMatches has the dimension of (numIouThresholds, numDetection)
                % dt_matches is therefore detection of different iou
                % threshold of all images found in ev of a particular
                % category, area range, and maximum detections allowed
                dt_matches=E.dtMatches(:,dt_img_ids); 
                dt_Ignore=E.dtIgnore(:,dt_img_ids);
                % sort detections by confidence score; note that the
                % sorting is done separately on every column, i.e. the
                % detections of every image is sorted based on its own
                % score rankings, from highest to lowest score
                [~,o]=sort(E.dtScores(dt_img_ids),'descend');
                % reshape dt_matches so that it is of size (number of iou
                % thresholds, number of images)
                true_positive=reshape( dt_matches & ~dt_Ignore,T,[]);
                true_positive=true_positive(:,o);
                false_positive=reshape(~dt_matches & ~dt_Ignore,T,[]); 
                false_positive=false_positive(:,o);
                % note that even though precision is defined to have 5
                % dimensions, this way we only specifying the first 3.
                % If k goes over the limit of the 3rd dimension, it will be
                % modulated on the 3rd and increments the 4th by 1. 
                precision(:,:,k)=0; 
                % same dimension logistics for recall (4 dimensions)
                recall(:,k)=0;
                for t=1:T % T = length(iouThresholds) = 10; iouThresholds = [.5:.05:.95];
                    % tp and fp at each score cutoff
                    tp=cumsum(true_positive(t,:)); 
                    fp=cumsum(false_positive(t,:)); 
                    num_tp=length(tp);
                    % np = number of gt not ignored. rc = recall array at
                    rc=tp/gt_not_ignored; 
                    pr=tp./(fp+tp); % each score cutoff
                    
                    q=zeros(1,R); % R = length(recThresholds) = 101; recThresholds = [0:.01:1]; 
                    recall_thresholds=parameters.recThresholds;
                    if(num_tp==0 || tp(num_tp)==0)
                        continue; 
                    end
                    recall(t,k)=rc(end);
                    % make precision-recall curve monotonically decreasing
                    for i=num_tp-1:-1:1
                        pr(i)=max(pr(i+1),pr(i)); 
                    end
                    i=1; r=1; s=100;
                    % interpolate precision at 101 recall thresholds
                    while(r<=R && i<=num_tp)
                        if(rc(i)>=recall_thresholds(r))
                            q(r)=pr(i); 
                            r=r+1; 
                        else
                            i=i+1; 
                            if(i+s<=num_tp && rc(i+s)<recall_thresholds(r))
                                i=i+s; 
                            end
                        end
                    end
                    % a precision-recall pair list for that iou threshold
                    precision(t,:,k)=q; 
                end
            end
            ev.eval=struct('params',parameters,'date',date,'counts',[T R K A M],...
                'precision',precision,'recall',recall);
            fprintf('DONE (t=%0.2fs).\n',etime(clock,clk));
        end
        
        function summarize( ev )
            % Compute and display summary metrics for evaluation results.
            if(isempty(ev.eval))
                error('Please run accumulate() first'); 
            end
            if( any(strcmp(ev.params.iouType,{'bbox','segm'})) )
                k=100; 
                M={{1,':','all',k},{1,.50,'all',k}, {1,.75,'all',k},...
                    {1,':','small',k}, {1,':','medium',k}, {1,':','large',k},...
                    {0,':','all',1}, {0,':','all',10}, {0,':','all',k},...
                    {0,':','small',k}, {0,':','medium',k}, {0,':','large',k}};
            elseif( strcmp(ev.params.iouType,'keypoints') )
                k=20; 
                M={{1,':','all',k},{1,.50,'all',k}, {1,.75,'all',k},...
                    {1,':','medium',k}, {1,':','large',k},...
                    {0,':','all',k},{0,.50,'all',k}, {0,.75,'all',k},...
                    {0,':','medium',k}, {0,':','large',k}};
            end
            k=length(M); 
            ev.stats=zeros(1,k);
            for s=1:k
                ev.stats(s)=summarize1(M{s}{:}); 
            end
            
            function s = summarize1( ap, iouThr, areaRange, maxDetections )
                p=ev.params; 
                i=iouThr; 
                m=find(p.maxDetections==maxDetections);
                if(i~=':')
                    iStr=sprintf('%.2f     ',i); 
                    i=find(p.iouThresholds==i);
                else
                    iStr=sprintf('%.2f:%.2f',min(p.iouThresholds),max(p.iouThresholds)); 
                end
                as=[0 1e5; 0 32; 32 96; 96 1e5].^2; 
                a=find(areaRange(1)=='asml');
                a=find(p.areaRange(:,1)==as(a,1) & p.areaRange(:,2)==as(a,2));
                if(ap)
                    tStr='Precision (AP)'; 
                    % get precision across all recall thresholds and categories
                    % when iou threshold, area range, and max detection
                    % held constant. 
                    s=ev.eval.precision(i,:,:,a,m); 
                else
                    tStr='Recall    (AR)'; 
                    s=ev.eval.recall(i,:,a,m); 
                end
                fStr=' Average %s @[ IoU=%s | area=%6s | maxDetections=%3i ] = %.3f\n';
                s=mean(s(s>=0)); 
                fprintf(fStr,tStr,iStr,areaRange,maxDetections,s);
            end
        end
        
        function visualize( ev, varargin )
            % Crop detector bbox results after evaluation (fp, tp, or fn).
            %  Preliminary implementation, undocumented. Use at your own risk.
            %  Require's Piotr's Toolbox (https://github.com/pdollar/toolbox/).
            def = { 'imgDir','../images/val2014/', 'outDir','visualize', ...
                'catIds',[], 'areaIds',1:4, 'type',{'tp','fp','fn'}, ...
                'dim',200, 'pad',1.5, 'ds',[10 10 1] };
            p = getPrmDflt(varargin,def,0);
            if(isempty(p.catIds))
                p.catIds=ev.params.catIds; 
            end
            type=p.type; 
            d=p.dim; 
            pad=p.pad; 
            ds=p.ds;
            % recursive call unless performing singleton task
            if(length(p.catIds)>1)
                q=p; 
                for i=1:length(p.catIds)
                    q.catIds=p.catIds(i); 
                    ev.visualize(q); 
                end
                return
            end
            if(length(p.areaIds)>1)
                q=p; 
                for i=1:length(p.areaIds)
                    q.areaIds=p.areaIds(i); 
                    ev.visualize(q); 
                end
                return
            end
            if(iscell(p.type))
                q=p; 
                for i=1:length(p.type)
                    q.type=p.type{i}; 
                    ev.visualize(q); 
                end
                return
            end
            % generate file name for result
            areaNms={'all','small','medium','large'};
            catNm=regexprep(ev.cocoGt.loadCats(p.catIds).name,' ','_');
            fn=sprintf('%s/%s-%s-%s%%03i.jpg',p.outDir,...
                catNm,areaNms{p.areaIds},type); disp(fn);
            if(exist(sprintf(fn,1),'file'))
                return
            end
            % select appropriate gt and dt according to type
            E=ev.evalImgs(p.catIds==ev.params.catIds,p.areaIds);
            E.dtMatches=E.dtMatches(1,:); E=select(E,1,~E.dtIgnore(1,:));
            E.gtMatches=E.gtMatches(1,:); E=select(E,0,~E.gtIgnore(1,:));
            [~,o]=sort(E.dtScores,'descend'); 
            E=select(E,1,o);
            if(strcmp(type,'fn'))
                E=select(E,0,~E.gtMatches); 
                gt=E.gtIds; 
                G=1; 
                D=0;
            elseif(strcmp(type,'tp'))
                E=select(E,1,E.dtMatches>0); 
                dt=E.dtIds; 
                gt=E.dtMatches; 
                G=1; 
                D=1;
            elseif(strcmp(type,'fp'))
                E=select(E,1,~E.dtMatches); 
                dt=E.dtIds; 
                G=0; 
                D=1;
            end
            % load dt, gt, and im and crop region bbs
            if(D)
                is=E.dtImgIds; 
            else
                is=E.gtImgIds; 
            end
            n=min(prod(ds),length(is)); 
            is=ev.cocoGt.loadImgs(is(1:n));
            if(G)
                gt=ev.cocoGt.loadAnns(gt(1:n)); 
                bb=gt; 
            end
            if(D)
                dt=ev.cocoDt.loadAnns(dt(1:n)); 
                bb=dt; 
            end
            if(~n)
                return; 
            end
            bb=cat(1,bb.bbox); 
            bb(:,1:2)=bb(:,1:2)+1;
            r=max(bb(:,3:4),[],2)*pad/d; r=[r r r r];
            bb=bbApply('resize',bbApply('squarify',bb,0),pad,pad);
            % get dt and gt bbs in relative coordinates
            if(G)
                gtBb=cat(1,gt.bbox); 
                gtBb(:,1:2)=gtBb(:,1:2)-bb(:,1:2);
                gtBb=gtBb./r; if(~D), gtBb=[gtBb round([gt(1:n).area])']; 
                end
            end
            if(D)
                dtBb=cat(1,dt.bbox); 
                dtBb(:,1:2)=dtBb(:,1:2)-bb(:,1:2);
                dtBb=dtBb./r; 
                dtBb=[dtBb E.dtScores(1:n)']; 
            end
            % crop image samples appropriately
            ds(3)=ceil(n/prod(ds(1:2))); 
            Is=cell(ds);
            for i=1:n
                I=imread(sprintf('%s/%s',p.imgDir,is(i).file_name));
                I=bbApply('crop',I,bb(i,:),0,[d d]); I=I{1};
                if(D)
                    I=bbApply('embed',I,dtBb(i,:),'col',[0 0 255]); 
                end
                if(G)
                    I=bbApply('embed',I,gtBb(i,:),'col',[0 255 0]); 
                end
                Is{i}=I;
            end
            for i=n+1:prod(ds)
                Is{i}=zeros(d,d,3,'uint8'); 
            end
            I=reshape(cell2mat(permute(Is,[2 1 3])),ds(1)*d,ds(2)*d,3,ds(3));
            for i=1:ds(3)
                imwrite(imresize(I(:,:,:,i),.5),sprintf(fn,i)); 
            end
            % helper function for taking subset of E
            function E = select( E, D, kp )
                fs={'Matches','Ids','ImgIds','Scores'}; 
                pr={'gt','dt'};
                for f=1:3+D
                    fd=[pr{D+1} fs{f}]; 
                    E.(fd)=E.(fd)(kp); 
                end
            end
        end
        
        function analyze( ev )
            % Derek Hoiem style analyis of false positives.
            outDir='./analyze'; 
            if(~exist(outDir,'dir'))
                mkdir(outDir); 
            end
            if(~isfield(ev.cocoGt.data.annotations,'ignore'))
                [ev.cocoGt.data.annotations.ignore]=deal(0); 
            end
            dt=ev.cocoDt; 
            gt=ev.cocoGt; 
            prm=ev.params; 
            rs=prm.recThresholds;
            ev.params.maxDetections=100; 
            catIds=ev.cocoGt.getCatIds();
            % compute precision at different IoU values
            ev.params.catIds=catIds; 
            ev.params.iouThresholds=[.75 .5 .1];
            ev.evaluate(); 
            ev.accumulate(); 
            ps=ev.eval.precision;
            ps(4:7,:,:,:)=0; 
            ev.params.iouThresholds=.1; 
            ev.params.useCats=0;
            for k=1:length(catIds)
                catId=catIds(k);
                nm=ev.cocoGt.loadCats(catId); nm=[nm.supercategory '-' nm.name];
                fprintf('\nAnalyzing %s (%i):\n',nm,k); 
                clk=clock;
                % select detections for single category only
                D=dt.data; A=D.annotations; 
                A=A([A.category_id]==catId);
                D.annotations=A; 
                ev.cocoDt=dt; 
                ev.cocoDt=CocoApi(D);
                % compute precision but ignore superclass confusion
                is=gt.getCatIds('supNms',gt.loadCats(catId).supercategory);
                D=gt.data; 
                A=D.annotations; 
                A=A(ismember([A.category_id],is));
                [A([A.category_id]~=catId).ignore]=deal(1);
                D.annotations=A; 
                ev.cocoGt=CocoApi(D);
                ev.evaluate(); 
                ev.accumulate(); 
                ps(4,:,k,:)=ev.eval.precision;
                % compute precision but ignore any class confusion
                D=gt.data; 
                A=D.annotations;
                [A([A.category_id]~=catId).ignore]=deal(1);
                D.annotations=A; 
                ev.cocoGt=gt; 
                ev.cocoGt.data=D;
                ev.evaluate(); 
                ev.accumulate(); 
                ps(5,:,k,:)=ev.eval.precision;
                % fill in background and false negative errors and plot
                ps(ps==-1)=0; 
                ps(6,:,k,:)=ps(5,:,k,:)>0; 
                ps(7,:,k,:)=1;
                makeplot(rs,ps(:,:,k,:),outDir,nm);
                fprintf('DONE (t=%0.2fs).\n',etime(clock,clk));
            end
            % plot averages over all categories and supercategories
            ev.cocoDt=dt; 
            ev.cocoGt=gt; 
            ev.params=prm;
            fprintf('\n'); 
            makeplot(rs,mean(ps,3),outDir,'overall-all');
            sup={ev.cocoGt.loadCats(catIds).supercategory};
            for k=unique(sup), ps1=mean(ps(:,:,strcmp(sup,k),:),3);
                makeplot(rs,ps1,outDir,['overall-' k{1}]); 
            end
            
            function makeplot( rs, ps, outDir, nm )
                % Plot FP breakdown using area plot.
                fprintf('Plotting results...                  '); 
                t=clock;
                cs=[ones(2,3); .31 .51 .74; .75 .31 .30;
                    .36 .90 .38; .50 .39 .64; 1 .6 0]; 
                m=size(ps,1);
                areaNms={'all','small','medium','large'}; 
                nm0=nm; 
                ps0=ps;
                for a=1:size(ps,4)
                    nm=[nm0 '-' areaNms{a}]; 
                    ps=ps0(:,:,:,a);
                    ap=round(mean(ps,2)*1000); 
                    ds=[ps(1,:); diff(ps)]';
                    ls={'C75','C50','Loc','Sim','Oth','BG','FN'};
                    for i=1:m
                        if(ap(i)==1000)
                            ls{i}=['[1.00] ' ls{i}]; 
                        else
                            ls{i}=sprintf('[.%03i] %s',ap(i),ls{i}); 
                        end
                    end
                    figure(1); 
                    clf; 
                    h=area(rs,ds); 
                    legend(ls,'location','sw');
                    for i=1:m
                        set(h(i),'FaceColor',cs(i,:)); 
                    end
                    title(nm)
                    xlabel('recall'); 
                    ylabel('precision'); 
                    set(gca,'fontsize',20)
                    nm=[outDir '/' regexprep(nm,' ','_')]; 
                    print(nm,'-dpdf')
                    [status,~]=system(['pdfcrop ' nm '.pdf ' nm '.pdf']);
                    if(status>0)
                        warning('pdfcrop not found.'); 
                    end
                end
                fprintf('DONE (t=%0.2fs).\n',etime(clock,t));
            end
        end
    end
    
    methods( Static )
        function e = evaluateImg( gt, detection, params )
            % Run evaluation for a single image and category.
            parameters=params; 
            numIouThresholds=length(parameters.iouThresholds); 
            areaRange=parameters.areaRange;
            area=[gt.area]; 
            gtIgnore=[gt.iscrowd]|[gt.ignore]|area<areaRange(1)|area>areaRange(2);
            numGroundTruth=length(gt); 
            numDetection=length(detection); 
            for gt_idx=1:numGroundTruth
                gt(gt_idx).ignore=gtIgnore(gt_idx); 
            end
            % sort dt highest score first, sort gt ignore last
            [~,o]=sort([gt.ignore],'ascend'); 
            gt=gt(o);
            [~,o]=sort([detection.score],'descend'); 
            detection=detection(o);
            if(numDetection>parameters.maxDetections)
                numDetection=parameters.maxDetections; 
                detection=detection(1:numDetection); 
            end
            % compute iou between each dt and gt region
            iscrowd = uint8([gt.iscrowd]);
            threshold_idx=find(strcmp(parameters.iouType,{'segm','bbox','keypoints'}));
            if(threshold_idx==1)
                gt_idx=[gt.segmentation]; 
                dt_idx=[detection.segmentation]; 
            elseif(threshold_idx==2)
                gt_idx=cat(1,gt.bbox); 
                dt_idx=cat(1,detection.bbox); 
            end
            
            if(threshold_idx<=2)
                ious=MaskApi.iou(dt_idx,gt_idx,iscrowd); 
            else
                ious=CocoEval.oks(gt,detection); 
            end
            % attempt to match each (sorted) dt to each (sorted) gt
            gt_matches=zeros(numIouThresholds,numGroundTruth); 
            gtIds=[gt.id]; 
            gtIgnore=[gt.ignore];
            dt_matches=zeros(numIouThresholds,numDetection); 
            dtIds=[detection.id]; 
            dtIgnore=zeros(numIouThresholds,numDetection);
            for threshold_idx=1:numIouThresholds
                for dt_idx=1:numDetection
                    % information about best match so far (m=0 -> unmatched)
                    iou_threshold=min(parameters.iouThresholds(threshold_idx),1-1e-10); 
                    matched_gt_idx=0;
                    for gt_idx=1:numGroundTruth
                        % if this gt already matched, and not a crowd, continue
                        if( gt_matches(threshold_idx,gt_idx)>0 && ~iscrowd(gt_idx) )
                            continue; 
                        end
                        % if dt matched to regular gt, and on ignore gt, stop
                        if( matched_gt_idx>0 && gtIgnore(matched_gt_idx)==0 && gtIgnore(gt_idx)==1 )
                            break; 
                        end
                        % if match successful and best so far, store appropriately
                        if( ious(dt_idx,gt_idx)>=iou_threshold )
                            iou_threshold=ious(dt_idx,gt_idx); 
                            matched_gt_idx=gt_idx; 
                        end
                    end
                    % if match made store id of match for both dt and gt
                    if(~matched_gt_idx)
                        continue; 
                    end
                    tIg(threshold_idx,dt_idx)=gtIgnore(matched_gt_idx);
                    dt_matches(threshold_idx,dt_idx)=gtIds(matched_gt_idx); 
                    gt_matches(threshold_idx,matched_gt_idx)=dtIds(dt_idx);
                end
            end
            % set unmatched detections outside of area range to ignore
            if(isempty(detection))
                area=zeros(1,0); 
            else
                area=[detection.area]; 
            end
            dtIgnore = dtIgnore | (dt_matches==0 & repmat(area<areaRange(1)|area>areaRange(2),numIouThresholds,1));
            % store results for given image and category
            dtImgIds=ones(1,numDetection)*parameters.imgIds; 
            gtImgIds=ones(1,numGroundTruth)*parameters.imgIds;
            e = {dtIds,gtIds,dtImgIds,gtImgIds,dt_matches,gt_matches,[detection.score],dtIgnore,gtIgnore};
        end
        
        function o = oks( gt, dt )
            % Compute Object Keypoint Similarity (OKS) between objects.
            G=length(gt); 
            D=length(dt); 
            o=zeros(D,G); 
            if(~D||~G)
                return; 
            end
            % sigmas hard-coded for person class, will need params eventually
            sigmas=[.26 .25 .25 .35 .35 .79 .79 .72 .72 .62 ...
                .62 1.07 1.07 .87 .87 .89 .89]/10;
            vars=(sigmas*2).^2; 
            k=length(sigmas); 
            m=k*3; bb=cat(1,gt.bbox);
            % create bounds for ignore regions (double the gt bbox)
            x0=bb(:,1)-bb(:,3); 
            x1=bb(:,1)+bb(:,3)*2;
            y0=bb(:,2)-bb(:,4); 
            y1=bb(:,2)+bb(:,4)*2;
            % extract keypoint locations and visibility flags
            gKp=cat(1,gt.keypoints); 
            assert(size(gKp,2)==m);
            dKp=cat(1,dt.keypoints); 
            assert(size(dKp,2)==m);
            xg=gKp(:,1:3:m); 
            yg=gKp(:,2:3:m); 
            vg=gKp(:,3:3:m);
            xd=dKp(:,1:3:m); 
            yd=dKp(:,2:3:m);
            % compute oks between each detection and ground truth object
            for d=1:D
                for g=1:G
                    v=vg(g,:); 
                    x=xd(d,:); 
                    y=yd(d,:); 
                    k1=nnz(v);
                    if( k1>0 )
                        % measure the per-keypoint distance if keypoints visible
                        dx=x-xg(g,:); 
                        dy=y-yg(g,:);
                    else
                        % measure minimum distance to keypoints in (x0,y0) & (x1,y1)
                        dx=max(0,x0(g,:)-x)+max(0,x-x1(g,:));
                        dy=max(0,y0(g,:)-y)+max(0,y-y1(g,:));
                    end
                    % use the distances to compute the oks
                    e=(dx.^2+dy.^2)./vars/gt(g).area/2;
                    if(k1>0)
                        e=e(v>0); 
                    else
                        k1=k;
                    end
                    o(d,g)=sum(exp(-e))/k1;
                end
            end
        end
    end
end
