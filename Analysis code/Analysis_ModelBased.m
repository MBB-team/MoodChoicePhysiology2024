%% Modelling of choice behavior
% Note, this script requires the Variational Bayesian Analysis (VBA) toolbox to be added to the MATLAB path:
% https://mbb-team.github.io/VBA-toolbox/

% Prepare
    do_inversions = false;
    do_mdlcomparison = true;
    do_analysis_winningmodel = false;
    load('participants.mat')
    data_directory = [cd filesep 'Data']; %Fill in the directory where the data is stored here
% Model settings
    %List the models to be inverted
        invert_models.DelayModel = {'exponential'};
        invert_models.RiskModel = {'expected reward'};
        invert_models.EffortModel = {'additive'};
        invert_models.RewardModel = {'fixed','variable'};
        invert_models.PowerModel = {'fixed','variable'};
        invert_models.ChoiceTemp = {'none','across types','per type'};
        invert_models.ChoiceBias = {'none','across types','per type'};
        invert_models.Mood = {'none','on bias'};
    %List the models to be compared to each other
        compare_models.DelayModel = {'exponential'};
        compare_models.RiskModel = {'expected reward'};
        compare_models.EffortModel = {'additive'};
        compare_models.RewardModel = {'fixed','variable'};
        compare_models.PowerModel = {'fixed','variable'};
        compare_models.ChoiceTemp = {'none','across types','per type'};
        compare_models.ChoiceBias = {'none','across types','per type'};
        compare_models.Mood = {'none'};


%% Invert models
if do_inversions
    
% Configure model space
    [analysis_list,constraints_list,priors_list] = MakeAnalysisList(invert_models);
    parameternames = constraints_list.Properties.VariableNames;
    %Restrict list to reported models only (for computational efficiency)
        match = false(size(analysis_list));
        for i = 1:size(analysis_list,2)
            varName = analysis_list.Properties.VariableNames{i};
            match(:,i) = strcmp(analysis_list.(varName),winning_model.(varName));
        end
        i_winning = all(match,2);
        include_models = strcmp(analysis_list.Mood,'none') | i_winning;
        analysis_list = analysis_list(include_models,:);
        constraints_list = constraints_list(include_models,:);
        priors_list = priors_list(include_models,:);
