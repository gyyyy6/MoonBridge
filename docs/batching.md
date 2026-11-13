# 批量协议（Batching）报告

> 2026-11-13 ｜ 对应 ADR 0001 的第 2 条决策 ｜ 状态：**已实现并验证**

## 0. 一句话结论

新增一个 wasm 导出 `mb_call_batch`，让 N 次 Python→MoonBit 调用共用一次跨语言跨越。
10 万次 `json::valid` 实测 **40.34 μs/次 → 6.87 μs/次，5.87× 加速**，宿主跨越次数
**100,000 → 391**；原有 168 个 MoonBit 测试、10 万次 × 6 用例的句柄与内存不变量全部保持。

---

## 1. 为什么选这个方向：三个方向的实测评估

终期冲刺给了三个候选方向。先用仓库里能拿到的数据算一遍账，再动手。

| 方向 | 实测证据 | 判断 |
| --- | --- | --- |
| **一、批量协议** | S0 已测出单次往返 6.9–22.7 μs，且 ADR 0001 明确写了「hot path 一律批量」却一直没实现。`mb_call` 的 dispatcher 是纯函数 `dispatch(symbol, payload) -> Status`，可以被 N 次复用 → 改动是**加性的**，不碰已有帧格式。 | **选它**：直接打在已测出的瓶颈上；只新增一个导出，不动语义；收益可量化。 |
| 二、泛型单态化 | `gen.sh all` 的降级构成是 `foreign=622 unknown=558 result=142 higher-order=605 async=110`；S2 报告里「泛型 / 返回位类型变量」只占 **66 处**（约 1%）。剩下的大头来自**跨包 stub 互不 import**（类型图本次实测 50 个含环文件），这是 S2 为让每个 `.pyi` 独立可检查而做的架构取舍，不是泛型问题。而且 S5 之后运行时早已用 `WArr` / `WMap` / `WRes` 递归形状按具体实例生成解码器，"单态化"在 stub 注解层做，运行时行为不变。 | 否：前提与现状不符，收益约 1%，却要动跨包导入与环检测，风险最高。 |
| 三、增量生成缓存 | 本机计时：`scripts/gen.sh all` 全程 **40.6 s**，其中 `scripts/corpus.sh all` 约 **37 s**（读注册表/收集 561 个 `.mbti`），`CLI --gen` 热跑仅 **1.3 s**，`mypy --strict` 约 2 s。缓存能跳过的恰好是那 1.3 s，即**上限约 3%**。另外 `run_gen` 从全部 package 构建一个 `World`（330 个模块 / 648 条导入边），任一 `.mbti` 变动都可能改变别的 stub；按单文件哈希跳过需要额外维护依赖图，而 `gen.sh` 目前的 `rm -rf "$OUT"` 也会让缓存失效。 | 否：能跑通但收益太小，且正确性需要额外机制，不值当。 |

**结论**：方向一是唯一同时满足「收益显著、改动加性、可证伪」的一项。方向二、三的评估数据也留在这里，
评审时可以直接复算，而不是只看一句"我们选择了 A"。

---

## 2. 协议设计

### 2.1 帧格式（两边同一份字节表）

`src/abi/codec.mbt` 新增 `encode_batch` / `decode_batch`，容器格式：

```text
batch := <u32 count> (<u32 len> <frame bytes>)*
frame := 对请求： <u32 sym_len> <symbol utf8> <payload>   （与 mb_call 的子帧完全一样）
         对响应： <status frame>                          （@abi.encode_status 的原样输出）
```

- 请求与响应**共用同一个容器**，所以一组 golden 向量就能钉住两个方向。
- Python 侧 `_codec.dump_batch` / `_codec.load_batch` 由 `render_codec()` 生成，
  与 MoonBit 侧同表；`codec_test.mbt` 里的字节级断言是二者不会漂移的保证。
- 长度越界、尾部多余字节一律 `DecodeError` / `truncated batch`，绝不短读——短读会把
  下一帧的头当成上一帧的数据，把一个坏帧变成两个错答案。

### 2.2 分层

| 层 | 文件 | 新增内容 |
| --- | --- | --- |
| wire | `src/abi/codec.mbt` | `encode_batch` / `decode_batch` + `Cursor::u32` / `write_u32` |
| guest（MoonBit） | `src/gen/guest_gen.mbt` → 生成 `src/guest_gen/guest.mbt` | `run_one` / `batch_error` / `#export_name("mb_call_batch")` |
| transport（Python） | `src/gen/runtime_gen.mbt` → `_wasmtime.py` | `WasmHost.call_batch`；找不到导出时退化为 N 次单次调用 |
| runtime（Python） | 同上 → `_runtime.py` | `Runtime.request_many`、`crossings` 计数器、`_release_partial` |
| 公共 API | 同上 → `__init__.py` | `moonbridge.run_batch(symbol, calls, wrap=None)` |
| 生成器 | `src/gen/pyi.mbt` | 为可批量函数产出 `<fn>_many` |

`run_one` 直接调用**同一个** `dispatch`，所以句柄表、回调蹦床、类型化异常、释放路由在批量路径上
与单调用路径逐字相同——不存在"第二套协议慢慢漂移"的问题。答案先收进本地数组，最后 `publish` 一次：
`publish` 写的是共享响应缓冲，而批量中间若触发回调，回调也用同一个缓冲传参，逐帧 publish 会互相覆盖。

### 2.3 `*_many` 的生成规则

ADR 0001 承诺「生成器对可批量的 API 自动提供 `*_many` 变体」。本次兑现，规则写死在
`src/gen/pyi.mbt`：

