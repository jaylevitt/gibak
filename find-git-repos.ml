(* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms *)

open Printf
open Folddir
open Util
open Unix

let debug = ref false

module Findrepos(F : Folddir.S) =
struct
  let find_repositories ?(debug=false) path =
    let aux l name stat =
      let dir = join path name in
        match stat.st_kind with
          | S_DIR -> begin
              try access (join dir ".git") [F_OK]; Prune (name :: l)
              with Unix_error _ -> Continue l
            end
          | _ -> Continue l
    in List.sort compare (F.fold_directory ~debug aux [] path "")
end

module All = Findrepos(Folddir.Make(Folddir.Ignore_none))
module Gitignored = Findrepos(Folddir.Make(Folddir.Gitignore))

let main () =
  let usage = "Usage: find-git-repos <options>" in
  let path = ref "." in
  let find_repos = ref All.find_repositories in
  let zerosep = ref false in
  let sorted = ref false in
  let specs = [
       "--path", Arg.Set_string path, "Set base path (default: .)";
       "-i", Arg.Unit (fun () -> find_repos := Gitignored.find_repositories),
       "Mimic git semantics (honor .gitignore, don't scan git submodules)";
       "-z", Arg.Set zerosep, "Use \\0 to separate filenames.";
       "-s", Arg.Set sorted, "Sort output.";
       "--debug", Arg.Set debug, "Debug mode"
     ]
  in Arg.parse specs ignore usage;
     let print = if !zerosep then printf "%s\000" else printf "%s\n" in
     let l = !find_repos ~debug:!debug !path in
       List.iter print (if !sorted then List.sort compare l else l)

let () = main ()
