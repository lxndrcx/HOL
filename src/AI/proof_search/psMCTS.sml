(* ========================================================================= *)
(* FILE          : psMCTS.sml                                                *)
(* DESCRIPTION   : MCTS algorithm                                            *)
(* AUTHOR        : (c) Thibault Gauthier, Czech Technical University         *)
(* DATE          : 2018                                                      *)
(* ========================================================================= *)

structure psMCTS :> psMCTS =
struct

open HolKernel Abbrev boolLib aiLib

val ERR = mk_HOL_ERR "psMCTS"

(* -------------------------------------------------------------------------
   Global fixed parameters
   ------------------------------------------------------------------------- *)

val exploration_coeff = 1.0
val ignorestatus_flag = ref false

(* -------------------------------------------------------------------------
   Timers
   ------------------------------------------------------------------------- *)

val backuptime = ref 0.0
val selecttime = ref 0.0
val fevalpolitime = ref 0.0
val statusoftime  = ref 0.0
val applymovetime = ref 0.0

fun backup_timer f x = total_time backuptime f x
fun select_timer f x = total_time selecttime f x
fun fevalpoli_timer f x  = total_time fevalpolitime f x
fun status_of_timer f x  = total_time statusoftime f x
fun apply_move_timer f x = total_time applymovetime f x

fun init_timers () =
  (
  backuptime    := 0.0;
  selecttime    := 0.0;
  fevalpolitime := 0.0;
  statusoftime  := 0.0;
  applymovetime := 0.0
  )

fun string_of_timers tim =
  String.concatWith "\n"
    [
    "  backup time     : " ^ Real.toString (!backuptime),
    "  select time     : " ^ Real.toString (!selecttime),
    "  fevalpoli time  : " ^ Real.toString (!fevalpolitime),
    "  status_of time  : " ^ Real.toString (!statusoftime),
    "  apply_move time : " ^ Real.toString (!applymovetime)
    ]

(* -------------------------------------------------------------------------
   Debug
   ------------------------------------------------------------------------- *)

fun string_of_id id = String.concatWith " " (map int_to_string id)

fun string_of_poli poli =
  let fun f ((s,r),i) =
    s ^ " " ^ Real.toString (approx 2 r) ^ " " ^ int_to_string i
  in
    String.concatWith "\n  " (map f poli)
  end

(* -------------------------------------------------------------------------
   Node
   ------------------------------------------------------------------------- *)

datatype status = Undecided | Win | Lose

fun string_of_status status = case status of
    Undecided => "Undecided"
  | Lose      => "Lose"
  | Win       => "Win"

type 'a sit    = bool * 'a
type 'b choice = (('b * real) * int list)

type ('a,'b) node =
{
  pol    : 'b choice list,
  sit    : 'a sit,
  sum    : real,
  vis    : real,
  status : status
}

type ('a,'b) tree = (int list, ('a,'b) node) Redblackmap.dict

fun genealogy id =
  if null id then [] else id :: genealogy (tl id)

