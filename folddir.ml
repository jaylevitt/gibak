open Util
open Unix

module type IGNORE =
sig
  type t
  val init : string -> t
  val update : t -> base:string -> path:string -> t
  val is_ignored : ?debug:bool -> t -> string -> bool
end

let join a b = if a <> "" && b <> "" then a ^ "/" ^ b else a ^ b

type 'a fold_acc = Continue of 'a | Prune of 'a

module type S =
sig
  type ignore_info
  val fold_directory :
    ?debug:bool -> ('a -> string -> Unix.stats -> 'a fold_acc) -> 'a ->
    string -> ?ign_info:ignore_info -> string -> 'a
end

module Make(M : IGNORE) : S with type ignore_info = M.t =
struct
  type ignore_info = M.t

  let rec fold_directory ?(debug=false) f acc base ?(ign_info = M.init base) path =
    let acc = ref acc in
    let ign_info = M.update ign_info ~base ~path in
    let dir = join base path in
      try
        do_finally (opendir dir) closedir
          (fun d ->
             try
               while true do
                 match readdir d with
                     "." | ".." -> ()
                     | n when M.is_ignored ~debug ign_info n -> ()
                     | n ->
                         let n = join path n in
                         let stat = lstat (join base n) in
                           match f !acc n stat with
                             | Continue x ->
                                 acc := x;
                                 if stat.st_kind = S_DIR then
                                   acc := fold_directory ~debug f ~ign_info
                                            !acc base n
                             | Prune x -> acc := x
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
  let update () ~base ~path = ()
  let is_ignored ?debug () _ = false
end

module Gitignore : IGNORE =
struct
  open Printf

  type glob_type = Accept | Deny
  (* Simple: no wildcards, no slash
   * Simple_local: leading slash, otherwise no slashes, no wildcards
   * Endswith: *.whatever, no slashes
   * Endswith_local: *.whatever, leading slash only
   * Startswith_local: whatever*, leading slash only
   * Noslash: wildcards, no slashes
   * Nowildcard: non-prefix slashes, no wildcards
   * Complex: non-prefix slashes, wildcards
   * *)
  type patt =
      Simple of string | Noslash of string
    | Complex of string | Simple_local of string
    | Endswith of string | Endswith_local of string
    | Startswith_local of string
    | Nowildcard of string * int
  type glob = glob_type * patt
  type t = (string * glob list) list

  external fnmatch : bool -> string -> string -> bool = "perform_fnmatch" "noalloc"

  let string_of_patt = function
      Simple s | Noslash s | Complex s | Nowildcard (s, _) -> s
      | Simple_local s -> "/" ^ s
      | Endswith s -> "*." ^ s
      | Endswith_local s -> "/*." ^ s
      | Startswith_local s -> "/" ^ s ^ "*"

  let has_wildcard s =
    let rec loop s i max =
      if i < max then
        match String.unsafe_get s i with
            '*' | '?' | '[' | '{' -> true
            | _ -> loop s (i+1) max
      else false
    in loop s 0 (String.length s)

  let suff1 s = String.sub s 1 (String.length s - 1)
  let pref1 s = String.sub s 0 (String.length s - 1)

  let patt_of_string s =
    try
      match String.rindex s '/' with
          0 ->
            let s = suff1 s in
              if not (has_wildcard s) then Simple_local s
              else
                let suff = suff1 s in
                  if s.[0] = '*' && not (has_wildcard suff) then
                    Endswith_local suff
                  else
                    let pref = pref1 s in
                      if s.[String.length s - 1] = '*' && not (has_wildcard pref) then
                        Startswith_local pref
                      else
                        Complex s
        | _ ->
            if not (has_wildcard s) then
              let l = String.length s in
                Nowildcard (s, if s.[0] = '/' then l - 1 else l)
            else
              Complex s
    with Not_found ->
      let suff = suff1 s in
        if s.[0] = '*' && not (has_wildcard suff) then
          Endswith suff
        else if has_wildcard s then
          Noslash s
        else
          Simple s

  let glob_of_string s = match s.[0] with
      '!' -> (Accept, (patt_of_string (suff1 s)))
    | _ -> (Deny, patt_of_string s)

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

  let init path = []

  let update t ~base ~path =
    (Filename.basename path, read_gitignore (join base path)) :: t

  type path = { basename : string; length : int; full_name : string Lazy.t }

  let path_of_string s = { basename = s; length = String.length s; full_name = lazy s }

  let string_of_path p = Lazy.force p.full_name

  let path_length p = p.length

  let push pref p =
    { basename = p.basename; length = p.length + 1 + String.length pref;
      full_name = lazy (String.concat "/" [pref; string_of_path p]) }

  let basename p = p.basename

  let check_ending suff path =
    let fname = basename path in
    let l1 = String.length suff in
    let l2 = String.length fname in
      if l2 < l1 then false else strneq l1 suff 0 fname (l2 - l1)

  let check_start pref path =
    let fname = basename path in
    let l1 = String.length pref in
    let l2 = String.length fname in
      if l2 < l1 then false else
        strneq l1 pref 0 fname 0

  let glob_matches local patt path = match patt with
      Simple s -> s = basename path
    | Simple_local s -> if local then s = basename path else false
    | Endswith s -> check_ending s path
    | Endswith_local s -> if local then check_ending s path else false
    | Startswith_local s -> if local then check_start s path else false
    | Noslash s -> fnmatch false s (basename path)
    | Complex s -> fnmatch true s (string_of_path path)
    | Nowildcard (s, l) ->
        if l = path_length path then
          fnmatch true s (string_of_path path)
        else false

  let path_of_ign_info t = String.concat "/" (List.rev (List.map fst t))

  let is_ignored ?(debug=false) t fname =
    let rec aux local path = function
      | [] -> false
      | (dname, globs)::tl as t ->
        let ign = List.fold_left
          (fun s (ty, patt) ->
            if glob_matches local patt path then
              (match ty with
                  Accept ->
                    if debug then
                        eprintf "ACCEPT %S (matched %S) at %S\n"
                          (string_of_path path) (string_of_patt patt)
                          (path_of_ign_info t);
                    `Kept
                | Deny ->
                    if debug then
                        eprintf "DENY %S (matched %S) at %S\n"
                          (string_of_path path) (string_of_patt patt)
                          (path_of_ign_info t);
                    `Ignored)
            else s)
          `Dontknow globs
        in match ign with
          | `Dontknow -> aux false (push dname path) tl
          | `Ignored -> true
          | `Kept -> false
    in fname = ".git" || aux true (path_of_string fname) t
end
