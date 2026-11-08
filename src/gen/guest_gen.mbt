//! The MoonBit half of a binding, generated from a plan.
//!
//! S3 wrote the guest's dispatch by hand next to a generated Python module. The
//! two agreed because a person kept them in agreement. Here every branch, every
//! handle table and every decoder comes from the same `Plan` the Python side is
//! read off, so an interface change regenerates both halves or neither.
//!
//! The generated file has four parts:
//!
//! 1. **The ABI surface**, which is identical for every guest: buffers the host
//!    reads and writes, one discovered offset per buffer layout, and six
//!    exports.
//! 2. **One decoder per wire shape**, emitted only for the shapes this plan
//!    actually uses — an unused private function is a warning, and warnings are
//!    errors in this repo.
//! 3. **One table per concrete type that crosses**, because MoonBit has no
//!    runtime type information and a single table cannot hold two types. Each
//!    table is tagged, and a release batch names the tag.
//! 4. **The dispatch**, one arm per symbol, in the order the plan lists them.

///|
/// The MoonBit type of a decoded value, including the `?` of an optional one.
///
/// This is the type a decoder yields *before* the failure `?` is added, which
/// is why `Option` nests here and not in the helper's name: `Array[Int?]` has
/// elements of type `Int?`, and each element is decoded by the `Int` helper
/// that already returns `Int?`.
fn val_ty(w : Wire) -> String {
  match w {
    WInt => "Int"
    WDouble => "Double"
    WBool => "Bool"
    WStr | WStrView => "String"
    WUnit => "Unit"
    WHandle(t) => t.expr
    WMaybe(inner) => val_ty(inner) + "?"
    WArr(inner) | WArrView(inner) => "Array[" + val_ty(inner) + "]"
    WMap(k, v) => "Map[" + val_ty(k) + ", " + val_ty(v) + "]"
    WRes(ok, _) => val_ty(ok)
    WCall(params, ret) => {
      let parts : Array[String] = []
      for p in params {
        parts.push(val_ty(p))
      }
      "(" + join_strings(parts, ", ") + ") -> " + val_ty(ret)
    }
  }
}

///|
/// The name of the decoder for a shape. An optional one reuses the inner
/// decoder, because that decoder already answers with `T?` — `null` and "the
/// caller left it out" are the same thing on the wire.
fn dec_name(w : Wire) -> String {
  match w {
    WMaybe(inner) => dec_name(inner)
    // A `StringView` arrives as a `String`: the host has no way to hand over a
    // borrowed view, so both shapes read through one decoder.
    WStrView => "dec_str"
    _ => "dec_" + w.key()
  }
}

///|
/// The name of the encoder for a shape, with the same `Option` collapse: an
/// encoder already takes a `T?`.
fn enc_name(w : Wire) -> String {
  match w {
    WMaybe(inner) => enc_name(inner)
    _ => "enc_" + w.key()
  }
}

///|
fn base_wire(w : Wire) -> Wire {
  match w {
    WMaybe(inner) => base_wire(inner)
    _ => w
  }
}

///|
/// How one argument is decoded, given the frame and its position.
///
/// `None` for `Unit`, which carries nothing: the callee's parameter is `()`,
/// and asking the frame for a value that was never sent would be a protocol
/// error invented by the generator.
fn arg_expr(w : Wire, index : String) -> String? {
  match base_wire(w) {
    WUnit => None
    _ => Some(dec_name(w) + "(arg(argv, " + index + "))")
  }
}

///|
/// The encoder for one return shape. Every encoder takes a `T?`, so a plain `T`
/// and a `T?` are converted by the same call.
fn out_helper(w : Wire) -> String {
  enc_name(w)
}

///|
/// How a decoded local is passed to the guest: a `StringView` parameter needs
/// the view built here, where its owner is still alive.
fn call_arg(w : Wire, v : String) -> String {
  match base_wire(w) {
    WStrView => v + "[:]"
    // MoonBit will not coerce an `Array` into an `ArrayView` at a call, and the
    // declaration is the only place that says which one is wanted.
    WArrView(_) => v + "[:]"
    WUnit => "()"
    _ => v
  }
}

///|
/// The names a generated identifier needs.
fn arg_var(i : Int32) -> String {
  "a" + i.to_string()
}

///|
fn some_var(i : Int32) -> String {
  "v" + i.to_string()
}

///|
/// Appends `s` to `list` when `list` does not already hold an equal element.
fn[T : Eq] push_unique(list : Array[T], value : T) -> Unit {
  if !list.contains(value) {
    list.push(value)
  }
}

///|
/// Every shape one value is made of, outermost first.
///
/// A `StringView` is recorded as a `String` because the decoder is shared, and
/// a duplicate definition does not compile.
fn collect_shapes(w : Wire, out : Array[Wire]) -> Unit {
  let normalized = match w {
    // A view is decoded and encoded by the array helpers, so it must not add a
    // second copy of them.
    WArrView(inner) => WArr(inner)
    other => other
  }
  push_unique(out, normalized)
  match w {
    WMaybe(inner) => collect_shapes(inner, out)
    WArr(inner) => collect_shapes(inner, out)
    WMap(k, v) => {
      collect_shapes(k, out)
      collect_shapes(v, out)
    }
    WRes(ok, err) => {
      collect_shapes(ok, out)
      collect_shapes(err, out)
    }
    WCall(params, ret) => {
      for p in params {
        collect_shapes(p, out)
      }
      collect_shapes(ret, out)
    }
    _ => ()
  }
}

///|
/// The packages the generated file has to import, sorted, derived from what the
/// plan actually mentions. An unused import is a warning, and a missing one is a
/// compile error, so this is computed rather than declared.
fn used_packages(plan : Plan) -> Array[String] {
  let pkgs : Array[String] = []
  for s in plan.syms {
    if s.kind == Free {
      push_unique(pkgs, s.decl_pkg)
    } else {
      push_unique(pkgs, s.owner_pkg)
    }
    for w in s.params {
      note_wire_pkg(w, pkgs)
    }
    note_wire_pkg(s.ret, pkgs)
  }
  let sorted : Array[String] = []
  for p in pkgs {
    let mut at = 0
    while at < sorted.length() && sorted[at] < p {
      at = at + 1
    }
    sorted.insert(at, p)
  }
  sorted
}

