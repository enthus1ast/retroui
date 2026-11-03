## The local database (retro/db): values, a mail-like schema with FTS5
## search over 20 000 messages, Arabic, the kept statements, transactions,
## errors, and a writer and a reader in two threads at once.

import std/[os, strutils, random, monotimes, times, typedthreads, atomics]
import retro/db

let dir = getTempDir() / "retro-test-db-" & $getCurrentProcessId()
removeDir(dir)

proc ms(since: MonoTime): float = float((getMonoTime() - since).inNanoseconds) / 1e6

proc raisesDb(body: proc ()): ref DbError =
  try: body()
  except DbError as e: return e
  doAssert false, "no DbError"

echo "SQLite ", sqliteVersion()
doAssert sqliteVersion().startsWith("3.")

block values:
  doAssert toDbValue(3).kind == dkInt and toDbValue(3).num == 3 and toDbValue(3).flt == 3.0
  doAssert toDbValue(2.75).flt == 2.75 and toDbValue(2.75).num == 2 and toDbValue(-2.75).num == -2
  doAssert toDbValue("12").num == 12 and toDbValue(" 7.9 ").num == 7 and toDbValue("x").num == 0
  doAssert toDbValue("2.5").flt == 2.5 and toDbValue("abc").flt == 0.0
  doAssert toDbValue(true).num == 1 and toDbValue(false).num == 0
  doAssert toDbValue(42).str == "42" and toDbValue("hi").str == "hi"
  doAssert dbNull().isNull and dbNull().str == "" and dbNull().num == 0 and dbNull().flt == 0
  doAssert blob("a\0b").kind == dkBlob and blob("a\0b").str == "a\0b" and blob("12").num == 0
  doAssert toDbValue(1e300).num == high(int64) and toDbValue(NaN).num == 0
  doAssert $toDbValue("x") == "\"x\"" and $dbNull() == "NULL"

  let m = openDb(":memory:")
  m.exec("CREATE TABLE v(a, b, c, d, e, f, g)")
  m.exec("INSERT INTO v VALUES(?, ?, ?, ?, ?, ?, ?)", 1, 2.5, "text", blob("a\0b"), dbNull(), "",
         "سلام 👋")
  doAssert m.lastInsertId == 1 and m.changes == 1
  let r = m.one("SELECT * FROM v")
  doAssert r.len == 7
  doAssert r[0] == toDbValue(1) and r[1].kind == dkFloat and r[1].f == 2.5
  doAssert r[2].kind == dkText and r[2].s == "text"
  doAssert r[3].kind == dkBlob and r[3].s == "a\0b"
  doAssert r[4].isNull
  doAssert r[5].kind == dkText and r[5].s == "", "an empty string stays text, not NULL"
  doAssert r[6].s == "سلام 👋"
  doAssert m.value("SELECT count(*) FROM v").num == 1
  doAssert m.value("SELECT a FROM v WHERE a = ?", 99).isNull
  doAssert m.one("SELECT a FROM v WHERE a = ?", 99).len == 0
  doAssert m.all("SELECT a FROM v").len == 1
  doAssert m.value("SELECT ?", high(int64)).num == high(int64)
  doAssert m.value("SELECT ? + 1", 41).num == 42
  doAssert m.value("SELECT length(?)", blob("")).num == 0
  doAssert m.columns("SELECT a, b AS bee FROM v") == @["a", "bee"]
  m.exec("UPDATE v SET a = a + 1")
  doAssert m.changes == 1
  doAssert m.userVersion == 0
  m.userVersion = 3
  doAssert m.userVersion == 3
  # a value made from an int32, a float32, a byte sequence
  m.exec("INSERT INTO v(a, b, d) VALUES(?, ?, ?)", int32(-5), float32(0.5), blob([1'u8, 2, 3]))
  doAssert m.one("SELECT a, b, d FROM v WHERE rowid = ?", m.lastInsertId) ==
    @[toDbValue(-5), toDbValue(0.5), blob("\1\2\3")]
  m.close()
  m.close()                                      # (twice: nothing)
  doAssert not m.isOpen

block ftsQueries:
  doAssert ftsQuery("inv") == "\"inv\"*"
  doAssert ftsQuery("  march   inv ") == "\"march\" \"inv\"*"
  doAssert ftsQuery("a\"b") == "\"a\"\"b\"*"
  doAssert ftsQuery("NOT x OR") == "\"NOT\" \"x\" \"OR\"*"
  doAssert ftsQuery("") == "\"\"" and ftsQuery(" - * ( ") == "\"\""
  doAssert ftsQuery("invoice —") == "\"invoice\"*", "words without letters are dropped"
  doAssert ftsQuery("فاتورة") == "\"فاتورة\"*", "as typed, unless asked"
  doAssert ftsQuery("فاتورة", fold = true) == "\"فاتوره\"*"
  doAssert ftsQuery("مُدير", fold = true) == "\"مدير\"*" and ftsQuery("ً", fold = true) == "\"\""
  doAssert ftsText("مُدير المَكتب، شكراً") == "مدير المكتب، شكرا"
  doAssert ftsText("أحمد إبراهيم آمنة على") == "احمد ابراهيم امنه علي"
  doAssert ftsText("plain text, café") == "plain text, café"
  doAssert ftsText("bad \xFF\xD8 bytes") == "bad \xFF\xD8 bytes"
  let m = openDb(":memory:")
  m.execScript("CREATE VIRTUAL TABLE f USING fts5(body)")
  m.exec("INSERT INTO f(body) VALUES('invoice for march')")
  # nothing anyone types gives a syntax error
  for typed in ["", "\"", "\"\"\"", "AND", "OR OR", "NEAR(a b)", "a:b", "col:x", "^x", "x*", "*",
                "(", ")", "-x", "+", "a AND (b", "{a b}", "\0", "\xFF\xFE", "؟ ، —", "x\"y\"z",
                "NOT", "a NOT", "''", ";", "--", "/* */", "🙂", "invoice"]:
    discard m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery(typed))
    discard m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery(typed, fold = true))
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("MAR")).len == 1
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("invoice ma")).len == 1
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("invoice april")).len == 0
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("")).len == 0
  # an index of the text as it is: found as written (folding is for both sides or neither)
  m.exec("INSERT INTO f(body) VALUES(?)", "فاتورة الكهرباء")
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("فاتورة")).len == 1
  doAssert m.all("SELECT rowid FROM f WHERE f MATCH ?", ftsQuery("الكهر")).len == 1
  # fts_text() in SQL: text folded, other values as they are
  doAssert m.value("SELECT fts_text('شُكراً')").str == "شكرا"
  doAssert m.value("SELECT fts_text(5)").num == 5 and m.value("SELECT fts_text(NULL)").isNull

