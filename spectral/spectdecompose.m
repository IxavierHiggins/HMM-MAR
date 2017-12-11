function [sp_fit,sp_fit_group,sp_profiles] = spectdecompose(sp_fit,options)
%
% From a multitaper or MAR estimation of the states spectra,  
% it factorises the spectral information (which is given by frequency bin)
% into a set of spectral components (which are much fewer than the
% frequency bins), in order to facilitate interpretation and visualisation
% The decomposition can be done either using PCA or non-negative matrix
% factorisation or NNMF (the default). Note that if NNMF is used, the
% solution might somewhat vary every time the function is called. 
%
% INPUTS: 
%
% sp_fit                   The output of hmmspectramar or hmmspectramt. It
%                       should be a cell, where each element corresponds 
%                       to one subject
% options               Struct indicating the decomposing options
%        .Ncomp         Number of components (default 4)
%        .Method        'NNMF' or 'PCA' (default 'NNMF')
%        .Base          What to base the factorisation on: PSD if 'psd' or on
%                       coherence if 'coh' (default: 'coh') 
%        .sp_profiles   Spectral profiles; if supplied, these will be used
%                       instead of computing them (default: empty) 
%        .plot          If the spectral profiles are to be printed (default: 1) 
% 
% OUTPUT:
% 
% sp_fit                A cell with the spectral components, with the same fields  
%                       and dimensions that the input 'sp_fit', but with Ncomp 
%                       components instead of No. frequency bins.
% sp_fit_group          A single struct containing the mean across subjects
%                       of sp_fit
% sp_profiles           The (frequency bins by spectral components) mixing
%                       matrix used to project from (no. of frequency bins
%                       by regions) to (no. of components by regions)
%
% Author: Mark Woolrich, OHBA, University of Oxford (2017)
%         Diego Vidaurre, OHBA, University of Oxford (2017)

if ~iscell(sp_fit)
    error('Variable fit needs to be a cell, with one estimation per subject')
end

if nargin < 3, options = struct(); end
if ~isfield(options,'Ncomp'), options.Ncomp = 4; end
if ~isfield(options,'Method'), options.Method = 'NNMF'; end
if ~isfield(options,'Base'), options.Base = 'coh'; end
if ~isfield(options,'plot'), options.plot = 1; end

p = size(sp_fit{1}.state(1).psd,2); % no. channels
Nf = size(sp_fit{1}.state(1).psd,1); % no. frequencies
N = length(sp_fit); % no. subjects
K = length(sp_fit{1}.state); % no. states
ind_offdiag = triu(true(p),1)==1;

% put coh and psd in temporary arrays
coh_comps = zeros(N,K,Nf,p,p);
psd_comps = zeros(N,K,Nf,p);
for n = 1:N
    for k = 1:K
        psd = sp_fit{n}.state(k).psd;
        coh = sp_fit{n}.state(k).coh;
        for j = 1:p
            psd_comps(n,k,:,j) = psd(:,j,j);
            for l=1:p
                coh_comps(n,k,:,j,l) = coh(:,j,l);
            end
        end
    end
end

if ~isfield(options,'sp_profiles') || isempty(options.sp_profiles)
    
    % Build the matrix that is to be factorised
    if strcmpi(options.Base,'psd')
        X = zeros(Nf,p*K);
        for k=1:K
            ind = (1:p) + (k-1)*p;
            X(:,ind)= squeeze(mean(abs(psd_comps(:,k,:,:)),1));
        end
    else
        p2 = p*(p-1)/2;
        X = zeros(Nf,K*p2); 
        for k = 1:K
            ind = (1:p2) + (k-1)*p2;
            ck = squeeze(mean(abs(coh_comps(:,k,:,:,:)),1));
            X(:,ind) = ck(:,ind_offdiag);
        end
    end
    
    % Doing the decomposition
    if strcmpi(options.Method,'NNMF')
        try
            [~,b] = nnmf(X,options.Ncomp,'replicates',500,'algorithm','als');
        catch
            error('nnmf not found - perhaps the Matlab version is too old')
        end
        sp_profiles = pinv(X') * b';
    else
        try
            [~,b] = pca(X,'NumComponents',options.Ncomp);
        catch
            error('Error running pca - maybe not matlab''s own?')
        end
        sp_profiles = b';
    end

else   
    sp_profiles = options.sp_profiles; 
   
end

% plot if required
if options.plot
    figure;
    if options.Ncomp > 4
        j1 = ceil(options.Ncomp/2); j2 = 2; 
    else
        j1 = options.Ncomp; j2 = 1; 
    end
    for j = 1:options.Ncomp
        subplot(j1,j2,j)
        plot(sp_profiles(:,j),'LineWidth',2.5)
    end
end

% group level
sp_fit_group = struct();
sp_fit_group.state = struct();
for k = 1:K
    psd = squeeze(mean(abs(psd_comps(:,k,:,:)),1))' *  sp_profiles;
    coh = squeeze(mean(abs(coh_comps(:,k,:,:,:)),1));
    coh = (coh(:,ind_offdiag)' * sp_profiles)';
    sp_fit_group.state(k).psd = zeros(options.Ncomp,p,p);
    sp_fit_group.state(k).coh = ones(options.Ncomp,p,p);
    for j = 1:p
        sp_fit_group.state(k).psd(:,j,j) = psd(j,:)';
    end
    for i = 1:options.Ncomp
        graphmat = zeros(p);
        graphmat(ind_offdiag) = coh(i,:);
        graphmat=(graphmat+graphmat') + eye(p);
        sp_fit_group.state(k).coh(i,:,:) = graphmat;
    end
end

for n = 1:N
    sp_fit{n} = struct();
    sp_fit{n}.state = struct();
    for k = 1:K
        psd = squeeze(abs(psd_comps(n,k,:,:)))' *  sp_profiles;
        coh = squeeze(abs(coh_comps(n,k,:,:,:)));
        coh = (coh(:,ind_offdiag)' * sp_profiles)';
        sp_fit{n}.state(k).psd = zeros(options.Ncomp,p,p);
        sp_fit{n}.state(k).coh = ones(options.Ncomp,p,p);
        for j = 1:p
            sp_fit{n}.state(k).psd(:,j,j) = psd(j,:)';
        end
        for i = 1:options.Ncomp
            graphmat = zeros(p);
            graphmat(ind_offdiag) = coh(i,:);
            graphmat=(graphmat+graphmat') + eye(p);
            sp_fit{n}.state(k).coh(i,:,:) = graphmat;
        end
    end
end
    
end
