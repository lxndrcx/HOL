(* Copyright (c) 2010-2011 Tjark Weber. All rights reserved. *)

(* Entry point into HolQbfLib. *)

structure HolQbfLib :> HolQbfLib = struct


 fun get_certificate t =
  let
    val path = FileSys.tmpName ()
    val cert_path = path ^ ".qbc" (* the file name is hard-wired in Squolem *)
    fun dowork () =
        let
          val dict = QDimacs.write_qdimacs_file path t
          (* the actual system call to Squolem *)
          val cmd = "squolem2 -c " ^ path ^ " >/dev/null 2>&1"
          val _ = if !QbfTrace.trace > 1 then
                    Feedback.HOL_MESG ("HolQbfLib: calling external command '" ^
                                       cmd ^ "'")
                  else ()
          val _ = Systeml.system_ps cmd
          val cert = QbfCertificate.read_certificate_file cert_path
        in
          (dict,cert)
        end
    fun finish () =
    (* delete temporary files *)
        if !QbfTrace.trace < 4 then
          List.app (fn path => OS.FileSys.remove path handle SysErr _ => ())
                   [path, cert_path]
        else ()
  in
    Portable.finally finish dowork ()
  end

  (* 'prove' can prove valid QBFs in prenex form by validating a
     certificate of validity generated by the QBF solver Squolem.
     Returns a theorem "|- t". Fails if Squolem does not generate a
     certificate of validity. *)
  fun prove t =
  let
    val (dict, cert) = get_certificate t
  in
    case cert of
      QbfCertificate.VALID _ => QbfCertificate.check t dict cert
    | _ =>
      raise Feedback.mk_HOL_ERR "HolQbfLib" "prove" "certificate says invalid"
  end

  (* 'disprove' can disprove invalid QBFs in prenex form by validating
     a certificate of invalidity generated by the QBF solver Squolem.
     Returns a theorem "t |- F". Fails if Squolem does not generate a
     certificate of invalidity. *)
  fun disprove t =
  let
    val (dict, cert) = get_certificate t
  in
    case cert of
      QbfCertificate.INVALID _ =>
      QbfCertificate.check t dict cert
    | _ =>
      raise Feedback.mk_HOL_ERR "HolQbfLib" "disprove" "certificate says valid"
  end

  (* 'decide_prenex' can prove valid and disprove invalid QBFs in
     prenex form by validating a certificate (of validity or
     invalidity, respectively) generated by the QBF solver
     Squolem. Returns a theorem "|- t" or "t |- F". Fails if Squolem
     does not generate a certificate. *)
  fun decide_prenex t =
  let
    val (dict, cert) = get_certificate t
  in
    QbfCertificate.check t dict cert
  end

  (* Similar to 'decide_prenex' but accepts QBFs with fewer form
     restrictions. In case of free variables in an invalid formula,
     they will be universally quantified in the resulting theorem's
     assumptions. *)
  fun decide t =
  let
    open Thm Drule boolSyntax boolLib
    val fvs = Term.free_vars t
    val t = list_mk_forall (fvs,t)
    val tt = QbfConv.qbf_prenex_conv t
    val t' = rhs (concl tt)
    in if Teq t' then SPECL fvs (EQ_MP (SYM tt) boolTheory.TRUTH) else
       if Feq t' then EQ_MP tt (ASSUME t) else let
    val (dict, cert) = get_certificate t'
    val th = QbfCertificate.check t' dict cert
  in case cert of
    QbfCertificate.INVALID _ =>
      UNDISCH (SUBS_OCCS [([1],SYM tt)] (DISCH t' th))
  | QbfCertificate.VALID _ =>
      SPECL fvs (EQ_MP (SYM tt) th)
  end end

  fun set_sat_prove s = QbfCertificate.sat_prove := s

end
