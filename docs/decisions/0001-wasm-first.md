# ADR 0001：宿主 ABI 以 wasm 为主，native 为性能选项

- 状态：已接受
- 日期：2026-11-06
- 决策者：MoonBridge 作者

## 背景

MoonBridge 要在 Python 与 MoonBit 之间传递值。可选宿主形态有两种：

1. **native（C ABI）**：MoonBit 编译成 `.dll` / `.so`，Python 用 `ctypes` / `cffi` 调用。
   - 优点：每次调用接近原生（纳秒级），可直接复用 C 生态。
   - 缺点：每个平台/架构都要单独构建；Windows 上 MoonBit native 后端要求 **MSVC Build Tools**
     （实测本机只有 mingw gcc，`moon build --target native` 直接失败）；wheel 必须分平台矩阵发布。
2. **wasm**：MoonBit 编译成 `.wasm`，Python 用 `wasmtime` 加载。
   - 优点：**零 C 工具链**，一个 `py3-none-any` wheel 全平台可用；沙箱化，崩溃不会带走解释器进程；
     线性内存可由宿主直接读写，字节搬运成本低。
   - 缺点：每次跨语言调用有固定开销（见下），无法直接使用依赖系统库的 MoonBit 包。

## 实测数据（Windows 11，Python 3.13，wasmtime 50.0.1）

| 场景 | 每次调用 |
| --- | --- |
| 纯 wasm 基线 `nop` | 6.9 μs |
| 纯 wasm 基线 `id(i32)` | 16.6 μs |
| MoonBit `add(i32, i32)` | 22.7 μs |

基线本身就占了绝大部分开销，说明**瓶颈在 Python 绑定层，而不是 MoonBit 生成的代码**。
换句话说：换 ABI 形式不会让"每次调用"变快多少，真正要优化的是**跨越次数**。

## 决策

1. **默认后端为 wasm**，因为它让"一条命令生成、任何机器能装"成立，这是本项目的核心承诺。
2. **hot path 一律批量**：上下文管理器 + 缓冲协议，一次跨越处理 N 个元素，
   而不是让用户写 `for x in xs: lib.f(x)`。生成器对可批量的 API 自动提供 `*_many` 变体。
3. **保留 native 后端**，作为 `--backend native` 的可选路径，用于对延迟敏感的调用；
   它不参与默认体验，避免把"装 MSVC"变成用户的前置条件。
4. **句柄而非指针**：任何 GCF 对象过界都变成 `i32` 句柄，宿主拿不到裸指针，
   生命周期由 MoonBit 侧的表管理。这条在两种后端上都成立，是 ABI 的稳定核心。

## 后果

- 正面：安装体验统一；崩溃隔离；跨平台只需要一个 wheel；ABI 不依赖编译器内部布局。
- 负面：单次调用比 native 慢一个数量级；wasm 侧无法使用系统库；调试栈更深。
- 风险：`wasmtime` 在部分平台的版本兼容性；需要在 CI 上固定版本并做启动自检
  （加载时校验 `abi_version` 与对象数据偏移探针）。

## 备选方案

- **只用 native**：被 MSVC 前置条件否决（会让 Windows 用户装 2GB 工具链才能跑 hello world）。
- **只用 ctypes + 手写胶水**：回到生态现状，没有增量。
- **wasm-gc + 组件模型**：更接近未来标准，但当前 Python 侧运行时对 GC 提案支持不齐，
  留作后续演进路径。
