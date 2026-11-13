# 开发复盘：MoonBridge 的可解释性记录

> 记录日期：2026-11-13 ｜ 面向：终期验收 / 代码审阅
>
> 目的：让任何没有参与开发的人，都能沿着「**决策 → 证据 → 复现命令**」解释仓库里的每一个技术选择，
> 包括那些由 AI 辅助得出的选择。

## 0. 这份文档要回答什么

1. **为什么这样设计？**（关键架构决策）
2. **AI 到底做了什么、人做了什么？**（开发流程中的具体角色）
3. **如果评委指着某一行代码问「为什么」，翻哪个文件能答上来？**（AI 可解释）

一条原则贯穿全文：**没有证据的主张不写进仓库**。决策要有 ADR，数字要有可复现命令，
失败要有复盘，边界要有可数的清单。AI 给出的结论，只有被本地命令或测试复现之后才算数。

---

## 1. 关键架构决策

### 1.1 为什么 wasm 优先，而不是 native（C ABI）

**决策**：默认后端 wasm；native 只作为可选的 `--backend native` 性能路径；hot path 一律批量协议；
GC 托管对象过界一律用句柄而非裸指针。完整论证见 [ADR 0001](decisions/0001-wasm-first.md)。

**为什么**：

- **免 C 工具链**。本机 Windows 只有 mingw gcc，没有 MSVC Build Tools，
  `moon build --target native` 直接失败。若以 native 为默认，"先装 2GB 工具链"就成了 hello world 的前置条件，
  且 wheel 必须按平台矩阵分发。
- **一个 wheel 走天下**。wasm 让 `py3-none-any` 单 wheel 成立（[`pack/moonbridge_build.py`](../pack/moonbridge_build.py)、
  [`scripts/wheel.sh`](../scripts/wheel.sh)）；`moon.mod` 里的 `preferred_target = "wasm"` 是这条决策的机器可读形式。
- **崩溃隔离、线性内存可直读**。guest 崩溃不会带走 Python 解释器进程。

**实测，不是推断**：Spike 01 在 Windows 11 / Python 3.13 / wasmtime 50.0.1 上测得
纯 wasm `nop` 6.9 μs、`id(i32)` 16.6 μs、MoonBit `add` 22.7 μs。基线本身就占了绝大部分开销，
说明**瓶颈在 Python 绑定层，不在 MoonBit**。所以换 ABI 不会让单次调用明显变快，
真正该优化的是**跨越次数**。复现：[`spikes/01-wasm-python/README.md`](../spikes/01-wasm-python/README.md)、
[`baseline_overhead.py`](../spikes/01-wasm-python/baseline_overhead.py)、
[`bridge_test.py`](../spikes/01-wasm-python/bridge_test.py)；数据同时抄在 README 的「Spike 01 结论」里。

同一个 spike 还给出了句柄协议的物理原因：`String` / `Bytes` 参数在 wasm ABI 里是**单个 i32 对象指针**
（不是 `(ptr, len)`），而 MoonBit 的 GC 随时可能回收它——宿主只能持有不透明句柄，不能持有裸指针。

**否决了什么**：只用 native（MSVC 前置条件）；只用 ctypes + 手写胶水（回到生态现状、没有增量）；
wasm-gc + 组件模型（当时 Python 侧运行时对 GC 提案支持不齐，留作演进路径）。
**代价**也写进 ADR「后果」：单次调用比 native 慢一个数量级、wasm 侧无法使用系统库、调试栈更深。

### 1.2 为什么设计 Plan 模型（S4）

**问题**：S3 时 Python 侧 `.py` / `.pyi` 是生成的，但 guest 的 dispatch 表是 270 行手写
（当时在 `src/guest_json/`，S4 删除）。手写的表不会因为编译失败被发现，只会在某次调用悄悄返回错的字段；
签名、句柄表编号、错误类型会各自漂移。

**决策**：一份 `Plan`，两半投影。

```text
                    ┌──────────── Plan ─────────────┐
.mbti ──▶ World ──▶ │ Sym[]  符号 + wire 形状 + 标签  │ ──┬──▶ .py / .pyi   调用方
 (S1)     (S3)      │ HandleSlot[] 每类型一张句柄表    │   └──▶ guest.mbt    应答方
                    └────────────────────────────────┘
```

