
let do_finally x final f = try f x with e -> (try final x with _ -> ()); raise e
