# Retro Mail

Outlook Express 4 to look at and to use, with what the new Outlook does:
Microsoft 365 (work or school), Outlook.com and Gmail, side by side.

- **Signed in in the browser.** The service's own sign-in page opens in
  your browser (OAuth 2.0 with PKCE, answered on a loopback address).
  Retro Mail never sees a password; it keeps an encrypted sign-in token
  (DPAPI on Windows, the keychain on macOS, libsecret or an encrypted file
  on Linux, the app's private folder on Android).
- **Official APIs only:** Microsoft Graph and the Gmail API (and Google
  Calendar). No IMAP passwords, no screen scraping, nothing built in: each
  account uses an app registration of your own (below).
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

## Your Microsoft app registration

1. Open <https://entra.microsoft.com> (your company's IT may do this for
   you), **App registrations > New registration**.
2. Name it "Retro Mail". Supported accounts: your organisation only, any
   organisation, or also personal Microsoft accounts (for Outlook.com).
3. **Authentication > Add a platform > Mobile and desktop applications**:
   add `http://localhost`. Set **Allow public client flows** to *Yes*.
4. **API permissions > Add > Microsoft Graph > Delegated**: `Mail.ReadWrite`,
   `Mail.Send`, `Calendars.Read`, `MailboxSettings.Read`, `User.Read`,
   `offline_access`. If your organisation requires it, an administrator
   clicks *Grant admin consent* once.
5. Copy the **Application (client) ID** (and, for a single-organisation app,
   the **Directory (tenant) ID**) into the wizard.

## Your Google app

1. Open <https://console.cloud.google.com>, make a project.
2. **APIs & Services > Library**: enable the *Gmail API* and the *Google
   Calendar API*.
3. **OAuth consent screen**: External (or Internal for Workspace), add your
   address as a test user, add the scopes `gmail.modify` and
   `calendar.readonly`.
4. **Credentials > Create credentials > OAuth client ID > Desktop app**.
5. Copy its **client ID** and **client secret** into the wizard (Google
   calls it a secret; for desktop apps it is not one, but it is needed).

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
