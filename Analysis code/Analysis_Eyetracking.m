
% Settings
    screenX = 1920/8; %screen width (for heatmap)
    screenY = 1080/8; %screen height (for heatmap)
    smoothing_angle = 3;
    data_directory = ''; %fill in the data directory here
    samplingrate = 60; %Hz
    
% Prepare
    load('participants.mat')
    participants = participants(participants.eyetracking==1,:);
    gazeresults = struct;

% Gather results
for ppt = 1:size(participants,1)
    %Load data
        disp(['PPT# ' num2str(ppt)])
        load([data_directory filesep participants.dataset{ppt} filesep 'AllData.mat']);
        load([data_directory filesep participants.dataset{ppt} filesep 'AllGazeData.mat']);
    %Make difference heatmap of happy vs. sad induction choices
        heatmaps = cell(1,2);
        for cond = 1:2
            select_trials = AllData.trialinfo.condition == cond;
            %Loop through selected trials
                screen_gaze = zeros(screenY,screenX); %Blank map
                for trl = find(select_trials)'
                    if isempty(AllGazeData(trl).pupil_X)
                        continue
                    else
                        pupil_X = AllGazeData(trl).pupil_X{:};
                        pupil_Y = AllGazeData(trl).pupil_Y{:};
                        if length(pupil_X)>samplingrate
                            pupil_X = pupil_X(1:samplingrate);
                            pupil_Y = pupil_Y(1:samplingrate);
                        end
                        [pixel_index,gaze_density] = ConvolveGaze(pupil_X,pupil_Y,smoothing_angle,screenX,screenY);
                        if ~isempty(pixel_index)
                            screen_gaze(pixel_index) = screen_gaze(pixel_index) + gaze_density;
                        end
                    end
                end
            %Make a normalized heatmap
                total_gaze = sum(sum(screen_gaze));
                mean_heatmap = screen_gaze./total_gaze;
            %Store
                heatmaps{cond} = mean_heatmap;
        end
        gazeresults(ppt).delta_heatmap = heatmaps{1}-heatmaps{2};
    %Time resolved gaze frequency during 3 seconds, and LL gaze rate per trial
        freq_LL = zeros(length(AllGazeData),3*samplingrate);
        freq_SS = zeros(length(AllGazeData),3*samplingrate);
        gazerate_LL = NaN(length(AllGazeData),1);
        for trl = 1:length(AllGazeData)
            %gaze at uncostly/less-rewarding option (data coded as "left")
                ii_SS = cell2mat([AllGazeData(trl).i_leftreward;AllGazeData(trl).i_leftcost]);
                ii_SS = ii_SS(ii_SS<=size(freq_SS,2));
                freq_SS(trl,ii_SS) = 1;
            %gaze at costly/more-rewarding option (data coded as "right")
                ii_LL = cell2mat([AllGazeData(trl).i_rightreward;AllGazeData(trl).i_rightcost]);
                ii_LL = ii_LL(ii_LL<=size(freq_LL,2));
                freq_LL(trl,ii_LL) = 1;
            %gaze rate in the first second
                ii_LL_1s = ii_LL(ii_LL<=samplingrate);
                ii_SS_1s = ii_SS(ii_SS<=samplingrate);
                if total_gazes > 0
                    gazerate_LL(trl) = length(ii_LL_1s)/samplingrate;
                end
        end
        gazeresults(ppt).frequency_LL = {nanmean(freq_LL)};
        gazeresults(ppt).frequency_SS = {nanmean(freq_SS)};
    %First second gaze rate: regressions
        %Against mood
            fit_mdl = fitglm(gazerate_LL,AllData.trialinfo.mood);
            gazeresults(ppt).beta_mood_gaze = fit_mdl.Coefficients.Estimate';
        %Predict LL choice
            if nanmean(AllData.trialinfo.choiceLL)<0.05 || nanmean(AllData.trialinfo.choiceLL)>0.95
                gazeresults(ppt).beta_gaze_choiceLL = NaN(1,2);
            else
                fit_mdl = fitglm(gazerate_LL,AllData.trialinfo.choiceLL,'Distribution','binomial');
                gazeresults(ppt).beta_gaze_choiceLL = fit_mdl.Coefficients.Estimate';
            end
        %Predict LL RT
            RT = AllData.trialinfo.RT;
            RT(RT > 10) = NaN; %Trim out choices more than 10s
            RT(RT < 0.75) = NaN; %Trim out choices less than 0.75s
            RT(RT > nanmean(RT)+3*nanstd(RT) | RT < nanmean(RT)-3*nanstd(RT)) = NaN; %Choices more or less than 3 standard deviations above or below the mean
            fit_model = fitglm(AllData.trialinfo.trial,RT); %Regress out trial number
            RT = fit_model.Residuals.Raw;
            RT = nanzscore(RT); %Standardize
            fit_mdl = fitglm(gazerate_LL(AllData.trialinfo.choiceLL==1),RT(AllData.trialinfo.choiceLL==1));
            gazeresults(ppt).beta_gaze_RT_LL = fit_mdl.Coefficients.Estimate';
