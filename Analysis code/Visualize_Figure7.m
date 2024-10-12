% Figure 7: Eyetracking results

% Load data
    load('gazeresults.mat')
    load('participants.mat')
    load('choiceModelFree.mat')
    participants = participants(participants.eyetracking==1,:);
    data_directory = 'C:\Users\rheerema\OneDrive\Experiment data\MoodChoicePhysiology2024'; %Fill in the directory where the data is stored here

% Setup
    hf = figure;
    hf.Position = [697 249 869 588];
    color_LL = [221,28,119]./255;
    color_SS = [201,148,199]./255;
    color_rect = [[231,225,239]./255, 0.5];

% Gather data
    heatmaps = NaN(screenY,screenX,length(gazeresults));
    medianRT = NaN(size(participants,1),1);
    choicerate = NaN(size(participants,1),1);
    meanRT_LL = NaN(size(participants,1),1);
    for ppt = 1:length(gazeresults)
        %load dataset
            load([data_directory filesep participants.dataset{ppt} filesep 'AllData.mat'])
            disp(['ppt #' num2str(ppt)])
        %heatmaps
            heatmaps(:,:,ppt) = gazeresults(ppt).delta_heatmap;
        %costly option choice rate
            choicerate(ppt) = nanmean(AllData.trialinfo.choiceLL);
        %RT
            RT = AllData.trialinfo.RT;
            medianRT(ppt) = nanmedian(RT);
            RT(RT > 10) = NaN; %Trim out choices more than 10s
            RT(RT < 0.5) = NaN; %Trim out choices less than 0.5s
            RT(RT > nanmean(RT)+3*nanstd(RT) | RT < nanmean(RT)-3*nanstd(RT)) = NaN; %Choices more or less than 3 standard deviations above or below the mean
            fit_model = fitglm(AllData.trialinfo.trial,RT); %Regress out trial number
            RT = fit_model.Residuals.Raw;
            RT = nanzscore(RT); %Standardize
            meanRT_LL(ppt) = nanmean(RT(AllData.trialinfo.choiceLL==1));
    end

%% Panel A -- Average gaze map
    subplot(2,3,1:2); hold on
    % Settings
        color = [1 1 1];
        screenX = 1920; %PRISME screen width
        screenY = 1080; %PRISME screen height  
        screen_distance = 80; %[cm] distance from the PPT's eyes to screen (approximately)
        screen_width = 51; %[cm] width of the active area of the screen
        margin = tan(2/180*pi)*screen_distance/screen_width;
    % Average difference heatmap
        mean_heatmap = nanmean(heatmaps,3);
        imagesc(mean_heatmap); set(gca,'YDir','normal'); 
        axis equal; axis([0 screenX 0 screenY]); box on; xticks([]); yticks([]); 
        c = colorbar; c.Label.String = ''; %Gaze density (a.u.)';
        box on
    % Draw cost and reward boxes
        %Coordinates
            rewardlefttext = [3/16 1-12/16 5/16 1-10/16] + margin*[-1 -1 +1 +1]; %Coordinates with margin(x1 y1 x2 y2 with origin at the bottom left)
            rewardrighttext = [11/16 1-12/16 13/16 1-10/16] + margin*[-1 -1 +1 +1]; %Coordinates with margin(x1 y1 x2 y2 with origin at the bottom left)
            costboxleft = [3/16 1-1/2 5/16 1-1/4] + margin*[-1 -1 +1 +1]; %Coordinates with margin(x1 y1 x2 y2 with origin at the bottom left)
            costboxright = [11/16 1-1/2 13/16 1-1/4] + margin*[-1 -1 +1 +1]; 
        %Draw rectangles
            rewardlefttext = rewardlefttext .* [screenX screenY screenX screenY];
                rectangle('Position',[rewardlefttext([1 2]) rewardlefttext([3 4])-rewardlefttext([1 2])],'EdgeColor',color)
            rewardrighttext = rewardrighttext .* [screenX screenY screenX screenY];
                rectangle('Position',[rewardrighttext([1 2]) rewardrighttext([3 4])-rewardrighttext([1 2])],'EdgeColor',color)
            costboxleft = costboxleft .* [screenX screenY screenX screenY];
                rectangle('Position',[costboxleft([1 2]) costboxleft([3 4])-costboxleft([1 2])],'EdgeColor',color)
            costboxright = costboxright .* [screenX screenY screenX screenY];
                rectangle('Position',[costboxright([1 2]) costboxright([3 4])-costboxright([1 2])],'EdgeColor',color)

