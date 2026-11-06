# MoonBridge

**把 MoonBit 模块变成可 `pip install` 的 Python 包。**

给一个 `moon.mod`，MoonBridge 读取它的公开接口（`moon info` 产物），生成一个真正的 Python
包：模块、类、枚举、异常、`.pyi` 类型存根、docstring，加上 MoonBit 侧的运行时（句柄表 +
稳定宿主 ABI），最后打成 wheel。

```text
moon.mod  ──moon info──▶  接口 IR  ──typemap──▶  代码生成  ──▶  wheel
                                                        │
                                          MoonBit 运行时（句柄/ABI）
                                                        │
                                            wasm 模块 / native 库
```

> 状态：**S0 通过、S1 通过、S2 通过、S3 通过、S4 通过、S5 通过**（2026-11-07）。
> S0：调用 ABI、内存共享、宿主↔MoonBit 字节流、UTF-8 往返全部跑通，实测见
> [spikes/01-wasm-python](spikes/01-wasm-python/)。
> S1：`.mbti` 解析器 + 类型图，在 **501 个真实接口文件 / 17,793 条声明**上 100% 通过，
> 见 [S1 语料报告](docs/s1-corpus-report.md)。
> S2：类型映射 + Python 代码生成，**501 个包生成 stub，`mypy --strict` 0 报错**，
> 见 [S2 映射与生成](docs/s2-type-mapping.md)。
> S3：跨包句柄与生命周期，**真实 json 包端到端跑通，10 万次调用 0 泄漏、guest 内存逐字节不变**，
> 见 [S3 运行时](docs/s3-runtime.md)。
> S4：**guest 侧也由生成器产出**，对象能被构造、读、写；10 万次 × 6 个用例共 150 万帧，
> 内存曲线平直、`live=0`、`dropped=0`，见 [S4 对象模型](docs/s4-object-model.md)。
> S5：`Array` / `Map` / `Option` / `Result` / 回调 / 异常字段全部可跨边界——Python 的 `list`、
> `dict`、`lambda` 直接传，MoonBit 的 `suberror` 变成 Python 的 `except` 类，
> 见 [S5 容器与回调](docs/s5-containers-and-callbacks.md)。

---

## 为什么要做这个

MoonBit 已经能编译到 wasm / wasm-gc / js / native，但**别的语言调用 MoonBit 仍然要靠手写胶水**。
生态里现有的跨语言能力是零散的：

| 目标语言 | 现有方案 | 形态 |
| --- | --- | --- |
| Node.js | `unmbt/napi-mbt` | 生成 Node-API 绑定（仅 Node） |
| Java / Android | `Nanaloveyuki/ajni` | JNI 双向运行时（仅 Java） |
| C | `icyaaaww/moonbind` | 从 C 头文件生成 MoonBit 绑定（**反方向**） |
| TypeScript | `mizchi/ts` | TS ↔ MoonBit 桥接 |
| **Python** | **无** | — |
| **Go / Rust / Swift / PHP** | **无** | — |

MoonBridge 补的是这一层：**不是给某个库手写一层包装，而是把"跨语言绑定"本身做成编译器式的生成器**。
增量不在"又一个包装库"，而在：

1. **通用性**：任意 MoonBit 模块一条命令生成，不是一次性胶水；
2. **所有权协议**：GC 托管对象通过句柄表跨越边界，宿主永远不会拿到悬垂指针；
3. **类型保真**：MoonBit 的 `enum` / `Option` / `Result` / 泛型映射成 Python 侧有类型的对象，
   而不是 `dict` 与 `Any`；
4. **可安装**：产出符合 PEP 517 的 wheel，`pip install` 即用，不需要用户懂 wasm。

---

## Spike 01 结论（已验证）