- 只对 **Bind**（可调用的 `.py` 模块）生成，stub 不生成；
- 至少一个参数，且**全部是位置参数**——labelled / optional 参数在元组里没有无歧义的位置；
- 参数形状里**没有函数值**——Python callable 需要先经 `callback_id` 登记，批量元组没有这个入口；
- 返回句柄时自动带 `wrap=lambda h: _runtime.wrap(<Class>, h)`，批量结果和单次调用一样有 Python 所有者。

本次 4 个绑定包里满足条件的自由函数是 `json::valid`，生成结果：

```python
def valid_many(calls: Sequence[tuple[str]]) -> list[bool]:
    """Calls `valid` once per tuple in one crossing."""
    return cast(list[bool], _runtime.default().request_many(
        "moonbitlang/core/json::valid", calls, None))
```

`json::parse` 带 3 个 optional 参数、`callbacks` 包全是函数值参数，所以**没有**生成 `*_many`。
这不是遗漏，是规则：这类调用请用低层 `moonbridge.run_batch(symbol, calls, wrap=...)`，
或继续单次调用。文档不承诺一个"调了才知道不行"的接口。

### 2.4 一个实测抓到的泄漏（以及修法）

批量是 fail-fast：遇到第一个失败帧就抛异常。但 **guest 会把整批跑完**，失败帧**之后**的成功帧
照样可能创建句柄。第一版实现只释放"失败帧之前"已经包装好的对象，结果 3 帧
（`parse(ok)` / `parse(bad)` / `parse(ok)`）的批次留下 1 个句柄。

修法在 `Runtime.request_many`：**先解码并包装所有成功帧**，再决定是否抛错；抛错前用
`_release_partial` 把这一批产生的所有句柄全部 `close()`。现在断言 `live=0`、`dropped=0`。
这个坑已固化成 `bench/bench.py` 的一条断言，防止以后有人把解码循环改回"边解边抛"。

---

## 3. 验证结果

### 3.1 10 万次对比（Windows 11 / Python 3.13 / wasmtime 50.0.1 / batch size 256）

`bench/bench.py` 里两条路径做的是**同一件事**：10 万次真实 `valid()` 调用、10 万次真实解码，
只有跨越次数不同。

| 模式 | 总耗时 | 每次调用 | 宿主跨越次数 |
| --- | --- | --- | --- |
| 循环单次调用 | 4.034 s | 40.34 μs | 100,000 |
| `valid_many` 批量 | 0.687 s | **6.87 μs** | **391** |
| **加速比** | | **5.87×** | **256× 更少** |

重跑 3 次：**5.87× / 5.89× / 5.97×**（中位数 5.89×），不是一次抖动。
6.87 μs 已接近 S0 测出的纯 wasm `nop` 基线 6.9 μs——**剩余开销基本是 MoonBit 自己执行
`valid` 的成本，绑定层已被摊薄到接近零**。这也反过来印证 ADR 0001 的判断：瓶颈从来不在
MoonBit 生成的代码，而在跨越次数。

### 3.2 不变量（无回退）

| 检查 | 结果 |
| --- | --- |
| `moon test --deny-warn`（default / wasm / js） | **171/171**（原 168 + 新增 3 条批量帧 golden 测试） |
| `moon check --deny-warn` + `moon fmt --check`（wasm + js） | 全绿 |
| `mypy --strict`（`gen.sh all`，561 个 stub / 556 文件） | 0 报错 |
| `reuse lint` | 77/77，REUSE 3.3 合规 |
| `bash scripts/e2e.sh`（10 万次 × 6 用例） | `live=0`、`dropped=0`、guest 内存曲线平直（192 / 384 KiB 不变） |
| 批量新增断言 | 加速 > 1×、跨越数下降、类型化异常仍抛、`live=0`、`dropped=0` |
| wheel 冒烟（从仓库外） | `valid_many` / `run_batch` / 「64 次调用 1 次跨越」全绿，14 项检查通过 |

`bash scripts/e2e.sh` 最后重建的 wheel 为 **621,600 字节 / 567 条目**（553 个 `.pyi`，
内含 368,859 字节的新 guest wasm），`pip install` 后即可用批量 API。

### 3.3 复现命令

```bash
# 全部回归（生成 → wasm → 端到端 → 10 万次基准（含批量对比）→ 重建 wheel）
bash scripts/e2e.sh

# 只要批量对比，缩短规模
BENCH_CALLS=20000 bash scripts/e2e.sh
```

---

## 4. 已知边界（诚实清单）

- **不是自动矢量化**：`run_batch` 不会把一个 `Array[T]` 参数自动拆成 N 次调用；调用方（或
  `*_many`）负责把 N 组参数交给它。它优化的是**跨越次数**，不是 MoonBit 内部的循环。
- **批大小有上限**：整批响应会一次性写进 guest 的响应缓冲。实测 256 稳妥；超大批量会触发
  `publish` 扩容（`FixedArray` 倍增），内存随之上涨。帧容器本身把 count 限制在 1,000,000。
- **fail-fast 语义**：一批里某次调用失败会抛异常，但**之前的子调用已经在 guest 里执行过**，
  副作用不会回滚。所以不要把"期望失败的调用"和"返回句柄的调用"混在一批里。
- **单态化与增量缓存未做**：见第 1 节的实测评估；两项都是收益/风险比不划算，不是遗漏。
- **native 后端仍未实现**（原路线图 S7），与本次批量协议互不依赖。

---

## 相关文档

- [ADR 0001：wasm 优先](decisions/0001-wasm-first.md) —— 批量协议的决策来源
- [S3 运行时](s3-runtime.md) —— 句柄表、批量释放、`dropped` 计数器
- [S6 打包](s6-wheel.md) —— wheel 与从仓库外的冒烟测试
- [开发复盘](development-retrospective.md) —— 可解释性证据索引
