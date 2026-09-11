#!/usr/bin/env wolframscript
(* ==============================================================================
   repro_543.wl -- known-answer ladder for the PSALTer Tier-1 investigation (GH #543)
   ==============================================================================
   Usage (lane idle; run from a scratch directory -- PSALTer writes PDFs into cwd):

     d=third_party/psalter_runs/repro543-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$d"
     ( cd "$d" && QT_QPA_PLATFORM=offscreen wolframscript -file "$OLDPWD/scripts/psalter/repro_543.wl" A 2>&1 ) \
        | python3 scripts/psalter/stamp_lines.py > "$d/run.log"; grep -a REPRO543 "$d/run.log"

   Rungs, with the expected result stated here so a verdict needs no oracle .mx:

     A  free scalar  L = 1/2 Theta1 (d phi)^2 - 1/2 Theta2 phi^2
        one non-trivial sector (the odd-parity slot holds the literal 1);
        PseudoDeterminant a NON-ZERO quadratic in Def with pole
        Def^2 = +-Theta2/Theta1 (the sign is PSALTer's momentum convention and is
        recorded, not asserted); no gauge symmetry, so $LocalSourceConstraints = {}
        is the correct answer here.  ~30 s.  (#543 comment 1's reproduction.)
     B  Proca  L = -1/2 T1 (d_a A_b)^2 + 1/2 T2 (d.A)^2 - 1/2 T3 A^2
        published 1x1 blocks (docs/cosmology/spectrum_design.md:658-666, and the
        committed upstream fixture tests_cosmo/fixtures/psalter/ParticleSpectrographVectorTheory.wxf):
          0+ : 1/2 [ Def^2 (T2 - T1) - T3 ]      1- : 1/2 [ -Def^2 T1 - T3 ]
        BOTH association keys must match these up to a coupling-free constant.
        Decides the #542 "missing mass term" note in vector_smoke.wls.
     C  Fierz-Pauli (PSALTer README worked example, Coupling1 = alpha, Coupling2 = beta)
        from the author's own ParticleSpectrographMassiveGravity.png:
          0+ block {{-2 beta + alpha k^2, -Sqrt[3] beta}, {-Sqrt[3] beta, 0}}  -> det -3 beta^2
          1- block  beta                       2+ block  beta - alpha k^2 / 2  (pole 2 beta/alpha)
        PseudoDeterminant entries must match {-3 beta^2, beta, beta - alpha Def^2/2}
        up to coupling-free constants.
     G  Maxwell = rung B at T1 = T2, T3 = 0.  A GAUGE theory: $LocalSourceConstraints
        must be non-empty (one generator), and at least one PseudoDeterminant entry
        must be non-zero.  This is the cheap rung that exercises the mechanism
        behind #543 (null-space identification); ~60 s.  Run it several times:
        PSALTer is unseeded (README known bug 1), so the row count per run is data.
     X  cubic control  L = rung A + Theta3 phi^3.  ParticleSpectrum must THROW
        ParticleSpectrum::NonQuadraticFields (ValidateLagrangian.m:38).  A guard nobody
        has watched fire is not restored (#556).
     D  CTEG -- never this file: bash scripts/psalter/run_tier1_gate.sh

   Every run prints REPRO543 lines: engine, PSALTer revision, kernel count, the
   messages seen, both association keys in InputForm, the dimensions of
   $LocalSourceConstraints, subkernel liveness, and a PASS/FAIL verdict with a
   reason.  The association is exported as repro543_<rung>.wxf into cwd.
   Exit 0 = PASS, 1 = FAIL, 2 = could not evaluate.
   ============================================================================== *)

rung = If[Length[$ScriptCommandLine] >= 2, $ScriptCommandLine[[2]], "A"];
say[a__] := Print["REPRO543 ", a];
t0 = AbsoluteTime[];
say["rung=", rung, " begin=", DateString["ISODateTime"], " cwd=", Directory[]];
say["env $Version=", System`$Version, " $VersionNumber=", $VersionNumber, " $ReleaseNumber=", $ReleaseNumber];
say["env $UserBaseDirectory=", $UserBaseDirectory, " $ProcessorCount=", $ProcessorCount,
    " $MaxLicenseSubprocesses=", $MaxLicenseSubprocesses];
say["env resources=", InputForm[Quiet@{ResourceObject["LinearlyIndependent"]["UUID"], ResourceObject["PolynomialDegree"]["UUID"]}],
    " behave=", InputForm[Quiet@{ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}], ResourceFunction["PolynomialDegree"][pdVarX^2 pdVarY, {pdVarX, pdVarY}]}]];

Needs["xAct`PSALTer`"];
say["env psalter=", xAct`PSALTer`Private`$Version, " install=", xAct`PSALTer`Private`$InstallDirectory];
Def = xAct`PSALTer`Def;

(* ---- matching helpers: order-independent, up to a coupling-free constant ---- *)
constantRatioQ[p_, q_, syms_] := With[{r = Quiet@Simplify[p/q]},
  r =!= 0 && FreeQ[r, Def] && FreeQ[r, Alternatives @@ syms] && NumericQ[r]];
exactQ[p_, q_] := TrueQ@PossibleZeroQ@Simplify[p - q];
matchSet[vals_, expected_, syms_] := Length[vals] === Length[expected] &&
  AnyTrue[Permutations@Range@Length@expected,
    Function[perm, And @@ MapThread[(exactQ[#1, #2] || constantRatioQ[#1, #2, syms]) &, {vals[[perm]], expected}]]];
(* PSALTer lists every spin sector as an even/odd parity pair and puts the literal 1 in a
   parity slot that carries no field (so the scalar's spin-0 sector reads {block, 1}). Those
   trivial slots are dropped before matching; a literal 0 is NOT dropped -- it is the failure
   signature of #543. *)
flat[assoc_, key_] := DeleteCases[Flatten[{assoc[key]}], 1];

(* ---- rung definitions: {theory name, Lagrangian, checker} ---- *)
DefConstantSymbol[Theta1]; DefConstantSymbol[Theta2]; DefConstantSymbol[Theta3];
scalarL := (1/2) Theta1 CD[-a]@ScalarField[] CD[a]@ScalarField[] - (1/2) Theta2 ScalarField[]^2;
vectorL[t1_, t2_, t3_] := -(1/2) t1 CD[-a]@VectorField[-b] CD[a]@VectorField[b] +
  (1/2) t2 CD[-a]@VectorField[a] CD[-b]@VectorField[b] - (1/2) t3 VectorField[-a] VectorField[a];

checkA[assoc_] := Module[{pd = flat[assoc, xAct`PSALTer`PseudoDeterminant], p, c0, c2, root},
  If[Length[pd] =!= 1, Return[{"FAIL", "expected 1 non-trivial sector, got " <> ToString@Length@pd <> ": " <> ToString[pd, InputForm]}]];
  p = First@pd;
  If[TrueQ@PossibleZeroQ@p, Return[{"FAIL", "pseudo-determinant is zero"}]];
  If[! PolynomialQ[p, Def] || Exponent[p, Def] =!= 2, Return[{"FAIL", "not a quadratic in Def: " <> ToString[p, InputForm]}]];
  c2 = Coefficient[p, Def, 2]; c0 = Coefficient[p, Def, 0]; root = Simplify[-c0/c2];
  If[! TrueQ@Simplify[root^2 == (Theta2/Theta1)^2], Return[{"FAIL", "pole Def^2=" <> ToString[root, InputForm] <> " is not +-Theta2/Theta1"}]];
  {"PASS", "pole Def^2=" <> ToString[root, InputForm] <> " (sign recorded, not asserted)"}];

checkB[assoc_] := With[{exp = {(Def^2 (Theta2 - Theta1) - Theta3)/2, (-Def^2 Theta1 - Theta3)/2}, syms = {Theta1, Theta2, Theta3}},
  Which[
    ! matchSet[flat[assoc, xAct`PSALTer`PseudoDeterminant], exp, syms],
      {"FAIL", "PseudoDeterminant != published 0+/1- blocks: " <> ToString[flat[assoc, xAct`PSALTer`PseudoDeterminant], InputForm]},
    ! matchSet[flat[assoc, xAct`PSALTer`WaveOperator], exp, syms],
      {"FAIL", "WaveOperator != published blocks: " <> ToString[flat[assoc, xAct`PSALTer`WaveOperator], InputForm]},
    True, {"PASS", "both keys match the published 0+ and 1- blocks"}]];

checkC[assoc_] := With[{exp = {-3 Coupling2^2, Coupling2, Coupling2 - Coupling1 Def^2/2}, syms = {Coupling1, Coupling2}},
  If[matchSet[flat[assoc, xAct`PSALTer`PseudoDeterminant], exp, syms],
    {"PASS", "0+ -3 beta^2, 1- beta, 2+ beta - alpha Def^2/2 (pole 2 beta/alpha), as published"},
    {"FAIL", "PseudoDeterminant != published Fierz-Pauli sectors: " <> ToString[flat[assoc, xAct`PSALTer`PseudoDeterminant], InputForm]}]];

checkG[assoc_] := Module[{sc = xAct`PSALTer`Private`$LocalSourceConstraints, pd = flat[assoc, xAct`PSALTer`PseudoDeterminant]},
  Which[
    Length[Flatten[{sc}]] == 0 || Head[sc] === String, {"FAIL", "no source constraint identified (gauge symmetry lost)"},
    ! AnyTrue[pd, ! TrueQ@PossibleZeroQ@# &], {"FAIL", "all pseudo-determinants zero: " <> ToString[pd, InputForm]},
    True, {"PASS", "constraint rows=" <> ToString[Dimensions[sc]] <> ", non-zero pseudo-determinant present"}]];

{name, L, check} = Switch[rung,
  "A", DefField[ScalarField[], PrintAs -> "\[Phi]"]; {"Repro543A", scalarL, checkA},
  "X", DefField[ScalarField[], PrintAs -> "\[Phi]"]; {"Repro543X", scalarL + Theta3 ScalarField[]^3, None},
  "B", DefField[VectorField[-a], PrintAs -> "A", PrintSourceAs -> "j"]; {"Repro543B", vectorL[Theta1, Theta2, Theta3], checkB},
  "G", DefField[VectorField[-a], PrintAs -> "A", PrintSourceAs -> "j"]; {"Repro543G", vectorL[Theta1, Theta1, 0], checkG},
  "C", DefConstantSymbol[Coupling1, PrintAs -> "\[Alpha]"]; DefConstantSymbol[Coupling2, PrintAs -> "\[Beta]"];
       DefField[MetricPerturbation[-a, -b], Symmetric[{-a, -b}], PrintAs -> "\[ScriptH]", PrintSourceAs -> "\[ScriptCapitalT]"];
       {"Repro543C",
        Coupling1*((1/2)*CD[-b]@MetricPerturbation[a, -a]*CD[b]@MetricPerturbation[c, -c]
          - CD[a]@MetricPerturbation[-a, -b]*CD[b]@MetricPerturbation[c, -c]
          - (1/2)*CD[-c]@MetricPerturbation[a, b]*CD[c]@MetricPerturbation[-a, -b]
          + CD[-b]@MetricPerturbation[a, b]*CD[c]@MetricPerturbation[-a, -c])
        + Coupling2*(MetricPerturbation[-a, -b]*MetricPerturbation[a, b] - MetricPerturbation[a, -a]*MetricPerturbation[b, -b]),
        checkC},
  _, say["rung=", rung, " verdict=FAIL reason=unknown rung (A|B|C|G|X)"]; Quit[2]];

(* ---- run; $MessageList is read inside the same top-level expression ---- *)
{wall, msgs} = AbsoluteTiming[(Catch[ParticleSpectrum[L, TheoryName -> name, MaxLaurentDepth -> 1, ShowPropagator -> False]]; Tally[$MessageList])];
say["wall_s=", Round[wall, 0.1], " $KernelCount=", $KernelCount];
say["messages=", ToString[msgs, InputForm]];
If[$KernelCount > 0,
  say["subkernels=", InputForm[ParallelEvaluate[{$KernelID, System`$Version, $UserBaseDirectory,
    Quiet@ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}], Quiet@ResourceFunction["PolynomialDegree"][pdVarX^2 pdVarY, {pdVarX, pdVarY}]}]]]];

If[rung === "X",
  fired = MemberQ[First /@ msgs, HoldForm[ParticleSpectrum::NonQuadraticFields]];
  say["rung=X verdict=", If[fired, "PASS", "FAIL"], " reason=", If[fired, "NonQuadraticFields threw on a cubic Lagrangian", "cubic Lagrangian accepted: NonQuadraticFields did not fire"], " total_s=", Round[AbsoluteTime[] - t0, 0.1]];
  Quit[If[fired, 0, 1]]];

assoc = ToExpression["Global`" <> name];
If[! AssociationQ[assoc], say["rung=", rung, " verdict=FAIL reason=no association produced"]; Quit[2]];
say["keys=", (Context[#] <> SymbolName[#]) & /@ Keys[assoc]];
say["WaveOperator=", ToString[assoc[xAct`PSALTer`WaveOperator], InputForm]];
say["PseudoDeterminant=", ToString[assoc[xAct`PSALTer`PseudoDeterminant], InputForm]];
say["SourceConstraints dims=", Dimensions[xAct`PSALTer`Private`$LocalSourceConstraints],
    " leaves=", LeafCount[xAct`PSALTer`Private`$LocalSourceConstraints]];
Export[FileNameJoin[{Directory[], "repro543_" <> rung <> ".wxf"}], assoc, "WXF"];
{verdict, reason} = check[assoc];
say["rung=", rung, " verdict=", verdict, " reason=", reason, " total_s=", Round[AbsoluteTime[] - t0, 0.1]];
Quit[If[verdict === "PASS", 0, 1]]
