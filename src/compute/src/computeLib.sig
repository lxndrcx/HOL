signature computeLib =
sig

  local open HolKernel Abbrev in

  type comp_rws = clauses.comp_rws

  val new_rws : unit -> comp_rws
  val from_list : thm list -> comp_rws
  val add_thms : thm list -> comp_rws -> unit
  val add_conv : term * int * conv -> comp_rws -> unit
  val set_skip : comp_rws -> string -> int option -> unit

  val CBV_CONV      : comp_rws -> conv
  val WEAK_CBV_CONV : comp_rws -> conv

  (* thm preprocessors of rules.sml *)
  val lazyfy_thm    : thm -> thm
  val strictify_thm : thm -> thm

  end

end;