[`src/gen/symbols.mbt`](../src/gen/symbols.mbt) 是两半唯一的真相：
`Sym[]` 记录符号名、参数 wire 形状（`WInt` / `WStr` / `WMaybe` / `WHandle` / `WArr` / `WMap` / `WRes` / `WCall`）、
标签、返回形状、是否抛错；`HandleSlot[]` 按实际用到的具体类型生成句柄表。
[`src/gen/pyi.mbt`](../src/gen/pyi.mbt) / [`runtime_gen.mbt`](../src/gen/runtime_gen.mbt) 渲染 Python 侧，
[`src/gen/guest_gen.mbt`](../src/gen/guest_gen.mbt) 渲染 guest 侧。

**为什么不是「两边各写各的，再加一个一致性测试」**：测试只能覆盖被测到的字段；
Plan 让不一致在结构上不可能发生，而不是事后检查。[S4 报告](s4-object-model.md)里的 `takes_self`
是个具体例子——`Hasher::Hasher(seed?)` 是关联函数不接 `Self`，`Point::norm(Self)` 要接；
少了这个判断，guest 会给构造函数塞一个幽灵首参，编译能过、调用才错。

生成物 [`src/guest_gen/guest.mbt`](../src/guest_gen/guest.mbt) **提交入库**，理由写在
[S4 报告「六、复现」](s4-object-model.md)：一次 `git clone` 就能 `moon build`，不必先跑一遍生成器；
而 `scripts/e2e.sh` 每次都会重新生成并在内容不同时提示漂移。

**证据**：提交 `307d3f9`（plan the symbols）→ `8c74167`（generate the guest half from the plan）
→ `91afd6f`（bind constructors and fields）；[S4 报告](s4-object-model.md)、README「S4」节、
[申报书](../项目申报书.md)「原创性说明」第 1 条。

### 1.3 其余关键决策速查表

| 决策 | 为什么 | 代价 / 被抓到的反例 | 仓库内证据 |
| --- | --- | --- | --- |
| 世代句柄 `(slot << 10) \| generation`，0 号留给「无对象」 | 宿主永不拿到悬垂指针，旧 id 不能指向被复用的槽位 | 0 号句柄曾被当成「没有对象」，第一份文档永不释放；世代 10 位回绕每 1023 次漏一个 | [`src/abi/handle.mbt`](../src/abi/handle.mbt)、[S3 报告](s3-runtime.md)、提交 `fecea66` / `622a14e` |
| 四级降级阶梯 + 每次降级记账 | 不让 `Any` 静默吞掉类型精度 | 函数类型降级为 `Any` 而**不是** `Callable`：S2 没有回调蹦床，写 `Callable` 等于承诺一条走不通的路 | [`src/map/type_map.mbt`](../src/map/type_map.mbt)、[S2 报告](s2-type-mapping.md) |
| stub 之间互不 import | MoonBit 包图含 48 个环，跨包类型暂时走 `Any` | 精度损失；S3 用 World 索引把 `foreign` 降级从 4812 收到 605 | [`src/map/world.mbt`](../src/map/world.mbt)、README「S2 / S3」 |
| 回调走 wasm import，在 guest 栈上同步执行 | Python 可调用对象不能复制进线性内存，wire 上只传 `Int32` id | 无协程 / 重放 / 第二线程；`debug_assert` 在 release 下被编译掉，实测 0 次调用 | [`src/callbacks/`](../src/callbacks/)、[S5 报告](s5-containers-and-callbacks.md) |
| 自写零构建依赖 PEP 517 后端（`requires = []`） | 断网也能构建、两次构建 sha256 一致，用户不必先装 setuptools | 运行时仍需 `wasmtime>=20`；冒烟测试必须从仓库外跑，否则会误导入 `_gen/` | [`pack/`](../pack/)、[S6 报告](s6-wheel.md)、[`scripts/wheel_smoke.py`](../scripts/wheel_smoke.py) |
| 语料钉版本、只取发布的 `.mbti` | 第三方接口是外部产物，靠「最新」无法复现；`mooncakes` 包自带 `pkg.generated.mbti`，正是生成器真实会拿到的输入 | 工具链升级后语料从 501 扩到 561，数字必须按快照日期分开记 | [`corpus/packages.txt`](../corpus/packages.txt)、[`scripts/corpus.sh`](../scripts/corpus.sh)、[申报书「复现更新」](../项目申报书.md) |
| 把「泄漏」写成断言而不是报告 | 四个 bug 都不报错，只让内存缓慢上涨 | `dropped` 计数是唯一能区分「释放了」和「以为释放了」的数字 | [`bench/`](../bench/)、[`scripts/e2e.sh`](../scripts/e2e.sh)、S3/S4 报告 |