///|
fn note_wire_pkg(w : Wire, pkgs : Array[String]) -> Unit {
  match w {
    WHandle(t) => push_unique(pkgs, t.pkg)
    WMaybe(inner) => note_wire_pkg(inner, pkgs)
    _ => ()
  }
}

///|
/// `@json`, from a package path, spelled the way the generated file sees it.
fn guest_alias(pkg : String) -> String {
  @map.pkg_alias(pkg)
}

///|
/// The text of one call, with `extra` already-rendered label arguments appended
/// after the positional ones.
///
/// MoonBit rejects an optional parameter passed positionally, so the call has to
/// name it — which means the *shape* of the call depends on which optionals the
/// caller supplied. `render_call` builds the tree of those shapes; this is its
/// leaf.
fn call_leaf(sym : Sym, extra : Array[String]) -> String {
  let positional : Array[String] = []
  let mut i = 0
  while i < sym.params.length() {
    match sym.params[i] {
      WMaybe(_) => ()
      _ => positional.push(call_arg(sym.params[i], arg_var(i)))
    }
    i = i + 1
  }
  for e in extra {
    positional.push(e)
  }
  match sym.kind {
    Ctor => {
      let fields : Array[String] = []
      let mut j = 0
      while j < sym.params.length() {
        let label = if j < sym.labels.length() {
          sym.labels[j]
        } else {
          "field" + j.to_string()
        }
        fields.push(label + ": " + call_arg(sym.params[j], arg_var(j)))
        j = j + 1
      }
      guest_alias(sym.owner_pkg) +
      "." +
      sym.owner +
      "::{ " +
      join(fields, ", ") +
      " }"
    }
    Getter => arg_var(0) + "." + sym.name
    Free =>
      guest_alias(sym.decl_pkg) +
      "." +
      sym.name +
      "(" +
      join(positional, ", ") +
      ")"
    _ =>
      guest_alias(sym.owner_pkg) +
      "." +
      sym.owner +
      "::" +
      sym.name +
      "(" +
      join(positional, ", ") +
      ")"
  }
}

///|
/// The call, with one nested `match` per optional parameter.
///
/// The number of shapes is `2^n` for `n` optional parameters, which is why the
/// planner refuses a signature with more than a handful: past that the text
/// grows faster than the interface is worth.
fn render_call(sym : Sym) -> String {
  // Optional parameters, in declaration order.
  let optionals : Array[Int32] = []
  let mut i = 0
  while i < sym.params.length() {
    match sym.params[i] {
      WMaybe(_) => optionals.push(i)
      _ => ()
    }
    i = i + 1
  }
  if optionals.length() == 0 {
    return call_leaf(sym, [])
  }
  optional_tree(sym, optionals, 0, [])
}

///|
fn optional_tree(
  sym : Sym,
  optionals : Array[Int32],
  level : Int32,
  provided : Array[String],
) -> String {
  if level == optionals.length() {
    return call_leaf(sym, provided)
  }
  let i = optionals[level]
  let label = if i < sym.labels.length() { sym.labels[i] } else { "" }
  let with_value : Array[String] = []
  for p in provided {
    with_value.push(p)
  }
  with_value.push(label + "=" + call_arg(sym.params[i], some_var(i)))
  "match " +
  arg_var(i) +
  " {\n" +
  "        Some(" +
  some_var(i) +
  ") => " +
  optional_tree(sym, optionals, level + 1, with_value) +
  "\n        None => " +
  optional_tree(sym, optionals, level + 1, provided) +
  "\n      }"
}

///|
/// One `match` arm of the dispatch.
fn render_arm(sym : Sym) -> String {
  let sb = StringBuilder()
  sb.write_string("    \"" + sym.symbol + "\" => {\n")
  match sym.kind {
    Setter => render_setter_arm(sym, sb)
    _ => {
      // Arguments. A required one is unwrapped here, because a missing
      // argument is a protocol failure with a symbol name in it. An optional
      // one is passed through: `null` *is* the absent argument, so there is
      // nothing to fail on.
      let mut i = 0
      while i < sym.params.length() {
        let w = sym.params[i]
        match arg_expr(w, i.to_string()) {
          None => ()
          Some(expr) =>
            match w {
              WMaybe(_) =>
                sb.write_string("      let " + arg_var(i) + " = " + expr + "\n")
              _ =>
                sb.write_string(
                  "      let " +
                  arg_var(i) +
                  " = match " +
                  expr +
                  " {\n" +
                  "        Some(v) => v\n" +
                  "        None => return @abi.Failed(\"" +
                  sym.symbol +
                  ": bad argument " +
                  (i + 1).to_string() +
                  "\")\n" +
                  "      }\n",
                )
            }
        }
        i = i + 1
      }
      let call = render_call(sym)
      if sym.raises {
        // A raised MoonBit error becomes a failure frame that names its type,
        // so the Python side can raise the generated exception class rather
        // than a catch-all.
        let failure = if sym.error_type == "" {
          "@abi.Failed(error.to_string())"
        } else {
          "@abi.FailedAs(\"" + sym.error_type + "\", error.to_string())"
        }
        sb.write_string(
          "      let value = try {\n        " +
          call +
          "\n      } catch {\n        error => return " +
          failure +
          "\n      }\n",
        )
      } else {
        sb.write_string("      let value = " + call + "\n")
      }
      match sym.ret {
        WRes(ok, _) =>
          // `Ok` is the value; `Err` is the exception Python would have raised
          // had the language had one. The wrapper is erased on purpose.
          sb.write_string(
            "      match value {\n" +
            "        Ok(inner) => @abi.Ok(" +
            enc_name(ok) +
            "(Some(inner)))\n" +
            "        Err(error) => @abi.FailedAs(\"" +
            sym_error_type(sym) +
            "\", error.to_string())\n" +
            "      }\n",
          )
        _ => {
          // Every encoder takes a `T?`. A return that is already optional is
          // passed through; a plain one is wrapped, because MoonBit does not
          // coerce `T` into `T?` at a call.
          let argument = match sym.ret {
            WMaybe(_) => "value"
            _ => "Some(value)"
          }
          let encoded = "@abi.Ok(" + out_helper(sym.ret) + "(" + argument + "))"
          // Encoding a handle inserts into a table, which raises when the table
          // is full. A `try` around a body that cannot raise is a warning, so it
          // is only written where it can.
          if encoder_raises(sym.ret) {
            sb.write_string(
              "      try {\n        " +
              encoded +
              "\n      } catch {\n        error => @abi.Failed(error.to_string())\n      }\n",
            )
          } else {
            sb.write_string("      " + encoded + "\n")
          }
        }
      }
    }
  }
  sb.write_string("    }\n")
  sb.to_string()
}

