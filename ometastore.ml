open Printf
open Unix
open Folddir
open Util

let debug = ref false
let verbose = ref false
let use_mtime = ref false
let magic = "Ometastore"
let version = "00000"

type xattr = { name : string; value : string }

type entry = {
  path : string;
  owner : string;
  group : string;
  mode : int;
  mtime : float;
  kind : Unix.file_kind;
  xattrs : xattr list;
}

type whatsnew = Added of entry | Deleted of entry | Diff of entry * entry

external utime : string -> int -> unit = "perform_utime"

let user_name = memoized (fun uid -> (getpwuid uid).pw_name)
let group_name = memoized (fun gid -> (getgrgid gid).gr_name)

let int_of_file_kind = function
    S_REG -> 0 | S_DIR -> 1 | S_CHR -> 2 | S_BLK -> 3 | S_LNK -> 4 | S_FIFO -> 5
  | S_SOCK -> 6

let kind_of_int = function
    0 -> S_REG | 1 -> S_DIR | 2 -> S_CHR | 3 -> S_BLK | 4 -> S_LNK | 5 -> S_FIFO
  | 6 -> S_SOCK | _ -> invalid_arg "kind_of_int"

let entry_of_path path =
  let s = lstat path in
  let user = user_name s.st_uid in
  let group = group_name s.st_gid in
    { path = path; owner = user; group = group; mode = s.st_perm;
      kind = s.st_kind; mtime = s.st_mtime; xattrs = [] }

module Entries(F : Folddir.S) =
struct
  let get_entries ?(verbose=false) path =
    let aux l name = { (entry_of_path (join path name)) with path = name } :: l
    in List.sort compare (F.fold_directory ~verbose aux [] path "")
end

let write_int os bytes n =
  for i = bytes - 1 downto 0 do
    output_char os (Char.chr ((n lsr (i lsl 3)) land 0xFF))
  done

let read_int is bytes =
  let r = ref 0 in
  for i = 0 to bytes - 1 do
    r := !r lsl 8 + Char.code (input_char is)
  done;
  !r

let write_xstring os s =
  write_int os 2 (String.length s);
  output_string os s

let read_xstring is =
  let len = read_int is 2 in
  let s = String.create len in
    really_input is s 0 len;
    s

let dump_entries ?(verbose=false) l fname =
  let dump_entry os e =
    if verbose then print_endline e.path;
    write_xstring os e.path;
    write_xstring os e.owner;
    write_xstring os e.group;
    write_xstring os (string_of_float e.mtime);
    write_int os 2 e.mode;
    write_int os 1 (int_of_file_kind e.kind);
    write_int os 2 (List.length e.xattrs);
    List.iter
      (fun t -> write_xstring os t.name; write_xstring os t.value)
      e.xattrs
  in do_finally (open_out_bin fname) close_out begin fun os ->
    output_string os (magic ^ "\n");
    output_string os (version ^ "\n");
    List.iter (dump_entry os) l
  end

let read_entries fname =
  let read_entry is =
    let path = read_xstring is in
    let owner = read_xstring is in
    let group = read_xstring is in
    let mtime = float_of_string (read_xstring is) in
    let mode = read_int is 2 in
    let kind = kind_of_int (read_int is 1) in
    let nattrs = read_int is 2 in
    let attrs = ref [] in
      for i = 1 to nattrs do
        let name = read_xstring is in
        let value = read_xstring is in
          attrs := { name = name; value = value } :: !attrs
      done;
      { path = path; owner = owner; group = group; mtime = mtime; mode = mode;
        kind = kind; xattrs = !attrs }
  in do_finally (open_in_bin fname) close_in begin fun is ->
    if magic <> input_line is then failwith "Invalid file: bad magic";
    let _ = input_line is (* version *) in
    let entries = ref [] in
      try
        while true do
          entries := read_entry is :: !entries
        done;
        assert false
      with End_of_file -> !entries
  end

