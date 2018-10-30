true_positive = randi(5, 1, 10);
false_positive = randi(5, 1, 10);
gt_not_ignored = sum(true_positive) + 10;
% tp and fp at each score cutoff
tp=cumsum(true_positive);
fp=cumsum(false_positive);
num_tp=length(tp);
% np = number of gt not ignored. rc = recall array at
% each score cutoff
rc=tp/gt_not_ignored;
pr=tp./(fp+tp);
recall_thresholds=0:0.01:1;
R = length(recall_thresholds);
q=zeros(1,R); % R = length(recThresholds) = 101; recThresholds = [0:.01:1];
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