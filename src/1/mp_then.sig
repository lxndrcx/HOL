signature mp_then =
sig

  include Abbrev

  datatype match_position
    = Any
    | Pat of term quotation
    | Pos of (term list -> term)
    | Concl

  val PART_MATCH' : (term -> term) -> thm -> term -> thm
  val mp_then : match_position -> thm_tactic -> thm -> thm -> tactic

end
