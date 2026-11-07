## Tests of retroui/xmpp that need no server of anyone's: the parts of an
## address; a connection to a port where nothing answers -- the thread
## starts, says it is connecting, gives the error, and stops; and a session
## with a small server of the test's own (a thread that answers as a server
## would): signing on, the account's archive found, a page of it asked for
## and taken, a message with its archive id, a forged archive answer from
## someone else left out.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, net, times, strutils, typedthreads]
import retroui/xmpp

doAssert bareJid("me@yax.im/Retro") == "me@yax.im"
doAssert bareJid("me@yax.im") == "me@yax.im"
doAssert resourceOf("me@yax.im/Retro/2") == "Retro/2"
doAssert resourceOf("me@yax.im") == ""
doAssert domainOf("me@yax.im/Retro") == "yax.im"
doAssert domainOf("conference.yax.im") == "conference.yax.im"
doAssert localOf("me@yax.im/Retro") == "me"
doAssert localOf("yax.im") == ""
doAssert newId() != newId()

# (a port nobody listens on: the one a socket of ours had a moment ago)
let probe = newSocket()
probe.bindAddr(Port(0), "127.0.0.1")
let port = int(probe.getLocalAddr()[1])
probe.close()

xmppStart("me@127.0.0.1", "secret", host = "127.0.0.1", port = port)
doAssert xmppRunning()
var sawConnecting, sawError = false
let until = epochTime() + 10
while epochTime() < until and not sawError:
  for e in xmppEvents():
    case e.kind
    of xeConnecting: sawConnecting = true
    of xeError, xeOffline: sawError = true
    else: discard
  sleep(20)
doAssert sawConnecting, "no xeConnecting"
doAssert sawError, "no error for a port where nothing answers"
xmppStop()
doAssert not xmppRunning()

# ---- a session with a server of the test's own ---------------------------------------------------

