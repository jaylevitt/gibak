(* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms *)

let do_finally x final f =
  let r = try f x with e -> (try final x with _ -> ()); raise e in final x; r

let memoized f =
  let t = Hashtbl.create 13 in fun x ->
    try Hashtbl.find t x with Not_found -> let y = f x in Hashtbl.add t x y; y

let strneq n s1 o1 s2 o2 =
  let rec loop s1 s2 i j k =
    if k > 0 then
      if String.unsafe_get s1 i = String.unsafe_get s2 j then
        loop s1 s2 (i+1) (j+1) (k-1)
      else
        false
    else true in
  let l1 = String.length s1 and l2 = String.length s2 in
    if n < 0 || o1 < 0 || o2 < 0 || o1 + n > l1 || o2 + n > l2 then
      invalid_arg "strneq";
    loop s1 s2 o1 o2 n