///|
/// The error type a `Result` return carries, spelled the way the Python side
/// registered it.
fn sym_error_type(sym : Sym) -> String {
  sym.error_type
}

///|
/// Whether encoding this shape can raise. Only a handle does: it inserts into a
/// table, and a full table raises.
fn encoder_raises(w : Wire) -> Bool {
  match w {
    WHandle(_) => true
    WArr(inner) | WArrView(inner) => encoder_raises(inner)
    WMap(k, v) => encoder_raises(k) || encoder_raises(v)
    WMaybe(inner) => encoder_raises(inner)
    _ => false
  }
}

///|
/// A field write has to reach the object, not a copy of it: the argument decoder
/// hands back a value, and after the assignment the value goes back into the
/// reference the table holds.
fn render_setter_arm(sym : Sym, sb : StringBuilder) -> Unit {
  let key = match sym.params[0] {
    WHandle(t) => t.key
    _ => ""
  }
  let value_wire = if sym.params.length() > 1 { sym.params[1] } else { WUnit }
  let value_expr = dec_name(value_wire) + "(arg(argv, 1))"
  sb.write_string(
    "      let id = match arg_handle(argv, 0) {\n" +
    "        Some(v) => v\n" +
    "        None => return @abi.Failed(\"" +
    sym.symbol +
    ": bad argument 1\")\n" +
    "      }\n" +
    "      let value = match " +
    value_expr +
    " {\n" +
    "        Some(v) => v\n" +
    "        None => return @abi.Failed(\"" +
    sym.symbol +
    ": bad argument 2\")\n" +
    "      }\n" +
    "      match tables." +
    key +
    ".get(id) {\n" +
    "        Some(slot) => {\n" +
    "          let current = slot.val\n" +
    "          current." +
    sym.name +
    " = value\n" +
    "          slot.val = current\n" +
    "          @abi.Ok(@abi.Value::unit())\n" +
    "        }\n" +
    "        None => @abi.Failed(\"" +
    sym.symbol +
    ": stale handle\")\n" +
    "      }\n",
  )
}

///|
/// One decoder per shape, as source.
///
/// Three rules make the recursion work. A decoder takes a `@abi.Value?` — the
/// same thing the frame hands back for a position that may not exist — so a
/// container can decode its elements with the very function it uses for itself.
/// An `Option` has no helper of its own, because the inner decoder already
/// answers with a `T?`. And nothing recurses at emission time: every shape is
/// collected up front, so a shape shared by two symbols is written once.
fn emit_dec_helper(sb : StringBuilder, w : Wire) -> Unit {
  match w {
    // An `Option` is read by the payload's decoder, which already answers with a
    // `T?`. Delegating keeps this function total even if a caller passes a
    // wrapper that the emission loop did not unwrap.
    WMaybe(inner) => emit_dec_helper(sb, inner)
    WUnit => ()
    WInt =>
      sb.write_string(
        "///|\nfn dec_int(v : @abi.Value?) -> Int? {\n" +
        "  match v {\n    Some(x) => x.as_int()\n    None => None\n  }\n}\n\n",
      )
    WDouble =>
      // A Python `int` is a perfectly good `Double`: the codec tags it as an
      // int, and refusing it here would make `f(1)` fail where `f(1.0)` works.
      sb.write_string(
        "///|\nfn dec_double(v : @abi.Value?) -> Double? {\n" +
        "  match v {\n" +
        "    Some(x) =>\n" +
        "      match x.as_double() {\n" +
        "        Some(d) => Some(d)\n" +
        "        None =>\n" +
        "          match x.as_int() {\n" +
        "            Some(n) => Some(n.to_double())\n" +
        "            None => None\n" +
        "          }\n" +
        "      }\n" +
        "    None => None\n" +
        "  }\n}\n\n",
      )
    WBool =>
      sb.write_string(
        "///|\nfn dec_bool(v : @abi.Value?) -> Bool? {\n" +
        "  match v {\n    Some(x) => x.as_bool()\n    None => None\n  }\n}\n\n",
      )
    WStr | WStrView =>
      sb.write_string(
        "///|\nfn dec_str(v : @abi.Value?) -> String? {\n" +
        "  match v {\n    Some(x) => x.as_string()\n    None => None\n  }\n}\n\n",
      )
    WHandle(t) =>
      sb.write_string(
        "///|\n/// A handle from the host, resolved against the table for `" +
        t.expr +
        "`.\nfn dec_" +
        t.key +
        "(v : @abi.Value?) -> " +
        t.expr +
        "? {\n" +
        "  match v {\n" +
        "    Some(x) =>\n" +
        "      match x.as_handle() {\n" +
        "        Some(id) =>\n" +
        "          match tables." +
        t.key +
        ".get(id) {\n" +
        "            Some(slot) => Some(slot.val)\n" +
        "            None => None\n" +
        "          }\n" +
        "        None => None\n" +
        "      }\n" +
        "    None => None\n" +
        "  }\n}\n\n",
      )
    WArr(inner) | WArrView(inner) => {
      let ty = val_ty(inner)
      sb.write_string(
        "///|\nfn dec_" +
        w.key() +
        "(v : @abi.Value?) -> Array[" +
        ty +
        "]? {\n" +
        "  match v {\n" +
        "    Some(@abi.List(items)) => {\n" +
        "      let out : Array[" +
        ty +
        "] = []\n" +
        "      let mut ok = true\n" +
        "      for item in items {\n" +
        "        match " +
        dec_name(inner) +
        "(Some(item)) {\n" +
        "          Some(x) => out.push(x)\n" +
        "          None => ok = false\n" +
        "        }\n" +
        "      }\n" +
        "      if ok {\n" +
        "        Some(out)\n" +
        "      } else {\n" +
        "        None\n" +
        "      }\n" +
        "    }\n" +
        "    _ => None\n" +
        "  }\n}\n\n",
      )
    }
    WMap(k, v) =>
      sb.write_string(
        "///|\nfn dec_" +
        w.key() +
        "(v : @abi.Value?) -> Map[" +
        val_ty(k) +
        ", " +
        val_ty(v) +
        "]? {\n" +
        "  match v {\n" +
        "    Some(@abi.Map(pairs)) => {\n" +
        "      let out : Map[" +
        val_ty(k) +
        ", " +
        val_ty(v) +
        "] = Map([])\n" +
        "      let mut ok = true\n" +
        "      for pair in pairs {\n" +
        "        let (raw_key, raw_value) = pair\n" +
        "        match (" +
        dec_name(k) +
        "(Some(raw_key)), " +
        dec_name(v) +
        "(Some(raw_value))) {\n" +
        "          (Some(kk), Some(vv)) => out.set(kk, vv)\n" +
        "          _ => ok = false\n" +
        "        }\n" +
        "      }\n" +
        "      if ok {\n" +
        "        Some(out)\n" +
        "      } else {\n" +
        "        None\n" +
        "      }\n" +
        "    }\n" +
        "    _ => None\n" +
        "  }\n}\n\n",
      )
    // A `Result` is unwrapped by the arm that returns it.
    WRes(_, _) => ()
    // A callback arrives as an integer id; the guest wraps it in a closure
    // that calls back through the host import.
    WCall(_, _) => sb.write_string(callback_decoder(w))
  }
}

