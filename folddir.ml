open Util
open Unix

exception Prune

module type IGNORE =
sig
  type t
  val init : string -> t
  val update : t -> string -> t
  val is_ignored : ?verbose:bool -> t -> string -> bool
end

let join a b = if a <> "" && b <> "" then a ^ "/" ^ b else a ^ b

module type S =
sig
  type ignore_info
  val fold_directory : ?verbose:bool -> ('a -> string -> 'a) -> 'a -> string ->
                       ?ign_info:ignore_info -> string -> 'a
end

module Make(M : IGNORE) : S with type ignore_info = M.t =
struct
  type ignore_info = M.t

  let rec fold_directory ?(verbose=false) f acc base ?(ign_info = M.init base) path =
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
                     | n when M.is_ignored ~verbose ign_info n -> ()
                     | n ->
                         try
                           let n = join path n in
                             acc := f !acc n;
                             if (stat (join base n)).st_kind = S_DIR then
                               acc := fold_directory f ~ign_info !acc base n
                         with Prune -> ()
               done;
               assert false
             with End_of_file -> ());
        !acc
      with Unix.Unix_error _ -> !acc
end

module Ignore_none : IGNORE =
struct
  type t = unit
  let init _ = ()
  let update () _ = ()
  let is_ignored ?verbose () _ = false
end

module Gitignore : IGNORE =
struct
  open Printf

  type glob_type = Accept | Deny
  type glob = glob_type * string
  type t = { base : string; levels : (string * glob list) list }

  external fnmatch : bool -> string -> string -> bool = "perform_fnmatch"

  let glob_of_string s = match s.[0] with
      '!' -> (Accept, String.sub s 1 (String.length s - 1))
    | _ -> (Deny, s)

  let collect_globs l =
    let rec aux acc = function
        [] -> acc
      | line::tl ->
          if line = "" || line.[0] = '#' then aux acc tl
          else aux (glob_of_string line :: acc) tl
    in aux [] l

  let read_gitignore path =
    try
      collect_globs
        (do_finally (open_in (join path ".gitignore")) close_in
           (fun is ->
              let l = ref [] in
                try
                  while true do
                    l := input_line is :: !l
                  done;
                  assert false
                with End_of_file -> !l) )
    with Sys_error _ -> []

  let init path = { base = path; levels = [] }

  let update t subdir =
    let base = join t.base subdir in
    let globs = read_gitignore base in
      { base = base; levels = (subdir, globs) :: t.levels }

  let glob_matches glob name =
    if String.contains glob '/' then
      fnmatch true glob name
    else
      fnmatch false glob (Filename.basename name)

  let is_ignored ?(verbose=false) t fname =
    let rec aux fname = function
      | [] -> false
      | (dname, globs)::tl ->
        let ign = List.fold_left
          (fun s (ty, glob) ->
            if glob_matches glob fname then
              (match ty with
                  Accept ->
                    if verbose then printf "ACCEPT %S (matched %S)\n" fname glob;
                    Some false
                | Deny ->
                    if verbose then printf "DENY %S (matched %S)\n" fname glob;
                    Some true)
            else s)
          None globs
        in match ign with
             Some b -> b
           | None -> aux (join dname fname) tl
    in aux fname t.levels
end
