## UI Automation on Windows (run under Wine too): the window's provider
## walked as Narrator walks it -- names, control types, places, focus --
## and its patterns used: a value put in the text box, the button invoked,
## the check box toggled, the slider set; the next frames do it.
##
##   nim c -r --os:windows tests/test_uia.nim        (or with MinGW, then wine)

when not defined(windows):
  echo "test_uia: Windows only"
else:
  import std/[os, strutils]
  import retroui
  import retroui/uirelays/drivers/winapi_driver

  type
    Vt = ptr UncheckedArray[pointer]
    Variant = object
      vt: uint16
      r1, r2, r3: uint16
      val: int64
      more: int64
    URect = object
      left, top, width, height: float64

  proc vt(p: pointer): Vt = cast[Vt](cast[ptr pointer](p)[])

  proc qi(p: pointer; iid: array[4, uint32]): pointer =
    type Q = proc (this, riid: pointer; ppv: ptr pointer): int32 {.stdcall.}
    var g = iid
    discard cast[Q](vt(p)[0])(p, addr g, addr result)

  const
    IidFragment = [0xf7063da8'u32, 0x439c8359'u32, 0xc5bb9792'u32, 0x877d9a29'u32]

  proc release(p: pointer) =
    type R = proc (this: pointer): uint32 {.stdcall.}
    if p != nil: discard cast[R](vt(p)[2])(p)

  proc prop(simple: pointer; id: int32): Variant =
    type G = proc (this: pointer; id: int32; ret: ptr Variant): int32 {.stdcall.}
    discard cast[G](vt(simple)[5])(simple, id, addr result)

  proc name(simple: pointer): string =
    let v = prop(simple, 30005)
    if v.vt == 8 and v.val != 0: $cast[WideCString](v.val) else: ""

  proc navigate(frag: pointer; dir: int32): pointer =
    type N = proc (this: pointer; dir: int32; ret: ptr pointer): int32 {.stdcall.}
    discard cast[N](vt(frag)[3])(frag, dir, addr result)

  proc simpleOf(frag: pointer): pointer =
    qi(frag, [0xd6dd68d1'u32, 0x433286fd'u32, 0xbe9a6686'u32, 0x4cd2a2de'u32])

  proc pattern(simple: pointer; id: int32): pointer =
    type P = proc (this: pointer; id: int32; ret: ptr pointer): int32 {.stdcall.}
    discard cast[P](vt(simple)[4])(simple, id, addr result)

  var
    name0 = "World"
    greeted = ""
    check = false
    level = 10
    frames = 0
    log: seq[string]

  proc walk(): seq[tuple[name: string; ct: int; simple: pointer]] =
    let root = uiaRootProvider()
    doAssert root != nil, "UI Automation is there"
    let rf = qi(root, IidFragment)
    var c = navigate(rf, 3)                  # first child
    while c != nil:
      let s = simpleOf(c)
      result.add (name(s), int(prop(s, 30003).val and 0xFFFFFFFF), s)
      let n = navigate(c, 1)                 # next sibling
      release(c)
      c = n
    release(rf)
    release(root)

  proc find(items: seq[tuple[name: string; ct: int; simple: pointer]]; ct: int; nm = ""): pointer =
    for it in items:
      if it.ct == ct and (nm.len == 0 or it.name == nm): return it.simple

  app "UIA test", 360, 200:
    inc frames
    row([60, -1]):
      label "&Name:"
      edit name0
    if button("&Greet"): greeted = "Hello, " & name0
    checkbox "&Check", check
    slider level, 0, 100
    label greeted
    case frames
    of 5:
      let items = walk()
      for it in items: log.add $it.ct & " " & it.name
      doAssert items.find(50004, "Name:") != nil, "the box, named by its label: " & $log
      doAssert items.find(50000, "Greet") != nil
      # the value pattern: text put in the box
      let v = pattern(items.find(50004), 10002)
      doAssert v != nil, "the box has the value pattern"
      type SetV = proc (this: pointer; s: WideCString): int32 {.stdcall.}
      discard cast[SetV](vt(v)[3])(v, newWideCString("Sultan"))
      release(v)
    of 8:
      doAssert name0 == "Sultan", name0
      let items = walk()
      let inv = pattern(items.find(50000, "Greet"), 10000)
      doAssert inv != nil
      type Inv = proc (this: pointer): int32 {.stdcall.}
      discard cast[Inv](vt(inv)[3])(inv)
      release(inv)
      let tg = pattern(items.find(50002, "Check"), 10015)
      doAssert tg != nil
      discard cast[Inv](vt(tg)[3])(tg)
      release(tg)
    of 11:
      doAssert greeted == "Hello, Sultan", greeted
      doAssert check
      let items = walk()
      let rv = pattern(items.find(50015), 10003)
      doAssert rv != nil, "the slider has the range pattern"
      type SetR = proc (this: pointer; v: float64): int32 {.stdcall.}
      discard cast[SetR](vt(rv)[3])(rv, 64.0)
      release(rv)
    of 14:
      doAssert level == 64, $level
      # a place on the screen, and the focus
      let items = walk()
      let b = items.find(50000, "Greet")
      let f = qi(b, IidFragment)
      type Bounds = proc (this: pointer; r: ptr URect): int32 {.stdcall.}
      var r: URect
      discard cast[Bounds](vt(f)[5])(f, addr r)
      doAssert r.width > 20 and r.height > 10, $r
      release(f)
      echo "test_uia: ok (", log.join(", "), ")"
      quitApp()
    else: discard
    wakeIn(30)
