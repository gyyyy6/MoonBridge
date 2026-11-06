# S2：类型映射与 Python 代码生成

S2 的产出是**可被类型检查器接受的 Python 接口**。判定标准只有一条，并且是可重复执行的：

```bash
bash scripts/gen.sh all   # 语料 → .pyi → mypy --strict
```

2026-11-06 实测：**501 个接口文件生成 501 个 stub，mypy --strict 对 495 个唯一模块 0 报错**（6 个重复包名被合并），无一处 `# type: ignore`。

---

## 一、类型映射表

映射的目标不是"看起来像"，而是"类型检查器能接受、并且不会骗调用方"。

| MoonBit | Python | 说明 |
|---|---|---|
| `Int` `Int8` `Int16` `Int32` `Int64` `UInt*` `BigInt` `Byte` | `int` | 宽度全部折叠：Python 只有一种整数 |
| `Double` `Float` | `float` | 同上 |
| `Bool` | `bool` | |
| `String` `StringView` | `str` | |
| `Char` | `str` | 单个码位；Python 没有独立的字符类型 |
| `Bytes` | `bytes` | |
| `Unit` | `None` | |
| `Array[T]` `FixedArray[T]` | `list[T]` | |
| `ArrayView[T]` | `Sequence[T]` | 视图只读，用 `Sequence` 才能接受 tuple / range |
| `Option[T]`、`T?` | `Optional[T]` | `T??` 折叠为一层：可选链在边界上没有意义 |
| `Result[T, E]` | `T` | 错误通过 `MoonError` 异常传播，`E` 不进签名 |
| `Map[K, V]` | `dict[K, V]` | |
| `(A, B)` | `tuple[A, B]` | 空元组是 `tuple[()]` |
| `&T` | `T` | 借用是调用约定，不是值类型 |
| 本包声明的类型 | 生成的类 | 见"句柄"一节 |
| `typealias` / `type X = Y` | `X: TypeAlias = ...` | 别名解析到目标，不引入新类 |
| 其它 | `Any` | **必定**伴随一条降级记录 |

## 二、降级阶梯

映射结果只有四种，按保真度从高到低：

1. **直接对应** —— `Int` → `int`。
2. **透明擦除** —— `Borrowed`、`T??`：在 Python 侧不可观测，擦掉不损失信息。
3. **句柄** —— 包内声明的 struct / enum / suberror / trait / opaque，映射为生成类。值本体不跨边界，跨边界的是一个不透明整数句柄。
4. **降级为 `Any`** —— 无法可靠表达时。

第 4 级是唯一会丢信息的路径，所以它**从不静默**：每个 `Any` 都对应一条 `Degrade` 记录，`--gen` 会按原因汇总打印。

| 原因 | 含义 | 语料计数 |
|---|---|---|
| `foreign` | `@other.Type`，跨包类型 | 4812 |
| `unknown` | 既非本包声明也非内置表条目（如 `Json`、`Iter`、`Ref`） | 890 |
| `higher-order` | 函数类型的值 | 699 |
| `result` | `Result[T, E]` 的错误类型被丢弃 | 130 |
| `async` | `async` 值 | 81 |
| `unbound-self` | 类型上下文之外的 `Self` | 1 |
| `arity` | 泛型实参个数不匹配 | 0 |
| `too-deep` | 嵌套超过 24 层 | 0 |

两处刻意的选择：

- **函数类型降级为 `Any`，而不是 `Callable`。** S2 没有建回调蹦床，写 `Callable` 等于承诺一条走不通的路。`Any` 诚实。
- **`Result[T, E]` 只保留 `T`。** 错误走异常，这是 Python 的惯例；把 `E` 留在签名里会与异常通道重复。

## 三、命名规则

三层，全部是纯函数，输出可按字节复现：

1. `python_identifier` —— 合法性。保留字与 stub 自身导入名追加 `_`；数字开头加 `n_`；非 ASCII 字母保留（Python 3 允许 Unicode 标识符）。
2. `stub_name` —— 在第 1 层之上再加"不得遮蔽"：`int` `str` `bytes` `list` `dict` `tuple` `property` `staticmethod` `classmethod` 以及 `Any` `Optional` `Protocol` `TypeVar` 等导入名。原因很实际：一个叫 `property` 的字段会让同一类体内所有 `@property` 退化成 `str`；一个叫 `Protocol` 的类会让整个文件的 `typing.Protocol` 失效。
3. 成员冲突 —— 字段与方法同名在 MoonBit 合法（靠调用语法区分），Python 只有一个命名空间，方法让位，加数字后缀 `_2`。