% Loop through participants
    modelinversion = struct;
    parfor ppt = 1:size(participants,1) %replace "parfor" with "for" if you don't have the parallel computing toolbox installed
        %Collect data
            %Load the data
                disp(['PPT #' num2str(ppt)])
                data = load([data_directory filesep participants.dataset{ppt}]);
                AllData = data.AllData;
                trialinfo = AllData.trialinfo;
            %Compute mood
                AllData.affect.Mood = AllData.affect.RateHappy-AllData.affect.RateSad;
                AllData.affect.Mood(ismember(AllData.affect.Condition,{'anger','fear'})) = NaN;
                AllData.affect.Mood = nanzscore(AllData.affect.Mood);
                trialinfo.mood = NaN(size(trialinfo,1),1);
                for trl = 1:size(AllData.trialinfo,1)
                    ind = AllData.trialinfo.induction(trl); 
                    trialinfo.mood(trl) = AllData.affect.Mood(ind); %note, only for happy/sad/neutral condition trials
                end
            %Exclude choice types from datasets that are dissimilar to the same type in other studies
                include_choicetypes = true(1,3);   
                for type = 1:3
                    if participants.study(ppt) == 1 && type == 2 %Excude probability discounting from study 1 
                        include_choicetypes(type) = 0;
                    elseif participants.study(ppt) == 2 && type == 1 %Exclude delay discounting from study 2
                        include_choicetypes(type) = 0;
                    end
                end
                select = ismember(trialinfo.choicetype,find(include_choicetypes)) & ismember(trialinfo.condition,[1,2,5]);                
            %Input to VBA
                y = trialinfo.choiceLL(select);         %Data to be fitted
                u = [   trialinfo.SSReward(select)';    %Trial features
                        ones(1,sum(select));            %LL Reward
                        trialinfo.Loss(select)';
                        trialinfo.Delay(select)';
                        trialinfo.Risk(select)';
                        trialinfo.Effort(select)';
                        trialinfo.choicetype(select)';
                        trialinfo.mood(select)'];
                condition = trialinfo.condition(select);
                %Remove missing datapoints
                    i_isnan_u = any(isnan(u),1); i_isnan_y = isnan(y);
                    u = u(:,(~i_isnan_u & ~i_isnan_y'));
                    y = y(~i_isnan_u' & ~i_isnan_y);
                    condition = condition(~i_isnan_u' & ~i_isnan_y);
                %Prepare input for observation function
                    u_obs = reshape(u',numel(u),1); %Input into the observation function
        %Loop through models to invert
            for mdl = 1:size(analysis_list,1)
                %Inversion settings
                    %Options: general
                        options = struct;
                        options.sources.type = 1; %binary data
                        options.verbose = 0; %don't print text in the command window
                        options.DisplayWin = 0; %don't show progress on images
                    %Options: in observation function
                        options.inG.parameternames = parameternames;
                        options.inG.constraints = constraints_list{mdl,:}; %#ok<PFBNS>
                        options.inG.modelcat = analysis_list.Properties.VariableNames;
                        options.inG.modelspec = analysis_list{mdl,:}; 
                        options.inG.P0 = priors_list{mdl,:};  %#ok<PFBNS>
                        options.inG.inv = mdl;
                    %Prior variance
                        options.priors.SigmaPhi = eye(size(constraints_list,2));
                        for par = 1:size(constraints_list,2)
                            switch char(constraints_list{mdl,par})
                                case 'fixed'
                                    options.priors.SigmaPhi(par,par) = 0;
                                case 'none'
                                    options.priors.SigmaPhi(par,par) = 10;
                                case 'safepos'
                                    options.priors.SigmaPhi(par,par) = 10;
                                case 'exponential'
                                    options.priors.SigmaPhi(par,par) = 1;
                            end
                        end
                    %Get prior parameter values from calibration data
                        options.priors.muPhi = (priors_list{mdl,:})'; %Use flat priors to fit calibration data first
                        if ~isempty(AllData.calibration)
                            options.priors.muPhi = PriorsFromCalibration(options,AllData.calibration,include_choicetypes); %Use fitted calibration parameters as priors for main experiment
                        end
                    %Dimensions
                        dim = struct;
                        dim.n_theta = 0;
                        dim.n = 0; 
                        dim.n_phi = size(constraints_list,2); 
                        dim.p = length(y);          
                        dim.n_t = 1;
                %Invert the model and get results
                    [posterior,output] = VBA_NLStateSpaceModel(y,u_obs,[],@ObservationFunction,dim,options);
                    muPhi = posterior.muPhi;
                    SigmaPhi = posterior.SigmaPhi;
                %Process inversion results
                    %Calculate choice probability, actual choice, and residuals
                        P_LL = cell(1,3); Residuals = cell(1,3); Y = cell(1,3);
                        for type = find(include_choicetypes)
                            type_select = u(7,:)==type;
                            P_LL{type} = ObservationFunction([],muPhi,u(:,type_select),options.inG);
                            Y{type} = y(type_select)';
                            Residuals{type} = Y{type} - P_LL{type};
                        end
                    %Correct constrained or excluded output
                        for i_par = 1:size(constraints_list,2)
                            %Convert parameter estimates based on parameter constraints
                                switch char(constraints_list{mdl,i_par})
                                    case 'exponential'
                                        muPhi(i_par) = exp(muPhi(i_par));
                                    case 'softmax'
                                        muPhi(i_par) = 1/(1+exp(-muPhi(i_par)));
                                    case 'safepos'
                                        muPhi(i_par) = RH_Safepos(muPhi(i_par));                                        
                                end
                            %Set parameters from uninverted choice types as NaN
                                if ~include_choicetypes(1) && ismember(parameternames{i_par},{'kD','biasD','betaD','gammaD'})
                                    muPhi(i_par) = NaN;
                                    SigmaPhi(i_par,i_par) = NaN;
                                elseif ~include_choicetypes(2) && ismember(parameternames{i_par},{'kR','biasR','betaR','gammaR'})
                                    muPhi(i_par) = NaN;
                                    SigmaPhi(i_par,i_par) = NaN;
                                elseif ~include_choicetypes(3) && ismember(parameternames{i_par},{'kE','biasE','betaE','gammaE'})
                                    muPhi(i_par) = NaN;
                                    SigmaPhi(i_par,i_par) = NaN;
                                end
                        end
                        SigmaPhi = diag(SigmaPhi);
                %Store in the modelinversion structure
                    modelinversion(ppt).muPhi(mdl,:) = muPhi';
                    modelinversion(ppt).SigmaPhi(mdl,:) = SigmaPhi';
                    modelinversion(ppt).logF(1,mdl) = output.F;
                    modelinversion(ppt).Y(mdl,:) = Y; 
                    modelinversion(ppt).P_LL(mdl,:) = P_LL; 
                    modelinversion(ppt).Residuals(mdl,:) = Residuals; 
                    modelinversion(ppt).analysis = analysis_list;
            end %for inv            
    end %parfor
% Get inversion results (necessary for the next steps)
    Inversionresults = GetInversionResults(modelinversion, participants);
% Store
    save([cd filesep 'Results' filesep 'choiceModelBased'],'modelinversion','Inversionresults')
    
end %if do_inversions

%% Compare models
if do_mdlcomparison
    %Get modelling results
        load([cd filesep 'Results' filesep 'choiceModelBased'])
    %Analysis list
        analysis_list = MakeAnalysisList(compare_models);
        categorynames = analysis_list.Properties.VariableNames; %Predefined model categories
        i_model = num2cell(1:length(Inversionresults)); i_model = cellfun(@num2str,i_model,'uni',false); %Model index from Inversionresults
    %Select models from Inversionresults to keep
        select = false(length(Inversionresults),1);
        for i_inv = 1:length(Inversionresults) %Loop through all models that have been inverted in Inversionresults
            analysis = Inversionresults(i_inv).analysis;
            for i_list = 1:size(analysis_list,1) %Loop through models listed to be compared
                match = false(1,size(analysis_list,2));
                for i_cat = 1:size(analysis_list,2) %Loop through model categories
                    if strcmp(analysis_list{i_list,i_cat},analysis(i_cat))
                        match(i_cat) = true;
                    else
                        break;
                    end
                end
                if all(match)
                    select(i_inv) = true;
                end
            end
        end
        logEvidence = cell2mat({Inversionresults(select).logF}'); %K x n (K models, n subjects)
        logEvidence = logEvidence(:,(~isnan(mean(logEvidence)) & mean(logEvidence)~=0) ); %Exclude ppts with failed inversions
    %Model comparison per family
        mdlComp = struct;
        for i_cat = 1:length(categorynames) %Loop through categories
            try
                list_fam = unique(analysis_list.(categorynames{i_cat})); %List all unique families per category
            catch
                list_fam = cell(length(comparemodels.(categorynames{i_cat})),1);
                for i = 1:length(list_fam)
                    list_fam(i) = {[categorynames{i_cat} num2str(i)]};
                end
            end
            if length(list_fam)>1 %Compare model families if there are more than one
                %Set options
                    options.verbose = 1;
                    options.DisplayWin = 1;
                    options.figName = categorynames{i_cat}; %Name the figure after the category
                    options.families = cell(length(list_fam),1); %Sort the models into the different families of the category
                %Divide into families
                    for i_fam = 1:length(list_fam)
                        options.families{i_fam} = find(strcmp(analysis_list.(categorynames{i_cat}),list_fam(i_fam)))'; %List the indices from analysis_list                        
                        if isempty(options.families{i_fam})
                            modelcategory = comparemodels.(categorynames{i_cat}){i_fam};
                            include_fam = false(size(analysis_list,1),1);
                            for i = 1:length(include_fam) %loop through analyses
                                analysis = analysis_list.(categorynames{i_cat}){i};
                                if length(analysis)==length(modelcategory) && all(strcmp(analysis,modelcategory))
                                    include_fam(i) = true;
                                end
                            end
                            options.families{i_fam} = find(include_fam);
                        end
                    end
                %Invert
                    options.modelNames = i_model(select);
                    [posterior,out] = VBA_groupBMC(logEvidence,options);
                %Store
                    mdlComp.families.(categorynames{i_cat}).mdl = list_fam; %Family "members"
                    mdlComp.families.(categorynames{i_cat}).freq = out.families.a; %Family frequencies
                    mdlComp.mdlFreq = posterior.a; %Model frequencies (i.e. posterior counts)
                    mdlComp.excProb = out.ep; %Exceedence probabilities
            end %if list_fam
        end %for i_cat
    %Visualize
        figure; 
        %Top row: per-family results
            family_names = fieldnames(mdlComp.families);
            n_fam = length(family_names); %number of families
            for i_fam = 1:n_fam
                subplot(2,n_fam,i_fam); hold on
                title(family_names{i_fam})
                ylabel('Model frequency')
                bar(mdlComp.families.(family_names{i_fam}).freq' ./ sum(mdlComp.families.(family_names{i_fam}).freq),'FaceColor',[0.75 0.75 0.75])
                xticks(1:length(mdlComp.families.(family_names{i_fam}).freq))
                xticklabels(mdlComp.families.(family_names{i_fam}).mdl)
            end
        %Bottom row: results across models
            subplot(2,2,3); hold on; box on
                bar(mdlComp.mdlFreq./(sum(mdlComp.mdlFreq)),'FaceColor',[0 0 0]);
                xticks(1:length(mdlComp.mdlFreq)); 
                ylabel('Model frequency'); xlabel('Model number'); title('Full model space: posterior counts')
            subplot(2,2,4); hold on; box on
                bar(mdlComp.excProb,'FaceColor',[0 0 0]);
                xticks(1:length(mdlComp.mdlFreq)); 
                ylabel('Exceedance probability'); xlabel('Model number'); title('Full model space: exceedance probability')
end
        
%% Subfunction: make analysis list
function [analysis_list,constraints_list,priors_list] = MakeAnalysisList(listmodels)
% Produces an analysis list (table) for discounting models, and accordinly, a list of parameters with their constraints 
% for each analysis, and a list of prior values for each parameter per analysis (given the parameter constraints). 
% The parameters are:
    parameter_names = {'kRew','kD','kR','kE','biasD','biasR','biasE','bias',...
        'betaD','betaR','betaE','beta','gammaD','gammaR','gammaE','betaMood'};

% Analysis list
    combinations = RH_Combine({listmodels.DelayModel,listmodels.RiskModel,listmodels.EffortModel,listmodels.RewardModel,...
        listmodels.PowerModel,listmodels.ChoiceTemp,listmodels.ChoiceBias,listmodels.Mood});
    analysis_list = cell2table(combinations,'VariableNames',...
        {'DelayModel' 'RiskModel' 'EffortModel' 'RewardModel' 'PowerModel' 'ChoiceTemp' 'ChoiceBias' 'Mood'});

% Parameter constraints and priors list
    n_analyses = size(analysis_list,1);
    n_parameters = length(parameter_names);
    constraints_list = cell2table(cell(n_analyses,n_parameters),'VariableNames',parameter_names);
    priors_list = array2table(NaN(n_analyses,n_parameters),'VariableNames',parameter_names);
    for i = 1:n_analyses
        %Weight on reward
            priors_list.kRew(i) = 1;
            if strcmp(analysis_list.RewardModel{i},'fixed')
                constraints_list.kRew{i} = 'fixed';
            elseif strcmp(analysis_list.RewardModel{i},'variable')
                constraints_list.kRew{i} = 'safepos';
            elseif strcmp(analysis_list.RewardModel{i},'power')
                constraints_list.kRew{i} = 'safepos';
            end
        %Weights on costs: always positive
            constraints_list.kD{i} = 'safepos';
            priors_list.kD(i) = 1;
            constraints_list.kR{i} = 'safepos';
            priors_list.kR(i) = 1;
            constraints_list.kE{i} = 'safepos';
            priors_list.kE(i) = 1;
        %Bias term: may vary freely
            priors_list.bias(i) = 0;
            priors_list.biasD(i) = 0;
            priors_list.biasR(i) = 0;
            priors_list.biasE(i) = 0;
            switch analysis_list.ChoiceBias{i}
                case 'none' %all fixed to zero
                    constraints_list.bias{i} = 'fixed';
                    constraints_list.biasD{i} = 'fixed';
                    constraints_list.biasR{i} = 'fixed';
                    constraints_list.biasE{i} = 'fixed';
                case 'across types' %only one parameter is inverted; the rest is fixed
                    constraints_list.bias{i} = 'none';
                    constraints_list.biasD{i} = 'fixed';
                    constraints_list.biasR{i} = 'fixed';
                    constraints_list.biasE{i} = 'fixed';
                case 'per type' %the common parameter is fixed to zero; the rest is inverted
                    constraints_list.bias{i} = 'fixed';
                    constraints_list.biasD{i} = 'none';
                    constraints_list.biasR{i} = 'none';
                    constraints_list.biasE{i} = 'none';
            end
        %Inverse choice temperature
            switch analysis_list.ChoiceTemp{i}
                case 'none'
                    constraints_list.beta{i} = 'fixed';
                    priors_list.beta(i) = 1;
                    constraints_list.betaD{i} = 'fixed';
                    priors_list.betaD(i) = 1;
                    constraints_list.betaR{i} = 'fixed';
                    priors_list.betaR(i) = 1;
                    constraints_list.betaE{i} = 'fixed';
                    priors_list.betaE(i) = 1;
                case 'across types' %Invert one temperature (pos.) across types, the rest are set to 1;
                    constraints_list.beta{i} = 'exponential';
                    priors_list.beta(i) = 0;
                    constraints_list.betaD{i} = 'fixed';
                    priors_list.betaD(i) = 1;
                    constraints_list.betaR{i} = 'fixed';
                    priors_list.betaR(i) = 1;
                    constraints_list.betaE{i} = 'fixed';
                    priors_list.betaE(i) = 1;
                case 'per type' %Invert one choice temperature (positive) per type, the beta across type is set to 1
                    constraints_list.beta{i} = 'fixed';
                    priors_list.beta(i) = 1;
                    constraints_list.betaD{i} = 'exponential';
                    priors_list.betaD(i) = 0;
                    constraints_list.betaR{i} = 'exponential';
                    priors_list.betaR(i) = 0;
                    constraints_list.betaE{i} = 'exponential';
                    priors_list.betaE(i) = 0;
            end
        %Power on cost
            priors_list.gammaD(i) = 1;
            priors_list.gammaR(i) = 1;
            priors_list.gammaE(i) = 1;
            switch analysis_list.PowerModel{i}
                case 'fixed'
                    constraints_list.gammaD{i} = 'fixed';
                    constraints_list.gammaR{i} = 'fixed';
                    constraints_list.gammaE{i} = 'fixed';
                case 'variable'
                    constraints_list.gammaD{i} = 'safepos'; %Invert power on cost; it is positive
                    constraints_list.gammaR{i} = 'safepos'; %Invert power on cost; it is positive
                    constraints_list.gammaE{i} = 'safepos'; %Invert power on cost (positive)
            end        
         %Weight on mood
            priors_list.betaMood(i) = 0;
            if ~strcmp(analysis_list.Mood{i},'none')
                constraints_list.betaMood{i} = 'none'; %Inverted, free to vary
            else %Not inverted, set to zero
                constraints_list.betaMood{i} = 'fixed';
            end
    end %for i

end %function

%% Subfunction: get priors from calibration
function [muPhi] = PriorsFromCalibration(options,cal_trialinfo,include_choicetypes)
% Invert the specified model (from options) and produce the fitted parameters as output.

%Limit the data to included choice types
    select = ismember(cal_trialinfo.choicetype,find(include_choicetypes));
    cal_trialinfo = cal_trialinfo(select,:);
%Data to be fitted
    y = cal_trialinfo.choiceLL; 
%Dimensions
    dim.n_theta = 0; % # evolution parameters
    dim.n = 0; % # hidden states
    dim.p = length(y); % # output (data) dimension (# observations per time sample)          
    dim.n_phi = length(options.inG.parameternames ); % # of parameters to be fitted
    dim.n_t = 1;
%Input
    y = y(~isnan(y));
    u = [cal_trialinfo.SSReward(~isnan(y))'; 
            ones(1,sum(~isnan(y)));
            cal_trialinfo.Loss(~isnan(y))';
            cal_trialinfo.Delay(~isnan(y))';
            cal_trialinfo.Risk(~isnan(y))';
            cal_trialinfo.Effort(~isnan(y))';
            cal_trialinfo.choicetype(~isnan(y))'
            zeros(size(y))'];
    u = reshape(u',numel(u),1);
%Invert calibration choice data
    [posterior,~] = VBA_NLStateSpaceModel(y,u,[],@ObservationFunction,dim,options);
    muPhi = posterior.muPhi;
end

%% Subfunction: observation function
function [Z] = ObservationFunction(~,P,u,in)
%  Inverts model for delay, risk, and effort discounting
%  Inputs:
%       P: vector of parameters
%       u: Experimental design inputs (option 1 and 2)
%       in: any exra relevant information

%Parameters
    par = struct;
    for i_par = 1:length(in.parameternames)
        switch in.constraints{i_par}
            case 'none'
                par.(in.parameternames{i_par}) = P(i_par);
            case 'exponential'
                par.(in.parameternames{i_par}) = exp(P(i_par));
            case 'softmax'
                par.(in.parameternames{i_par}) = 1/(1+exp(-P(i_par)));
            case 'fixed'
                par.(in.parameternames{i_par}) = in.P0(i_par);
            case 'safepos'
                par.(in.parameternames{i_par}) = RH_Safepos(P(i_par));
        end
    end    
%Trial data
    if size(u,2) == 1 %n_t = 1
        u = (reshape(u,length(u)/8,8))';
        Z = NaN(size(u,2),1);   %Probability of chosing costly option
    else
        Z = NaN(1,size(u,2));   %Probability of chosing costly option
    end
%Loop through choices
    for i = 1:length(Z)
        %Inputs (u)
            R1 = u(1,i);   %Reward for (uncostly) option 1
            R2 = u(2,i);   %Reward for (costly) option 2
            L = u(3,i);    %Loss in the case of a lost risky lottery
            C_d = u(4,i);  %Cost: delay 
            C_r = u(5,i);  %Cost: risk 
            C_e = u(6,i);  %Cost: effort    
            type = u(7,i); %Choice type
            M = u(8,i);    %Mood
        %Reward: weighted or not
            if strcmp(in.modelspec{strcmp(in.modelcat,'RewardModel')},'variable') 
                k_Reward = par.kRew;
            elseif strcmp(in.modelspec{strcmp(in.modelcat,'RewardModel')},'fixed')
                k_Reward = 1;
            end
        %Weight on Cost
            switch type
                case 1 %Delay
                    k_Cost = par.kD;
                case 2 %Risk
                    k_Cost = par.kR;
                case 3 %Effort
                    k_Cost = par.kE;
            end
        %Choice temperature           
            if strcmp(in.modelspec{strcmp(in.modelcat,'ChoiceTemp')},'per type')
                switch type
                    case 1 %Delay
                        beta = par.betaD; 
                    case 2 %Risk
                        beta = par.betaR; 
                    case 3 %Effort
                        beta = par.betaE;
                end
            else
                beta = par.beta;
            end
        %Choice bias            
            if strcmp(in.modelspec{strcmp(in.modelcat,'ChoiceBias')},'per type')
                switch type
                    case 1 %Delay
                        bias = par.biasD; 
                    case 2 %Risk
                        bias = par.biasR; 
                    case 3 %Effort
                        bias = par.biasE;
                end
            else
                bias = par.bias;
            end        
        %Mood parameter
            switch in.modelspec{strcmp(in.modelcat,'Mood')}
                case 'on bias'
                    bias = bias + par.betaMood * M;                    
            end
        %Compute decision values per choice type
            V1 = k_Reward .* R1; %value of (uncostly) option 1
            if type == 1 %Delay
                V2 = k_Reward .* R2 .* exp(-k_Cost .* C_d .^ par.gammaD);
            elseif type == 2 %Risk
                V2 = k_Reward .* (1 - C_r) .* R2 - k_Cost .* (C_r .* L) .^ par.gammaR;
            elseif type == 3 %Physical Effort
                V2 = k_Reward .* R2 - k_Cost .* C_e .^ par.gammaE; 
            end %if type                
        %Compute probability of chosing option 2 (costly option)
            DV = V2 - V1; %Decision value
            Z(i) = 1./(1 + exp( -(beta.*DV + bias) ) );
    end %for i
end %function

%% Subfunction: get inversion results structure
function [Inversionresults] = GetInversionResults(modelinversion, participants, analysis_list,constraints_list,priors_list)
disp('Getting inversion results...')

% Prepare
    Inversionresults = struct;       
    typenames = {'Delay','Risk','Effort'};
    
% Collect all participants' model inversion results
    for ppt = 1:size(participants,1) %Loop through participants
        %Get data
            disp(['PPT ' num2str(ppt)])
            switch participants.study(ppt)
                case 1; n_choices = 75;
                case 2; n_choices = 120;
                case 3; n_choices = 180;                
                case 4; n_choices = 120;
            end        
        %Loop through inversions
            for mdl = 1:size(analysis_list,1) %List of specified inversions
                parameternames = constraints_list.Properties.VariableNames(~isnan(priors_list{mdl,:}));            
                %Analysis overview (in principle, this only needs to be done for 1 participant)  
                    %The models of the inversion
                        Inversionresults(mdl).analysis = analysis_list{mdl,:};
                    %The inversion's parameter priors and constraints
                        for par = 1:length(parameternames)
                            Inversionresults(mdl).priors.(parameternames{par}) = priors_list.(parameternames{par})(mdl);
                            Inversionresults(mdl).constraints.(parameternames{par}) = constraints_list.(parameternames{par}){mdl};
                        end
                %Posteriors
                    %Model evidence -- for model comparison
                        if ~isempty(modelinversion(ppt).logF)
                            Inversionresults(mdl).logF(ppt) = modelinversion(ppt).logF(mdl);
                        end
                    %Per parameter
                        for par = 1:length(parameternames)
                            if ~isempty(modelinversion(ppt).muPhi)
                                Inversionresults(mdl).muPhi(ppt).(parameternames{par}) = modelinversion(ppt).muPhi(mdl,par);
                                Inversionresults(mdl).SigmaPhi(ppt).(parameternames{par}) = modelinversion(ppt).SigmaPhi(mdl,par);
                            else
                                Inversionresults(mdl).muPhi(ppt).(parameternames{par}) = NaN;
                                Inversionresults(mdl).SigmaPhi(ppt).(parameternames{par}) = NaN;
                            end
                        end
                %Choices, modelled choices, and residuals -- for model visualization
                    for type = 1:length(typenames)
                        if ~isempty(modelinversion(ppt).Y)
                            Inversionresults(mdl).Y(ppt).(typenames{type}) = [modelinversion(ppt).Y{mdl,type} NaN(1,n_choices-length(modelinversion(ppt).Y{mdl,type}))]; %NB: padded with NaNs
                            Inversionresults(mdl).P_LL(ppt).(typenames{type}) = [modelinversion(ppt).P_LL{mdl,type} NaN(1,n_choices-length(modelinversion(ppt).P_LL{mdl,type}))]; %NB: padded with NaNs
                            Inversionresults(mdl).Residuals(ppt).(typenames{type}) = modelinversion(ppt).Residuals{mdl,type};
                        end
                    end                
            end %for mdl
    end %for ppt

end %function

%% Subfunction: positivity transformation
function [y1,y2] = RH_Safepos(x)
% This function produces a close approximation of the absolute value of input x, 
% without the nonlinearity around zero that you get from exponental transformations.
%smoothness parameter
    k = 10;         
%approximate absolute value
    y1 = log(1 + exp(k .* x)) ./ k;
%compute the original value of x if input is y1
    y2 = log(exp(k .* x) - 1) ./ k;
end