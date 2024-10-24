# MoodChoicePhysiology2024
This repository contains supporting material of the paper "Heerema &amp; Pessiglione (2024) How mood-related physiological states bias economic decisions".

### Literature overview table
The file `Literature overview table.xlsx` lists all the studies we could find that employed some form of mood/emotion induction procedure, followed by economic cost-benefit trade-offs. Design properties and main results per studies are listed. Information from this file was used in the introduction and discussion of the paper.

### Stimuli
The sheet `Stimuli overiew table.xlsx` contains lists of the text vignettes (in English and in French) and of the music fragments, with their average ratings obtained from a pilot study.\
Music files as used in the exploratory and confirmatory studies can be accessed in the `Music stimuli` folder.

### Analysis files
The folder `Analysis code` contains the following:
* `participants.mat`: an overview with demographic information and experimental features for each participant.
* `Analysis_ModelFree.m`: runs the model-free analysis of ratings and choice behaviour. Summary results are saved into the `Results` folder.
* `Analysis_ModelBased.m`: runs the model-based analysis of choice behaviour using the VBA toolbox (see [https://mbb-team.github.io/VBA-toolbox/](url)). A list of models is created and inverted, and then the models are compared. Model data from the (winning) model is created and stored, along with results from the preceding steps, in the `Results` folder.
* `Analysis_Physiology.m`: analyses physiological data recorded at the time of the emotion induction. Requires MATLAB's Signal Processing Toolbox to be installed, as well as Fieldtrip ([https://www.fieldtriptoolbox.org/](url)) and PsPM ([https://bachlab.github.io/PsPM/](url)).
* `Analysis_Eyetracking.m`: analyses gaze patterns recorded during choices.
* `Visualize_FigureX.m`: recreates the figures from the publication, using the summary data stored in the `Results` folder.

### Raw data
Raw data can be accessed here: [https://1drv.ms/f/s!AlQbJDY7oqVPjd1zdoWe0b9q1N8NLg?e=SQdpeN](url).\
Data is stored in a unique folder per participant:
* Each folder contains a main file `AllData.mat`, with the following variables:
  * _trialinfo_: information about each individual choice trial in the main experiment, and the participant's choice behaviour
  * _calibration_: information and choice behaviour from choice calibration trials at the beginning of the experiment
  * _affect_: information and behavioural results from each individual emotion induction in the main experiment
  * _pupil_: per-induction pupil diameter response data
  * _EDA_: per-induction electrodermal activity 
  * _EMG_: per-induction electromyography 
* In studies where physiology was recorded with a BIOPAC setup (see [https://www.biopac.com/](url)), the file `BiopacDataset.mat` contains the raw data as outputted by the _AcqKnowledge_ software.
* In studies where eyetracking was performed with an EyeTribe camera (see [https://github.com/EyeTribe/documentation](url)), the file `AllGazeData.mat` contains the per-choice gaze position data. The raw data outputted by the Eyetribe (also containing raw pupil diameter data) can be found in the folder `Eyetracking`. Each file contains data from one trial (i.e. induction followed by a series of choice trials).

The meaning of each of the variables in each of these files is explained in the file `Dataset variables explainer.xlsx`.
