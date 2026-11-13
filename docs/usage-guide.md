# MoonBridge 用户手册（给 Python 开发者）

> **这份文档不需要你懂 MoonBit。**
> 你只要会 `pip install` 和 `import` 就够了。MoonBridge 把 MoonBit 库翻译成了
> 普通的 Python 包：装好之后就是一个有类型提示、能 `try/except`、能被 `mypy`
> 检查的 Python 模块，背后跑的是 WebAssembly，但你**不需要**知道 wasm 是什么，
> **不需要**装 Rust / C 编译器，**不需要**配置任何环境变量或动态库路径。

本文所有命令都在 **Python 3.9+** 下实测过。示例输出是真实运行结果，不是示意。

---

## 目录

| 章节 | 你想做什么 |
| --- | --- |
| [0. 30 秒版本](#0-30-秒版本) | 只想赶紧跑起来 |
| [1. 环境准备](#1-环境准备) | Windows / macOS / Linux 各要装什么 |
| [2. 场景一：直接使用现成的 Python 包](#2-场景一直接使用现成的-python-包) | `pip install` → `import` → 调用 → 处理异常；含 [2.6 批量调用](#26-批量调用把-n-次调用压成-1-次跨越) |
| [3. 场景二：把自己的 MoonBit 库变成 Python 包](#3-场景二把自己的-moonbit-库变成-python-包开发者指南) | 从 `moon new` 到自己的 `.whl` |
| [4. 常见问题排查](#4-常见问题排查troubleshooting) | 5 个新手最容易踩的坑 |
| [5. 速查表](#5-速查表) | 命名规则、异常类型、去哪找帮助 |

---

## 0. 30 秒版本

先进入仓库根目录，建一个干净的虚拟环境（见 [§1](#1-环境准备)），然后粘贴这三条命令：

```bash
pip install ./dist/moonbridge-0.1.0-py3-none-any.whl

python -c "import moonbridge; moonbridge.install(); from moonbridge import moonbitlang__core__json as m; print('valid:', m.valid('[1, 2, 3]'))"

python scripts/wheel_smoke.py
```

预期：

```text
valid: True
...
wheel installed and functional
```

第 3 条会跑 11 项自检（JSON 往返、对象读写、`list`/`dict`/`lambda` 跨边界、
类型化异常、句柄归零）。三条命令里没有任何需要你手动下载、编译或配置的东西：
`wasmtime` 会由 `pip` 自动带上，wheel 里自带了 wasm 二进制。

> 完整保姆级说明继续往下看。**[返回 README](../README.md)**

---

## 1. 环境准备

### 1.1 一句话结论

| 场景 | 需要装的东西 |
| --- | --- |
| **场景一**（用现成的 wheel） | 只有 **Python 3.9+** 和 `pip`。其余全自动。 |
| **场景二**（把**自己的** MoonBit 库做成 wheel） | 额外需要 **MoonBit CLI (`moon`)**、**Node.js 18+**、**git**。 |

**关于 `wasmtime`**：它是运行 WebAssembly 的 Python 库。你**不需要单独安装**——
wheel 的元数据里写了 `Requires-Dist: wasmtime>=20`，`pip install` 时会自动装上。
它是带预编译二进制的 wheel（Windows / macOS / Linux 全平台都有），
**不需要 Rust、不需要 C 编译器、不需要系统包管理器**。

> 想确认它确实装好了：`python -c "import wasmtime; print('ok')"`。
> 只有当你处于离线环境、或 `pip` 被代理挡住时，才需要手动补一句
> `pip install "wasmtime>=20"`（见 [§4 Q1](#q1modulenotfounderror-no-module-named-wasmtime)）。

### 1.2 Python 3.9+

先确认版本，低于 3.9 请升级（3.8 会在 `dict[str, X]` 这类运行时注解上报
`TypeError: 'type' object is not subscriptable`）：

```bash
python --version          # Windows
python3 --version         # macOS / Linux
```

如果没装：

| 系统 | 安装命令 |
| --- | --- |
| **Windows** | `winget install -e --id Python.Python.3.13`（或到 <https://www.python.org/downloads/> 下载安装包，**勾选 "Add python.exe to PATH"**） |
| **macOS** | `brew install python@3.13`（或官网 pkg 安装包） |
| **Linux (Debian/Ubuntu)** | `sudo apt update && sudo apt install -y python3 python3-venv python3-pip` |

### 1.3 建议：建一个干净的虚拟环境

虚拟环境（`venv`）能避免和你机器上其它项目的依赖打架。**强烈建议**，尤其是
"复制粘贴就能跑" 的前提就是环境干净。

```bash
# Windows（PowerShell）
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip --version

# Windows（cmd.exe）
python -m venv .venv
.venv\Scripts\activate.bat

# macOS / Linux（bash / zsh）
python3 -m venv .venv
source .venv/bin/activate
python -m pip --version
```

激活成功后，命令行提示符前通常会出现 `(.venv)`。之后本文所有 `pip` / `python`
都指这个环境里的那份。**用 `python -m pip ...`（而不是裸 `pip ...`）可以避免
"pip 和 python 不是同一个解释器" 的问题**（见 [§4 Q3](#q3python-版本太低--pip-装到了别的解释器)）。

> Windows PowerShell 若提示"禁止运行脚本"，先执行
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`，或改用上面的 cmd 版本。

### 1.4 场景二额外需要：MoonBit CLI 与 Node.js

只有当你想**自己生成绑定**（[§3](#3-场景二把自己的-moonbit-库变成-python-包开发者指南)）时才需要。
MoonBit 官方安装脚本（会自动装到 `$HOME/.moon` 并加入 PATH）：

```bash
# macOS / Linux
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash

# Windows（PowerShell）
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

装完**重开终端**，验证：

```bash
moon version     # 本手册实测：moon 0.1.20261104
node --version   # 需要 18+，本手册实测：v22.22.2
git --version
```

> `moon run --target js src/cli` 会用到 Node.js（这是唯一不依赖 C 工具链的后端）。
> 官方还要求先装好 git。参考：<https://moonbitlang.com/download>。

---

## 2. 场景一：直接使用现成的 Python 包

以仓库里自带的 `moonbridge-0.1.0-py3-none-any.whl` 为例。这个 wheel 内含
MoonBit 标准库 `json` / `builtin` / `lexbuf` 的绑定和一个回调测试包。

### 2.1 安装

在**仓库根目录**执行（`dist/` 里的 wheel 已经随仓库提供）：

```bash
python -m pip install ./dist/moonbridge-0.1.0-py3-none-any.whl
```

首次安装会从 PyPI 拉取 `wasmtime`，所以需要联网一次。典型输出：

```text
Processing ./dist/moonbridge-0.1.0-py3-none-any.whl
Collecting wasmtime>=20 (from moonbridge==0.1.0)
  Downloading wasmtime-50.0.1-py3-none-win_amd64.whl (8.0 MB)
Installing collected packages: wasmtime, moonbridge
Successfully installed moonbridge-0.1.0 wasmtime-50.0.1
```

验证装到了哪：

```bash
python -c "import moonbridge; print(moonbridge.__file__)"
# ...\site-packages\moonbridge\__init__.py
```

### 2.2 最小可运行示例：三步

```bash
python -c "import moonbridge; moonbridge.install(); from moonbridge import moonbitlang__core__json as m; print('valid:', m.valid('[1, 2, 3]'))"
```

输出：`valid: True`

拆开看，只有三件事：

```python
import moonbridge                    # 1. 导入包
moonbridge.install()                 # 2. 初始化（加载内置的 wasm，一次即可）
from moonbridge import moonbitlang__core__json as mjson   # 3. 像普通 Python 模块一样导入
print(mjson.valid('[1, 2, 3]'))     # 调用 MoonBit 标准库 json 的函数
```

**`moonbridge.install()` 做了什么？** 它读取 wheel 里自带的 `_guest.wasm` 并启动，
把它设成之后所有生成模块默认调用的对象。使用 `__file__` 定位，所以你**不用**
传 wasm 路径、不用设环境变量。每个 Python 进程调用一次即可；忘了调用会报
`MoonStateError`（见 [§4 Q2](#q2moonstateerror-no-moonbridge-runtime-is-installed)）。

**模块名怎么来的？** MoonBit 的包名用 `/` 分隔，Python 模块名用 `__` 替换：

| MoonBit 包 | Python 模块 |
| --- | --- |
| `moonbitlang/core/json` | `moonbitlang__core__json` |
| `moonbitlang/core/builtin` | `moonbitlang__core__builtin` |
| `gyyyy6/moonbridge/callbacks` | `gyyyy6__moonbridge__callbacks` |

### 2.3 更多调用例子

写成文件更清楚（把下面存成 `demo.py`，然后 `python demo.py`）：

```python
import moonbridge
from moonbridge import moonbitlang__core__json as mjson

moonbridge.install()

# 1) 判断 JSON 是否合法 -> bool
print(mjson.valid('{"a": [1, 2, 3]}'))     # True
print(mjson.valid('{oops'))                 # False

# 2) 解析 -> 对象 -> 重新序列化
with mjson.parse('{"b":"x","a":[1,2,3]}') as doc:
    print(doc.stringify())                  # {"b":"x","a":[1,2,3]}

# 3) 构造 MoonBit 对象、读写字段
pos = mjson.Position(12, 34)
print(pos.line, pos.column)                 # 12 34
pos.close()

# 4) Python 的 list / dict 直接传
array = mjson.Json.array([mjson.Json.number(1.5), mjson.Json.string("x")])
print(array.stringify())                    # [1.5,"x"]
array.close()

# 5) 回调：Python 的 lambda 传进去，MoonBit 侧会真的调用它
from moonbridge import gyyyy6__moonbridge__callbacks as mcb
print(mcb.call_with(lambda x: x * 2, 21))  # 42
```

> 这些例子都来自仓库的 `scripts/wheel_smoke.py`，运行 `python scripts/wheel_smoke.py`
> 会一次跑完 11 条等价断言。

**关于 `close()` 和 `with`**：`parse()` 返回的 `Json`、`Position` 等对象背后是
MoonBit 堆上的值，Python 侧只持有一个不透明句柄。用 `with ... as ...:`
会在退出时立刻释放；也可以显式调用 `.close()`；不写也行，垃圾回收会批量释放
（wheel 的自检最后一项就是"结束时句柄归零"）。

### 2.4 异常处理

MoonBit 的错误会被翻译成**真正的 Python 异常类**，可以直接 `except`：

```python
import moonbridge
from moonbridge import moonbitlang__core__json as mjson

moonbridge.install()

try:
    mjson.parse("{oops")           # 故意写坏
except mjson.ParseError as exc:    # 具体类型
    print(type(exc).__name__, "|", exc)
    # ParseError | Invalid character 'o' at line 1, column 1
except moonbridge.MoonError as exc:  # 兜底：所有来自 MoonBit 的错误
    print("其它 MoonBit 错误:", exc)
```

异常层级：

| 类 | 含义 | 怎么导入 |
| --- | --- | --- |
| `MoonError` | 所有跨边界错误的基类（继承 `Exception`） | `moonbridge.MoonError` |
| `ParseError`、`JsonDecodeError` | 由具体 MoonBit `suberror` 生成的类 | 在对应模块里，如 `mjson.ParseError` |
| `MoonStateError` | 忘了 `install()`，或用了已 `close()` 的句柄 | `moonbridge.MoonStateError` |
| `MoonPanic` | guest 进入了无法处理的状态 | `moonbridge.MoonPanic` |

推荐的写法是 **`except 具体类` 在前、`except moonbridge.MoonError` 兜底在后**。
因为 `MoonError` 继承自 `Exception`，普通 `except Exception` 也能接住它，不会漏。

### 2.5 类型提示与 mypy

wheel 里带了 `.pyi` 类型存根和 `py.typed` 标记，所以编辑器和 `mypy` 能直接
补全、检查参数类型，**无需额外装 typeshed 存根**：

```python
# check.py
from __future__ import annotations
import moonbridge
from moonbridge import moonbitlang__core__json as mjson

def check(text: str) -> bool:
    moonbridge.install()
    return mjson.valid(text)
```

```bash
python -m pip install mypy
python -m mypy --strict check.py
# Success: no issues found in 1 source file
```

> 如果 mypy 说找不到 `moonbridge` 的类型信息，几乎都是"装 wheel 的 venv" 和
> "跑 mypy 的 venv" 不是同一个，见 [§4 Q5](#q5mypy-报找不到-moonbridge-的类型存根)。

### 2.6 批量调用：把 N 次调用压成 1 次跨越

如果要对**同一个函数**连续调用很多次（比如校验一整批 JSON），单次调用每次都要付一次
跨语言往返（约 20–40 μs）。批量协议把 N 组参数打包成**一次**跨越，实测 10 万次
`valid()` 从 40.34 μs/次降到 6.87 μs/次（**5.87×**）。

生成器会给可批量函数自动配一个 `<函数名>_many`，直接传参数元组列表即可：

```python
import moonbridge
from moonbridge import moonbitlang__core__json as mjson

moonbridge.install()
results = mjson.valid_many([
    ('{"a": 1}',),
    ("{oops",),
    ("[]",),
])
print(results)   # [True, False, True]
```

规则很简单，三条：

1. **`_many` 的参数是「参数元组的列表」**：单参数就是 `(值,)`，别漏掉逗号。
2. **一次 `valid_many([...])` 只跨越一次**。可以自己数：
   `runtime.crossings` 在调用前后只增加 1，而 `runtime.calls` 增加的是列表长度。
   （`host, runtime = moonbridge.install()` 能拿到这两个对象。）
3. **一批里不要混入"期望失败"的调用**：中途某个调用抛异常时，整批都会以异常结束
   （之前已执行的调用不会回滚）。`valid()` 这种返回 `False` 而不是抛异常的函数最适合批量。

需要更底层的控制时，用 `moonbridge.run_batch(symbol, calls)`。`symbol` 是
`<包名>::<函数名>` 形式的 MoonBit 全名，`calls` 是参数列表的列表：

```python
moonbridge.run_batch(
    "moonbitlang/core/json::valid",
    [('{"a": 1}',), ("{oops",)],
)   # [True, False]
```

`run_batch` 还有个 `wrap=` 参数，供返回 MoonBit 对象（句柄）的函数使用——普通用户
用自动生成的 `_many` 就够了，不必碰它。批量协议的设计与实测数据见
[批量协议报告](batching.md)。

> 哪些函数会生成 `_many`：全位置参数、且参数里没有函数值的自由函数。
> 带可选参数（如 `parse`）或回调的函数没有无歧义的元组位置，仍请用单次调用或 `run_batch`。

---

## 3. 场景二：把自己的 MoonBit 库变成 Python 包（开发者指南）

这一节给"我写了一个 MoonBit 库，想让 Python 能调"的开发者。
**前提**：按 [§1.4](#14-场景二额外需要moonbit-cli-与-nodejs) 装好 `moon`、Node.js、git，
并激活一个 Python 3.9+ 的虚拟环境。

### 3.1 先理解流程（30 秒）

```text
你的 .mbt 源码  ──moon info──▶  pkg.generated.mbti（公开接口）
                                      │
                    MoonBridge CLI ────┼──▶  .py / .pyi（Python 绑定）
                                      └──▶  guest.mbt（MoonBit 侧的应答代码）
                                                    │
                                       moon build --target wasm --release
                                                    │
                                              _guest.wasm
                                                    │
                         打包（PEP 517）──▶  .whl ──pip install──▶  import 你的库
```

**为什么要重新编译 wasm？** Python 侧的函数体只是一层"转发"，真正执行在 guest 里。
所以只有生成 `.pyi` 存根（只能做类型检查）是不够的，必须把你自己的函数也
编进 guest。这也是为什么这一步需要在 MoonBridge 仓库里跑几条 `moon` 命令——
但你依然不需要手写任何 wasm 或 C 代码，全部由生成器产出。

### 3.2 完整可复制命令流

以下命令在 **bash / Git Bash** 下逐行执行（Windows 用户请用 Git Bash，
MoonBit 官方也推荐它）。所有命令都已端到端实测。

#### 第 0 步：拿到 MoonBridge 源码

```bash
git clone https://github.com/gyyyy6/MoonBridge.git
cd MoonBridge
```

#### 第 1 步：用 `moon new` 建自己的库

建议建在仓库**外面**，避免嵌套 git 仓库：

```bash
cd ..
moon new --user demo mylib
cd mylib
```

把模板里的 `mylib.mbt` 换成自己的公开函数（**一定要写 `pub`**，否则接口里看不到）：

```bash
cat > mylib.mbt <<'EOF'
///|
pub fn add(a : Int, b : Int) -> Int {
  a + b
}
///|
pub fn greet(name : String) -> String {
  "Hello, " + name + "!"
}
EOF
```

编译检查，并生成接口文件：

```bash
moon check
moon info
cat pkg.generated.mbti
```

应能看到（这就是 MoonBridge 要读的输入）：

```text
package "demo/mylib"

// Values
pub fn add(Int32, Int32) -> Int32

pub fn greet(String) -> String
```

> **Windows 注意**：`moon new` 可能打印一条
> `failed to create file symlink: ...\README.md -> README.mbt.md ... 客户端没有所需的特权`。
> 这是模板想建一个符号链接、而 Windows 默认没开开发者模式导致的，**无害**：
> 项目已经建好，继续往下即可（`moon check` 能过就说明没问题）。

#### 第 2 步：把库接进 MoonBridge 模块

guest 要在 MoonBridge 模块里一起编译，所以把源码作为模块内的一个包放进去：

```bash
cd ../MoonBridge
mkdir -p src/mylib
cp ../mylib/mylib.mbt src/mylib/
printf 'pkgtype(kind: "library")\n' > src/mylib/moon.pkg
moon info
cat src/mylib/pkg.generated.mbti
```

现在包名变成了 `gyyyy6/moonbridge/mylib`，对应 Python 模块
`gyyyy6__moonbridge__mylib`。

> 这一步的 `moon info` 不能省：它同时会生成 `src/callbacks/pkg.generated.mbti`，
> 第 4 步的生成器要读它（`*.generated.mbti` 是构建产物，不进版本库）。

#### 第 3 步：收集标准库接口（离线即可）

```bash
bash scripts/corpus.sh core
```

会从本机已安装的 MoonBit 标准库里收集约 139 个 `.mbti`，写到
`_corpus/manifest.txt`，不需要联网。

#### 第 4 步：生成 Python 绑定 + guest

```bash
moon run --target js src/cli -- \
  --gen _gen \
  --bind "moonbitlang/core/json,moonbitlang/core/builtin,moonbitlang/core/lexbuf,gyyyy6/moonbridge/callbacks,gyyyy6/moonbridge/mylib" \
  --guest "moonbitlang/core/json,moonbitlang/core/builtin,moonbitlang/core/lexbuf,gyyyy6/moonbridge/callbacks,gyyyy6/moonbridge/mylib" \
  --guest-out src/guest_gen \
  --list _corpus/manifest.txt \
  src/callbacks/pkg.generated.mbti \
  src/mylib/pkg.generated.mbti
```

看到 `bind: modules=5 of 5` 和
`bind gyyyy6/moonbridge/mylib -> gyyyy6__moonbridge__mylib.py` 就成功了。
看一眼生成结果：

```bash
cat _gen/moonbridge/gyyyy6__moonbridge__mylib.pyi
# def add(arg0: int, arg1: int, /) -> int: ...
# def greet(arg0: str, /) -> str: ...
```

> **为什么 `--bind` 里还要带那几个标准库包？** guest 里容器、回调、异常字段的
> 通用辅助代码（例如释放 `Map` 用的 `release_pairs`）只有在这些包一起绑定时
> 才会生成。只绑定自己的库会得到 `release_pairs is unbound` 之类的编译错误。
> 所以请**保留这一整串**，只把你自己的包名追加在末尾。这是当前版本的已知约束，
> 已在 [S5 容器与回调](s5-containers-and-callbacks.md) 中记录。

#### 第 5 步：编译 guest 的 wasm

```bash
moon fmt
moon build --target wasm --release
```

产物在 `_build/wasm/release/build/guest_gen/guest_gen.wasm`。

#### 第 6 步：打成 wheel

MoonBridge 自带一个零依赖的 PEP 517 构建后端（`pack/moonbridge_build.py`），
把生成的包和 wasm 放进一个暂存目录，再让 `pip` 产出 wheel：

```bash
mkdir -p dist/myproj
cp -r _gen/moonbridge dist/myproj/
cp _build/wasm/release/build/guest_gen/guest_gen.wasm dist/myproj/moonbridge/_guest.wasm
cp pack/moonbridge_build.py pack/pyproject.toml dist/myproj/
python -c "import json; json.dump({'name':'moonbridge','version':'0.1.0','package':'moonbridge','summary':'My own MoonBit bindings','requires':['wasmtime>=20']}, open('dist/myproj/moonbridge_wheel.json','w'))"
python -m pip wheel --no-build-isolation --no-deps -w dist dist/myproj
```

看到 `Successfully built moonbridge` 即完成，wheel 在 `dist/` 下。

> 想改包名 / 版本号 / 描述，改上面那行 JSON 里的 `name` / `version` / `summary`
> 即可；`package` 必须保持 `moonbridge`（Python 包目录名）。
> 仓库里的 `bash scripts/wheel.sh` 是同一套流程的自动化脚本，
> 但它要求 `wasmtime` 装在**系统 Python** 里；用虚拟环境时请按上面的显式步骤走。
>
> 注意：输出的 wheel 文件名与仓库自带的那个相同，会**覆盖** `dist/` 里原有的
> wheel（这正是第 7 步要装的新包）。想留一份原件，先把
> `dist/moonbridge-0.1.0-py3-none-any.whl` 复制走，或把 `-w` 换成别的目录。

#### 第 7 步：安装并调用自己的库

```bash
python -m pip install --force-reinstall dist/moonbridge-0.1.0-py3-none-any.whl
python -c "import moonbridge; moonbridge.install(); from moonbridge import gyyyy6__moonbridge__mylib as my; print(my.add(2, 40)); print(my.greet('Python'))"
```

实测输出：

```text
42
Hello, Python!
```

到这里，一个你自己写的 MoonBit 函数就已经被 Python 调用了。原来 wheel 自带的
`moonbitlang__core__json` 等绑定依旧可用，可以顺手再跑一次
`python scripts/wheel_smoke.py` 确认没有破坏原有功能。

> **诚实边界**：当前版本需要在 MoonBridge 模块内部完成 guest 的重新生成与编译
> （即第 2～5 步）。"给任意外部 MoonBit 模块一条命令直接产出 wheel" 属于路线图
> 里的 S7，尚未实现。上面的流程是真实、可复现、已实测的等价路径。

---

## 4. 常见问题排查（Troubleshooting）

### Q1：`ModuleNotFoundError: No module named 'wasmtime'`

**原因**：wheel 依赖 `wasmtime>=20`，但 `pip` 没能把它装上——常见于离线机器、
公司代理、或 SSL 被中间设备打断（本手册实测环境就遇到过 `ReadTimeoutError`
和 `SSLEOFError`）。

**解法**（按顺序试）：

```bash
# 1) 手动补装，确认版本
python -m pip install "wasmtime>=20"
python -c "import wasmtime; print('ok')"

# 2) 若公司/本机代理配置失效，先清掉再装
#    macOS / Linux:
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy python -m pip install "wasmtime>=20"
#    Windows PowerShell:
#    $env:HTTP_PROXY=""; $env:HTTPS_PROXY=""; python -m pip install "wasmtime>=20"

# 3) 国内网络可用镜像
python -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple "wasmtime>=20"
```

注意别只装了依赖却漏了 wheel 本身，最终检查：
`python -m pip show moonbridge` 与 `python -c "import moonbridge; print(moonbridge.__file__)"`。

---

### Q2：`MoonStateError: no MoonBridge runtime is installed; call ... set_default(...) first`

**原因**：调用任何生成函数前没有执行 `moonbridge.install()`。

**解法**：每个 Python 进程开始时调用一次：

```python
import moonbridge
moonbridge.install()          # 只要一次，放在 import 之后、第一次调用之前
```

同一个异常也会在你对已经 `close()` 的对象继续调用时出现，此时改为在
`with ... as ...:` 块内使用它，或重新创建对象。

---

### Q3：Python 版本太低 / `pip` 装到了别的解释器

**症状**：`TypeError: 'type' object is not subscriptable`、
`SyntaxError`，或 `pip install` 显示成功但 `import moonbridge` 仍失败。

**原因**：生成的绑定使用了 `dict[str, X]` 等运行时泛型注解，要求 **Python ≥ 3.9**；
另外 `pip` 与 `python` 指向不同环境也很常见。

**解法**：

```bash
python --version                       # 必须 >= 3.9
python -m pip --version                # 确认 pip 属于同一个 python
python -c "import sys; print(sys.executable)"   # 看清当前解释器绝对路径
python -m pip install --force-reinstall ./dist/moonbridge-0.1.0-py3-none-any.whl
```

**始终用 `python -m pip ...` 而不是裸 `pip ...`**，就能避免装错环境。

---

### Q4：`pip` 说找不到 `dist/moonbridge-0.1.0-py3-none-any.whl`

**原因**：不在仓库根目录；或用了早期克隆（旧版本的仓库没有把 wheel 纳入版本库）。

**解法**：

```bash
cd MoonBridge                          # 回到仓库根目录
ls -l dist/moonbridge-0.1.0-py3-none-any.whl     # 确认文件在
python -m pip install ./dist/moonbridge-0.1.0-py3-none-any.whl
```

如果你是 2026-11 之前克隆的仓库，先 `git pull` 更新；wheel 是随仓库一起提交的。
想从源码重新构建也可以，但需要 MoonBit 工具链：`bash scripts/e2e.sh`。

---

### Q5：mypy 报找不到 `moonbridge` 的类型存根

**症状**：`Skipping analyzing "moonbridge": module is installed, but missing library stubs or py.typed marker`
或 `Cannot find implementation or library stub for module named "moonbridge"`。

**原因**：跑 `mypy` 的解释器与装 wheel 的 venv 不是同一个；或从仓库源码目录
（`_gen/` 之类）直接 import，绕过了带 `py.typed` 的安装包。

**解法**：

```bash
python -m pip install --force-reinstall ./dist/moonbridge-0.1.0-py3-none-any.whl
python -m pip install mypy
python -m mypy --version                      # 注意要用同一个 python -m
python -c "import moonbridge, pathlib; print(pathlib.Path(moonbridge.__file__).parent / 'py.typed')"
# 该路径应存在；若指向仓库内的 _gen/，请 cd 到别的目录再运行
python -m mypy --strict your_script.py
```

---

### 还有两个小提醒

- **Windows PowerShell 不支持 heredoc**：`python - <<'PY'` 会报
  `The term '<<' is not recognized`。本手册的 Quick Start 与场景一都刻意使用
  `python -c "..."` 单行形式，就是为了在 cmd / PowerShell / bash 下都能直接粘贴。
  多行示例请存成 `.py` 文件再 `python demo.py`。
- **`import moonbridge` 别从 `_gen/` 目录里启动**：那里有一份生成物同名目录，
  会遮蔽已安装的包。在仓库根目录或任意其它目录运行即可；`scripts/wheel_smoke.py`
  特意从 `dist/` 里执行就是为了排除这种误判。

---

## 5. 速查表

### 5.1 命令速查

| 想做什么 | 命令 |
| --- | --- |
| 安装 | `python -m pip install ./dist/moonbridge-0.1.0-py3-none-any.whl` |
| 初始化 | `moonbridge.install()`（每个进程一次） |
| 导入某个 MoonBit 包 | `from moonbridge import moonbitlang__core__json as mjson` |
| 跑 11 项自检 | `python scripts/wheel_smoke.py` |
| 类型检查 | `python -m mypy --strict your_script.py` |
| 重装（升级/修复） | `python -m pip install --force-reinstall ./dist/moonbridge-0.1.0-py3-none-any.whl` |

### 5.2 API 速查

| 名字 | 说明 |
| --- | --- |
| `moonbridge.install(wasm=None)` | 加载内置 wasm 并设为默认运行时，返回 `(host, runtime)` |
| `moonbridge.open_guest(wasm=None)` | 只加载不设为默认，用于拿新编译的 wasm 做测试 |
| `moonbridge.MoonError` | 所有 MoonBit 侧错误的基类 |
| `moonbridge.MoonStateError` | 未 `install()` / 句柄已释放 |
| `moonbridge.MoonPanic` | guest 内部不可恢复状态 |
| `moonbridge.MoonObject` | 所有句柄对象的基类；支持 `.close()` 和 `with` |
| `mjson.valid(s)` / `mjson.parse(s)` | 判断 / 解析 JSON |
| `mjson.valid_many([(s,), ...])` | 批量判断，N 次调用只用 1 次跨语言跨越 |
| `moonbridge.run_batch(symbol, calls)` | 低层批量入口，自定义符号时使用 |
| `runtime.calls` / `runtime.crossings` | 逻辑调用数 / 实际跨越次数，用来确认批量生效 |
| `mjson.ParseError` / `JsonDecodeError` | 可 `except` 的具体异常类 |

### 5.3 想深入了解

| 想问的问题 | 看哪份文档 |
| --- | --- |
| 整体架构、阶段验收 | [README](../README.md) |
| 为什么选 wasm、AI 工具在开发中的角色 | [开发复盘](development-retrospective.md) |
| wheel 是怎么打出来的 | [S6 打包](s6-wheel.md) |
| 跨边界对象 / 容器 / 回调 / 异常的细节 | [S5 容器与回调](s5-containers-and-callbacks.md) |
| 想让高频调用变快、理解批量协议 | [批量协议报告](batching.md) |
| 类型映射规则 | [S2 映射与生成](s2-type-mapping.md) |
| 报告 bug | <https://github.com/gyyyy6/MoonBridge/issues> |

---

**许可证**：Apache-2.0，见 [LICENSE](../LICENSE)。