const Schema = """
CREATE TABLE IF NOT EXISTS folders(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS messages(
  id INTEGER PRIMARY KEY,
  folder INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  remote_id TEXT UNIQUE,
  subject TEXT, sender TEXT, date INTEGER, body TEXT, flags INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS messages_by_date ON messages(folder, date DESC);
-- the search index: only the words (the text is in messages), Arabic folded
CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(subject, sender, body,
  content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 2');
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO message_fts(rowid, subject, sender, body)
    VALUES (new.id, fts_text(new.subject), fts_text(new.sender), fts_text(new.body));
END;
CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
  DELETE FROM message_fts WHERE rowid = old.id;
END;
CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF subject, sender, body ON messages BEGIN
  DELETE FROM message_fts WHERE rowid = old.id;
  INSERT INTO message_fts(rowid, subject, sender, body)
    VALUES (new.id, fts_text(new.subject), fts_text(new.sender), fts_text(new.body));
END;
"""

proc search(db: Db; typed: string; limit = 50): seq[int64] =
  for r in db.rows("""SELECT m.id FROM message_fts JOIN messages m ON m.id = message_fts.rowid
                      WHERE message_fts MATCH ? ORDER BY rank LIMIT ?""", ftsQuery(typed, fold = true), limit):
    result.add r[0].num