fun access_child tree (_,cid) =
  if !ignorestatus_flag then true else
    ((case #status (dfind cid tree) of Undecided => true | _ => false)
    handle NotFound => true)

fun access_poli tree pol = filter (access_child tree) pol

(* -------------------------------------------------------------------------
   Backup: not efficient but conceptually simple
   ------------------------------------------------------------------------- *)

fun quant_status quant status tree pol =
  let
    val cidl    = map snd pol
    fun is_status cid = #status (dfind cid tree) = status
                        handle NotFound => false
  in
    quant is_status cidl
  end

fun all_win tree pol     = quant_status all Win tree pol
fun all_lose tree pol    = quant_status all Lose tree pol
fun exists_win tree pol  = quant_status exists Win tree pol
fun exists_lose tree pol = quant_status exists Lose tree pol

fun update_node decay tree eval {pol,sit,sum,vis,status} =
  let
    val newstatus =
      if status = Undecided then
        if fst sit then
          (if exists_win tree pol then Win else
           if all_lose tree pol   then Lose else
           Undecided)
        else
          (if all_win tree pol     then Win else
           if exists_lose tree pol then Lose else
           Undecided)
      else status
  in
    {pol=pol, sit=sit, sum=sum+eval, vis=vis+1.0, status=newstatus}
  end

fun backup decay tree (id,eval) =
  let
    val node1   = dfind id tree
    val node2   = update_node decay tree eval node1
    val newtree = dadd id node2 tree
  in
    case tl id of
      []  => newtree
    | pid => backup decay newtree (pid, decay * eval)
  end

(* --------------------------------------------------------------------------
   Node creation
   ------------------------------------------------------------------------- *)

fun node_create_backup decay fevalpoli status_of tree (id,sit) =
  let
    fun wrap_poli poli = let fun f i x = (x, i :: id) in mapi f poli end
    val ((eval,poli),status) =
      case status_of sit of
        Win       => ((1.0,[]),Win)
      | Lose      => ((0.0,[]),Lose)
      | Undecided => (fevalpoli sit,Undecided)
    val node =
      {pol=wrap_poli poli, sit=sit, sum=0.0, vis=0.0, status=status}
    val tree1 = dadd id node tree
    val tree2 = backup_timer (backup decay tree1) (id,eval)
  in
    tree2
  end

(* -------------------------------------------------------------------------
   Value of a choice
   ------------------------------------------------------------------------- *)

fun value_choice player tree vtot ((move,polv),cid) =
  let
    val (sum,vis) =
      let val child = dfind cid tree in ((#sum child),(#vis child)) end
      handle NotFound => (0.0,0.0)
    val exploitation = (if player then sum else vis - sum) / (vis + 1.0)
    val exploration  = (polv * Math.sqrt vtot) / (vis + 1.0)
  in
    exploitation + exploration_coeff * exploration
  end

(* -------------------------------------------------------------------------
   Selection of a node to extend by traversing the tree
   ------------------------------------------------------------------------- *)

datatype ('a,'b) select =
  TreeUpdate of ('a,'b) tree | NodeSelect of (int list * int list)

fun select_child decay tree id =
  let
    val node  = dfind id tree handle NotFound => raise ERR "select_child" ""
    val pol   = filter (access_child tree) (#pol node)
  in
    if null pol then
      case #status (dfind id tree) of
          Undecided => raise ERR "select_child" ""
        | Win => TreeUpdate (backup decay tree (id,1.0))
        | Lose => TreeUpdate (backup decay tree (id,0.0))
    else
      let
        val player  = fst (#sit node)
        val l1      = map_assoc (value_choice player tree (#vis node)) pol
        val l2      = dict_sort compare_rmax l1
        val choice  = fst (hd l2)
        val cid     = snd choice
      in
        if not (dmem cid tree)
        then NodeSelect (id,cid)
        else select_child decay tree cid
      end
  end

(* -------------------------------------------------------------------------
   Expansion + creation + backup
   ------------------------------------------------------------------------- *)

fun find_move pol cid =
  let val r = valOf (List.find (fn (_,x) => x = cid) pol) in
    fst (fst r)
  end
  handle Option => raise ERR "find_move" ""

fun expand decay fevalpoli status_of apply_move tree (id,cid) =
  let
    val node = dfind id tree
    val sit1 = #sit node
    val move = find_move (#pol node) cid
    val sit2 = apply_move move sit1
  in
    node_create_backup decay fevalpoli status_of tree (cid,sit2)
  end

(* -------------------------------------------------------------------------
   MCTS
   ------------------------------------------------------------------------- *)

fun starttree_of decay fevalpoli status_of startsit =
  let val empty_tree = dempty (list_compare Int.compare) in
    node_create_backup decay fevalpoli status_of empty_tree ([0],startsit)
  end

fun mcts (nsim,decay) fevalpoli status_of apply_move starttree =
  let
    val fevalpoli_timed = fevalpoli_timer fevalpoli
    val status_of_timed = status_of_timer status_of
    val apply_move_timed = apply_move_timer apply_move
    fun loop tree =
      if dlength tree > nsim orelse
         #status (dfind [0] tree) <> Undecided then tree else
      let
        val selecto = select_timer (select_child decay tree) [0]
        val newtree  = case selecto of
            TreeUpdate tree_upd => tree_upd
          | NodeSelect (id,cid) => expand decay
          fevalpoli_timed status_of_timed apply_move_timed tree (id,cid)
      in
        loop newtree
      end
  in
    loop starttree
  end

(* -------------------------------------------------------------------------
   Changing the root of the tree to an arbitrary node. Allow reuse of
   the trees during bigsteps.
   ------------------------------------------------------------------------- *)

fun remove_prefix prefix l = case (prefix,l) of
    ([],_) => l
  | (_,[]) => raise ERR "remove_prefix" ""
  | (a1 :: m1, a2 :: m2) =>
    if a1 = a2 then remove_prefix m1 m2 else raise ERR "remove_prefix" ""

fun remove_suffix_add0 suffix l =
  rev (0 :: (remove_prefix (rev suffix) (rev l)))

fun cut_tree tree suffix =
  let
    val l0 = dlist tree
    fun change_entry (id,{pol,sit,sum,vis,status}) =
      let
        fun f x = remove_suffix_add0 suffix x
        val newid = f id
        val newpol = map_snd f pol
      in
        (newid, {pol=newpol, sit=sit, sum=sum, vis=vis, status=status})
      end
    val l1 = mapfilter change_entry l0
  in
    dnew (list_compare Int.compare) l1
  end

(* -------------------------------------------------------------------------
   Statistics
   ------------------------------------------------------------------------- *)

datatype wintree = Wleaf of int list | Wnode of (int list * wintree list)

fun wtree_of tree id =
  let
    val node  = dfind id tree
    val cidl0 = map snd (#pol node)
    fun is_win cid =
      (#status (dfind cid tree) = Win handle NotFound => false)
    val cidl1 = filter is_win cidl0
  in
    if null cidl1
    then Wleaf id
      else Wnode (id, map (wtree_of tree) cidl1)
  end

fun list_imax l = case l of
    [] => raise ERR "list_imax" ""
  | [a] => a
  | a :: m => Int.max (a, list_imax m)

fun depth_of_wtree wtree = case wtree of
    Wleaf _ => 1
  | Wnode (_,treel) => list_imax (map depth_of_wtree treel) + 1

fun best_child tree id =
  let
    val node  = dfind id tree
    val cidl0 = map snd (#pol node)
    fun visit_of_child cid =
      SOME (cid, #vis (dfind cid tree))
      handle NotFound => NONE
    val cidl1 = List.mapPartial visit_of_child cidl0
  in
    if null cidl1
    then NONE
    else SOME (fst (hd (dict_sort compare_rmax cidl1)))
  end

fun node_variation tree id =
  if not (dmem id tree) then [] else
  (
  case best_child tree id of
    NONE => []
  | SOME cid => cid :: node_variation tree cid
  )

fun root_variation tree = node_variation tree [0]

(* -------------------------------------------------------------------------
   Creating the distribution
   ------------------------------------------------------------------------- *)

fun move_win tree cid = #status (dfind cid tree) = Win
fun move_lose tree cid = #status (dfind cid tree) = Lose

fun print_distrib l =
  print_endline
    ("  " ^ String.concatWith " " (map (Real.toString o approx 4 o snd) l))

(* Player1 *)
fun p1_distrib tree cidl =
  if exists (move_win tree) cidl then
    map_assoc (fn x => if move_win tree x then SOME 1.0 else NONE) cidl
  else if all (move_lose tree) cidl then
    map_assoc (fn x => SOME (#vis (dfind x tree))) cidl
  else
    map_assoc (fn x => if move_lose tree x
      then NONE else SOME (#vis (dfind x tree))) cidl

(* Player 2 *)
fun p2_distrib tree cidl =
  if exists (move_lose tree) cidl then
    map_assoc (fn x => if move_lose tree x then SOME 1.0 else NONE) cidl
  else if all (move_win tree) cidl then
    map_assoc (fn x => SOME (#vis (dfind x tree))) cidl
  else
    map_assoc (fn x => if move_win tree x
      then NONE else SOME (#vis (dfind x tree))) cidl

(* Wrap with innaccessible *)
fun inac_distrib f tree cidl =
  let
    val cidl' = filter (fn x => dmem x tree) cidl
    val dis   = f tree cidl'
    val d     = dnew (list_compare Int.compare) dis
  in
    map_assoc (fn x => (dfind x d handle NotFound => NONE)) cidl
  end

fun make_distrib tree id =
  let
    val node = dfind id tree
    val cidl = map snd (#pol node)
  in
    if fst (#sit node)
    then inac_distrib p1_distrib tree cidl
    else inac_distrib p2_distrib tree cidl
  end

(* -------------------------------------------------------------------------
   Rescaling the distribution for the training examples
   ------------------------------------------------------------------------- *)

fun swap (a,b) = (b,a)

fun move_of_cid node cid =
  let val pol = #pol node in
    fst (assoc cid (map swap pol))
  end

fun poli_example tree id =
  let
    val dis0 = make_distrib tree id
    val dis1 = map (fn (_,x) => if isSome x then valOf x else 0.0) dis0
    val tot = sum_real dis1
  in
    if tot < 0.5 then NONE else SOME (map (fn x => x / tot) dis1)
  end

fun eval_example tree id =
  let val node = dfind id tree in #sum node / #vis node end

(* -------------------------------------------------------------------------
   Big step selection
   ------------------------------------------------------------------------- *)

fun select_bigstep tree id =
  let
    val node = dfind id tree
    val _    = print_distrib (map fst (#pol node))
    val dis0 = make_distrib tree id
    val disstats = map_snd (fn x => if isSome x then valOf x else 0.0) dis0
    val _    = print_distrib disstats
    val dis1 = mapfilter (fn (a,b) => (a, valOf b)) dis0
    val tot  = sum_real (map snd dis1)
  in
    if tot < 0.5
    then (print_endline "  This is the END."; NONE)
    else SOME (select_in_distrib dis1)
  end


end (* struct *)
