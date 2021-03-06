signature Streams =
sig
   datatype 'a stream = Stream of 'a * (unit -> 'a stream)
   exception end_of_stream
   val empty_stream : unit -> 'a stream
   val stream_map : ('a -> 'b) -> (unit -> 'a stream) -> (unit -> 'b stream)
   val stream_append : (unit -> 'a stream) ->
                       (unit -> 'a stream) ->
                       (unit -> 'a stream)
   val stream_append_list : (unit -> 'a stream) list -> (unit -> 'a stream)
   val stream_flat : (unit -> (unit -> 'a stream) stream) -> unit -> 'a stream
   val permutations : 'a list -> unit -> 'a list stream
end