| 验证项 | 结果 |
| --- | --- |
| `#export_name` 导出 | `mb_add` / `mb_fib` / 缓冲与字符串函数全部可见 |
| 线性内存导出 | 需 `options(link: {"wasm": {"export-memory-name": "memory"}})` |
| 参数表示 | `String` / `Bytes` 参数是**单个 i32 对象指针** → 必须走句柄协议 |
| 宿主写入 → MoonBit 读 | 写 16 字节，MoonBit 校验和 1626 一致 |
| MoonBit 写 → 宿主读 | 读回 `b'AAAAAAAA'` |
| UTF-8 往返 | `你好, MoonBit 🚀` → 13 个码位 / 20 字节，往返字节一致 |
| 每次调用开销 | 本机 wasmtime-py 基线：`nop` 6.9 μs，单参 16.6 μs；MoonBit `add` 22.7 μs |

最后一行决定了架构：**瓶颈在 Python 绑定层，不在 MoonBit**。因此高频路径必须走
"批量调用 + 缓冲协议"（一次跨越处理 N 个元素），并且 native(C ABI) 后端要作为性能选项保留。
详见 [ADR 0001](docs/decisions/0001-wasm-first.md)。

---

## S1：接口解析与类型图

`moon info` 输出的 `.mbti` 是纯文本接口，但它是**生成的**、且随工具链版本演进的。
MoonBridge 用一个手写递归下降解析器把它读成 AST，再建成类型图：

```text
.mbti  ──lexer──▶ token ──parser──▶ AST ──graph──▶ 类型图
                                                  │
                                     依赖顺序 / 互递归组 / 外部类型
```

```bash
# 解析若干接口文件，逐文件汇报，任一失败则退出码非 0
moon run --target js src/cli -- path/to/pkg.generated.mbti ...

# 跑真实语料（标准库 + 20 个已发布模块及其依赖）
bash scripts/corpus.sh all
```

