function varargout = ea_genvat_butenko(varargin)
% Wrapper for OSS-DBS for VTA calculation

if nargin==5
    acoords=varargin{1};
    S=varargin{2};
    side=varargin{3};
    options=varargin{4};
    stimname=varargin{5};
elseif nargin==6
    acoords=varargin{1};
    S=varargin{2};
    side=varargin{3};
    options=varargin{4};
    stimname=varargin{5};
    lgfigure=varargin{6};
elseif nargin==1 && ischar(varargin{1}) % return name of method.
    varargout{1} = 'OSS-DBS (Butenko 2020)';
    return
end

directory = [options.root, options.patientname, filesep];

if ~exist([directory,'stimulations',filesep,ea_nt(options.native),S.label],'dir')
    mkdir([directory,'stimulations',filesep,ea_nt(options.native),S.label]);
end

options = ea_assignpretra(options);

%% Set MRI_data_name
% Segment MRI
if options.native
    if ~isfile([directory, 'c1', options.prefs.prenii_unnormalized]) ...
            || ~isfile([directory, 'c2', options.prefs.prenii_unnormalized]) ...
            || ~isfile([directory, 'c3', options.prefs.prenii_unnormalized])
        ea_newseg(directory, options.prefs.prenii_unnormalized, 0, options, 1);
    end

    segMaskDir = directory;
    segFileSuffix = options.prefs.prenii_unnormalized;
else
    if ~isfile([ea_space, 'c1mask.nii']) ...
            || ~isfile([ea_space, 'c2mask.nii']) ...
            || ~isfile([ea_space, 'c3mask.nii'])
        ea_newseg(ea_space, 't1.nii', 0, options, 1);
        movefile([ea_space, 'c1t1.nii'], [ea_space, 'c1mask.nii']);
        movefile([ea_space, 'c2t1.nii'], [ea_space, 'c2mask.nii']);
        movefile([ea_space, 'c3t1.nii'], [ea_space, 'c3mask.nii']);
    end

    segMaskDir = ea_space;
    segFileSuffix = 'mask.nii';
end

if ~isfile([segMaskDir, 'segmask.nii'])
    % Binarize segmentations
    c1 = ea_load_nii([segMaskDir, 'c1', segFileSuffix]);
    c2 = ea_load_nii([segMaskDir, 'c2', segFileSuffix]);
    c3 = ea_load_nii([segMaskDir, 'c3', segFileSuffix]);
    c1.img = c1.img>0.5;
    c2.img = c2.img>0.5;
    c3.img = c3.img>0.5;

    % Fuse segmentations by voting in the order  CSF -> WM -> GM
    c2.img(c3.img) = 0;
    c1.img(c2.img | c3.img) = 0;
    c1.fname = [segMaskDir, 'segmask.nii'];
    c1.dt = [4 0];
    c1.img = int16(c1.img) + int16(c2.img)*2 + int16(c3.img)*3;
    ea_write_nii(c1);
end

%% Set patient folder
settings.Patient_folder = directory;

%% Set native/MNI flag
settings.Estimate_In_Template = options.prefs.machine.vatsettings.estimateInTemplate;

%% Set MRI path
% Put the MRI file in stimulation folder
copyfile([segMaskDir, 'segmask.nii'], [directory,'stimulations',filesep,ea_nt(options.native),S.label]);
settings.MRI_data_name = [directory,'stimulations',filesep,ea_nt(options.native),S.label,filesep,'segmask.nii'];

%% Scaled tensor data
settings.DTI_data_name = ''; % 'dti_tensor.nii';

%% Index of the tissue in the segmented MRI data
settings.GM_index = 1;
settings.WM_index = 2;
settings.CSF_index = 3;

settings.default_material = 'GM'; % GM, WM or CSF

%% Electrodes information
settings.Electrode_type = options.elmodel;

% Reload reco since we need to decide whether to use native or MNI coordinates.
[~, ~, markers] = ea_load_reconstruction(options);
coords_mm = ea_resolvecoords(markers, options);

% Head
settings.Implantation_coordinate = nan(length(coords_mm), 3);
for i=1:length(coords_mm)
    if ~isempty(coords_mm{i})
        settings.Implantation_coordinate = [settings.Implantation_coordinate; coords_mm{i}(1,:)];
    end
end

% Tail
settings.Second_coordinate = nan(length(coords_mm), 3);
for i=1:length(coords_mm)
    if ~isempty(coords_mm{i})
        settings.Second_coordinate = [settings.Second_coordinate; coords_mm{i}(end,:)];
    end
end

% Rotation around the lead axis in degrees
settings.Rotation_Z = 0.0;

%% Stimulation Information
source = {find(S.amplitude{1},1), find(S.amplitude{2},1)};

% 0 - VC; 1 - CC
settings.current_control = [];
if ~isempty(source{1})
    settings.current_control = [settings.current_control; uint8(~eval(['S.Rs', num2str(source{1}), '.va']))];
end
if ~isempty(source{2})
    settings.current_control = [settings.current_control; uint8(~eval(['S.Ls', num2str(source{2}), '.va']))];
end

% Signal vector: give an amplitude. If CC; 0.0 refers to 0 V (ground)
% other numbers are in mA. None is for floating potentials
amp = [S.amplitude{1}(source(1))
    S.amplitude{2}(source(2))];
settings.Phi_vector = nan(2,options.elspec.numel);
settings.Case_grounding = zeros(2,1);

for side = 1:2
    switch side
        case 1
            sideCode = 'R';
            cntlabel = {'k0','k1','k2','k3','k4','k5','k6','k7'};
        case 2
            sideCode = 'L';
            cntlabel = {'k8','k9','k10','k11','k12','k13','k14','k15'};
    end

    stimSource = S.([sideCode, 's', num2str(source(side))]);
    for cnt = 1:options.elspec.numel
        if S.activecontacts{side}(cnt)
            switch stimSource.(cntlabel{cnt}).pol
                case 1 % Negative, cathode
                    settings.Phi_vector(side, cnt) = -amp(side)*stimSource.(cntlabel{cnt}).perc/100;
                case 2 % Postive, anode
                    settings.Phi_vector(side, cnt) = amp(side)*stimSource.(cntlabel{cnt}).perc/100;
            end
        end
    end
    if stimSource.case.perc == 100
        settings.Case_grounding(side) = 1;
    end
end

% Threshold for Astrom VTA (V/mm)
settings.Activation_threshold_VTA = options.prefs.machine.vatsettings.butenko_ethresh;

%% Save settings for OSS-DBS
parameterFile = [directory, 'stimulations', filesep, ea_nt(options.native), S.label, filesep, 'oss-dbs_parameters.mat'];
save(parameterFile, 'settings');

%% Run OSS-DBS
cd([ea_getearoot, 'ext_libs/OSS-DBS/OSS_platform']);
system(['python3 ', ea_getearoot, 'ext_libs/OSS-DBS/OSS_platform/OSS-DBS_LeadDBS_integrator.py ', parameterFile]);

%% Save results
% Convert the unit from V/mm to V/m for efield VTA (to be consistent as in Lead-DBS)
efieldVAT = {'vat_efield_right.nii', 'vat_efield_left.nii'};
for f=1:length(efieldVAT)
    efield = ea_load_nii([directory, 'stimulations', filesep, ea_nt(options.native), S.label, filesep, efieldVAT{f}]);
    efield.img = efield.img*1000;
    ea_write_nii(efield);
end

% ea_axonact2ftr([directory, 'stimulations', filesep, ea_nt(options.native), S.label, filesep, Activation]);