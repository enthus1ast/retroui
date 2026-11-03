#!/usr/bin/env python3
"""A small stand-in for the services Retro Mail talks to, for its tests:
Microsoft's and Google's sign-in (OAuth 2.0 with PKCE), Microsoft Graph's
mail, categories and calendar, the Gmail API (with its batch and upload
endpoints) and Google Calendar. State lives in memory; GET /test/state shows
it, POST /test/newmail adds a message to both inboxes.

    python3 tests/mailmock.py 8765

Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net
"""
import base64, hashlib, json, re, sys, threading, time, urllib.parse
from email import message_from_bytes, policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
NOW = time.time()

def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))

def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

def jwt(claims):
    return b64u(b'{"alg":"none"}') + "." + b64u(json.dumps(claims).encode()) + "."

PIXEL = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAGklEQVR4nGP4z8DAwMDAxMDAwMDAwMDAwAAAOAAD"
    "+u3b3gAAAABJRU5ErkJggg==")

NEWSLETTER = """<html><head><style>.pre{display:none;font-size:0;max-height:0}
.btn td{background:#0063b1;padding:10px 18px}.btn a{color:#ffffff;text-decoration:none}</style></head>
<body><span class="pre">This preheader must not show.</span>
<table width="100%" bgcolor="#eeeeee" cellpadding="0" cellspacing="0"><tr><td align="center">
<table width="600" bgcolor="#ffffff" cellpadding="16"><tr><td>
<h1 style="color:#003366">Retro Weekly</h1><p>Three new toolkits this week, and a
<b>big</b> one for Nim.</p><img src="cid:logo1" width="8" height="8" alt="logo">
<img src="https://example.com/banner.png" width="560" height="120" alt="Banner">
<table class="btn"><tr><td><a href="https://example.com/read">Read more</a></td></tr></table>
</td></tr></table></td></tr></table></body></html>"""

ARABIC = """<div dir="rtl"><p>مرحبا سلطان، هذا اختبار للبريد العربي مع كلمة English في الوسط.</p>
<p>الاجتماع يوم الثلاثاء الساعة 2</p></div>"""