let compare_entries l1 l2 =
  let module M = Map.Make(struct type t = string let compare = compare end) in
  let to_map l = List.fold_left (fun m e -> M.add e.path e m) M.empty l in
  let m1 = to_map l1 in
  let m2 = to_map l2 in
  let changes =
    List.fold_left
      (fun changes e2 ->
         try
           let e1 = M.find e2.path m1 in
             if e1 = e2 then changes else Diff (e1, e2) :: changes
         with Not_found -> Added e2 :: changes)
      [] l2 in
  let deletions =
    List.fold_left
      (fun dels e1 -> if M.mem e1.path m2 then dels else Deleted e1 :: dels)
      [] l1
  in List.sort compare (List.rev_append deletions changes)

let print_changes =
  List.iter
    (function
         Added e -> printf "Added: %s\n" e.path
       | Deleted e -> printf "Deleted: %s\n" e.path
       | Diff (e1, e2) ->
           let test name f s = if f e1 <> f e2 then name :: s else s in
           let (++) x f = f x in
           let diffs =
             test "owner" (fun x -> x.owner) [] ++
             test "group" (fun x -> x.group) ++
             test "mode" (fun x -> x.mode) ++
             test "kind" (fun x -> x.kind) ++
             test "mtime"
               (if !use_mtime then (fun x -> x.mtime) else (fun _ -> 0.)) ++
             test "xattr" (fun x -> x.xattrs)
           in match List.rev diffs with
               [] -> ()
             | l -> printf "Changed %s: %s\n" e1.path (String.concat " " l))

let out s = if !verbose then Printf.fprintf Pervasives.stdout s
            else Printf.ifprintf Pervasives.stdout s

let fix_usergroup e =
  out "%s: set owner/group to %S %S\n" e.path e.owner e.group;
  chown e.path (getpwnam e.owner).pw_uid (getgrnam e.group).gr_gid

let apply_change = function
  | Added e when e.kind = S_DIR ->
      out "%s: mkdir (mode %d)\n" e.path e.mode;
      Unix.mkdir e.path e.mode
  | Deleted _ | Added _ -> ()
  | Diff (e1, e2) ->
      if e1.owner <> e2.owner || e1.group <> e2.group then fix_usergroup e2;
      if e1.mode <> e2.mode then begin
        out "%s: chmod %d\n" e2.path e2.mode;
        chmod e2.path e2.mode;
      end;
      if e1.kind <> e2.kind then
        printf "%s: file type of changed (nothing done)\n" e1.path;
      if !use_mtime && e1.mtime <> e2.mtime then begin
        out "%s: mtime set to %.0f\n" e1.path e2.mtime;
        utime e2.path (int_of_float e2.mtime)
      end

let apply_changes path l =
  List.iter apply_change
    (List.map
       (function
            Added _ | Deleted _ as x -> x
          | Diff (e1, e2) -> Diff ({ e1 with path = join path e1.path},
                                   { e2 with path = join path e2.path}))
       l)

module Allentries = Entries(Folddir.Make(Folddir.Ignore_none))
module Gitignored = Entries(Folddir.Make(Folddir.Gitignore))

let main () =
  let usage = "Usage: ometastore <options>" in
  let mode = ref `Unset in
  let file = ref ".ometastore" in
  let path = ref "." in
  let get_entries = ref Allentries.get_entries in
  let specs = [
       "-c", Arg.Unit (fun () -> mode := `Compare),
       "Show differences between stored and real metadata";
       "-s", Arg.Unit (fun () -> mode := `Save), "Save metadata";
       "-a", Arg.Unit (fun () -> mode := `Apply), "Apply current metadata";
       "-i", Arg.Unit (fun () -> get_entries := Gitignored.get_entries),
       "Honor .gitignore specifications";
       "-m", Arg.Set use_mtime, "Consider mtime for diff and apply";
       "-v", Arg.Set verbose, "Verbose mode";
       "--debug", Arg.Set debug, "Debug mode"
     ]
  in Arg.parse specs ignore usage;
     match !mode with
       | `Unset -> Arg.usage specs usage
       | `Save -> dump_entries ~verbose:!verbose (!get_entries !path) !file
       | `Compare | `Apply as mode ->
           let stored = read_entries !file in
           let actual = !get_entries ~verbose:!debug !path in
             match mode with
                 `Compare -> print_changes (compare_entries stored actual)
               | `Apply -> apply_changes !path (compare_entries actual stored)

let () = main ()