proc fakeServer(sock: Socket) {.thread.} =
  ## Answers as an XMPP server would, enough for the session below (no
  ## TLS: the client is told `insecure`).
  var c: Socket
  sock.accept(c)
  var buf = ""
  var opened = 0
  let head = "<?xml version='1.0'?><stream:stream xmlns='jabber:client' " &
             "xmlns:stream='http://etherx.jabber.org/streams' id='s1' from='localhost' version='1.0'>"
  proc take(marker: string): bool =
    let k = buf.find(marker)
    if k < 0: return false
    buf = buf[k + marker.len .. ^1]
    true
  let until = epochTime() + 20
  var done = false
  while epochTime() < until and not done:
    var data = newString(4096)
    let n = try: c.recv(addr data[0], data.len) except CatchableError: -1
    if n <= 0: break
    data.setLen(n)
    buf.add data
    while true:
      if take("<stream:stream"):
        inc opened
        if opened == 1:
          c.send(head & "<stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>" &
                 "<mechanism>PLAIN</mechanism></mechanisms></stream:features>")
        else:
          c.send(head & "<stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>")
      elif take("<auth "):
        c.send("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      elif take("id='bind1'"):
        c.send("<iq type='result' id='bind1'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>" &
               "<jid>me@localhost/Retro</jid></bind></iq>")
      elif take("id='info-me@localhost'"):
        c.send("<iq type='result' id='info-me@localhost' from='me@localhost'>" &
               "<query xmlns='http://jabber.org/protocol/disco#info'><feature var='urn:xmpp:mam:2'/></query></iq>")
        # a message as it comes, with its id in the archive
        c.send("<message from='bob@localhost/Phone' to='me@localhost/Retro' type='chat' id='m9'>" &
               "<body>live</body><stanza-id xmlns='urn:xmpp:sid:0' by='me@localhost' id='A9'/></message>")
      elif buf.contains("queryid='") and buf.contains("</iq>"):
        let k = buf.find("queryid='") + 9
        let qid = buf[k ..< buf.find('\'', k)]
        buf = buf[buf.find("</iq>", k) + 5 .. ^1]
        # someone else pretending to be the archive: left out
        c.send("<message from='eve@localhost'><result xmlns='urn:xmpp:mam:2' queryid='" & qid & "' id='X'>" &
               "<forwarded xmlns='urn:xmpp:forward:0'><message from='bob@localhost' to='me@localhost' type='chat'>" &
               "<body>forged</body></message></forwarded></result></message>")
        c.send("<message to='me@localhost/Retro'><result xmlns='urn:xmpp:mam:2' queryid='" & qid & "' id='A1'>" &
               "<forwarded xmlns='urn:xmpp:forward:0'><delay xmlns='urn:xmpp:delay' stamp='2026-11-01T10:00:00Z'/>" &
               "<message from='bob@localhost/Phone' to='me@localhost' type='chat' id='m1'><body>hello</body>" &
               "</message></forwarded></result></message>")
        c.send("<message to='me@localhost/Retro'><result xmlns='urn:xmpp:mam:2' queryid='" & qid & "' id='A2'>" &
               "<forwarded xmlns='urn:xmpp:forward:0'><delay xmlns='urn:xmpp:delay' stamp='2026-11-01T10:01:00Z'/>" &
               "<message from='me@localhost/Laptop' to='bob@localhost' type='chat' id='m2'><body>hi &amp; bye</body>" &
               "<x xmlns='jabber:x:oob'><url>https://x/v.m4a</url></x></message></forwarded></result></message>")
        c.send("<iq type='result' id='" & qid & "'><fin xmlns='urn:xmpp:mam:2' complete='true'>" &
               "<set xmlns='http://jabber.org/protocol/rsm'><first index='0'>A1</first><last>A2</last>" &
               "<count>2</count></set></fin></iq>")
      elif take("</stream:stream>"):
        done = true
        break
      else: break
  c.close()

let server = newSocket(buffered = false)
server.setSockOpt(OptReuseAddr, true)
server.bindAddr(Port(0), "127.0.0.1")
server.listen()
let serverPort = int(server.getLocalAddr()[1])
var serverThread: Thread[Socket]
createThread(serverThread, fakeServer, server)

xmppStart("me@localhost", "secret", host = "127.0.0.1", port = serverPort, insecure = true)
var online, archive, done = false
var live: XmppEvent
var got: seq[XmppEvent]
var fin: XmppEvent
var asked = ""
let until2 = epochTime() + 15
while epochTime() < until2 and not done:
  for e in xmppEvents():
    case e.kind
    of xeOnline: online = true
    of xeServices:
      for (k, v) in e.fields:
        if k == "archive" and v == "me@localhost":
          archive = true
          asked = askArchive(with = "bob@localhost", latest = true, max = 20)
    of xeMessage: live = e
    of xeArchived: got.add e
    of xeArchiveDone:
      fin = e
      done = true
    of xeError: echo "error: ", e.text
    else: discard
    when defined(xmppDebug): echo e.kind, " ", e.text
  sleep(10)
doAssert online, "signed on"
doAssert archive, "the account's archive found"
doAssert live.text == "live" and live.archiveId == "A9", "a message with its archive id: " & $live
doAssert got.len == 2, "two from the archive, the forged one left out: " & $got.len
doAssert got[0].jid == "bob@localhost" and got[0].text == "hello" and not got[0].mine and
         got[0].archiveId == "A1" and got[0].stamp == "2026-11-01T10:00:00Z" and got[0].id == "m1" and
         got[0].resource == asked
doAssert got[1].jid == "bob@localhost" and got[1].mine and got[1].text == "hi & bye" and
         got[1].url == "https://x/v.m4a"
doAssert fin.id == asked and fin.text == "A2" and fin.show == "complete" and ("count", "2") in fin.fields
xmppStop()
let until3 = epochTime() + 5
while xmppRunning() and epochTime() < until3:
  discard xmppEvents()
  sleep(10)
doAssert not xmppRunning()
joinThread(serverThread)
server.close()
echo "test_xmpp: ok"
