//! Declaration-level parsing and the public entry points.
//!
//! `moon info` prints exactly one declaration per line, and only `{ ... }`
//! bodies wrap. The parser therefore never needs to guess where a signature
//! ends: every declaration is required to finish on the line it started, which
//! turns a silently wrong parse into a positioned syntax error.

///|
/// Text form of a single token, used to reconstruct attribute arguments.
fn token_text(tok : Token) -> String {
  match tok.kind {
    Ident(s) => s
    Num(n) => n.to_string()
    Str(s) => "\"" + s + "\""
    Punct(s) => s
    Newline => " "
    Eof => ""
  }
}

///|
/// Non-raising check of a token's identifier text, usable inside conditions.
fn peek_is_ident(tok : Token, s : String) -> Bool {
  match tok.kind {
    Ident(i) => i == s
    _ => false
  }
}

///|
fn Parser::skip_newlines(self : Parser) -> Unit {
  while !self.at_eof() {
    match self.peek().kind {
      Newline => self.pos = self.pos + 1
      _ => break
    }
  }
}

///|
fn Parser::expect_ident(self : Parser, s : String) -> Unit raise ParseError {
  if self.at_ident(s) {
    ignore(self.advance())
  } else {
    raise unexpected(self.peek(), "`" + s + "`")
  }
}

///|
/// Joins the tokens in `[start, end)`.
fn Parser::render_range(self : Parser, start : Int32, end : Int32) -> String {
  let mut s = ""
  let mut i = start
  while i < end && i < self.pos {
    s = s + token_text(self.toks[i])
    i = i + 1
  }
  s
}

///|
/// Rejects trailing garbage: a declaration must end at the end of its line.
fn Parser::expect_line_end(self : Parser) -> Unit raise ParseError {
  match self.peek().kind {
    Newline | Eof => ()
    _ => raise unexpected(self.peek(), "end of line")
  }
}

///|
/// `#attr` or `#attr(arg, ...)`. Arguments are captured as raw text because
/// nothing downstream interprets them yet, but the printer must round-trip them.
fn Parser::parse_attr(self : Parser) -> Attr raise ParseError {
  self.expect_punct("#")
  let name = self.take_ident()
  let mut args = ""
  if self.at_punct("(") {
    let start = self.pos + 1
    let mut depth = 0
    while !self.at_eof() {
      if self.at_punct("(") {
        depth = depth + 1
      } else if self.at_punct(")") {
        depth = depth - 1
      }
      ignore(self.advance())
      if depth == 0 {
        break
      }
    }
    args = self.render_range(start, self.pos - 1)
  }
  { name, args, }
}

///|
/// `pub`, `pub(all)`, `priv`, or nothing.
fn Parser::parse_access(self : Parser) -> Access raise ParseError {
  if self.at_ident("pub") {
    ignore(self.advance())
    let has_modifier = match self.peek().kind {
      Punct(p) => p == "("
      _ => false
    }
    if has_modifier && peek_is_ident(self.peek_n(1), "all") {
      ignore(self.advance()) // `(`
      ignore(self.advance()) // `all`
      self.expect_punct(")")
      return Open
    }
    if has_modifier && peek_is_ident(self.peek_n(1), "open") {
      ignore(self.advance()) // `(`
      ignore(self.advance()) // `open`
      self.expect_punct(")")
      return OpenTrait
    }
    return ReadOnly
  }
  if self.at_ident("priv") {
    ignore(self.advance())
    return Private
  }
  Private
}

///|
/// True when the next non-newline token is `derive`. Some declarations put it
/// on the line after the closing brace instead of trailing it.
fn Parser::derive_follows(self : Parser) -> Bool {
  let mut i = self.pos
  while i < self.toks.length() {
    match self.toks[i].kind {
      Newline => i = i + 1
      _ => return peek_is_ident(self.toks[i], "derive")
    }
  }
  false
}

