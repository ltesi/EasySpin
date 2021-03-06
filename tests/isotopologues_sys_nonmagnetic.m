function ok = test()

% Test whether isotopologue() handles multi-electron system

Sys.Nucs = '(12,13)C';
Sys.A = 5;
Sys.Abund = [0.9 0.1];

Iso = isotopologues(Sys);

ok = isempty(Iso(1).Nucs);
