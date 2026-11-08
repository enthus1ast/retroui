## Retro Designer's values: what a control's arguments are while the
## designer draws it. The designer reads each argument from the file (a
## string, a number, a list, an enum's name...) into a `Value`; the
## variables a control changes (`edit name`, `checkbox("x", on)`) are
## `VarCell`s, one per variable, so two controls on one variable show the same.
## The generated registry (registry.nim) calls the real controls with them.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/strutils
import retroui

type
  ValueKind* = enum
    vkNone,          ## not given, or worked out by code: the default is used
    vkStr, vkInt, vkFloat, vkBool,
    vkStrs, vkInts,  ## a list of strings, of numbers
    vkIdent,         ## a name: an enum's value, a constant (`pxOpen`, `chBar`)
    vkSet,           ## `{a, b}`: names
    vkColor, vkRect
  Value* = object
    kind*: ValueKind
    s*: string
    i*: int
    f*: float
    b*: bool
    ss*: seq[string]
    ii*: seq[int]
    c*: Color
    r*: Rect
  VarCell* = ref object
    ## A variable the designed window's controls change: its value while
    ## designing (from its `var` line, else the type's own).
    name*: string
    kind*: ValueKind           ## what it holds (vkNone: not known yet)
    s*: string
    i*: int
    f*: float
    b*: bool
    ss*: seq[string]
    ii*: seq[int]
  Args* = object
    ## A control's arguments, one per parameter (in the parameters' order).
    vals*: seq[Value]
    cells*: seq[VarCell]

proc given*(a: Args; i: int): bool {.inline.} = i < a.vals.len and a.vals[i].kind != vkNone

proc argStr*(a: Args; i: int; d: string): string =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkStr, vkIdent: v.s
  of vkInt: $v.i
  of vkFloat: $v.f
  of vkBool: $v.b
  else: d

proc argInt*(a: Args; i: int; d: int): int =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkInt: v.i
  of vkFloat: int(v.f)
  of vkBool: ord(v.b)
  else: d

proc argFloat*(a: Args; i: int; d: float): float =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkFloat: v.f
  of vkInt: float(v.i)
  else: d

proc argBool*(a: Args; i: int; d: bool): bool =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkBool: v.b
  of vkInt: v.i != 0
  else: d

proc argStrs*(a: Args; i: int; d: seq[string]): seq[string] =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkStrs: v.ss
  of vkStr: @[v.s]
  else: d

proc argInts*(a: Args; i: int; d: seq[int]): seq[int] =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkInts: v.ii
  of vkInt: @[v.i]
  else: d

proc argFloats*(a: Args; i: int; d: seq[float]): seq[float] =
  if not a.given(i): return d
  let v = a.vals[i]
  case v.kind
  of vkInts:
    for x in v.ii: result.add float(x)
  else: result = d

proc argColor*(a: Args; i: int; d: Color): Color =
  if a.given(i) and a.vals[i].kind == vkColor: a.vals[i].c else: d

proc argRect*(a: Args; i: int; d: Rect): Rect =
  if a.given(i) and a.vals[i].kind == vkRect: a.vals[i].r else: d

proc argIdent*(a: Args; i: int): string =
  ## The name given (an enum's value, a constant), else "".
  if a.given(i) and a.vals[i].kind == vkIdent: a.vals[i].s else: ""

proc argNames*(a: Args; i: int): seq[string] =
  ## The names of a `{a, b}` set given, else none.
  if a.given(i) and a.vals[i].kind == vkSet: a.vals[i].ss else: @[]

# (the variables: a cell each; the registry's calls take them as `var`)

var spare: VarCell = VarCell()     # (for a variable parameter given no variable)

proc cell*(a: var Args; i: int): VarCell =
  if i < a.cells.len and a.cells[i] != nil: a.cells[i]
  else:
    spare = VarCell()
    spare

proc vstr*(a: var Args; i: int): var string = a.cell(i).s
proc vint*(a: var Args; i: int): var int = a.cell(i).i
proc vfloat*(a: var Args; i: int): var float = a.cell(i).f
proc vbool*(a: var Args; i: int): var bool = a.cell(i).b
proc vstrs*(a: var Args; i: int): var seq[string] = a.cell(i).ss
proc vints*(a: var Args; i: int): var seq[int] = a.cell(i).ii

# (what a call gives back, for `let pick = menuButton(...)`)

proc toValue*(x: bool): Value = Value(kind: vkBool, b: x)
proc toValue*(x: int): Value = Value(kind: vkInt, i: x)
proc toValue*(x: float): Value = Value(kind: vkFloat, f: x)
proc toValue*(x: string): Value = Value(kind: vkStr, s: x)
proc toValue*[T](x: T): Value = Value(kind: vkNone)

proc `$`*(v: Value): string =
  ## The value as the inspector shows it.
  case v.kind
  of vkNone: ""
  of vkStr, vkIdent: v.s
  of vkInt: $v.i
  of vkFloat: $v.f
  of vkBool: $v.b
  of vkStrs: v.ss.join(", ")
  of vkInts:
    var s: seq[string]
    for x in v.ii: s.add $x
    s.join(", ")
  of vkSet: "{" & v.ss.join(", ") & "}"
  of vkColor: "color(" & $v.c.r & ", " & $v.c.g & ", " & $v.c.b & ")"
  of vkRect: "rect(" & $v.r.x & ", " & $v.r.y & ", " & $v.r.w & ", " & $v.r.h & ")"
