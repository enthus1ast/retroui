# Retro Mail

Outlook Express 4 to look at and to use, with what the new Outlook does:
Microsoft 365 (work or school), Outlook.com and Gmail, side by side.

- **Signed in in the browser.** The service's own sign-in page opens in
  your browser (OAuth 2.0 with PKCE, answered on a loopback address).
  Retro Mail never sees a password; it keeps an encrypted sign-in token
  (DPAPI on Windows, the keychain on macOS, libsecret or an encrypted file
  on Linux, the app's private folder on Android).
- **Official APIs only:** Microsoft Graph and the Gmail API (and Google
  Calendar). No IMAP passwords, no screen scraping: one click to add an
  account (below).
- **Offline first.** Mail is kept in a local SQLite file with a full-text
  index: the list opens at once, search answers in milliseconds without the
  network, and changes made offline go out when the network comes back.
- **What the new Outlook does:** threads, Focused and Other, tags (Outlook
  categories, Gmail labels, with their colors), flags, pin, snooze,
  quick replies, the calendar, people, to do, notes, signatures for new
  mail and for replies, send later, attachments of any size.
- **Replies in blue,** as Outlook wrote them (Tools > Options > General
  turns it off).
- **What Outlook Express did:** the start page, the Outlook bar, the folder
  tree with unread counts, the contacts pane, threads with + and - boxes,
  the preview pane with its gray header, "----- Original Message -----",
  the Internet Connection Wizard (as the Add Account Wizard), Tools >
  Options with its tabs.
- **No browser inside.** Mail is drawn by the toolkit's own HTML view
  (tables, styles, hidden preheaders, inline pictures, right to left);
  pictures from the web wait until you ask, so senders cannot see when you
  read their mail.

## Adding an account

File > Add Account (it opens by itself the first time): type your e-mail
address and press Enter. Retro Mail finds where your mail is (Outlook.com,
Hotmail and Gmail by name; a company's domain by its Microsoft 365 tenant or
its mail servers), and your browser opens that service's own sign-in page,
with your address filled in. Sign in, allow Retro Mail, and the window goes
on by itself. That is all.

(An organisation that allows only apps it registered itself: Tools >
Options > Accounts > *Organisation's App* takes its Application ID.)

## For whoever builds it: the app registrations, once

A program signs in to Microsoft and Google as a registered app. Make the two
registrations once, as the developer, and build them in: every user then
signs in with one click. A client ID names the app, not anyone's account,
and is public (every desktop mail program carries one); Google says a
desktop client's "secret" is not kept secret either.

**Microsoft** (<https://entra.microsoft.com>, App registrations > New registration):

1. Name "Retro Mail"; supported accounts: *any organisational directory and
   personal Microsoft accounts*.
2. Authentication > Add a platform > *Mobile and desktop applications*:
   `http://localhost`. *Allow public client flows*: Yes.
3. API permissions > Microsoft Graph > Delegated: `Mail.ReadWrite`,
   `Mail.Send`, `Calendars.Read`, `MailboxSettings.Read`, `User.Read`,
   `offline_access`.
4. Branding: verify the publisher (an organisation's users can then allow
   it themselves where their admins let them; some companies still have an
   administrator approve new apps once).

**Google** (<https://console.cloud.google.com>):

1. A project; enable the *Gmail API* and the *Google Calendar API*.
2. OAuth consent screen: External; scopes `gmail.modify` and
   `calendar.readonly`. Until Google verifies the app, only the test users
   you list (up to 100) can sign in, and they see an "unverified app"
   page; Gmail's scopes need Google's verification (and its yearly security
   review) before anyone at all can.
3. Credentials > Create credentials > OAuth client ID > *Desktop app*.

Then put the three values in `examples/mail/appids.nim`, or give them when
building (GitHub Actions takes them from repository secrets of the same
names):

```sh
RETRO_MAIL_MICROSOFT_ID=... RETRO_MAIL_GOOGLE_ID=... RETRO_MAIL_GOOGLE_SECRET=... nimble mailapk
```

A build without them asks each user for an app registration of their own.

## Using it

| Keys | |
|---|---|
| Ctrl+N | new message |
| Ctrl+R / Ctrl+Shift+R | reply / reply to all |
| Ctrl+F | forward |
| Del / Backspace | delete / archive |
| Insert | flag |
| Ctrl+Q / Ctrl+U | mark read / unread |
| Ctrl+T | tags |
| Ctrl+E | search |
| F5 | send and receive |
| Ctrl+1 ... Ctrl+5 | Mail, Calendar, People, To Do, Notes |

Search understands `from:`, `to:`, `subject:`, `has:attachment`, `tag:`,
`is:unread`, `is:flagged`, `is:pinned`, `in:sent`, `before:2026-01-01`,
`after:` and plain words; *Search the server* goes beyond what is kept.

On a phone each screen comes alone (folders, list, conversation, writing)
and the Outlook bar sits at the bottom; swipe a message right to archive
it, left to delete it (Tools > Options > Swipe changes what they do).

## Building

```sh
nimble mail                 # build and run
nimble mailexe              # Windows, from Linux (MinGW)
nimble mailapk              # Android
nim c -r tests/test_mail.nim   # the engine against tests/mailmock.py
```

Pin, snooze, notes, to-dos and drafts are kept on the device. Calendars
are read-only for now (new events: in Outlook or Google Calendar).

Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net
