//! End-to-end tests: a full `.mbti` file in, an AST out.

///|
let sample =
  #|// Generated using `moon info`, DON'T EDIT IT
  #|package "acme/widgets"
  #|
  #|import {
  #|  "moonbitlang/core/builtin",
  #|  "moonbitlang/core/json",
  #|}
  #|
  #|// Values
  #|pub const MAX : Int = 1024
  #|
  #|#deprecated
  #|pub let version : String
  #|
  #|#callsite(autofill(loc))
  #|pub fn[T : Show] render(value : T, indent? : Int, loc~ : SourceLoc) -> String raise RenderError
  #|
  #|// Errors
  #|pub(all) suberror RenderError {
  #|  Bad(String)
  #|}
  #|
  #|// Types and methods
  #|pub(all) struct Widget {
  #|  id : Int
  #|  mut label : String
  #|}
  #|
  #|pub(all) struct Pair[A, B] {
  #|  first : A
  #|  second : B
  #|} derive(Eq, @builtin.ToJson)
  #|
  #|type Buffer
  #|
  #|pub type Fd = Int
  #|
  #|pub(all) enum Kind {
  #|  Plain
  #|  Fancy(String, mut extra~ : Int)
  #|}
  #|
  #|pub(open) trait Render {
  #|  render(Self) -> String
  #|  size(Self) -> Int = _
  #|}
  #|
  #|pub impl Render for Widget
  #|
  #|// Type aliases
  #|pub typealias Handle = Int
  #|
  #|// Traits
  #|pub using @builtin {type ArrayView as View}

///|
test "parse: header and imports" {
  let pkg = @mbti.parse(sample)
  assert_eq(pkg.name, "acme/widgets")
  assert_eq(pkg.imports, ["moonbitlang/core/builtin", "moonbitlang/core/json"])
}

///|
test "parse: declaration counts by kind" {
  let pkg = @mbti.parse(sample)
  assert_eq(pkg.count_kind("const"), 1)
  assert_eq(pkg.count_kind("let"), 1)
  assert_eq(pkg.count_kind("fn"), 1)
  assert_eq(pkg.count_kind("error"), 1)
  assert_eq(pkg.count_kind("struct"), 2)
  assert_eq(pkg.count_kind("type"), 1) // opaque Buffer
  assert_eq(pkg.count_kind("enum"), 1)
  assert_eq(pkg.count_kind("trait"), 1)
  assert_eq(pkg.count_kind("impl"), 1)
  // `pub type Fd = Int` is an alias too, not an opaque type.
  assert_eq(pkg.count_kind("alias"), 2)
  assert_eq(pkg.count_kind("using"), 1)
}

///|
test "parse: an unmodified opaque type is public" {
  // `.mbti` lists only the public surface, so `type Buffer` means "public, but
  // the representation is hidden". Treating it as private would drop the type
  // from generated stubs while every function still mentions it.
  let pkg = @mbti.parse(sample)
  for decl in pkg.decls {
    match decl {
      @mbti.Decl::Opaque(o) =>
        if o.name == "Buffer" {
          assert_eq(o.access, @mbti.ReadOnly)
        }
      _ => ()
    }
  }
}

///|
test "parse: const keeps its literal verbatim" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[0] {
    @mbti.Const(c) => {
      assert_eq(c.name, "MAX")
      assert_eq(c.value, "1024")
      assert_eq(c.ty, @mbti.Named(@mbti.QName::plain("Int"), []))
      assert_eq(c.access, @mbti.ReadOnly)
    }
    _ => fail("expected a const declaration first")
  }
}

