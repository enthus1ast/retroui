SQLite -- public domain
=======================

`sqlite3.c` and `sqlite3.h` here are the SQLite amalgamation, version
3.54.1 (source id 2026-10-16 14:45:20
555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76), as
sqlite.org publishes it, unchanged. `retro/db` compiles it in.

The SQLite source code is in the public domain
(https://sqlite.org/copyright.html). Its authors have released their work
to the public for any use; no licence and no attribution are needed. In
place of a legal notice, here is its blessing:

> May you do good and not evil.
> May you find forgiveness for yourself and forgive others.
> May you share freely, never taking more than you give.

To update: take `sqlite3.c` and `sqlite3.h` from a newer
`sqlite-amalgamation-*.zip` (https://sqlite.org/download.html), put them
here, write the version above, and run `tests/test_db.nim`.
