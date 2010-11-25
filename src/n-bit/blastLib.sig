signature blastLib =
sig
    include Abbrev

    val BIT_BLAST_CONV  : conv

    val BBLAST_CONV     : conv
    val BBLAST_PROVE    : conv
    val BBLAST_RULE     : rule
    val BBLAST_TAC      : tactic
    val FULL_BBLAST_TAC : tactic

end
