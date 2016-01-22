function ea_acpc2mni(hobf,hevent,leadfig)

% fidpoints_mm=[-0.4,1.53,-2.553       % AC
%     -0.24,-26.314,-4.393            % PC
%     -0.4,1.53,20];              % Midsag
fidpoints_mm=[0.25,1.298,-5.003       % AC
    -0.188,-24.756,-2.376            % PC
    0.25,1.298,55];              % Midsag

uidir=getappdata(leadfig,'uipatdir');

% prompt for ACPC-coordinates:
res = ea_acpcquery;
if ischar(res)
    return
end
acpc=[res.xmm,res.ymm,res.zmm];
[FileName,PathName] = uiputfile('ACPC2MNI_Mapping.nii','Save Mapping...');

leaddir=[fileparts(which('lead')),filesep];

if ~length(uidir)
ea_error('Please choose and normalize patients first.');
end

disp('*** Converting ACPC-coordinates to MNI based on normalizations in selected patients.');
ea_dispercent('Iterating through patients');
for pt=1:length(uidir)
    ea_dispercent(pt/length(uidir));
    directory=[uidir{pt},filesep];
    whichnormmethod=ea_whichnormmethod(directory);
    switch whichnormmethod
        case 'ea_normalize_spmdartel' % use dartel MNI template
            tempfile=[leaddir,'templates',filesep,'dartel',filesep,'dartelmni_6.nii'];
        case 'ea_normalize_ants'
            ea_error('ANTs normalization is not supported for ACPC2MNI conversion as of now.');
        otherwise % use mni_hires
            tempfile=[leaddir,'templates',filesep,'mni_hires.nii'];
    end
    
    fidpoints_vox=ea_getfidpoints(fidpoints_mm,tempfile);
    
    [~,ptname]=fileparts(uidir{pt});
    options.prefs=ea_prefs(ptname);
    
    % warp into patient space:
    
    [fpinsub_mm] = ea_map_coords(fidpoints_vox', '', [directory,'y_ea_normparams.nii'], [directory,options.prefs.prenii_unnormalized]);
    fpinsub_mm=fpinsub_mm';
    
    
    fid(pt).AC=fpinsub_mm(1,:);
    fid(pt).PC=fpinsub_mm(2,:);
    fid(pt).MSP=fpinsub_mm(3,:);

    % x-dimension
    A=fpinsub_mm(3,:)-fpinsub_mm(1,:);
    B=fpinsub_mm(2,:)-fpinsub_mm(1,:);
    xvec=cross(A,B); %normal to given plane
    xvec=xvec/norm(xvec);
    % y-dimension (just move from ac to pc and scale by y dimension):
    yvec=(fpinsub_mm(2,:)-fpinsub_mm(1,:));
    yvec=yvec/norm(yvec);
    
    % z-dimension (just move from ac to msag plane by z dimension):
    zvec=(fpinsub_mm(3,:)-fpinsub_mm(1,:));
    zvec=zvec/norm(zvec);    
    switch res.acmcpc
        case 1 % relative to AC:
            warpcoord_mm=fpinsub_mm(1,:)+acpc(1)*xvec+acpc(2)*yvec+acpc(3)*zvec;
        case 2 % relative to midcommissural point:
            warpcoord_mm=mean([fpinsub_mm(1,:);fpinsub_mm(2,:)],1)+acpc(1)*xvec+acpc(2)*yvec+acpc(3)*zvec;
        case 3 % relative to PC:
            warpcoord_mm=fpinsub_mm(2,:)+acpc(1)*xvec+acpc(2)*yvec+acpc(3)*zvec;
    end
    anat=ea_load_nii([directory,options.prefs.prenii_unnormalized]);
    warpcoord_mm=[warpcoord_mm';1];
    warpcoord_vox=anat.mat\warpcoord_mm;
    warpcoord_vox=warpcoord_vox(1:3);
    fid(pt).WarpedPointNative=warpcoord_mm(1:3)';
    % re-warp into MNI:
    try
        [warpinmni_mm] = ea_map_coords(warpcoord_vox, '', [directory,'y_ea_inv_normparams.nii'], tempfile);
    catch
        ea_redo_inv(directory,options);
        [warpinmni_mm] = ea_map_coords(warpcoord_vox, '', [directory,'y_ea_inv_normparams.nii'], tempfile);
    end
    
    warppts(pt,:)=warpinmni_mm';
    fid(pt).WarpedPointMNI=warppts(pt,:);
    
    if res.mapmethod==2
        anat.img(:)=0;
        anat.img(round(warpcoord_vox(1)),round(warpcoord_vox(2)),round(warpcoord_vox(3)))=1;
        anat.fname=[directory,'ACPCquerypoint.nii'];
        spm_write_vol(anat,anat.img);

        % warp into nativespace
        matlabbatch{1}.spm.util.defs.comp{1}.def = {[directory,'y_ea_normparams.nii']};
        matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {[directory,'ACPCquerypoint.nii']};
        matlabbatch{1}.spm.util.defs.out{1}.pull.savedir.saveusr = {directory};
        matlabbatch{1}.spm.util.defs.out{1}.pull.interp = 4;
        matlabbatch{1}.spm.util.defs.out{1}.pull.mask = 1;
        matlabbatch{1}.spm.util.defs.out{1}.pull.fwhm = [0 0 0];
        cfg_util('run',{matlabbatch});
        clear matlabbatch
        wfis{pt}=[directory,'wACPCquerypoint.nii'];
    end
end
ea_dispercent(1,'end');

% create clear cut version:
if res.mapmethod==1
    bb=ea_load_nii([leaddir,'templates',filesep,'bb.nii']);
    bb.img(:)=0;
    warppts_vox=[warppts';ones(1,size(warppts,1))];
    warppts_vox=round(bb.mat\warppts_vox);
    
    for pnt=1:size(warppts_vox,2);
        try
            bb.img(warppts_vox(1,pnt),warppts_vox(2,pnt),warppts_vox(3,pnt))=1;
        end
    end
    
    bb.fname=[PathName,FileName];
    spm_write_vol(bb,bb.img);
else
    % create innativespacemapped files:
    
    matlabbatch{1}.spm.util.imcalc.input = wfis;
    matlabbatch{1}.spm.util.imcalc.output = [FileName];
    matlabbatch{1}.spm.util.imcalc.outdir = {PathName};
    matlabbatch{1}.spm.util.imcalc.expression = 'sum(X)';
    matlabbatch{1}.spm.util.imcalc.var = struct('name', {}, 'value', {});
    matlabbatch{1}.spm.util.imcalc.options.dmtx = 1;
    matlabbatch{1}.spm.util.imcalc.options.mask = 0;
    matlabbatch{1}.spm.util.imcalc.options.interp = 1;
    matlabbatch{1}.spm.util.imcalc.options.dtype = 4;
    cfg_util('run',{matlabbatch});
    clear matlabbatch
end

% smooth clear version:
matlabbatch{1}.spm.spatial.smooth.data = {[PathName,FileName,',1']};
matlabbatch{1}.spm.spatial.smooth.fwhm = [1 1 1];
matlabbatch{1}.spm.spatial.smooth.dtype = 0;
matlabbatch{1}.spm.spatial.smooth.im = 0;
matlabbatch{1}.spm.spatial.smooth.prefix = 's';
cfg_util('run',{matlabbatch});
clear matlabbatch

[pth,fn,ext]=fileparts(bb.fname);
ea_crop_nii([pth,filesep,fn,ext]);
ea_crop_nii([pth,filesep,'s',fn,ext]);

assignin('base','fid',fid);



function ea_redo_inv(directory,options)
matlabbatch{1}.spm.util.defs.comp{1}.inv.comp{1}.def = {[directory,'y_ea_normparams.nii']};
matlabbatch{1}.spm.util.defs.comp{1}.inv.space = {[directory,options.prefs.prenii_unnormalized]};
matlabbatch{1}.spm.util.defs.out{1}.savedef.ofname = 'ea_inv_normparams.nii';
matlabbatch{1}.spm.util.defs.out{1}.savedef.savedir.saveusr = {directory};
spm_jobman('run',{matlabbatch});


function fidpoints_vox=ea_getfidpoints(fidpoints_mm,tempfile)

V=spm_vol(tempfile);
fidpoints_vox=V(1).mat\[fidpoints_mm,ones(size(fidpoints_mm,1),1)]';
fidpoints_vox=fidpoints_vox(1:3,:)';

function whichnormmethod=ea_whichnormmethod(directory)
load([directory,'ea_normmethod_applied']);
cnt=0;
while 1
    whichnormmethod=norm_method_applied{end-cnt};
    switch whichnormmethod
        case 'ea_normalize_apply_normalization'
            cnt=cnt+1;
        otherwise
            break
    end

end



function o=cell2acpc(acpc)

acpc=ea_strsplit(acpc{1},' ');
if length(acpc)~=3
    acpc=ea_strsplit(acpc{1},',');
    if length(acpc)~=3
        ea_error('Please enter 3 values separated by spaces or commas.');
    end
end
for dim=1:3
o(dim,1)=str2double(acpc{dim});
end
