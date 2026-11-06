# S6：打包成 wheel

前五个阶段的产物是"能跑的一堆文件"。S6 的验收标准只有一句话：

```bash
pip install ./dist/moonbridge-0.1.0-py3-none-any.whl
python -c "import moonbridge; moonbridge.install()"
```

装完之后，调用方不需要知道 wasm、不需要找 `.py`、不需要设 `PYTHONPATH`。

2026-11-06 实测：wheel 501,064 字节，508 个条目，`pip install` 后从仓库外
`import moonbridge` 成功，11 项功能断言全绿，`live=0`。

---

## 一、为什么自己写 PEP 517 后端

一个 Python 包要能被 `pip install`，得先有一个构建系统。常规选择（setuptools / flit / hatchling）
都有一个先有鸡还是先有蛋的问题：**用户为了装你的包，得先装你的构建系统**。而我们的包其实不需要
构建系统——它就是一堆已经生成好的 `.py` / `.pyi` 加一个 wasm 文件，而 wheel 是一个带元数据的 zip。

所以 `pack/moonbridge_build.py` 只用标准库：

```toml
[build-system]
requires = []                    # 没有构建依赖
build-backend = "moonbridge_build"
backend-path = ["."]             # 后端就在源码树里
```

`requires = []` 不是省事，是**离线可构建**的保证：pip 不需要连索引去找 setuptools，
在断网机器上也能 `pip wheel`。四个必需的钩子都在：`build_wheel`、
`prepare_metadata_for_build_wheel`、`build_sdist`、`get_requires_for_build_*`。

---

## 二、wheel 里装了什么

```text
moonbridge-0.1.0-py3-none-any.whl       501,064 字节，508 个条目
├── moonbridge/
│   ├── __init__.py                      install() / open_guest()
│   ├── _codec.py                        帧编解码
│   ├── _runtime.py                      句柄生命周期、异常、回调表
│   ├── _wasmtime.py                     wasm 宿主
│   ├── _guest.wasm                      140,306 字节，guest 本体
│   ├── moonbitlang__core__json.py       4 个绑定的包
│   ├── moonbitlang__core__builtin.py
│   ├── moonbitlang__core__lexbuf.py
│   ├── gyyyy6__moonbridge__callbacks.py
│   └── *.pyi                            494 个包的类型存根
└── moonbridge-0.1.0.dist-info/          METADATA / WHEEL / RECORD / top_level.txt
```

`Tag: py3-none-any` 是诚实的：wheel 里是可移植的 wasm，不绑定平台。真正绑平台的是
`wasmtime`，它在 `METADATA` 里作为 `Requires-Dist` 声明，由 pip 按目标机器挑轮子：

```
Requires-Dist: wasmtime>=20
```

wasm 放在包目录里（`moonbridge/_guest.wasm`），所以 `install()` 只用 `__file__` 就能找到它：

```python
from pathlib import Path

path = Path(wasm) if wasm is not None else Path(__file__).with_name(_GUEST_FILE)
```

`wasm=` 这个参数留着不是为了好看：开发者改了一行 MoonBit、想拿新编的 guest 去跑已安装的绑定时，
只换这一个文件就够，不用重装。

---

## 三、构建是可复现的

zip 会把时间戳写进每个条目，两次构建的 sha256 就不同。后端给所有条目一个固定时间
（`SOURCE_DATE_EPOCH`，默认 1980-01-01，zip 能表达的最早时间），并固定权限 0644：

```bash
$ python -c "...build_wheel twice..."
f2870c0951df9dfcc025a005410fa9c3ae1920f2b3a422468d1c59f4e3418375
f2870c0951df9dfcc025a005410fa9c3ae1920f2b3a422468d1c59f4e3418375
reproducible: True
```

同一个值也是 pip 自己驱动这个后端产出的哈希——**两条路径（直接调后端 / pip 走 PEP 517）
构建出同一串字节**。这不是巧合，是后端里没有一处读时钟的结果。

---

## 四、脚本做了什么，以及为什么这么小心

`scripts/wheel.sh`：

