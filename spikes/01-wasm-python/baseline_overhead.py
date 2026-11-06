import time
from wasmtime import Engine, Store, Module, Instance, Config

wat = """
(module
  (func (export "nop"))
  (func (export "id") (param i32) (result i32) local.get 0)
  (memory (export "memory") 1))
"""
eng = Engine(Config())
mod = Module(eng, wat)
store = Store(eng)
inst = Instance(store, mod, [])
nop = inst.exports(store)["nop"]
idf = inst.exports(store)["id"]
for f, args, name in ((nop, (), "nop"), (idf, (7,), "id(i32)")):
    for _ in range(2000): f(store, *args)
    n = 200000
    t0 = time.perf_counter_ns()
    for _ in range(n): f(store, *args)
    dt = (time.perf_counter_ns() - t0) / n
    print(f"baseline wasmtime-py {name}: {dt:.0f} ns/call")
