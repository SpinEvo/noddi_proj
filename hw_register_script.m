clc;clear;close all;
project_path = '/home/hongwei/***';
code_path = [project_path,filesep,'code']; cd(code_path);
niifolder = [project_path,filesep,'nifti'];
sub_name = {dir(niifolder).name}; sub_name(1:2) = []; sub_name = sub_name';
subfolder = strcat(niifolder,filesep,sub_name);

%% Crop T1W & T2Flair - robustfov
T1Wfolder = strcat(subfolder,filesep,'T1W',filesep,'T1W.nii');
CropT1Wfolder = strcat(subfolder,filesep,'T1W',filesep,'T1W_crop.nii');
for i = 1:length(T1Wfolder)
    command = ['robustfov -i ',T1Wfolder{i},' -r ',CropT1Wfolder{i},' -b 180'];
    unix(command);
    cd(fileparts(CropT1Wfolder{i})); gunzip('T1W_crop.nii.gz');
    delete('T1W_crop.nii.gz'); cd(code_path);
end

FLAIRfolder = strcat(subfolder,filesep,'FLAIR',filesep,'FLAIR.nii');
CropFLAIRfolder = strcat(subfolder,filesep,'FLAIR',filesep,'FLAIR_crop.nii');
for i = 1:length(FLAIRfolder)
    command = ['robustfov -i ',FLAIRfolder{i},' -r ',CropFLAIRfolder{i},' -b 180'];
    unix(command);
    cd(fileparts(CropFLAIRfolder{i})); gunzip('FLAIR_crop.nii.gz');
    delete('FLAIR_crop.nii.gz'); cd(code_path);
end

%% Register - ants
addpath(genpath('/opt/MATLAB_toolbox/spm12'));
addpath(genpath('/opt/MATLAB_toolbox/DPABI_V6.0_210501'));
b0_ref_folder = strcat(subfolder,filesep,'DTI',filesep,'b0.nii');
for i = 1:length(subfolder)
    [b0,header] = y_Read([subfolder{i},filesep,'DTI',filesep,'DTI_topup_eddy.nii.gz'],1);
    y_Write(b0,header,[subfolder{i},filesep,'DTI',filesep,'b0.nii']);
end

% Rigid: T1W to T2Flair & DTI
for i = 1:length(CropT1Wfolder)
    cd(fileparts(CropT1Wfolder{i}));
    command = ['antsRegistrationSyN.sh -d 3 -f ',FLAIRfolder{i},' -m ',CropT1Wfolder{i},' -t ', '''r''',' -o T12FLAIR_'];
    unix(command);
    command = ['antsRegistrationSyN.sh -d 3 -f ',b0_ref_folder{i},' -m ',CropT1Wfolder{i},' -t ', '''r''',' -o T12DTI_'];
    unix(command);
    cd(code_path);
end

maskfolder = strcat(subfolder,filesep,'FLAIR',filesep,'mask.nii');
% Rigid: T12FALIR_T1W to T12DTI_T1W
for i = 1:length(CropT1Wfolder)
    cd(fileparts(CropT1Wfolder{i}));
    command = ['antsRegistrationSyN.sh -d 3 -f T12DTI_Warped.nii.gz -m T12FLAIR_Warped.nii.gz -t ', '''r''',' -o FLAIR2DTI_'];
    unix(command);
    command = ['cp ',maskfolder{i},' ',fileparts(CropT1Wfolder{i})]; unix(command);
    command = 'antsApplyTransforms -d 3 -i mask.nii -o FLAIR2DTI_mask.nii -r T12DTI_Warped.nii.gz -t FLAIR2DTI_0GenericAffine.mat -n GenericLabel';
    unix(command);
    command = ['antsApplyTransforms -d 3 -i ',FLAIRfolder{i},' -o FLAIR2DTI_FLAIR.nii -r T12DTI_Warped.nii.gz -t FLAIR2DTI_0GenericAffine.mat'];
    unix(command);
    cd(code_path);
end

%% Segment - fast
T12DTIfolder = strcat(subfolder,filesep,'T1W',filesep,'T12DTI_Warped.nii.gz');
for i = 1:length(T12DTIfolder)
    cd(fileparts(T12DTIfolder{i}));
    % bet
    command = 'bet2 T12DTI_Warped.nii.gz T12DTI_Warped_brain -m -f 0.5';
    unix(command);
    % fast
    command = 'fast -s 1 -t 1 -n 3 -g -B -o Seg T12DTI_Warped_brain';
    unix(command);
    cd(code_path);
end

