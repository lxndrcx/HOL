open HolKernel Parse boolLib bossLib
open boolSimps
open grammarTheory finite_mapTheory
open locationTheory

val _ = new_theory "peg"

(* Based on
     Koprowski and Binzstok, "TRX: A Formally Verified Parser Interpreter".
     LMCS vol 7, no. 2. 2011.
     DOI: 10.2168/LMCS-7(2:18)2011
*)

val _ = Hol_datatype `pegsym =
    empty of 'c
  | any of (('a # locs) -> 'c)
  | tok of ('a -> bool) => (('a # locs) -> 'c)
  | nt of 'b inf => ('c -> 'c)
  | seq of pegsym => pegsym => ('c  -> 'c -> 'c)
  | choice of pegsym => pegsym => ('c + 'c -> 'c)
  | rpt of pegsym => ('c list -> 'c)
  | not of pegsym => 'c
`

val _ = Hol_datatype`
  peg = <| start : ('a,'b,'c) pegsym ;
           rules : 'b inf |-> ('a,'b,'c) pegsym |>
`
(* Option type should be replaced with sum type (loc. for NONE *)
Inductive peg_eval:
  (∀s c. peg_eval G (s, empty c) (SOME(s, c))) ∧
  (∀n r s f c.
       n ∈ FDOM G.rules ∧ peg_eval G (s, G.rules ' n) (SOME(r,c)) ⇒
       peg_eval G (s, nt n f) (SOME(r, f c))) ∧
  (∀n s f.
       n ∈ FDOM G.rules ∧ peg_eval G (s, G.rules ' n) NONE ⇒
       peg_eval G (s, nt n f) NONE) ∧
  (∀h t f. peg_eval G (h::t, any f) (SOME (t, f h))) ∧
  (∀f. peg_eval G ([], any f) NONE) ∧
  (∀e t P f. P (FST e) ⇒ peg_eval G (e::t, tok P f) (SOME(t, f e))) ∧
  (∀e t P f. ¬P (FST e) ⇒ peg_eval G (e::t, tok P f) NONE) ∧
  (∀P f. peg_eval G ([], tok P f) NONE) ∧
  (∀e s c. peg_eval G (s, e) NONE ⇒ peg_eval G (s, not e c) (SOME(s,c))) ∧
  (∀e s s' c. peg_eval G (s, e) (SOME s') ⇒ peg_eval G (s, not e c) NONE)  ∧
  (∀e1 e2 s f. peg_eval G (s, e1) NONE ⇒ peg_eval G (s, seq e1 e2 f) NONE)  ∧
  (∀e1 e2 s0 s1 c1 f.
     peg_eval G (s0, e1) (SOME (s1, c1)) ∧ peg_eval G (s1, e2) NONE ⇒
     peg_eval G (s0, seq e1 e2 f) NONE) ∧
  (∀e1 e2 s0 s1 s2 c1 c2 f.
     peg_eval G (s0, e1) (SOME(s1, c1)) ∧
     peg_eval G (s1, e2) (SOME(s2, c2)) ⇒
     peg_eval G (s0, seq e1 e2 f) (SOME(s2, f c1 c2))) ∧
  (∀e1 e2 s f.
     peg_eval G (s, e1) NONE ∧ peg_eval G (s, e2) NONE ⇒
     peg_eval G (s, choice e1 e2 f) NONE) ∧
  (∀e1 e2 s s' f c.
     peg_eval G (s, e1) (SOME(s',c)) ⇒
     peg_eval G (s, choice e1 e2 f) (SOME(s', f (INL c)))) ∧
  (∀e1 e2 s s' f c.
     peg_eval G (s, e1) NONE ∧ peg_eval G (s, e2) (SOME(s',c)) ⇒
     peg_eval G (s, choice e1 e2 f) (SOME(s',f (INR c))))  ∧
  (∀e f s s1 list.
     peg_eval_list G (s, e) (s1,list) ⇒
     peg_eval G (s, rpt e f) (SOME(s1, f list))) ∧
  (∀e s. peg_eval G (s, e) NONE ⇒ peg_eval_list G (s, e) (s,[])) ∧
  (∀e s0 s1 s2 c cs.
     peg_eval G (s0, e) (SOME(s1,c)) ∧
     peg_eval_list G (s1, e) (s2,cs) ⇒
     peg_eval_list G (s0, e) (s2,c::cs))
End

Theorem peg_eval_strongind' =
  peg_eval_strongind
    |> SIMP_RULE (srw_ss()) [pairTheory.FORALL_PROD]
    |> Q.SPECL [`G`, `\es0 r. P1 (FST es0) (SND es0) r`,
                `\es0 sr. P2 (FST es0) (SND es0) (FST sr) (SND sr)`]
    |> SIMP_RULE (srw_ss()) []

open rich_listTheory
val peg_eval_suffix0 = prove(
  ``(∀s0 e sr. peg_eval G (s0,e) sr ⇒ ∀s r. sr = SOME (s,r) ⇒ IS_SUFFIX s0 s) ∧
    ∀s0 e s rl. peg_eval_list G (s0,e) (s,rl) ⇒ IS_SUFFIX s0 s``,
  HO_MATCH_MP_TAC peg_eval_strongind' THEN
  SRW_TAC [][IS_SUFFIX_compute, IS_PREFIX_APPEND3, IS_PREFIX_REFL] THEN
  METIS_TAC [IS_PREFIX_TRANS]);

(* Theorem 3.1 *)
val peg_eval_suffix = save_thm(
  "peg_eval_suffix",
  peg_eval_suffix0 |> SIMP_RULE (srw_ss() ++ DNF_ss) [])

(* Theorem 3.2 *)
val peg_deterministic = store_thm(
  "peg_deterministic",
  ``(∀s0 e sr. peg_eval G (s0,e) sr ⇒ ∀sr'. peg_eval G (s0,e) sr' ⇔ sr' = sr) ∧
    ∀s0 e s rl. peg_eval_list G (s0,e) (s,rl) ⇒
                ∀srl'. peg_eval_list G (s0,e) srl' ⇔ srl' = (s,rl)``,
  HO_MATCH_MP_TAC peg_eval_strongind' THEN SRW_TAC [][] THEN
  ONCE_REWRITE_TAC [peg_eval_cases] THEN SRW_TAC [][]);

(* Lemma 3.3 *)
val peg_badrpt = store_thm(
  "peg_badrpt",
  ``peg_eval G (s0,e) (SOME(s0,r)) ⇒ ∀r. ¬peg_eval G (s0, rpt e f) r``,
  strip_tac >> simp[Once peg_eval_cases] >> map_every qx_gen_tac [`s1`, `l`] >>
  disch_then (assume_tac o MATCH_MP (CONJUNCT2 peg_deterministic)) >>
  `peg_eval_list G (s0,e) (s1,r::l)`
    by METIS_TAC [last (peg_eval_rules |> SPEC_ALL |> CONJUNCTS)] >>
  pop_assum mp_tac >> simp[]);

Inductive peg0:
  (∀c. peg0 G (empty c)) ∧

  (* any *)
  (∀f. peggt0 G (any f)) ∧
  (∀f. pegfail G (any f)) ∧

  (* tok *)
  (∀t f. peggt0 G (tok t f)) ∧
  (∀t f. pegfail G (tok t f)) ∧

  (* rpt *)
  (∀e f. pegfail G e ⇒ peg0 G (rpt e f)) ∧
  (∀e f. peggt0 G e ⇒ peggt0 G (rpt e f)) ∧

  (* nt rules *)
  (∀n f. n ∈ FDOM G.rules ∧ peg0 G (G.rules ' n) ⇒
         peg0 G (nt n f)) ∧
  (∀n f. n ∈ FDOM G.rules ∧ peggt0 G (G.rules ' n) ⇒
         peggt0 G (nt n f)) ∧
  (∀n f. n ∈ FDOM G.rules ∧ pegfail G (G.rules ' n) ⇒
         pegfail G (nt n f)) ∧

  (* seq rules *)
  (∀e1 e2 f. pegfail G e1 ∨ (peg0 G e1 ∧ pegfail G e2) ∨
             (peggt0 G e1 ∧ pegfail G e2) ⇒
             pegfail G (seq e1 e2 f)) ∧
  (∀e1 e2 f. peggt0 G e1 ∧ (peg0 G e2 ∨ peggt0 G e2) ∨
             (peg0 G e1 ∨ peggt0 G e1) ∧ peggt0 G e2 ⇒
             peggt0 G (seq e1 e2 f)) ∧
  (∀e1 e2 f. peg0 G e1 ∧ peg0 G e2 ⇒ peg0 G (seq e1 e2 f)) ∧

  (* choice rules *)
  (∀e1 e2 f. peg0 G e1 ∨ (pegfail G e1 ∧ peg0 G e2) ⇒
             peg0 G (choice e1 e2 f)) ∧
  (∀e1 e2 f. pegfail G e1 ∧ pegfail G e2 ⇒ pegfail G (choice e1 e2 f)) ∧
  (∀e1 e2 f. peggt0 G e1 ∨ (pegfail G e1 ∧ peggt0 G e2) ⇒
             peggt0 G (choice e1 e2 f)) ∧

  (* not *)
  (∀e c. pegfail G e ⇒ peg0 G (not e c)) ∧
  (∀e c. peg0 G e ∨ peggt0 G e ⇒ pegfail G (not e c))
End

val peg_eval_suffix' = store_thm(
  "peg_eval_suffix'",
  ``peg_eval G (s0,e) (SOME(s,c)) ⇒
    s0 = s ∨ IS_SUFFIX s0 s ∧ LENGTH s < LENGTH s0``,
  strip_tac >> imp_res_tac peg_eval_suffix >> Cases_on `s0 = s` >- simp[] >>
  fs[IS_SUFFIX_compute] >>
  imp_res_tac IS_PREFIX_LENGTH >> fs[] >>
  qsuff_tac `LENGTH s ≠ LENGTH s0` >- (strip_tac >> decide_tac) >>
  strip_tac >>
  metis_tac [IS_PREFIX_LENGTH_ANTI, LENGTH_REVERSE, REVERSE_REVERSE]);

val peg_eval_list_suffix' = store_thm(
  "peg_eval_list_suffix'",
  ``peg_eval_list G (s0, e) (s,rl) ⇒
    s0 = s ∨ IS_SUFFIX s0 s ∧ LENGTH s < LENGTH s0``,
  strip_tac >> imp_res_tac peg_eval_suffix >> Cases_on `s0 = s` >- simp[] >>
  fs[IS_SUFFIX_compute] >> imp_res_tac IS_PREFIX_LENGTH >> fs[] >>
  qsuff_tac `LENGTH s ≠ LENGTH s0` >- (strip_tac >> decide_tac) >> strip_tac >>
  metis_tac [IS_PREFIX_LENGTH_ANTI, LENGTH_REVERSE, REVERSE_REVERSE]);


fun rule_match th = FIRST (List.mapPartial (total MATCH_MP_TAC)
                                           (th |> SPEC_ALL |> CONJUNCTS))

val lemma4_1a0 = prove(
  ``(∀s0 e r. peg_eval G (s0, e) r ⇒
              (∀c. r = SOME(s0,c) ⇒ peg0 G e) ∧
              (r = NONE ⇒ pegfail G e) ∧
              (∀s c. r = SOME(s,c) ∧ LENGTH s < LENGTH s0 ⇒ peggt0 G e)) ∧
    (∀s0 e s rl. peg_eval_list G (s0,e) (s,rl) ⇒
                 (s0 = s ⇒ pegfail G e) ∧
                 (LENGTH s < LENGTH s0 ⇒ peggt0 G e))``,
  ho_match_mp_tac peg_eval_strongind' >> simp[peg0_rules] >> rpt conj_tac
  >- (rpt strip_tac >> imp_res_tac peg_eval_suffix' >> fs[peg0_rules])
  >- (rpt strip_tac >> rule_match peg0_rules >>
      imp_res_tac peg_eval_suffix' >> fs[] >> rw[] >>
      full_simp_tac (srw_ss() ++ ARITH_ss) [])
  >- (rpt strip_tac >> rule_match peg0_rules >>
      imp_res_tac peg_eval_suffix' >> fs[] >> rw[] >>
      full_simp_tac (srw_ss() ++ ARITH_ss) []) >>
  rpt strip_tac
  >- (first_x_assum match_mp_tac >> rw[] >>
      imp_res_tac peg_eval_suffix >> fs[IS_SUFFIX_compute] >>
      imp_res_tac IS_PREFIX_LENGTH >> fs[] >>
      `LENGTH s = LENGTH s0'` by decide_tac >>
      metis_tac [IS_PREFIX_LENGTH_ANTI, LENGTH_REVERSE, REVERSE_REVERSE]) >>
  imp_res_tac peg_eval_suffix' >- rw[] >>
  imp_res_tac peg_eval_list_suffix' >- rw[] >>
  asm_simp_tac (srw_ss() ++ ARITH_ss) [])

val lemma4_1a = save_thm("lemma4_1a",lemma4_1a0 |> SIMP_RULE (srw_ss() ++ DNF_ss) [AND_IMP_INTRO])

Inductive wfpeg:
  (∀n f. n ∈ FDOM G.rules ∧ wfpeg G (G.rules ' n) ⇒ wfpeg G (nt n f)) ∧
  (∀c. wfpeg G (empty c)) ∧
  (∀f. wfpeg G (any f)) ∧
  (∀t f. wfpeg G (tok t f)) ∧
  (∀e c. wfpeg G e ⇒ wfpeg G (not e c)) ∧
  (∀e1 e2 f. wfpeg G e1 ∧ (peg0 G e1 ⇒ wfpeg G e2) ⇒
             wfpeg G (seq e1 e2 f)) ∧
  (∀e1 e2 f. wfpeg G e1 ∧ wfpeg G e2 ⇒ wfpeg G (choice e1 e2 f)) ∧
  (∀e f. wfpeg G e ∧ ¬peg0 G e ⇒ wfpeg G (rpt e f))
End

Definition subexprs_def[simp]:
  (subexprs (any f1) = { any f1 }) ∧
  (subexprs (empty c) = { empty c }) ∧
  (subexprs (tok t f2) = { tok t f2 }) ∧
  (subexprs (nt s f) = { nt s f }) ∧
  (subexprs (not e c) = not e c INSERT subexprs e) ∧
  (subexprs (seq e1 e2 f3) = seq e1 e2 f3 INSERT subexprs e1 ∪ subexprs e2) ∧
  (subexprs (choice e1 e2 f4) =
    choice e1 e2 f4 INSERT subexprs e1 ∪ subexprs e2) ∧
  (subexprs (rpt e f5) = rpt e f5 INSERT subexprs e)
End


val subexprs_included = store_thm(
  "subexprs_included",
  ``e ∈ subexprs e``,
  Induct_on `e` >> srw_tac[][subexprs_def] )

val Gexprs_def = Define`
  Gexprs G = BIGUNION (IMAGE subexprs (G.start INSERT FRANGE G.rules))
`

Theorem start_IN_Gexprs[simp]:
  G.start ∈ Gexprs G
Proof
  simp[Gexprs_def, subexprs_included]
QED

val wfG_def = Define`wfG G ⇔ ∀e. e ∈ Gexprs G ⇒ wfpeg G e`;

val IN_subexprs_TRANS = store_thm(
  "IN_subexprs_TRANS",
  ``∀a b c. a ∈ subexprs b ∧ b ∈ subexprs c ⇒ a ∈ subexprs c``,
  Induct_on `c` >> simp[] >> rpt strip_tac >> fs[] >> metis_tac[]);

val Gexprs_subexprs = store_thm(
  "Gexprs_subexprs",
  ``e ∈ Gexprs G ⇒ subexprs e ⊆ Gexprs G``,
  simp_tac (srw_ss() ++ DNF_ss) [Gexprs_def, pred_setTheory.SUBSET_DEF] >>
  strip_tac >> metis_tac [IN_subexprs_TRANS]);

val IN_Gexprs_E = store_thm(
  "IN_Gexprs_E",
  ``(not e c ∈ Gexprs G ⇒ e ∈ Gexprs G) ∧
    (seq e1 e2 f ∈ Gexprs G ⇒ e1 ∈ Gexprs G ∧ e2 ∈ Gexprs G) ∧
    (choice e1 e2 f2 ∈ Gexprs G ⇒ e1 ∈ Gexprs G ∧ e2 ∈ Gexprs G) ∧
    (rpt e f3 ∈ Gexprs G ⇒ e ∈ Gexprs G)``,
  rpt strip_tac >> imp_res_tac Gexprs_subexprs >> fs[] >>
  metis_tac [pred_setTheory.SUBSET_DEF, subexprs_included]);

val pair_CASES = pairTheory.pair_CASES
val option_CASES = optionTheory.option_nchotomy
val list_CASES = listTheory.list_CASES

val reducing_peg_eval_makes_list = prove(
  ``(∀s. LENGTH s < n ⇒ ∃r. peg_eval G (s, e) r) ∧ ¬peg0 G e ∧ LENGTH s0 < n ⇒
    ∃s' rl. peg_eval_list G (s0,e) (s',rl)``,
  strip_tac >> completeInduct_on `LENGTH s0` >> rw[] >>
  full_simp_tac (srw_ss() ++ DNF_ss ++ ARITH_ss) [] >>
  `peg_eval G (s0,e) NONE ∨ ∃s1 c. peg_eval G (s0,e) (SOME(s1,c))`
    by metis_tac [pair_CASES, option_CASES]
  >- metis_tac [peg_eval_rules] >>
  `s0 ≠ s1` by metis_tac [lemma4_1a] >>
  `LENGTH s1 < LENGTH s0` by metis_tac [peg_eval_suffix'] >>
  metis_tac [peg_eval_rules]);

val peg_eval_total = store_thm(
  "peg_eval_total",
  ``wfG G ⇒ ∀s e. e ∈ Gexprs G ⇒ ∃r. peg_eval G (s,e) r``,
  simp[wfG_def] >> strip_tac >> gen_tac >>
  completeInduct_on `LENGTH s` >>
  full_simp_tac (srw_ss() ++ DNF_ss) [] >> rpt strip_tac >>
  `wfpeg G e` by metis_tac[] >>
  Q.UNDISCH_THEN `e ∈ Gexprs G` mp_tac >>
  pop_assum mp_tac >> qid_spec_tac `e` >>
  Induct_on `wfpeg` >> rw[]
  >- ((* nt *)
      qsuff_tac `G.rules ' n ∈ Gexprs G`
      >- metis_tac [peg_eval_rules, option_CASES, pair_CASES] >>
      asm_simp_tac (srw_ss() ++ DNF_ss) [Gexprs_def, FRANGE_DEF] >>
      metis_tac [subexprs_included])
  >- (* empty *) metis_tac [peg_eval_rules]
  >- (* any *) metis_tac [peg_eval_rules, list_CASES]
  >- (* tok *) metis_tac [peg_eval_rules, list_CASES]
  >- (* not *) metis_tac [peg_eval_rules, optionTheory.option_nchotomy,
                          IN_Gexprs_E]
  >- ((* seq *) Q.MATCH_ASSUM_ABBREV_TAC `seq e1 e2 f ∈ Gexprs G` >>
      markerLib.RM_ALL_ABBREVS_TAC >>
      `e1 ∈ Gexprs G` by imp_res_tac IN_Gexprs_E >>
      `peg_eval G (s,e1) NONE ∨ ∃s' c. peg_eval G (s,e1) (SOME(s',c))`
        by metis_tac[option_CASES, pair_CASES]
      >- metis_tac [peg_eval_rules] >>
      Cases_on `s' = s`
      >- (`peg0 G e1` by metis_tac [lemma4_1a] >>
          `e2 ∈ Gexprs G` by imp_res_tac IN_Gexprs_E >>
          metis_tac [peg_eval_rules, option_CASES, pair_CASES]) >>
      `LENGTH s' < LENGTH s` by metis_tac [peg_eval_suffix'] >>
      `∃r'. peg_eval G (s',e2) r'` by metis_tac [IN_Gexprs_E] >>
      metis_tac [option_CASES, pair_CASES, peg_eval_rules])
  >- (* choice *)
     metis_tac [peg_eval_rules, option_CASES, IN_Gexprs_E, pair_CASES] >>
  (* rpt *) imp_res_tac IN_Gexprs_E >>
  `peg_eval G (s, e) NONE ∨ ∃s' c. peg_eval G (s,e) (SOME (s',c))`
    by metis_tac [option_CASES, pair_CASES]
  >- (`peg_eval_list G (s,e) (s,[])` by metis_tac [peg_eval_rules] >>
      metis_tac [peg_eval_rules]) >>
  `s' ≠ s` by metis_tac [lemma4_1a] >>
  `LENGTH s' < LENGTH s` by metis_tac [peg_eval_suffix'] >>
  metis_tac [peg_eval_rules, reducing_peg_eval_makes_list])

(* derived and useful PEG forms *)
val pegf_def = Define`pegf sym f = seq sym (empty ARB) (λl1 l2. f l1)`

val ignoreL_def = Define`
  ignoreL s1 s2 = seq s1 s2 (λa b. b)
`;
val _ = set_mapped_fixity{fixity = Infixl 500, term_name = "ignoreL",
                          tok = "~>"}

val ignoreR_def = Define`
  ignoreR s1 s2 = seq s1 s2 (λa b. a)
`;
val _ = set_mapped_fixity{fixity = Infixl 500, term_name = "ignoreR",
                          tok = "<~"}

val choicel_def = Define`
  (choicel [] = not (empty ARB) ARB) ∧
  (choicel (h::t) = choice h (choicel t) (λs. sum_CASE s I I))
`;

val checkAhead_def = Define`
  checkAhead P s = not (not (tok P ARB) ARB) ARB ~> s
`;

val peg_eval_seq_SOME = store_thm(
  "peg_eval_seq_SOME",
  ``peg_eval G (i0, seq s1 s2 f) (SOME (i,r)) ⇔
    ∃i1 r1 r2. peg_eval G (i0, s1) (SOME (i1,r1)) ∧
               peg_eval G (i1, s2) (SOME (i,r2)) ∧ (r = f r1 r2)``,
  simp[Once peg_eval_cases] >> metis_tac[]);

val peg_eval_seq_NONE = store_thm(
  "peg_eval_seq_NONE",
  ``peg_eval G (i0, seq s1 s2 f) NONE ⇔
      peg_eval G (i0, s1) NONE ∨
      ∃i r. peg_eval G (i0,s1) (SOME(i,r)) ∧
            peg_eval G (i,s2) NONE``,
  simp[Once peg_eval_cases] >> metis_tac[]);

val peg_eval_tok_NONE = save_thm(
  "peg_eval_tok_NONE",
  ``peg_eval G (i, tok P f) NONE``
    |> SIMP_CONV (srw_ss()) [Once peg_eval_cases])

val peg_eval_tok_SOME = store_thm(
  "peg_eval_tok_SOME",
  ``peg_eval G (i0, tok P f) (SOME (i,r)) ⇔ ∃h. P (FST h) ∧ i0 = h::i ∧ r = f h``,
  simp[Once peg_eval_cases] >> metis_tac[]);

val peg_eval_empty = store_thm(
  "peg_eval_empty[simp]",
  ``peg_eval G (i, empty r) x ⇔ (x = SOME(i,r))``,
  simp[Once peg_eval_cases])

val peg_eval_NT_SOME = store_thm(
  "peg_eval_NT_SOME",
  ``peg_eval G (i0,nt N f) (SOME(i,r)) ⇔
      ∃r0. r = f r0 ∧ N ∈ FDOM G.rules ∧
           peg_eval G (i0,G.rules ' N) (SOME(i,r0))``,
  simp[Once peg_eval_cases]);

val peg_eval_choice = store_thm(
  "peg_eval_choice",
  ``∀x.
     peg_eval G (i0, choice s1 s2 f) x ⇔
      (∃i r. peg_eval G (i0, s1) (SOME(i, r)) ∧ x = SOME(i, f (INL r))) ∨
      (∃i r. peg_eval G (i0, s1) NONE ∧
             peg_eval G (i0, s2) (SOME(i, r)) ∧ x = SOME(i, f (INR r))) ∨
      peg_eval G (i0, s1) NONE ∧ peg_eval G (i0,s2) NONE ∧ (x = NONE)``,
  simp[Once peg_eval_cases, SimpLHS] >>
  simp[optionTheory.FORALL_OPTION, pairTheory.FORALL_PROD] >> metis_tac[]);

val peg_eval_choicel_NIL = store_thm(
  "peg_eval_choicel_NIL[simp]",
  ``peg_eval G (i0, choicel []) x = (x = NONE)``,
  simp[choicel_def, Once peg_eval_cases]);

val peg_eval_choicel_CONS = store_thm(
  "peg_eval_choicel_CONS",
  ``∀x. peg_eval G (i0, choicel (h::t)) x ⇔
          peg_eval G (i0, h) x ∧ x <> NONE ∨
          peg_eval G (i0,h) NONE ∧ peg_eval G (i0, choicel t) x``,
  simp[choicel_def, SimpLHS, Once peg_eval_cases] >>
  simp[pairTheory.FORALL_PROD, optionTheory.FORALL_OPTION]);

val peg_eval_rpt = store_thm(
  "peg_eval_rpt",
  ``peg_eval G (i0, rpt s f) x ⇔
      ∃i l. peg_eval_list G (i0,s) (i,l) ∧ x = SOME(i,f l)``,
  simp[Once peg_eval_cases, SimpLHS] >> metis_tac[]);

val peg_eval_list = Q.store_thm(
  "peg_eval_list",
  `peg_eval_list G (i0, e) (i, r) ⇔
     peg_eval G (i0, e) NONE ∧ i = i0 ∧ r = [] ∨
     (∃i1 rh rt.
        peg_eval G (i0, e) (SOME (i1, rh)) ∧
        peg_eval_list G (i1, e) (i, rt) ∧ r = rh::rt)`,
  simp[Once peg_eval_cases, SimpLHS] >> metis_tac[]);

val pegfail_empty = store_thm(
  "pegfail_empty[simp]",
  ``pegfail G (empty r) = F``,
  simp[Once peg0_cases]);

val peg0_empty = store_thm(
  "peg0_empty[simp]",
  ``peg0 G (empty r) = T``,
  simp[Once peg0_cases]);

val peg0_not = store_thm(
  "peg0_not[simp]",
  ``peg0 G (not s r) ⇔ pegfail G s``,
  simp[Once peg0_cases, SimpLHS]);

val peg0_choice = store_thm(
  "peg0_choice[simp]",
  ``peg0 G (choice s1 s2 f) ⇔ peg0 G s1 ∨ pegfail G s1 ∧ peg0 G s2``,
  simp[Once peg0_cases, SimpLHS]);

val peg0_choicel = store_thm(
  "peg0_choicel[simp]",
  ``(peg0 G (choicel []) = F) ∧
    (peg0 G (choicel (h::t)) ⇔ peg0 G h ∨ pegfail G h ∧ peg0 G (choicel t))``,
  simp[choicel_def])

val peg0_seq = store_thm(
  "peg0_seq[simp]",
  ``peg0 G (seq s1 s2 f) ⇔ peg0 G s1 ∧ peg0 G s2``,
  simp[Once peg0_cases, SimpLHS])

val peg0_tok = store_thm(
  "peg0_tok[simp]",
  ``peg0 G (tok P f) = F``,
  simp[Once peg0_cases])

val peg0_pegf = store_thm(
  "peg0_pegf[simp]",
  ``peg0 G (pegf s f) = peg0 G s``,
  simp[pegf_def])

val _ = export_theory()
