# Spike 01：Python 调用 MoonBit(Wasm)

目的只有一个：**在写生成器之前，先证明这条路真的能走通。**

## 复现

```bash
cd module
moon build --target wasm --release        # 产物：_build/wasm/release/build/moonbridge-spike.wasm

cd ..
python -m pip install wasmtime
python bridge_test.py
# 或指定构建产物
python bridge_test.py module/_build/wasm/release/build/moonbridge-spike.wasm
```

## 这个 spike 验证了什么

| # | 验证项 | 手段 |
| --- | --- | --- |
| 1 | 调用 ABI | `mb_add(2,40) == 42`、`mb_fib(20) == 6765` 从 Python 调用 |
| 2 | 内存导出 | `moon.pkg` 里 `options(link: {"wasm": {"export-memory-name": "memory"}})` |
| 3 | 对象数据偏移 | 不硬编码编译器布局，用指纹 `mb_probe()` 在内存里扫描出偏移 |
| 4 | 宿主 → MoonBit | Python 写入 16 字节，MoonBit 侧 `mb_buf_checksum` 校验和一致 |
| 5 | MoonBit → 宿主 | `mb_buf_filled(8, 'A')` 后从线性内存读回 `b'AAAAAAAA'` |
| 6 | UTF-8 往返 | `你好, MoonBit 🚀` → 13 码位 / 20 字节，往返字节一致 |
| 7 | 调用开销 | 200k 次调用聚合计时，并与纯 wasm 基线对照 |

## 关键发现

**1. `String` / `Bytes` 参数在 wasm ABI 里是一个 `i32`。**

```wat
(func $_...9utf8__len (param i32) (result i32))
```

也就是说宿主拿到的不是 `(ptr, len)`，而是 MoonBit 堆里某个对象的指针。
这直接决定了协议形态：**宿主必须只持有句柄，不能持有裸指针**——因为 MoonBit 的 GC
随时可能回收它。`spikes` 里用 `registry` 数组保活就是这个问题的雏形。

**2. 对象数据偏移实测为 `ptr + 0`，但不能硬编码。**

`Bytes` 的数据确实从对象指针处开始，长度等信息在别处。这属于编译器内部布局，
会随版本变化。spike 采用**启动时探针自检**：拿一段已知内容，在指针附近扫描定位，
校验失败就拒绝启动。生成器应当把这个结论固定成"每版本验证"的断言，而不是常量。

**3. 调用开销由 Python 绑定层主导。**

| 场景 | 每次调用 |
| --- | --- |
| 纯 wasm `nop` | 6.9 μs |
| 纯 wasm `id(i32)` | 16.6 μs |
| MoonBit `add(i32,i32)` | 22.7 μs |

MoonBit 的代码不是瓶颈，**跨越本身**才是。所以架构上必须做批量协议
（一次跨越处理 N 个元素），而不是指望把单次调用优化到 1 μs。
详见 [ADR 0001](../../docs/decisions/0001-wasm-first.md)。

## 遗留问题（S1 起处理）

- `Bytes` 没有 `unsafe_set`，宿主写入依赖"先让 MoonBit 分配、宿主直接改内存"这条路；
  将来需要提供正式的 `Buffer` 抽象，避免用户触碰裸内存。
- 句柄表还没有回收机制（当前用数组保活，只增不减）。
- native 后端未验证：本机缺 MSVC，留待 GitHub Actions 的 Linux runner。
