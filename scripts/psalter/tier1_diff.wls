#!/usr/bin/env wolframscript
(* ==============================================================================
   Tier-1 install gate: compare our PSALTer run against the author's own result
   ==============================================================================
   Usage:
     wolframscript -file tier1_diff.wls <ours.mx> <oracle.mx> <TheoryName> <out.json>

   Tier 1 gates the PSALTer install because BOTH sides are the author's: his
   published input script and his published result file. A mismatch can then only
   be our install. Everything here exists to keep that property honest.

   Three things are deliberate.

   1. PSALTer is NOT loaded. Loading it redefines Print and Message globally
      (PSALTer.m:15-20) and attaches meanings to the very symbols the saved
      results are written in terms of, which could re-evaluate the thing we are
      trying to compare. This runs in a plain kernel.

   2. Both .mx files define a symbol of the SAME name, so loading the second
      overwrites the first. We load one, copy its value into an ordinary
      variable, clear the name, then load the other. Wolfram expressions are
      immutable, so the copy is unaffected. The symbol is discovered by search
      rather than assumed, so a result file produced differently is diagnosed
      instead of silently missed.

   3. The per-entry verdict is THREE-valued. Simplify is not complete, so
      "did not prove equal" and "proved different" are different facts, and
      collapsing them manufactures a false pass. An undecided comparison is a
      blocking flag, never a pass. Every comparison is time-limited so a hang
      becomes a verdict rather than another stall on the single-license lane.
   ============================================================================== *)

$HistoryLength = 0;

args = Rest@$ScriptCommandLine;
If[Length[args] < 4,
  Print["usage: tier1_diff.wls <ours.mx> <oracle.mx> <TheoryName> <out.json>"];
  Quit[2]];
{oursPath, oraclePath, theoryName, outPath} = args[[1 ;; 4]];

(* Budgets. Generous relative to the expressions actually involved, but finite:
   an unbounded Simplify on a large symbolic matrix is exactly the kind of stall
   this gate must not introduce. *)
