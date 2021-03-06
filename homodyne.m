function [image phase] = homodyne(kspace,method,window)
%[image phase] = homodyne(kspace,method,window)
%
% Partial Fourier reconstruction for 2D or 3D datasets.
% Leave kspace zeroed where unsampled so the code can
% figure out the sampling automatically.
%
% In this code we obey the laws of physics (1 dim only).
%
% Inputs:
% -kspace is partially filled kspace (2D or 3D) single coil
%
% Optional inputs:
% -method ('homodyne','pocs','least-squares') ['homodyne']
% -window ('step','ramp','quad','cube','quartic') ['cube']

[nx ny nz nc] = size(kspace);

if nc~=1 || nx==1 || ny==1
    error('only 2D or 3D kspace allowed');
end

%% detect sampling
mask = (kspace~=0);
kx = find(any(any(mask,2),3));
ky = find(any(any(mask,1),3));
kz = find(any(any(mask,1),2));

if any(diff(kx)~=1) || any(diff(ky)~=1) || any(diff(kz)~=1)
    error('kspace not centered or not contiguous');
end

% fraction of sampling in kx, ky, kz
f = [numel(kx)/nx numel(ky)/ny];
if nz>1; f(3) = numel(kz)/nz; end

% some checks
threshold = 0.98;

[~,dim] = min(f);
fprintf('partial sampling: [%s]. Using dimension %i.\n',num2str(f,'%.2f '),dim);

if all(f>threshold)
    error('kspace is fully sampled - no need for homodyne');
end

% set default choices
if ~exist('method','var') || isempty(method)
    method = 'homodyne';
end
if ~exist('window','var') || isempty(window)
    window = 'cube';
end

%% set up filters
if dim==1; H = zeros(nx,1,1); index = kx; end
if dim==2; H = zeros(1,ny,1); index = ky; end
if dim==3; H = zeros(1,1,nz); index = kz; end
H(index) = 1;

% high pass filter
H = H + flip(1-H);

center = find(H==1); % symmetric center of kspace
center = [center(1)-1;center(:);center(end)+1]; % pad by 1 point
ramp = linspace(H(center(1)),H(center(end)),numel(center)); % symmetric points add to 2

switch window
    case 'step'
        H(center) = 1;
    case {'linear','ramp'}
        H(center) = ramp;
    case {'quadratic','quad'}
        H(center) = (ramp-1).^2.*sign(ramp-1)+1;
    case {'cubic','cube'}
        H(center) = (ramp-1).^3+1;
    case {'quartic'}
        H(center) = (ramp-1).^4.*sign(ramp-1)+1;    
    otherwise
        error('window not recognized');
end

% low pass filter
L = sqrt(max(0,1-(H-1).^2));

% low resolution phase
phase = bsxfun(@times,L,kspace);
if false
    % smoothing in the other in-plane dimension (no clear benefit)
    if dim~=1; phase = bsxfun(@times,phase,sin(linspace(0,pi,nx)')); end
    if dim~=2; phase = bsxfun(@times,phase,sin(linspace(0,pi,ny) )); end
end
phase = angle(ifftn(ifftshift(phase)));

%% reconstruction

maxit = 10; % no. of iterations to use for iterative methods

switch(method)
    
    case 'homodyne';
        
        image = bsxfun(@times,H,kspace);
        image = ifftn(ifftshift(image)).*exp(-i*phase);
        image = real(image);
        
    case 'pocs';
        
        tmp = kspace;
        
        for iter = 1:maxit
            
            % abs and low res phase
            image = abs(ifftn(tmp));
            tmp = image.*exp(i*phase);
            
            % data consistency
            tmp = fftshift(fftn(tmp));
            tmp(mask) = kspace(mask);
            
        end
        
    case 'least-squares';

        % penalized least squares requires pcgpc.m
        lambda = 1e-2; damp = 1e-4; % exact values not important
        b = reshape(exp(-i*phase).*ifftn(ifftshift(kspace)),[],1);
        tmp = pcgpc(@(x)pcpop(x,mask,phase,lambda,damp),b,[],maxit);
        image = real(reshape(tmp,size(phase)));

    otherwise;
        error('unknown method ''%s''',method);

end

% twix data are always fftshifted
image = fftshift(image);
phase = fftshift(phase);

%% phase constrained projection operator (image <- image)
function y = pcpop(x,mask,phase,lambda,damp)
% y = P' * F' * W * F * P * x + i * imag(x) + damp * x
x = reshape(x,size(phase));
y = exp(i*phase).*x;
y = fftn(y);
y = fftshift(mask).*y;
y = ifftn(y);
y = exp(-i*phase).*y;
y = y + lambda*i*imag(x) + damp*x;
y = reshape(y,[],1);
