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
  let usage = "Usage: find-repositories <options>" in
  let path = ref "." in
  let find_repos = ref All.find_repositories in
  let zerosep = ref false in
  let specs = [
       "--path", Arg.Set_string path, "Set base path (default: .)";
       "-i", Arg.Unit (fun () -> find_repos := Gitignored.find_repositories),
       "Honor .gitignore specifications";
       "-z", Arg.Set zerosep, "Use \\0 to separate filenames.";
       "--debug", Arg.Set debug, "Debug mode"
     ]
  in Arg.parse specs ignore usage;
     let print = if !zerosep then printf "%s\000" else print_endline in
       List.iter print (!find_repos ~debug:!debug !path)

let () = main ()
