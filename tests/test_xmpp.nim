## Tests of retroui/xmpp that need no server: the parts of an address, and a
## connection to a port where nothing answers -- the thread starts, says it
## is connecting, gives the error, and stops.
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/[os, net, times]
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
echo "test_xmpp: ok"
