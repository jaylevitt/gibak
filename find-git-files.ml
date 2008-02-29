open Printf
open Folddir
open Util
open Unix

let debug = ref false

module Find(F : Folddir.S) =
struct
  let find_repositories ?(debug=false) path =
    let aux l name stat =
      let dir = join path name in
        match stat.st_kind with
          | S_DIR -> begin
              try access (join dir ".git") [F_OK]; Prune l
              with Unix_error _ -> Continue l
            end
          | _ -> Continue (name :: l)
    in List.rev (F.fold_directory ~debug aux [] path "")
end

module Gitignored = Find(Folddir.Make(Folddir.Gitignore))

let main () =
  let usage = "Usage: find-git-files <options>" in
  let path = ref "." in
  let zerosep = ref false in
  let specs = [
       "--path", Arg.Set_string path, "Set base path (default: .)";
       "-z", Arg.Set zerosep, "Use \\0 to separate filenames.";
       "--debug", Arg.Set debug, "Debug mode"
     ]
  in
    Arg.parse specs ignore usage;
    let print = if !zerosep then printf "%s\000" else print_endline in
      List.iter print (Gitignored.find_repositories ~debug:!debug !path)

let () = main ()
