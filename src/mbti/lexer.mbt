//! Lexer for `.mbti` interface files.
//!
//! `moon info` emits one line per declaration, with `{ ... }` bodies indented
//! by two spaces. The lexer therefore keeps newlines as significant tokens:
//! the parser uses them as declaration terminators.
//!
//! The input is scanned bytewise. Every structural character of the format is
//! ASCII, and non-ASCII bytes only ever occur inside identifiers (MoonBit
//! allows CJK labels) or string literals, both of which are copied verbatim.
//! That keeps the scanner free of per-character allocation for identifiers.

///|
/// A lexical token together with its 1-based source position.
pub(all) struct Token {
  kind : Tok
  line : Int32
  col : Int32
} derive(Debug, Eq)

///|

///|
/// Token kinds produced by `tokenize`.
pub(all) enum Tok {
  /// Identifier or keyword; the parser decides which by text.
  Ident(String)
  /// Decimal integer literal.
  Num(Int32)
  /// String literal, already unescaped.
  Str(String)
  /// Punctuation, including the two byte sequences `->`, `=>` and `..`.
  Punct(String)
  /// Statement separator: keeps declarations one-per-line.
  Newline
  /// End of input.
  Eof
} derive(Debug, Eq)

///|

///|

///|
fn is_digit(c : Int32) -> Bool {
  c >= 48 && c <= 57
}

///|
/// MoonBit identifiers may start with `_`, an ASCII letter, or any non-ASCII
/// code point (CJK labels are legal), so every byte >= 0x80 continues an
/// identifier.
fn is_ident_start(c : Int32) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
}

///|
fn is_ident_cont(c : Int32) -> Bool {
  is_ident_start(c) || is_digit(c) || c == 39 // ' as in x'
}

///|
fn ascii_str(c : Int32) -> String {
  c.unsafe_to_char().to_string()
}

///|
/// Decodes the UTF-8 byte range `[start, end)` into a `String`.
/// `Bytes::to_unchecked_string` is *not* usable here: its offsets are UTF-16
/// code units, which silently produces garbage on byte offsets.
fn slice_str(b : Bytes, start : Int32, end : Int32) -> String {
  let view = b.exact_view(start~, end~)
  @utf8.decode(view) catch {
    _ => @utf8.decode_lossy(view)
  }
}

///|
fn parse_decimal(digits : StringView) -> Int32 {
  let mut acc = 0
  for ch in digits {
    let d = ch.to_int() - 48
    if d >= 0 && d <= 9 {
      acc = acc * 10 + d
    }
  }
  acc
}

///|
/// Tokenizes a whole `.mbti` file. Never fails: unknown bytes become
/// single-character `Punct` tokens so the parser can report a positioned
/// syntax error instead of a lexer crash.
pub fn tokenize(src : String) -> Array[Token] {
  let bytes = @utf8.encode(src)
  let n = bytes.length()
  let out : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut col = 1
  while i < n {
    let c = bytes.at(i).to_int()
    if c == 10 {
      out.push({ kind: Newline, line, col, })
      i = i + 1
      line = line + 1
      col = 1
    } else if c == 32 || c == 9 || c == 13 {
      i = i + 1
      col = col + 1
    } else if c == 47 && i + 1 < n && bytes.at(i + 1).to_int() == 47 {
      // `//` line comment: dropped, the newline itself is kept.
      while i < n && bytes.at(i).to_int() != 10 {
        i = i + 1
        col = col + 1
      }
    } else if c == 34 {
      let start_line = line
      let start_col = col
      i = i + 1
      col = col + 1
      let content_start = i
      let mut escaped = false
      while i < n {
        let b = bytes.at(i).to_int()
        if b == 92 {
          escaped = true
          i = i + 2
          col = col + 2
        } else if b == 34 {
          break
        } else if b == 10 {
          // Unterminated string: stop at the line end, let the parser complain.
          break
        } else {
          i = i + 1
          col = col + 1
        }
      }
      let content_end = if i <= n { i } else { n }
      let raw = slice_str(bytes, content_start, content_end)
      if i < n && bytes.at(i).to_int() == 34 {
        i = i + 1
        col = col + 1
      }
      out.push({
        kind: Str(if escaped { unescape(raw) } else { raw }),
        line: start_line,
        col: start_col,
      })
    } else if is_ident_start(c) {
      let start = i
      let start_col = col
      while i < n && is_ident_cont(bytes.at(i).to_int()) {
        i = i + 1
        col = col + 1
      }
      out.push({
        kind: Ident(slice_str(bytes, start, i)),
        line,
        col: start_col,
      })
    } else if is_digit(c) {
      let start = i
      let start_col = col
      while i < n && is_digit(bytes.at(i).to_int()) {
        i = i + 1
        col = col + 1
      }
      let text = slice_str(bytes, start, i)
      out.push({ kind: Num(parse_decimal(text)), line, col: start_col, })
    } else {
      let start_col = col
      let next = if i + 1 < n { bytes.at(i + 1).to_int() } else { -1 }
      let text = if (c == 45 && next == 62) ||
        (c == 61 && next == 62) ||
        (c == 46 && next == 46) ||
        (c == 58 && next == 58) {
        i = i + 2
        col = col + 2
        ascii_str(c) + ascii_str(next)
      } else {
        i = i + 1
        col = col + 1
        ascii_str(c)
      }
      out.push({ kind: Punct(text), line, col: start_col, })
    }
  }
  out.push({ kind: Eof, line, col, })
  out
}

///|
/// Resolves the handful of escapes that can appear in `.mbti` attribute and
/// documentation strings. Unknown escapes keep the escaped byte, matching the
/// lenient behaviour of the scanner.
fn unescape(raw : String) -> String {
  let bytes = @utf8.encode(raw)
  let n = bytes.length()
  let mut out = ""
  let mut i = 0
  while i < n {
    let c = bytes.at(i).to_int()
    if c == 92 && i + 1 < n {
      let esc = bytes.at(i + 1).to_int()
      out = out +
        (if esc == 110 {
          "\n"
        } else if esc == 116 {
          "\t"
        } else if esc == 114 {
          "\r"
        } else {
          ascii_str(esc)
        })
      i = i + 2
    } else {
      out = out + slice_str(bytes, i, i + 1)
      i = i + 1
    }
  }
  out
}