已覆盖的语法（全部由真实语料逼出来，明细见
[S1 语料报告](docs/s1-corpus-report.md#语料逼出来的语法缺口)）：泛型与 trait 约束、
函数类型、`T??`、`&Trait`、`async fn`、`raise` / `raise E` / `noraise` / `nocancel`
及其 `+` 组合、`pub(all)` / `pub(open)` / `priv`、`mut` 字段、构造器标签字段、
`const` 字面量、`type X = Y` 别名、重导出块、旧式 `import( … )` 块。

类型图回答三个生成器必需的问题：**先发哪个类型**（`topo_order`）、
**哪些类型互相递归必须一起产**（`cycles`，Tarjan SCC）、
**哪些类型不在本包**（`external_names`，交给宿主类型表）。

## S2：类型映射与 Python 代码生成

解析出的类型图要变成 Python 能理解的东西，中间要过两道关：**类型映射**（MoonBit 类型
→ Python 注解）和**命名**（MoonBit 标识符 → 合法且不遮蔽的 Python 标识符）。

```text
AST  ──typemap──▶ PyType ──render──▶ .pyi
      │                              │
   降级阶梯（4 级，每级都记账）        mypy --strict 校验
```

```bash
# 全语料生成 + mypy strict（需要 python + mypy）
bash scripts/gen.sh all
bash scripts/gen.sh core    # 仅标准库，离线可跑
```

映射结果只有四种，按保真度从高到低：**直接对应**（`Int`→`int`）、**透明擦除**
（`&T`、`T??`）、**句柄**（包内类型 → 生成类，值留在 MoonBit 堆上，跨边界的是不透明整数）、
**降级为 `Any`**。第四级从不静默：每个 `Any` 都带一条原因记录，`--gen` 按原因汇总：

```text
stubs=501 failed=0 types=1937 funcs=4789 fields=3733 skipped=7
degraded: foreign=4812 unknown=890 result=130 higher-order=699 arity=0 async=81
```

（S2 当时的数字。S3 引入世界索引后 `foreign` 降到 605、`unknown` 降到 255。）

两处刻意的选择：函数类型降级为 `Any` 而**不是** `Callable`（没有回调蹦床，写 `Callable`
等于承诺一条走不通的路）；stub 之间**互不 import**（MoonBit 包图含 48 个环，跨包类型走 `Any`，
保证每个 `.pyi` 独立可检查）。完整映射表、命名规则、以及 mypy 逼出来的六类问题见
[S2 映射与生成](docs/s2-type-mapping.md)。

## S3：跨包句柄与运行时

前两段产出的是一份"说得对"的接口。这一段让它能真的调起来：跨包导入补上、句柄表跑起来、
wasmtime 接进来，然后拿真实的 `moonbitlang/core/json` 验一遍。

```text
.mbti ──▶ stub(.pyi)   类型检查器读的那一份
     └──▶ module(.py)  解释器执行的那一份   ┐
                                            ├─ 同一次遍历，签名不可能与函数体不符
     世界索引 ──▶ from . import <stem>       ┘
                                            │
     Python 对象 ──handle id──▶ 句柄表 ──▶ MoonBit 堆 ──▶ wasm guest
                    ◀──批量回收 / close() / with──┘
```

```bash
# 生成 + 端到端 + 10 万次调用基准，任一泄漏即退出码非 0
bash scripts/e2e.sh
```

三个数字说明这一段到底做了什么：

| | S2 | S3 |
|---|---|---|
| 跨包类型降级为 `Any` | 4812 处 | **605 处**（剩下的真的不在语料里） |
| 生成的模块间导入边 | 0 | **566**（276 个模块） |
| 10 万次调用的 guest 内存 | — | **64 KiB 不变**，句柄表归零 |

基准还抓到了三个都不报错、只体现在曲线上的 bug：0 号句柄被当成"没有对象"（第一份文档永不释放）、
导出函数的返回值泄漏（41 字节/次）、世代计数器回绕（每 1023 次漏一个）。三个都写进
[S3 运行时](docs/s3-runtime.md)，包括怎么二分定位的。

## S4：生成 guest 与对象模型

S3 的绑定只有一半是生成的：`.py` / `.pyi` 从接口推出来，**guest 的 dispatch 表是手写的**。
手写的表会漂——它不会因为编译失败被发现，只会在某次调用悄悄返回错的字段。S4 把这个缺口补上：

```text
                    ┌──────────── Plan ─────────────┐
.mbti ──▶ World ──▶ │ Sym[]        符号/形状/标签    │ ──┬──▶ .py / .pyi   调用方
 (S1)     (S3)      │ HandleSlot[] 每类型一张句柄表   │   └──▶ guest.mbt    应答方
                    └───────────────────────────────┘
```

一份计划，两半投影，**两半不可能不一致**。顺带把"看得见"变成"用得上"：生成的类现在真的能
`Position(3, 7)`、读 `line`、写 `cursor`。

| | S3 | S4 |
|---|---|---|
| guest 侧 dispatch | 手写 270 行 | **生成 1161 行**（`--guest` / `--guest-out`） |
| 句柄表 | 手写 12 张 | **按用到的具体类型生成** |
| 生成类的可调用成员 | 只有方法 | 方法 + `__init__` + `@property` + setter |
| 端到端断言 | 调通 + 释放 | 构造、读、写、句柄实参、`dropped=0` |
| 10 万次基准 | 4 个用例 | 6 个用例，150 万帧，内存平直 |

验收又抓到一个不报错的泄漏：`parse` 返回 `Json` 的句柄，而 `Json` 是 **enum**，
`render_enum` 从来没写 `moon_type_id`——`close()` 发出 `release_tag(0, id)`，guest 里没有 tag 0 的表，
**什么都没释放**，Python 侧却把这次释放算成功。只有 `Runtime.dropped` 看得见它。
细节见 [S4 对象模型](docs/s4-object-model.md)。

## S5：容器、回调与异常

到 S4 为止，能调的函数都是**标量函数**：`Array`、`Map`、`Option`、`Result`、函数值全在
`unmarshalable-param` 这一格里。S5 把这一格清掉，Python 侧不需要任何新类型：

```python
Json.array([Json.number(1.0), Json.string("two")])   # list -> Array[Json]
Json.object_({"a": Json.number(1.0)})                # dict -> Map[String, Json]
mcb.call_with(lambda x: x + 2, 40)                   # callable -> Int32 id
try: mjson.parse("{oops")
except mjson.ParseError as exc: ...                  # suberror -> except 类
```

回调是这里唯一需要新机制的东西：wire 上只有一个 `Int32` id，guest 通过 **wasm import**
回头调用宿主，所以回调发生在 guest 栈上——没有协程、没有重放、没有第二个线程。

| | S4 | S5 |
|---|---|---|
| wire 形状 | 8 个标量 | 递归树（`WArr` / `WMap` / `WRes` / `WCall`） |
| guest 符号 | 49 | **54** |
| `unmarshalable-param` | 15 | **14** |
| 端到端断言 | 29 | **42** |

验收抓到的是一类"只在重新生成之后才红"的 bug：`Option[T]` 的解码器就是 `T` 的解码器，
于是按名字去重时 `WMaybe(WInt)` 会把 `dec_int` 这个名字占住却什么都不写，真正的报错出现在
生成物的 `dec_int is unbound`。名字和形状不是一对一，这一课写在
[S5 容器与回调](docs/s5-containers-and-callbacks.md) 里，连同"回调通道被建立 ≠ 通得过"
（`debug_assert` 在 release 下被编译掉，实测 0 次调用）一起。

## 开发

```bash
# MoonBit 侧
moon check --deny-warn
moon test  --deny-warn
moon fmt --check

# 语料（core 子集离线可跑；all 需要网络）
bash scripts/corpus.sh core
bash scripts/corpus.sh all

# 生成 Python stub 并跑 mypy strict
bash scripts/gen.sh all

# 生成 + 端到端 + 基准（需要 python + wasmtime）
bash scripts/e2e.sh
BENCH_CALLS=20000 bash scripts/e2e.sh   # 快速跑一遍

# Spike 复现（需要 Python 3.10+ 与 wasmtime）
cd spikes/01-wasm-python/module && moon build --target wasm && cd ..
python bridge_test.py
```

> CLI 目前在 js 后端运行（唯一不依赖 C 工具链的后端），文件读取只有一处
> `extern "js"`，其余代码与目标无关。

工具链：MoonBit `0.1.20261023`（moonc `0.10.17`）/ Python 3.13 / wasmtime 50.0.1。

---

## 路线图

- [x] **S0** 宿主 ABI 可行性：wasm 导出、内存共享、UTF-8 往返
- [x] **S1** 接口 IR：解析 `moon info`，覆盖 struct / enum / 泛型 / trait / 别名
      （501 个真实接口文件 100% 通过，见 [报告](docs/s1-corpus-report.md)）
- [x] **S2** 类型映射与代码生成：501 个包生成 `.pyi`，`mypy --strict` 0 报错
      （见 [报告](docs/s2-type-mapping.md)）
- [x] **S3** 跨包句柄与生命周期：真实 json 包端到端可调，10 万次往返 0 泄漏、内存不涨
      （见 [报告](docs/s3-runtime.md)）
- [x] **S4** 生成 guest 与对象模型：dispatch 表与句柄表由计划产出，对象可构造/读/写，
      10 万次 × 6 用例 150 万帧 0 泄漏（见 [报告](docs/s4-object-model.md)）
- [x] **S5** 容器、回调与异常字段：`Array` / `Map` / `Option` / `Result` / `Callable` 全部可跨边界，
      `suberror` 变成 Python 异常类（见 [报告](docs/s5-containers-and-callbacks.md)）
- [ ] **S6** PEP 517 打包、真实包端到端、批量协议与基准
- [ ] **S7** native(C ABI) 后端、CI 矩阵、文档站

---

## 与现有生态的关系

MoonBridge 不重新实现任何已有能力：JSON、CSV、正则、压缩等一律复用 mooncakes 上的包，
它只负责**把它们的接口翻译到 Python**。如果你在找一个 JSON 查询引擎，请用
`moonbit-community/moonbit-jq`；MoonBridge 的价值在于让那类库能被 Python 直接调用。

---

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
