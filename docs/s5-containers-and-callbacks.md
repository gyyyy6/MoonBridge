# S5：容器、回调与异常字段

S4 的清单里有一列"跳过"，其中最大的一项是 `unmarshalable-param`——`Array[T]`、`Map[K, V]`、
`Option[T]`、`Result[T, E]`、函数值都落在这一格里。也就是说：**能调的函数都是标量函数**。

S5 把这一格清掉。

```bash
bash scripts/e2e.sh   # 现在会打一个 list、一个 dict、五个回调、一个 typed exception
```

2026-11-07 实测：168 个 MoonBit 单测通过；`mypy --strict` 498 个文件 0 报错；
42 项端到端断言全绿（其中 13 项是 S5 新增的）；`dropped=0`。

---

## 一、形状树长出了枝

`Wire` 在 S4 是一个**封闭的标量集合**。S5 之后它是递归的：

```moonbit
pub(all) enum Wire {
  WInt; WDouble; WBool; WStr; WStrView; WUnit
  WMaybe(Wire)              // Option[T]
  WHandle(TyRef)            // 留在 guest 堆里的对象
  WArr(Wire)                // Array[T]
  WArrView(Wire)            // ArrayView[T]
  WMap(Wire, Wire)          // Map[K, V]
  WRes(Wire, Wire)          // Result[T, E] —— 只在返回位
  WCall(Array[Wire], Wire)  // (A, B) -> C
}
```

`Wire::key()` 把形状压成标识符（`arr_int`、`map_str_builtin_Json`、`cb__to_bool`），
所以一个 helper 的名字只由形状决定，不由它出现在哪个符号里决定。`Array[Map[String, Int]]`
贡献三个形状，写三个 helper，被两个符号共用也只写一次。

Python 那边**不需要新类型**：`list` 是 `list[T]`，`dict` 是 `dict[K, V]`，`Callable[[A], B]`
是新加的唯一一个（`src/map/type_map.mbt`）。调用方写的东西和标量调用没有区别：

```python
mbuiltin.Json.array([mbuiltin.Json.number(1.0), mbuiltin.Json.string("two")])
mbuiltin.Json.object_({"a": mbuiltin.Json.number(1.0)})
```

---

## 二、三个必须做对的地方

### 1. 名字不是一对一，形状才是

`Option[T]` 的解码器**就是** `T` 的解码器——`dec_name(WMaybe(WInt)) == dec_name(WInt) == "dec_int"`，
因为解码器本来返回 `T?`。这个折叠是对的，它让 `Option` 不产生第二个 helper。

它同时埋了一个洞。收集形状时 `WMaybe(WInt)` 和 `WInt` 都会进列表，如果按名字去重，
先到的 `WMaybe` 会把 `dec_int` 这个名字*占住*，然后交给 `emit_dec_helper`——而那里
`WMaybe(_) => ()` 什么都不写。后到的 `WInt` 一看名字已被占用，就被当成重复跳过了。

结果是：**`dec_int` 这个名字登记了，函数一行也没写出来**。真正的报错出现在最远端：

```
Error: [4021] guest.mbt:666:16
   666 │       let a1 = dec_int(arg(argv, 1))
       │                ───┬───  The value identifier dec_int is unbound.
```

修法是把"要写谁"和"叫什么"分开：`emit_*(sb, base_wire(w))`。日志里能看出这个区别：

```
EMIT dec_str contained=false
  HIT strview        ← 真的写了
EMIT dec_int contained=false
  HIT opt_int        ← 命中的是 Option，什么都没写
```

这类 bug 不会在测试里红，只在**重新生成之后**红，而且症状（未定义标识符）指向生成物
而不是生成器。所以 `emit_dec_helper` / `emit_enc_helper` 的 `WMaybe` 分支现在改成委托给内层，
让它在任何调用顺序下都是全函数。

### 2. 容器里不能有借来的字符串

`StringView` 是借来的：它的生命周期不超过源字符串。把它放进 `Array` 或 `Map`，解码时源字符串
已经出作用域，容器里剩下的是悬空视图。所以 `contains_strview(w)` 会拒绝任何**内部**含
`StringView` 的容器，`Map[String, StringView]` 因此被跳过（`unmarshalable-param` 计数 +1）。

反过来，`Self` 在容器里必须能解析。以前的 `container` 用 `owner = None` 解码元素，
于是 `Json::array(Array[Self])` 的元素 `Self` 无处可查，整个函数被跳过；而
`Json::object(Map[String, Self])` 走的是另一条路、带 `owner`，就能过。同一个工具包里的
两个构造函数,一个能接一个不能接，纯粹是实现的偶然。

S5 把 `container` 删掉，统一走 `single_arg(pkg, args, owner, make)`：元素用容器自己的 owner 解析，
再靠 `contains_strview` 兜住借用。`Json::array` 从此出现在 guest 里，`dec_arr_builtin_Json`
是它的解码器。

顺带修掉一个同源问题：`moon info` 把 `Int` 写成 `Int32`，而 `wire_in` 只认 `"Int"`，
于是自己写的探针包一个函数都进不去。`Int32` 就是 wasm 上的 32 位整数，和 wire 的整数同宽，
所以两个名字映射到同一个 `WInt`；真正的 `Int64` 不映射，它会被截断。