proc count(db: Db; typed: string): int =
  int(db.value("SELECT count(*) FROM message_fts WHERE message_fts MATCH ?", ftsQuery(typed, fold = true)).num)

let mailPath = dir / "account" / "mail.db"

block mail:
  let db = openDb(mailPath)
  doAssert fileExists(mailPath), "the folder is made"
  doAssert db.value("PRAGMA journal_mode").str == "wal"
  doAssert db.value("PRAGMA foreign_keys").num == 1
  doAssert db.value("PRAGMA synchronous").num == 1
  db.execScript(Schema)
  db.execScript(Schema)                          # (IF NOT EXISTS: again is fine)
  db.exec("INSERT INTO folders(name) VALUES(?)", "Inbox")
  let inbox = db.lastInsertId
  db.exec("INSERT INTO folders(name) VALUES(?)", "Archive")
  let archive = db.lastInsertId

  const
    words = ["meeting", "report", "budget", "hotel", "guest", "training", "schedule", "staff",
             "quality", "review", "pool", "room", "kitchen", "contract", "visa", "leave",
             "uniform", "audit", "laundry", "spa", "menu", "please", "thanks", "regards", "the",
             "and", "for", "with", "this", "that", "will", "from", "your", "our", "today",
             "tomorrow", "week", "month", "team", "shift", "night", "morning", "approval",
             "request", "form", "policy", "update", "attached", "find", "below"]
    rare = ["invoice", "inventory", "payroll"]
    arabic = ["اجتماع", "تقرير", "الميزانية", "الفندق", "الضيوف", "تدريب", "جدول", "الموظفين",
              "إجازة", "رواتب", "مراجعة", "الجودة"]
    names = ["Sultan Al Isaiee", "Maryam Al Balushi", "John Smith", "أحمد الحارثي", "Fatma Al Rawahi"]
  var rng = initRand(2026)
  var expectInv, expectPayroll, expectArabic = 0
  let n = 20_000
  let t0 = getMonoTime()
  db.transaction:
    for i in 0 ..< n:
      var subject, body: seq[string]
      for k in 0 ..< 5: subject.add words[rng.rand(words.high)]
      for k in 0 ..< 80: body.add words[rng.rand(words.high)]
      if rng.rand(99) < 4: body.insert(rare[rng.rand(rare.high)], rng.rand(body.len))
      if rng.rand(99) < 2: subject.add rare[rng.rand(rare.high)]
      for k in 0 ..< 10: body.add "w" & $rng.rand(5000)       # (a long tail of other words)
      if i mod 7 == 0:
        for k in 0 ..< 8: body.add arabic[rng.rand(arabic.high)]
      let s = subject.join(" ")
      let b = body.join(" ")
      let sender = names[rng.rand(names.high)]
      if "invoice" in s or "inventory" in s or "invoice" in b or "inventory" in b: inc expectInv
      if "payroll" in s or "payroll" in b: inc expectPayroll
      if "رواتب" in b: inc expectArabic
      db.exec("INSERT INTO messages(folder, remote_id, subject, sender, date, body) VALUES(?, ?, ?, ?, ?, ?)",
              (if i mod 3 == 0: archive else: inbox), "id" & $i, s, sender, 1_760_000_000 + i * 60, b)
  let insertMs = ms(t0)
  doAssert db.value("SELECT count(*) FROM messages").num == n

  # searching: the counts are right, and quick
  doAssert db.count("inv") == expectInv, $db.count("inv") & " " & $expectInv
  doAssert db.count("PAYROLL") == expectPayroll
  doAssert db.count("payroll inv") <= min(expectPayroll, expectInv)
  doAssert db.count("رواتب") == expectArabic and expectArabic > 0
  doAssert db.count("Isaiee") > 0 and db.count("الحارثي") > 0
  doAssert db.search("payroll").len == min(50, expectPayroll)
  doAssert expectInv in 400 .. 2000 and expectPayroll > 50
  proc timed(q: string): float =
    let t = getMonoTime()
    for k in 0 ..< 20: doAssert db.search(q).len <= 50
    ms(t) / 20
  let rareMs = timed("payroll")
  let prefix = timed("inv")
  let arabicMs = timed("رواتب")
  let common = timed("hotel guest")                # (in nearly every message)
  let t2 = getMonoTime()
  let all = db.count("inv")
  let countMs = ms(t2)
  doAssert all == expectInv
  echo "  ", n, " messages inserted (with the FTS5 index) in one transaction: ",
       int(insertMs), " ms"
  echo "  best 50 by rank: \"payroll\" ", formatFloat(rareMs, ffDecimal, 2), " ms, \"inv\" ",
       formatFloat(prefix, ffDecimal, 2), " ms, \"رواتب\" ", formatFloat(arabicMs, ffDecimal, 2),
       " ms, \"hotel guest\" (", db.count("hotel guest"), " matches) ",
       formatFloat(common, ffDecimal, 1), " ms; counting the ", all, " matches of \"inv\": ",
       formatFloat(countMs, ffDecimal, 2), " ms"

  # Arabic as people type it: no vowel marks, alef without hamza, ه for ة
  db.exec("INSERT INTO messages(folder, subject, sender, body) VALUES(?, ?, ?, ?)", inbox,
          "فاتورة الكهرباء لشهر مارس", "أحمد البلوشي <ahmed@example.om>",
          "مُدير المَكتب أرسلَ الفاتورة. شكراً لكم، وإلى اللقاء. Café crème.")
  let ar = db.lastInsertId
  for typed in ["فاتورة", "فاتوره", "الكهرب", "مدير", "مُدير", "المكتب", "احمد", "أحمد", "البلوشي",
                "شكرا", "والى", "cafe", "CRÈME", "ahmed@example", "مارس الفاتوره"]:
    doAssert ar in db.search(typed), "not found: " & typed
  doAssert ar notin db.search("فاتورة ابريل")
  # the index follows updates and deletes
  db.exec("UPDATE messages SET subject = ? WHERE id = ?", "فاتورة الماء", ar)
  doAssert ar in db.search("الماء") and ar notin db.search("الكهرباء")
  db.exec("DELETE FROM messages WHERE id = ?", ar)
  doAssert db.search("الماء").len == 0

  # foreign keys are on: a message needs its folder; a folder takes its messages along
  let fk = raisesDb(proc () = db.exec("INSERT INTO messages(folder, subject) VALUES(?, ?)", 999, "x"))
  doAssert "FOREIGN KEY" in fk.msg
  let before = db.value("SELECT count(*) FROM messages").num
  let inArchive = db.value("SELECT count(*) FROM messages WHERE folder = ?", archive).num
  db.exec("DELETE FROM folders WHERE id = ?", archive)
  doAssert db.value("SELECT count(*) FROM messages").num == before - inArchive
  doAssert db.count("inv") < expectInv, "the cascade emptied the index too"
  db.close()

