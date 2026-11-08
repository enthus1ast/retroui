## Retro Designer's model: the designed file as the designer shows it --
## its pages (each `app`, each `while beginFrame()` window, each proc of
## yours that draws controls), and on each page the items: controls,
## events (a control with code under it), layout blocks (row, group,
## tabs...), branches (`if`, `case`: one shown), boxes for what the
## designer does not draw (a loop, a call of yours), and code that draws
## nothing. Read again after every change of the file.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[algorithm, tables, strutils]
import compiler/[ast, idents]
import retroui
import source, registry

type
  ItemKind* = enum
    ikControl = "control"        ## a control: `button "OK"`, `edit name`
    ikEvent = "event"            ## a control with the code its event runs: `if button("OK"): ...`
    ikValue = "value"            ## a control whose answer is kept: `let pick = menuButton(...)`
    ikBlock = "block"            ## a layout block with a body: row, group, tabs, menu...
    ikBranch = "branch"          ## `if`, `when`, `case`: one of its arms is shown
    ikArm = "arm"                ## ... one arm
    ikBox = "box"                ## drawn as a box: a loop, a call of your own
    ikCode = "code"              ## code that draws nothing
  Item* = ref object
    kind*: ItemKind
    node*: PNode                 ## the statement (an arm: its branch)
    call*: PNode                 ## the control's or the block's call
    name*: string                ## the control's or the block's name
    list*: PNode                 ## the body the statement is in
    owner*: PNode                ## what owns that body
    body*: PNode                 ## a block's, an arm's body
    bodies*: seq[seq[Item]]      ## a block's bodies (most have one)
    kids*: seq[Item]             ## a block's (first body), a branch's arms, an arm's items
    parent*: Item
    line*: int
    shown*: int                  ## a branch: the arm shown (-1: worked out)
    cond*: string                ## an arm: its condition ("else")
    rect*: Rect                  ## where it was drawn last (logical pixels)
    drawn*: bool                 ## ... it was drawn in the last frame
  PageKind* = enum
    pgApp = "app", pgLoop = "window", pgProc = "proc"
  Page* = ref object
    kind*: PageKind
    title*: string
    node*: PNode                 ## the `app` call, the `while` loop, the proc
    sizeCall*: PNode             ## the call whose arguments are its size (`app`, `openApp`)
    body*: PNode
    w*, h*: int                  ## its size (design pixels)
    root*: Item                  ## an item holding the body's items
    setup*: seq[PNode]           ## (a `while beginFrame()` window: what comes before its
                                 ##  loop -- its variables' starting values)
  VarInfo* = object
    name*, typ*, init*: string   ## a variable of the file: its name, type, starting value
    node*: PNode                 ## its `var x = ...` (the identdefs)
    section*: PNode
    line*: int
    isConst*, isLet*: bool
  Design* = ref object
    src*: Src
    pages*: seq[Page]
    vars*: seq[VarInfo]
    procs*: Table[string, PNode] ## the file's procs, by name
    uiProcs*: Table[string, Page]

proc isControl*(name: string): bool = controls.hasKey(name)
proc isBlock*(name: string): bool = blocks.hasKey(name)

proc condText(s: Src; n: PNode): string =
  s.textOf(n).replace("\n", " ")

proc firstStr(n: PNode): string =
  for a in n.args:
    let x = if a.kind == nkExprEqExpr: a[1] else: a
    if x.kind in {nkStrLit, nkRStrLit, nkTripleStrLit}: return x.strVal
    if x.kind in {nkCall, nkCommand} and x.callee == "tr" and x.len > 1 and
       x[1].kind in {nkStrLit, nkRStrLit, nkTripleStrLit}:
      return x[1].strVal
  ""

proc intArgs(n: PNode): seq[int] =
  for a in n.args:
    let x = if a.kind == nkExprEqExpr: a[1] else: a
    if x.kind in {nkIntLit .. nkUInt64Lit}: result.add int(x.intVal)