---

## 2. AI 工具在开发流程中的具体角色

### 2.1 先把记录边界说清楚

- 本仓库 git 历史只有一个作者 `gyyyy6`（`git log --format='%an <%ae>' | sort -u` 可核），
  commit message 无 `Co-authored-by`，仓库内没有 `AGENTS.md` 或 AI 会话日志。
  → **本文不把任何具体源文件归因于某个 AI 工具**；能核对的是「AI 参与过的活动」以及「这些活动留在仓库里的产物」。
- AI 会话级工作记录保存在工作区 `.workbuddy/memory/2026-11-06.md` 与 `2026-11-08.md`，
  位于 **git 仓库之外**（仓库根是 `MoonBridge/`）。这本身就是可解释性缺口，
  本文第 3 节把它压缩成仓库内可核对的记录。

### 2.2 WorkBuddy 的角色（按阶段）

| 阶段 | AI 具体做了什么 | 人做了什么决定 | 留在仓库里的产物 |
| --- | --- | --- | --- |
| 选题与去重 | 跑 70+ 组 `moon search`，梳理 Node（`napi-mbt`）/ Java（`ajni`）/ C（`moonbind`，反方向）/ TS 的已有方案；指出前身项目 MoonQuery 与 `moonbit-jq` 重叠、初审被驳回；识别出「Python / Go / Rust 的绑定生成器」这个空白形态 | 用户拍板放弃 MoonQuery、启动 MoonBridge | README「为什么要做这个」生态对照表；[`corpus/packages.txt`](../corpus/packages.txt) 里 20 个按领域挑选并钉版本的模块 |
| 可行性验证 | 设计并执行 Spike 01（导出、共享内存、双向字节流、UTF-8 往返、200k 次计时基线），把结论写成 ADR | 接受 ADR 的取舍 | [`spikes/01-wasm-python/`](../spikes/01-wasm-python/)、[ADR 0001](decisions/0001-wasm-first.md) |
| 分阶段实现与验收 | 按 S0–S6 拆阶段、写可复现脚本、把每阶段的数字与「抓到的 bug」写成报告 | 逐阶段审核数字、决定哪些能力算完成 | `docs/s1..s6-*.md`、`scripts/*.sh`、60 余个按模块拆分的提交 |
| 故障诊断（AI 价值最集中的部分） | 见下方三个例子：日志归因、隔离环境复现、干净 venv 复现 | 用户提供 CI 日志、确认修复方向、决定何时推送 | 提交 `2f4437d` / `7f15c96` / `68f0d2a` / `17a7409`，以及 [`ci.yml`](../.github/workflows/ci.yml) 里的注释 |
| 材料与合规 | 申报书字段核对、Gitlink 导入路径核对、mooncakes / REUSE / CI 自查清单 | 用户填写表单、提供账号凭证、执行对外发布 | [`项目申报书.md`](../项目申报书.md)、本文、[`REUSE.toml`](../REUSE.toml) |

三个体现「先复现再改」的诊断例子：

1. **CI 全绿 ≠ 覆盖到位**。语料下载失败被脚本降级成警告，只解析 139/561 个 `.mbti`、mypy 只查 143 个文件，
   门禁照样通过。用 `MOON_HOME` 硬链出一个没有 registry index 的隔离环境精确复现，
   再把「本轮新增第三方 `.mbti` 为 0」改成硬失败 → `17a7409`。
