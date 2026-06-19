% for one participant
% one run: 
% 1. VidA-T1-N 
% 2. VidB-T1-B
% 3. VidC-T1-H
% 4. VidD-T2-N
% 5. VidE-T2-B
% 6. VidF-T2-H
%% 
n_subs = 30;
n_runs = 6;
n_blocks = 6;
n_vids = 39;
% condition key:
% 1=T1N, 2=T1B, 3=T1H
% 4=T2N, 5=T2B, 6=T2H

% runs 1-3: vid1=T1B, vid2=T1H, vid3=T1N, vid4=T2B, vid5=T2H, vid6=T2N
conds_first = [1,2,3,4,5,6];

% runs 4-6: task flips, filter stays with video
%           vid1=T2B, vid2=T2H, vid3=T2N, vid4=T1B, vid5=T1H, vid6=T1N
conds_last  = [4,5,6,1,2,3];


condmat = zeros(n_subs, n_blocks, n_runs, 2);
for isub = 1:n_subs
    vid = randperm(n_vids);
    for irun = 1:n_runs
        shuffle_idx = randperm(n_blocks);  % shuffle blocks, vid & cond move together
        if irun <= 3
            conds = conds_first;
        else
            conds = conds_last;
        end
        condmat(isub, :, irun, 1) = vid(shuffle_idx);
        condmat(isub, :, irun, 2) = conds(shuffle_idx);

    end
end

save('condmat.mat', 'condmat');

% for run 1-3, conds 123456, 


% % how many times each clip was seen
% count_vid = zeros(n_vids,1);
% for isub = 1:30
%     for iblock = 1:6
%         count_vid(condmat(isub,iblock,1,1),1) =  count_vid(condmat(isub,iblock,1,1),1) + 1;
%     end
% end
% count_vid(condmat(isub,:,1,1),1)
% count_vid(condmat(:,:,1,1),1) =  count_vid(condmat(:,:,1,1),1) + 1;
% figure;bar(count_vid)