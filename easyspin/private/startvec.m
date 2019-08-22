% startvec calculates the starting vector in the given basis (basis), including
% the orientational potential (Potential) and the spin operator in SopH (either S+
% or Sx).

function [StartingVector,nIntegrals] = startvec(basis,Potential,SopH,useSelectionRules,PeqTolerances)

nIntegrals = [0 0 0];

jKbasis = isfield(basis,'jK') && ~isempty(basis.jK) && any(basis.jK);

% Settings
if nargin<5, useSelectionRules = true; end
if nargin<6, PeqTolerances = []; end
if isempty(PeqTolerances)
  PeqTolerances = [1e-10 1e-6 1e-6];
end
PeqIntThreshold = PeqTolerances(1);
PeqIntAbsTol = PeqTolerances(2);
PeqIntRelTol = PeqTolerances(3);

L = basis.L;
M = basis.M;
K = basis.K;
if jKbasis
  jK = basis.jK;
end
nOriBasis = numel(L);

lambda = Potential.lambda;
Lp = Potential.L;
Mp = Potential.M;
Kp = Potential.K;

% Treat special case of no potential
if ~any(lambda)
  idx0 = find(L==0 & M==0 & K==0);
  if numel(idx0)~=1
    error('Exactly one orientational basis function with L=M=K=0 is allowed.');
  end
  nSpinBasis = numel(SopH);
  idx = (idx0-1)*nSpinBasis + (1:nSpinBasis);
  nBasis = nOriBasis*nSpinBasis;
  StartingVector = sparse(idx,1,SopH(:),nBasis,nBasis);
  StartingVector = StartingVector/sqrt(sum(StartingVector.^2)); % norm doesn't work for sparse
  return
end

% Remove zero entries
idx = lambda~=0;
if ~isempty(idx)
  lambda = lambda(idx);
  Lp = Lp(idx);
  Mp = Mp(idx);
  Kp = Kp(idx);
end

% Detect old-style potential (contains only terms with even L, M=0, and even K)
zeroMp = all(Mp==0);
zeroKp = all(Kp==0);
evenLp = all(mod(Lp,2)==0);
evenMp = all(mod(Mp,2)==0);
evenKp = all(mod(Kp,2)==0);

% Set up starting vector in orientational basis
oriVector = zeros(nOriBasis,1);
for b = 1:numel(oriVector)
  
  L_  = L(b);
  M_  = M(b);
  K_  = K(b);
  if jKbasis
    jK_ = jK(b);
  end
  
  if useSelectionRules && zeroMp
    if M_~=0, continue; end
    if evenLp && mod(L_,2)~=0, continue; end
    if evenKp && mod(K_,2)~=0, continue; end
    if jKbasis && jK_~=1, continue; end
    if zeroKp
      if K_~=0, continue; end
      fun = @(b) wignerd([L_ 0 0],b) .* exp(-U(0,b,0)/2) .* sin(b);
      Int = (2*pi)^2 * integral(fun,0,pi);
      nIntegrals = nIntegrals + [1 0 0];
    else
      fun = @(b,c) cos(K_*c) .* wignerd([L_ 0 K_],b) .* exp(-U(0,b,c)/2) .* sin(b);
      Int = (2*pi) * integral2(fun,0,pi,0,2*pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
      nIntegrals = nIntegrals + [0 1 0];
    end
  elseif useSelectionRules && zeroKp
    if K_~=0, continue; end
    if evenLp && mod(L_,2)~=0, continue; end
    if evenMp && mod(M_,2)~=0, continue; end
    fun = @(a,b) cos(M_*a) .* wignerd([L_ M_ 0],b) .* exp(-U(a,b,0)/2) .* sin(b);
    Int = (2*pi) * integral2(fun,0,2*pi,0,pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
    nIntegrals = nIntegrals + [0 1 0];
  else
    fun = @(a,b,c) conj(wignerd([L_ M_ K_],a,b,c)) .* exp(-U(a,b,c)/2) .* sin(b);
    Int = integral3(fun,0,2*pi,0,pi,0,2*pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
    nIntegrals = nIntegrals + [0 0 1];
  end
  
  if abs(Int) < PeqIntThreshold, continue; end
  
  oriVector(b) = sqrt((2*L_+1)/(8*pi^2)) * Int;
  if jKbasis
    oriVector(b) = sqrt(2/(1 + (K_==0))) * oriVector(b);
  end
  
end

% form starting vector in direct product basis
StartingVector = real(kron(oriVector,SopH(:)));
StartingVector = StartingVector/norm(StartingVector);
StartingVector = sparse(StartingVector);

  % General orientational potential function (real-valued)
  function u = U(a,b,c)
    u = 0;
    for p = 1:numel(lambda)
      if lambda(p)==0, continue; end
      if Kp(p)==0 && Mp(p)==0
        u = u - wignerd([Lp(p) +Mp(p) +Kp(p)],b) * real(lambda(p));
      else
        u = u - 2*real(wignerd([Lp(p) +Mp(p) +Kp(p)],a,b,c) * lambda(p));
      end
    end
  end

end
