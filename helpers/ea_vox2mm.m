function mm=ea_vox2mm(vox, transform)
% converts voxel-coordinates to mm-coordinates
% coords need to be row vector: N*3

if ischar(transform)
    transform = ea_get_affine(transform);
end

% vox = round(vox);
mm = [vox, ones(size(vox,1),1)] * transform';
mm(:,4) = [];
