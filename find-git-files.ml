(* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms *)

open Printf
open Folddir
open Util
open Unix

let debug = ref false

module Find(F : Folddir.S) =
struct
  let find ?(debug=false) ?(sorted=false) path =
    let aux l name stat =
      let dir = join path name in
        match stat.st_kind with
          | S_DIR -> begin
              try access (join dir ".git") [F_OK]; Prune (name :: l)
              with Unix_error _ -> Continue (name :: l)
            end
          | _ -> Continue (name :: l)
    in List.rev (F.fold_directory ~debug ~sorted aux [] path "")
end

module Gitignored = Find(Folddir.Make(Folddir.Gitignore))

let main () =
  let usage = "Usage: find-git-files <options>" in
  let path = ref "." in
  let zerosep = ref false in
  let sorted = ref false in
  let specs = [
       "--path", Arg.Set_string path, "Set base path (default: .)";
       "-z", Arg.Set zerosep, "Use \\0 to separate filenames.";
       "-s", Arg.Set sorted, "Sort output.";
       "--debug", Arg.Set debug, "Debug mode"
     ]
  in
    Arg.parse specs ignore usage;
    let print = if !zerosep then printf "%s\000" else printf "%s\n" in
      List.iter print (Gitignored.find ~debug:!debug ~sorted:!sorted !path)

let () = main ()
