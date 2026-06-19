function X_std = standardize_pose(X)
            % X is an [N x 2] or [N x 3] matrix of COCO keypoints

            % 1. Recenter around mid-hip (COCO indices 12 and 13 are hips)
            hip_center = mean(X(12:13, :), 1, 'omitnan');
            X_centered = X - hip_center;

            % 2. Calculate Torso Dimensions
            % Vertical Axis: Mid-Shoulder (6,7) to Mid-Hip (12,13)
            shoulder_mid = mean(X_centered(6:7, :), 1, 'omitnan');
            hip_mid      = mean(X_centered(12:13, :), 1, 'omitnan'); % Should be [0,0] now
            V = norm(shoulder_mid - hip_mid);

            % Horizontal Axis: Left Shoulder (6) to Right Shoulder (7)
            H = norm(X_centered(6, : ) - X_centered(7, :));

            % 3. Calculate "Torso Diamond" Scale
            % This is the Euclidean norm of the torso dimensions.
            % It remains stable even if the person turns (H shrinks) or leans (V shrinks).
            torso_scale = sqrt(V^2 + H^2);

            % 4. Safety check to prevent division by zero
            if torso_scale < 1e-6
                X_std = X_centered; % Return centered but unscaled if scale is invalid
            else
                X_std = X_centered / torso_scale;
            end
        end 