end

% Save
    save([cd filesep 'Results' filesep 'gazeresults'],'gazeresults')

%% Subfunctions

%Gaze convolution
function [i_nonzero,trl_gaze] = ConvolveGaze(pupil_X,pupil_Y,smoothing_angle,screenX,screenY)

%Settings
    screen_distance = 80; %[cm] distance from the PPT's eyes to screen (approximately)
    screen_width = 51; %[cm] width of the active area of the screen
    I = reshape(1:screenX*screenY,screenY,screenX); %Pixel indices
%Make smoothing kernels
    %Distances to eye from each pixel
        pix_X = repmat(1:screenX,screenY,1); %X-coordinate of each pixel
        pix_Y = repmat((screenY:-1:1)',1,screenX); %Y-coordinate of each pixel; center is bottom left
        center_dist = sqrt((pix_X-screenX/2).^2 + (pix_Y-screenY/2).^2); %Distance to center, in pixels
        center_dist = screen_width/screenX.*center_dist; %Distance to center, in centimeters
        eye_dist = sqrt(screen_distance^2 + center_dist.^2); %Distance to eyes, in centimeters    
    %Diversion angle (angle between fixation and center of the screen)
        div_angle = asin(center_dist./eye_dist);
    %Distance from center minus sigma (in cm)
        rad_angle = (smoothing_angle/180)*pi; %radian angle corresponding to sigma
        dist_min_sigma = screen_distance*tan(div_angle-rad_angle/2);
    %Sigma
        sigma_cm = 2*(center_dist - dist_min_sigma);
        sigma_pix = round((sigma_cm/screen_width)*screenX); %sigma in pixels (taken from the width of the screen
        all_sigma = unique(sigma_pix)';
        all_kernels = cell(1,max(all_sigma));
        for sigma = all_sigma
            all_kernels{sigma} = Gaussian_filter(6*sigma,sigma);
        end
%Convolve
    screen_gaze = zeros(screenY,screenX); %Blank map
    for i_sample = 1:length(pupil_X)
        if ~any(isnan([pupil_X(i_sample) pupil_Y(i_sample)]))
            %Get the kernel for this sample
                sigma = sigma_pix(ceil(pupil_Y(i_sample))*screenY,ceil(pupil_X(i_sample)*screenX));
                kernel = all_kernels{sigma};
            %Get the outer X and Y coordinates of the kernel on screen
                X = round(pupil_X(i_sample)*screenX) + [-size(kernel,2)/2,size(kernel,2)/2-1];
                Y = round(pupil_Y(i_sample)*screenY) + [-size(kernel,1)/2,size(kernel,1)/2-1];
                X_kernel = [1 size(kernel,2)];
                Y_kernel = [1 size(kernel,1)];
            %Correct coordinates that are off-screen
                if X(1)<1; X_kernel(1) = -X(1)+2; X(1) = 1; end
                if X(2)>screenX; X_kernel(2) = size(kernel,2)-X(2)+screenX; X(2) = screenX; end
                if Y(1)<1; Y_kernel(1) = -Y(1)+2; Y(1) = 1; end
                if Y(2)>screenY; Y_kernel(2) = size(kernel,1)-Y(2)+screenY; Y(2) = screenY; end
            %Make a map
                screen_gaze(Y(1):Y(2),X(1):X(2)) = screen_gaze(Y(1):Y(2),X(1):X(2)) + ...
                    kernel(Y_kernel(1):Y_kernel(2),X_kernel(1):X_kernel(2));       
        end
    end %for i_sample
%Output
    i_nonzero = I(screen_gaze~=0); %Indices of pixels where gaze is nonzero
    trl_gaze = screen_gaze(i_nonzero); %Convoluted gaze values of these pixels
    
end

%Gaussian filter
function g=Gaussian_filter(Filter_size, sigma)
    %size=5; %filter size, odd number
    size=Filter_size;
    g=zeros(size,size); %2D filter matrix
    %sigma=2; %standard deviation
    %gaussian filter
    for i=-(size-1)/2:(size-1)/2
        for j=-(size-1)/2:(size-1)/2
            x0=(size+1)/2; %center
            y0=(size+1)/2; %center
            x=i+x0; %row
            y=j+y0; %col
            g(y,x)=exp(-((x-x0)^2+(y-y0)^2)/2/sigma/sigma);
        end
    end
    %normalize gaussian filter
    sum1=sum(g);
    sum2=sum(sum1);
    g=g/sum2;
end