///|
/// A struct field or a constructor field.
///
/// Handles the four shapes that occur in practice: `priv x : T`,
/// `mut x : T`, `x : T`, and a bare positional type.
fn Parser::parse_field(self : Parser) -> Field raise ParseError {
  let mut field_access = Open
  if self.at_ident("priv") {
    ignore(self.advance())
    field_access = Private
  }
  let mut is_mut = false
  if self.at_ident("mut") {
    ignore(self.advance())
    is_mut = true
  }
  match self.named_param_kind() {
    Some(kind) => {
      let name = self.take_ident()
      ignore(self.advance()) // `?` or `~`
      ignore(self.advance()) // `:`
      {
        name,
        ty: self.parse_type(),
        access: field_access,
        is_mut,
        label: Some(kind),
      }
    }
    None => {
      let is_named = match (self.peek().kind, self.peek_n(1).kind) {
        (Ident(_), Punct(p)) => p == ":"
        _ => false
      }
      if is_named {
        let name = self.take_ident()
        ignore(self.advance()) // `:`
        {
          name,
          ty: self.parse_type(),
          access: field_access,
          is_mut,
          label: None,
        }
      } else {
        {
          name: "",
          ty: self.parse_type(),
          access: field_access,
          is_mut,
          label: None,
        }
      }
    }
  }
}

///|
/// `pub const PI : Double = 0x3.243F6A8885A308CA8A54`. The value is an
/// expression, so it is captured verbatim up to the end of the line.
fn Parser::parse_const(
  self : Parser,
  access : Access,
  attrs : Array[Attr],
) -> ConstDecl raise ParseError {
  self.expect_ident("const")
  let name = self.take_ident()
  self.expect_punct(":")
  let ty = self.parse_type()
  self.expect_punct("=")
  let start = self.pos
  while !self.at_eof() {
    match self.peek().kind {
      Newline => break
      _ => ignore(self.advance())
    }
  }
  { name, ty, value: self.render_range(start, self.pos), attrs, access, }
}

///|
/// `derive(Show, @debug.Debug)`.
fn Parser::parse_derives(self : Parser) -> Array[QName] raise ParseError {
  let out : Array[QName] = []
  if self.at_ident("derive") {
    ignore(self.advance())
    self.expect_punct("(")
    while !self.at_punct(")") {
      out.push(self.parse_qname())
      if self.at_punct(",") {
        ignore(self.advance())
      } else {
        break
      }
    }
    self.expect_punct(")")
  }
  out
}

///|
/// `pub fn [T] name(params) -> Ret raise?` and `Type::method` variants.
fn Parser::parse_fn(
  self : Parser,
  access : Access,
  attrs : Array[Attr],
) -> FuncDecl raise ParseError {
  let mut is_async = false
  if self.at_ident("async") {
    ignore(self.advance())
    is_async = true
  }
  // Trait bodies may omit the `fn` keyword: `trait P { pretty(Self) -> Doc }`.
  if self.at_ident("fn") {
    ignore(self.advance())
  }
  let generics = self.parse_generics()
  let mut receiver : QName? = None
  let mut name = ""
  // `&Logger::write` — a method on a borrowed (trait-object) receiver.
  if self.at_punct("&") {
    ignore(self.advance())
  }
  if self.at_punct("@") {
    // `@pkg.Type::method`
    let q = self.parse_qualified_name()
    self.expect_punct("::")
    receiver = Some(q)
    name = self.take_ident()
  } else {
    let first = self.take_ident()
    if self.at_punct("::") {
      ignore(self.advance())
      receiver = Some(QName::plain(first))
      name = self.take_ident()
    } else {
      name = first
    }
  }
  self.expect_punct("(")
  let params : Array[Param] = []
  while !self.at_punct(")") {
    params.push(self.parse_param())
    if self.at_punct(",") {
      ignore(self.advance())
    } else {
      break
    }
  }
  self.expect_punct(")")
  let mut ret = Unit
  if self.at_punct("->") {
    ignore(self.advance())
    ret = self.parse_type()
  }
  let effect = self.parse_effect()
  { name, is_async, receiver, generics, params, ret, effect, attrs, access, }
}

///|
fn Parser::parse_value(
  self : Parser,
  access : Access,
  attrs : Array[Attr],
) -> ValueDecl raise ParseError {
  self.expect_ident("let")
  let name = self.take_ident()
  self.expect_punct(":")
  let ty = self.parse_type()
  { name, ty, attrs, access, }
}