block rowsLeftEarly:
  let db = openDb(":memory:")
  db.execScript("CREATE TABLE t(x); CREATE TABLE u(x)")
  db.transaction:
    for i in 1 .. 100: db.exec("INSERT INTO t VALUES(?)", i)
  var n = 0
  for r in db.rows("SELECT x FROM t ORDER BY x"):
    inc n
    if n == 3: break
  doAssert n == 3
  # (a statement still running would keep the table locked)
  db.exec("CREATE TABLE t2 AS SELECT * FROM t")
  for r in db.rows("SELECT x FROM t2"): break
  db.exec("DROP TABLE t2")
  # an exception in the loop: reset too
  try:
    for r in db.rows("SELECT x FROM t WHERE x > ?", 50):
      raise newException(ValueError, "stop")
  except ValueError: discard
  db.exec("CREATE TABLE t3 AS SELECT * FROM t")
  for r in db.rows("SELECT x FROM t3"):
    if r[0].num == 1: break
  db.exec("DROP TABLE t3")
  # `one` and `value` stop after the first row, and the statement is ready again
  doAssert db.one("SELECT x FROM t ORDER BY x") == @[toDbValue(1)]
  doAssert db.one("SELECT x FROM t ORDER BY x") == @[toDbValue(1)]
  doAssert db.value("SELECT x FROM t ORDER BY x DESC").num == 100
  # the same statement inside its own loop: each loop runs its own
  var pairs = 0
  for a in db.rows("SELECT x FROM t WHERE x <= ?", 10):
    for b in db.rows("SELECT x FROM t WHERE x <= ?", 10):
      inc pairs
  doAssert pairs == 100
  # more statements than are kept: the oldest are dropped, all still work
  for round in 0 .. 1:
    for i in 0 ..< 150:
      doAssert db.value("SELECT " & $i & " + x FROM t WHERE x = ?", 1).num == i + 1
  # the connection closed inside a loop: the loop ends cleanly after
  var seen = 0
  for r in db.rows("SELECT x FROM t"):
    inc seen
    db.close()
    break
  doAssert seen == 1 and not db.isOpen
  doAssert "closed" in raisesDb(proc () = discard db.value("SELECT 1")).msg