proc drawsSomething(d: Design; n: PNode; depth = 0): bool =
  ## `n` (a body) calls a control or a block somewhere in it.
  if n == nil or depth > 40: return false
  let c = n.callee
  if c.len > 0 and (c.isControl or c.isBlock or d.uiProcs.hasKey(c)): return true
  if n.kind in {nkProcDef, nkFuncDef, nkTemplateDef, nkMacroDef, nkIteratorDef}: return false
  for i in 0 ..< n.safeLen:
    if d.drawsSomething(n[i], depth + 1): return true
  false

proc controlCall(n: PNode): PNode =
  ## The control called by statement `n`, else nil.
  if n == nil: return nil
  case n.kind
  of nkCall, nkCommand, nkIdent:
    if n.callee.isControl and n.bodyOf == nil: return n
  of nkDiscardStmt:
    if n.len > 0: return controlCall(n[0])
  of nkPar:
    if n.len == 1: return controlCall(n[0])
  of nkPrefix:
    # (`not button("x")`)
    if n.len == 2: return controlCall(n[1])
  of nkInfix:
    if n.len == 3:
      let l = controlCall(n[1])
      if l != nil: return l
      return controlCall(n[2])
  else: discard
  nil

proc build(d: Design; list, owner: PNode; parent: Item): seq[Item]

proc classify(d: Design; st, list, owner: PNode; parent: Item): Item =
  let s = d.src
  result = Item(node: st, list: list, owner: owner, parent: parent, line: s.lineOfNode(st),
                shown: -1)
  let it = result
  case st.kind
  of nkCall, nkCommand, nkIdent:
    let c = st.callee
    let body = st.bodyOf
    if body != nil and c.isBlock:
      it.kind = ikBlock
      it.call = st
      it.name = c
      it.body = body
      # (a second body: `do:` after the first, a split's right side)
      var bs: seq[PNode]
      for i in 1 ..< st.len:
        if st[i].kind == nkStmtList: bs.add st[i]
        elif st[i].kind == nkDo and st[i].len > 0: bs.add st[i][^1]
      for b in bs: it.bodies.add d.build(b, st, it)
      if it.bodies.len > 0: it.kids = it.bodies[0]
    elif body == nil and c.isControl:
      it.kind = ikControl
      it.call = st
      it.name = c
    elif c.len > 0 and d.uiProcs.hasKey(c):
      it.kind = ikBox
      it.call = st
      it.name = c
    elif body != nil:
      it.kind = ikBox
      it.call = st
      it.name = c
    else:
      it.kind = ikCode
  of nkDiscardStmt:
    let cc = controlCall(st)
    if cc != nil:
      it.kind = ikControl
      it.call = cc
      it.name = cc.callee
    else: it.kind = ikCode
  of nkIfStmt, nkWhenStmt:
    let first = if st.len > 0: st[0] else: nil
    let cc = if first != nil and first.kind in {nkElifBranch, nkElifExpr} and first.len > 0:
               controlCall(first[0]) else: nil
    if cc != nil:
      it.kind = ikEvent
      it.call = cc
      it.name = cc.callee
      it.body = first.bodyOf
    elif d.drawsSomething(st):
      it.kind = ikBranch
      for br in st:
        let arm = Item(kind: ikArm, node: br, owner: br, parent: it, line: s.lineOfNode(br),
                       shown: -1)
        arm.body = br.bodyOf
        arm.list = st
        arm.cond = if br.kind in {nkElse, nkElseExpr}: "else"
                   elif br.len > 0: (if st.kind == nkWhenStmt: "when " else: "if ") &
                                    s.condText(br[0])
                   else: ""
        arm.kids = d.build(arm.body, br, arm)
        it.kids.add arm
    else: it.kind = ikCode
  of nkCaseStmt:
    let cc = if st.len > 0: controlCall(st[0]) else: nil
    if cc != nil:
      it.kind = ikEvent
      it.call = cc
      it.name = cc.callee
    elif d.drawsSomething(st):
      it.kind = ikBranch
      for i in 1 ..< st.len:
        let br = st[i]
        let arm = Item(kind: ikArm, node: br, owner: br, parent: it, line: s.lineOfNode(br),
                       shown: -1)
        arm.body = br.bodyOf
        arm.list = st
        if br.kind == nkElse: arm.cond = "else"
        else:
          var cs: seq[string]
          for k in 0 ..< br.len - 1: cs.add s.textOf(br[k])
          arm.cond = "of " & cs.join(", ")
        arm.kids = d.build(arm.body, br, arm)
        it.kids.add arm
    else: it.kind = ikCode
  of nkLetSection, nkVarSection:
    it.kind = ikCode
    if st.len == 1 and st[0].kind == nkIdentDefs and st[0].len >= 3:
      let cc = controlCall(st[0][^1])
      if cc != nil:
        it.kind = ikValue
        it.call = cc
        it.name = cc.callee
  of nkForStmt, nkWhileStmt:
    it.kind = if d.drawsSomething(st): ikBox else: ikCode
    it.name = if st.kind == nkForStmt: "for" else: "while"
    if it.kind == ikBox and st.kind == nkForStmt:
      # (what it draws: drawn for each value, its controls chosen and set)
      it.body = st.bodyOf
      it.kids = d.build(it.body, st, it)
  of nkBlockStmt:
    if d.drawsSomething(st):
      it.kind = ikBranch
      let arm = Item(kind: ikArm, node: st, owner: st, parent: it, line: it.line, shown: -1,
                     cond: "block")
      arm.body = st.bodyOf
      arm.list = st
      arm.kids = d.build(arm.body, st, arm)
      it.kids.add arm
    else: it.kind = ikCode
  else:
    it.kind = ikCode

