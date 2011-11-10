function varargout = resfields_perturb(Sys,Exp,Opt)

% Compute resonance fields based on formulas from
% Iwasaki, J.Magn.Reson. 16, 417-423 (1974)

% Assert correct Matlab version
error(chkmlver);

% Check number of input arguments.
switch (nargin)
  case 0, help(mfilename); return;
  case 2, Opt = struct('unused',NaN);
  case 3,
  otherwise
    error('Use two or three inputs: refields_perturb(Sys,Exp) or refields_perturb(Sys,Exp,Opt)!');
end

% A global variable sets the level of log display. The global variable
% is used in logmsg(), which does the log display.
if ~isfield(Opt,'Verbosity'), Opt.Verbosity = 0; end
global EasySpinLogLevel;
EasySpinLogLevel = Opt.Verbosity;

% Spin system
%------------------------------------------------------
[Sys,err] = validatespinsys(Sys);
error(err);
S = Sys.S;
highSpin = any(S>1/2);

if Sys.nElectrons~=1
  err = sprintf('Perturbation theory available only for systems with 1 electron. Yours has %d.',Sys.nElectrons);
end
if any(Sys.AStrain)
  err = ('A strain (Sys.AStrain) not supported with perturbation theory. Use matrix diagonalization or remove Sys.AStrain.');
end
if highSpin && any(Sys.DStrain) && any(mod(Sys.S,1))
  err = ('D strain not supported for half-integer spins with perturbation theory. Use matrix diagonalization or remove Sys.DStrain.');
end
if any(Sys.DStrain(:)) && any(Sys.Dpa(:))
  err = 'D stain cannot be used with tilted D tensors.';
end
error(err);


if Sys.fullg
  g = Sys.g;
else
  Rg = erot(Sys.gpa);
  g = Rg*diag(Sys.g)*Rg.';
end

if highSpin
  % make D traceless (needed for Iwasaki expressions)
  if Sys.fullD
    D = Sys.D - sum(diag(Sys.D))/3;
  else
    D = diag(Sys.D-mean(Sys.D));
    RD = erot(Sys.Dpa);
    D = RD*D*RD.';
  end
end

I = Sys.I;
nNuclei = Sys.nNuclei;
if (nNuclei>0)
  nStates = 2*I+1;
else
  nStates = 1;
end

% Guard against zero hyperfine couplings
% (otherwise inv(A) gives error further down)
if nNuclei>0
  if ~Sys.fullA
    if any(Sys.A(:)==0)
      error('All hyperfine coupling constants must be non-zero.');
    end
  end
end

for iNuc = 1:nNuclei
  if Sys.fullA
    A{iNuc} = Sys.A((iNuc-1)*3+(1:3),:);
  else
    RA = erot(Sys.Apa(iNuc,:));
    A_ = diag(Sys.A(iNuc,:))*Sys.Ascale(iNuc);
    A{iNuc} = RA*A_*RA';
  end
  mI{iNuc} = -I(iNuc):I(iNuc);
  idxn{iNuc} = 1:nStates(iNuc);
end


% Experiment
%------------------------------------------------------
err = '';
if ~isfield(Exp,'mwFreq'), err = 'Exp.mwFreq is missing.'; end
if ~isfield(Exp,'Orientations'), err = 'Exp.Orientations is missing'; end
if isfield(Exp,'Detection'), err = 'Exp.Detection is obsolete. Use Exp.Mode instead.'; end

if isfield(Exp,'Mode')
  if strcmp(Exp.Mode,'parallel')
    err = 'Parallel mode EPR cannot be done with perturbation theory. Use matrix diagonalization.';
  end
end
if isfield(Exp,'Temperature')
  if numel(Exp.Temperature)~=1
    err = 'Exp.Temperature must be a single number.';
  end
  if isinf(Exp.Temperature)
    err = 'If given, Exp.Temperature must have a finite value.';
  end
else
  Exp.Temperature = NaN;
end
if isfield(Exp,'CrystalSymmetry')
  if ~isempty(Exp.CrystalSymmetry)
    err = 'Space groups are not supported with perturbation theory.';
  end
end
error(err);

nu = Exp.mwFreq*1e3;
Ori = Exp.Orientations;

% Orientations
%------------------------------------------------------
[n1,n2] = size(Ori);
if ((n2==2)||(n2==3)) && (n1~=2) && (n1~=3)
  Ori = Ori.';
end
[nAngles,nOrientations] = size(Ori);
switch nAngles
 case 2,
  IntegrateOverChi = 1;
  Ori(3,end) = 0; % Entire chi column is set to 0.
 case 3,
  IntegrateOverChi = 0;
 otherwise
  error('Orientations array has %d rows instead of 2 or 3.',nAngles);
end


% Options
%----------------------------------------------------------
if ~isfield(Opt,'PerturbOrder'), Opt.PerturbOrder = 2; end
if ~isfield(Opt,'DirectAccumulation'), Opt.DirectAccumulation = 0; end
secondOrder = (Opt.PerturbOrder==2);
if secondOrder
  logmsg(1,'2nd order perturbation theory');