///|
/// The closure a callback parameter becomes.
///
/// The id travels through a table the *host* owns, so the guest never holds a
/// Python object: it holds a number and a function that turns the number into a
/// call. Nothing about the Python callable is visible from here.
fn callback_decoder(w : Wire) -> String {
  let params = match w {
    WCall(params, _) => params
    _ => []
  }
  let ret = match w {
    WCall(_, ret) => ret
    _ => WUnit
  }
  let types : Array[String] = []
  let encoded : Array[String] = []
  let applied : Array[String] = []
  let mut i = 0
  for p in params {
    let name = "a" + i.to_string()
    // A function *type* names no parameters; only the closure that
    // implements it does.
    types.push(val_ty(p))
    encoded.push(enc_name(p) + "(Some(" + name + "))")
    applied.push(name)
    i = i + 1
  }
  let call_args = if applied.length() == 0 {
    "[]"
  } else {
    "[" + join_strings(encoded, ", ") + "]"
  }
  let body = if ret == WUnit {
    "    invoke_callback(id, " + call_args + ")\n    ()"
  } else if is_maybe(ret) {
    // The decoder already answers with a `T?`, which is exactly what an
    // optional callback returns — unwrapping it would lose the `None`.
    "    match invoke_callback(id, " +
    call_args +
    ") {\n" +
    "      Some(v) => " +
    dec_name(ret) +
    "(Some(v))\n" +
    "      None => None\n" +
    "    }"
  } else {
    "    match invoke_callback(id, " +
    call_args +
    ") {\n" +
    "      Some(v) => match " +
    dec_name(ret) +
    "(Some(v)) {\n" +
    "        Some(r) => r\n" +
    "        None => " +
    zero_value(ret) +
    "\n" +
    "      }\n" +
    "      None => " +
    zero_value(ret) +
    "\n" +
    "    }"
  }
  "///|\nfn " +
  dec_name(w) +
  "(v : @abi.Value?) -> ((" +
  join_strings(types, ", ") +
  ") -> " +
  val_ty(ret) +
  ")? {\n" +
  "  match v {\n" +
  "    Some(raw) => match raw.as_int() {\n" +
  "    Some(id) =>\n" +
  "      Some(fn(" +
  join_strings(applied, ", ") +
  ") {\n" +
  body +
  "\n      })\n" +
  "      None => None\n" +
  "    }\n" +
  "    None => None\n" +
  "  }\n}\n\n"
}

///|
fn is_maybe(w : Wire) -> Bool {
  match w {
    WMaybe(_) => true
    _ => false
  }
}

///|
/// What a callback returns when the host call failed.
///
/// The value is never seen: a Python exception inside a callback is recorded by
/// the host and re-raised when the outer call returns, so the outer result is
/// discarded either way. A default keeps the MoonBit closure total, which is
/// what its declared type demands.
fn zero_value(w : Wire) -> String {
  match w {
    WInt => "0"
    WDouble => "0.0"
    WBool => "false"
    WStr | WStrView => "\"\""
    WUnit => "()"
    _ => "abort(\"callback shape\")"
  }
}