proc build(d: Design; list, owner: PNode; parent: Item): seq[Item] =
  if list == nil: return
  for st in list.stmts:
    if st.kind in {nkCommentStmt, nkEmpty}: continue
    result.add d.classify(st, list, owner, parent)

proc findLoops(n: PNode; owner: PNode; acc: var seq[tuple[loop, list, owner: PNode]]) =
  if n == nil: return
  if n.kind in {nkStmtList, nkStmtListExpr}:
    for st in n:
      if st.kind == nkWhileStmt and st.len > 0 and st[0].callee == "beginFrame":
        acc.add (st, n, owner)
  for i in 0 ..< n.safeLen:
    let o = if n.kind in {nkProcDef, nkFuncDef}: n else: owner
    findLoops(n[i], o, acc)

proc procName(n: PNode): string =
  if n == nil or n.kind notin {nkProcDef, nkFuncDef} or n.len == 0: return ""
  var x = n[0]
  if x.kind == nkPostfix: x = x[1]
  if x.kind == nkIdent: x.ident.s else: ""

proc readVars(d: Design) =
  for st in d.src.tree:
    if st.kind in {nkVarSection, nkLetSection, nkConstSection}:
      for def in st:
        if def.kind notin {nkIdentDefs, nkConstDef}: continue
        let init = if def.len >= 1: def[^1] else: nil
        let typ = if def.len >= 2: def[^2] else: nil
        for k in 0 ..< def.len - 2:
          var nm = def[k]
          if nm.kind == nkPragmaExpr: nm = nm[0]
          if nm.kind == nkPostfix: nm = nm[1]
          if nm.kind != nkIdent: continue
          d.vars.add VarInfo(name: nm.ident.s, node: def, section: st,
                             typ: (if typ != nil and typ.kind != nkEmpty: d.src.textOf(typ) else: ""),
                             init: (if init != nil and init.kind != nkEmpty: d.src.textOf(init) else: ""),
                             line: d.src.lineOfNode(def), isConst: st.kind == nkConstSection,
                             isLet: st.kind == nkLetSection)

