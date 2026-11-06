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
/// Writes a UTF-8 file, creating nothing on the way: the caller makes the
/// directory first so a typo in the output path fails loudly.
#cfg(target="js")
extern "js" fn write_text_file(path : String, data : String) -> Bool = "function (path, data) { try { require('fs').writeFileSync(path, data, 'utf8'); return true } catch (e) { console.error(String(e)); return false } }"

///|
#cfg(not(target="js"))
fn write_text_file(path : String, data : String) -> Bool {
  ignore(path)
  ignore(data)
  false
}

///|
#cfg(target="js")
extern "js" fn make_dir(path : String) -> Bool = "function (path) { try { require('fs').mkdirSync(path, { recursive: true }); return true } catch (e) { return false } }"

///|
#cfg(not(target="js"))
fn make_dir(path : String) -> Bool {
  ignore(path)
  false
}

///|
/// Aggregate counters over a corpus run.
priv struct Tally {
  mut files : Int32
  mut passed : Int32
  mut failed : Int32
  mut decls : Int32
  mut types : Int32
  mut edges : Int32
  mut cyclic : Int32
}

///|
fn Tally::new() -> Tally {
  { files: 0, passed: 0, failed: 0, decls: 0, types: 0, edges: 0, cyclic: 0, }
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
/// Aggregate counters over a generation run.
priv struct GenTally {
  mut stubs : Int32
  mut failed : Int32
  mut types : Int32
  mut funcs : Int32
  mut fields : Int32
  mut skipped : Int32
  mut degraded : Int32
}

///|
fn GenTally::new() -> GenTally {
  {
    stubs: 0,
    failed: 0,
    types: 0,
    funcs: 0,
    fields: 0,
    skipped: 0,
    degraded: 0,
  }
}

///|
/// Generates one stub per input file into `<out_dir>/moonbridge/`, together
/// with the runtime module the stubs import. Returns the number of failures.
fn run_gen(files : Array[String], out_dir : String) -> Int32 {
  let pkg_dir = out_dir + "/moonbridge"
  if !make_dir(pkg_dir) {
    println("error: cannot create " + pkg_dir)
    return 1
  }
  ignore(write_text_file(pkg_dir + "/__init__.py", @gen.render_init()))
  ignore(write_text_file(pkg_dir + "/_runtime.py", @gen.render_runtime()))
  ignore(write_text_file(pkg_dir + "/py.typed", ""))
  let tally = GenTally::new()
  // Two packages can flatten to the same module stem; writing both would lose
  // one silently, so a collision is a hard failure.
  let stems : Map[String, String] = Map([])
  for path in files {
    let src = read_text_file(path)
    if src == "" {
      tally.failed = tally.failed + 1
      println("FAIL " + path + ": cannot read file")
      continue
    }
    match @mbti.parse_result(src) {
      Ok(pkg) => {
        let stub = @gen.generate(pkg, @gen.GenOptions::standard())
        match stems.get(stub.module_name) {
          Some(other) =>
            if other != pkg.name {
              tally.failed = tally.failed + 1
              println(
                "FAIL " +
                pkg.name +
                ": module stem " +
                stub.module_name +
                " already used by " +
                other,
              )
              continue
            }
          None => ()
        }
        stems.set(stub.module_name, pkg.name)
        if !write_text_file(pkg_dir + "/" + stub.filename, stub.text) {
          tally.failed = tally.failed + 1
          println("FAIL " + pkg.name + ": cannot write " + stub.filename)
          continue
        }
        tally.stubs = tally.stubs + 1
        tally.types = tally.types + stub.types
        tally.funcs = tally.funcs + stub.funcs
        tally.fields = tally.fields + stub.fields
        tally.skipped = tally.skipped + stub.skipped
        tally.degraded = tally.degraded + stub.degraded.length()
      }
      Err(msg) => {
        tally.failed = tally.failed + 1
        println("FAIL " + path + ": " + msg)
      }
    }
  }
  println("")
  println(
    "stubs=" +
    tally.stubs.to_string() +
    " failed=" +
    tally.failed.to_string() +
    " types=" +
    tally.types.to_string() +
    " funcs=" +
    tally.funcs.to_string() +
    " fields=" +
    tally.fields.to_string() +
    " skipped=" +
    tally.skipped.to_string() +
    " degraded=" +
    tally.degraded.to_string(),
  )
  tally.failed
}

///|
fn main {
  let args = @env.args()
  let mut quiet = false
  let mut want_graph = false
  let mut gen_dir : String? = None
  let files : Array[String] = []
  let mut i = 2 // argv[0] is the node binary, argv[1] is this script
  while i < args.length() {
    let arg = args[i]
    if arg == "--quiet" {
      quiet = true
    } else if arg == "--graph" {
      // Also build the type graph, which is where a parse that "succeeded"
      // but produced nonsense would show up.
      want_graph = true
    } else if arg == "--gen" && i + 1 < args.length() {
      // Generate Python stubs instead of reporting parse statistics.
      i = i + 1
      gen_dir = Some(args[i])
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
      "usage: moon run --target js src/cli -- [--quiet] [--graph] [--gen <dir>] [--list <manifest>] <file.mbti>...",
    )
    set_exit_code(2)
    return
  }
  match gen_dir {
    Some(dir) => {
      let failures = run_gen(files, dir)
      if failures > 0 {
        set_exit_code(1)
      }
      return
    }
    None => ()
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
        let mut graph_note = ""
        if want_graph {
          let g = @mbti.TypeGraph::build(pkg)
          tally.types = tally.types + g.node_count()
          tally.edges = tally.edges + g.edge_count()
          let cycles = g.cycles()
          if cycles.length() > 0 {
            tally.cyclic = tally.cyclic + 1
          }
          graph_note = "  types=" +
            g.node_count().to_string() +
            " edges=" +
            g.edge_count().to_string() +
            " cycles=" +
            cycles.length().to_string()
        }
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
            pkg.count_kind("impl").to_string() +
            graph_note,
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
    "%" +
    (if want_graph {
      " types=" +
      tally.types.to_string() +
      " edges=" +
      tally.edges.to_string() +
      " files_with_cycles=" +
      tally.cyclic.to_string()
    } else {
      ""
    }),
  )
  if tally.failed > 0 {
    set_exit_code(1)
  }
}