///|
/// One encoder per shape, as source. Every encoder takes a `T?`.
fn emit_enc_helper(sb : StringBuilder, w : Wire) -> Unit {
  match w {
    WMaybe(inner) => emit_enc_helper(sb, inner)
    WUnit =>
      sb.write_string(
        "///|\nfn enc_unit(_v : Unit?) -> @abi.Value {\n  @abi.Value::unit()\n}\n\n",
      )
    WInt =>
      sb.write_string(
        "///|\nfn enc_int(v : Int?) -> @abi.Value {\n" +
        "  match v {\n    Some(x) => @abi.Int(x)\n    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WDouble =>
      sb.write_string(
        "///|\nfn enc_double(v : Double?) -> @abi.Value {\n" +
        "  match v {\n    Some(x) => @abi.Double(x)\n    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WBool =>
      sb.write_string(
        "///|\nfn enc_bool(v : Bool?) -> @abi.Value {\n" +
        "  match v {\n    Some(x) => @abi.Bool(x)\n    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WStr =>
      sb.write_string(
        "///|\nfn enc_str(v : String?) -> @abi.Value {\n" +
        "  match v {\n    Some(x) => @abi.Str(x)\n    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WStrView =>
      // A view is borrowed from a value the caller owns; the host gets a copy.
      sb.write_string(
        "///|\nfn enc_strview(v : StringView?) -> @abi.Value {\n" +
        "  match v {\n    Some(x) => @abi.Str(x.to_owned())\n    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WHandle(t) =>
      // `insert` raises when the table is full, and a full table is a real
      // outcome rather than a bug: the encoder is honest about it and every
      // caller runs inside a `try`.
      sb.write_string(
        "///|\nfn enc_" +
        t.key +
        "(v : " +
        t.expr +
        "?) -> @abi.Value raise {\n  match v {\n" +
        "    Some(x) => @abi.Handle(tables." +
        t.key +
        ".insert(@ref.Ref(x)))\n" +
        "    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    WArr(inner) | WArrView(inner) => {
      let raises = if encoder_raises(inner) { " raise" } else { "" }
      // Every encoder takes `T?`. An element of an `Array[T?]` is already an
      // `Option`, so it passes through unwrapped; every other element needs one
      // `Some(...)` around it.
      let elem = match inner {
        WMaybe(_) => "item"
        _ => "Some(item)"
      }
      sb.write_string(
        "///|\nfn enc_" +
        w.key() +
        "(v : Array[" +
        val_ty(inner) +
        "]?) -> @abi.Value" +
        raises +
        " {\n" +
        "  match v {\n" +
        "    Some(items) => {\n" +
        "      let out : Array[@abi.Value] = []\n" +
        "      for item in items {\n" +
        "        out.push(" +
        enc_name(inner) +
        "(" +
        elem +
        "))\n" +
        "      }\n" +
        "      @abi.List(out)\n" +
        "    }\n" +
        "    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    }
    WMap(k, v) => {
      let raises = if encoder_raises(k) || encoder_raises(v) {
        " raise"
      } else {
        ""
      }
      let key_arg = match k {
        WMaybe(_) => "key"
        _ => "Some(key)"
      }
      let val_arg = match v {
        WMaybe(_) => "item"
        _ => "Some(item)"
      }
      sb.write_string(
        "///|\nfn enc_" +
        w.key() +
        "(v : Map[" +
        val_ty(k) +
        ", " +
        val_ty(v) +
        "]?) -> @abi.Value" +
        raises +
        " {\n" +
        "  match v {\n" +
        "    Some(items) => {\n" +
        "      let out : Array[(@abi.Value, @abi.Value)] = []\n" +
        "      for entry in items {\n" +
        "        let (key, item) = entry\n" +
        "        out.push((" +
        enc_name(k) +
        "(" +
        key_arg +
        "), " +
        enc_name(v) +
        "(" +
        val_arg +
        ")))\n" +
        "      }\n" +
        "      @abi.Map(out)\n" +
        "    }\n" +
        "    None => @abi.Value::unit()\n  }\n}\n\n",
      )
    }
    // A `Result` is unwrapped in the dispatch arm, not by an encoder: `Ok` has
    // a value to encode and `Err` has a type to name.
    WRes(_, _) => ()
    // A callback is not a return shape the frame can carry.
    WCall(_, _) => ()
  }
}

///|
/// The MoonBit source of a whole guest module.
pub fn render_guest(plan : Plan) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "//! The MoonBit half of a generated MoonBridge binding. Do not edit.\n" +
    "//!\n" +
    "//! `moonbridge guest-gen` writes this file from the same type graph that\n" +
    "//! writes the Python module, so every branch below has a caller and every\n" +
    "//! symbol the Python side sends is matched here. Regenerate instead of\n" +
    "//! editing: a hand edit breaks that guarantee and nothing will say so.\n" +
    "//!\n" +
    "//! The ABI is six exports and two buffers:/n" +
    "//!\n" +
    "//! ```text\n" +
    "//!   mb_in_reserve(n) -> ptr     grow the input buffer, return its object ptr\n" +
    "//!   mb_stage() -> ptr           the response buffer's object ptr\n" +
    "//!   mb_call(in_len) -> out_len  run the frame already in the input buffer\n" +
    "//!   mb_probe() -> ptr           a fingerprinted Bytes, for layout discovery\n" +
    "//!   mb_probe_out() -> ptr       the same fingerprint as a FixedArray\n" +
    "//!   mb_live_handles() -> count  objects the tables still hold\n" +
    "//! ```\n\n",
  )
  sb.write_string(
    "///|\n/// The response buffer, as a one-element array so the guest can replace it.\n" +
    "///\n" +
    "/// It is a `FixedArray[Byte]`, not a `Bytes`, and that is the whole point.\n" +
    "/// `Bytes` is immutable here, so publishing a response would mean handing the\n" +
    "/// host a freshly encoded object, one per call, and every object a guest\n" +
    "/// export returns keeps a reference the host cannot release. A mutable array\n" +
    "/// is written in place, so the host is handed the same object every call.\n" +
    "let out_slot : Array[FixedArray[Byte]] = [FixedArray::make(4096, b'\\x00')]\n\n",
  )
  // A callback needs a second buffer: the host writes the call's result into
  // memory, and it cannot use the input buffer, which still holds the frame
  // being decoded.
  let needs_callback_buf = plan_uses_callbacks(plan)
  sb.write_string(
    "///|\n/// The input buffer, owned by the guest so the host never has to know how a\n" +
    "/// MoonBit `Bytes` is laid out beyond one discovered offset.\n" +
    "priv struct Buffers {\n" +
    "  mut inbox : Bytes\n" +
    (if needs_callback_buf {
      "  /// Written by the host while a callback runs.\n" +
      "  mut cb_out : Bytes\n"
    } else {
      ""
    }) +
    "}\n\n" +
    "///|\nlet buffers : Buffers = { inbox: Bytes::new(1024), " +
    (if needs_callback_buf { "cb_out: Bytes::new(256), " } else { "" }) +
    "}\n\n",
  )
  sb.write_string(
    "///|\n/// A fingerprinted buffer the host probes once to learn where the data of a\n" +
    "/// `Bytes` object lives.\n" +
    "let probe_bytes : Bytes = @utf8.encode(\"MOONBRIDGE-PROBE-DATA-OFFSET-0420\")\n\n" +
    "///|\n/// The same fingerprint as a `FixedArray[Byte]`. The two layouts are not\n" +
    "/// promised to match, so the host measures each one.\n" +
    "let probe_out : FixedArray[Byte] = {\n" +
    "  let marker = @utf8.encode(\"MOONBRIDGE-PROBE-DATA-OFFSET-0420\")\n" +
    "  let arr : FixedArray[Byte] = FixedArray::make(marker.length(), b'\\x00')\n" +
    "  arr.blit_from_bytesview(0, marker[:])\n" +
    "  arr\n" +
    "}\n\n",
  )
  // Tables: one per concrete type, because a single table has no way to hold
  // two types without runtime type information.
  if plan.handles.length() > 0 {
    sb.write_string(
      "///|\n/// One table per concrete type that crosses. MoonBit has no runtime type\n" +
      "/// information, so a value can only be stored where its type is known.\n" +
      "///\n" +
      "/// Vales are held behind a `Ref` rather than directly: a struct is a value,\n" +
      "/// so a handle that returned a copy could not be written through.\n" +
      "priv struct Tables {\n",
    )
    for h in plan.handles {
      sb.write_string(
        "  " + h.ty.key + " : @abi.HandleTable[@ref.Ref[" + h.ty.expr + "]]\n",
      )
    }
    sb.write_string("}\n\n///|\nlet tables : Tables = {\n")
    for h in plan.handles {
      sb.write_string("  " + h.ty.key + ": @abi.HandleTable::new(),\n")
    }
    sb.write_string("}\n\n")
  }
  // Exports.
  sb.write_string(
    "///|\n" +
    "/// Ensures the input buffer holds at least `n` bytes and returns it.\n" +
    "#export_name(\"mb_in_reserve\")\n" +
    "pub fn in_reserve(n : Int32) -> Bytes {\n" +
    "  if buffers.inbox.length() < n {\n" +
    "    let size = if n * 2 > 1024 { n * 2 } else { 1024 }\n" +
    "    buffers.inbox = Bytes::new(size)\n" +
    "  }\n" +
    "  buffers.inbox\n" +
    "}\n\n" +
    "///|\n#export_name(\"mb_stage\")\n" +
    "pub fn stage_ptr() -> FixedArray[Byte] {\n  out_slot[0]\n}\n\n" +
    "///|\n#export_name(\"mb_probe\")\n" +
    "pub fn probe() -> Bytes {\n  probe_bytes\n}\n\n" +
    "///|\n#export_name(\"mb_probe_out\")\n" +
    "pub fn probe_out_ptr() -> FixedArray[Byte] {\n  probe_out\n}\n\n" +
    "///|\n#export_name(\"mb_live_handles\")\n" +
    "pub fn live_handles() -> Int32 {\n  live_total()\n}\n\n",
  )
  // The frame plumbing, identical for every guest.
  sb.write_string(
    "///|\n/// Copies `src` into the response buffer, growing it if needed, and returns\n" +
    "/// the response length.\n" +
    "fn publish(src : Bytes) -> Int32 {\n" +
    "  let n = src.length()\n" +
    "  let cur = out_slot[0]\n" +
    "  if cur.length() < n {\n" +
    "    let mut size = cur.length()\n" +
    "    while size < n {\n" +
    "      size = size * 2\n" +
    "    }\n" +
    "    out_slot[0] = FixedArray::make(size, b'\\x00')\n" +
    "  }\n" +
    "  out_slot[0].blit_from_bytesview(0, src[:])\n" +
    "  n\n" +
    "}\n\n" +
    "///|\nfn read_u32(b : Bytes, at : Int32) -> Int32 {\n" +
    "  let mut v = 0\n" +
    "  for shift = 0; shift < 4; shift = shift + 1 {\n" +
    "    v = v | (b.unsafe_get(at + shift).to_int() << (shift * 8))\n" +
    "  }\n" +
    "  v\n" +
    "}\n\n" +
    "///|\nfn slice(b : Bytes, start : Int32, end : Int32) -> Bytes {\n" +
    "  @buffer.from_bytes(b.exact_view(start~, end~)).to_bytes()\n" +
    "}\n\n" +
    "///|\n/// `args[i]`, or `None` when the caller sent fewer arguments than the symbol\n" +
    "/// needs. A protocol error is a failure message, never an index panic.\n" +
    "fn arg(args : Array[@abi.Value], i : Int32) -> @abi.Value? {\n" +
    "  if i < args.length() {\n" +
    "    Some(args[i])\n" +
    "  } else {\n" +
    "    None\n" +
    "  }\n" +
    "}\n\n",
  )
  if needs_callback_buf {
    sb.write_string(render_callback_support())
  }
  // Decoders and encoders, only for the shapes this plan uses.
  //
  // Collections are structural: `Array[Map[String, Int]]` contributes three
  // shapes, and the recursion in `emit_*_helper` writes all three. A shape that
  // appears in two symbols is written once, which is why this dedupes by key
  // rather than by symbol.
  let args_used : Array[Wire] = []
  let outs_used : Array[Wire] = []
  let mut needs_handle_id = false
  for s in plan.syms {
    for w in s.params {
      collect_shapes(w, args_used)
    }
    collect_shapes(s.ret, outs_used)
    if s.kind == Setter {
      needs_handle_id = true
    }
  }
  if needs_handle_id {
    sb.write_string(
      "///|\n/// The raw id behind a handle argument, for a write that has to reach the\n" +
      "/// object rather than a copy of it.\n" +
      "fn arg_handle(args : Array[@abi.Value], i : Int32) -> Int32? {\n" +
      "  match arg(args, i) {\n" +
      "    Some(v) => v.as_handle()\n" +
      "    None => None\n" +
      "  }\n" +
      "}\n\n",
    )
  }
  // Two shapes can share one helper — `String` and `StringView` decode through
  // the same function — so the emitted set is keyed by helper name, not by
  // shape. Emitting twice would define the same function twice.
  let dec_written : Array[String] = []
  for w in args_used {
    let name = dec_name(w)
    if !dec_written.contains(name) {
      dec_written.push(name)
      // `Option[T]` decodes and encodes with the `T` helper, so the shape that
      // has to be written is the payload, not the wrapper. Emitting the wrapper
      // would claim the name and then write nothing, and the `T` that follows
      // in `args_used` would be skipped as a duplicate.
      emit_dec_helper(sb, base_wire(w))
    }
  }
  let enc_written : Array[String] = []
  for w in outs_used {
    let name = enc_name(w)
    if !enc_written.contains(name) {
      enc_written.push(name)
      emit_enc_helper(sb, base_wire(w))
    }
  }
  sb.write_string(render_release(plan))
  sb.write_string(render_dispatch(plan))
  sb.write_string(
    "///|\n/// Runs one frame. The host wrote `in_len` bytes into the input buffer first.\n" +
    "#export_name(\"mb_call\")\n" +
    "pub fn call(in_len : Int32) -> Int32 {\n" +
    "  if in_len < 4 || in_len > buffers.inbox.length() {\n" +
    "    return publish(@abi.encode_status(@abi.Failed(\"bad frame length\")))\n" +
    "  }\n" +
    "  let sym_len = read_u32(buffers.inbox, 0)\n" +
    "  if 4 + sym_len > in_len {\n" +
    "    return publish(@abi.encode_status(@abi.Failed(\"symbol overruns the frame\")))\n" +
    "  }\n" +
    "  let symbol = @utf8.decode_lossy(\n" +
    "    slice(buffers.inbox, 4, 4 + sym_len).exact_view(),\n" +
    "  )\n" +
    "  let payload = slice(buffers.inbox, 4 + sym_len, in_len)\n" +
    "  publish(@abi.encode_status(dispatch(symbol, payload)))\n" +
    "}\n",
  )
  sb.to_string()
}

///|
/// The count and the routing table: a release batch names a tag, and the tag
/// picks the table. Without this, an id would be ambiguous between two tables.
fn render_release(plan : Plan) -> String {
  if plan.handles.length() == 0 {
    return "///|\nfn live_total() -> Int32 {\n  0\n}\n\n" +
      "///|\nfn release_tag(_tag : Int32, _id : Int32) -> Bool {\n  false\n}\n\n"
  }
  let sb = StringBuilder()
  sb.write_string(
    "///|\n/// Objects the tables still hold.\nfn live_total() -> Int32 {\n",
  )
  let mut i = 0
  while i < plan.handles.length() {
    let h = plan.handles[i]
    if i == 0 {
      sb.write_string("  ")
    } else {
      sb.write_string(" + ")
    }
    sb.write_string("tables." + h.ty.key + ".live_count()")
    i = i + 1
  }
  sb.write_string("\n}\n\n")
  sb.write_string(
    "///|\n/// Releases one id from the table its tag names. The tag exists because an id\n" +
    "/// is only unique within one table.\n" +
    "fn release_tag(tag : Int32, id : Int32) -> Bool {\n" +
    "  match tag {\n",
  )
  for h in plan.handles {
    sb.write_string(
      "    " + h.tag.to_string() + " => tables." + h.ty.key + ".release(id)\n",
    )
  }
  sb.write_string("    _ => false\n  }\n}\n\n")
  sb.write_string(
    "///|\nfn release_pairs(items : Array[@abi.Value]) -> @abi.Status {\n" +
    "  let mut released = 0\n" +
    "  for item in items {\n" +
    "    let pair = match item.as_list() {\n" +
    "      Some(p) => p\n" +
    "      None => return @abi.Failed(\"abi.release wants [tag, id] pairs\")\n" +
    "    }\n" +
    "    if pair.length() != 2 {\n" +
    "      return @abi.Failed(\"abi.release wants [tag, id] pairs\")\n" +
    "    }\n" +
    "    let tag = match pair[0].as_int() {\n" +
    "      Some(n) => n\n" +
    "      None => return @abi.Failed(\"abi.release: the tag must be an int\")\n" +
    "    }\n" +
    "    let id = match pair[1].as_int() {\n" +
    "      Some(n) => n\n" +
    "      None => return @abi.Failed(\"abi.release: the id must be an int\")\n" +
    "    }\n" +
    "    if release_tag(tag, id) {\n" +
    "      released = released + 1\n" +
    "    }\n" +
    "  }\n" +
    "  @abi.Ok(@abi.Int(released))\n" +
    "}\n\n",
  )
  sb.to_string()
}

///|
fn render_dispatch(plan : Plan) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "///|\n/// The dispatcher. A symbol is\n" +
    "/// `<declaring package>::<function>` or\n" +
    "/// `<declaring package>::<Type>::<name>`, which is what the generated Python\n" +
    "/// module sends.\n" +
    "fn dispatch(symbol : String, payload : Bytes) -> @abi.Status {\n" +
    "  let args = @abi.decode(payload) catch {\n" +
    "    _ => return @abi.Failed(\"malformed argument frame\")\n" +
    "  }\n" +
    "  let argv = match args {\n" +
    "    @abi.List(items) => items\n" +
    "    _ => [args]\n" +
    "  }\n" +
    "  match symbol {\n",
  )
  for s in plan.syms {
    sb.write_string(render_arm(s))
  }
  sb.write_string(
    "    \"abi.release\" => match arg(argv, 0) {\n" +
    "      Some(v) => match v.as_list() {\n" +
    "        Some(items) => release_pairs(items)\n" +
    "        None => @abi.Failed(\"abi.release expects a list\")\n" +
    "      }\n" +
    "      None => @abi.Ok(@abi.Int(0))\n" +
    "    }\n" +
    "    \"abi.live\" => @abi.Ok(@abi.Int(live_total()))\n" +
    "    _ => @abi.Failed(\"unknown symbol \" + symbol)\n" +
    "  }\n" +
    "}\n\n",
  )
  sb.to_string()
}

///|
/// The package manifest that compiles the guest as a wasm library exporting its
/// memory under a fixed name.
pub fn render_guest_pkg(plan : Plan, abi : String) -> String {
  let imports : Array[String] = [abi, "moonbitlang/core/buffer"]
  push_unique(imports, "moonbitlang/core/encoding/utf8")
  if plan.handles.length() > 0 {
    push_unique(imports, "moonbitlang/core/ref")
  }
  for p in used_packages(plan) {
    push_unique(imports, p)
  }
  let sb = StringBuilder()
  sb.write_string("import {\n")
  for i in imports {
    sb.write_string("  \"" + i + "\",\n")
  }
  sb.write_string(
    "}\n\n" +
    "pkgtype(kind: \"foreign_library\")\n\n" +
    "// The host reads and writes linear memory directly, so the memory object\n" +
    "// needs a stable name and the heap must not start at zero: address 0 is a\n" +
    "// valid pointer, so it could not mean \"no buffer\".\n\n" +
    "options(\n" +
    "  link: {\n" +
    "    \"wasm\": { \"export-memory-name\": \"memory\", \"heap-start-address\": 4096 },\n" +
    "  },\n" +
    ")\n",
  )
  sb.to_string()
}

///|
/// Whether any symbol in the plan takes or returns a function.
fn plan_uses_callbacks(plan : Plan) -> Bool {
  let mut found = false
  for s in plan.syms {
    for w in s.params {
      if has_callback(w) {
        found = true
      }
    }
    if has_callback(s.ret) {
      found = true
    }
  }
  found
}

///|
fn has_callback(w : Wire) -> Bool {
  match w {
    WCall(_, _) => true
    WMaybe(inner) | WArr(inner) | WArrView(inner) => has_callback(inner)
    WMap(k, v) => has_callback(k) || has_callback(v)
    WRes(ok, err) => has_callback(ok) || has_callback(err)
    _ => false
  }
}

///|
/// The guest half of the callback channel.
///
/// A callback is an `Int32` id on the wire. Everything else — which Python
/// callable the id names, whether it raised — lives on the host side. The guest
/// only knows how to say "call number 3 with these arguments" and read the
/// answer back out of memory.
///
/// The import is the part that makes this work at all: because `mb_cb_invoke`
/// is a *wasm import*, the host function runs on the thread that is already
/// inside the guest, with the guest's stack intact. No coroutine, no replay, no
/// second thread.
fn render_callback_support() -> String {
  "///|\n" +
  "/// Calls back into the host, which owns the callable. The request is already\n" +
  "/// in the response buffer; the answer is written to `buffers.cb_out`.\n" +
  "///\n" +
  "/// Only the wasm build has a host to call. The generator itself runs on\n" +
  "/// JavaScript, and it compiles this package too, so the other target gets a\n" +
  "/// stub: nothing can call a callback without a guest instance.\n" +
  "#cfg(target=\"wasm\")\n" +
  "extern \"wasm\" fn mb_cb_invoke(cb_id : Int32, len : Int32) -> Int32 = \"env\" \"mb_cb_invoke\"\n\n" +
  "#cfg(not(target=\"wasm\"))\n" +
  "fn mb_cb_invoke(cb_id : Int32, len : Int32) -> Int32 {\n" +
  "  ignore(cb_id)\n" +
  "  ignore(len)\n" +
  "  0\n" +
  "}\n\n" +
  "///|\n" +
  "/// Hands the host a buffer to write a callback's result into, and returns it.\n" +
  "///\n" +
  "/// Exported because the host cannot allocate: it can only write into memory\n" +
  "/// the guest already owns, and it has to ask for that memory in the guest's\n" +
  "/// own allocator.\n" +
  "#export_name(\"mb_cb_buffer\")\n" +
  "pub fn cb_buffer(n : Int32) -> Bytes {\n" +
  "  if n > buffers.cb_out.length() {\n" +
  "    let mut size = if buffers.cb_out.length() > 0 { buffers.cb_out.length() } else { 256 }\n" +
  "    while size < n {\n" +
  "      size = size * 2\n" +
  "    }\n" +
  "    buffers.cb_out = Bytes::new(size)\n" +
  "  }\n" +
  "  buffers.cb_out\n" +
  "}\n\n" +
  "///|\n" +
  "/// Runs one Python callable and returns its value.\n" +
  "///\n" +
  "/// `None` means the host could not produce a value — it raised, or the answer\n" +
  "/// did not decode. The caller substitutes a default and lets the host re-raise\n" +
  "/// the original exception once the outer call returns, so the bad value is\n" +
  "/// never observed.\n" +
  "fn invoke_callback(id : Int32, args : Array[@abi.Value]) -> @abi.Value? {\n" +
  "  let sent = publish(@abi.encode(@abi.Value::List(args)))\n" +
  "  let got = mb_cb_invoke(id, sent)\n" +
  "  if got <= 0 {\n" +
  "    return None\n" +
  "  }\n" +
  "  let frame = slice(buffers.cb_out, 0, got)\n" +
  "  let status = try {\n" +
  "    Some(@abi.decode_status(frame))\n" +
  "  } catch {\n" +
  "    _ => None\n" +
  "  }\n" +
  "  match status {\n" +
  "    Some(@abi.Ok(v)) => Some(v)\n" +
  "    _ => None\n" +
  "  }\n" +
  "}\n\n"
}
