#!/usr/bin/env wolframscript
(* ==============================================================================
   register_resources.wl -- make PSALTer's two undocumented Function Repository
   dependencies resolve on this machine, from the GENUINE code, with no edit to
   PSALTer and no change to the pinned install.  GH #543 / #551 / #556.
   ==============================================================================
   Usage (lane idle; writes only the resource registry under $LocalBase, i.e.
   ~/.Wolfram/Objects, which every kernel on the machine shares):

     wolframscript -file scripts/psalter/register_resources.wl

   Why this exists.  PSALTer calls ResourceFunction["LinearlyIndependent"] (on
   subkernels, IsNullVectorOfSpace.m:6, and on the master, SymbolicNullSpace.m:31)
   and ResourceFunction["PolynomialDegree"] (ValidateLagrangian.m:38,
   UnresolvedPoleRow.m:11,21).  When either does not resolve, the result is
   non-Boolean, `If` takes no branch, every null space comes back {}, and the
   gauge-singular determinants divide by zero -- the Tier-1 MISMATCH of #543.
   The Function Repository has not served definitions to this machine at all
   (outage, then a 401 for anonymous clients, then a truncated response even for
   an authenticated one -- see #551), so the genuine code is registered locally:

     LinearlyIndependent  -- the Function Repository entry (v3.0.0) is a thin
                             wrapper around ResourceFunctionHelpers`LinearlyIndependent,
                             shipped by Wolfram in the ResourceFunctionHelpers paclet
                             that is already installed.  Located via PacletFind; the
                             file is loaded verbatim under our own package name so the
                             registered object stores the full definition (a symbol
                             reference is engine-dependent, see below).
     PolynomialDegree     -- the Function Repository entry (v1.0.0, contributed by
                             Dennis M Schneider) is a six-line definition.  It is
                             evaluated VERBATIM from the repository's own definition
                             notebook, downloaded from the resource page and pinned
                             by sha256 below.  Never retyped (#556).

   How name resolution works (read from the installed ResourceSystemClient-1.26.1,
   Path.m:29-42 and FindResource.m:23-34, 2026-09-11): the search path is LOCAL
   FIRST and short-circuits on the first hit, so once the name->UUID entry exists
   in ~/.Wolfram/Objects/Persistence/ResourceNames the repository is never asked,
   whatever the network or login state.  What was observed earlier ("the
   repository wins") is the poisoning case: a name that is NOT yet registered gets
   resolved by the repository and cached under that name, after which the
   repository object is sticky.  So this script points $ResourceSystemBase at an
   unreachable address FOR THIS KERNEL ONLY while it clears any such entries and
   registers both objects; the variable dies with this kernel and nothing on disk
   disables the repository.  Fresh kernels afterwards -- master and PSALTer's
   subkernels, with the normal repository address -- resolve both names locally.

   IDENTITY IS FIXED.  Both objects are registered with the UUIDs the 2026-09-11
   certification recorded (evidence/tier1-20260911-pass/README.md), so any machine
   that runs this script produces the same identities, and verify-wolfram-setup.sh
   check 10 can assert PROVENANCE (these UUIDs, on master and subkernel) rather
   than merely behavior -- a repository-fetched function behaves identically and
   would otherwise pass unnoticed.

   The registry lives under ~/.Wolfram/Objects, which is container overlay unless
   the devcontainer mounts it; scripts/psalter/ensure_registered.sh re-runs this
   idempotently and is what install-psalter.sh and the devcontainer call.

   Exit 0: both names resolve and BEHAVE on this kernel and on a fresh subkernel
   (values, not merely symbols).  Exit 1: anything else.  Re-runnable: existing
   entries under either name are removed first.
   ============================================================================== *)

Off[General::stop];
say[a__] := Print["PSALTER_RESOURCES ", a];
fail[a__] := (say["FAIL ", a]; Quit[1]);

(* Repository lookups must not win during registration; session-scoped only. *)
$ResourceSystemBase = "https://127.0.0.1:9/";

repoRoot = DirectoryName[$InputFileName, 3];
(* The PolynomialDegree definition notebook is COMMITTED (scripts/psalter/resources/, sha256-
   pinned, PROVENANCE.md beside it) so certification needs no live cloud URL: a fresh user
   gets it with the clone.  third_party/psalter_resources/ is the pre-#557 location and a
   download is the last resort. *)
committedDir = FileNameJoin[{repoRoot, "scripts", "psalter", "resources"}];
resourceDir = FileNameJoin[{repoRoot, "third_party", "psalter_resources"}];

(* Certified identities and content hashes -- evidence/tier1-20260911-pass/README.md. *)
liUUID = "d40a8dd6-658c-47d2-8719-2f5fc8e1f83d";
pdUUID = "2f89f2e6-7bc8-4491-84bf-d8e13c69addb";
liSHA  = "7bc228a2eb817a65b1760fee81954922430f11031287b045912c1379bd58b817";

(* ---- 1. LinearlyIndependent: the installed ResourceFunctionHelpers paclet ---- *)
paclet = First[PacletFind["ResourceFunctionHelpers"], $Failed];
If[paclet === $Failed, fail["ResourceFunctionHelpers paclet not installed"]];
pacletFile = FileNameJoin[{paclet["Location"], "Kernel", "LinearlyIndependent.wl"}];
If[!FileExistsQ[pacletFile], fail["paclet file missing: ", pacletFile]];
(* The certified thing is the FILE CONTENT, not the paclet version: the engine-bundled
   ResourceFunctionHelpers (1.3.33, SystemFiles/Components) and the userbase 1.3.34 copy are
   byte-identical (measured 2026-09-11), so a fresh user's offline copy certifies too. *)
If[FileHash[pacletFile, "SHA256", "HexString"] =!= liSHA,
  fail["LinearlyIndependent.wl sha256 is not the certified ", liSHA, ": ", FileHash[pacletFile, "SHA256", "HexString"], " (", pacletFile, ")"]];
(* Load Wolfram's paclet file VERBATIM under a package name of our own, so the function
   and its private helpers (undeterminedsystem, DetNotZero) land in PSALTerResources`RFH`
   and the registered object stores the full definition. A registration that merely
   references ResourceFunctionHelpers`LinearlyIndependent is engine-dependent: on 14.3
   that symbol is an autoload alias (an OwnValue, no DownValues) and on 14.2.1 it evaluated
   to $Failed once PSALTer was loaded. Only the BeginPackage name is changed. *)
pacletText = Import[pacletFile, "Text"];
If[StringCount[pacletText, "BeginPackage[\"ResourceFunctionHelpers`\"]"] =!= 1,
  fail["unexpected paclet file layout (BeginPackage not found exactly once)"]];
renamedText = StringReplace[pacletText, "BeginPackage[\"ResourceFunctionHelpers`\"]" -> "BeginPackage[\"PSALTerResources`RFH`\"]"];
renamedFile = FileNameJoin[{$TemporaryDirectory, "PSALTerResources-LinearlyIndependent.wl"}];
Export[renamedFile, renamedText, "Text"];
Get[renamedFile];
DeleteFile[renamedFile];
liSym = PSALTerResources`RFH`LinearlyIndependent;
(* DownValues and ExtendedFullDefinition hold their argument: apply them to the symbol itself. *)
If[Length[DownValues @@ {liSym}] == 0, fail["no definitions loaded from the paclet file"]];
liDeps = DeleteDuplicates@Cases[Language`ExtendedFullDefinition @@ {liSym}, s_Symbol /; StringStartsQ[Context[s], "ResourceFunctionHelpers`"] :> s, Infinity, Heads -> True];
If[liDeps =!= {}, fail["loaded LinearlyIndependent still references the paclet's own context: ", InputForm[liDeps]]];
If[liSym[{{1, 0}, {0, 1}}] =!= True || liSym[{{1, 0}, {2, 0}}] =!= False || liSym[{{0, 1}}] =!= True || liSym[{{0, 0}}] =!= False,
  fail["loaded LinearlyIndependent does not behave"]];
say["paclet=ResourceFunctionHelpers version=", paclet["Version"], " file=", pacletFile,
    " sha256=", FileHash[pacletFile, "SHA256", "HexString"], " downvalues_loaded=", Length[DownValues @@ {liSym}], " helpers=", Length[Names["PSALTerResources`RFH`LinearlyIndependent`Private`*"]]];

(* ---- 2. PolynomialDegree: the author's definition notebook, sha256-pinned ---- *)
pdName = "PolynomialDegree-1-0-0-definition.nb";
pdURL = "https://www.wolframcloud.com/download/c64bf854-fcd3-40f3-9aa2-4ec399411d8f?extension=always&filename=PolynomialDegree-1-0-0-definition";
pdSHA = "c233e226d4c77de65ee19ddbc84c20c9724df467bb86c27f1a65f17fba89787c";
pdNotebook = Which[
  FileExistsQ[FileNameJoin[{committedDir, pdName}]], FileNameJoin[{committedDir, pdName}],
  FileExistsQ[FileNameJoin[{resourceDir, pdName}]],  FileNameJoin[{resourceDir, pdName}],
  True, If[!DirectoryQ[resourceDir], CreateDirectory[resourceDir]];
        say["committed notebook missing; downloading ", pdURL]; URLDownload[pdURL, FileNameJoin[{resourceDir, pdName}]];
        FileNameJoin[{resourceDir, pdName}]];
If[FileHash[pdNotebook, "SHA256", "HexString"] =!= pdSHA,
  fail["PolynomialDegree notebook sha256 mismatch: ", FileHash[pdNotebook, "SHA256", "HexString"]]];
nb = Import[pdNotebook];
defBoxes = Cases[nb, Cell[BoxData[b_], "Input" | "Code", ___] :> b, Infinity];
Begin["PSALTerResources`"];
heldDefs = Select[ToExpression[#, StandardForm, Hold] & /@ defBoxes,
  ! FreeQ[#, SetDelayed | Set] && ! FreeQ[#, PolynomialDegree] &];
ReleaseHold /@ heldDefs;
Global`nDefinitionCells = Length[heldDefs];
End[];
pdSym = Symbol["PSALTerResources`PolynomialDegree"];
If[pdSym[a^2 b, {a, b}] =!= 3 || pdSym[a b + a^3, {a, b}] =!= 3 || pdSym[c1 Def^4 + c2 Def^2, Def] =!= 4,
  fail["notebook PolynomialDegree does not behave: ", InputForm[pdSym[a^2 b, {a, b}]]]];
say["notebook=", pdNotebook, " sha256=", pdSHA, " definition_cells=", nDefinitionCells];

(* ---- 3. Clean the shared registry of anything under either name, deterministically ----
   Name lookups are what we are trying to control, so the cleanup does not use them: every
   cached object carries its own metadata/put.wl naming it; those, the name-cache entries
   and the repository name/version lists are removed by path. Only entries for the two
   names are touched. *)
localBase = FileNameJoin[URLParse[$LocalBase, "Path"]];
names = {"LinearlyIndependent", "PolynomialDegree"};
mentionsQ[file_] := FileExistsQ[file] && StringContainsQ[Import[file, "Text"], RegularExpression["\"Name\"\\s*->\\s*\"(" <> StringRiffle[names, "|"] <> ")\""]];
removed = {};
Do[If[mentionsQ[FileNameJoin[{d, "metadata", "put.wl"}]], DeleteDirectory[d, DeleteContents -> True]; AppendTo[removed, FileNameTake[d]];
      If[FileNames["*", DirectoryName[d]] === {}, DeleteDirectory[DirectoryName[d]]]],
   {d, Select[FileNames["*", FileNameJoin[{localBase, "Resources"}], 2], DirectoryQ]}];
Do[If[mentionsQ[FileNameJoin[{d, "put.wl"}]], DeleteDirectory[d, DeleteContents -> True]; AppendTo[removed, "ResourceNames/" <> FileNameTake[d]]],
   {d, Select[FileNames["*", FileNameJoin[{localBase, "Persistence", "ResourceNames"}]], DirectoryQ]}];
Do[With[{d = FileNameJoin[{localBase, "Persistence", "ResourceFunctionAutocompleteNames", n}]}, If[DirectoryQ[d], DeleteDirectory[d, DeleteContents -> True]; AppendTo[removed, "Autocomplete/" <> n]]], {n, names}];
Do[With[{d = FileNameJoin[{localBase, "Resources", c}]}, If[DirectoryQ[d], DeleteDirectory[d, DeleteContents -> True]; AppendTo[removed, c]]], {c, {"namescache", "versionscache"}}];
say["registry_cleaned=", InputForm[removed]];

(* ---- 4. Build, register, resolve once ---- *)
(* Why "Autoload" -> True: a caller-supplied "UUID" alone makes the client treat the
   association as a reference to an already-known resource; ResourceRegister then looks the
   UUID up, cannot find it and fails (ResourceObject::notf; ResourceSystemClient 1.26.1
   CreateResources.m:8-18, Resources.m:99-113). "Autoload" -> True routes the construction
   through the client's own restore path (CreateResources.m:46-54), which loads the supplied
   UUID into the session before registering -- the same path a persisted object takes when
   it is read back from the registry. Measured 2026-09-11: without it, registration fails;
   with it, the UUID is kept, the name resolves and the function evaluates. Fixed UUIDs make
   the registry byte-for-byte reproducible after a rebuild, which is what lets
   verify-wolfram-setup.sh assert provenance by identity. *)
liRO = ResourceObject[<|"Name" -> "LinearlyIndependent", "ResourceType" -> "Function",
  "UUID" -> liUUID, "Autoload" -> True, "Function" -> liSym, "Version" -> "3.0.0",
  "Description" -> "Determine whether a set of vectors is linearly independent (genuine implementation: Wolfram's ResourceFunctionHelpers paclet file loaded verbatim under a private package name; registered locally for PSALTer, GH #543)"|>];
pdRO = ResourceObject[<|"Name" -> "PolynomialDegree", "ResourceType" -> "Function",
  "UUID" -> pdUUID, "Autoload" -> True, "Function" -> pdSym, "Version" -> "1.0.0",
  "Description" -> "Compute the degree of a polynomial in any number of variables (author: Dennis M Schneider; evaluated verbatim from the Function Repository definition notebook, sha256 " <> pdSHA <> "; registered locally for PSALTer, GH #543)",
  "ContributorInformation" -> <|"ContributedBy" -> "Dennis M Schneider"|>|>];
(* The symbol form must evaluate through the resource; otherwise fall back to the
   author's body as a pure function (unreachable difference: Return[] on a
   non-polynomial), and say so. *)
pdForm = "symbol";
If[ResourceFunction[pdRO][a^2 b, {a, b}] =!= 3,
  pdForm = "pure-function";
  pdRO = ResourceObject[<|"Name" -> "PolynomialDegree", "ResourceType" -> "Function",
    "UUID" -> pdUUID, "Autoload" -> True, "Function" -> Function[{poly, varslist}, If[poly === 0, Undefined,
      Module[{epoly = Expand[poly]},
        If[!PolynomialQ[epoly, varslist], Message[PSALTerResources`Poly::notpoly, poly, varslist]; Return[]];
        If[Head[epoly] =!= Plus, Plus @@ Exponent[epoly, varslist],
          Max[(Plus @@ Exponent[#1, varslist] &) /@ Level[epoly, 1]]]]]],
    "Version" -> "1.0.0",
    "Description" -> "Compute the degree of a polynomial in any number of variables (author: Dennis M Schneider; body from the Function Repository definition notebook, sha256 " <> pdSHA <> "; registered locally for PSALTer, GH #543)",
    "ContributorInformation" -> <|"ContributedBy" -> "Dennis M Schneider"|>|>]];
If[liRO["UUID"] =!= liUUID || pdRO["UUID"] =!= pdUUID,
  fail["ResourceObject did not keep the supplied UUIDs: ", InputForm[{liRO["UUID"], pdRO["UUID"]}]]];
r1 = ResourceRegister[liRO, "Local"]; r2 = ResourceRegister[pdRO, "Local"];
If[Head[r1] =!= ResourceObject && Head[r1] =!= ResourceFunction, fail["ResourceRegister LinearlyIndependent: ", InputForm[r1]]];
If[Head[r2] =!= ResourceObject && Head[r2] =!= ResourceFunction, fail["ResourceRegister PolynomialDegree: ", InputForm[r2]]];
say["registered LinearlyIndependent uuid=", liRO["UUID"], " PolynomialDegree uuid=", pdRO["UUID"], " pd_form=", pdForm,
    " definition_lists=", InputForm[Quiet@{Length[liRO["DefinitionList"]], Length[pdRO["DefinitionList"]]}]];

(* ---- 5. Behavior on this kernel, then on fresh subkernels (normal repository address) ---- *)
master = {ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}],
          ResourceFunction["LinearlyIndependent"][{{1, 0}, {2, 0}}],
          If[True && ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}], "appended", "not", "neither"],
          ResourceFunction["PolynomialDegree"][a^2 b, {a, b}],
          If[ResourceFunction["PolynomialDegree"][a^3 b, {a, b}] > 2, "fired", "not fired", "neither"]};
say["master=", InputForm[master], " resolved_uuids=", InputForm[{ResourceObject["LinearlyIndependent"]["UUID"], ResourceObject["PolynomialDegree"]["UUID"]}]];
If[master =!= {True, False, "appended", 3, "fired"}, fail["master behavior wrong"]];
If[{ResourceObject["LinearlyIndependent"]["UUID"], ResourceObject["PolynomialDegree"]["UUID"]} =!= {liUUID, pdUUID},
  fail["by-name resolution did not pick the certified identities on the master"]];
LaunchKernels[2];
sub = ParallelEvaluate[{$KernelID, $ResourceSystemBase,
  ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}],
  !ResourceFunction["LinearlyIndependent"][{{1, 0}, {1, 0}}],
  If[True && ResourceFunction["LinearlyIndependent"][{{1, 0}, {0, 1}}], "appended", "not", "neither"],
  ResourceFunction["PolynomialDegree"][a^2 b, {a, b}],
  If[ResourceFunction["PolynomialDegree"][a^3 b, {a, b}] > 2, "fired", "not fired", "neither"],
  ResourceObject["LinearlyIndependent"]["UUID"], ResourceObject["PolynomialDegree"]["UUID"]}];
CloseKernels[];
say["subkernels=", InputForm[sub]];
(* Behavior AND provenance on every subkernel: the resolved objects must be the certified
   identities, not a repository fetch that happens to behave the same. *)
If[!AllTrue[sub, Take[#, {3, 7}] === {True, True, "appended", 3, "fired"} &], fail["subkernel behavior wrong"]];
If[!AllTrue[sub, Take[#, {8, 9}] === {liUUID, pdUUID} &], fail["subkernel resolution is not the certified identities: ", InputForm[Take[#, {8, 9}] & /@ sub]]];
say["registry=", InputForm[FileNames["*", FileNameJoin[{FileNameJoin[URLParse[$LocalBase, "Path"]], "Resources"}]]]];
say["DONE ok"];
Quit[0]
