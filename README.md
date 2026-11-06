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

> 状态：**S0 通过、S1 通过**（2026-11-06）。
> S0：调用 ABI、内存共享、宿主↔MoonBit 字节流、UTF-8 往返全部跑通，实测见
> [spikes/01-wasm-python](spikes/01-wasm-python/)。
> S1：`.mbti` 解析器 + 类型图，在 **501 个真实接口文件 / 17,793 条声明**上 100% 通过，
> 见 [S1 语料报告](docs/s1-corpus-report.md)。

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

## 开发

```bash
# MoonBit 侧
moon check --deny-warn
moon test  --deny-warn
moon fmt --check

# 语料（core 子集离线可跑；all 需要网络）
bash scripts/corpus.sh core
bash scripts/corpus.sh all

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
- [ ] **S2** 类型映射与代码生成：函数 + 值类型，生成 `.pyi` 并通过 mypy strict
- [ ] **S3** 句柄表与生命周期：`__del__` 回收、环引用、10 万次往返 0 泄漏
- [ ] **S4** 集合 / `Option` / `Result` / 回调 / 异常映射
- [ ] **S5** PEP 517 打包、真实包端到端、批量协议与基准
- [ ] **S6** native(C ABI) 后端、CI 矩阵、文档站

---

## 与现有生态的关系

MoonBridge 不重新实现任何已有能力：JSON、CSV、正则、压缩等一律复用 mooncakes 上的包，
它只负责**把它们的接口翻译到 Python**。如果你在找一个 JSON 查询引擎，请用
`moonbit-community/moonbit-jq`；MoonBridge 的价值在于让那类库能被 Python 直接调用。

---

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
