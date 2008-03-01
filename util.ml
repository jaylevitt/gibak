
let do_finally x final f =
  let r = try f x with e -> (try final x with _ -> ()); raise e in final x; r

let memoized f =
  let t = Hashtbl.create 13 in fun x ->
    try Hashtbl.find t x with Not_found -> let y = f x in Hashtbl.add t x y; y

let strneq s1 o1 s2 o2 =
  let rec loop s1 s2 i j m n =
    if i < m && j < n then
      if String.unsafe_get s1 i = String.unsafe_get s2 j then
        loop s1 s2 (i+1) (j+1) m n
      else
        false
    else if i = m && j = n then true else false in
  let l1 = String.length s1 and l2 = String.length s2 in
    if o1 < 0 || o2 < 0 || o1 >= l1 || o2 >= l2 then invalid_arg "strneq";
    l1 - o1 = l2 - o2 && loop s1 s2 o1 o2 l1 l2
