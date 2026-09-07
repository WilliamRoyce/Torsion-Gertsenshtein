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

(* The six message templates, verbatim. They live on ParticleSpectrum, not on
   ValidateLagrangian -- the validator is a private helper that throws them. *)
Print["PROBE522 message_templates=",
  ToString[Messages[ParticleSpectrum], InputForm]];

(* How many places each name appears in the installed tree. One occurrence means
   "defined but never thrown"; more than one means a throw site exists. *)
Do[
  Print["PROBE522 occurrences_", m, "=",
    Length@Flatten@Map[
      FindList[#, "ParticleSpectrum::" <> m] &,
      FileNames["*.m", xAct`PSALTer`Private`$InstallDirectory, Infinity]]],
  {m, {"Zero", "UnknownCoupling", "UnknownField", "NonQuadraticFields",
       "NonLinearCouplings", "ParityOdd"}}];

DefConstantSymbol[Theta1];
DefField[VectorField[-a], PrintAs -> "A"];

(* ---- Leg A: bare numeric coefficient, against a declared-coupling control ---
   The expected outcome is that PSALTer says NOTHING about the missing coupling.
   That cannot be read off $MessageList directly here, because this install emits
   a large ambient cascade on any theory whatsoever (#543). So run the same
   operator twice -- once with a declared coupling, once with a bare number -- and
   compare the message SETS. Any message the bare run raises that the control does
   not is a complaint about the coefficient. ------------------------------------ *)
Print["=== PROBE522A begin (bare numeric coefficient vs declared-coupling control) ==="];

kinetic = CD[-a]@VectorField[-b]*CD[a]@VectorField[b];

runLeg[tag_String, lagrangian_] := Module[{msgs = {}, completed = False},
  Block[{$MessageList = {}},
    Check[
      ParticleSpectrum[lagrangian, TheoryName -> tag,
                       MaxLaurentDepth -> 1, ShowPropagator -> False];
      completed = True,
      completed = False];
    msgs = $MessageList];
  <|"messages" -> DeleteDuplicates[ToString /@ msgs], "completed" -> completed|>];

control = runLeg["Probe522Control", -(1/4)*Theta1*kinetic];
bare    = runLeg["Probe522Bare",    -(1/4)*kinetic];

Print["PROBE522A control_message_count=", Length[control["messages"]]];
Print["PROBE522A bare_message_count=", Length[bare["messages"]]];
Print["PROBE522A messages_only_in_bare=",
  ToString[Complement[bare["messages"], control["messages"]], InputForm]];
Print["PROBE522A no_extra_complaint_about_bare_coefficient=",
  Complement[bare["messages"], control["messages"]] === {}];
Print["PROBE522A control_completed=", control["completed"]];
Print["PROBE522A bare_completed=", bare["completed"]];
Print["PROBE522A bare_wrote_mx=",
  Length@FileNames["ParticleSpectrographProbe522Bare.mx", Directory[]]];
Print["=== PROBE522A end ==="];

(* ---- Leg B: a genuinely undeclared symbol. Expected: UnknownCoupling. ----- *)
Print["=== PROBE522B begin (undeclared symbol) ==="];
(* PSALTer aborts via Throw, so this must be caught or the script dies here. *)
unknownMessages = {};
Catch[
  Block[{$MessageList = {}},
    ParticleSpectrum[
      -(1/4)*Global`UndeclaredCoupling*kinetic,
      TheoryName -> "Probe522Unknown", MaxLaurentDepth -> 1, ShowPropagator -> False];
    unknownMessages = $MessageList]];
Print["PROBE522B messages=", ToString[unknownMessages, InputForm]];
Print["PROBE522B unknowncoupling_template=",
  ToString[MessageName[ParticleSpectrum, "UnknownCoupling"], InputForm]];
Print["=== PROBE522B end ==="];

Print["PROBE522 done"];
Quit[0]