else
  logmsg(1,'1st order perturbation theory');
end
if (Opt.PerturbOrder>2)
  error('Only 1st and 2nd order perturbation theory are supported.');
end
FourierDomain = 0;

%----------------------------------------------------------



E0 = nu;

for iNuc = 1:nNuclei
  A_ = A{iNuc};
  detA(iNuc) = det(A_);
  invA{iNuc} = inv(A_); % gives an error with zero h couplings
  trAA(iNuc) = trace(A_.'*A_);
end

if highSpin
  trDD = trace(D^2);
end
II1 = I.*(I+1);

directAccumulation = Opt.DirectAccumulation;

if directAccumulation
else
  if (nNuclei>0)
    idxn = allcombinations(idxn{:});
  else
    idxn = 1;
  end
  nNucTrans = size(idxn,1);
end

if directAccumulation
  E1A = zeros(max(nStates),nNuclei);
  Baxis = linspace(Exp.Range(1),Exp.Range(2),Exp.nPoints);
  dB = Baxis(2)-Baxis(1);
  spec = zeros(1,Exp.nPoints);
end

% Prefactor for transition probability
g1pre = det(g)*inv(g).';
gg = g'*g;
trgg = trace(gg);


% Loop over all orientations
for iOri = nOrientations:-1:1
  [h1x,h1y,h] = erot(Ori(:,iOri));
  h = h.';
  vecs(:,iOri) = h;
  
  % zero-order resonance field
  geff(iOri) = norm(g*h);
  u = g*h/geff(iOri);
  B0 = E0/(geff(iOri)*bmagn);
  
  % frequency to field conversion factor
  preOri = 1e6*planck/(geff(iOri)*bmagn);

  % g intensity (see Weil/Bolton p.104, also Abragam/Bleaney p.136 eq. 3.10b)
  % reduce with cross(M*a,M*b) = det(M)*inv(M).^2*cross(a,b)
  % A.Lund et al, 2008, appendix, eq. (A5)
  if IntegrateOverChi
    %g1(iOri) = pi*(norm(g1pre*h1x.')^2 + norm(g1pre*h1y.')^2)/geff(iOri)^2;
    g1(iOri) = pi*(trgg-u.'*gg*u);
  else
    g1(iOri) = norm(g1pre*h1x.')^2/geff(iOri)^2;
  end
  % Aasa-Vangard 1/g factor
  dBdE = 1*(planck/bmagn)*1e9/geff(iOri);
  g1(iOri) = g1(iOri)*dBdE;
  % add units and prefactor to match matrix diagonalization value
  g1(iOri) = (bmagn/planck/1e9/2)^2*g1(iOri);

  if highSpin
    Du = D*u;
    uDu = u.'*Du;
    uDDu = Du.'*Du;
    D1sq = uDDu - uDu^2;
    D2sq = 2*trDD + uDu^2 - 4*uDDu;
  end

  imS = 0;
  for mS = S:-1:-S+1
    imS = imS + 1;

    % first-order
    if highSpin
      E1D = -uDu/2*(3-6*mS);
    else
      E1D = 0;
    end
    if (nNuclei>0)
      for iNuc = 1:nNuclei
        K = A{iNuc}*u;
        nK = norm(K);
        k(:,iNuc) = K/nK;
        E1A_ = mI{iNuc}*nK;
        if directAccumulation
          E1A(1:nStates(iNuc),iNuc) = E1A_(:);
        else
          E1A(:,iNuc) = E1A_(idxn(:,iNuc)).';
        end
      end
    else
      E1A = 0;
    end

    % second-order
    if secondOrder
      if highSpin
        x =  D1sq*(4*S*(S+1)-3*(8*mS^2-8*mS+3))...
          - D2sq/4*(2*S*(S+1)-3*(2*mS^2-2*mS+1));
        E2D = -x./(2*geff(iOri)*bmagn*B0);
      else
        E2D = 0;
        E2DA = 0;
      end
      if (nNuclei>0)
        for n = 1:nNuclei
          k_ = k(:,n);
          Ak = A{n}.'*k_;
          kAu = Ak.'*u;
          kAAk = norm(Ak)^2;
          A1sq = kAAk - kAu^2;
          A2 = detA(n)*(u.'*invA{n}*k_);
          A3 = trAA(n) - norm(A{n}*u)^2 - kAAk + kAu^2;
          x = A1sq*mI{n}.^2 - A2*(1-2*mS)*mI{n} + A3/2*(II1(n)-mI{n}.^2);
          E2A_ = +x./(2*geff(iOri)*bmagn*B0);
          if directAccumulation
            E2A(1:nStates(n),n) = E2A_(:);
          else
            E2A(:,n) = E2A_(idxn(:,n)).';
          end
          if highSpin
            DA = Du.'*Ak - uDu*kAu;
            y = DA*(3-6*mS)*mI{n};
            E2DA_ = -y./(geff(iOri)*bmagn*B0);
            if directAccumulation
              E2DA(1:nStates(n),n) = E2DA_;
            else
              E2DA(:,n) = E2DA_(idxn(:,n)).';
            end
          else
            E2DA = 0;
          end
        end
      else
        E2DA = 0;
        E2A = 0;
      end
    end
    
    if directAccumulation
      % compute B shifts
      if secondOrder
        Bshifts = (-E1D-E2D-(E1A+E2A+E2DA))*1e6*planck/(geff(iOri)*bmagn);
      else
        Bshifts = (-E1D-sum(E1A,2))*1e6*planck/(geff(iOri)*bmagn);
      end
      % (intensities)
      if FourierDomain
      else
        % accumulate into spectrum
        if (nNuclei>0)
          spec = spec + g1(iOri)*Exp.AccumWeights(iOri)*...
            multinucstick(planck*1e6*B0*1e3,nStates,Bshifts*1e3,...
            Baxis(1),dB,Exp.nPoints);
        else
          idx = fix((B0*planck*1e9+Bshifts*1e3-Baxis(1))/dB+1);
          if (idx>1) && (idx<=Exp.nPoints)
            spec(idx) = spec(idx) + g1(iOri)*Exp.AccumWeights(iOri);
          end
        end
      end
    else
      if secondOrder
        Bfinal{imS}(iOri,:) = (E0-E1D-E2D-sum(E1A+E2A+E2DA,2))*preOri;
      else
        Bfinal{imS}(iOri,:) = (E0-E1D-sum(E1A,2))*preOri;
      end
    end
    
  end

end

if ~isnan(Exp.Temperature)
  Populations = exp(-planck*(2*S:-1:0)*Exp.mwFreq*1e9/boltzm/Exp.Temperature);
  Populations = Populations/sum(Populations);
  Polarization = diff(Populations);
else
  Polarization = ones(1,2*S);
end

if directAccumulation
  B = [];
  Int = [];
  Wid = [];
  Transitions = [];
else
  % Positions
  %-------------------------------------------------------------------
  B = [];
  for imS=1:2*S
    B = [B Bfinal{imS}];
  end
  B = B.'*1e3;
  
  % Intensities
  %-------------------------------------------------------------------
  nNucSublevels = prod(2*I+1);
  if highSpin
    mS = S:-1:-S+1;
    Int_ = (S*(S+1) - mS.*(mS-1));
    Int = [];
    for iTrans = 1:2*S
      Int = [Int; repmat(Polarization(iTrans)*g1,nNucSublevels,1)*Int_(iTrans)];
    end
  else
    Int = repmat(Polarization*g1,size(B,1),1);
  end
  Int = Int/nNucSublevels;
  
  % Widths
  %-------------------------------------------------------------------
  if any(Sys.HStrain)
    lw2 = sum(Sys.HStrain.^2*vecs.^2,1);
    lw = sqrt(lw2)*1e6*planck./geff/bmagn*1e3;
    Wid = repmat(lw,nNucTrans*2*S,1);
  elseif any(Sys.gStrain)
    if any(Sys.gpa)
      error('g strain and g tilt cannot be used simultaneously.');
    end
    gslw = Sys.gStrain./Sys.g*Exp.mwFreq*1e3;
    lw = sqrt(sum(gslw.^2*vecs.^2,1)); % MHz
    lw = planck*lw*1e6./geff/bmagn*1e3; % mT
    Wid = repmat(lw,nNucTrans*2*S,1);

  elseif any(Sys.DStrain)
    x = vecs(1,:);
    y = vecs(2,:);
    z = vecs(3,:);
    mS = -S:S;
    mSS = mS.^2-S*(S+1)/3;
    for k = 1:numel(mS)
      dBdD_(k,:) = (3*z.^2-1)/2*mSS(k)*planck./geff/bmagn*1e9;
      dBdE_(k,:) = 3*(x.^2-y.^2)/2*mSS(k)*planck./geff/bmagn*1e9;
    end
    for k = 1:numel(mS)-1
      lwD(k,:) = (dBdD_(k+1,:)-dBdD_(k,:))*Sys.DStrain(1);
      lwE(k,:) = (dBdE_(k+1,:)-dBdE_(k,:))*Sys.DStrain(2);
    end
    lw = sqrt(lwD.^2+lwE.^2);
    Wid = repmat(lw,nNucTrans,1);
  else
    Wid = [];
  end
  
  % Transitions
  %-------------------------------------------------------------------
  nI = prod(2*I+1);
  Transitions = [];
  Manifold = (1:nI).';
  for k = 1:2*S
    Transitions = [Transitions; [Manifold Manifold+nI]];
    Manifold = Manifold + nI;
  end
  
  spec = 0;
end

% Arrange output
%---------------------------------------------------------------
Output = {B,Int,Wid,Transitions,spec};
varargout = Output(1:max(nargout,1));

return

%==================================================================

function Combs = allcombinations(varargin)

if (nargin==0), Combs = []; return; end

Combs = varargin{1}(:);
nCombs = numel(Combs);

for iArg = 2:nargin
  New = varargin{iArg}(:);
  nNew = numel(New);
  [idxNew,idxCombs] = find(ones(nNew,nCombs));
  Combs = [Combs(idxCombs(:),:), New(idxNew(:))];
  nCombs = nCombs*nNew;
end

return

