(* ==============================================================================
   PSALTer Smoke Test
   ==============================================================================
   Verifies that PSALTer is installed and, critically, that its unconditional
   PDF export works headlessly.

   Usage:
     QT_QPA_PLATFORM=offscreen wolframscript -file scripts/psalter_smoke.wl

   Why the environment variable matters: DefField calls SummariseField
   (Sources/DefField.m:91), which exports a FieldKinematics<Field>.pdf through
   the Wolfram front end (Sources/DefField/SummariseField.m:85) with no guard and
   no time limit. The front end needs a Qt platform plugin whose libraries are
   all present; when none can be initialized, Qt aborts and the export call
   blocks indefinitely rather than failing. `offscreen` is the plugin most likely
   to be satisfiable on a bare container.
   Run this from a throwaway directory: PSALTer writes into the current one.

   Expected output:
     - PSALTer version banner
     - A declared field, and the PDF it exported
     - "PSALTER SMOKE TEST PASSED"
   ============================================================================== *)

Print["========================================"];
Print["PSALTer Smoke Test"];
Print["========================================"];
Print[""];

Print["Loading PSALTer (first load builds projection-operator tables)..."];
Needs["xAct`PSALTer`"];
Print["PSALTER_VERSION=", xAct`PSALTer`Private`$Version[[1]]];
Print["> Package loaded"];
Print[""];

(* PSALTer defines its functions through the StackSetDelayed wrapper, so they
   carry definition rules rather than a value: DownValues is the right test,
   ValueQ reports False for a perfectly good install. *)
Print["Checking entry points..."];
Print["PSALTER_SYMBOLS_OK=",
  TrueQ[Length[DownValues[xAct`PSALTer`DefField]] > 0 &&
        Length[DownValues[xAct`PSALTer`ParticleSpectrum]] > 0]];
Print["> DefField and ParticleSpectrum are defined"];
Print[""];

(* The load-bearing step: declaring a field triggers the headless PDF export. *)
Print["Declaring a rank-1 field (this exports a PDF via the front end)..."];
DefField[SmokeTestField[-a], PrintAs -> "A"];
Print["> Field declared"];
Print[""];

Print["Checking the exported PDF..."];
Print["PSALTER_DEFFIELD_PDF=",
  Length@FileNames["FieldKinematics*.pdf", xAct`PSALTer`Private`$WorkingDirectory]];
Print["  Working directory: ", xAct`PSALTer`Private`$WorkingDirectory];
Print[""];

Print["========================================"];
Print["PSALTER SMOKE TEST PASSED"];
Print["========================================"];
Print[""];
Print["PSALTer is installed and exports PDFs headlessly."];
Print[""];

Quit[0]
