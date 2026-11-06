# S1 语料报告：真实 `.mbti` 接口的解析覆盖率

> 目标：证明解析器能吃掉**真实世界里已经发布**的 MoonBit 接口，而不是只吃我们自己写的样例。
> 结论：**501 个接口文件 / 17,793 条声明 / 解析成功率 100%**。

## 语料是怎么来的

`moon info` 生成的 `pkg.generated.mbti` 是唯一权威的公开接口描述，而
**mooncakes 在发布包时会把这个文件一起打包**。所以不需要逐个 clone 仓库再本地构建
（那样每个包的依赖、工具链版本都会影响结果），直接取发布物里的接口文件即可——
拿到的是该包**发布时**的接口，正是生成器将来要面对的输入。

两部分：

| 语料 | 来源 | 文件数 | 声明数 |
| --- | --- | --- | --- |
| 标准库 | 本地工具链自带的 `$MOON_HOME/lib/core` | 79 | 2,974 |
| 第三方 | `corpus/packages.txt` 里 20 个模块 + 它们的传递依赖 | 422 | 14,819 |
| **合计** | | **501** | **17,793** |

20 个顶层模块按"一个常见领域一个头部包"挑选，且都在 `moon search` 结果里带有公开
GitHub 仓库和明确的下载量：

```
moonbit-community/yaml      mizchi/markdown        gaato/http
moonbitlang/protobuf        bobzhang/toml          moonbit-community/NyaCSV
cc06b/mooncry               mizchi/semver          cli/diff
mizchi/mwac                 ash1day/sql            mizchi/admiral
cli/test                    lampclaw/i18n          moonbitlang/regexp
f4ah6o/uuidm                hongweifei/lua         tonyfettes/xlog
moonbit-community/flate     moonbit-community/opentelemetry
```

传递依赖把语料扩大到 422 个包，覆盖了 `moonbitlang/async`（47 个包，含协程 / 事件循环 /
TLS / WebSocket）、`moonbitlang/parser`（26）、`mizchi/tui`（37）、`moonbitlang/x`（24）、
`bobzhang/moonjq`（24）等，接口形态差异足够大。

## 复现

```bash
bash scripts/corpus.sh all     # 标准库 + 第三方（需要网络，首次会下载依赖）
bash scripts/corpus.sh core    # 只跑标准库，离线可用
```

脚本会：生成依赖清单 → `moon check` 拉取发布物 → 收集所有 `.mbti` → 交给
`moon run --target js src/cli` 逐文件解析。**任何一个文件失败，退出码即非 0**，CI 里
`Corpus` 作业就是这条命令。

## 结果

```
files=501 passed=501 failed=0 declarations=17793 parse_rate=100.0%
```

## 语料逼出来的语法缺口

第一版解析器只按标准库写的，跑第三方语料时依次炸出下面这些真实构造。
每一条都是**先看到失败、再改语法、再跑全量**，不是照着语法书猜的：

| # | 真实写法 | 出现位置 | 处理 |
| --- | --- | --- | --- |
| 1 | `pub const PI : Double = 0x3.243F6A88…` | `moonbitlang/core/math` | `Const` 声明，值按原文保留 |
| 2 | `mut val : T`、`mut tail~ : List[A]` | `core/ref`、`core/list` | 字段带 `is_mut` |
| 3 | 构造器带标签字段 `More(A, tail~ : List[A])` | `core/list` | `Field.label` 记录 `?` / `~` |
| 4 | `derive(...)` 写在 `}` 的**下一行** | `quickcheck`、`string` | 向前看一个非空行再决定 |
| 5 | `pub(open) trait` | `core/random` | 新增 `Access::OpenTrait` |
| 6 | `T??` | `builtin`（`Option::flatten`） | 可选后缀改成循环 |
| 7 | `async () -> String?`、`pub async fn` | `moonbitlang/async` | `TypeExpr::Async` + `FuncDecl.is_async` |
| 8 | `@moonbit-community/otel/protocol/trace/v1.X` | `opentelemetry` | 包路径支持 `-` 与多级 `/` |
| 9 | `-> Unit noraise + nocancel` | `moonbitlang/async` | effect 从枚举改成标志集合 |
| 10 | trait 里 `pretty(Self) -> Document`（无 `fn`）、`= _` 默认实现 | `prettyprinter`、`core/builtin` | 方法可省略 `fn`，容忍 `= _` |
| 11 | `pub type Fd = Int`（`type` 直接写别名） | `async`、`moonbitlang/x` | 有 `=` 即别名，无 `=` 才是抽象类型 |
| 12 | `import( … )` 旧式导入块 | `moonbitlang/parser` | 同时接受 `(` 与 `{` |
| 13 | `type MatchResult derive(Eq)` | `core/string` | 抽象类型也能带 derive |
| 14 | `pub fn[T : Show] &Logger::write_iter(...)` | `core/builtin` | 接收者允许 `&Trait` 前缀 |
| 15 | `fn f(x : T)` 带名字的位置参数 | 自测用例 | 位置参数允许带名 |

## 解析器故意不做的事

- **不解释常量表达式**：`const` 的值按原文保存。绑定生成只需要知道它是编译期常量。
- **不展开 `pub using`**：重导出单独建节点，是否跟随由后续阶段决定。
- **不解析属性语义**：`#callsite(...)`、`#alias(...)` 等参数保留原文，供打印器还原。
- **遇到不认识的结构直接报错并给出 `line:col`**：宁可失败，也不静默跳过——
  静默跳过正是"解析成功但生成错误代码"的来源。

## 已知边界

- 语料只覆盖**发布物里的接口**。旧格式 `moon.mod.json` 的包（如 `mizchi/json`、
  `tonyfettes/lua`）当前工具链无法解析依赖，因此没有进入语料；它们对应的是更早的
  工具链版本，优先级低。
- 第三方包以 wasm 目标为主；纯 native 包的接口形态（如 `async` 相关）已有覆盖，
  但 native 专属属性未做系统枚举。
- 501 个文件里没有出现过的语法仍可能缺失。加包只需改 `corpus/packages.txt`，
  重跑脚本即可发现。
