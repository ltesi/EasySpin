function ok = test()

%======================================================
% Make sure syntax of addnoise works as documented
%======================================================

x = linspace(-1,1,10001);
y = gaussian(x,0,0.3);

yn = addnoise(y,10,'f');
yn = addnoise(y,10,'u');
yn = addnoise(y,10,'n');

ok = true;