proc readDesign*(src: Src): Design =
  ## The file's pages and variables.
  let d = Design(src: src)
  if src.tree == nil: return d
  d.readVars()
  # the procs that draw (each a page; a call of one is a box that opens it)
  for st in src.tree:
    let nm = procName(st)
    if nm.len > 0:
      d.procs[nm] = st
  var loops: seq[tuple[loop, list, owner: PNode]]
  findLoops(src.tree, nil, loops)
  # (a proc that only calls another that draws draws too: until no more are found)
  var more = true
  while more:
    more = false
    for nm, p in d.procs:
      if d.uiProcs.hasKey(nm): continue
      var inner: seq[tuple[loop, list, owner: PNode]]
      findLoops(p, p, inner)
      if inner.len == 0 and d.drawsSomething(p.bodyOf):
        d.uiProcs[nm] = Page(kind: pgProc, title: nm, node: p, body: p.bodyOf, w: 420, h: 300)
        more = true
  # `app "Title", w, h:` at the top
  for st in src.tree:
    if st.callee == "app" and st.bodyOf != nil:
      let ints = st.intArgs
      d.pages.add Page(kind: pgApp, title: st.firstStr, node: st, sizeCall: st,
                       body: st.bodyOf,
                       w: (if ints.len > 0: ints[0] else: 640),
                       h: (if ints.len > 1: ints[1] else: 480))
  # each `while beginFrame():` window: its title and size from the openApp before it
  for (loop, list, owner) in loops:
    var title = procName(owner)
    var sizeCall: PNode = nil
    var w = 640
    var h = 480
    var setup: seq[PNode]
    for st in list.stmts:
      if st == loop: break
      setup.add st
      let c = st.callee
      if c.startsWith("open") and st.isCallNode:
        let t = st.firstStr
        if t.len > 0: title = t
        let ints = st.intArgs
        if ints.len >= 2:
          w = ints[0]
          h = ints[1]
          sizeCall = st
    d.pages.add Page(kind: pgLoop, title: (if title.len > 0: title else: "Window"),
                     node: loop, sizeCall: sizeCall, body: loop.bodyOf, w: w, h: h,
                     setup: setup)
  var procPages: seq[Page]
  for nm, pg in d.uiProcs: procPages.add pg
  procPages.sort(proc (a, b: Page): int = cmp(a.node.info.line, b.node.info.line))
  d.pages.add procPages
  for pg in d.pages:
    pg.root = Item(kind: ikArm, node: pg.node, owner: pg.node, body: pg.body,
                   name: pg.title, shown: -1)
    pg.root.kids = d.build(pg.body, pg.node, pg.root)
  d

iterator walk*(it: Item): Item =
  ## `it` and everything in it, depth first.
  var stack = @[it]
  while stack.len > 0:
    let x = stack.pop()
    yield x
    if x.kind == ikBlock and x.bodies.len > 1:
      for b in countdown(x.bodies.high, 0):
        for k in countdown(x.bodies[b].high, 0): stack.add x.bodies[b][k]
    else:
      for k in countdown(x.kids.high, 0): stack.add x.kids[k]

proc label*(d: Design; it: Item): string =
  ## How the Object Tree names an item.
  let s = d.src
  case it.kind
  of ikControl, ikValue, ikEvent:
    var t = it.name
    let txt = it.call.firstStr
    if txt.len > 0: t.add "  \"" & txt.replace("&", "") & "\""
    else:
      for a in it.call.args:
        if a.kind == nkIdent:
          t.add "  " & a.ident.s
          break
    if it.kind == ikEvent: t.add "  (event)"
    t
  of ikBlock:
    var t = it.name
    let txt = it.call.firstStr
    if txt.len > 0: t.add "  \"" & txt.replace("&", "") & "\""
    t
  of ikBranch:
    let n = it.node
    case n.kind
    of nkIfStmt: "if"
    of nkWhenStmt: "when"
    of nkCaseStmt: "case " & (if n.len > 0: s.condText(n[0]) else: "")
    else: "block"
  of ikArm: it.cond
  of ikBox:
    if it.call != nil and d.uiProcs.hasKey(it.name): return it.name & "()  (proc)"
    let line = s.lineText(it.line).strip
    if line.len > 50: line[0 ..< 50] & "..." else: line
  of ikCode: s.lineText(it.line).strip

proc findItem*(pg: Page; node: PNode): Item =
  ## The item of statement `node` on the page.
  if pg == nil or pg.root == nil: return nil
  for x in pg.root.walk:
    if x.node == node: return x
  nil

proc itemAtLine*(pg: Page; line: int): Item =
  ## The innermost item on the page that starts at `line`.
  if pg == nil or pg.root == nil: return nil
  for x in pg.root.walk:
    if x != pg.root and x.line == line and x.kind != ikCode: result = x

proc varOf*(d: Design; name: string): int =
  ## The variable named `name` (as Nim reads names), else -1.
  for i, v in d.vars:
    if cmpIgnoreStyle(v.name, name) == 0 and v.name.len > 0 and name.len > 0 and
       v.name[0] == name[0]: return i
  -1