///|
fn Parser::parse_struct(
  self : Parser,
  access : Access,
  attrs : Array[Attr],
) -> StructDecl raise ParseError {
  self.expect_ident("struct")
  let name = self.take_ident()
  let generics = self.parse_generics()
  let fields : Array[Field] = []
  if self.at_punct("(") {
    ignore(self.advance())
    while !self.at_punct(")") {
      fields.push(self.parse_field())
      if self.at_punct(",") {
        ignore(self.advance())
      } else {
        break
      }
    }
    self.expect_punct(")")
  } else if self.at_punct("{") {
    ignore(self.advance())
    while true {
      self.skip_newlines()
      if self.at_punct("}") {
        break
      }
      fields.push(self.parse_field())
      if self.at_punct(",") {
        ignore(self.advance())
      }
    }
    self.expect_punct("}")
  }
  if self.derive_follows() {
    self.skip_newlines()
  }
  let derives = self.parse_derives()
  {
    name,
    generics,
    fields,
    // `pub struct X { }` in an interface dump always hides its fields.
    has_hidden_fields: fields.length() == 0 && access == ReadOnly,
    derives,
    attrs,
    access,
  }
}

///|
fn Parser::parse_enum(
  self : Parser,
  keyword : String,
  access : Access,
  attrs : Array[Attr],
) -> EnumDecl raise ParseError {
  self.expect_ident(keyword)
  let name = self.take_ident()
  let generics = self.parse_generics()
  let ctors : Array[Ctor] = []
  if self.at_punct("{") {
    ignore(self.advance())
    while true {
      self.skip_newlines()
      if self.at_punct("}") {
        break
      }
      let ctor_name = self.take_ident()
      let ctor_fields : Array[Field] = []
      if self.at_punct("(") {
        ignore(self.advance())
        while !self.at_punct(")") {
          ctor_fields.push(self.parse_field())
          if self.at_punct(",") {
            ignore(self.advance())
          } else {
            break
          }
        }
        self.expect_punct(")")
      }
      ctors.push({ name: ctor_name, fields: ctor_fields, })
      if self.at_punct(",") {
        ignore(self.advance())
      }
    }
    self.expect_punct("}")
  }
  if self.derive_follows() {
    self.skip_newlines()
  }
  let derives = self.parse_derives()
  { name, generics, ctors, derives, attrs, access, }
}

///|
fn Parser::parse_trait(
  self : Parser,
  access : Access,
  attrs : Array[Attr],
) -> TraitDecl raise ParseError {
  self.expect_ident("trait")
  let name = self.take_ident()
  let generics = self.parse_generics()
  let supers : Array[QName] = []
  if self.at_punct(":") {
    ignore(self.advance())
    while true {
      supers.push(self.parse_qname())
      if self.at_punct("+") {
        ignore(self.advance())
      } else {
        break
      }
    }
  }
  let methods : Array[FuncDecl] = []
  if self.at_punct("{") {
    ignore(self.advance())
    while true {
      self.skip_newlines()
      if self.at_punct("}") {
        break
      }
      let method_attrs : Array[Attr] = []
      while self.at_punct("#") {
        method_attrs.push(self.parse_attr())
        self.skip_newlines()
      }
      methods.push(self.parse_fn(Private, method_attrs))
      // A trait method may ship a default implementation, whose body the
      // interface dump elides as `= _`.
      if self.at_punct("=") {
        ignore(self.advance())
        ignore(self.advance()) // `_`
      }
      self.expect_line_end()
    }
    self.expect_punct("}")
  }
  { name, generics, supers, methods, attrs, access, }
}

///|
fn Parser::parse_impl(
  self : Parser,
  attrs : Array[Attr],
) -> ImplDecl raise ParseError {
  self.expect_ident("impl")
  ignore(self.parse_generics())
  let trait_name = self.parse_qname()
  let trait_args = self.parse_type_args()
  self.expect_ident("for")
  let for_ty = self.parse_type()
  { trait_name, trait_args, for_ty, attrs, }
}

///|
fn Parser::parse_using(
  self : Parser,
  attrs : Array[Attr],
) -> ReexportDecl raise ParseError {
  ignore(attrs)
  self.expect_ident("using")
  self.expect_punct("@")
  let pkg = self.take_ident()
  self.expect_punct("{")
  let entries : Array[ReexportEntry] = []
  while true {
    self.skip_newlines()
    if self.at_punct("}") {
      break
    }
    let kind = self.take_ident()
    let name = self.take_ident()
    let mut as_name : String? = None
    if self.at_ident("as") {
      ignore(self.advance())
      as_name = Some(self.take_ident())
    }
    entries.push({ kind, name, as_name, })
    if self.at_punct(",") {
      ignore(self.advance())
    }
  }
  self.expect_punct("}")
  { pkg: "@" + pkg, entries, }
}

