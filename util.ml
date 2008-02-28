
let do_finally x final f =
  let r = try f x with e -> (try final x with _ -> ()); raise e in final x; r

let memoized f =
  let t = Hashtbl.create 13 in fun x ->
    try Hashtbl.find t x with Not_found -> let y = f x in Hashtbl.add t x y; y
