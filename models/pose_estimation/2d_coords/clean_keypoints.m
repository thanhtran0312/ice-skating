function interpolated_keypoints = clean_keypoints(keypoints,confidence, conf_thresh)
    joints = size(keypoints,1);
    dim = size(keypoints,2);
    frames = size(keypoints,3);

    low_conf = reshape(confidence < conf_thresh, joints, 1, frames);
    low_conf = repmat(low_conf, 1,2,1);
    keypoints(low_conf) = NaN;
    
    t_new = 1:frames;
    interpolated_keypoints = zeros(joints,dim,frames);
    for ij = 1: joints
        for id = 1:dim
            t_old = t_new;
            jd_keypoints = squeeze(keypoints(ij,id,:));

            % median filter
            % win = 10;
            % med = medfilt1(jd_keypoints, win, 'omitnan'); % shape (4200-NaN,)
            % residual = abs(jd_keypoints - med);
            % threshold =  3*std(residual(~isnan(residual)));
            % jd_keypoints(residual>threshold) = NaN;

            % single-frame jump detection
            dy = abs(diff(jd_keypoints));
            max_jump =  2*std(dy(~isnan(dy)));
            % spike_frames = find(dy > max_jump);
            % bad = unique([spike_frames, spike_frames+1]);
            jd_keypoints(dy > max_jump) = NaN;

            nan = isnan(jd_keypoints);
            jd_keypoints(nan) = [];
            t_old(nan) = [];

            % clamp the first and last points
            interpolated_kpts = interp1(t_old,jd_keypoints,t_new,'pchip','extrap');
            interpolated_kpts(t_new < t_old(1)) = jd_keypoints(1);
            interpolated_kpts(t_new > t_old(end)) = jd_keypoints(end);

            interpolated_keypoints(ij,id,:) = interpolated_kpts;
            
        end
    end