1. **暂存**：把 `_gen/moonbridge`、wasm、`pack/` 里的两个文件、`moonbridge_wheel.json`
   拼成一个临时工程目录。版本号从 `moon.mod` 里读，wheel 和模块不可能说两个版本。
2. **构建**：`pip wheel --no-build-isolation --no-deps`。`--no-build-isolation` 是因为
   后端声明了零依赖，隔离环境只会多一个 venv 要建；`--no-deps` 是因为一个零依赖的 wheel
   没有可解析的东西，不该去问索引。
3. **安装**：`pip install --no-deps --force-reinstall <wheel>`，装进一个**一次性 venv**，
   并且用 `--system-site-packages` 让它看得见已经装好的 `wasmtime`——这一步要证明的是
   wheel 能装，不是 pip 能上网。
4. **使用**：`cd dist && <venv>/python scripts/wheel_smoke.py`。

第 4 步的 `cd` 是有意的：如果在仓库根目录跑，`import moonbridge` 会找到 `_gen/moonbridge`
（开发时就在那里的那份），wheel 少一个文件也照样"通过"。从 `dist/` 跑，导入只能落在
`site-packages`，脚本还会把它打印出来：

```
ok   imported from: ...\dist\venv\Lib\site-packages\moonbridge
ok   guest wasm shipped with the wheel: 140306 bytes
```

---

## 五、装完之后能用什么

`scripts/wheel_smoke.py` 只用公开 API，没有 `_codec`、没有帧、没有宿主细节：

```python
import moonbridge

host, runtime = moonbridge.install()          # 一句初始化

from moonbridge import moonbitlang__core__json as mjson

mjson.valid('{"a": [1, 2, 3]}')               # True
with mjson.parse('{"b": "x", "a": [1, 2, 3]}') as doc:
    doc.stringify()                           # '{"b":"x","a":[1,2,3]}'

pos = mjson.Position(12, 34)                  # guest 里的对象
pos.line, pos.column                          # 12, 34
```

实测输出：

```
ok   valid: True
ok   round trip: '{"b":"x","a":[1,2,3]}'
ok   field line: 12
ok   field column: 34
ok   list -> Array: '[1.5,"x"]'
ok   dict -> Map: '{"k":true}'
ok   callback: 42
ok   typed exception: ParseError: Invalid character 'o' at line 1, column 1
ok   every handle released: 0
```

最后一行是 S6 里最容易忽略的一条：**装好的包也不能泄漏**。`live_handles()` 归零说明
S3/S4 的句柄表在"从 wheel 导入"这条路径上和从源码导入时一样工作——它本来应该一样，
但"本来应该"不是验收。

---

## 六、数字

| 指标 | 值 |
|---|---|
| wheel 大小 | **501,064 字节**（zip 后，wasm 140,306） |
| wheel 条目 | 508（8 个 `.py` + 494 个 `.pyi` + wasm + 4 个 dist-info） |
| 构建依赖 | **0**（只用标准库） |
| 构建可复现 | 连续两次 sha256 相同，且与 pip 直接驱动后端的结果相同 |
| `pip install` 耗时 | < 1 s（本地 wheel，无依赖解析） |
| 安装后功能断言 | 11 项全绿，`live=0` |

---

## 七、诚实边界

* **`py3-none-any` 依赖 wasmtime 有对应平台的轮子**。没有 wasmtime 轮子的平台装得上
  `moonbridge` 但用不了——`import wasmtime` 会在 `install()` 时报错，报错信息指向缺的那个包。
* **只有 wasm 后端**。S7 计划的 native(C ABI) 后端会让 wheel 变成平台相关，那时
  `py3-none-any` 就要拆成每个平台一个 tag。
* **sdist 只能重打包，不能重新编译 wasm**。构建后端不调用 `moon build`——一个会 shell out
  到编译器的构建后端只在写它的那台机器上能用。要重新编译，请在源码树里跑 `scripts/e2e.sh`。
* **没有上传 PyPI**。S6 的验收是"本地能装、能 import、能干活"，不是"发布"。
* **`pip wheel` 的 `--no-build-isolation` 是本地选择**。真要发布，`requires = []` 依然成立，
  但 CI 里关掉隔离能省一次 venv。