%% Normalize MNI to DTI space - ants
template_path = [project_path,filesep,'template_used'];
% Copy template files
for i = 1:length(T12DTIfolder)
    cd(fileparts(T12DTIfolder{i}));
    sub_template_folder = [fileparts(T12DTIfolder{i}),filesep,'template'];
    if exist(sub_template_folder,'dir') == 7
        rmdir(sub_template_folder,'s');
    end
    mkdir(sub_template_folder);
    
    command = ['cp ',template_path,filesep,'MNI152_T1_2mm.nii ',sub_template_folder]; unix(command);
    command = ['cp ',template_path,filesep,'MNI2mm_CorticalGM.nii ',sub_template_folder]; unix(command);
    command = ['cp ',template_path,filesep,'MNI2mm_deepGM.nii ',sub_template_folder]; unix(command);
    command = ['cp ',template_path,filesep,'MNI2mm_half_hemi_L1R2.nii ',sub_template_folder]; unix(command);
    command = ['cp ',T12DTIfolder{i},' ',sub_template_folder]; unix(command);
    cd(code_path);
end

for i = 1:length(T12DTIfolder)
    sub_template_folder = [fileparts(T12DTIfolder{i}),filesep,'template']; cd(sub_template_folder);
    % Step-1: rigid
    command = ['antsRegistrationSyN.sh -d 3 -f T12DTI_Warped.nii.gz -m MNI152_T1_2mm.nii -t ', '''r''',' -o step1_']; unix(command);
    % Step-2: non-rigid
    command = 'antsRegistrationSyN.sh -d 3 -f T12DTI_Warped.nii.gz -m step1_Warped.nii.gz -o step2_'; unix(command);
    
    command = 'antsApplyTransforms -d 3 -i MNI2mm_CorticalGM.nii -o DTI_space_CorticalGM.nii -r T12DTI_Warped.nii.gz -t step2_1Warp.nii.gz -t step2_0GenericAffine.mat -t step1_0GenericAffine.mat -n GenericLabel';
    unix(command);
    command = 'antsApplyTransforms -d 3 -i MNI2mm_deepGM.nii -o DTI_space_deepGM.nii -r T12DTI_Warped.nii.gz -t step2_1Warp.nii.gz -t step2_0GenericAffine.mat -t step1_0GenericAffine.mat -n GenericLabel';
    unix(command);
    command = 'antsApplyTransforms -d 3 -i MNI2mm_half_hemi_L1R2.nii -o DTI_space_half_hemi_L1R2.nii -r T12DTI_Warped.nii.gz -t step2_1Warp.nii.gz -t step2_0GenericAffine.mat -t step1_0GenericAffine.mat -n GenericLabel';
    unix(command);
    cd(code_path);
end

%% Create ICH / PHE mirror ROIs
for i = 1:length(T12DTIfolder)
    cd(fileparts(T12DTIfolder{i}));
    sub_template_folder = [fileparts(T12DTIfolder{i}),filesep,'template'];
    command = ['cp FLAIR2DTI_mask.nii ',sub_template_folder]; unix(command);
    cd(sub_template_folder);
    command = 'antsApplyTransforms -d 3 -i FLAIR2DTI_mask.nii -o MNI2mm_lesion_mask.nii -r MNI2mm_deepGM.nii -t step2_1InverseWarp.nii.gz -t [step2_0GenericAffine.mat,1] -t [step1_0GenericAffine.mat,1] -n GenericLabel';
    unix(command);
    command = 'antsApplyTransforms -d 3 -i T12DTI_Warped.nii.gz -o MNI2mm_T12DTI_Warped.nii -r MNI2mm_deepGM.nii -t step2_1InverseWarp.nii.gz -t [step2_0GenericAffine.mat,1] -t [step1_0GenericAffine.mat,1]';
    unix(command);
    [lesion_mask,header] = y_Read('MNI2mm_lesion_mask.nii');
    lesion_mask_mirror = flip(lesion_mask);
    y_Write(lesion_mask_mirror,header,'MNI2mm_lesion_mask_mirror');
    command = 'antsApplyTransforms -d 3 -i MNI2mm_lesion_mask_mirror.nii -o DTI_space_lesion_mask_mirror.nii -r T12DTI_Warped.nii.gz -t step2_1Warp.nii.gz -t step2_0GenericAffine.mat -t step1_0GenericAffine.mat -n GenericLabel';
    unix(command);
    cd(code_path);
end
rmpath(genpath('/opt/MATLAB_toolbox/spm12'));
rmpath(genpath('/opt/MATLAB_toolbox/DPABI_V6.0_210501'));