def seed():
    g = {"me": {"displayName": "Sultan Al Isaiee", "mail": "sultan@contoso.com"},
         "folders": {}, "messages": {}, "deltas": {}, "categories": [
             {"displayName": "Retro", "color": "preset7"}, {"displayName": "Finance", "color": "preset4"}],
         "sent": [], "seq": 100, "events": []}
    for fid, name in [("f-inbox", "Inbox"), ("f-drafts", "Drafts"), ("f-sent", "Sent Items"),
                      ("f-trash", "Deleted Items"), ("f-archive", "Archive"),
                      ("f-junk", "Junk Email"), ("f-outbox", "Outbox"), ("f-proj", "Projects")]:
        g["folders"][fid] = {"id": fid, "displayName": name, "parentFolderId": "root",
                             "childFolderCount": 1 if fid == "f-proj" else 0,
                             "unreadItemCount": 0, "totalItemCount": 0}
    g["folders"]["f-proj-retro"] = {"id": "f-proj-retro", "displayName": "Retro", "parentFolderId": "f-proj",
                                    "childFolderCount": 0, "unreadItemCount": 0, "totalItemCount": 0}
    def add(mid, folder, frm, subj, html, t, conv, read=False, cats=(), att=False, to="sultan@contoso.com",
            focused=True):
        g["messages"][mid] = {
            "id": mid, "conversationId": conv, "subject": subj, "parentFolderId": folder,
            "from": {"emailAddress": {"name": frm[0], "address": frm[1]}},
            "toRecipients": [{"emailAddress": {"name": "", "address": to}}], "ccRecipients": [],
            "receivedDateTime": iso(t), "isRead": read, "flag": {"flagStatus": "notFlagged"},
            "importance": "normal", "hasAttachments": att, "categories": list(cats),
            "bodyPreview": re.sub("<[^>]+>", " ", html)[:120].strip(),
            "inferenceClassification": "focused" if focused else "other",
            "internetMessageId": "<%s@contoso.com>" % mid, "isDraft": False,
            "body": {"contentType": "html", "content": html}, "attachments": []}
    add("m1", "f-inbox", ("Ahmed Al Rawahi", "ahmed@contoso.com"), "Meeting about the Photo app",
        "<p>Tuesday at 2 is good for me. Should I bring the test images?</p>", NOW - 3600, "c1")
    add("m2", "f-sent", ("Sultan Al Isaiee", "sultan@contoso.com"), "Re: Meeting about the Photo app",
        "<p>Yes please, the RAW ones too.</p>", NOW - 3000, "c1", read=True, to="ahmed@contoso.com")
    add("m3", "f-inbox", ("Retro Weekly", "news@retroweekly.example"), "Retro Weekly: three new toolkits",
        NEWSLETTER, NOW - 7200, "c3", cats=["Retro"], att=True, focused=False)
    g["messages"]["m3"]["attachments"] = [
        {"@odata.type": "#microsoft.graph.fileAttachment", "id": "a1", "name": "logo.png",
         "contentType": "image/png", "size": len(PIXEL), "isInline": True, "contentId": "logo1",
         "contentBytes": base64.b64encode(PIXEL).decode()}]
    add("m4", "f-inbox", ("Muna Al Balushi", "muna@contoso.com"), "Invoice 1047 -- please check",
        "<p>The VAT line is counted twice.</p>", NOW - 86400 - 500, "c4", cats=["Finance"], att=True)
    g["messages"]["m4"]["attachments"] = [
        {"@odata.type": "#microsoft.graph.fileAttachment", "id": "a2", "name": "invoice-1047.pdf",
         "contentType": "application/pdf", "size": 9, "isInline": False,
         "contentBytes": base64.b64encode(b"%PDF-1.4\n").decode()}]
    add("m5", "f-inbox", ("Sara Al Kindi", "sara@contoso.com"), "تجربة البريد العربي", ARABIC,
        NOW - 2 * 86400, "c5")
    add("m6", "f-proj-retro", ("GitHub", "noreply@github.com"), "[retro] CI passed",
        "<p>All jobs passed.</p>", NOW - 3 * 86400, "c6", read=True)
    g["events"] = [{"id": "e1", "subject": "Photo app with Ahmed", "isAllDay": False,
                    "location": {"displayName": "Room 2"},
                    "start": {"dateTime": iso(NOW + 3600)[:-1]}, "end": {"dateTime": iso(NOW + 7200)[:-1]}}]

    gm = {"email": "foxoman@gmail.example", "history": 1000, "labels": [
        {"id": "INBOX", "name": "INBOX", "type": "system"}, {"id": "SENT", "name": "SENT", "type": "system"},
        {"id": "TRASH", "name": "TRASH", "type": "system"}, {"id": "SPAM", "name": "SPAM", "type": "system"},
        {"id": "DRAFT", "name": "DRAFT", "type": "system"}, {"id": "STARRED", "name": "STARRED", "type": "system"},
        {"id": "UNREAD", "name": "UNREAD", "type": "system"},
        {"id": "Label_1", "name": "Family", "type": "user", "color": {"backgroundColor": "#a479e2"}}],
        "messages": {}, "historyLog": [], "sent": [], "events": []}
    def gadd(mid, thread, labels, frm, subj, html, t, raw_parts=None, att=None):
        parts = [{"partId": "0", "mimeType": "text/html", "filename": "",
                  "headers": [{"name": "Content-Type", "value": "text/html; charset=utf-8"}],
                  "body": {"size": len(html.encode()), "data": b64u(html.encode())}}]
        if att:
            parts.append(att)
        gm["messages"][mid] = {
            "id": mid, "threadId": thread, "labelIds": labels, "snippet": re.sub("<[^>]+>", " ", html)[:100].strip(),
            "internalDate": str(int(t * 1000)), "sizeEstimate": 2000 + len(html),
            "payload": {"mimeType": "multipart/mixed", "headers": [
                {"name": "From", "value": "%s <%s>" % frm}, {"name": "To", "value": gm["email"]},
                {"name": "Subject", "value": subj}, {"name": "Message-ID", "value": "<%s@mail.gmail.example>" % mid},
                {"name": "Date", "value": time.strftime("%a, %d %b %Y %H:%M:%S +0000", time.gmtime(t))}],
                "parts": parts}}
    gadd("g1", "t1", ["INBOX", "UNREAD", "CATEGORY_PERSONAL"], ("Khalid Al Siyabi", "khalid@example.om"),
         "Photos from the weekend", "<p>Twelve pictures from Jebel Shams.</p>", NOW - 1800,
         att={"partId": "1", "mimeType": "image/jpeg", "filename": "shams.jpg",
              "headers": [{"name": "Content-Disposition", "value": "attachment; filename=shams.jpg"}],
              "body": {"size": 4, "attachmentId": "ga1"}})
    gadd("g2", "t1", ["SENT"], ("Sultan", gm["email"]), "Re: Photos from the weekend",
         "<p>Send them!</p>", NOW - 1700)
    gadd("g3", "t3", ["INBOX", "CATEGORY_PROMOTIONS", "Label_1"], ("Shop", "deals@shop.example"),
         "=?UTF-8?B?2LnYsdi2INiu2KfYtQ==?=", "<p>Big sale</p>", NOW - 5000)
    gm["events"] = [{"id": "ge1", "summary": "Family dinner", "status": "confirmed",
                     "start": {"dateTime": iso(NOW + 86400)}, "end": {"dateTime": iso(NOW + 90000)}}]
    return {"graph": g, "gmail": gm, "codes": {}, "tokens": {}, "log": []}

