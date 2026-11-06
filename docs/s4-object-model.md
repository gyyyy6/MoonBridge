# S4：生成 guest、对象模型与业务闭环

S3 的结论是"能调通"，但那份绑定只有一半是生成的：`.pyi` / `.py` 从接口推出来，**guest 侧的
dispatch 表是手写的**。手写的表会漂——它不会因为编译失败而被发现，只会在某次调用悄悄返回错的字段。

S4 把这个缺口补上：**两半从同一份计划投影出来**，并且让生成的对象真的能被构造、读、写。

```bash
bash scripts/e2e.sh   # 语料 → stub → 可调用模块 → 生成的 guest → wasm → Python → 10 万次调用
```

2026-11-06 实测：163 个 MoonBit 单测通过；`mypy --strict` 497 个文件 0 报错；28 项端到端断言全绿；
10 万次 × 6 个用例共 1,503,128 帧，guest 内存曲线全程平直（64 / 128 KiB 两档不动），
`live=0`、`dropped=0`。

---

## 一、一份计划，两半生成

```text
                    ┌──────────── Plan ─────────────┐
.mbti ──▶ World ──▶ │ Sym[]  符号 + 参数形状 + 标签  │ ──┬──▶ .py / .pyi   调用方
 (S1)     (S3)      │ HandleSlot[] 每个具体类型一张表 │   └──▶ guest.mbt    应答方
                    └───────────────────────────────┘
```

`Plan` 里没有"猜测"：每个 `Sym` 记录符号名（`<声明包>::<类型>::<名字>`）、每个参数的
wire 形状（`WInt` / `WDouble` / `WBool` / `WStr` / `WStrView` / `WUnit` / `WMaybe` / `WHandle`）、
标签（可选参数与被命名字段）、返回形状、是否抛错。两半各自把它渲染成自己的语言：

```moonbit
// src/gen/symbols.mbt —— 两边唯一的真相
if takes_self {
  params.push(WHandle(owner))
  labels.push("")
}
```

要不要接接收器这件事，S3 的 `Sym` 里没有，S4 补上了：`Hasher::Hasher(seed? : Int)` 是关联函数，
不接 `Self`；`Point::norm(Self)` 接。少了这个判断，guest 会给构造函数塞一个幽灵首参。

### 生成结果

三个包（json / builtin / lexbuf）作 guest，501 个包的语料做输入：

```text
guest: symbols=46 (free=2 method=37 ctor=2 get=4 set=1) tables=12
  skipped generic=411 deprecated=50 hidden-struct=3 labeled-param=2
  skipped unnamed-field=1 generic-struct=1 unmarshalable-param=18
  skipped receiver-not-in-guest=456
```

`receiver-not-in-guest=456` 是这段最诚实的一行：**方法挂在没编译进 guest 的类型上，就真的调不到**。
把它写成"尽力而为"的分支，只会把失败从生成期推迟到运行期。

生成的 `guest.mbt` 报 1161 行（`moon fmt` 格式化后 1396 行），结构固定：ABI 导出 → 每种参数形状一个解码器 → 每种返回形状一个编码器 →
`live_total` / `release_tag` / `release_pairs` → `dispatch` → `mb_call`。手写的 `src/guest_json/` 已删除。

编译器逼出来的四处错（都不报错、只在运行期才现形，或者干脆编译不过）：

| 现象 | 原因 | 修法 |
|---|---|---|
| `arg_str` 重复定义 | `String` 与 `StringView` 都解码到它 | 按 wire 形状收集解码器，不按拼写 |
| `Map::insert` 未声明 `raise` | 句柄编码器会抛 | 编码器带 `raise`，只用它的分支套 `try` |
| `unused_try` 报错 | 不抛的编码器也套了 `try` | 按实际形状决定是否包裹 |
| `WMaybe` 返回多包一层 | 只有它已经是 `T?` | 其余返回 `Some(value)`，它直接传 |

---

## 二、读写与构造器

生成的 `.py` 现在真的会调：

```python
class Position(_runtime.MoonObject):
    """MoonBit struct `Position`."""
    moon_type_id = 5
    def __init__(self, line: int, column: int) -> None:
        super().__init__(cast(int, _runtime.default().request(
            "moonbitlang/core/json::Position::__new__", [line, column])), _runtime.default())

    @property
    def line(self) -> int:
        return cast(int, _runtime.default().request(
            "moonbitlang/core/json::Position::__get_line", [self]))
```

```python
class StringScanner(_runtime.MoonObject):
    moon_type_id = 12
    @cursor.setter
    def cursor(self, value: int) -> None:
        _runtime.default().request(
            "moonbitlang/core/lexbuf::StringScanner::__set_cursor", [self, value])
```

三条规则：

1. **构造器接管句柄**：`__new__` 在 guest 里造出对象，Python 拿到的就是那个对象的句柄，
   不是副本。读写因此作用在同一个 MoonBit 堆对象上。
2. **没符号就不发成员**：`has_symbol` 决定 `__init__` / property / setter 是否存在。
   发一个调不通的成员，只会把生成期的失败改成调用期的失败。
3. **只读字段没有 setter**：MoonBit 里不是 `mut` 的字段，guest 侧没有可调用的写入路径。

### 泛型表：从"人工声明"到按需生成

S3 的 12 张句柄表是手写的。S4 里它们是 `Plan::build` 的产物：遍历符号时，每个
`WHandle` 位置的类型如果是 concretely 命名的（元数 0、包在 guest 里），就登记一张表并分配标签。
标签用单调计数器（`mut next_tag`），不是 `表数量 + 1`——同一个类型被登记两次也不会复用标签。