///|
test "parse: attributes and generic bounds on a function" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[2] {
    @mbti.Func(f) => {
      assert_eq(f.name, "render")
      assert_eq(f.receiver, None)
      assert_eq(f.is_async, false)
      assert_eq(f.attrs.map(fn(a) { a.name }), ["callsite"])
      assert_eq(f.attrs[0].args, "autofill(loc)")
      assert_eq(f.generics[0].name, "T")
      assert_eq(f.generics[0].bounds, [@mbti.QName::plain("Show")])
      // value : T | indent? : Int | loc~ : SourceLoc
      assert_eq(f.params.length(), 3)
      assert_eq(f.params[0].name, Some("value"))
      assert_eq(f.params[1].kind, @mbti.Optional)
      assert_eq(f.params[2].kind, @mbti.Labeled)
      assert_eq(f.effect.raises, true)
      assert_eq(
        f.effect.error,
        Some(@mbti.Named(@mbti.QName::plain("RenderError"), [])),
      )
    }
    _ => fail("expected the function declaration")
  }
}

///|
test "parse: struct fields keep mutability" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[4] {
    @mbti.Struct(s) => {
      assert_eq(s.name, "Widget")
      assert_eq(s.fields.length(), 2)
      assert_eq(s.fields[0].is_mut, false)
      assert_eq(s.fields[1].is_mut, true)
      assert_eq(s.fields[1].name, "label")
    }
    _ => fail("expected the Widget struct")
  }
}

///|
test "parse: derive list after the closing brace" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[5] {
    @mbti.Struct(s) => {
      assert_eq(s.name, "Pair")
      assert_eq(s.generics.length(), 2)
      assert_eq(s.derives.map(fn(q) { q.to_string() }), [
        "Eq", "@builtin.ToJson",
      ])
    }
    _ => fail("expected the Pair struct")
  }
}

///|
test "parse: enum constructor with a labeled mutable field" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[8] {
    @mbti.Enum(e) => {
      assert_eq(e.name, "Kind")
      assert_eq(e.ctors.length(), 2)
      assert_eq(e.ctors[0].fields.length(), 0)
      let fancy = e.ctors[1]
      assert_eq(fancy.name, "Fancy")
      assert_eq(fancy.fields.length(), 2)
      assert_eq(fancy.fields[0].label, None)
      assert_eq(fancy.fields[1].label, Some(@mbti.Labeled))
      assert_eq(fancy.fields[1].is_mut, true)
    }
    _ => fail("expected the Kind enum")
  }
}

///|
test "parse: trait methods without fn and with a default body" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[9] {
    @mbti.Trait(t) => {
      assert_eq(t.name, "Render")
      assert_eq(t.access, @mbti.OpenTrait)
      assert_eq(t.methods.length(), 2)
      assert_eq(t.methods[0].name, "render")
      assert_eq(t.methods[1].name, "size")
    }
    _ => fail("expected the Render trait")
  }
}

///|
test "parse: impl binds a trait to a type" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[10] {
    @mbti.Impl(i) => {
      assert_eq(i.trait_name, @mbti.QName::plain("Render"))
      assert_eq(i.for_ty, @mbti.Named(@mbti.QName::plain("Widget"), []))
    }
    _ => fail("expected an impl declaration")
  }
}

///|
test "parse: re-export block" {
  let pkg = @mbti.parse(sample)
  match pkg.decls[12] {
    @mbti.Reexport(r) => {
      assert_eq(r.pkg, "@builtin")
      assert_eq(r.entries.length(), 1)
      assert_eq(r.entries[0].kind, "type")
      assert_eq(r.entries[0].name, "ArrayView")
      assert_eq(r.entries[0].as_name, Some("View"))
    }
    _ => fail("expected a using declaration")
  }
}

///|
test "parse_result: reports the position of a syntax error" {
  match @mbti.parse_result("package \"x\"\npub fn broken(\n") {
    Ok(_) => fail("expected a syntax error")
    Err(msg) =>
      // The message must name a line so a corpus failure is actionable.
      if !msg.contains("line 2") {
        fail(msg)
      }
  }
}

///|
test "parse_result: empty input is an error, not a silent empty package" {
  match @mbti.parse_result("") {
    Ok(_) => fail("expected an error for empty input")
    Err(msg) => if !msg.contains("package") { fail(msg) }
  }
}