S = seed()

def gmail_counts():
    pass

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a):
        pass

    def body(self):
        return self._body

    def send(self, code, obj=None, raw=None, ctype="application/json", headers=()):
        data = raw if raw is not None else (b"" if obj is None else json.dumps(obj).encode())
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def authed(self):
        a = self.headers.get("Authorization", "")
        tok = a[7:] if a.startswith("Bearer ") else ""
        info = S["tokens"].get(tok)
        if not info or info["exp"] < time.time():
            self.send(401, {"error": {"code": "InvalidAuthenticationToken", "message": "Access token has expired or is not yet valid."}})
            return None
        return info

    # ---- dispatch ----
    def do_GET(self): self.route("GET")
    def do_POST(self): self.route("POST")
    def do_PATCH(self): self.route("PATCH")
    def do_DELETE(self): self.route("DELETE")
    def do_PUT(self): self.route("PUT")

    def route(self, meth):
        n = int(self.headers.get("Content-Length") or 0)
        self._body = self.rfile.read(n) if n else b""   # (always read: the connection is kept)
        u = urllib.parse.urlsplit(self.path)
        path, q = u.path, urllib.parse.parse_qs(u.query)
        S["log"].append(meth + " " + path)
        try:
            with LOCK:
                if path.startswith("/test/"): return self.test(meth, path, q)
                if path.startswith("/ms/") or path.startswith("/g/"): return self.oauth(meth, path, q)
                if path.startswith("/upload-session/"): return self.upload(meth, path)
                if path.startswith("/v1.0/"): return self.graph(meth, path[5:], q)
                if path.startswith("/batch/gmail/v1"): return self.gbatch()
                if path.startswith("/upload/gmail/v1/users/me/messages/send"): return self.gsend_upload()
                if path.startswith("/gmail/v1/users/me"): return self.gmail(meth, path[18:], q)
                if path.startswith("/calendar/v3/"): return self.gcal(q)
            self.send(404, {"error": {"message": "no such endpoint " + path}})
        except Exception as e:
            import traceback; traceback.print_exc()
            self.send(500, {"error": {"message": str(e)}})

    # ---- test helpers ----
    def test(self, meth, path, q):
        if path == "/test/state":
            g, gm = S["graph"], S["gmail"]
            return self.send(200, {"graph": {"messages": g["messages"], "sent": g["sent"], "categories": g["categories"]},
                                   "gmail": {"messages": gm["messages"], "sent": gm["sent"], "labels": gm["labels"]},
                                   "log": S["log"][-400:]})
        if path == "/test/newmail":
            g = S["graph"]
            g["seq"] += 1
            mid = "m%d" % g["seq"]
            g["messages"][mid] = dict(g["messages"]["m1"], id=mid, subject="Fresh news %d" % g["seq"],
                                      conversationId="c" + mid, isRead=False, receivedDateTime=iso(time.time()),
                                      internetMessageId="<%s@x>" % mid)
            gm = S["gmail"]
            gm["history"] += 1
            gid = "gn%d" % g["seq"]
            gm["messages"][gid] = json.loads(json.dumps(gm["messages"]["g1"]))
            gm["messages"][gid].update(id=gid, threadId="t" + gid, internalDate=str(int(time.time() * 1000)))
            gm["historyLog"].append((gm["history"], "added", gid))
            return self.send(200, {"graph": mid, "gmail": gid})
        if path == "/test/expire":
            for t in S["tokens"].values(): t["exp"] = 0
            return self.send(200, {})
        self.send(404, {})

    # ---- OAuth ----
    def oauth(self, meth, path, q):
        if path.endswith("/authorize") or path == "/g/auth":
            for k in ("client_id", "redirect_uri", "state", "code_challenge", "scope"):
                if k not in q: return self.send(400, raw=("missing " + k).encode(), ctype="text/plain")
            if q.get("code_challenge_method", [""])[0] != "S256":
                return self.send(400, raw=b"S256 only", ctype="text/plain")
            code = "code%d" % len(S["codes"])
            S["codes"][code] = {"challenge": q["code_challenge"][0], "redirect": q["redirect_uri"][0],
                                "client": q["client_id"][0], "google": path == "/g/auth"}
            loc = q["redirect_uri"][0] + ("&" if "?" in q["redirect_uri"][0] else "?") + \
                urllib.parse.urlencode({"code": code, "state": q["state"][0]})
            return self.send(302, raw=b"", headers=[("Location", loc)])
        if path.endswith("/token") or path == "/g/token":
            f = urllib.parse.parse_qs(self.body().decode())
            gt = f.get("grant_type", [""])[0]
            google = path == "/g/token"
            if gt == "authorization_code":
                c = S["codes"].pop(f.get("code", [""])[0], None)
                if not c: return self.send(400, {"error": "invalid_grant", "error_description": "bad code"})
                v = f.get("code_verifier", [""])[0]
                if b64u(hashlib.sha256(v.encode()).digest()) != c["challenge"]:
                    return self.send(400, {"error": "invalid_grant", "error_description": "PKCE verification failed"})
                if f.get("redirect_uri", [""])[0] != c["redirect"]:
                    return self.send(400, {"error": "invalid_grant", "error_description": "redirect_uri mismatch"})
                if google and not f.get("client_secret", [""])[0]:
                    return self.send(400, {"error": "invalid_client", "error_description": "client_secret is missing"})
            elif gt == "refresh_token":
                if not f.get("refresh_token", [""])[0].startswith("rt-"):
                    return self.send(400, {"error": "invalid_grant", "error_description": "AADSTS70008: expired"})
            else:
                return self.send(400, {"error": "unsupported_grant_type"})
            n = len(S["tokens"])
            at = "at-%d-%s" % (n, "g" if google else "m")
            S["tokens"][at] = {"google": google, "exp": time.time() + 3600}
            email = S["gmail"]["email"] if google else S["graph"]["me"]["mail"]
            return self.send(200, {"access_token": at, "refresh_token": "rt-%d" % n, "expires_in": 3600,
                                   "token_type": "Bearer", "scope": f.get("scope", [""])[0],
                                   "id_token": jwt({"email": email, "name": "Sultan Al Isaiee",
                                                    "preferred_username": email})})
        self.send(404, {})

    # ---- Microsoft Graph ----
    def graph(self, meth, path, q):
        if not self.authed(): return
        g = S["graph"]
        base = "http://%s/v1.0" % self.headers.get("Host")
        if path == "/me": return self.send(200, g["me"])
        if path == "/$batch":
            req = json.loads(self.body())
            out = []
            names = {"inbox": "f-inbox", "drafts": "f-drafts", "sentitems": "f-sent", "deleteditems": "f-trash",
                     "archive": "f-archive", "junkemail": "f-junk", "outbox": "f-outbox"}
            for r in req["requests"]:
                n = r["url"].split("/")[-1].split("?")[0]
                if n in names: out.append({"id": r["id"], "status": 200, "body": {"id": names[n]}})
                else: out.append({"id": r["id"], "status": 404, "body": {}})
            return self.send(200, {"responses": out})
        m = re.match(r"^/me/mailFolders(?:/([^/]+)/childFolders)?$", path)
        if m and meth == "GET":
            parent = m.group(1) or "root"
            vals = []
            for f in g["folders"].values():
                if f["parentFolderId"] == parent:
                    f = dict(f)
                    f["unreadItemCount"] = sum(1 for x in g["messages"].values() if x["parentFolderId"] == f["id"] and not x["isRead"])
                    f["totalItemCount"] = sum(1 for x in g["messages"].values() if x["parentFolderId"] == f["id"])
                    vals.append(f)
            return self.send(200, {"value": vals})
        m = re.match(r"^/me/mailFolders/([^/]+)/messages/delta$", path)
        if m:
            fid = m.group(1)
            token = q.get("$deltatoken", [None])[0]
            since = g["deltas"].get(token, {}) if token else None
            items = []
            for x in g["messages"].values():
                ver = x.get("_ver", 0)
                if x["parentFolderId"] == fid:
                    if since is None or ver > since.get(x["id"], -1):
                        items.append({k: v for k, v in x.items() if not k.startswith("_") and k not in ("body", "attachments")})
            if since is not None:
                for mid in since:
                    x = g["messages"].get(mid)
                    if x is None or x["parentFolderId"] != fid:
                        items.append({"id": mid, "@removed": {"reason": "deleted"}})
            # pages of 2 to exercise nextLink
            skip = int(q.get("$skiptoken", ["0"])[0])
            page = items[skip:skip + 2]
            res = {"value": page}
            keep = "&".join("%s=%s" % (k, urllib.parse.quote(v[0])) for k, v in q.items() if k != "$skiptoken")
            if skip + 2 < len(items):
                res["@odata.nextLink"] = "%s/me/mailFolders/%s/messages/delta?%s&$skiptoken=%d" % (base, fid, keep, skip + 2)
            else:
                tok = "d%d" % len(g["deltas"])
                g["deltas"][tok] = {x["id"]: x.get("_ver", 0) for x in g["messages"].values() if x["parentFolderId"] == fid}
                res["@odata.deltaLink"] = "%s/me/mailFolders/%s/messages/delta?$deltatoken=%s" % (base, fid, tok)
            return self.send(200, res)
        m = re.match(r"^/me/messages/([^/]+)(/.*)?$", path)
        if m:
            mid, rest = m.group(1), m.group(2) or ""
            x = g["messages"].get(mid)
            if x is None: return self.send(404, {"error": {"code": "ErrorItemNotFound", "message": "The specified object was not found in the store."}})
            if rest == "" and meth == "GET": return self.send(200, x)
            if rest == "" and meth == "PATCH":
                ch = json.loads(self.body())
                for k, v in ch.items():
                    if k == "body": x["body"] = {"contentType": v.get("contentType", "html").lower(), "content": v["content"]}
                    else: x[k] = v
                x["_ver"] = x.get("_ver", 0) + 1
                return self.send(200, x)
            if rest == "" and meth == "DELETE":
                del g["messages"][mid]
                return self.send(204, raw=b"")
            if rest == "/attachments" and meth == "GET":
                return self.send(200, {"value": [{k: v for k, v in a.items() if k not in ("contentBytes", "contentId")} for a in x["attachments"]]})
            if rest == "/attachments" and meth == "POST":
                a = json.loads(self.body())
                a["id"] = "na%d" % len(x["attachments"])
                a["size"] = len(base64.b64decode(a.get("contentBytes", "")))
                x["attachments"].append(a)
                return self.send(201, a)
            if rest == "/attachments/createUploadSession":
                item = json.loads(self.body())["AttachmentItem"]
                sid = "%s-%d" % (mid, len(x["attachments"]))
                S.setdefault("uploads", {})[sid] = {"msg": mid, "name": item["name"], "size": item["size"], "data": b""}
                return self.send(201, {"uploadUrl": "http://%s/upload-session/%s" % (self.headers.get("Host"), sid)})
            m2 = re.match(r"^/attachments/([^/]+)(/\$value)?$", rest)
            if m2:
                a = next((a for a in x["attachments"] if a["id"] == m2.group(1)), None)
                if not a: return self.send(404, {"error": {"message": "no attachment"}})
                if m2.group(2): return self.send(200, raw=base64.b64decode(a["contentBytes"]), ctype=a["contentType"])
                return self.send(200, a)
            if rest == "/move":
                dest = json.loads(self.body())["destinationId"]
                g["seq"] += 1
                nid = "m%d" % g["seq"]
                y = dict(x, id=nid, parentFolderId=dest)
                y["_ver"] = x.get("_ver", 0) + 1
                del g["messages"][mid]
                g["messages"][nid] = y
                return self.send(201, y)
            if rest in ("/createReply", "/createReplyAll", "/createForward"):
                g["seq"] += 1
                nid = "m%d" % g["seq"]
                d = {"id": nid, "conversationId": x["conversationId"], "subject": ("Fw: " if "Forward" in rest else "Re: ") + x["subject"],
                     "parentFolderId": "f-drafts", "from": {"emailAddress": {"name": "Sultan Al Isaiee", "address": g["me"]["mail"]}},
                     "toRecipients": [] if "Forward" in rest else [x["from"]], "ccRecipients": [], "receivedDateTime": iso(time.time()),
                     "isRead": True, "flag": {"flagStatus": "notFlagged"}, "importance": "normal", "hasAttachments": False,
                     "categories": [], "bodyPreview": "", "inferenceClassification": "focused", "isDraft": True,
                     "internetMessageId": "<%s@x>" % nid, "body": {"contentType": "html", "content": "<p>quoted</p>"},
                     "attachments": [dict(a) for a in x["attachments"]] if "Forward" in rest else [], "_replyOf": mid}
                g["messages"][nid] = d
                return self.send(201, d)
            if rest == "/send":
                x["isDraft"] = False
                x["parentFolderId"] = "f-sent"
                x["_ver"] = x.get("_ver", 0) + 1
                g["sent"].append({k: v for k, v in x.items()})
                return self.send(202, raw=b"")
        if path == "/me/messages" and meth == "POST":
            d = json.loads(self.body())
            g["seq"] += 1
            nid = "m%d" % g["seq"]
            d.update(id=nid, conversationId="c" + nid, parentFolderId="f-drafts", isDraft=True, attachments=[],
                     receivedDateTime=iso(time.time()), isRead=True, flag={"flagStatus": "notFlagged"},
                     **{"from": {"emailAddress": {"name": "Sultan Al Isaiee", "address": g["me"]["mail"]}}})
            g["messages"][nid] = d
            return self.send(201, d)
        if path == "/me/messages" and meth == "GET":
            s = q.get("$search", [""])[0].strip('"').lower()
            vals = [x for x in g["messages"].values() if s in x["subject"].lower() or s in x["body"]["content"].lower()]
            return self.send(200, {"value": [{k: v for k, v in x.items() if not k.startswith("_") and k not in ("body", "attachments")} for x in vals]})
        if path == "/me/outlook/masterCategories":
            if meth == "GET": return self.send(200, {"value": g["categories"]})
            c = json.loads(self.body())
            if any(x["displayName"].lower() == c["displayName"].lower() for x in g["categories"]):
                return self.send(409, {"error": {"message": "exists"}})
            g["categories"].append(c)
            return self.send(201, c)
        if path == "/me/calendarView":
            return self.send(200, {"value": g["events"]})
        self.send(404, {"error": {"code": "BadRequest", "message": "no such Graph path " + path}})

    def upload(self, meth, path):
        sid = path.split("/")[-1]
        u = S["uploads"][sid]
        data = self.body()
        rng = self.headers.get("Content-Range", "")
        m = re.match(r"bytes (\d+)-(\d+)/(\d+)", rng)
        if not m or int(m.group(1)) != len(u["data"]): return self.send(416, {"error": {"message": "bad range " + rng}})
        u["data"] += data
        if len(u["data"]) >= u["size"]:
            x = S["graph"]["messages"][u["msg"]]
            x["attachments"].append({"id": "big%d" % len(x["attachments"]), "name": u["name"], "size": len(u["data"]),
                                     "contentType": "application/octet-stream", "isInline": False,
                                     "contentBytes": base64.b64encode(u["data"]).decode()})
            return self.send(201, {})
        return self.send(200, {"nextExpectedRanges": ["%d-" % len(u["data"])]})

    # ---- Gmail ----
    def gmail(self, meth, path, q):
        if not self.authed(): return
        gm = S["gmail"]
        if path == "/profile": return self.send(200, {"emailAddress": gm["email"], "historyId": str(gm["history"])})
        if path == "/labels" and meth == "GET": return self.send(200, {"labels": gm["labels"]})
        if path == "/labels" and meth == "POST":
            b = json.loads(self.body())
            if "color" in b and b["color"]["backgroundColor"] not in ("#4a86e8", "#16a766", "#cc3a21", "#ffad47", "#a479e2", "#2da2bb"):
                return self.send(400, {"error": {"message": "Label color is not on the allowed palette"}})
            lid = "Label_%d" % (len(gm["labels"]) + 1)
            lab = {"id": lid, "name": b["name"], "type": "user"}
            if "color" in b: lab["color"] = b["color"]
            gm["labels"].append(lab)
            return self.send(200, lab)
        m = re.match(r"^/labels/([^/]+)$", path)
        if m:
            lid = m.group(1)
            ms = [x for x in gm["messages"].values() if lid in x["labelIds"]]
            return self.send(200, {"id": lid, "messagesTotal": len(ms), "messagesUnread": sum(1 for x in ms if "UNREAD" in x["labelIds"])})
        if path == "/messages" and meth == "GET":
            qq = q.get("q", [""])[0]
            ms = sorted(gm["messages"].values(), key=lambda x: -int(x["internalDate"]))
            if qq and not qq.startswith("newer_than"):
                ms = [x for x in ms if qq.lower() in x["snippet"].lower() or qq.lower() in json.dumps(x["payload"]["headers"]).lower()]
            return self.send(200, {"messages": [{"id": x["id"], "threadId": x["threadId"]} for x in ms]})
        if path == "/history":
            start = int(q.get("startHistoryId", ["0"])[0])
            if start < 1000: return self.send(404, {"error": {"code": 404, "message": "Requested entity was not found."}})
            hist = []
            for (hid, kind, mid) in gm["historyLog"]:
                if hid > start:
                    key = {"added": "messagesAdded", "deleted": "messagesDeleted", "labels": "labelsAdded"}[kind]
                    hist.append({"id": str(hid), key: [{"message": {"id": mid}}]})
            return self.send(200, {"history": hist, "historyId": str(gm["history"])})
        m = re.match(r"^/messages/([^/]+)(/.*)?$", path)
        if m:
            mid, rest = m.group(1), m.group(2) or ""
            x = gm["messages"].get(mid)
            if x is None: return self.send(404, {"error": {"code": 404, "message": "Requested entity was not found."}})
            if rest == "": return self.send(200, self.gview(x, q.get("format", ["full"])[0]))
            if rest == "/modify":
                b = json.loads(self.body())
                for l in b.get("addLabelIds", []):
                    if l not in x["labelIds"]: x["labelIds"].append(l)
                x["labelIds"] = [l for l in x["labelIds"] if l not in b.get("removeLabelIds", [])]
                gm["history"] += 1
                gm["historyLog"].append((gm["history"], "labels", mid))
                return self.send(200, {"id": mid, "labelIds": x["labelIds"]})
            if rest in ("/trash", "/untrash"):
                if rest == "/trash":
                    x["labelIds"] = [l for l in x["labelIds"] if l != "INBOX"] + ["TRASH"]
                else:
                    x["labelIds"] = [l for l in x["labelIds"] if l != "TRASH"]
                gm["history"] += 1
                gm["historyLog"].append((gm["history"], "labels", mid))
                return self.send(200, {"id": mid, "labelIds": x["labelIds"]})
            m2 = re.match(r"^/attachments/([^/]+)$", rest)
            if m2: return self.send(200, {"size": 4, "data": b64u(b"\xff\xd8\xff\xd9")})
        self.send(404, {"error": {"code": 404, "message": "no such Gmail path " + path}})

    def gview(self, x, fmt):
        y = json.loads(json.dumps(x))
        if fmt == "metadata":
            y["payload"] = {"mimeType": x["payload"]["mimeType"], "headers": x["payload"]["headers"]}
        return y

    def gbatch(self):
        if not self.authed(): return
        ct = self.headers.get("Content-Type", "")
        b = ct.split("boundary=")[1].strip('"')
        body = self.body().decode()
        out_b = "batch_mock_42"
        out = ""
        for part in body.split("--" + b):
            m = re.search(r"Content-ID: <([^>]+)>.*?\r\n\r\nGET (\S+)", part, re.S)
            if not m: continue
            cid, url = m.group(1), m.group(2)
            u = urllib.parse.urlsplit(url)
            mid = u.path.split("/")[-1]
            fmt = urllib.parse.parse_qs(u.query).get("format", ["full"])[0]
            x = S["gmail"]["messages"].get(mid)
            if x:
                js = json.dumps(self.gview(x, fmt))
                status = "200 OK"
            else:
                js = json.dumps({"error": {"code": 404}})
                status = "404 Not Found"
            out += "--%s\r\nContent-Type: application/http\r\nContent-ID: <response-%s>\r\n\r\nHTTP/1.1 %s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s\r\n" % (out_b, cid, status, js)
        out += "--%s--\r\n" % out_b
        self.send(200, raw=out.encode(), ctype="multipart/mixed; boundary=" + out_b)

    def gsend_upload(self):
        if not self.authed(): return
        ct = self.headers.get("Content-Type", "")
        b = ct.split("boundary=")[1].strip('"')
        body = self.body()
        parts = body.split(b"--" + b.encode())
        meta, raw = {}, b""
        for p in parts:
            if b"application/json" in p[:200]:
                meta = json.loads(p.split(b"\r\n\r\n", 1)[1].strip())
            elif b"message/rfc822" in p[:200]:
                raw = p.split(b"\r\n\r\n", 1)[1]
                if raw.endswith(b"\r\n"): raw = raw[:-2]
        msg = message_from_bytes(raw, policy=policy.default)
        gm = S["gmail"]
        gid = "gs%d" % (len(gm["sent"]) + 1)
        gm["sent"].append({"threadId": meta.get("threadId", ""), "subject": str(msg["subject"]), "to": str(msg["to"]),
                           "in_reply_to": str(msg.get("In-Reply-To", "")), "parts": [p.get_content_type() for p in msg.walk()],
                           "attachments": [p.get_filename() for p in msg.walk() if p.get_filename()]})
        return self.send(200, {"id": gid, "threadId": meta.get("threadId") or gid, "labelIds": ["SENT"]})

    def gcal(self, q):
        if not self.authed(): return
        return self.send(200, {"items": S["gmail"]["events"]})

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = ThreadingHTTPServer(("127.0.0.1", port), H)
    print("mailmock on", port, flush=True)
    srv.serve_forever()