2. **工具链漂移**。新版编译器把 `} derive(...)` 判为 deprecated（在 `--deny-warn` 下 35 条全变 error），
   且 `Json` 从 `builtin` 迁到 `json` 包。隔离安装新版复现后：`moon fmt` 自动迁移 48 处、
   用新 core 重新生成 `src/guest_gen`、修生成器三类真实不兼容 → `7f15c96`。
3. **本地绿 / CI 红**。Stubs job 只装了 mypy，生成的包里 `_wasmtime.py` 会 `import wasmtime`，
   于是报 `import-not-found`。用干净 venv 复现 → `68f0d2a`。
   教训写进仓库：本地验证 Python 门禁必须用干净 venv，不能用装了额外依赖的全局解释器。

### 2.3 Codex 的角色与边界

- Codex 的**可核对记录出现在前身项目**：`MoonQuery/项目申报书.md` 写着
  「深度使用 AI Agent（Codex）进行 TDD 迭代与工程文件生成」。该项目因「生态重叠且没有增量」被初审驳回，
  其申报书与 20 个提交留在工作区，**不在本仓库内**。
- 它带来的**方法性影响**是真实的：正因为那次驳回，MoonBridge 立项前先做了 70+ 组 registry 检索，
  并把「是否为移植项目 / 是否复制上游代码」明确写进[申报书](../项目申报书.md)的「原创性说明」与「生态增量」；
  语料里的第三方包只作为 `.mbti` 输入，**没有复制或改写其源码**，生成器输出的是这些库原本不存在的 Python 接口。
- 但 **MoonBridge 仓库内没有 Codex 的逐文件产出记录**。按「没有证据就不归因」的原则，
  本文不声称某段 MoonBit 代码由 Codex 编写；若确有使用，应补一条「工具 / 阶段 / 产物 / 复核人」记录。
  这条空缺已列入第 3.4 节的自查结果。

### 2.4 人机分工的约束

| AI 负责 | 人负责 |
| --- | --- |
| 生态检索、方案对比、假设生成 | 选题拍板、项目边界与「做完」的定义 |
| 复现脚本、日志归因、隔离环境构造 | 提供真实日志与凭证、确认修复方向 |
| 代码草稿、测试草稿、文档草稿 | 逐阶段审核数字、接受或否决降级与边界 |
| 合规 / 验收自查清单 | 提交与署名、对外发布与表单填写 |

**硬约束**：AI 的结论只有被 `moon check --deny-warn`、`moon test --deny-warn`、
`mypy --strict` 或 `scripts/e2e.sh` 复现后才能写进 README / 申报书；
数字变动要注明快照日期（[申报书「复现更新（2026-11-08）」](../项目申报书.md) 保留了 11-06 提交快照而不覆写它，
就是这条约束的落实）。

---

## 3. 「AI 可解释」原则的体现

### 3.1 四条落地规则

1. **每个决策有「为什么 + 否决了什么 + 代价」**：ADR 0001 与六份阶段报告，而不是只有结论。
2. **每个数字有可复现命令**：README「开发」节、`scripts/*.sh`、CI 的每个 job。
3. **每个失败都有复盘**：S3 三个静默泄漏、S4 的 enum 漏标签、S5 的 `dec_int is unbound`、
   CI 的四轮修复，都连同「怎么定位的」一起写进报告。
4. **每个边界都可数**：`Plan` 的 skipped 原因、降级原因汇总、[S4「S4 没做的」](s4-object-model.md)、
   路线图里未勾选的 S7。宁可少给一个方法，也不给「调了才知道不行」的接口。

### 3.2 证据索引（评审现场用）

