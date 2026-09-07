#!/usr/bin/env wolframscript
(* ==============================================================================
   Probe #522 -- does PSALTer reject a term with no declared coupling?
   ==============================================================================
   Usage:
     QT_QPA_PLATFORM=offscreen wolframscript -file probe_522_couplings.wls

   Our design rule is "reject a bare numeric coefficient, never auto-assign one",
   because PSALTer's theory space is S = Int Sum_i theta_i O_i and an unlabelled
   term is silently absorbed into a theory the user never declared. The question
   is whether PSALTer already enforces that or whether it is entirely our job.

   Reading the pinned sources says the latter: ValidateLagrangian defines six
   messages and throws only four, and numbers are not Variables, so nothing
   rejects a bare coefficient. So THE EXPECTED RESULT OF LEG A IS SILENCE -- this
   probe exists to record that silence as a measured fact, not to catch an error.

   Leg B feeds a genuinely undeclared symbol, which does draw UnknownCoupling, and
   captures its exact wording so our own validator hint can echo it.
   ============================================================================== *)

Print["PROBE522 begin"];
Needs["xAct`PSALTer`"];
Print["PROBE522 psalter_version=", xAct`PSALTer`Private`$Version[[1]]];

(* All six message templates, verbatim, and how many places each is referenced in
   the installed tree. A count of 1 means "defined but never thrown". *)
Print["PROBE522 message_templates=",
  ToString[Messages[xAct`PSALTer`Private`ValidateLagrangian], InputForm]];
Do[
  Print["PROBE522 references_", m, "=",
    Length@Flatten@Map[
      FindList[#, "ValidateLagrangian::" <> m] &,
      FileNames["*.m", xAct`PSALTer`Private`$InstallDirectory, Infinity]]],
  {m, {"Zero", "UnknownCoupling", "UnknownField", "NonQuadraticFields",
       "NonLinearCouplings", "ParityOdd"}}];

DefConstantSymbol[Theta1];
DefField[VectorField[-a], PrintAs -> "A"];

(* ---- Leg A: a bare numeric coefficient. Expected outcome: silence. -------- *)
Print["=== PROBE522A begin (bare numeric coefficient) ==="];
bareMessages = {};
bareCompleted = False;
Block[{$MessageList = {}},
  Check[
    ParticleSpectrum[
      -(1/4)*CD[-a]@VectorField[-b]*CD[a]@VectorField[b],
      TheoryName -> "Probe522Bare", MaxLaurentDepth -> 1, ShowPropagator -> False];
    bareCompleted = True,
    bareCompleted = False];
  bareMessages = $MessageList];
Print["PROBE522A messages=", ToString[bareMessages, InputForm]];
Print["PROBE522A silent=", bareMessages === {}];
Print["PROBE522A completed=", bareCompleted];
Print["PROBE522A wrote_mx=",
  Length@FileNames["ParticleSpectrographProbe522Bare.mx", Directory[]]];
Print["=== PROBE522A end ==="];

(* ---- Leg B: a genuinely undeclared symbol. Expected: UnknownCoupling. ----- *)
Print["=== PROBE522B begin (undeclared symbol) ==="];
unknownMessages = {};
Block[{$MessageList = {}},
  Check[
    ParticleSpectrum[
      -(1/4)*Global`UndeclaredCoupling*
        CD[-a]@VectorField[-b]*CD[a]@VectorField[b],
      TheoryName -> "Probe522Unknown", MaxLaurentDepth -> 1, ShowPropagator -> False],
    Null];
  unknownMessages = $MessageList];
Print["PROBE522B messages=", ToString[unknownMessages, InputForm]];
Print["PROBE522B silent=", unknownMessages === {}];
Print["=== PROBE522B end ==="];

Print["PROBE522 done"];
Quit[0]
