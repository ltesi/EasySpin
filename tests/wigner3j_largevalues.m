function [err,data] = test(opt,olddata)

% Test for some randomly selected parameters
%======================================================
a(1) = wigner3j(100,100,100,0,0,0);
b(1) = 0.00603239131346568401;
a(2) = wigner3j(100,100,100,-1,0,1);
b(2) = -0.00301619565673284200;
a(3) = wigner3j(100,100,100,10,5,-15);
b(3) = -0.00315922567170862;
a(4) = wigner3j(50,50,50,10,5,-15);
b(4) = 0.00715732335346969;
a(5) = wigner3j(300,300,300,1,0,-1);
b(5) = -0.00100875292778542;
a(6) = wigner3j(30,30,30,0,15,-15);
b(6) = -0.015285715489783877629;
a(7) = wigner3j(15,30,40,2,2,-4);
b(7) = -46874/9*sqrt(110/8194888366823);
a(8) = wigner3j(160,100,60,-10,60,-50);
b(8) = 3.81124616116626297978e-21;
a(9) = wigner3j(200,200,200,-10,60,-50);
b(9) = 0.00074939273139895143637;

ok = abs(a-b)<1e-9;
err = any(~ok);

data = [];