block transactions:
  let db = openDb(dir / "tx.db")
  db.exec("CREATE TABLE t(x INTEGER)")
  proc xs(): seq[int64] =
    for r in db.rows("SELECT x FROM t ORDER BY x"): result.add r[0].num
  # nested: an inner one that fails is undone alone
  db.transaction:
    db.exec("INSERT INTO t VALUES(1)")
    try:
      db.transaction:
        db.exec("INSERT INTO t VALUES(2)")
        db.transaction:
          db.exec("INSERT INTO t VALUES(22)")
        raise newException(ValueError, "inner fails")
    except ValueError: discard
    doAssert db.inTransaction
    db.transaction:
      db.exec("INSERT INTO t VALUES(3)")
  doAssert xs() == @[1'i64, 3]
  doAssert not db.inTransaction
  # an exception undoes it all and goes on
  try:
    db.transaction:
      db.exec("INSERT INTO t VALUES(4)")
      db.transaction:
        db.exec("INSERT INTO t VALUES(5)")
      raise newException(IOError, "outer fails")
  except IOError as e:
    doAssert e.msg == "outer fails"
  doAssert xs() == @[1'i64, 3] and not db.inTransaction
  # so does a failing statement
  db.exec("CREATE UNIQUE INDEX t_x ON t(x)")
  let e = raisesDb(proc () =
    db.transaction:
      db.exec("INSERT INTO t VALUES(6)")
      db.exec("INSERT INTO t VALUES(1)"))
  doAssert "UNIQUE" in e.msg and e.code == 2067, e.msg & " " & $e.code
  doAssert xs() == @[1'i64, 3] and not db.inTransaction
  # leaving with `return` commits
  proc early(stop: bool) =
    db.transaction:
      db.exec("INSERT INTO t VALUES(7)")
      if stop: return
      db.exec("INSERT INTO t VALUES(8)")
  early(true)
  doAssert xs() == @[1'i64, 3, 7] and not db.inTransaction
  # the committed rows are there for another connection
  let other = openDb(dir / "tx.db", readOnly = true)
  doAssert other.value("SELECT count(*) FROM t").num == 3
  doAssert "readonly" in raisesDb(proc () = other.exec("INSERT INTO t VALUES(9)")).msg
  other.close()
  # a transaction begun by hand: the template nests in it
  db.exec("BEGIN")
  db.transaction:
    db.exec("INSERT INTO t VALUES(10)")
  doAssert db.inTransaction
  db.exec("ROLLBACK")
  doAssert xs() == @[1'i64, 3, 7]
  db.close()

block errors:
  let db = openDb(":memory:")
  db.exec("CREATE TABLE t(x INTEGER NOT NULL)")
  var e = raisesDb(proc () = db.exec("SELEC 1"))
  doAssert "syntax error" in e.msg and "SELEC 1" in e.msg, e.msg
  e = raisesDb(proc () = db.exec("INSERT INTO nowhere VALUES(1)"))
  doAssert "no such table: nowhere" in e.msg
  e = raisesDb(proc () = db.exec("INSERT INTO t VALUES(?)", dbNull()))
  doAssert "NOT NULL constraint failed: t.x" in e.msg
  e = raisesDb(proc () = db.exec("INSERT INTO t VALUES(?)"))
  doAssert "1 parameters, 0 values" in e.msg
  e = raisesDb(proc () = db.exec("INSERT INTO t VALUES(1); INSERT INTO t VALUES(2)"))
  doAssert "one statement" in e.msg
  db.exec("INSERT INTO t VALUES(1);  -- a comment after is fine\n")
  e = raisesDb(proc () = db.execScript("CREATE TABLE a(x); CREATE TABLE a(x);"))
  doAssert "table a already exists" in e.msg
  e = raisesDb(proc () = discard db.all("SELECT * FROM t WHERE x = ? AND x = ?", 1))
  doAssert "parameters" in e.msg
  let long = "SELECT " & repeat("1 + ", 400) & "nosuchcolumn"
  e = raisesDb(proc () = discard db.value(long))
  doAssert "no such column" in e.msg and e.msg.len < 400, "the SQL is shortened"
  db.close()
  createDir(dir / "a folder")
  e = raisesDb(proc () = discard openDb(dir / "a folder"))
  doAssert e.msg.len > 0
  e = raisesDb(proc () = discard openDb(dir / "missing" / "x.db", readOnly = true))
  doAssert e.msg.len > 0

# ---- two threads: one writes, one reads, at once (WAL) ----------------------------------------

const
  Batches = 200
  PerBatch = 10

var
  readerChecks, readerPartial, readerLast, writerDone: Atomic[int]

proc writer(path: string) {.thread.} =
  let w = openDb(path)
  while readerChecks.load == 0: sleep(1)         # (the reader is looking)
  for i in 0 ..< Batches:
    w.transaction:
      for k in 0 ..< PerBatch:
        w.exec("INSERT INTO log(n, note) VALUES(?, ?)", i * PerBatch + k, "batch " & $i)
    if i mod 10 == 0: sleep(1)
  w.close()
  writerDone.store 1

proc reader(path: string) {.thread.} =
  let r = openDb(path, readOnly = true)
  var last = 0
  let until = epochTime() + 60
  while last < Batches * PerBatch:
    let c = int(r.value("SELECT count(*) FROM log").num)
    doAssert c mod PerBatch == 0, "half a transaction seen: " & $c
    doAssert c >= last, "the count went back"
    if c > 0 and c < Batches * PerBatch: readerPartial.atomicInc
    last = c
    readerChecks.atomicInc
    doAssert epochTime() < until, "the reader waited too long"
  readerLast.store last
  r.close()

block threads:
  let path = dir / "threads.db"
  let main = openDb(path)
  main.exec("CREATE TABLE log(n INTEGER PRIMARY KEY, note TEXT)")
  var tw, tr: Thread[string]
  let t0 = getMonoTime()
  createThread(tw, writer, path)
  createThread(tr, reader, path)
  joinThreads(tw, tr)
  doAssert writerDone.load == 1 and readerLast.load == Batches * PerBatch
  doAssert readerPartial.load > 0, "the reader saw the writer at work"
  doAssert main.value("SELECT count(*) FROM log").num == Batches * PerBatch
  echo "  two threads: ", Batches, " transactions written while the other read ",
       readerChecks.load, " times (", readerPartial.load, " mid-way), in ",
       int(ms(t0)), " ms"
  main.close()

removeDir(dir)
echo "test_db: ok"
