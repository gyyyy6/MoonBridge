# Changelog

本项目的开发按阶段推进（S0–S7），每个阶段有独立报告（`docs/`）与可复现命令。
版本号遵循 mooncakes 发布版本；日期为提交日期。

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
