//! Command-line driver for the `.mbti` parser.
//!
//! Reads the interface files given on the command line, parses each of them and
//! reports a per-file summary plus an aggregate pass rate. It is the harness
//! used to prove the parser handles real-world interfaces, and the exit code is
//! non-zero as soon as one file fails, so it can gate CI.
//!
//! The executable currently targets the JavaScript backend because that is the
//! one backend available without a C toolchain; `read_text_file` is the single
//! host-specific call in the whole program.

///|
/// Reads a file as UTF-8. Returns the empty string when the path is missing or
/// unreadable, which the caller reports as an error.
#cfg(target="js")
extern "js" fn read_text_file(path : String) -> String = "path => { try { return require('fs').readFileSync(path, 'utf8') } catch (e) { return '' } }"

///|
/// Non-JS backends cannot read the filesystem here, so every path reports as
/// unreadable. The wasm build is only used for type-checking the package.
#cfg(not(target="js"))
fn read_text_file(path : String) -> String {
  ignore(path)
  ""
}

///|
#cfg(target="js")
extern "js" fn set_exit_code(code : Int32) -> Unit = "code => { process.exitCode = code }"

///|
#cfg(not(target="js"))
fn set_exit_code(code : Int32) -> Unit {
  ignore(code)
}

///|
/// Aggregate counters over a corpus run.
priv struct Tally {
  mut files : Int32
  mut passed : Int32
  mut failed : Int32
  mut decls : Int32
}

///|
fn Tally::new() -> Tally {
  { files: 0, passed: 0, failed: 0, decls: 0, }
}

///|
fn pad_left(s : String, width : Int32) -> String {
  let mut out = s
  while out.length() < width {
    out = " " + out
  }
  out
}

///|
fn pad_right(s : String, width : Int32) -> String {
  let mut out = s
  while out.length() < width {
    out = out + " "
  }
  out
}

///|
/// One decimal place, without depending on float formatting options.
fn format_rate(rate : Double) -> String {
  let scaled = (rate * 10.0).round().to_int()
  (scaled / 10).to_string() + "." + (scaled % 10).to_string()
}

///|
fn main {
  let args = @env.args()
  let mut quiet = false
  let files : Array[String] = []
  let mut i = 2 // argv[0] is the node binary, argv[1] is this script
  while i < args.length() {
    let arg = args[i]
    if arg == "--quiet" {
      quiet = true
    } else if arg == "--list" && i + 1 < args.length() {
      // A manifest of paths, one per line: large corpora overflow argv.
      i = i + 1
      for line in read_text_file(args[i]).split("\n") {
        let path = line.trim().to_owned()
        if path.length() > 0 {
          files.push(path)
        }
      }
    } else {
      files.push(arg)
    }
    i = i + 1
  }
  if files.length() == 0 {
    println(
      "usage: moon run --target js src/cli -- [--quiet] [--list <manifest>] <file.mbti>...",
    )
    set_exit_code(2)
    return
  }
  let tally = Tally::new()
  for path in files {
    tally.files = tally.files + 1
    let src = read_text_file(path)
    if src == "" {
      tally.failed = tally.failed + 1
      println("FAIL " + path + ": cannot read file")
      continue
    }
    match @mbti.parse_result(src) {
      Ok(pkg) => {
        tally.passed = tally.passed + 1
        tally.decls = tally.decls + pkg.decls.length()
        if !quiet {
          println(
            "ok   " +
            pad_right(pkg.name, 32) +
            " decls=" +
            pad_left(pkg.decls.length().to_string(), 4) +
            "  fn=" +
            pkg.count_kind("fn").to_string() +
            " struct=" +
            pkg.count_kind("struct").to_string() +
            " enum=" +
            pkg.count_kind("enum").to_string() +
            " trait=" +
            pkg.count_kind("trait").to_string() +
            " impl=" +
            pkg.count_kind("impl").to_string(),
          )
        }
      }
      Err(msg) => {
        tally.failed = tally.failed + 1
        println("FAIL " + path + ": " + msg)
      }
    }
  }
  let rate = if tally.files == 0 {
    0.0
  } else {
    tally.passed.to_double() / tally.files.to_double() * 100.0
  }
  println("")
  println(
    "files=" +
    tally.files.to_string() +
    " passed=" +
    tally.passed.to_string() +
    " failed=" +
    tally.failed.to_string() +
    " declarations=" +
    tally.decls.to_string() +
    " parse_rate=" +
    format_rate(rate) +
    "%",
  )
  if tally.failed > 0 {
    set_exit_code(1)
  }
}
