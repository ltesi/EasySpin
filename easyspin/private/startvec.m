% startvec calculates the starting vector in the given basis (basis), including
% the orientational potential (Potential) and the spin operator in SopH (either
% S+ or Sx).

function [StartingVector,normPeq,nIntegrals] = startvec(basis,Potential,SopH,useSelectionRules,PeqTolerances)

% Settings
if nargin<5, useSelectionRules = true; end
if nargin<6, PeqTolerances = []; end
if isempty(PeqTolerances)
  PeqTolerances = [1e-8 1e-6 1e-6];
end
PeqIntThreshold = PeqTolerances(1);
PeqIntAbsTol = PeqTolerances(2);
PeqIntRelTol = PeqTolerances(3);

lambda = Potential.lambda;
Lp = Potential.L;
Mp = Potential.M;
Kp = Potential.K;

% Assure that potential contains only terms with nonnegative K, and nonnegative M
% for K=0. The other terms needed to render the potential real-valued are
% implicitly supplemented in the subfunction U(a,b,c).
if any(Kp<0)
  error('Only potential terms with nonnegative values of K are allowed. Terms with negative K required to render the potential real-valued are supplemented automatically.');
end
if any(Mp(Kp==0)<0)
  error('For potential terms with K=0, M must be nonnegative. Terms with negative M required to render the potential real-valued are supplemented automatically.');
end
zeroMK = Mp==0 & Kp==0;
if any(~isreal(lambda(zeroMK)))
  error('Potential coefficients for M=K=0 must be real-valued.');
end

% Remove zero entries and constant offset
rmv = lambda==0;
rmv = rmv | (Lp==0 & Mp==0 & Kp==0);
if any(rmv)
  lambda(rmv) = [];
  Lp(rmv) = [];
  Mp(rmv) = [];
  Kp(rmv) = [];
end

% Counter for the number of numerical 1D, 2D, and 3D integrals evaluated.
nIntegrals = [0 0 0];

jKbasis = isfield(basis,'jK') && ~isempty(basis.jK) && any(basis.jK);

L = basis.L;
M = basis.M;
K = basis.K;
if jKbasis
  jK = basis.jK;
end
nOriBasis = numel(L);

% Handle special case of no potential
if ~any(lambda)
  idx0 = find(L==0 & M==0 & K==0);
  if numel(idx0)~=1
    error('Exactly one orientational basis function with L=M=K=0 is allowed.');
  end
  sqrtPeq = zeros(nOriBasis,1);
  sqrtPeq(idx0) = 1;
  normPeq = 1;
  StartingVector = kron(sqrtPeq,SopH(:)/norm(SopH(:)));
  StartingVector = sparse(StartingVector);
  return
end

% Detect old-style potential (contains only terms with even L, M=0, and even K)
zeroMp = all(Mp==0);
zeroKp = all(Kp==0);
evenLp = all(mod(Lp,2)==0);
evenMp = all(mod(Mp,2)==0);
evenKp = all(mod(Kp,2)==0);

% Abbreviations for 1D, 2D, and 3D integrals
int_b = @(f) integral(f,0,pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
int_ab = @(f) integral2(f,0,2*pi,0,pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
int_bc = @(f) integral2(f,0,pi,0,2*pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);
int_abc = @(f) integral3(f,0,2*pi,0,pi,0,2*pi,'AbsTol',PeqIntAbsTol,'RelTol',PeqIntRelTol);

% Calculate partition sum Z such that Peq = exp(-U)/Z
if zeroMp && zeroKp
  Z = (2*pi)^2 * int_b(@(b) exp(-U(0,b,0)).*sin(b));
  nIntegrals = nIntegrals + [1 0 0];
elseif zeroMp && ~zeroKp
  Z = (2*pi) * int_bc(@(b,c) exp(-U(0,b,c)).*sin(b));
  nIntegrals = nIntegrals + [0 1 0];
elseif ~zeroMp && zeroKp
  Z = (2*pi) * int_ab(@(a,b) exp(-U(a,b,0)).*sin(b));
  nIntegrals = nIntegrals + [0 1 0];
else
  Z = int_abc(@(a,b,c) exp(-U(a,b,c)).*sin(b));
  nIntegrals = nIntegrals + [0 0 1];
end
sqrtZ = sqrt(Z);

% Calculate elements of sqrt(Peq) vector in orientational basis
sqrtPeq = zeros(nOriBasis,1);
for b = 1:numel(sqrtPeq)
  
  L_  = L(b);
  M_  = M(b);
  K_  = K(b);
  if jKbasis
    jK_ = jK(b);
  end
  
  if useSelectionRules
    if zeroMp
      if M_~=0, continue; end
      if evenLp && mod(L_,2)~=0, continue; end
      if evenKp && mod(K_,2)~=0, continue; end
      if jKbasis && jK_~=1, continue; end
      if zeroKp
        if K_~=0, continue; end
        f = @(b) wignerd([L_ 0 0],b) .* exp(-U(0,b,0)/2) .* sin(b);
        Int = (2*pi)^2 * int_b(f);
        nIntegrals = nIntegrals + [1 0 0];
      else
        f = @(b,c) cos(K_*c) .* wignerd([L_ 0 K_],b) .* exp(-U(0,b,c)/2) .* sin(b);
        Int = (2*pi) * int_bc(f);
        nIntegrals = nIntegrals + [0 1 0];
      end
    elseif zeroKp
      if K_~=0, continue; end
      if evenLp && mod(L_,2)~=0, continue; end
      if evenMp && mod(M_,2)~=0, continue; end
      f = @(a,b) cos(M_*a) .* wignerd([L_ M_ 0],b) .* exp(-U(a,b,0)/2) .* sin(b);
      Int = (2*pi) * int_ab(f);
      nIntegrals = nIntegrals + [0 1 0];
    else
      f = @(a,b,c) conj(wignerd([L_ M_ K_],a,b,c)) .* exp(-U(a,b,c)/2) .* sin(b);
      Int = int_abc(f);
      nIntegrals = nIntegrals + [0 0 1];
    end
  else
    f = @(a,b,c) conj(wignerd([L_ M_ K_],a,b,c)) .* exp(-U(a,b,c)/2) .* sin(b);
    Int = int_abc(f);
    nIntegrals = nIntegrals + [0 0 1];
  end
  Int = real(Int); % to remove small numeric errors in imaginary parts
  
  Int = sqrt((2*L_+1)/(8*pi^2))/sqrtZ * Int;
  if jKbasis
    Int = sqrt(2/(1 + (K_==0))) * Int;
  end
  
  % Store element if above threshold
  if abs(Int) >= PeqIntThreshold
    sqrtPeq(b) = Int;
  end
  
end

% Norm-squared of Peq is 1 in infinite-basis limit, < 1 for a truncated basis.
normPeq = norm(sqrtPeq)^2;

% Form starting vector in direct product basis
StartingVector = kron(sqrtPeq,SopH(:)/norm(SopH(:)));
StartingVector = sparse(StartingVector);

  % General orientational potential function (real-valued)
  % (assumes nonnegative K, and nonnegative M for K=0, and real lambda for
  % M=K=0; other terms are implicitly supplemented)
  function u = U(a,b,c)
    u = 0;
    for p = 1:numel(lambda)
      if lambda(p)==0, continue; end
      if Kp(p)==0 && Mp(p)==0
        u = u - wignerd([Lp(p) Mp(p) Kp(p)],b) * real(lambda(p));
      else
        u = u - 2*real(wignerd([Lp(p) Mp(p) Kp(p)],a,b,c) * lambda(p));
      end
    end
  end

end
