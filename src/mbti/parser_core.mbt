//! Recursive-descent parser for `.mbti` interface files.
//!
//! The grammar is a strict subset of MoonBit's signature syntax: no
//! expressions, no function bodies, no patterns. Declarations are terminated by
//! a newline and only `{ ... }` bodies may span lines, which is exactly how
//! `moon info` formats its output.

///|
/// A syntax error carrying the 1-based line and column of the offending token.
pub suberror ParseError {
  ParseError(String)
}

///|
/// Human-readable description of a token, used in error messages.
fn describe(tok : Token) -> String {
  match tok.kind {
    Ident(s) => "identifier `" + s + "`"
    Num(n) => "number " + n.to_string()
    Str(s) => "string \"" + s + "\""
    Punct(s) => "`" + s + "`"
    Newline => "end of line"
    Eof => "end of file"
  }
}

///|
/// The error raised when a token does not match the grammar. Exposed so the
/// caller sees the same wording as `moon test`.
pub fn unexpected(tok : Token, expected : String) -> ParseError {
  ParseError(
    "line " +
    tok.line.to_string() +
    ":" +
    tok.col.to_string() +
    ": expected " +
    expected +
    ", found " +
    describe(tok),
  )
}

///|
/// A token cursor with one-token lookahead helpers.
///
/// Only `pos` is mutable: the token array is fully materialised by the lexer,
/// so the parser never needs to hold a reference into the source text.
priv struct Parser {
  toks : Array[Token]
  mut pos : Int32
}

///|
fn Parser::new(toks : Array[Token]) -> Parser {
  { toks, pos: 0, }
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.toks[self.pos]
}

///|
fn Parser::peek_n(self : Parser, n : Int32) -> Token {
  let i = self.pos + n
  if i < self.toks.length() {
    self.toks[i]
  } else {
    self.toks[self.toks.length() - 1]
  }
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  match self.peek().kind {
    Eof => true
    _ => false
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let tok = self.peek()
  if !self.at_eof() {
    self.pos = self.pos + 1
  }
  tok
}

///|
fn Parser::at_punct(self : Parser, s : String) -> Bool {
  match self.peek().kind {
    Punct(p) => p == s
    _ => false
  }
}

///|
fn Parser::at_ident(self : Parser, s : String) -> Bool {
  match self.peek().kind {
    Ident(i) => i == s
    _ => false
  }
}

///|
fn Parser::expect_punct(self : Parser, s : String) -> Unit raise ParseError {
  if self.at_punct(s) {
    ignore(self.advance())
  } else {
    raise unexpected(self.peek(), "`" + s + "`")
  }
}

///|
fn Parser::take_ident(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(s) => {
      ignore(self.advance())
      s
    }
    _ => raise unexpected(self.peek(), "an identifier")
  }
}

///|
/// `true` when the current token can begin a type expression. Used to decide
/// whether `raise` carries an error type.
fn Parser::starts_type(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(_) => true
    Punct(p) => p == "(" || p == "&" || p == "@"
    _ => false
  }
}

///|
/// One path segment of a package path. Registry user names may contain `-`
/// (`@moonbit-community/...`), which the lexer splits into three tokens.
fn Parser::take_path_segment(self : Parser) -> String raise ParseError {
  let mut seg = self.take_ident()
  while self.at_punct("-") {
    ignore(self.advance())
    seg = seg + "-" + self.take_ident()
  }
  seg
}

///|
/// Qualified name after `@`: `@builtin.ToJson`. The `@` is kept in the stored
/// package string so the printer can reproduce the source exactly.
fn Parser::parse_qualified_name(self : Parser) -> QName raise ParseError {
  self.expect_punct("@")
  // Package paths may be nested: `@moonbitlang/core/hashmap.HashMap`.
  let mut pkg = self.take_path_segment()
  while self.at_punct("/") {
    ignore(self.advance())
    pkg = pkg + "/" + self.take_path_segment()
  }
  self.expect_punct(".")
  let name = self.take_ident()
  QName::qualified("@" + pkg, name)
}

///|
/// A name that may or may not be package-qualified.
fn Parser::parse_qname(self : Parser) -> QName raise ParseError {
  if self.at_punct("@") {
    self.parse_qualified_name()
  } else {
    QName::plain(self.take_ident())
  }
}

///|
/// `[Int, String]` type application. Returns an empty array when absent.
fn Parser::parse_type_args(self : Parser) -> Array[TypeExpr] raise ParseError {
  let out : Array[TypeExpr] = []
  if self.at_punct("[") {
    ignore(self.advance())
    while !self.at_punct("]") {
      out.push(self.parse_type())
      if self.at_punct(",") {
        ignore(self.advance())
      } else {
        break
      }
    }
    self.expect_punct("]")
  }
  out
}

///|
/// A type expression: `Int`, `Array[Int?]`, `(T) -> Bool raise?`, `&Show`.
fn Parser::parse_type(self : Parser) -> TypeExpr raise ParseError {
  let mut base = self.parse_type_base()
  // `T??` does occur: `Option::flatten(T??) -> T?` in the standard library.
  while self.at_punct("?") {
    ignore(self.advance())
    base = Optional(base)
  }
  base
}