### 3. 回调要有一个 wasm import

一个 Python 函数没法复制到 wasm 里。S5 的做法是：**wire 上只有一个 `Int32` id**，
guest 拿到 id 之后通过 wasm import 回头调用宿主：

```moonbit
#cfg(target="wasm")
extern "wasm" fn mb_cb_invoke(cb_id : Int32, len : Int32) -> Int32 = "env" "mb_cb_invoke"
```

因为它是 wasm *import*，宿主函数在"已经处于 guest 栈帧里"的线程上执行，不需要协程、
不需要重放、不需要第二个线程。参数帧由 guest `publish` 到响应缓冲区，宿主从那里读；
返回值写进 guest 自己的缓冲区——宿主不能在 guest 堆里分配，只能通过
`mb_cb_buffer(n)` 这个 export 向 guest 要一块内存。

`#cfg` 那一行是必需的：生成器本身跑在 JavaScript 上，而这个包也会被 js 目标编译，
`extern "wasm"` 在 js 后端是硬错误。js 目标拿到一个返回 0 的桩，反正没有 guest 实例时
也没人能调回调。

回调里抛出的 Python 异常不能穿过 guest 栈（会留下写了一半的缓冲区），所以宿主把它记下来、
返回 0，等外层调用返回后再抛。

---

## 三、`Result[T, E]` 变成 `except`

Python 没有 `Err` 这个值，它有异常。所以：

* `Result[T, E]` 只在**返回位**映射（参数位无从构造 `Err`），且只有 `E` 是 `suberror` 时才映射；
* `Ok` 走正常编码，`Err` 变成 `Status::FailedAs`；
* 帧里的失败载荷从"一个字符串"升级成"带类型的 map"：
  `{"type": "moonbitlang/core/json::ParseError", "message": "..."}`。旧的裸字符串仍然被接受，
  所以这是加法而不是破坏。

名字要能变回类。每个生成的模块在末尾发布自己声明的 `suberror`：

```python
_runtime.register_failure("moonbitlang/core/json::ParseError", ParseError)
```

`Runtime.request` 看到 `STATUS_FAILED` 就查表，命中就直接抛那个类，没命中抛 `MoonError`——
一个从没被 import 的包里的错误，仍然是个错误，只是没有专属的类可抛。

`error_type` 也不只来自 `raise` 子句：`fn f() -> Result[Int, ParseError]` 没有 `raise`，
但 `Result` 的名字就是答案，所以 `result_error_name` 会从返回类型里把它挖出来。

调用方看到的是：

```python
try:
    mjson.parse("{oops")
except mjson.ParseError as exc:   # 不是 MoonError
    ...
```

---

## 四、数字

| 指标 | S4 | S5 |
|---|---|---|
| guest 符号 | 49 | 54 |
| `unmarshalable-param` | 15 | 14 |
| MoonBit 单测 | 167 | 168 |
| `mypy --strict` 文件 | 497 | 498 |
| 端到端断言 | 29 | 42 |

54 个符号里新增的 5 个是 `Json::array(Array[Self])` 和探针包的四个回调函数。

---

## 五、诚实边界

* **回调只接标量签名**。参数和返回值可以是 `Int` / `Double` / `Bool` / `String` / `Unit`
  以及它们的 `Option`；带 handle 或容器的回调被拒绝。理由是回调通道复用同一套 codec，
  而一个要在两侧各自分配、各自释放的对象穿过它会有两套生命周期，S5 不做这件事。
* **`Result` 只在返回位**。参数位没有 `Err` 可写。
* **容器里不能有 `StringView`**，理由见上（借用）。
* **回调表不回收**。同一个 Python 函数反复传进去拿到同一个 id（guest 会比较回调），
  代价是这个函数在 runtime 关闭前一直活着。
* **`T??` 被拒绝**。`Option[Option[T]]` 在 wire 上和一个 `Option[T]` 分不开。

---

## 六、为什么加了 `src/callbacks`

回调通道最容易被"建立"而不是"跑通"：解码器能生成、id 能传进去、看起来一切正常，
但**没有一次真正的回调发生**。标准库里找不到一个能触发的例子：

* `builtin::debug_assert(() -> Bool)` 在 release 构建里被编译掉（实测 `calls: 0`）；
* `lexbuf::Lexbuf::from_fn(() -> String?)` 只是把函数存起来，没有方法去驱动它；
* `Option::unwrap_or_else` / `Map::get_or_init` 的参数是泛型 `T`，没有 wire 形状。

所以 `src/callbacks` 是一个四行的包，函数体就是那一次调用：

```moonbit
pub fn call_int(f : () -> Int) -> Int { f() }
```

它让"Python 可调用对象 → `Int32` id → wasm import → guest 闭包 → 结果写回 guest 内存 →
Python 拿到值"这条链路可以从一个断言里看见：

```
ok   callback returns: 40
ok   callback was called: 1
ok   callback with argument: 42
ok   two callbacks: 40
ok   callback returning none: '<none>'
ok   callback exception re-raised: from the callback
```

通道被建立但从未通过，和通道能通，是两件事。这一节就是为了不做前者。