三个特殊改写：

- `fn T::T(...)` → `T.new(...)` + `@staticmethod`。它是关联函数不是方法（签名里没有前导 `Self`），且成员名不能与类名相同，否则类体内对自身的引用会被成员遮蔽。
- `Type::method(Self, ...)` → `def method(self, ...)`。`.mbti` 把接收者打印成显式的前导 `Self` 形参，必须剥掉，否则每个方法都会多一个参数。
- 包路径 `moonbitlang/core/json` → `moonbitlang__core__json`。`/` 变 `__`，`-` 变 `_`，两种分隔符保持可区分；生成器仍维护 stem 表，撞名直接失败而不是静默覆盖。

## 四、生成产物

```
_gen/moonbridge/
  __init__.py      # from ._runtime import MoonError, MoonObject, Runtime
  _runtime.py      # 句柄基类 + 错误基类 + 调用入口
  py.typed         # 让 mypy 认定这是带类型的分发
  <module>.pyi     # 每个包一个
```

`_runtime.py` 与 stub 由同一次运行写出，不可能漂移：

```python
class MoonObject:      # 每个生成类的基类，持有 _handle
class MoonError(BaseException):   # 所有 suberror 的基类
class Runtime:         # invoke(symbol, payload) -> bytes，宿主注入传输层
```

**stub 之间互不 import。** MoonBit 的包依赖图含环（S1 实测 48 个包），跨包 import 会把环复制到 Python；因此跨包类型一律走 `Any`，每个 `.pyi` 都能独立检查。代价是 `foreign=4812`，这也是 S3 要还的债。

## 五、mypy --strict 逼出来的六类问题

第一次全量运行是 904 个错误，分布在 85 个文件。全部修完，共同点是**每一条都对应一个真实的接口形态**，不是凭空假设：

| 报错 | 出现 | 根因 | 修法 |
|---|---|---|---|
| `name-defined` | 240 | `.mbti` 里 `type Uuid derive(Eq)` 没有 `pub`，被当成私有而丢弃 | 无修饰符的 opaque 类型读作 public-opaque |
| `valid-type` | 522 | `fn T::T(...)` 生成的成员与类同名，遮蔽了类名 | 改名为 `new` 并标 `@staticmethod` |
| `valid-type` | 76 | 方法/字段名为 `int` `bytes` `list` `property`，遮蔽内置名 | `stub_name` 禁令表 |
| `type-var` | 66 | `fn[T] f() -> T`，`T` 无法从实参推断 | 仅出现在返回位的类型变量降级为 `Any` |
| `no-redef` | 34 | 字段与方法同名 | 方法加数字后缀 |
| `arg-type`/`misc` | 42 | `@property` 被同名字段遮蔽 | 同 `stub_name` |

这张表本身就是 S2 的价值：**它不是"写出来的"，是 501 个真实包逐个撞出来的**。

## 六、已知边界

S2 明确不做的事，写清楚比藏着好：

- **跨包类型 → `Any`。** 需要跨包 stub 导入与句柄归属，属于 S3。
- **内置但不在映射表里的类型 → `Any`**（`Json`、`Iter`、`Ref`、`SourceLoc` 等）。它们在 `@builtin` 包中声明，本包 stub 里没有对应类。
- **回调不桥接。** 接受函数值的 MoonBit 函数，其参数在 Python 侧是 `Any`。
- **`async` 不桥接。**
- **`Optional[T]` 是注解，不是运行时保证。** 真正的空值检查在 S3 的运行时编码层。
- **多构造器枚举只给 `tag` + 开放载荷。** `__init__(self, tag: str, *args: Any)` 是唯一诚实的公共签名。

## 七、下一步（S3）

1. 跨包句柄：`.pyi` 之间按依赖图做 `from . import <module>`，把 `foreign=4812` 收回来。
2. 句柄表与生命周期：`MoonObject` 持有真实句柄，宿主侧维护 id → 对象映射与释放策略。
3. 运行时编码：`Runtime.invoke` 落地为 wasmtime 调用 + 批量协议（S0 已测：单次调用 ~16μs，瓶颈在 Python 侧）。