///|
fn Parser::parse_type_base(self : Parser) -> TypeExpr raise ParseError {
  if self.at_punct("&") {
    ignore(self.advance())
    return Borrowed(self.parse_type())
  }
  // `async () -> String?`: the annotation belongs to the function type that
  // follows, so parse it and wrap the result.
  if self.at_ident("async") {
    ignore(self.advance())
    return Async(self.parse_type())
  }
  if self.at_punct("(") {
    return self.parse_paren_type()
  }
  if self.at_punct("@") {
    let q = self.parse_qualified_name()
    let args = self.parse_type_args()
    return Named(q, args)
  }
  match self.peek().kind {
    Ident(name) => {
      ignore(self.advance())
      if name == "Unit" {
        return Unit
      }
      if name == "Self" {
        return SelfType(self.parse_type_args())
      }
      Named(QName::plain(name), self.parse_type_args())
    }
    _ => raise unexpected(self.peek(), "a type")
  }
}

///|
/// Parses `( ... )`, which is a tuple, a parenthesised type, the unit type, or
/// the parameter list of a function type depending on what follows.
fn Parser::parse_paren_type(self : Parser) -> TypeExpr raise ParseError {
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
  if self.at_punct("->") {
    ignore(self.advance())
    let ret = self.parse_type()
    let effect = self.parse_effect()
    return Func(params, ret, effect)
  }
  if params.length() == 0 {
    return Unit
  }
  if params.length() == 1 {
    return params[0].ty
  }
  Tuple(params.map(fn(p) { p.ty }))
}

///|
/// Detects the `name? : T` and `name~ : T` forms. A bare `T?` parameter is a
/// positional optional type, not a named one, which the third token rules out.
fn Parser::named_param_kind(self : Parser) -> ParamKind? {
  match (self.peek().kind, self.peek_n(1).kind, self.peek_n(2).kind) {
    (Ident(_), Punct("?"), Punct(":")) => Some(Optional)
    (Ident(_), Punct("~"), Punct(":")) => Some(Labeled)
    _ => None
  }
}

///|
fn Parser::parse_param(self : Parser) -> Param raise ParseError {
  match self.named_param_kind() {
    Some(kind) => {
      let name = self.take_ident()
      ignore(self.advance()) // `?` or `~`
      ignore(self.advance()) // `:`
      { kind, name: Some(name), ty: self.parse_type(), }
    }
    None => {
      // `x : T` — a positional parameter that still has a name. Rare in dumps
      // but legal, and useful for generated code.
      let is_named = match (self.peek().kind, self.peek_n(1).kind) {
        (Ident(_), Punct(p)) => p == ":"
        _ => false
      }
      if is_named {
        let name = self.take_ident()
        ignore(self.advance()) // `:`
        { kind: Positional, name: Some(name), ty: self.parse_type(), }
      } else {
        { kind: Positional, name: None, ty: self.parse_type(), }
      }
    }
  }
}

///|
/// Parses the effect list: `raise`, `raise?`, `raise Foo`, `noraise`,
/// `nocancel`, possibly joined with `+`.
fn Parser::parse_effect(self : Parser) -> Effect raise ParseError {
  let mut raises = false
  let mut raises_may = false
  let mut no_raise = false
  let mut no_cancel = false
  let mut error : TypeExpr? = None
  while true {
    if self.at_ident("raise") {
      ignore(self.advance())
      if self.at_punct("?") {
        ignore(self.advance())
        raises_may = true
      } else {
        raises = true
      }
      if self.starts_type() {
        error = Some(self.parse_type())
      }
    } else if self.at_ident("noraise") {
      ignore(self.advance())
      no_raise = true
    } else if self.at_ident("nocancel") {
      ignore(self.advance())
      no_cancel = true
    } else {
      break
    }
    if self.at_punct("+") {
      ignore(self.advance())
    } else {
      break
    }
  }
  { raises, raises_may, no_raise, no_cancel, error, }
}

///|
/// `[T, A : Compare + Show, U = Int]`. Empty when the declaration is not
/// generic.
fn Parser::parse_generics(
  self : Parser,
) -> Array[GenericParam] raise ParseError {
  let out : Array[GenericParam] = []
  if self.at_punct("[") {
    ignore(self.advance())
    while !self.at_punct("]") {
      let name = self.take_ident()
      let bounds : Array[QName] = []
      let mut default : TypeExpr? = None
      if self.at_punct(":") {
        ignore(self.advance())
        while true {
          bounds.push(self.parse_qname())
          if self.at_punct("+") {
            ignore(self.advance())
          } else {
            break
          }
        }
      }
      if self.at_punct("=") {
        ignore(self.advance())
        default = Some(self.parse_type())
      }
      out.push({ name, bounds, default, })
      if self.at_punct(",") {
        ignore(self.advance())
      } else {
        break
      }
    }
    self.expect_punct("]")
  }
  out
}
