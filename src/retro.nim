## Retro Nim UI (`retro`) -- a small, fast, dependency-free Windows 3.1
## style UI toolkit for business and desktop apps, one code base for
## Windows (GDI), macOS (Cocoa), Linux and BSD (X11), Android and iOS.
##
## Immediate mode: write the UI as plain code that runs once per frame;
## widgets are procs bound to your own variables. `import retro` brings
## everything:
##
## ================  ==========================================================
## Module            What it has
## ================  ==========================================================
## `core`            the frame loop, input, layout (rows, columns, adaptive)
## `widgets`         buttons, check boxes, fields, lists, menus, tabs, dialogs
## `business`        grids (with cell kinds), trees, dates, numbers, forms
## `extras`          switches, chips, cards, banners, settings rows, phone parts
## `morecontrols`    range slider, menu and split buttons, tags, autocomplete, knob, accordion
## `records`         masked fields, record navigator, property and tree grids, wizards
## `desktop`         MDI windows, find and replace, hot keys, the About box
## `toolcustom`      Customize Toolbar: the user picks a tool bar's buttons
## `dock`            docked panels as Photoshop's: tabbed groups, icons, floating palettes
## `charts`          21 kinds of business chart, CSV tables, PNG export
## `planning`        kanban, Gantt, agenda, org chart, KPI tiles
## `report`, `pdf`   reports from Nim or HTML templates; PDF; printing; preview
## `templates`       Mustache-style text templates
## `mapview`         a world map with values, markers and routes
## `view3d`          a 3D view of meshes and models
## `canvas2d`        the HTML5 Canvas 2D API: paths, gradients, text, pictures
## `htmlview`        HTML (a safe subset) and the system's web view
## `markdown`        Markdown views
## `media`           sound, video, animated GIFs
## `native`          any API of the system: C libraries, Java, Objective-C, Win32
## `files`, `docfs`  folders, file jobs, the trash, other apps' documents
## `filewidgets`     file lists, previews, path and drive bars, the folder tree
## `imaging`, `zip`  PNG / JPEG / BMP pictures, zip archives
## `background`      work on worker threads
## `memwatch`        the device's memory; caches that let go when it runs short
## `thumbcache`      thumbnails of slow files kept on disk
## `platform`        settings, places, open / share, the clipboard, storage
## ================  ==========================================================
##
## Imported on their own (`import retro/http`), as they bring a C library
## or a thread of their own:
##
## ================  ==========================================================
## `http`            web requests from any thread: WinHTTP, libcurl, Java
## `oauth`           signing in in the system browser (OAuth 2.0, PKCE)
## `secrets`         tokens kept safe: DPAPI, the keychain, libsecret
## `db`              SQLite (compiled in) with full-text search
## `mime`            mail messages: reading, writing, charsets, addresses
## `richedit`        a rich text editor that reads and writes HTML
## `spell`           spelling (the system's checker, Hunspell) and AutoCorrect
## `mailimport`      mail brought in: Outlook Express (.dbx, .mbx), mbox, .eml
## `notify`          the system's notifications (and the unread count on the icon)
## `bgcheck`         a check the system runs while the app is closed (Android)
## `vault`, `rsa`    encryption with a password, RSA keys
## ================  ==========================================================
##
## .. code-block:: nim
##   import retro
##   var name = "World"
##   app "Hello", 320, 120:
##     row([60, -1]):
##       label "&Name:"
##       edit name
##     if button("&Greet", isDefault = true): echo "Hello, ", name

import retro/[core, widgets, business, extras, markdown, icons, nerdicons,
                pixelicons, platform, files, docfs, imaging, zip, background,
                textfile, filewidgets, charts, memwatch, thumbcache]
export core, widgets, business, extras, markdown, icons, nerdicons, pixelicons,
       platform, files, docfs, imaging, zip, background, textfile, filewidgets, charts,
       memwatch, thumbcache
import retro/[records, desktop, planning, view3d, mapview, htmlview, native, media,
                report, pdf, templates, canvas2d, morecontrols, dock, toolcustom]
export records, desktop, planning, view3d, mapview, htmlview, native, media,
       report, pdf, templates, canvas2d, morecontrols, dock, toolcustom

template app*(title: string; w, h: int; body: untyped) =
  ## Open a window (`w` x `h`; phones use the whole screen) and run `body`
  ## once per frame until it is closed.
  startApp(title, w, h)
  while beginFrame():
    captionBar()
    body
    endFrame()
  stopApp()

template app*(title: string; w, h: int; theme: Theme; body: untyped) =
  ## The same as `app`, drawn in `theme`.
  startApp(title, w, h, theme)
  while beginFrame():
    captionBar()
    body
    endFrame()
  stopApp()
