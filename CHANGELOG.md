# Changelog

本项目的开发按阶段推进（S0–S7），每个阶段有独立报告（`docs/`）与可复现命令。
版本号遵循 mooncakes 发布版本；日期为提交日期。

## [0.1.2] — 2026-11-28

适配 MoonBit 1.0 release candidate（moon `0.1.20261126` / moonc `1.0.0-rc1`）：

- `src/abi/codec.mbt`：三处 `Buffer::write_bytes` 改为 `write_bytesview`，字节输出不变。
- `src/gen/guest_gen.mbt`：生成的 `dispatch` 上局部标注 `#warnings("-deprecated")`。
  core 1.0 RC 给 `json::parse` 的 `max_nesting_depth` 加了 `label_migration(..., fill=false)`
  且无替代别名，生成器仍按接口原样投射可选参数，故只在生成代码里抑制这一类告警，
  其余告警保持开启；`--deny-warn` 重新全绿。生成物已按新语料重新产出。
- CI 新增显式的 `moon build --target wasm --release` 步骤，让检查 / 构建 / 测试三段都在门禁里可见。
- 全语料 565 个 `.mbti`、565 个 stub，`mypy --strict` 561 个源文件 0 报错；
  171/171 MoonBit 测试、`moon check / test / fmt --deny-warn`（wasm + js）全过。

## [0.1.1] — 2026-11-23

已发布至 mooncakes.io（`moon add gyyyy6/moonbridge@0.1.1`）。0.1.0 之后的所有内容都在这个版本里：
批量协议（S7）与适配 core `0.10.22` 的生成器修复。0.1.0 在新工具链下无法通过 `moon check`，
所以 0.1.1 是第一个能在 `moon 0.1.20261119 / moonc 0.10.22` 上直接安装使用的版本。

### 适配 core 0.10.22

CI 只装 `latest` 工具链，`moon 0.1.20261119 / moonc 0.10.22` 让 `MoonBit (check/test/fmt)` 与
`End to end` 两个 job 变红：新 core 废弃了五个 API，并把 `@lexbuf.StringScanner` 改成了只读类型。
以下修复都在生成器侧完成，生成物重新产出，没有手改 `src/guest_gen`。

- fix(gen): `Bytes::new(n)` → `Bytes::make(n, b'\x00')`（`src/gen/guest_gen.mbt` 四处模板）
- fix(gen): 「返回 `suberror` 值」的函数不再生成绑定。`DecodeContext::error` 原来会生成
  `wrap(JsonDecodeError, ...)`，而错误类由消息构造、`wrap` 又只接受对象基类，运行时与类型检查都过不去；
  现在按 `unmarshalable-return` 跳过——错误只以异常形式跨边界，这与 S5 的既有约定一致
- fix(gen): `StringScanner` 只读化后，重新生成即自动不再产出构造器与 `cursor` 写入，
  不再是「生成出编不过的代码」
- test: 探针包 `src/callbacks` 增加 `Cursor { mut pos, label }`；`bench/e2e.py` 与 `bench/bench.py`
  的 setter 用例改打它，字段写入的覆盖不再依赖标准库里恰好还有可变结构体
- chore: 重新生成 guest（core 语料 140 个接口 / 4,445 条声明 / 解析 100%）、重建 wheel
  （全语料 562 个接口 / 554 个存根，`mypy --strict` 558 文件 0 报错；wheel 629,953 B / 569 条目 /
  555 个 `.pyi` / guest wasm 386,651 B）
- 门禁：`moon check/test/fmt --deny-warn`（wasm + js）、171/171 测试、`mypy --strict` 144 文件 0 报错、
  `scripts/e2e.sh` 42 条断言 + 0 泄漏、wheel 安装后 14 项断言全绿

## [Unreleased] — 批量协议（S7 部分）

- feat(abi): 新增批量帧容器 `<u32 count>(<u32 len><frame>)*` 与 `mb_call_batch` 导出，复用既有 dispatch
- feat(runtime): `WasmHost.call_batch`、`Runtime.request_many` / `crossings`、公开 `run_batch()`，并为可批量函数自动生成 `<fn>_many`
- perf: 10 万次 `json::valid` 调用 4.034s → 0.687s（40.34 → 6.87 µs/call，5.87x），跨界次数 100,000 → 391
- test: 批次中途类型化失败仍 `live=0`（成功的帧在抛错前全部释放）；171/171 测试在 wasm + js 双目标通过
- docs: 新增 `docs/batching.md`（三个方向的评估与协议设计），同步 README、usage-guide、ADR 0001 与复盘

## [0.1.0] — 2026-11-06 ～ 2026-11-08

首批发布，覆盖 S0–S6。已发布至 mooncakes.io（`moon add gyyyy6/moonbridge@0.1.0`）。

- S0 宿主 ABI 可行性：wasm 导出、线性内存共享、UTF-8 往返；实测每次调用开销（nop 6.9 µs / 单参 16.6 µs）
- S1 接口 IR：手写 `.mbti` 递归下降解析器 + 类型图（拓扑序、Tarjan SCC、外部类型）
- S2 类型映射与 Python 代码生成：四级降级阶梯、命名规则、`mypy --strict` 校验
- S3 跨包句柄与运行时：世代句柄表、批量回收、wasmtime 宿主；真实 `json` 包端到端，10 万次 0 泄漏
- S4 生成 guest 与对象模型：一份 `Plan` 两半投影，dispatch 表 270 行手写 → 1161 行生成；对象可构造 / 读 / 写
- S5 容器、回调与异常：`Array` / `Map` / `Option` / `Result` / 函数值跨边界，`suberror` → Python 异常类
- S6 PEP 517 打包：自写 219 行构建后端、`requires = []`、两次构建 sha256 一致、仓库外安装后 11 项断言全绿
- 工程：CI 六 job（check / test / fmt 双目标、REUSE、语料、`mypy --strict`、端到端、spike）；Apache-2.0 + REUSE 标注

修复（均由断言而非人工 review 发现，详见 `docs/development-retrospective.md`）：

- 0 号句柄被当作"没有对象"，首份文档永不释放
- 导出函数返回值泄漏（41 字节 / 次；改用 `FixedArray[Byte]` 复用后往返 46 → 34 µs）
- 世代计数器回绕（每 1023 次释放漏一份文档）
- enum 未登记 `moon_type_id`，`close()` 报成功但 guest 未释放
- `Option[T]` 解码器与 `T` 同名去重导致生成的 `dec_*` 未定义
