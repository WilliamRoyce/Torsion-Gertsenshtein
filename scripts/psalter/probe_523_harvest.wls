#!/usr/bin/env wolframscript
(* ==============================================================================
   Probe #523 -- what surface must the Stage-1 exporter read?
   ==============================================================================
   Usage:
     QT_QPA_PLATFORM=offscreen wolframscript -file probe_523_harvest.wls

   PSALTer writes no WXF. ParticleSpectrum populates exactly two association keys
   and leaves everything else in private globals, so our exporter has to read
   private symbols -- which makes the installed revision a correctness input.

   The handoff flags a contradiction between two sections of the plan: one lists
   EIGHT $Local* globals, the other SIX. It is not a contradiction. Eight is what
   exists (the arguments ConstructSpectrograph receives); six is the subset the
   exporter chose, dropping $LocalWaveOperator as redundant with the association
   key and $LocalPropagator as display-only. So this probe tests the
   JUSTIFICATION rather than recounting:

     - is $LocalWaveOperator really redundant with the association's WaveOperator?
     - is $LocalPropagator even populated under ShowPropagator -> False, which is
       what the published CTEG script passes?

   If the redundancy does not hold, the six-item list is wrong and must gain the
   key -- that is the loud finding.

   This cannot ride along with the CTEG gate run: that script ends in Quit[].
   ============================================================================== *)

Print["PROBE523 begin"];
Needs["xAct`PSALTer`"];
Print["PROBE523 psalter_version=", xAct`PSALTer`Private`$Version[[1]]];

DefConstantSymbol[Theta1];
DefConstantSymbol[Theta2];
DefConstantSymbol[Theta3];
DefField[VectorField[-a], PrintAs -> "A"];

L = -(1/2)*Theta1*CD[-a]@VectorField[-b]*CD[a]@VectorField[b]
    + (1/2)*Theta2*CD[-a]@VectorField[a]*CD[-b]@VectorField[b]
    - (1/2)*Theta3*VectorField[-a]*VectorField[a];

report[tag_String, showProp_] := Module[{assoc, names},
  Print["--- run with ShowPropagator -> ", showProp, " ---"];
  Quiet@ParticleSpectrum[L, TheoryName -> tag, MaxLaurentDepth -> 1,
                         ShowPropagator -> showProp];

  assoc = ToExpression["Global`" <> tag];
  Print["PROBE523 ", tag, " assoc_key_count=", Length[Keys[assoc]]];
  Print["PROBE523 ", tag, " assoc_keys=",
        ((Context[#] <> SymbolName[#]) & /@ Keys[assoc])];

  names = Names["xAct`PSALTer`Private`$Local*"];
  Print["PROBE523 ", tag, " local_count=", Length[names]];
  Do[
    Print["PROBE523 ", tag, " ", StringReplace[n, "xAct`PSALTer`Private`" -> ""],
          " valueQ=",  ToExpression[n, InputForm, ValueQ],
          " head=",    ToExpression[n, InputForm, Composition[ToString, Head]],
          " leaves=",  ToExpression[n, InputForm, LeafCount],
          " bytes=",   ToExpression[n, InputForm, ByteCount]],
    {n, names}];

  (* The two questions that decide whether the six-item list is safe. *)
  Print["PROBE523 ", tag, " waveoperator_redundant_with_key=",
    TrueQ[assoc[xAct`PSALTer`WaveOperator] ===
          xAct`PSALTer`Private`$LocalWaveOperator]];
  Print["PROBE523 ", tag, " localpropagator_populated=",
    TrueQ[ValueQ[xAct`PSALTer`Private`$LocalPropagator]]];
  Print["PROBE523 ", tag, " localpropagator_leaves=",
    If[ValueQ[xAct`PSALTer`Private`$LocalPropagator],
       LeafCount[xAct`PSALTer`Private`$LocalPropagator], "unset"]];
  ];

report["Probe523PropOn", True];
report["Probe523PropOff", False];

Print["PROBE523 done"];
Quit[0]
