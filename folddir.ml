open Util
open Unix

module type IGNORE =
sig
  type t
  val init : string -> t
  val update : t -> string -> t
  val is_ignored : t -> string -> bool
end

let join a b = if a <> "" && b <> "" then a ^ "/" ^ b else a ^ b

module type S =
sig
  type ignore_info
  val fold_directory : ('a -> string -> 'a) -> 'a -> string ->
                       ?ign_info:ignore_info -> string -> 'a
end

module Make(M : IGNORE) : S with type ignore_info = M.t =
struct
  type ignore_info = M.t

  let rec fold_directory f acc base ?(ign_info = M.init base) path =
    let acc = ref acc in
    let ign_info = M.update ign_info path in
    let dir = join base path in
      try
        do_finally (opendir dir) closedir
          (fun d ->
             try
               while true do
                 match readdir d with
                     "." | ".." | ".git" -> ()
                     | n when M.is_ignored ign_info n -> ()
                     | n -> let n = join path n in
                         acc := f !acc n;
                         if (stat (join base n)).st_kind = S_DIR then
                           acc := fold_directory f ~ign_info !acc base n
               done;
               assert false
             with End_of_file -> ());
        !acc
      with Unix.Unix_error _ -> !acc
end