```moonbit
// 生成的 guest 侧
priv struct Tables {
  json_Position : HandleTable[@json.Position]
  builtin_Json  : HandleTable[@builtin.Json]
  ...
}
```

---

## 三、端到端验收抓到的泄漏

S4 让对象可以被构造之后，端到端测试第一次跑出来：

```text
live handles:  1  dropped=1 releases=4
```

`parse` 返回的是 `Json` 的句柄，`Json` 是一个 **enum**，而 `render_enum` 从来没写过
`moon_type_id`。于是 `close()` 发出了 `release_tag(0, id)`，guest 里没有 tag 0 的表，
**什么都没释放**，而 Python 侧把这次释放算作成功。对象在 guest 里活到进程结束。

这个 bug 有三个特点，值得写进申报书：

1. **不报错**。没有任何断言会失败，只有内存曲线慢慢往上走。
2. **只有 `dropped` 能看见**。`releases` 增加了，`live` 在单次调用里只多一个，看起来像正常。
   `Runtime.dropped` 专门数"发出去但没被任何表接住"的 id，是唯一能区分"释放了"和"以为释放了"的数字。
3. **它藏在最容易忘的那一类里**。struct 有表、opaque 有表，enum 读起来像"值"，
   所以没人觉得它需要表——但 `Json` 就是 enum。

修法是把标签收成一条路径：`tag_member(raw)` 由 struct / enum / error / opaque 共用，
表在就有标签，没表就没有。同时 `MoonObject.moon_type_id = 0` 现在有确定含义：
**这个类不持有句柄**。

---

## 四、10 万次调用的实测

`bash scripts/e2e.sh`，`--calls 100000`：

| 用例 | 每次迭代的帧数 | µs/帧 | p50 µs | 10 万次后 live |
|---|---|---|---|---|
| `valid`（字符串进、布尔出，无对象） | 1 | 35.1 | 31.8 | 0 |
| `parse`（文档进、句柄出、`close()`） | 1 | 86.7 | 74.3 | 0 |
| `parse/gc`（同上，交给 `weakref.finalize`） | 1 | 47.9 | 38.9 | 5（故意扣留） |
| `ctor+field`（构造 + 读两个字段 + 释放） | 4 | 40.1 | 34.5 | 0 |
| `ctor/gc`（构造 + 读一个字段，交给 GC） | 2 | 42.5 | 35.4 | 5（故意扣留） |
| `setter`（构造 + 读 + 写 `cursor` + 读回 + 释放） | 5 | 38.8 | 33.5 | 0 |

guest 线性内存：

```text
case           1000      5000     10000     25000     50000    100000
valid            64        64        64        64        64        64
parse            64        64        64        64        64        64
parse/gc        128       128       128       128       128       128
ctor+field      128       128       128       128       128       128
ctor/gc         128       128       128       128       128       128
setter          128       128       128       128       128       128
```

四帧一次迭代 ≈ 160 µs，单帧 ≈ 40 µs，与 `valid` 的 35 µs 同一量级：**对象模型没有额外的边界成本**，
构造和读字段都只是普通的一次调用。2 张内存档位（64 KiB 无句柄、128 KiB 有句柄）在 1000 次之后
到 10 万次之间一个字节都没动；`parse/gc` 与 `ctor/gc` 的 live 曲线是 GC 批次的锯齿（40 → 8 → 16 → 40 → 16 → 32），
始终有界，不随调用数增长。

断言（任一失败即退出码非 0）：

```text
ok   ctor+field released everything: live=0
ok   every release reached a table: dropped=0 of 500000 released
ok   guest is empty at the end: live=0
ok   setter memory plateaus: 128 KiB -> 128 KiB over the last 50,000 calls
no leaks: every handle the guest made was released
```

---

## 五、S4 没做的

诚实地列出来，这些留给 S5：

- **泛型实例化**：`Array[T]` / `Map[K, V]` 仍然不进边界（`unmarshalable-param=18`，
  以及语料里 411 个泛型声明）。S4 的表只覆盖元数 0 的具体类型。
- **集合与 `Option` / `Result` 的完整映射**：`T?` 已经能来回（`WMaybe`），
  `Result` 与 `Array` 还降级为 `Any`。
- **回调**：函数类型参数仍降级为 `Any`，没有蹦床。
- **异常**：`raise` 已经能跨（`MoonError`），但错误对象的**字段**还没暴露给 Python。

`skipped` 的每一类都是可数的，不是"以后再想"。

---

## 六、复现

```bash
moon test --deny-warn                    # 163 个单测

# 只重新生成 guest（不动 Python 侧）
moon build --target js
node _build/js/debug/build/cli/cli.js \
  --gen "$(pwd)/_gen2" \
  --bind moonbitlang/core/json,moonbitlang/core/builtin,moonbitlang/core/lexbuf \
  --guest moonbitlang/core/json,moonbitlang/core/builtin,moonbitlang/core/lexbuf \
  --guest-out "$(pwd)/src/guest_gen" \
  --list "$(pwd)/_corpus/manifest.txt"
moon fmt

# 全链路 + 基准
bash scripts/e2e.sh
```

`src/guest_gen/` 是生成产物，但**提交进仓库**：这样一次 `git clone` 就能 `moon build`，
不需要先跑一遍生成器；`scripts/e2e.sh` 每次都会重新生成它，并在与仓库内容不同时提示差异。