$normalizeSeconds = ToExpression@Environment["TIER1_NORMALIZE_SECONDS"] /. _?(!NumberQ[#]&) -> 60;
$simplifySeconds  = ToExpression@Environment["TIER1_SIMPLIFY_SECONDS"]  /. _?(!NumberQ[#]&) -> 300;
$maxDepth         = ToExpression@Environment["TIER1_MAX_DEPTH"]         /. _?(!NumberQ[#]&) -> 4;
$maxPositions     = 20;

(* ---------------------------------------------------------------- loading -- *)

(* Load one .mx and hand back the value it defined, leaving the kernel clean.
   OwnValues is HoldAll, so testing it does not evaluate the symbol. *)
loadTheory[path_String, name_String] := Module[{before, after, sym, val, got},
  before = Names["*`" <> name];
  Scan[(Unprotect[#]; ClearAll[#]) &, before];
  got = Quiet@Check[Get[path], $Failed];
  after = Names["*`" <> name];
  sym = SelectFirst[after, ToExpression[#, InputForm, OwnValues] =!= {} &];
  val = If[MissingQ[sym], Missing["NoSymbol"], ToExpression[sym]];
  Scan[(Unprotect[#]; ClearAll[#]) &, after];
  <|"getResult" -> ToString[got, InputForm],
    "symbol"    -> If[MissingQ[sym], Null, sym],
    "loaded"    -> !MissingQ[sym],
    "value"     -> val|>];

(* ------------------------------------------------------------ comparison -- *)

exprHash[e_] := IntegerString[Hash[BinarySerialize[e], "SHA256"], 16, 64];

(* A tidied form for the fast path. Never the verdict on its own: two equal
   expressions can serialize differently. *)
normalize[e_] := Quiet@TimeConstrained[Together[Expand[e]], $normalizeSeconds, e];

summary[e_] := <|
  "head"       -> ToString[Head[e]],
  "dimensions" -> Dimensions[e],
  "leaf_count" -> LeafCount[e],
  "byte_count" -> ByteCount[e],
  "hash_sha256"            -> exprHash[e],
  "hash_normalized_sha256" -> exprHash[normalize[e]]|>;

truncate[s_String] := If[StringLength[s] > 400, StringTake[s, 400] <> "...", s];


(* The three-valued core. Returns one of:
     equal / different / undecided  -- plus the evidence for the last two.

   Positions are taken at exactly the ARRAY depth, not at leaf level. The
   difference expression d = a - b shares the array structure of a and b, but its
   scalar entries do not: descending into a Times or Plus yields positions that
   are meaningless in a and b, and Extract then reports nonsense. *)
proveEqual[a_, b_] := Module[{d, depth, nonzero, total},
  d = TimeConstrained[Simplify[a - b], $simplifySeconds, $TimedOut];
  If[d === $TimedOut,
    Return@<|"status" -> "undecided_timeout",
             "detail" -> "Simplify exceeded " <> ToString[$simplifySeconds] <> " s",
             "positions" -> {}|>];

  depth = ArrayDepth[d];
  If[depth === 0,
    (* scalar comparison *)
    If[TrueQ[PossibleZeroQ[d]],
      Return@<|"status" -> "equal_simplified", "detail" -> "", "positions" -> {}|>,
      Return@<|"status" -> "different", "detail" -> "the two values differ",
        "positions" -> {<|"position" -> {},
          "ours" -> truncate@ToString[a, InputForm],
          "oracle" -> truncate@ToString[b, InputForm],
          "difference" -> truncate@ToString[d, InputForm]|>}|>]];

  nonzero = Position[d, x_ /; !TrueQ[PossibleZeroQ[x]], {depth}, Heads -> False];
  total = Times @@ Dimensions[d];
  If[nonzero === {},
    <|"status" -> "equal_simplified", "detail" -> "", "positions" -> {}|>,
    <|"status" -> "different",
      "detail" -> ToString[Length[nonzero]] <> " of " <> ToString[total] <>
                  " entries differ",
      "positions" -> (Function[pos,
          <|"position" -> pos,
            "ours"       -> truncate@ToString[Extract[a, pos], InputForm],
            "oracle"     -> truncate@ToString[Extract[b, pos], InputForm],
            "difference" -> truncate@ToString[Extract[d, pos], InputForm]|>]
        /@ Take[nonzero, UpTo[$maxPositions]])|>]];

compare[a_, b_, path_List, depth_Integer] := Module[{status, ev, kids = {}},
  Which[
    a === b,
      status = "identical"; ev = <|"detail" -> "", "positions" -> {}|>,
    Head[a] =!= Head[b],
      status = "head_mismatch";
      ev = <|"detail" -> ToString[Head[a]] <> " vs " <> ToString[Head[b]],
             "positions" -> {}|>,
    Dimensions[a] =!= Dimensions[b],
      status = "dimension_mismatch";
      ev = <|"detail" -> ToString[Dimensions[a]] <> " vs " <> ToString[Dimensions[b]],
             "positions" -> {}|>,
    exprHash[normalize[a]] === exprHash[normalize[b]],
      status = "equal_normalized"; ev = <|"detail" -> "", "positions" -> {}|>,
    True,
      With[{r = proveEqual[a, b]},
        status = r["status"];
        ev = <|"detail" -> r["detail"], "positions" -> r["positions"]|>]];

  (* Descend only when the node disagrees and there is somewhere to descend to,
     so a passing gate stays small and a failing one localizes. *)
  If[status =!= "identical" && status =!= "equal_normalized" &&
     status =!= "equal_simplified" && depth < $maxDepth &&
     Head[a] === List && Head[b] === List && Length[a] === Length[b],
    kids = Table[compare[a[[i]], b[[i]], Append[path, i], depth + 1], {i, Length[a]}]];

  <|"path" -> path, "status" -> status, "detail" -> ev["detail"],
    "ours" -> summary[a], "oracle" -> summary[b],
    "differing_positions" -> ev["positions"], "children" -> kids|>];

(* ----------------------------------------------------------------- main --- *)

fullName[k_] := If[Head[k] === Symbol, Context[k] <> SymbolName[k], ToString[k, InputForm]];
shortName[k_] := If[Head[k] === Symbol, SymbolName[k], ToString[k, InputForm]];

write[assoc_] := (Developer`WriteRawJSONFile[outPath, assoc, "Compact" -> False]; assoc);

ours   = loadTheory[oursPath, theoryName];
oracle = loadTheory[oraclePath, theoryName];

base = <|
  "schema_version" -> 1,
  "artifact" -> "psalter-tier1-diff",
  "generated_utc" -> DateString[Now, "ISODateTime", TimeZone -> 0] <> "Z",
  "theory_name" -> theoryName,
  "environment" -> <|
    "wolfram_version" -> $Version,
    "version_number" -> $VersionNumber,
    "system_id" -> $SystemID|>,
  "settings" -> <|
    "max_depth" -> $maxDepth,
    "normalize_seconds" -> $normalizeSeconds,
    "simplify_seconds" -> $simplifySeconds,
    "max_reported_positions" -> $maxPositions|>,
  "ours_symbol" -> ours["symbol"],
  "oracle_symbol" -> oracle["symbol"],
  "ours_get_result" -> ours["getResult"],
  "oracle_get_result" -> oracle["getResult"]|>;

(* An unreadable result file is its own verdict, never a mismatch: it means the
   gate could not be run, not that the install is wrong. *)
If[!oracle["loaded"],
  write@Join[base, <|"verdict" -> "oracle_unreadable",
    "verdict_reason" -> "Could not load a `" <> theoryName <> "` from " <> oraclePath,
    "entries" -> {}|>];
  Print["TIER1_VERDICT=oracle_unreadable"]; Quit[1]];

If[!ours["loaded"],
  write@Join[base, <|"verdict" -> "ours_unreadable",
    "verdict_reason" -> "Could not load a `" <> theoryName <> "` from " <> oursPath,
    "entries" -> {}|>];
  Print["TIER1_VERDICT=ours_unreadable"]; Quit[1]];

a = ours["value"]; b = oracle["value"];

keysOurs = Keys[a]; keysOracle = Keys[b];
shortOurs = shortName /@ keysOurs; shortOracle = shortName /@ keysOracle;
common = Intersection[shortOurs, shortOracle];
onlyOurs = Complement[shortOurs, shortOracle];
onlyOracle = Complement[shortOracle, shortOurs];

(* Keys are matched by NAME, not identity: if the two sides' key symbols live in
   different contexts, an identity match would report a total mismatch for a
   purely cosmetic reason. Recorded as a note, not a failure. *)
keyFor[keys_List, short_String] := SelectFirst[keys, shortName[#] === short &];
lookup[assoc_, keys_List, short_String] := assoc[keyFor[keys, short]];

(* Named arguments throughout: nested pure functions would shadow #1 here. *)
contextMismatches = Select[common,
  Function[short,
    fullName[keyFor[keysOurs, short]] =!= fullName[keyFor[keysOracle, short]]]];

entries = Table[
  compare[lookup[a, keysOurs, k], lookup[b, keysOracle, k], {k}, 0],
  {k, common}];

collect[e_] := Prepend[Flatten[collect /@ e["children"]], e["status"]];
allStatuses = Flatten[collect /@ entries];
passing = {"identical", "equal_normalized", "equal_simplified"};

verdict = Which[
  onlyOurs =!= {} || onlyOracle =!= {}, "mismatch",
  MemberQ[allStatuses, "different" | "head_mismatch" | "dimension_mismatch"], "mismatch",
  MemberQ[allStatuses, "undecided_timeout"], "undecided",
  AllTrue[allStatuses, MemberQ[passing, #] &], "match",
  True, "undecided"];

reason = Which[
  verdict === "match",
    ToString[Length[common]] <> " key(s) compared; every entry proved equal",
  onlyOurs =!= {} || onlyOracle =!= {},
    "key sets differ: only-ours " <> ToString[onlyOurs] <> ", only-oracle " <> ToString[onlyOracle],
  verdict === "undecided",
    "at least one comparison could not be decided; that is not a pass",
  True,
    "at least one entry differs"];

result = write@Join[base, <|
  "verdict" -> verdict,
  "verdict_reason" -> reason,
  "keys_ours" -> (fullName /@ keysOurs),
  "keys_oracle" -> (fullName /@ keysOracle),
  "keys_only_ours" -> onlyOurs,
  "keys_only_oracle" -> onlyOracle,
  "context_mismatches" -> contextMismatches,
  "status_tally" -> Association[# -> Count[allStatuses, #] & /@ DeleteDuplicates[allStatuses]],
  "used_simplify_fallback" -> Select[
      entries, MemberQ[collect[#], "equal_simplified"] &][[All, "path"]],
  "entries" -> entries|>];

Print["TIER1_VERDICT=", verdict];
Print["TIER1_REASON=", reason];
Print["TIER1_TALLY=", result["status_tally"]];
Quit[If[verdict === "match", 0, 1]]