///|
/// Parses one declaration, including any preceding attributes.
fn Parser::parse_decl(self : Parser) -> Decl raise ParseError {
  let attrs : Array[Attr] = []
  while true {
    self.skip_newlines()
    if self.at_punct("#") {
      attrs.push(self.parse_attr())
    } else {
      break
    }
  }
  self.skip_newlines()
  let access = self.parse_access()
  let decl = if self.at_ident("fn") || self.at_ident("async") {
    Decl::Func(self.parse_fn(access, attrs))
  } else if self.at_ident("let") {
    Decl::Value(self.parse_value(access, attrs))
  } else if self.at_ident("const") {
    Decl::Const(self.parse_const(access, attrs))
  } else if self.at_ident("struct") {
    Decl::Struct(self.parse_struct(access, attrs))
  } else if self.at_ident("enum") {
    Decl::Enum(self.parse_enum("enum", access, attrs))
  } else if self.at_ident("suberror") || self.at_ident("error") {
    let keyword = if self.at_ident("suberror") { "suberror" } else { "error" }
    Decl::Error(self.parse_enum(keyword, access, attrs))
  } else if self.at_ident("trait") {
    Decl::Trait(self.parse_trait(access, attrs))
  } else if self.at_ident("impl") {
    Decl::Impl(self.parse_impl(attrs))
  } else if self.at_ident("typealias") {
    ignore(self.advance())
    let name = self.take_ident()
    let generics = self.parse_generics()
    self.expect_punct("=")
    let target = self.parse_type()
    Decl::Alias({ name, generics, target, access, attrs, })
  } else if self.at_ident("using") {
    Decl::Reexport(self.parse_using(attrs))
  } else if self.at_ident("type") {
    ignore(self.advance())
    let name = self.take_ident()
    let generics = self.parse_generics()
    if self.at_punct("=") {
      // `pub type Fd = Int` — an alias written with `type`, not `typealias`.
      ignore(self.advance())
      let target = self.parse_type()
      Decl::Alias({ name, generics, target, access, attrs, })
    } else {
      if self.derive_follows() {
        self.skip_newlines()
      }
      let derives = self.parse_derives()
      // `.mbti` only ever lists the public surface, and it prints a public
      // opaque type without a modifier: `type Uuid derive(Eq)`. A missing
      // modifier therefore means "public but representation hidden", not
      // "private" — a private type would not appear in the dump at all.
      let opaque_access = if access == Private { ReadOnly } else { access }
      Decl::Opaque({ name, generics, derives, access: opaque_access, attrs, })
    }
  } else {
    raise unexpected(self.peek(), "a declaration")
  }
  self.expect_line_end()
  decl
}

///|
fn Parser::parse_package(self : Parser) -> Package raise ParseError {
  self.skip_newlines()
  self.expect_ident("package")
  let name = match self.peek().kind {
    Str(s) => {
      ignore(self.advance())
      s
    }
    _ => raise unexpected(self.peek(), "a package name string")
  }
  let imports : Array[String] = []
  while true {
    self.skip_newlines()
    if !self.at_ident("import") {
      break
    }
    ignore(self.advance())
    // Current dumps use `import { ... }`, older ones `import( ... )`.
    let close = if self.at_punct("(") { ")" } else { "}" }
    if close == ")" {
      self.expect_punct("(")
    } else {
      self.expect_punct("{")
    }
    while true {
      self.skip_newlines()
      if self.at_punct(close) {
        break
      }
      match self.peek().kind {
        Str(s) => {
          ignore(self.advance())
          imports.push(s)
        }
        _ => raise unexpected(self.peek(), "a module path string")
      }
      if self.at_punct(",") {
        ignore(self.advance())
      }
    }
    self.expect_punct(close)
  }
  let decls : Array[Decl] = []
  while true {
    self.skip_newlines()
    if self.at_eof() {
      break
    }
    decls.push(self.parse_decl())
  }
  { name, imports, decls, }
}

///|
/// Parses a whole `.mbti` file. Raises `ParseError` with the position of the
/// first token that does not fit the grammar.
pub fn parse(src : String) -> Package raise ParseError {
  Parser::new(tokenize(src)).parse_package()
}

///|
/// Non-raising wrapper used by batch tools that must keep going after a
/// malformed file.
pub fn parse_result(src : String) -> Result[Package, String] {
  Ok(parse(src)) catch {
    ParseError(msg) => Err(msg)
  }
}