| 想解释什么 | 打开哪个文件 | 一条复现命令 |
| --- | --- | --- |
| 为什么是 wasm | [ADR 0001](decisions/0001-wasm-first.md) + [`spikes/01-wasm-python/`](../spikes/01-wasm-python/) | `python spikes/01-wasm-python/baseline_overhead.py` |
| 为什么有 Plan | [S4 报告](s4-object-model.md) + [`src/gen/symbols.mbt`](../src/gen/symbols.mbt) | `bash scripts/e2e.sh` |
| 句柄为什么带世代 | [`src/abi/handle.mbt`](../src/abi/handle.mbt) + [S3 报告](s3-runtime.md) | `moon test --target wasm --deny-warn` |
| 为什么会有 `Any` | [S2 报告](s2-type-mapping.md) + [`src/map/type_map.mbt`](../src/map/type_map.mbt) | `bash scripts/gen.sh all` |
| 回调为什么不另起线程 | [S5 报告](s5-containers-and-callbacks.md) | `bash scripts/e2e.sh` |
| wheel 为什么零构建依赖 | [S6 报告](s6-wheel.md) + [`pack/moonbridge_build.py`](../pack/moonbridge_build.py) | `bash scripts/wheel.sh` |
| 数字是否可信 | [申报书「复现更新」](../项目申报书.md) + `docs/s*.md` 各阶段快照 | `bash scripts/corpus.sh all` / `bash scripts/e2e.sh` |
| 当前是否真的绿 | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | `moon fmt --check` / `moon check --deny-warn` / `moon test --deny-warn` |
| 许可证与第三方来源 | [`LICENSE`](../LICENSE) + [`REUSE.toml`](../REUSE.toml) | `reuse lint`（需安装 REUSE 工具） |
| AI 参与的边界 | 本文第 2 节 | `git log --format='%an <%ae>' \| sort -u` |

### 3.3 可复现清单

```bash
moon version --all
moon fmt --check
moon check --target wasm --deny-warn
moon check --target js   --deny-warn
moon test  --target wasm --deny-warn     # 168/168
moon test  --target js   --deny-warn     # 168/168
bash scripts/corpus.sh all               # 561 文件 / 19,098 声明 / 100% 解析
bash scripts/gen.sh all                  # 561 stub + mypy --strict
bash scripts/e2e.sh                      # 端到端 + 10 万次基准 + wheel 安装冒烟
bash scripts/wheel.sh
```

> 数字为 2026-11-08 工具链（moon `0.1.20261104` / moonc `0.10.20`）下的复现值；
> `docs/s*.md` 保留各阶段完成时的快照，README 顶部 S0–S6 状态是 11-06 快照。
> 两套数字并存且注明日期，是刻意保留的：不抹掉已经提交的申报快照。

### 3.4 主动列出的反证与自查结果

可解释不等于「看起来都解释得通」，还要主动指出**解释不了的地方**：

- 没有逐文件的 AI 产出归因（见 2.1 / 2.3），Codex 在 MoonBridge 内无记录。
- AI 会话记录原本在仓库外（本文补上仓库内版本）。
- `src/guest_gen/guest.mbt` 是生成物却入库 → 靠 `scripts/e2e.sh` 的漂移提示兜住；
  若某次提交只改了生成器没重生成，评审应能看到差异。
- CI 曾出现「绿色但语料缩水到 1/4」→ 已改为硬失败，但**任何把外部依赖失败降级成警告的脚本都仍是同类风险**。
- 第三方 `.mbti` 语料不入库、构建时下载 → 完整复现依赖网络；离线可用 `bash scripts/corpus.sh core`（标准库子集）。
- MoonBit 安装 CDN 只提供 `latest` / `nightly`，**工具链不能钉版本** →
  每次漂移都必须跑 `moon fmt` 并用新 core 重新生成 `src/guest_gen`，这条约定写在 [`ci.yml`](../.github/workflows/ci.yml) 顶部注释里。

---

## 4. 尚未闭合的项

- **mooncakes.io 发布**：`moon login` 需交互式终端、账号凭证由用户持有；本文不声称已经发布，
  发布成功后再由 README 补徽章与 `moon add gyyyy6/moonbridge` 安装指引。
- **S7**：native（C ABI）后端、CI 平台矩阵、文档站。
- **Codex 逐文件产出记录**（若确有使用）与 AI 会话记录的仓库内归档。
- **30 秒演示视频 / GIF**：条件允许时补充；当前仓库提供可复现的终端命令链作为等价演示。

---

## 相关文档

[README](../README.md) ｜ [申报书](../项目申报书.md) ｜ [ADR 0001](decisions/0001-wasm-first.md) ｜
[S1](s1-corpus-report.md) · [S2](s2-type-mapping.md) · [S3](s3-runtime.md) ·
[S4](s4-object-model.md) · [S5](s5-containers-and-callbacks.md) · [S6](s6-wheel.md)
