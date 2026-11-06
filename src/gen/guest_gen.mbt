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
/// The MoonBit type of a wire shape, with `?` stripped: the type a value is
/// unwrapped to before it is passed to the guest function.
fn base_decl(w : Wire) -> String {
  match w {
    WInt => "Int"
    WDouble => "Double"
    WBool => "Bool"
    WStr => "String"
    WStrView => "StringView"
    WUnit => "Unit"
    WHandle(t) => t.expr
    WMaybe(inner) => base_decl(inner)
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
/// The decoder for one argument shape, or `None` for `Unit`, which needs none.
fn arg_helper(w : Wire) -> String? {
  match w {
    WUnit => None
    WMaybe(inner) => arg_helper(inner)
    WInt => Some("arg_int")
    WDouble => Some("arg_double")
    WBool => Some("arg_bool")
    WStr => Some("arg_str")
    // A view is built at the call site, from a string this helper returns: a
    // view made inside the helper would borrow a value that dies with it.
    WStrView => Some("arg_str")
    WHandle(t) => Some("arg_" + t.key)
  }
}

///|
/// The encoder for one return shape. Every encoder takes a `T?`, so a plain `T`
/// and a `T?` are converted by the same call.
fn out_helper(w : Wire) -> String {
  match w {
    WMaybe(inner) => out_helper(inner)
    WInt => "out_int"
    WDouble => "out_double"
    WBool => "out_bool"
    WStr => "out_str"
    WStrView => "out_strview"
    WUnit => "out_unit"
    WHandle(t) => "out_" + t.key
  }
}

///|
/// How a decoded local is passed to the guest: a `StringView` parameter needs
/// the view built here, where its owner is still alive.
fn call_arg(w : Wire, v : String) -> String {
  match base_wire(w) {
    WStrView => v + "[:]"
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
      // argument is a protocol failure with a symbol name in it.
      let mut i = 0
      while i < sym.params.length() {
        let w = sym.params[i]
        match arg_helper(w) {
          None => ()
          Some(helper) =>
            match w {
              WMaybe(_) =>
                sb.write_string(
                  "      let " +
                  arg_var(i) +
                  " = " +
                  helper +
                  "(argv, " +
                  i.to_string() +
                  ")\n",
                )
              _ =>
                sb.write_string(
                  "      let " +
                  arg_var(i) +
                  " = match " +
                  helper +
                  "(argv, " +
                  i.to_string() +
                  ") {\n" +
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
        // A raised MoonBit error becomes a failure frame: the Python side turns
        // it into `MoonError`, which is the only error the ABI has.
        sb.write_string(
          "      let value = try {\n        " +
          call +
          "\n      } catch {\n        error => return @abi.Failed(error.to_string())\n      }\n",
        )
      } else {
        sb.write_string("      let value = " + call + "\n")
      }
      // Encoding can fail: a table that has run out of slots raises, and a
      // failure frame is a far better outcome than a panic the host cannot
      // attribute.
      // Every encoder takes a `T?`. A return that is already optional is
      // passed through; a plain one is wrapped, because MoonBit does not
      // coerce `T` into `T?` at a call.
      let argument = match sym.ret {
        WMaybe(_) => "value"
        _ => "Some(value)"
      }
      let encoded = "@abi.Ok(" + out_helper(sym.ret) + "(" + argument + "))"
      // Encoding a handle inserts into a table, which raises when the table is
      // full. A `try` around a body that cannot raise is a warning, so it is
      // only written where it can.
      let encoder_raises = match base_wire(sym.ret) {
        WHandle(_) => true
        _ => false
      }
      if encoder_raises {
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
  sb.write_string("    }\n")
  sb.to_string()
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
  let value_helper = match arg_helper(value_wire) {
    Some(h) => h
    None => "arg_int"
  }
  sb.write_string(
    "      let id = match arg_handle(argv, 0) {\n" +
    "        Some(v) => v\n" +
    "        None => return @abi.Failed(\"" +
    sym.symbol +
    ": bad argument 1\")\n" +
    "      }\n" +
    "      let value = match " +
    value_helper +
    "(argv, 1) {\n" +
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
/// The decoder for one argument shape, as source.
fn emit_arg_helper(sb : StringBuilder, w : Wire) -> Unit {
  let name = match arg_helper(w) {
    Some(n) => n
    None => return
  }
  match w {
    WInt =>
      sb.write_string(
        "///|\nfn " +
        name +
        "(args : Array[@abi.Value], i : Int32) -> Int? {\n" +
        "  match arg(args, i) {\n" +
        "    Some(v) => v.as_int()\n" +
        "    None => None\n" +
        "  }\n" +
        "}\n\n",
      )
    WDouble =>
      // A Python `int` is a perfectly good `Double`: the codec tags it as an
      // int, and refusing it here would make `f(1)` fail where `f(1.0)` works.
      sb.write_string(
        "///|\nfn " +
        name +
        "(args : Array[@abi.Value], i : Int32) -> Double? {\n" +
        "  match arg(args, i) {\n" +
        "    Some(v) =>\n" +
        "      match v.as_double() {\n" +
        "        Some(d) => Some(d)\n" +
        "        None =>\n" +
        "          match v.as_int() {\n" +
        "            Some(n) => Some(n.to_double())\n" +
        "            None => None\n" +
        "          }\n" +
        "      }\n" +
        "    None => None\n" +
        "  }\n" +
        "}\n\n",
      )
    WBool =>
      sb.write_string(
        "///|\nfn " +
        name +
        "(args : Array[@abi.Value], i : Int32) -> Bool? {\n" +
        "  match arg(args, i) {\n" +
        "    Some(v) => v.as_bool()\n" +
        "    None => None\n" +
        "  }\n" +
        "}\n\n",
      )
    WStr | WStrView =>
      sb.write_string(
        "///|\nfn " +
        name +
        "(args : Array[@abi.Value], i : Int32) -> String? {\n" +
        "  match arg(args, i) {\n" +
        "    Some(v) => v.as_string()\n" +
        "    None => None\n" +
        "  }\n" +
        "}\n\n",
      )
    WHandle(t) =>
      sb.write_string(
        "///|\n/// A handle from the host, resolved against the table for `" +
        t.expr +
        "`.\nfn " +
        name +
        "(args : Array[@abi.Value], i : Int32) -> " +
        t.expr +
        "? {\n" +
        "  match arg(args, i) {\n" +
        "    Some(v) =>\n" +
        "      match v.as_handle() {\n" +
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
        "  }\n" +
        "}\n\n",
      )
    WUnit | WMaybe(_) => ()
  }
}

///|
/// The encoder for one return shape, as source.
fn emit_out_helper(sb : StringBuilder, w : Wire) -> Unit {
  let name = out_helper(w)
  let decl = "fn " + name + "(v : " + base_decl(w) + "?) -> @abi.Value {\n"
  let head = "///|\n" + decl + "  match v {\n"
  let tail = "  }\n}\n\n"
  match w {
    WInt =>
      sb.write_string(
        head +
        "    Some(x) => @abi.Int(x)\n    None => @abi.Value::unit()\n" +
        tail,
      )
    WDouble =>
      sb.write_string(
        head +
        "    Some(x) => @abi.Double(x)\n    None => @abi.Value::unit()\n" +
        tail,
      )
    WBool =>
      sb.write_string(
        head +
        "    Some(x) => @abi.Bool(x)\n    None => @abi.Value::unit()\n" +
        tail,
      )
    WStr =>
      sb.write_string(
        head +
        "    Some(x) => @abi.Str(x)\n    None => @abi.Value::unit()\n" +
        tail,
      )
    WStrView =>
      // A view is borrowed from a value the caller owns; the host gets a copy.
      sb.write_string(
        head +
        "    Some(x) => @abi.Str(x.to_owned())\n    None => @abi.Value::unit()\n" +
        tail,
      )
    WUnit =>
      sb.write_string(
        "///|\nfn " +
        name +
        "(_v : Unit?) -> @abi.Value {\n  @abi.Value::unit()\n}\n\n",
      )
    WHandle(t) =>
      // `insert` raises when the table is full, and a full table is a real
      // outcome rather than a bug: the encoder is honest about it and every
      // caller runs inside a `try`.
      sb.write_string(
        "///|\nfn " +
        name +
        "(v : " +
        base_decl(w) +
        "?) -> @abi.Value raise {\n  match v {\n" +
        "    Some(x) => @abi.Handle(tables." +
        t.key +
        ".insert(@ref.Ref(x)))\n" +
        "    None => @abi.Value::unit()\n" +
        "  }\n}\n\n",
      )
    WMaybe(_) => ()
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
  sb.write_string(
    "///|\n/// The input buffer, owned by the guest so the host never has to know how a\n" +
    "/// MoonBit `Bytes` is laid out beyond one discovered offset.\n" +
    "priv struct Buffers {\n" +
    "  mut inbox : Bytes\n" +
    "}\n\n" +
    "///|\nlet buffers : Buffers = { inbox: Bytes::new(1024), }\n\n",
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
  // Decoders and encoders, only for the shapes this plan uses.
  let args_used : Array[Wire] = []
  let outs_used : Array[Wire] = []
  let mut needs_handle_id = false
  for s in plan.syms {
    for w in s.params {
      // `WStr` and `WStrView` share one decoder, so they must not both emit it.
      let base = match base_wire(w) {
        WStrView => WStr
        other => other
      }
      match arg_helper(base) {
        Some(_) => push_unique(args_used, base)
        None => ()
      }
    }
    push_unique(outs_used, base_wire(s.ret))
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
  for w in args_used {
    emit_arg_helper(sb, w)
  }
  for w in outs_used {
    emit_out_helper(sb, w)
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
