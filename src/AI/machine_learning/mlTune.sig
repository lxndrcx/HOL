signature mlTune =
sig

  include Abbrev

  type schedule = mlNeuralNetwork.schedule
  type dhex = mlTreeNeuralNetwork.dhex
  type dhtnn = mlTreeNeuralNetwork.dhtnn
  type dhtnn_param = mlTreeNeuralNetwork.dhtnn_param

  (* parameters *)
  type ml_param =
    {dim: int, nepoch: int, batchsize: int, learningrate: real, nlayer: int}

  val grid_param : int list * int list * int list * int list * int list ->
    ml_param list

  type set_param =
    (int * int) *
    ((term * real list) list * (term * real list) list * (term * int) list)

  (* training function *)
  val train_tnn_param : set_param -> ml_param -> (real * real * real)

  (* external parallelization *)
  val extspec : (set_param, ml_param, real * real * real) smlParallel.extspec

  (* statistics *)
  val write_summary :
    string -> (ml_param * (real * real * real )) list -> unit

  (* training multiple dhtnn architectures *)
  val traindhtnn_extspec :
    (unit, (dhex * schedule * dhtnn_param), dhtnn) smlParallel.extspec

end
