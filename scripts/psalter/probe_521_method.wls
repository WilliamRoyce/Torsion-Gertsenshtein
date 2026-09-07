#!/usr/bin/env wolframscript
(* ==============================================================================
   Probe #521 -- is ParticleSpectrum's `Method` option inert?
   ==============================================================================
   Usage:
     QT_QPA_PLATFORM=offscreen wolframscript -file probe_521_method.wls

   `spectrum_design.md` originally told Stage 1 to run with Method -> "Hard" and
   to treat the wall time as the architecture's go/no-go number. Reading the
   pinned sources says the option is declared but its value is never consulted:
   OptionValue is called for the other six options and never for Method. A static
   read can miss an option consumed through an inheritance path, so this confirms
   it on the live install.

   Three legs, not two. Easy vs Hard agreeing is WEAK evidence -- two real code
   paths could coincide on a trivial theory. The decisive leg is a nonsense value
   matching no branch at all: if that produces byte-identical output and no
   complaint, the option is not being read. That leg is this probe's own addition.

   Smallest possible subject: one rank-0 field, so any timing difference would
   have to come from the option rather than from the physics.
   ============================================================================== *)

Print["PROBE521 begin"];
Needs["xAct`PSALTer`"];
Print["PROBE521 psalter_version=", xAct`PSALTer`Private`$Version[[1]]];

(* What the declared options are, and whether the symbol appears anywhere it
   would have to appear if it were read. FindList searches the INSTALLED tree,
   so this is a statement about the running install, not about GitHub. *)
Print["PROBE521 declared_options=", ToString[Options[ParticleSpectrum], InputForm]];
Print["PROBE521 optionvalue_method_sites=",
  Length@Flatten@Map[
    FindList[#, "OptionValue@Method"] &,
    FileNames["*.m", xAct`PSALTer`Private`$InstallDirectory, Infinity]]];
Print["PROBE521 optionvalue_maxlaurent_sites=",
  Length@Flatten@Map[
    FindList[#, "OptionValue@MaxLaurentDepth"] &,
    FileNames["*.m", xAct`PSALTer`Private`$InstallDirectory, Infinity]]];

DefConstantSymbol[Theta1];
DefConstantSymbol[Theta2];
DefField[ScalarField[], PrintAs -> "\[Phi]"];

L = (1/2)*Theta1*CD[-a]@ScalarField[]*CD[a]@ScalarField[]
    - (1/2)*Theta2*ScalarField[]*ScalarField[];

(* Distinct TheoryNames: PSALTer DumpSaves ParticleSpectrograph<Name>.mx on every
   update, so shared names would have the legs overwrite each other. *)
(* Messages are captured, not suppressed: whether the nonsense value draws a
   complaint is half of what this probe is measuring. *)
run[tag_String, method_] := Module[{t, assoc, locals, msgs},
  msgs = {};
  t = First@AbsoluteTiming@Block[{$MessageList = {}},
        ParticleSpectrum[L, TheoryName -> tag, MaxLaurentDepth -> 1,
                         ShowPropagator -> False, Method -> method];
        msgs = $MessageList];
  assoc = ToExpression["Global`" <> tag];
  locals = AssociationMap[ToExpression, Names["xAct`PSALTer`Private`$Local*"]];
  <|"wall" -> t,
    "messages" -> ToString[msgs, InputForm],
    "keys" -> (SymbolName /@ Keys[assoc]),
    "hash" -> IntegerString[Hash[BinarySerialize[Values[assoc]], "SHA256"], 16],
    "locals_hash" -> IntegerString[Hash[BinarySerialize[locals], "SHA256"], 16]|>];

easy = run["Probe521Easy", "Easy"];
hard = run["Probe521Hard", "Hard"];
junk = run["Probe521Junk", "ThisValueMatchesNoBranch"];

Print["PROBE521 wall_easy_s=", Round[easy["wall"], 0.01]];
Print["PROBE521 wall_hard_s=", Round[hard["wall"], 0.01]];
Print["PROBE521 wall_junk_s=", Round[junk["wall"], 0.01]];
Print["PROBE521 hash_easy=", easy["hash"]];
Print["PROBE521 hash_hard=", hard["hash"]];
Print["PROBE521 hash_junk=", junk["hash"]];
Print["PROBE521 results_identical_easy_hard=", easy["hash"] === hard["hash"]];
Print["PROBE521 results_identical_all_three=",
      easy["hash"] === hard["hash"] === junk["hash"]];
Print["PROBE521 locals_identical_all_three=",
      easy["locals_hash"] === hard["locals_hash"] === junk["locals_hash"]];
Print["PROBE521 messages_easy=", easy["messages"]];
Print["PROBE521 messages_hard=", hard["messages"]];
Print["PROBE521 messages_junk=", junk["messages"]];
Print["PROBE521 done"];
Quit[0]