%% Panel B -- Time-resolved gaze results
    %Get gaze averages
        freq_LL = cell2mat(vertcat(gazeresults.frequency_LL));
        SEM_LL = nanstd(freq_LL) ./ sqrt(sum(~isnan(freq_LL))); %#ok<*NANSTD>
        freq_SS = cell2mat(vertcat(gazeresults.frequency_SS));
        SEM_SS = nanstd(freq_SS) ./ sqrt(sum(~isnan(freq_SS)));
    %Plot   
        subplot(2,3,4:5); hold on %Gaze frequency
        rectangle('Position',[0,0,1,1],'FaceColor',color_rect,'EdgeColor','none')
        X = linspace(0,3,180);
        hp1 = PrettyPatchPlot(X,nanmean(freq_SS),SEM_SS,color_SS); %SS option
        hp2 = PrettyPatchPlot(X,nanmean(freq_LL),SEM_LL,color_LL); %LL option
        L=line(mean(medianRT)*ones(1,2),[0,1],'LineWidth',2,'Color',1/3*ones(1,3),'LineStyle','--');
        ylim([0,0.6]); box on
        xlabel('Time since option display [s]'); ylabel('Gaze proportion'); legend([hp1,hp2],{'costly','uncostly'})        

%% Panel C -- Choice rate vs. gaze rate
    subplot(2,3,3); hold on; box on
    gaze_rate = vertcat(gazeresults.gazerate_LL);
    fit_model = fitglm(gaze_rate,choicerate);
    X = linspace(0,1);
    [Y,Y_CI] = predict(fit_model,X','Alpha',0.05); 
    E = Y_CI(:,2)'- Y';
    Y = Y';
    patch([X X(end:-1:1)], [Y+E Y(end:-1:1)-E(end:-1:1)], color_LL, 'facealpha', 0.05, 'Edgecolor', color_LL);
    plot(X, Y, 'linestyle', '-', 'LineWidth', 2, 'color', color_LL);
    xlabel('Costly option gaze proportion'); ylabel('Costly option choice rate')

%% Panel D -- LL chosen: Gaze rate vs. RT
    subplot(2,3,6); cla; hold on; box on
    gaze_rate_chosen = vertcat(gazeresults.gazerate_LL_choice);
    fit_model = fitglm(gaze_rate,meanRT_LL);
    X = linspace(0,1);
    [Y,Y_CI] = predict(fit_model,X','Alpha',0.05); 
    E = Y_CI(:,2)'- Y';
    Y = Y';
    patch([X X(end:-1:1)], [Y+E Y(end:-1:1)-E(end:-1:1)], color_LL, 'facealpha', 0.05, 'Edgecolor', color_LL);
    plot(X, Y, 'linestyle', '-', 'LineWidth', 2, 'color', color_LL);
    xlabel({'Costly option gaze proportion';'(costly option chosen)'}); ylabel('Costly option RT')

%% Patch plot
function h = PrettyPatchPlot(X,Y,E,color) 
    patch([X X(end:-1:1)], [Y+E Y(end:-1:1)-E(end:-1:1)], color, 'facealpha', 0.25, 'Edgecolor', color);
    h = plot(X, Y, 'linestyle', '-', 'LineWidth', 2, 'color', color);
end