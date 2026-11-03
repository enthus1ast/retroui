# Changes

## 0.17.0

- **Retro Mail 1.0** (`examples/mail.nim`, `nimble mail`): Outlook Express 4
  to look at and to use, with what the new Outlook does, for Microsoft 365,
  Outlook.com and Gmail. Signed in in the browser (the services' own pages:
  no password typed here, the tokens kept encrypted); Microsoft Graph and
  the Gmail API only. Adding an account is your address and Enter: Retro
  Mail finds the service (by name, by the domain's Microsoft tenant, by its
  MX records) and the browser opens its sign-in page, done (the app registrations
  are built in: `examples/mail/appids.nim` or CI secrets; `docs/retromail.md`
  says how to make them once). Everything is kept in a local SQLite store: the list opens at
  once, search answers offline in milliseconds (`from:`, `tag:`, `is:`,
  `has:attachment`, `before:`), and changes made offline go out later.
  The start page, the Outlook bar, the folder tree with sub-folders and
  unread counts, the contacts pane, threads with + and - boxes (your
  replies in Sent Items in them), Focused and Other, tags in their colors
  (Outlook categories, Gmail labels), flags, pin, snooze, quick replies,
  rich text writing with signatures for new mail and for replies (a reply
  written in Outlook's blue, as it used to be; Options turns it off), send
  later, attachments of any size (Graph's upload sessions), the calendar,
  people, to do, notes, Tools > Options in OE's tabs, a phone layout where
  a message swipes right to archive and left to delete. Pictures from the
  web wait until asked. `tests/test_mail.nim` runs the engine against
  `tests/mailmock.py`, a stand-in for both sign-ins, Graph and Gmail.
- **New modules** (imported on their own: `import retro/http`):
  - `http`: requests from any thread -- WinHTTP on Windows, libcurl (or the
    curl command) elsewhere, Java's HTTP on Android (PATCH too).
  - `oauth`: OAuth 2.0 in the system browser with PKCE and a loopback
    redirect; Microsoft and Google ready; refresh; the id token's claims.
  - `secrets`: tokens kept safe -- DPAPI, the keychain, libsecret, else an
    encrypted file.
  - `sha2`: SHA-256 and HMAC.
  - `db`: SQLite 3.54 compiled in, with FTS5 and an Arabic-aware folding
    for search; prepared statements kept, transactions that nest.
  - `mime`: mail messages read and written -- multipart, charsets
    (Arabic's windows-1256 and ISO-8859-6 among them), encoded words,
    RFC 2231 file names, addresses, dates.
  - `richedit`: a rich text editor that reads and writes HTML -- bold,
    italic, colors, sizes, lists, quotes, links, undo, the clipboard,
    Arabic paragraphs, a ready tool bar; `base`, the look of what is typed
    on an empty line (a reply's blue).
- **The HTML view reads mail.** `htmlView` / `htmlBlock` have a layout
  engine of their own (`htmldom`, `htmlcss`, `htmllayout`): style sheets
  and inline styles, tables as newsletters nest them, hidden preheaders
  left hidden, quotes as mail clients draw them, right to left,
  pictures through the app (`images`: cid: and the web only when allowed),
  selection and copying, `htmlToText`. No script, no network; a 200 KB
  newsletter lays out in about 15 ms.
- `tools/android/build_dex.sh` writes the dex in groups (a single long
  chain made the compiler crash).

## 0.16.3

- **uirelays is the code of the `uirelays` branch.** That branch is
  nim-lang/uirelays with my commits on top, ready for a pull request, and
  `src/retro/uirelays` holds the same files: nothing in it knows about
  retro any more (the C side's `retro_*` names are `uirelays_*`, the
  activity's `retroCall` is `uirelaysCall`, the Termux place is Retro
  Files' own), and the phone drivers draw rectangles, lines and points
  too, so any uirelays program runs on them. `tools/uirelays.sh` keeps the
  two the same (`push`, `pull`, `diff`); the pull request's text is
  `docs/uirelays-pr.md`.
- **Every app for every system.** One table in `retro.nimble` (Photo,
  Files, Board, the gallery, Notepad, Ledger, Charts, Invoice, Native,
  Hello) drives `nimble apks`, `exes`, `appimages` and `macapps`
  (`tools/macapp.sh`: the .app, its icon and Info.plist, zipped). GitHub
  Actions: **CI** runs the tests, the fuzzers, the Android driver on a fake
  Android and builds every example on Linux, Windows and macOS; **Release**
  makes all the packages, and a GitHub release for a `v...` tag. The
  gallery's APK is 0.16.3, and smaller (LTO, built for size).
- Fixes: the rasterizer skips a line with a NaN or an infinite end (the
  UI fuzzer's charts of NaN wrote outside its buffer); a PSD's color mode
  read without an unsafe conversion; EGL's functions looked up without a
  copy of their name; Photo's scratch files let go of from a destructor
  that cannot raise; the Android mock test and the Photo fuzzer up to
  date (neither ran any more); the README's signing-key folder.

- **Retro Board 1.3.1.** A line drawn from a shape, or onto one, holds on
  to it: a connector (an arrow with no heads, straight, curved or elbow
  from the Arrow panel) that follows the shapes as they move; Alt draws a
  free line. 100% is a page unit to each dot of the screen: half the size
  it was on tablets and phones (and sharp desktop screens), as the zoom box
  says.
- **Retro Board 1.3: the panels as Retro Photo's.** The properties panel
  is now `retro/dock`'s docked panels down the right, in tabs grouped by
  what they are about: Color, Stroke and Fill (how a shape looks); Text,
  Arrow and Shapes (what it is); Arrange, Board and Info (where it goes,
  the pages and the canvas, the memory). Dragged by their tabs into other
  groups or out as floating palettes, folded, collapsed to icons; a menu
  per panel (Reset Panels); View > Panels shows and hides each; Tab hides
  them all; kept as left between runs. On a phone, a strip of icons whose
  panels open beside it. The canvas leaves the panels' clicks to them.
- **Exit Zen and Edit (View mode) work again**: the canvas under the
  button took its press first.
- `Dock.coverRects`: where the dock covers its area (its columns, its
  floating palettes, a collapsed column's group shown) -- for a canvas
  drawn by hand under it. An edge-to-edge `beginMdi` stops above a status
  bar drawn before it.
- **Retro Board 1.2: Excalidraw's options.** A properties panel in
  sections -- stroke, background (a fill color of its own), fill
  (hachure, cross-hatch, zigzag, dots), stroke style, sloppiness
  (architect, artist, cartoonist), edges (sharp, round), arrow type
  (straight, curved, elbow), arrowheads, size, font, text align (and top,
  middle, bottom), opacity, layers, align and distribute, actions
  (duplicate, delete, link, group, lock, next step) and, with nothing
  selected, the canvas's color; it scrolls when taller than the window.
  Links on shapes (a badge opens them), Ctrl+Arrow (or Arrange > Next Step)
  adds a flowchart's next shape with an arrow, Edit > Find (Ctrl+F, F3),
  Arrange > Position and Size, View > Stats (the board, the memory used,
  Free Memory), Zen mode (Alt+Z) and View mode (Alt+R), export in the dark
  colors. The engine (`retro/board`): `fillColor`, `roughness`, `round`,
  `elbow`, `link`, `Board.paper`; `fillLines`, `roundCorners`,
  `elbowPath`, `addConnected`, `findText`, `paperOf`.
- **Shapes stay in their clip when the GPU draws** (`gfxgpu`): a path was
  clipped to the whole screen, not to its clip -- a canvas's shapes were
  drawn over the title bar, the menus and the status bar (and a button's
  hatching out of the button), on phones and tablets.
- **Retro Board 1.1**: six handwriting fonts, a font picker that shows
  each in its own letters (Caveat by default); 12 more shapes (rounded
  rectangle, right triangle, cylinder, document, speech bubble, cross,
  double arrow, chevron, lightning, moon, cube, person); the **Sketch**
  line style (View > Sketch Style for new shapes); the navy 3.1 title bar
  on phones and tablets, a status bar with the memory used, View > Colors
  (every scheme) and Appearance... (kept); File > Exit on every system.
- **Lines no longer vanish when zoomed in on a phone** (`gfxgpu`): a shape
  bigger than the GPU's mask atlas (2048 pixels: a stroke across a phone's
  screen, zoomed in) was drawn as nothing -- the atlas said "too big" in a
  field the caller did not look at. It is now drawn with a texture of its
  own, what came before it drawn first.
- **Memory** (`retro/board`): pictures are kept once per board
  (`assets`, `addAsset`, `assetOf`; files keep them once too, older ones
  are read) -- a 3 MB photo moved 60 times took 354 MB, now 3 MB; the
  steps to undo keep at most `undoBudget` bytes (16 MB), the drawings
  `drawingBudget`; Retro Board lets them go when memory is short.
- `addFontData(family, style, data, packed)` (`retro/textengine`): a font
  the program carries, offered by name and read when first drawn.
- `fontSpans`: text set in a board font, letters it lacks in another.

- **Retro Board 1.0** (`examples/retroboard.nim`, `nimble board`,
  `nimble boardapk`): a whiteboard in the manner of tldraw. Tools: select,
  hand, draw (pen pressure), highlighter, eraser, laser pointer, 19
  shapes, arrow, line, text, sticky note, frame, picture. A style panel
  (twelve colors, opacity, fill, dash, size, font, alignment, arrowheads,
  smooth lines), pages, zoom; move, size, turn, snap, group, lock, align,
  distribute, flip, order, copy and paste, undo and redo; double click (or
  tap) to type in a shape; pinch and two-finger pan on phones, a long
  press for the menu; tldraw's keyboard shortcuts; a dark mode; saved as
  you go; `.board` files; PNG, SVG and PDF export, shared from a phone.
- **`retro/board`**, the whiteboard's document: pages of shapes, styles,
  bound arrows, undo and redo of changes (`change`, `begin` / `commit` /
  `cancelChange`), hit-testing, snapping guides, groups, clipboard,
  align / distribute / flip, the drawing of each shape as outlines (kept
  till it changes), `.board` JSON, `renderBitmap`, `toSvg`, `toPdf`.
- **`retro/freehand`**: the outline of a stroke drawn with a pen, a finger
  or the mouse -- thinner where it went fast or was pressed lightly,
  streamlined, tapered and capped -- as one polygon.
- **Two-finger gestures** on Android: a pinch and a two-finger drag come as
  `GestureEvent`s (`scale`, `dx`, `dy`, `phase`) and to apps as
  `ui.pinch`, `ui.pinchX` / `pinchY`, `ui.panDX` / `panDY` and
  `ui.gesturing`; the first finger's press is let go far away when the
  second comes down (nothing is clicked).
- `fillContours(contours, color, ox, oy, k)`: several outlines filled as
  one shape, panned and zoomed (a drawing kept in its own units).
- **Paths drawn in part are drawn right** (`gfx`, `raster`): when only
  some of the screen changed, a path crossing the edge of a part was
  drawn with its corners moved onto that edge (a wrong slant near it), a
  1-pixel gap at the part's right side, and -- a line ending on the left
  side a hair past it -- a faint tint across the rest of the row. Its
  edges are now cut where they cross (`Raster.edge`, which no longer
  allocates); `Raster.line` keeps a row's area whatever the rounding.

## 0.16.2

- **uirelays brought up to date** (upstream `f885a4f`, merged with retro's
  own changes): the `renderText` font relay -- a run of the platform's text
  as pixels -- in every driver, retro's Android one too; Windows opens a
  font file by the face it holds (a bold file no longer opens regular);
  fonts need no window; native font resources are released.
- **The platform's text drawn in its place**: text in scripts the built-in
  fonts lack (CJK, and others) is now made into pixels by the driver
  (`renderText`) and blended into the frame among the rest of the drawing
  -- before, the system drew it over the finished frame, so it showed
  through a menu or dialog opened over it; and with the GPU it is drawn at
  all (it was left out). Kept per text and size; a driver without
  `renderText` draws it as before.
- **The control gallery up to date**, and built for every system:
  `nimble galleryexe` (Windows), `galleryappimage` (Linux), `galleryapk`
  (now versioned). Its Windows page has docked panels (tabs, groups, a
  column of icons, the side panel sized from its edge), a window kept on
  top and size grips; its menu bar a Window menu (`mdiWindowMenu`) and
  Insert > Field, a long submenu; its folder tree room inside its frame
  and a menu on a right click.
- **Lines with arrowheads** (`retro/photoshapes`): a shape's open lines
  get an end at their start and their end (`ShapeData.startEnd`,
  `endEnd`: `LineEnd` -- an arrow, an open arrow, a stealth arrow, a
  circle, a square, a diamond, a bar; `endW`, `endL` their size), drawn in
  the stroke's color and turned as the line goes (a curve's too), the line
  cut back under an arrowhead; kept in documents, in SVG and EPS as
  outlines (`endsPath`, `trimmedPath`). Retro Photo's Line tool makes such
  a line: it stays a line, its ends dragged with the Move tool.
- **Rows with own-width columns** (`row([-1, 0])`): a column of the
  widget's own width now takes its room from the shared ones (as wide as
  last frame) -- the shared column took all of it and pushed the rest out
  of the row (Retro Photo's Libraries panel: its New... button cut off).
- **The ink tables made once, by one thread** (`retro/photoinks`): a CMYK
  or grayscale picture separated on all the cores asked for them at once
  -- each thread made them over the others' and freed tables still being
  read (a crash now and then saving a CMYK TIFF; AddressSanitizer found it).
- `Doc.stepsMade` counts the steps made (an operation's own: those since it
  began -- Retro Photo's Esc takes them back); `Layer.box`, `boxVer` keep a
  layer's measured box on the layer (a cache by its address gave a new
  layer a deleted one's).
- **Windows kept on top** (`MdiWindow.pinned`): a pin in a document
  window's title bar (latched in while on), "Always on Top" in its control
  menu and in `mdiWindowMenu`; a pinned window stays over the other
  documents (the palettes still over it), and clicking one under it makes
  that one the active window without hiding the pinned one.
- **The whole side panel sized from its edge** (`retro/dock`): a split bar
  between the documents and the dock -- dragged, the first open column
  widens or narrows (up to what leaves the documents room); with every
  column collapsed to icons, dragged out it opens the main one again.
- **The About box's pages scroll inside their tab** (`beginScroll(...,
  framed = false)`: a scroll bar only when the page is taller), the
  buttons and the tabs staying put.
- **Tooltips beside the pointer on Windows**: placed under the cursor by
  its real size (the system's cursor size and the display's scale, new
  `WindowRelays.pointerHeight`), no longer under the arrow itself.
- **Retro Files 3.3**: View > Folders in Windows -- each folder in a
  window of its own, as the 3.1 File Manager had them (Window > New Window,
  Cascade Shift+F5, Tile Shift+F4, Always on Top, the windows' list;
  Ctrl+F6 the next, Ctrl+F4 closes), each with its address bar, search and
  preview -- or in tabs, as before (Folder Options > Folders).
- **Pointers for sizing and moving** (`CursorKind`): `curSizeNWSE`,
  `curSizeNESW` and `curMove` in every driver (X11, Windows, GTK, SDL,
  macOS; the others their nearest).
- **`retro/edgetrace`** (new): the edges of a picture found (as Canny's
  detector: the color channel that changes most, alpha too) and linked
  into ordered lines -- `newEdgeMap`, `chainAt`, `chainPoints`,
  `chainPart`, `chainClosed`, `simplify`; pictures over 6 MP traced on a
  smaller copy (a 4000 x 3000 photo in about 0.3 s).
- **Retro Photo 4.8**:
  - the Move tool as Photoshop's: the transform box's handles take the
    pointer from further away (a side anywhere along it), the one under it
    lights up (filled blue, larger; the outline thicker inside; a curved
    arrow where it turns), the pointer shows what a drag does (slanted
    arrows at the corners, following a turned box; four arrows inside --
    the pointer was always an arrow before); a double-click on type edits
    it in the Type tool, the Move tool back when done; a right click lists
    the layers under the pointer (and Free Transform, Duplicate, Delete,
    Blending Options); Auto-Select by Layer or Group;
  - Smart Guides (View > Show > Smart Guides, Preferences): a move snaps
    to the other layers' edges and middles, the image's and the guides,
    magenta lines where it lines up, the room to the nearest layer on each
    side, how far it has gone; Ctrl held: free;
  - the Selection Brush (in the selection tools: Add or Subtract, its size
    and hardness, the red overlay), the Adjustment Brush (in the brushes:
    Brightness, Contrast, Exposure, Saturation, Vibrance, Warmth, Clarity,
    Dehaze, Black & White, Invert painted as an adjustment layer's mask;
    the amount changes it afterwards) and Content-Aware Tracing (in the
    pens: the edge under the pointer lit up, a click makes it a path,
    Shift+click goes on along an edge; Detail and Detailed / Normal /
    Simplified);
  - Window > Arrange > Always on Top for floating images; the panels'
    side sized by its edge.
  - the tools work on the image only: a press on the gray round it does
    nothing (the Hand and the Zoom anywhere; a box's handles, the crop's,
    a lasso being drawn still take it);
  - several layers picked: Group, Merge (new Layer > Merge Layers) in the
    bar under the image, a right click on the layers or the image; the
    Layers panel's folder button groups them;
  - no other program's names in the menus, dialogs and help ("PSD" for
    the format).
- **Always on Top waits while a window is maximized** (its pin grayed,
  its menu items off); `MdiWindow.gripSize` sizes a window's grip, and a
  window that is not flush gets the grip too.
- `beginTree`, `folderTree`: `padding`, room inside the frame.
- **The menu bar by the keyboard**: F10, or Alt pressed and let go alone
  (a tablet's keyboard has no F10), opens the first menu -- again closes
  it; Left / Right go along the bar even with the pointer resting on a
  menu's title (it took the menu back every frame: only a pointer that
  moves there opens another now); a menu opened by a key after the bar
  was drawn is no longer closed in the same frame (F10 did nothing).
- **Menus taller than the screen go on in columns**, as 3.1's long menus
  did (a tablet's Window menu): the rows wrap at the bottom of the screen
  into columns of about the same height, a line between them. A submenu
  or context menu that would only pass the bottom moves up instead, in
  one column (it wrapped into a strip of short columns along the bottom);
  a submenu opens beside the whole menu -- right of all its columns, else
  left of it -- and is drawn over it (it opened beside its own column,
  over the next one).
  The pointer on its way to an open submenu, over the rows of another
  column, leaves it open; resting on another row closes it after a moment
  (400 ms), as 3.1's menus waited (the submenu closed as soon as the
  pointer crossed a row: one beside a menu in columns could not be reached).
- **Type (and shapes) moved off the image come back**: their box is
  their whole text's, off the image too -- shown round it on the gray, a
  press there picks it and drags it back, Properties gives its X and Y
  (before, the box was cut to the image: all of it off, nothing to grab).
- `gfx.intersects(a, b)`.
- **The pin of a window's title bar works**: the title bar's drag took
  its press (it reached up to the minimize button), so a click on the pin
  moved the window instead.
- **Retro Files 3.3** also: Tabs or Windows from the tool bar, View >
  Folders In and the Window menu (always there on a desktop); each
  folder's window with a size grip (Folder Options: none to large); in a
  narrow window the search is a button, its box under the address bar;
  room inside the folder tree's frame; the folder tree's menu (a right
  click: open in a new tab or window, new folder, paste into it,
  favorites, copy as path, terminal, folder sizes, empty the trash,
  properties).

## 0.16.1

**The memory of the programs no longer only grows** (Retro Files showed
1.8 GB after a while of use).

- **The system's malloc for every program** (the examples' and tests'
  config.nims; `retroapk` adds `-d:useMalloc` to every APK): Nim's own
  allocator keeps every page it ever took -- on each thread, and the
  picture workers decode on three -- and never gives them back, so a
  program that shows many pictures only grew. The toolkit warns at compile
  time without it (`-d:retroNimAlloc` keeps Nim's allocator, quietly).
- **What is let go of goes back to the system** (`memwatch.trimHeap`:
  glibc's malloc_trim, Android's M_PURGE; big blocks -- pictures -- mapped
  on their own so freeing one returns it at once): after the caches let
  go, when the program goes to the background, and when it rests after
  its memory grew.
- **A budget for the program too** (`programBudget`: a tenth of the
  device's memory, 384 MB to 1.5 GB): past it the caches let go even with
  the device far from short.
- **The GPU's textures within a budget** (`gpuTextureBudget`, 160 MB): a
  viewer flicking through photos keeps a few, not one for every photo of
  the last two seconds.
- Pictures over 2 MP shown at less than half their size, and any over 24
  MB decoded, are read a band at a time (`bigPictureBytes`): a 12 MP photo
  in the viewer no longer takes its whole decode first.
- A long session in a folder of 25 big photos a time, six folders round:
  425 MB held with Nim's allocator, 269 MB with malloc alone, 162 MB now
  -- the pictures kept (124 MB) and little more (tests/test_memsoak keeps
  it so).

**Windows**

- A window opens with its inside the size the program asks for (the title
  bar and borders added around it, as on the other systems), grown by the
  display's scale and kept within the desktop: the content no longer
  scrolls in a window too small for it.
- `nimble photoexe` and `nimble filesexe` build Retro Photo and Retro Files
  for Windows from Linux or macOS, with their icons and version
  (`tools/winicon.nim`: a .ico and a VERSIONINFO linked in by windres).
- Smaller programs: `retrokit small` (and the examples' Windows builds)
  link with LTO, stripped -- a window with a photo and a button: 2.6 MB
  before, 1.48 MB now, 1.12 MB with `-d:retroNoW98 -d:retroNoKawkab` (Retro
  Sans and DejaVu Sans Mono standing in for MS W98 UI and Kawkab Mono).

Retro Files 3.2, Retro Photo 4.7.

## 0.16.0

**Retro Photo 4.6**

- **Pictures too big to edit whole** (a gigapixel scan, a 30000-pixel
  map: more than the device's memory allows) are no longer refused: Open
  offers **A Smaller Copy** (all of it, as big as the device allows) or
  **A Part of It...** (picked on a preview, at full size), read a band at
  a time; the copy is a new image, so saving never writes over the big
  file. (`photofiles`: `pictureTooBig`, `largestSize`, `bigPictureSize`,
  `openPictureScaled`, `openPictureRegion`, `PictureTooBigError`.)
- **JPEG XL written lossy too** (Export As > JPEG XL: Lossless off, a
  quality as cjxl's -q, 90 looking the same as the picture): XYB, the
  Squeeze transform and quantization through the MA tree, as `cjxl -m 1`
  -- about a tenth of the lossless size at quality 90, every file read by
  libjxl 0.12 to within one level of our own decoder.
- **Pexels and Unsplash** in the Assets window (photos and backgrounds;
  each with a free key in Assets > Settings): search, the curated or
  popular ones, credits and links as their rules ask (Unsplash told when
  one of its photos is used).

- **Dialogs on tablets and phones:** the controls at the right of Select
  and Mask (and of Layer Style, Export As, the color dialog and others)
  were cut off when the interface was scaled up -- their columns were
  scaled twice. Select and Mask is wider, and on a narrow screen puts its
  settings under the picture.

**Retro Files 3.1**

- Very big pictures no longer take their whole size in memory: their
  thumbnails and the picture viewer read them a band at a time (a
  12000 x 9000 PNG: a few MB instead of 1.1 GB).
- In the Arabic interface a line that mixes Arabic with numbers ("812 MB
  متاحة من 252 GB") reads right to left, in its order; the copy progress,
  the times left, the line counts and Rename's "Title Case" are Arabic too.

**Toolkit**

- `bigpicture`: very big pictures (gigapixel scans, panoramas, maps 30000
  pixels a side) read a band at a time straight from the file (mapped):
  `readScaled` (all of it fitted, averaged: the memory is what is made),
  `readRegion` (a part, 1:1 or at 1/n), `bigPictureInfo`, `fittedSize` --
  PNG (every kind, interlaced too), JPEG (baseline a few rows of blocks at
  a time, restart intervals skipped; progressive keeping only the
  coefficients of the rows wanted, or at 1/8 only the averages; EXIF
  turned), BMP, TGA, TIFF (strips inflated as they go, tiles a row at a
  time); a progress callback, Cancel. `loadPicture` reads big PNG, JPEG
  and BMP files so (`bigPictureBytes`): a 12000 x 9000 PNG shown at 1024
  pixels takes a few MB instead of 1.1 GB, a JPEG 14 MB in a tenth of a
  second. `codec`: `Inflater` (`initInflater`, `inflateRead`: deflate a
  little at a time). `jpeg`: `jpegLayout`, `jpegBands`, `exifTurned`;
  `decodeJpeg` reads from the file's bytes without a copy.
  `imageformats`: `tiffInfo`, `tiffCheck`, `tiffPiece`, `tiffSample`,
  `tiffPixel`, `tgaInfo`, `tgaPixel`, `maxFilePixels`; `decodeTiff` and
  `decodeTga` check the size a header claims against the data first (a
  damaged file cannot ask for gigabytes), and PackBits TIFFs whose last
  strip is short read.
- Fixed: 40 rows of the apps and the kit (`row([dp(80), -1])`) scaled their
  widths twice -- right on a desktop at 100 %, cut off on a tablet. `row`'s
  widths are design pixels (scaled once); `rowPx` takes widths measured on
  the screen.
- `typeset.setRtlInterface` (set by `setUiLanguage`): in a right-to-left
  interface a line that mixes Arabic with Latin and numbers reads right to
  left ("1.0 GB متاحة من 252 GB" in its order); one without Arabic keeps
  its own direction.
- `jxl`: `encodeJxl(b, quality, effort)`, `encodeJxlDistance`,
  `jxlDistance` -- lossy JPEG XL (lossy modular). `assetstore`: Pexels and
  Unsplash (`pexelsKey`, `unsplashKey`, `hasKey`, `AssetItem.pingUrl`);
  `assetfetch`: `withHeaders`, `splitHeaders` -- request headers (an API's
  key) sent with downloads on every system, Android too; `fetch.downloadFile`
  takes `headers`.
- Camera raw thumbnails checked on real files: a Canon CR2 and a Nikon NEF
  give their previews in 6 to 70 ms at thumbnail size; real Canon, Fuji,
  DNG and Panasonic files of exiftool's test set read cleanly.

## 0.15.0

**Retro Photo 4.5**

- **File > New as today's Photoshop, kept simple:** tabs by what the
  document is for -- Recent, Saved, Photo, Print, Social, Web, Mobile, Art &
  Illustration, Film & Video -- with blank presets as cards (A4 to roll-up
  banners, Instagram to YouTube, phones, 4K), the recent files and sizes,
  your own saved presets, and **15 ready-made templates** with their
  pictures: event flyer, employee of the month, certificate, staff notice,
  business card, announcement post, event story, Eid greeting, Facebook
  cover, YouTube thumbnail, photo collage, before and after, title card...
  Their type stays type, their photos go into frames (Layer > Place Into);
  in the Arabic interface their words are Arabic. Preset Details at the
  right: size in pixels, inches, centimeters, millimeters, points or picas,
  orientation, artboards, resolution, color mode, background. Preferences
  > General > Use Legacy "New Document" Interface brings back the 1994
  dialog.
- **Assets** (File > Browse Assets, Window > Assets): free photos,
  illustrations, SVG vectors, icons, textures and backgrounds from
  Openverse, Wikimedia Commons, Iconify (300,000 open-source icons), Poly
  Haven and ambientCG -- and Pixabay with your free key -- by kind and
  category, with a search; Insert puts one straight into the image (a
  photo as a Smart Object, an icon or SVG as vector shape layers in the
  foreground color, a texture as a layer), Open as Document, Download
  (to Pictures/Retro Photo Assets with CREDITS.txt); the credit kept in
  File Info. Through the sources' APIs only, as their terms ask.
- **The Retro Photo Library**, carried in the app (works offline) and
  online (a catalog on GitHub adds to it with no new version): 14 brushes
  (bokeh, sparkle, snowflake, crescent, khatam star, calligraphy nib...),
  14 patterns (Islamic khatam stars, arabesque, Moroccan trellis...), 12
  gradients (gold foil, rose gold, Oman flag...), 6 swatch sets, 10 layer
  styles and the designs; a pattern or gradient comes in as a fill layer,
  a style on the layer, a brush into the Brushes.
- **8 more templates** (23 in all): National Day greeting, Ramadan Kareem,
  We're Hiring, Quote Post, Wi-Fi Card (with its QR code), Thank You Card,
  Restaurant Menu, Welcome Card.
- **New QR Code** (Layer menu): links, text, Wi-Fi, phone, email, contact
  cards -- a vector shape layer, sharp at any size.
- **Retro Photo is a still-image editor again:** the Timeline (frame
  animation), animated GIF/WebP export and video import are taken out of
  the app; an animated GIF, WebP or JPEG XL opens as its first picture.
  The toolkit keeps all of it for other apps (`photoanim`, `gifanim`,
  `media`: frames, tweens, video reading and H.264 writing;
  `photofiles.openAnimations`).
- **Quick Actions** panel: Remove Background, Blur Background, Black &
  White Background (each a layer with its mask, editable), Select Subject,
  Enhance Image, Smooth Skin, Restore Old Photo, Frequency Separation, Crop
  and Straighten Photos, Share.
- **File > Share** (Android's share sheet: WhatsApp, mail...); **Export >
  Layers to Files**; **Automate > Image Processor** (a folder resized,
  converted to JPEG, PNG or WebP, watermarked), **Contact Sheet**, **Crop
  and Straighten Photos** (several photos scanned at once, each cut out and
  made straight).
- **Image > Adjustments > Match Color**, **Select > Focus Area**, **Filter
  > Other > Frequency Separation**, the **Color Themes** panel (analogous,
  triad, complementary... added to the Swatches), **View > Before &
  After** (a line to drag), **Type > Paste Lorem Ipsum**; R picks Rotate
  View, as in Photoshop.
- **Files:** **JPEG XL** (read: lossy, lossless, animated, 16-bit; written
  lossless), **SVG** opened and placed as editable shape layers, Canon
  **CR3** (lossless and C-RAW), HEIC and AVIF on desktops
  through the system's libraries (libheif, libavif, ImageIO, WIC; 10-bit
  kept at 16), AVIF and HEIC written where the system can.
- **The layers composited on the GPU** when that is quicker (the same
  pixels as the CPU's, exactly; it measures and keeps to the faster).
- **A pen's pressure, tilt and rotation on Windows, macOS and Linux (X11,
  GTK 4, SDL 3)**, its eraser end too.
- In the Arabic interface the color field, sliders, curves, gradients,
  the Navigator, Liquify, Lens Correction, Blur Gallery and Vanishing
  Point keep left and right.

- About boxes of every app made with the kit name the developer: Sultan
  Al Isaiee @foxoman, www.foxoman.net, sultan@foxoman.net.
- Help > Report a Problem is the toolkit's box now: add what you were
  doing, then Copy or **Send by Email**. The thumbnails of the Open dialog
  and the Assets window are kept on disk; when the device runs short of
  memory the zoomed-out copies are let go.

**Retro Files 3.0**

- **Thumbnails of almost every picture there is:** camera raw photos (CR3,
  CR2, NEF, ARW, DNG, RAF, ORF, RW2, PEF... -- the camera's own preview,
  turned the right way), Photoshop and Retro Photo documents, SVG, JPEG
  XL, WebP and GIF on every system, TIFF, TGA, EXR and HDR, HEIC and AVIF
  on desktops through the system's libraries.
- **Thumbnails kept on disk** (Folder Options > Work: on, at most 32 MB to
  1 GB, Clear): a folder of photos, videos or documents opens at once the
  second time -- 120 camera JPEGs: 2.7 s the first time, 0.06 s after.
- **Smart memory:** the pictures kept in memory are a share of the
  device's memory (16 to 192 MB, not a fixed 96 MB); when the device runs
  short they are let go, all but those on the screen, and all of them
  when the app goes to the background (a phone ends first the apps that
  keep the most). Tools > Free Memory; the About box says what is used.
- **Arabic interface**, mirrored right to left (Folder Options > Look >
  Language).
- **Tools > Folder Sizes:** what takes the room in a folder, measured in
  the background, largest first; double-click one to go there.
- Edit > **Copy To Folder / Move To Folder**, File > **Send To**
  (compressed folder, a folder, the other pane, Favorites), **Open with
  app**, **Share** on phones, New > **Markdown Document**; Help > What's
  New, **Report a Problem** (a fault no longer closes the app: it is kept
  for the report), Retro Files on the Web.
- Very large folders stay quick: 20,200 items are listed in about 0.1 s
  and every view draws a frame in under a millisecond while scrolling
  (tests/test_filespeed); thousands of random taps, drags and keys run
  without a fault (tests/test_filesapp).

**Toolkit**

- `memwatch`: `deviceMemory`, `freeMemory`, `programMemory`,
  `memoryNumbers`, `cacheBudget`, `memoryPressure`, `onMemoryPressure`,
  `releaseMemory`, `memoryReport` (Linux and Android from /proc, Windows
  from GlobalMemoryStatusEx and the working set, macOS and iOS from
  sysctl). The shared picture cache (`pictures()`) follows it:
  `newPictureCache()` sizes itself from the device's memory,
  `PictureCache.release`.
- `thumbcache`: `useThumbCache`, `thumbCacheFolder`, `cachedThumb`,
  `keepThumb`, `worthKeeping`, `thumbCacheBytes`, `clearThumbCache` --
  `background` keeps the thumbnails of slow files there by itself, on its
  worker threads, trimmed to the limit (least recently used first).
- `morepictures`: `addMorePictures` -- thumbnails and previews for camera
  raw files (their embedded previews), PSD/PSB, RPD, SVG, JPEG XL, TIFF,
  TGA, EXR, HDR everywhere; GIF, WebP, HEIC, AVIF on desktops.
- `desktop`: `reportProblem`, `problemBox` (the faults of the last run
  told at the next start; Copy, Send by Email); the About box's facts say
  how much memory is used and free.
- Fixed: the worker threads that decode thumbnails (`background`) shared
  the drawing thread's pool of cores, which could crash when several big
  pictures were decoded at once; each worker now decodes by itself.
  `decodeWithSystem` uses a file of its own per thread.
- **Another language goes further:** a label is looked up whole before it
  wraps (`label(name, literal = true)` shows a file's name as it is), and
  grid column titles, toasts, banners, empty and busy states, status bars,
  setting details, headings, search placeholders, combo lists, palette
  tabs, fact labels, the drive bar's and the tree's places, kinds of file
  ("صورة PNG"), counts, sizes, job summaries and the undo label are
  translated; the toolkit's Arabic table grew.

- `assetstore` / `assetfetch`: open asset sources (Openverse, Wikimedia
  Commons, Pixabay, Iconify, Poly Haven, ambientCG, a library catalog),
  their categories, queries and answers, a pool of download threads with
  a cache (Android through `RetroNet.java`). `svgimport`: SVG read
  (paths, shapes, transforms, gradients, clips, masks, CSS classes, use,
  markers), as shape layers (`placeSvg`) or drawn (`rasterizeSvg`). `jxl`:
  JPEG XL decoder and lossless encoder, pure Nim. `qrcode`: QR codes
  (versions 1-40, every level, as a bitmap or as outlines). `media`:
  `videoFrameAt`, `videoInfo`, `beginVideo` / `addFrame` / `finish` (H.264
  MP4: Android's MediaCodec, ffmpeg on desktops).
- `core`: `RetroDeveloper`, `RetroCredit`, `RetroWebsite`, `RetroEmail`.
- `phototemplates`: `docPresets`, `DocPreset.sizeLabel`, `docTemplates`,
  `templatesOf`, `buildTemplate`, `templateThumb`.
- `photoquick`: `blurBackground`, `bwBackground`, `frequencySeparation`,
  `focusArea`, `findPhotos`, `cutPhoto`, `colorTheme`, `featherMask`.
- `photogpu`: `enableGpuComposite`, `gpuComposite`, `gpuCompositeSupport`,
  `releaseGpuComposite`; `photo.gpuCompositeHook`.
- `cr3` (CRX codec), `rawformats` reads CR3; `systemimage`:
  `decodeWithSystem(path, hi)`, `encodeWithSystem`, `systemEncodeExts`.
- Pen events on the desktop drivers (`drivers/penaxes`).

## 0.14.0

**Retro Photo 4.4**

- **16 bits a channel, kept through the work:** blurs, sharpening, High
  Pass, Levels, Curves and every adjustment made of tables, gradients,
  Image Size, Canvas Size, Crop, Flip and Rotate work on the 16-bit
  numbers; the layers are composited at 16 bits (masks, opacity and fill,
  blend modes, clipping, adjustment layers). A tool that paints at 8 bits
  changes only the pixels it touched. 32-bit light is kept the same way.
- **CMYK by its ICC profile:** Color Settings > Load CMYK Profile (any
  printer's .icc), rendering intent and black point compensation; used for
  CMYK and Proof Colors and named as the PDF/X output intent.
- **OpenType:** text shaped by the font's own tables (GSUB and GPOS:
  ligatures, Arabic joining and its marks placed, kerning), the Amiri
  naskh font built in; **variable fonts** (weight, width, slant... and the
  named instances); an **OpenType panel** (the font's features on and off,
  its axes); **Character and Paragraph Styles** panels (define, apply,
  redefine, overrides shown with a +).
- **PSD:** type layers saved editable (Photoshop opens them as type);
  Smart Objects saved and read as smart objects (their file inside);
  **layered TIFF** read and written.
- **Formats:** WebP (lossy, lossless, animated; read and written), OpenEXR
  (half or float, read and written), camera raw files NEF, ARW, CR2, ORF,
  RW2, PEF and RAF, HEIC and AVIF opened (by Android itself; on a desktop
  by a converter installed there), Export > SVG (shapes and paths as
  vectors, the rest as a picture).
- **Timeline:** frame animation as Photoshop's -- frames, their delays,
  Play, loop, Make Frames From Layers, Tween, Flatten Frames Into Layers;
  animated GIF and WebP opened as frames and saved; Place Video Frames to
  Layers.
- **Rotate View** (in the Hand tool's group; Esc or Reset View) and the
  **Art History Brush** (10 styles).
- **Scripts:** File > Scripts -- a script editor, scripts run from files,
  in Retro Script (reads like JavaScript: `app`, `doc`, `layer`; safe: no
  files, no network).
- **A pen's pressure, tilt and rotation** (Android and iPad): Brush
  Settings > Pen Tilt and Rotation; the eraser end erases.
- **Liquify:** Smooth, Push Left, Freeze and Thaw Mask, pressure. **Filter
  > Vanishing Point:** a plane in perspective, Paste onto it, Stamp along
  it. **Select and Mask:** Color Aware edges.
- **The GPU for filters:** Gaussian Blur and the adjustments made of
  tables run on the GPU on big pictures (the CPU when there is none).
- **العربية:** the whole interface in Arabic, right to left
  (Preferences > Interface > Language); the picture is not mirrored.

**Toolkit**

- `photodeep` (16-bit composite, filters, gradients), `photo`: `hi`
  tracking (`syncHi`, `setHi`, `hiPixels`, `flattened16`), character and
  paragraph styles, `AnimFrame`; `photofx`: `HiWay`, `withHi`, `DeepImg`.
- `otshape` (OpenType shaping), `ttf`: variable axes and instances;
  `textengine`: `features`, `variation`, style names.
- `icclut`, `photoinks`: `setInkProfile`; `webp`, `exr`, `gifanim`,
  `rawformats`, `systemimage`, `photosvg`, `photoanim`, `photovp`,
  `rscript`; `psd`: TySh, smart objects; `media`: `videoFrames`.
- `core`: `ui.rtl`, `setUiLanguage`, `tr`, `beginKeepSides`; `gfx`:
  mirrored drawing; `lang_ar`; pen pressure, tilt, azimuth and twist in
  events (Android, iOS); `gfxgpu`: `gpuBlur`, `gpuColorTable`.

**Not yet:** layers composited on the GPU (the filters and the display
are), tiles for pictures bigger than memory, Canon CR3 and JPEG XL, video
layers (frames are placed as layers), pen pressure on Windows, macOS and
X11.

## 0.13.0

**Retro Photo 4.3**

- **32 Bits/Channel** (Image > Mode): the light kept as it is, brighter
  than white too -- from Image > Mode, or a Radiance (.hdr) or PFM picture
  opened; View > 32-bit Preview Options shows it at an exposure and gamma;
  HDR Toning (Exposure and Gamma, Highlight Compression, Equalize
  Histogram, Local Adaptation) brings it down to 16 or 8 bits. Kept in
  .rpd; saved as .hdr and .pfm.
- **24-bit output:** Export As names PNG-24 (24-bit color; 32 with its
  transparency; 48-bit from a 16-bit image) beside PNG-8; BMP at 24 bits
  or 32 (its transparency kept -- and read back).
- **PDF for a press:** PDF/X-4 or PDF/X-1a:2003 with its printing
  condition (FOGRA39, FOGRA51, GRACoL2006, SWOP2006, Japan Color 2001),
  crop marks, registration marks, color bars, page information, the bleed
  drawn from the picture's edges, trim and bleed boxes. **Type stays
  text:** its font (only the letters used) goes into the file, so a PDF
  editor finds, copies and edits it later -- Arabic too; outlines when
  asked. The web preset keeps the text and makes the pictures small.
- **Arabic justification by the scribes' rules:** a typed tatweel first,
  then after Seen and Sad (سـ صـ), before a final Heh, Teh Marbuta or Dal,
  after Jeem, Hah, Khah (جـ), after Tah, before a final Alef, Lam, Kaf...;
  never before the "teeth" letters in the middle of a word. The tashkeel
  stays over its letter while the join is drawn out.
- **Text in columns, and flowing on:** a paragraph box in up to 12
  columns with a gutter (Paragraph panel); Type > Flow Into a New Box makes
  a box that shows what does not fit the first (and on, box after box);
  "Overset" says when text is left out.
- **A new splash** with a 3.1 progress bar; **Help > Report a Problem:** a
  fault of the program (a panel that fails, a slip in a frame) no longer
  closes it -- the panel says so, the work stays, and what happened is
  kept for a report (shown at the next start if the program stopped).
- The Channels panel shows Photoshop's keys (Ctrl+2 for all, Ctrl+3, 4,
  5 for each); icons drawn in the theme's text color everywhere (dark
  and OLED themes).

**Toolkit**

- `retro/photohdr`: 32-bit light (`Layer.hdr`), `toHdr`, `setExposure`,
  `toneMap`, `flattenedHdr`, `readHdr`/`writeHdr` (Radiance RGBE, run
  length), `readPfm`/`writePfm`; `encodeBmp32`, `decodeBmp` keeps alpha;
  `ExportFormat` `efHdr`, `efPfm`; `ExportOptions.bmpBits`.
- `pdf`: TrueType fonts embedded as Type 0 / CIDFontType2 with ToUnicode
  (`glyphText`, `textRender`, `canEmbed`), `subsetTtf`; `outputIntent`,
  `pdfx`. `photopdf`: `liveText`, `regMarks`, `colorBars`, `pageInfo`,
  `standard`, `condition`, `profile`.
- `textengine`: kashida ranking by the scribes' rules, marks kept with
  their letter; `TextData.columns`, `gutter`, `clipOverflow`,
  `TextLayout.overflow`, `remainder`. `photo`: `Layer.flowFrom`,
  `effectiveText`, `flowsOn`.
- `core`: `guarded`, `noteFault`, `takeFaults`, `layoutMark` /
  `layoutRestore`, `ui.lastFault`; faults written to the app's data folder
  (`errorMessageWriter`); the dock guards each panel. `gfx`: `drawMark` /
  `drawRestore`. `desktop`: `splashBox`.

## 0.12.0

**Retro Photo 4.2**

- **The Filter Gallery** (Filter > Filter Gallery): Artistic -- Colored
  Pencil, Cutout, Dry Brush, Film Grain, Paint Daubs, Plastic Wrap, Poster
  Edges, Sponge, Watercolor; Brush Strokes -- Accented Edges, Angled
  Strokes, Crosshatch, Ink Outlines, Spatter, Sumi-e; Sketch (in the
  foreground and background colors) -- Bas Relief, Charcoal, Chrome,
  Graphic Pen, Halftone Pattern, Photocopy, Reticulation, Stamp, Torn
  Edges; Texture -- Craquelure, Grain (ten kinds), Mosaic Tiles, Patchwork,
  Stained Glass, Texturizer (canvas, brick, burlap, sandstone). Each with
  its settings and the preview on the image.
- **More of the Filter menu:** Stylize > Oil Paint, Render > Fibers and
  Lighting Effects (spot, point, infinite; a texture's relief), Distort >
  Displace, Sharpen > Smart Sharpen.
- **109 custom shapes in 12 sets** (Shapes, Arrows, Banners & Awards,
  Frames, Nature, Animals, Objects, Symbols, Talk Bubbles, Music,
  Ornaments, Web); the Shapes panel shows a set at a time. **Live Shape**
  in Properties: the shape's W and H, a rectangle's corner radius, Flip
  Horizontal and Vertical, Rotate 90°.
- **New tools:** the Slice and Slice Select tools (with the Crop tool, C:
  boxes over the image, numbered; Slices From Guides; File > Export >
  Slices to Files saves each as a PNG), the Note tool (notes pinned on
  the image) and the Count tool (numbers on what is clicked, Alt+click to
  take one away), with the Eyedropper (I).
- **The toolbar docked down the left edge**, its header the docked panels'
  thin blue strip, its arrows (◂◂ ▸▸) one column or two. The workspace
  fills the window edge to edge: no margin of white round it, the
  pictures' tabs right under the options bar.
- **One look for every tab:** the documents' tabs, the docked panels',
  the palettes' and the dialogs' are drawn by the same code -- the same
  height, gray and labels. The Win 3.1 look stays: the white menu bar,
  the white windows.

**Toolkit**

- `retro/photoartistic`: the 36 filters above, built on Kuwahara filters
  made of box sums, Voronoi cells and value noise, on all the cores.
- `photoshapes`: `CustomShape.category`, `ShapeCategories`, the shapes
  built from polygons, stars, circles and bands (`CustomShapes` is a seq).
- `dock.panelHeader`, `panelHeaderH`, `HeaderSide`: the docked column's
  header for any toolbar; `widgets.paletteTabFace`, `paletteTabH`: one
  palette tab look (dock, `tabStrip`, `beginTabs`, `paletteTabs`);
  `beginMdi(edgeToEdge = true)`; `core.barsBottom`.
- Pixel icons: Slice, Note, Count.

## 0.11.0

**Retro Photo 4.1**

- **Documents as tabs, filling the workspace:** pictures open as tabs in
  all the room between the toolbar and the panels, top to bottom, as
  Photoshop's. Windows of their own (MDI, as in 1994: Cascade, Tile) are an
  option: Window > Arrange > Floating Windows (MDI), or Preferences >
  Workspace; Tabbed Documents brings the tabs back.
- **A status bar under each picture**, as today's Photoshop: its zoom
  (typed in it), then what its menu shows (sizes, profile, dimensions,
  the tool, timing).
- **Type:** right-to-left and left-to-right buttons in the options bar and
  the Paragraph panel; **Arabic kashida** (Paragraph > Insert Kashida:
  None, Short, Medium, Long, Stylistic) lengthens justified Arabic lines at
  the places a scribe would, one a word.
- **New tools:** the Magnetic Lasso (sides that cling to edges as you go,
  its Width, Contrast and Frequency), the Triangle shape, the Frame tool
  (K: a box or an ellipse that a picture fills).
- **The selection tools as Photoshop's:** a drag inside the selection
  moves its outline, not the pixels (Ctrl+drag moves the pixels); a click
  inside deselects (the Magic Wand: selects again); the arrow keys move the
  outline; Shift held after the drag began makes a square or a circle, Alt
  draws from the middle; the Polygonal Lasso's sides at 45 degrees with
  Shift; the Magic Wand's Contiguous.
- **More of Photoshop's ways:** the Gradient at 45 degrees with Shift; the
  Paint Bucket's Contiguous and All Layers; the Zoom tool zooms to a box
  dragged; the number keys set the layer's opacity with the tools that do
  not paint, and two typed quickly set that value (4, 5: 45 %); a click
  (no drag) with a shape tool asks its size (Create Rectangle, Ellipse,
  Polygon...: width, height, From Center); the Move tool's Shift+click
  picks another layer to move with the first, Ctrl+click picks with
  Auto-Select off; Alt swaps Dodge and Burn.
- **A new About box:** a banner with the icon, the version, pages for
  What's New and Credits, Copy Info (the version, system and screen, for a
  report).
- **One gray everywhere:** the workspace, the toolbar, the options bar and
  the panels in the same face color, tabs as the docked panels' in every
  dialog; the dock's header in the title bar's blue.
- **Panels docked as today's Photoshop has them** (the toolkit's new
  `retro/dock`): down the right, Color / Swatches / Gradients / Patterns,
  Properties / Adjustments / Libraries and Layers / Channels / Paths open,
  the rest as a strip of icons beside them (a click shows that panel
  beside the strip). Drag the bars between groups to share the height,
  double-click a group's tabs to fold it, the arrows at the top of a
  column collapse it to icons, its left edge sizes it. A panel dragged by
  its tab goes into another group, between groups (a group of its own),
  to the left of the dock (a column of its own) or out over the documents
  (a floating palette, dragged back by its title bar). Each panel's menu
  has Close and Close Tab Group; Window shows a closed panel where it was.
  The workspace (Window > Workspace) keeps it all.
- **The Layers panel as Photoshop's:** a filter (by kind -- pixels,
  adjustments, type, shapes, Smart Objects -- or by name, with its on/off
  switch), the blend mode and Opacity, the four locks (transparent pixels,
  image pixels, position, all) and Fill, and at the bottom Link, Style,
  Mask, Adjustment, Group, New, Delete. Linked layers (and layers picked
  together) move together; a layer whose position is locked does not
  move, one whose pixels are locked is not painted.
- **Adjustment Presets** in the Adjustments panel: 36 looks in six kinds
  (Portraits, Landscapes, Photography, Creative, Black & White,
  Cinematic), each shown on your image; a click puts its adjustment
  layers on in a group. Your own: pick adjustment layers, then the
  panel's menu > Save Adjustment Preset (My Presets); Import and Export
  (.radj); Batch: Apply a Preset to Files.
- **New adjustment layers: Clarity, Dehaze, Grain** (Layer > New
  Adjustment Layer, the Adjustments panel; set in Properties). Clarity and
  Grain look at the pixels around each, so the composite does them
  between the layers under and over them.
- **Layer > Layer Cleanup:** empty layers and groups (and, when asked,
  hidden ones) thrown away; layers still called "Layer 3" named after what
  they hold ("Blue Shape", the words of a type layer, "Gradient Fill").
- **Layer > Harmonize:** a placed object's colors and light made to fit
  the picture, and a shadow cast away from where the light comes from
  (with a darker touch where it stands), on a layer under it.
- **Colorize** (Filter > Neural Filters): click the picture to put colors
  on it; each runs out along what is alike and stops at edges, the
  picture's light kept.
- **Content-Aware Expand:** drag the Crop tool's handles past the image;
  with Fill: Content-Aware the new room is made up from what is near it.
- **The Artboard tool** (with the Move tool, V): drag a box for an
  artboard, drag one by its name to move it with all on it, sizes (A4,
  Phone, Square, HD) in the options bar; File > Export > Artboards to
  Files saves each as a PNG.
- **Dynamic Text** (Paragraph panel): text in a box drawn as big as fills
  the box -- size the box, the text follows.
- **The color picker on the canvas:** Alt+Shift + the right button on the
  image with a painting tool (a long press on a tablet): a square of
  shades and a strip of hues where you press; move to pick.
- **The healing tools as Photoshop's:** the Spot Healing Brush's Type
  (Content-Aware, Create Texture, Proximity Match); the Patch's Source /
  Destination, Transparent and Content-Aware (Structure, Color).
- **Quick Actions** in Properties for what is picked: Remove Background,
  Select Subject, Auto Tone and Color on a picture; Warp, Rasterize on
  type; Select and Mask, Content-Aware Fill, Layer via Copy on a
  selection.
- **A faster engine** (a 12-megapixel image, 8 layers, 2 cores; `tools/benchphoto.nim`):

  | | before | now |
  |---|---:|---:|
  | composite, the whole image | 619 ms | 257 ms |
  | composite, a 400 x 400 part | 9.1 ms | 5.0 ms |
  | brush stroke + composite | 333 ms | 186 ms |
  | Gaussian Blur 10 px | 240 ms | 192 ms |
  | Add Noise | 836 ms | 77 ms |
  | layer style made again | 827 ms | 389 ms |
  | save .rpd | 3470 ms | 1890 ms |
  | open .rpd | 2060 ms | 1070 ms |
  | flattened copy | 631 ms | 282 ms |

  The blend modes that mix each channel alone use a table, and over opaque
  pixels skip the divisions (to the same pixel); Curves, Levels and the
  other adjustments of each channel alone use a table by channel instead of
  the 3-D one; layer styles blur and measure distances along rows (kind to
  the cache) on all the cores; Add Noise is drawn from a table on all the
  cores; .rpd files are packed at the quick level (a little bigger) and
  their layers unpacked at once on all the cores; the resampler's loops are
  laid out for each number of taps.
- **Fixed:** fonts got from Google Fonts were listed but drawn in DejaVu
  Sans: they are now taken from Google's font repository (whole TTFs, the
  plain styles before the variable ones), each file checked before it is
  installed (WOFF/WOFF2, CFF-only and broken files refused; an Arabic family
  must have Arabic letters), and a font that cannot be read says why in the
  Character palette ("Drawn in DejaVu Sans: ...").

**Toolkit**

- `retro/dock`: docked panels (groups of tabs, columns collapsed to icons,
  fly-outs, floating palettes, drag and drop of panels, kept as JSON).
- `retro/photocc`: Layer Cleanup, Harmonize with a shadow, Colorize from
  color hints, Content-Aware Expand, artboards; `photosmart`: Spot Healing
  types, the Patch's options; `photodevelop`: Dehaze; the composite:
  Clarity and Grain layers; `textengine`: Dynamic Text (`fit`,
  `fitScale`); `photowidgets`: the on-canvas color picker
  (`hudPickerRects`, `drawHudPicker`, `hudPick`); `canvasSizeAt`.
- `retro/photopresets`: Adjustment Presets -- 36 built in, put on an image
  as adjustment layers, their look on pixels, files, batches.
- `aboutBox`: a banner (the icon from a PNG or a glyph, name, version,
  tagline, a rainbow), pages of What's New and Credits, Copy Info
  (`aboutInfo`, `systemName`). MDI windows and dialogs default to the
  face gray; `beginTabs` in the palette look fills its page.
- `photo`: `moveSelection`, `shiftedMask` (the outline moved, the pixels
  stay); `photopaint.bucketFill`: `contiguous`, `allLayers`;
  `photowidgets`: `zoomToRect`, a status strip under the view
  (`statusW`, `statusRect`); `textengine`: kashida (`ParaStyle.kashida`),
  `magneticPath` (live-wire edges) in `photocc`.
- The photo engine: Lock Image Pixels, Lock Position and linked layers
  (`lockPixels`, `lockPosition`, `link`, `linkLayers`, `movedLayers`);
  the layer rows show links; MDI palettes can be `bare` (no title or
  frame).

## 0.10.0

**Retro Photo 4.0: the tools as Photoshop has them today**

- **New tools:** the Perspective Crop (four corners dragged onto the
  slanted thing, made straight), the Background Eraser (samples the color
  under its middle, erases it -- Once / Continuous, Contiguous / Discontiguous,
  Protect Foreground; the Background becomes a layer), the Color Replacement
  tool, the Freeform and Curvature pens, the Star and Spiral shapes. The
  Crop tool works as today's: handles pressed and dragged, Enter or the task
  bar commits.
- **The Move tool comes first, picking what you click** (Auto-Select on): the
  thing on the page under the click -- type, a shape, a placed picture, as
  far as its mask shows it, within a few pixels of a thin line (a finger's
  width on a touch screen) -- before a layer as big as the page, and the
  page before a texture laid over all (grain, light); not hidden layers or
  groups. The Layers palette scrolls to the layer picked; the click that
  picks a layer moves it (it does not grab its handles).
- **Smarter selections:** Select Subject and Remove Background know skin
  and go over the subject's edge a second time, finer.
- **Illustrator's path tools** (Layer > Path Operations): Merge Shape
  Components, Offset Path, Outline Stroke, Simplify, Reverse Path Direction,
  Join -- outlines fitted with curves, holes kept as holes.
- **Neural Filters** (Filter > Neural Filters): JPEG Artifacts Removal,
  Photo Restoration, Depth Blur, Color Transfer, Harmonization, Super Zoom,
  in a workspace of their own, output to a new layer or the current one.
- **Save Adobe PDF** with Photoshop's presets -- for the web, for print, for
  a press -- up to 3500 pixels an inch, CMYK, crop marks and bleed, type
  and shapes as outlines (they stay sharp at any size); **File > Automate >
  PDF Presentation** puts several documents in one PDF.
- **Opens PDF and Illustrator (.ai) files**: a page as pixels, or its
  drawing as shape layers (the Import PDF dialog: page, resolution); opens
  and saves **PostScript and EPS** (its picture or its preview).
- **Arabic on the canvas:** the alignment buttons go the way Arabic reads,
  justified Arabic is lengthened at its joins (kashida) before its spaces,
  Arabic-Indic and Persian digits, the arrow keys move the way the text
  runs.
- **Type > Get Google Fonts...** (and "+ Google Fonts" in the Character
  palette): search the catalog, a family downloaded into the app's folder,
  ready at once.
- **Layer Comps** keep positions too and are saved in the document; the
  **Libraries** panel keeps colors, styles and graphics between documents.
- Filters preview **on the canvas** as they are set (Preview).
- **The Open dialog shows the file** (pictures, Retro Photo and Photoshop
  documents, PDFs) and a picture of it while it opens.
- Documents in **windows** again by default (Preferences > Workspace:
  tabs); a new **icon**; Exit and the close box **ask before leaving
  unsaved work**; the open documents **come back** at the next start
  (Preferences: Reopen Documents).
- Retro Photo's documents are **.rpd** (no version in the name; .rp3 files
  still open), with a picture inside for the file lists.
- `examples/magazine.nim`: a three-page magazine made with the engine, tool
  by tool, saved as .rpd and exported as a PDF presentation.
- **Starts eight times faster:** the window is up in under a tenth of a
  second (it took 0.6 s: the printing inks' table, for the Info palette's
  CMYK, is made only when first needed, and then on all the cores).

**Retro Files 2.1**

- **The Columns view** (as Finder and DeskFiles have it): each folder of
  the way a column with its count, a sort button and "so many folders · so
  many files" under it; the picked file's preview in a column of its own.
  Left and Right go up and into folders, Up and Down along a column, typing
  goes to a name; a folder picked with the keys shows what is in it. Details
  / Icons / Columns buttons beside the address.
  More columns than fit scroll sideways, with a scroll bar under them (the
  newest kept in view; Shift + the wheel or a finger too) while the preview
  stays put at the right; a folder just opened has nothing picked yet, as
  in Finder.
- **Viewers for PDF** (the pages one under another, drawn on worker threads
  at the size shown; page box, zoom, as wide as the window), **video** (in
  the window on Linux and Android) and **sound** (a player with the folder's
  sounds as a play list, played on in order); a **slide show** in the
  picture viewer.
- **Pictures of PDFs and videos** in the lists and the preview (the first
  page; a frame of the video, a little way in when it starts black, with a
  play mark).
- **Rename several at once** by a pattern ("Holiday ###", find and replace,
  the letters' case) with the new names shown first; **Edit > Select
  Matching** (Ctrl+Shift+A: *.jpg *.png); **File > Duplicate** (Ctrl+D);
  **Tools > Open Terminal Here** (Ctrl+Alt+T); Rename and Refresh buttons.
- Faster: the column view makes only the rows in view (a folder of 5000
  files scrolls in under a millisecond a frame); the window is up in 25 ms
  (GStreamer is started by the first video picture, on a worker thread).

**Toolkit**

- `fileColumns` and `fvColumns`; `batchNames`, `renameAll` (names that swap
  places too), `selectMatching`, `globMatch`; `FileListEvent.preview`.
- **`retro/pdfview`**: `openPdfView`, `pdfView` (pages drawn on workers at
  the size shown, zoom, page in view), `pdfPage`, `pdfPreview`,
  `addPdfPreviews`. `pageAsync` and `addPageReader` draw pages of documents
  on the worker threads.
- `audioView` (a sound file's player; `videoView(audio = true)`),
  `videoFrame` and `addVideoPreviews`; Android: `media.frame`.
- `openTerminal`, `canOpenTerminal`.
- `nimble photoapk` / `nimble apk`: 4.0 / 11 and 2.1 / 21; `nimble magazine`
  makes the sample magazine.
- `addPictureReader` teaches every picture list, preview and Open dialog a
  kind of file; `windowIcon` (the taskbar's picture), `busyPicture`,
  `filePicker(preview = true)`.
- New modules: `photopdf`, `pdfread` (a PDF reader: xref streams, object
  streams, damaged files, TrueType / CFF / Type 1 / Type 3 fonts, shadings,
  functions), `photoimport`, `photoneural`, `photovector`, `fetch`,
  `googlefonts`.
- Fonts named in a PDF but not in it (the standard 14) are drawn at
  Adobe's widths: the words fill their lines as they should.
- Tooltips sit above the pointer on tablets and phones (Android's mouse
  pointer, big, hid them under it); under its arrow on desktops, as before.
- **Fixes:** a data race when the screen was drawn on several threads with
  big pixel icons (it could crash a window full of file icons); PDF pages
  drawn on several threads at once shared objects (fresh ones each now);
  GStreamer no longer ends the program on a machine without sound (it
  plays silent).

## 0.9.0

**Retro Photo 3.9: today's Photoshop, for its tutorials** (drawn as 1994 drew)

- The menus as Photoshop CC has them -- File, Edit, Image, Layer, Type,
  Select, Filter, Plugins, View, Window, Help -- so a tutorial's paths work as
  written: Image > Adjustments > Curves, Image > Mode, Image > Image Rotation,
  Edit > Free Transform and Edit > Transform (Again, Rotate 180° / 90°, Flip),
  Layer > New, Layer > Layer Mask (Delete, Apply, Disable), Layer > Rasterize,
  Select > Modify, Select > All Layers, Filter > Camera Raw Filter, Filter >
  Convert for Smart Filters, View > Show, View > Screen Mode, Window's panels
  A to Z. The Retro Photo 1994 key set keeps Photoshop 3's menus.
- **Edit > Search** (Ctrl+F): any command, panel or tool by a few letters,
  with where it is in the menus and its keys; Enter does it.
- Today's keys: Ctrl+T Free Transform, Ctrl+Shift+T Transform Again,
  Ctrl+Alt+Z Toggle Last State, Ctrl+Alt+F Last Filter, Ctrl+, Hide Layers,
  Ctrl+Alt+A All Layers, Ctrl+Alt+P Close Others, F12 Revert, F6 Color.
- **Free Transform as since 2019:** a corner keeps the proportions (Shift
  frees them; shapes the other way round), Ctrl moves a corner alone,
  Ctrl+Alt+Shift in perspective, Ctrl+Shift on a side skews. Preferences >
  Tools > Use Legacy Free Transform brings back the old Shift.
- **New panels:** Adjustments (with Properties), Histogram (with the
  Navigator and History; kept up as the image changes, from a sample of a
  million pixels), Gradients and Patterns (with Color and Swatches; eight
  patterns made in the program, those defined and loaded), Styles (fifteen
  layer styles: shadows, bevels, glows, gold, chrome, neon, glass, a 1994
  button; Shift adds; New Style keeps the layer's), Shapes, Tool Presets,
  Layer Comps (visibility and appearance kept by name), Clone Source (five
  sources), Glyphs (with Character and Paragraph; recently used first).
- **The Contextual Task Bar** under the image: the next steps for what is
  there (Select Subject, Remove Background, Select and Mask, Feather,
  Invert, Mask, Fill, Deselect, Warp Text, Commit / Cancel a transform or a
  crop). Window > Contextual Task Bar or Preferences hides it.
- **New tools:** the Ruler (A, L, W, H in the options bar; Straighten Layer
  levels the photo), the Color Sampler (four points an image, their colors
  in the options bar), the Magic Eraser (a color made transparent; the
  Background becomes a layer, as Photoshop does).
- Palette tabs that do not fit share the width, their names shortened
  (the full name as a tooltip).

**Retro Files 2.0: Windows 98 Explorer**

- The Standard Buttons with text labels under the icons (View > Toolbars >
  Text Labels: under, beside, none, text only): Back, Forward, Up, Cut,
  Copy, Paste, Undo, Delete, Properties, Views, New Folder, Folders, Two
  Panes, Preview, Search, Options.
- **View as Web Page:** at the left of the files, the folder's name large
  over a rule in the title color, and the selection described (its kind,
  size, date, a picture's preview, a total for several).
- Explorer 98's menus: File > New (Folder, Text Document), View > Toolbars,
  Status Bar, Explorer Bar (Folders, Preview), As Web Page, Arrange Icons,
  Folder Options; Tools > Find > Files or Folders (F3), Go to Folder
  (Ctrl+G). The Address label (Alt+D), the zone (the place the folder is
  in) in the status bar, Properties of the folder when nothing is selected.
- The **Small icons** view; Ctrl+wheel still steps through the icon sizes.
- Keys: F3 finds (as Explorer; Alt+P the preview pane), Ctrl+G, Ctrl+A.
- **Termux from the side panel:** picking Termux (or another app's folder)
  in the folder tree or the drive bar did nothing; it opens now (and asks
  for access the first time).

**Toolkit**

- **Buttons with a picture and a label, four looks:** `ButtonLook`
  (`blIconOnly`, `blTextOnly`, `blTextBelow`, `blTextBeside`); `button(label,
  pic, look)`, `barButton` for tool bars (the bar's look: `setToolbarLook`,
  a taller bar for text below), `buttonAt` placed by hand; a picture is an
  `Icon` or a glyph of the icon font (`glyphPic`); `labeledSize`,
  `drawLabeled` for your own. Tool buttons fill a taller bar.
- **`retro/morecontrols`:** `rangeSlider` (two thumbs; drag the band to move
  both), `menuButton`, `splitButton`, `tagInput` (chips with ×; Enter or a
  comma adds, Backspace takes the last off), `autocomplete` (a text box
  whose matches drop under it), `knob`, `led`, `accordionHeader`,
  `timeline`, `pill`. In the gallery's More page.
- `fvSmallIcons` for `fileList`; `iconView(oneLine = true)`.
- **Less memory:** where there is no graphics device (no /dev/dri: a
  server, a container, a VM without one), automatic drawing no longer
  starts OpenGL only to find a software renderer: an app takes some 15 MB
  instead of 88 MB. `$RETRO_GPU` now wins over the drawing kept in the
  settings. `nimble apps` strips the binaries (about 14 % smaller).
- `paletteTabs` fit any number of tabs.
- Shortcuts can use the comma and the period ("Ctrl+,").
- `retrokit doctor` knows the NDK is fetched by itself and the signing is
  built in.
- `retroapk`: the compiled pieces go to the user's cache folder
  (`~/.cache/retro/apk`), not beside the source; `--clean` removes them
  after, `--work:DIR` puts them elsewhere.
- `nimble photoapk` / `nimble apk` give the version and its code (3.9 / 10,
  2.0 / 20).

**The repository**

- Every module has a header and every exported routine a doc comment.
- `.github/workflows/ci.yml`: the tests and the fuzzers on Linux, every
  example built on Linux, Windows and macOS, the APKs built and kept.
- `CONTRIBUTING.md`; `.gitignore` keeps out builds, compiled examples and
  tests, and the generated `docs/api`.

## 0.8.1

- **A font from a file:** `setUiFontFile` / `loadUiFontFile` (a .ttf of the
  user's, its bold found beside it) make it every app's font (`ufFile`);
  `appearanceSettings` has "A Font File..." and `storeAppearance` keeps it.
  A pixel font (a bitmap font made outlines, as the Windows 3.1 and 98 ones
  people convert) is found to be one and drawn at whole multiples of its
  pixels, crisp at 100 %, 2x and in between (`pixelGrid`).
- **Kawkab Mono**, the new default font of every app: monospaced Arabic
  and Latin (Abdullah Arif's, with Source Code Pro's Latin; SIL OFL 1.1),
  regular and bold. A light hinter fits its stems to whole pixels and its
  size is set so each letter is a whole number of screen pixels wide, at
  100 %, 2x and in-between scales, so it is crisp everywhere and lines up
  in columns. `ufKawkab`; Retro Sans (`ufRetro`) and DejaVu Sans
  (`ufSmooth`) are still there, in `appearanceSettings` too.
- The panes of `split` (and `sidePane`) scroll when what they hold is
  taller than they are: their own scroll bar, the wheel, a finger, Tab.
- What split panes, scroll panels and MDI windows hold never makes the
  window scroll sideways (`beginClipped` / `endClipped` for your own).
- Grid cells, headers and totals too long for their column end in "...".
- Progress cells of a grid write their figure in two colors, as a 3.1
  gauge does, so it reads over the bar and beside it.
- `iconColumn` takes pixel icons by name ("Sheet", "pxSheet"), as its
  documentation said.
- `factList`: a label too long for its column puts the value under it
  instead of over it.
- `branch` with an icon of its own and an id did not compile when its
  arguments were expressions.
- `panel`: a framed white area with padding that scrolls when what it
  holds is taller (the content area of a business app).
- **Excel files:** `retro/xlsx` reads .xlsx workbooks (shared strings,
  numbers, dates from their styles, both date systems) and writes plain
  ones (`readXlsx`, `writeXlsx`).
- **Sealed files:** `retro/vault` seals data with a password or PIN
  (Monocypher, vendored: Argon2id and XChaCha20-Poly1305): `newVaultKey`,
  `seal`, `unseal`, `isSealed`, `vaultKeyFor`, `wipe`.
- `retro/templates`: `#[tags]#` filled from a table (`fillTags`, with
  filters: `|words`, `|words-ar`, `|long`, `|long-ar`, `|n3`,
  `|ar-digits`, `|upper`...), blanks to ask (`#[?Purpose]#`), and amounts
  in words in English and Arabic (`amountWords`, `numberWords`,
  `arabicNumberWords`; Omani rials and baisa by default).
- Reports: `setBackground` puts a picture (a letterhead) behind every page.
- `editArea` wraps long lines at the words (`wrap = false` for the old
  sideways scrolling); Up, Down, Home and End go by the lines as shown.
  `editAt` takes `wrap` too.
- `focusFirstText()`: the next text box drawn takes the focus (a dialog
  that asks for a PIN can be typed into at once).
- A wrapped paragraph keeps its direction on every line: an English line
  that starts with an Arabic word is still laid out from the left (and
  the other way round). The marks U+200F and U+061C count as right to
  left.
- Charts write every category label when each has some room (shortened
  with "..." when long) instead of every other one.
- Touch: a tap that opens a row of a list (`tapActivates`) leaves nothing
  selected, so the next tap opens again instead of adding to a
  selection; `filePicker` forgets what was selected the last time it was
  open, and starts on the file it was given.
- **Image editing:** `retro/photo` (documents of layers with 16 blend
  modes, a soft selection, alpha channels, Quick Mask, paths, tile-based
  undo of pixels, selections and paths, transforms by four corners
  (`warpedPixels`: scale, skew, perspective, distort, rotate), Apply Image
  and Calculations, .rp3 / PNG / JPEG / BMP files, size limits
  `sizeOk`), `retro/photopaint` (brushes, the painting tools with Erase to
  Saved and the stamp From Snapshot / From Saved, bucket, gradients, lines
  with arrowheads, type, paths filled, stroked and edited point by
  point), `retro/photofx` (over 45 filters with Shear and Extrude, Levels,
  Curves, Color Balance, Hue/Saturation by color range, Selective Color,
  Variations, Color Range, previews; a quick median for any radius) and
  `retro/photowidgets` (the document view with zoom, rulers, marching ants
  and a Quick Mask of any color; the color picker, the curves, levels and
  shear editors, brush, swatch and layer rows). `examples/photo.nim` is
  Retro Photo 3, an image editor of 1994 made with them.
- **Warps:** `retro/photowarp` -- Liquify on a mesh (`LiquifyMesh`:
  `push` for the Forward Warp, `reconstruct`, `twirl`, `pucker` / bloat,
  `reconstructAll`; `liquifyImg` of the whole, a part or a preview), Lens
  Correction (`LensCorrection`: distortion, red/cyan and blue/yellow
  fringes, vignette, vertical and horizontal perspective, angle, scale,
  the edges transparent, extended or of a color; `lensImg`) and
  Straighten (`straighten`: turned and cut to the biggest upright
  rectangle it fills, `innerRect`). Retro Photo has Filter > Liquify...,
  Filter > Lens Correction... and the crop tool's Straighten.
- **Styled type:** `retro/textengine` sets text as an image editor does:
  any TrueType font of the system (`systemFontDirs`, `addFontDir`,
  `scanFonts`, `fontFamilies`, `fontStyles`, `fontFace` with faux bold
  and italic for the styles a family lacks) or the built-in ones; per
  character (`CharStyle`) the font, size, color, tracking, kerning on or
  off, leading, baseline shift, horizontal and vertical scale, faux bold
  and italic, all caps, small caps, superscript, subscript, underline,
  strikethrough; per paragraph (`ParaStyle`) the alignment (left, center,
  right, four justifications), indents, space before and after, the
  direction; point text or text in a box (wrapped at the words);
  right-to-left and joined Arabic; warps (`TextWarp`: Arc, Arc Lower and
  Upper, Arch, Bulge, Shell, Flag, Wave, Fish, Rise, Fisheye, Inflate,
  Squeeze, Twist, horizontal or vertical, with distortions) and text along
  a path. `layoutText` (the caret, `charAt`, `lineMove`, `wordLeft`...),
  `renderText` / `renderTextInto`, the caret and clicks on warped text
  (`caretLine`, `charAtDrawn`, `placePoint`), editing by spans
  (`insertText`, `deleteText`, `restyle`, `styleAt`), `scaled`, `moved`,
  JSON (`toJson`, `textFrom`). `ttf` reads a font's names, weight and
  slant (`family`, `style`, `weight`, `italic`, `faceInfo` without loading
  it), .ttc collections (`fontCount`, `parseFace(data, index)`), the
  underline's place and the outlines (`contours`).
- `retro/textwidgets`: `fontCombo` (each family shown in its own letters),
  `fontStyleCombo`, `fontSample`. `combo` takes `preview` to draw its
  items (`ItemPreview`). Fills and polygons of a see-through color are
  drawn see-through (a selection's highlight over a picture).
- **Type layers and layer styles** (`retro/photo`): `Layer.text` (a type
  layer: `isText`, `addTextLayer`, `setText`, `drawText`,
  `rasterizeText`, `rasterizeAllText`), kept editable through undo
  (`touchLayers`), Image Size (set again, sharp), Crop and Canvas Size,
  duplicated, merged and saved in .rp3. Layer styles (`Layer.fx`,
  `LayerFx`, `Effect`, Fill Opacity `fill`): Drop Shadow, Outer Glow,
  Gradient and Color Overlay, Satin, Inner Glow, Inner Shadow, Stroke
  (outside, inside, centered), Bevel and Emboss (inner, outer, emboss,
  pillow) -- made by `retro/photostyles` (`defaultEffect`,
  `renderFx`, distance fields and blurs on all the cores), kept until the
  layer or the style changes, merged down, scaled by Image Size, saved.
  `layerRows`: a "T" for type layers (`thumbGlyph`) and an "fx" mark
  (`fx`, `fxOff`, `fxClicked`). Pixel icons for the alignments, the
  character switches, Warp Text, type on a path, layer styles, the
  Character and Paragraph palettes.
- Retro Photo: the Type tool of today -- type on the image (a click: a
  line; a box dragged: a paragraph; a click on the work path: along it),
  with the caret, selections, the keys and the clipboard; the Character
  and Paragraph palettes, Warp Text, Layer > Layer Style (every effect,
  copy, paste, hide), Layer > Type, Rasterize, and a new Layer menu. Text
  is still text after a move, an undo, an Image Size; painting or a filter
  on it asks to rasterize it first.
- `pictureBox` (photowidgets): a framed box with a picture fitted in it,
  where the mouse goes (`toPicture`) and whether it is dragged.
- **Layer masks and adjustment layers** (`retro/photo`): a layer's
  `mask` (gray: white shows, black hides; `maskOff`), painted on when
  `editMask` is on (`layer` gives it; `current` the layer itself);
  `addLayerMask` (Reveal All, Hide All, Reveal / Hide Selection),
  `removeLayerMask` (thrown away or applied). Adjustment layers
  (`newAdjustmentLayer`, `setAdjustment`, `Adjustment`) change what is
  under them where their own pixels -- their mask -- let: Levels, Curves,
  Brightness/Contrast, Color Balance, Hue/Saturation, Selective Color,
  Vibrance, Exposure, Photo Filter, Black & White, Channel Mixer,
  Threshold, Posterize, Invert (`adjustmentFn` in `retro/photodevelop`;
  composited through a 33^3 color table). Masks follow Image Size, Canvas
  Size, Crop, Flip, Rotate and Content-Aware Scale (`pixelLayers`), merge
  down with their layer and are kept in .rp3 files. Painting on any mask
  is gray (`Layer.gray`).
- 13 more blend modes: Color Burn, Linear Burn, Darker Color, Color Dodge,
  Linear Dodge (Add), Lighter Color, Vivid Light, Linear Light, Pin Light,
  Hard Mix, Exclusion, Subtract, Divide (`LayerModes` and `PaintModes`
  in their families).
- `touchLayers`: adding, removing, moving layers, masks and adjustment
  layers, and changing their settings, is undone without copying the image.
- `layerRows` shows a layer's mask beside its thumbnail (framed when it is
  painted on, crossed out when off) and an icon (`LayerRow.maskThumb`,
  `maskActive`, `maskOff`, `icon`; `LayerRowsEvent.maskClicked`,
  `thumbClicked`). Pixel icons for adjustment layers and layer masks.
- **Smart tools, on the device:** `retro/photosmart` -- Content-Aware
  Fill (PatchMatch from a small copy up, lines that meet the hole carried
  into it, its colors made to meet the surroundings), healing (`heal`:
  another place's texture with the light and color of where it goes), the
  Spot Healing Brush, the Healing Brush and the Patch (`spotHeal`,
  `healStroke`, `patch`), red eye, Select Subject (what stands out from
  the picture's edges, in focus, near the middle, refined by GrabCut and
  a guided filter) and Select Sky, Content-Aware Scale (seams of least
  detail on a small copy, the subject and skin spared) and enlarging with
  Preserve Details (`enlarge`; Lanczos resampling, `rsLanczos`, in
  `retro/photo`). Also a minimum cut of a graph (`CutGraph`, `maxflow`,
  Boykov-Kolmogorov). Retro Photo has them as tools (J), in Edit (Content-
  Aware Fill, Content-Aware Scale...), Select (Subject, Sky) and Image Size.
- `photopaint`: a stroke tells its document, layer, coverage and stamp
  offset (`strokeDoc`, `strokeLayer`, `coverage`, `stampOffset`).
- **Develop:** `retro/photodevelop` makes a photo's everyday corrections in
  one go, as camera raw programs do: white balance (temperature, tint),
  exposure, contrast, highlights, shadows, whites, blacks, clarity,
  dehaze, vibrance, saturation, noise reduction (of the light, edges
  kept; of the color), sharpening, vignette and grain (`Develop`,
  `developImg`, `develop`), with Auto (`autoDevelop`), presets
  (`developPresets`, `$` / `parseDevelop` to keep your own) and quick
  previews of the whole or of a part 1:1 (`smallCopy`, `developBase`).
  Highlights, shadows and clarity follow the light around each pixel
  (a guided filter: edges kept, no halos). Also Auto Tone, Auto Contrast,
  Auto Color, Shadows/Highlights, Vibrance, Exposure, Photo Filter (20
  filters), Black & White (with a tint), Channel Mixer, and Reduce Noise
  (`detailImg`). Retro Photo has them in Image > Adjust and
  Filter > Develop... (Ctrl+Shift+A).
- **All the cores:** `retro/parallel` shares work out among the
  processor's cores (`parallelFor`, `parallelRows`, `parallelChunks`;
  `threadCount`, `setThreadCount`, $RETRO_THREADS). The image engine uses
  it everywhere: compositing, the filters and adjustments, resampling,
  rotating, the histogram, JPEG decoding, the view. A 24 megapixel photo
  opens, blurs and sharpens in about half a second on two cores.
- The image engine is quicker on one core too: the gaussian blur in whole
  numbers in strips (a big radius through a smaller copy), adjustments of
  a big picture through a 3D colour table, resampling with its weights
  worked out once, filters written back without copies (`writeBack` with
  a `base` for previews made again and again). `mipLevel` keeps smaller
  copies of the image up to date where it changed: a zoomed-out view is
  drawn smoothly from them.
- A JPEG encoder: `encodeJpeg(bitmap, quality)`.
- MDI palettes: an `MdiWindow` with `palette` floats over the documents
  with a thin title bar and is never the active document; `sizable`,
  `flush` (no padding: a canvas); `paletteTabs`, `paletteSize`,
  `mdiIsActive`, `mdiAreaRect`.
- 35 more pixel icons: the tools of an image editor (marquee, lasso,
  magic wand, airbrush, rubber stamp, smudge, dodge, burn, sponge, the pen
  and its arrow, add, delete and convert point) and the mask and screen
  modes.
- `focusFirstText(inDialog = true)`: the first text box of the dialog
  being opened takes the focus, not a box of a palette drawn before it.
- `autoFocus` (true): false keeps the first box of a palette from taking
  the keys when nothing has the focus (a canvas program); dialogs still
  focus their first control.
- An empty `label("")` no longer takes the whole row.
- Palettes scroll when what they hold is taller than they are (a short
  or touch screen); `mdiWindowSize` gives the size a document window needs
  for its content.
- `picturesDir()` (the phone's Pictures with the access to all files, the
  user's Pictures on a desktop) and `askStorage` / `storageDialog`: asks
  for Android's "All files access" once, with the reason, or goes on in
  the app's own folder.
- `filePicker`: several pickers in one program (Open, Save As, Place) no
  longer reset each other; saving puts the focus in the file name.
- **Photoshop documents:** `retro/psd` reads .psd and .psb (8, 16 and 32
  bits; RGB, grayscale, CMYK, Lab, indexed, duotone, bitmap,
  multichannel; RLE and ZIP data, with or without prediction): the
  layers, groups (`lsct` with the group's own blend mode), masks (with
  the "real" mask beside a vector mask), vector masks (`vmsk`, `vsms`:
  the path records and their combinations), shape strokes (`vstk`), fill
  and adjustment layers, effects and other action descriptors (a reader
  and now a writer: `descriptorData`, `psdObj`, `psdRgb`...), the merged
  picture, the resolution and the light's angles. `writePsd` writes them
  back (RGB, grayscale or CMYK; .psb when big) with any extra blocks
  (`PsdLayer.extra`, `vectorMaskData`).
- `retro/photofiles`: any picture in, any picture out. `openPicture`
  (Retro Photo, Photoshop, PNG, JPEG, BMP, GIF, TIFF, Targa), `docOfPsd`
  (groups that pass through give their opacity and masks to their
  layers, others are merged into one; shape layers stay shapes; clipping
  masks, layer styles, Levels, Curves, Hue/Saturation with its ranges,
  Color Balance, Brightness/Contrast, Exposure, Vibrance, Selective
  Color, Channel Mixer, Black & White, Invert, Threshold, Posterize;
  gradient fills with all their stops and the five styles), `psdOf` /
  `savePsd` (shapes as fill layers with vector masks, styles as
  Photoshop's effects, adjustments, clipping, masks), `exportPicture`
  with `ExportOptions` (JPEG quality and 4:2:0, PNG compression, PNG-8
  and GIF with a palette and dither, TIFF compression -- CMYK
  separations for a CMYK image --, Targa RLE, BMP, transparency or a
  matte, scaled). All 316 files of psd-tools' test set open.
- **Shape layers** (`retro/photoshapes`): `rectPath` (rounded),
  `ellipsePath`, `polygonPath` (stars, smooth corners), `linePath` (with
  arrowheads), `svgPath` (SVG path data), 19 `CustomShapes`
  (`customPath`), `combine` with the path operations (`PathOp`: combine,
  subtract, intersect, exclude; `SubPath.op`, `joined`). `ShapeData`: a
  fill and a stroke (`ShapePaint`: none, a color, a gradient through
  `GradientStop`s; inside, centered or outside; caps, miter, round or
  bevel joins; dashes), drawn sharp (`renderShape`, exact coverage in
  bands on every core) after every resize, turn, flip, crop or transform
  (`mapShape`, `quadMap`), kept in .rp3 and undo; `shapeMask` for vector
  masks; `gradientT` lays gradients out as Photoshop does. `Raster`:
  `edge` (outlines past the sides), `accumulate`, `clear`.
- **Clipping masks:** `Layer.clipped` -- a layer shows only where the
  layer under it does (its effects too), composited directly.
- **Printing inks, Lab, duotones:** `retro/photoinks` models how cyan,
  magenta, yellow and black print on paper (Neugebauer's mixing of the
  inks and their overprints, dot gain, black generation, the total ink
  and black limits: `InkSetup`, `setInks`): `inkOf`, `printed`,
  `printedFast`, `proofOf`, `inGamut`, `gamutDistance`; Lab (`labOf`,
  `fromLab`, `labBytes`) and duotones (`DuotoneInk`, `duotoneTable`,
  `defaultDuotone`). `retro/photo` has the CMYK Color, Lab Color and
  Duotone modes (`toCMYK`, `toLab`, `toDuotone`; `channelCount`,
  `channelNames`, `channelGray`, `showChannel`; one channel edited keeps
  the others in its own space), Proof Colors and the gamut warning
  (`Doc.proof`, `gamutWarning`, drawn by the view); `toCmyk` gives the
  printing inks.
- **Brushes:** `BrushDynamics` -- size, angle and roundness jitter, the
  smallest size, scattering (across or both ways), the dabs' count, flow,
  opacity and flow jitter, hue, brightness and foreground/background
  jitter -- and symmetry painting (`SymmetryKind`: vertical, horizontal,
  dual axis, radial and mandala with up to 16 axes; `symmetric`). A
  stroke's own buffers are made in 64-pixel tiles only where it paints
  (a stroke on a 96 megapixel image no longer takes 576 MB).
- **Filter Factory plug-ins:** `retro/filterfactory` runs filters written
  as four formulas in the language of Adobe's Filter Factory (the
  channels, the place, eight sliders, `src`, `rad`, `cnv`, `sin`, `mix`,
  `scl`, `rnd`, `? :`...; `compileFormula`, `compileFilter`, `filterFn`
  on every core) and keeps them as plug-in files (`savePlugin`,
  `loadPlugins`, `builtInPlugins`: twelve to start with).
- Adjustments as Photoshop makes them: Curves through a natural spline,
  each channel's curve or levels before the master's, Hue/Saturation with
  the master's lightness first and the ranges' own limits (`HueRanges`,
  `rangeMask`).
- The busy box comes up sooner (a quarter of a second), names what is
  being done (nested work keeps the outer name, `busyLabels`) and shows
  how far it has got: opening and saving pictures (deflate and inflate
  quicker, PNG with a quick filter choice, JPEG decoded in bands on every
  core), filters, compositing. An image of one plain layer is drawn from
  that layer without a copy (`simpleLayer`, `compPtr`, `compCopy`); with
  `-d:useMalloc` big pictures give their memory back when closed.
- Retro Photo 3.4: File > Open reads Photoshop, TIFF and Targa too;
  Save As keeps layers in .psd; File > Export > Export As... (every
  format with its options, scaled) and Quick Export as PNG / JPEG;
  Layer > Layer from File... (a picture as a new layer above the current
  one; also in the Layers palette's menu); the Shape tools (Rectangle,
  Rounded Rectangle, Ellipse, Polygon, Line, Custom Shape) as shape
  layers, paths or pixels, with fill, stroke and path operations; the
  Move tool, the arrow keys and Free Transform move shapes and type as
  what they are; Layer > Create Clipping Mask (Ctrl+Alt+G); Mode > CMYK
  Color, Lab Color, Duotone..., Printing Inks Setup..., CMYK Preview
  (Ctrl+Alt+Y) and Gamut Warning (Ctrl+Shift+Y), CMYK and Lab channels;
  the color picker warns of colors that cannot print; Smoothing,
  Symmetry and Brush Dynamics... for the brushes; Filter > Plug-ins with
  Filter Factory... and its plug-ins.
- **Retro Photo 3.5**, toward a Photoshop of today in the clothes of 1994:
  - Layers: groups (pass through or mixing their own way, nested,
    collapsed, moved, duplicated and merged whole; clipping to a group);
    Blend If; mask Density and Feather; Lock Layer; Align and Distribute;
    Bring to Front... (Ctrl+] and Ctrl+[); fill layers (Solid Color,
    Gradient, Pattern); Gradient Map and Color Lookup (.cube files and
    built-in looks) as adjustments and adjustment layers.
  - The History palette (states and snapshots, the History Brush paints
    any of them), the Navigator, the Properties palette (the canvas,
    rulers and guides; a layer's place, its mask's density and feather;
    an adjustment's or fill's settings; type and shape; Smart Filters).
  - Actions: recorded, played, steps turned off, stops, kept, saved and
    loaded (.actions); File > Automate > Batch... (an action on a folder of
    pictures, saved where and as asked), Fit Image....
  - An options bar under the menu bar (Window > Options Bar): each tool's
    settings, with sliders that drop down, selection modes, align
    buttons, the gradient's kinds.
  - Guides, the grid and snapping (View); Select and Mask...; the Quick
    Selection and Object Selection tools; the Remove tool and
    Content-Aware Move; the Mixer Brush; textured and dual brushes; a
    gradient editor with midpoints; the Path Selection tool.
  - Smart Objects: Convert to Smart Object, Place... (one), scaled,
    turned and distorted without loss, flipped, Smart Filters (changed,
    hidden or taken off later), Edit Contents (in a window of its own,
    saved back), Replace and Export Contents, New Smart Object via Copy.
  - Warp (a grid, or a style), Puppet Warp (pins: rigid, normal or
    distort), Perspective Warp (a plane laid out, then moved, made upright
    or level); the Blur Gallery (Field, Iris, Tilt-Shift, with Light
    Bokeh); Surface Blur; Skin Smoothing.
  - Photomerge (panoramas: perspective, collage or reposition, blended,
    cropped, the edges filled), Merge to HDR Pro (exposures fused), Load
    Files into Stack, Auto-Align and Auto-Blend Layers (panorama, focus
    stacking), Sky Replacement (painted skies or a picture, its edge and
    light).
  - Color profiles: read from JPEG, PNG, TIFF and Photoshop files,
    converted to sRGB (or kept and shown converted), Assign / Convert to
    Profile, embedded on export. Raw photos: DNG (Camera Raw: white
    balance and exposure on the light itself). Brushes from .abr and .gbr
    files, and saved as .abr.
  - Big images are saved in the background; Edit > Purge > Everything.
- New in the toolkit for it: `retro/photomerge` (corners matched,
  RANSAC, `photomerge`, `exposureFusion`, `focusStackMasks`, Surface Blur,
  Skin Smoothing, skies), `retro/photowarp` (`drawMesh`, Warp,
  `puppetWarp`, `renderSmart`, `variableBlur` and the Blur Gallery's
  radii), `retro/iccprofile`, `retro/rawphoto` (DNG, lossless JPEG,
  demosaicing, `developRaw`), `retro/abr`, `retro/photosave` (saving on
  a thread of its own), `popupSlider`, `filePicker(fmFolder)` (a folder),
  pixel icons for the selection modes and gradient kinds.
- **MS W98 UI**, the new default font of every app: martyr—'s outline
  conversion (2022, after Lev Leontev's 2019 one) of the MS Sans Serif of
  Windows 98, regular and bold, drawn on its pixel grid so it is crisp at
  every scale. **It comes with no licence**: its authors say it is free to
  use, but MS Sans Serif is Microsoft's (see
  `src/retro/fonts/NOTICE-MSW98UI.txt`). Build with `-d:retroNoW98` to
  leave it out; `setUiFont(ufKawkab)`, `ufRetro` or `ufSmooth` for
  another. Arabic and the icon glyphs fall back to the other fonts.
- **Control sizes:** `setControlSizes(csAuto / csDesktop / csTouch)` and
  "Controls" in `appearanceSettings`: on a tablet the desktop sizes by
  default (Automatic: touch sizes on phones only), touch sizes when asked.
- `beginStatusBar` / `statusRow` / `statusSep` / `endStatusBar`: a status
  bar of cells, clipped to itself. `pane`: a plain panel of a height.
- `tabStrip`: tabs torn off (dragged out) and moved (`tornOff`, `moved`).
- MDI: a window docked behind the floating ones (`docked`), the chosen one
  of them, `mdiTitleDragged`.
- **Keymaps** (`retro/desktop`): commands' keys with defaults and the
  user's own over them (`keyFor`, `setKey`, `keymapPressed`,
  `storeKeymap`, `restoreKeymap`, `keymapEditor`).
- `recentFiles` / `addRecentFile` (`retro/platform`).
- `busy`: `lastBusy` and `busyNow`, what the last long command took.
- `retro/adobefiles`: Photoshop's swatches (.aco v1/v2, .ase: read and
  written), curves (.acv) and levels (.alv) (read and written), gradients
  (.grd v5) and patterns (.pat) (read).
- `retro/photobrushes`: brush presets in folders, tips (round, square,
  chalk, bristles, star, leaf, grass, splatter... and sampled), saved as
  JSON, `strokePreview`, `tipPreview`.
- Painting: brushes from 1 to 5000 pixels (tips over 1024 kept at 1024 and
  scaled), the dabs' rows on all cores, tiles made before a stroke, the
  color sampled only when a dynamic needs it. A 6000 x 4000 picture, a
  5000-pixel stroke on 2 cores: a 20-pixel soft brush 51 -> 24 ms, 500
  pixels 838 -> 252 ms, 1000 pixels 1846 -> 512 ms, 5000 pixels 8918 ->
  2814 ms; the memory at its peak 515 -> 336 MB.
- Photoshop files: masks' Density and Feather, a group's fill opacity, the
  merged picture matted on white as Photoshop keeps it, 16 bits a channel
  read and written. Of 316 test files (psd-tools' corpus) all open; drawn
  by our engine, 157 of 280 look the same as Photoshop's merged picture
  (116 before), 46 near, 77 different.
- 16-bit PNG read (`decodePng(data, addr hi)`) and written
  (`encodePng16`); a document's depth (`Doc.depth`, `setDepth`,
  `flattened16`).
- **Retro Photo 3.6**:
  - The window sized with the mouse (and on Android tablets and
    ChromeOS: freeform, 1280 x 800 to start); desktop-sized controls on
    tablets (Preferences > Interface for touch sizes).
  - Documents as tabs (dragged out to float, Window > Arrange >
    Consolidate All to Tabs / Float All in Windows, Ctrl+Tab), the
    status bar of today's Photoshop (the zoom typed in, and its menu:
    document sizes, profile, dimensions, measurement scale, scratch
    sizes, efficiency, timing, the tool, save progress, smart objects,
    layer count).
  - Preferences in pages, as Photoshop has them: General, Interface,
    Workspace, Tools, History & Saving, Performance, Scratch Disks,
    Cursors, Transparency & Gamut, Units & Rulers, Guides, Grid & Slices,
    Type, Color Profiles.
  - Keyboard Shortcuts... (Edit): Photoshop's keys by default, 1994's when
    asked, any changed.
  - Brushes as in Photoshop 2026: presets in folders, each shown as it
    paints; Brush Settings (F5) with the tip shape and the dynamics; 1 to
    5000 pixels; [ and ] (Shift: hardness), , and . the presets; Alt and
    the right button dragged for size and hardness; brush tips of one's
    own from the selection.
  - Presets: Photoshop's swatches, curves, levels, gradients, patterns and
    brushes read (Edit > Presets, and the Curves, Levels and Gradient
    dialogs); swatches, curves and levels saved.
  - Autosave and recovery; File > Open Recent; Window > Workspace (the
    palettes where they were, kept); Image > Mode > 8 / 16 Bits/Channel.
  - Idle: no CPU used, about 21 MB with three pictures open.
- **Drawing on the GPU:** OpenGL ES 2 (or OpenGL 2.1) loaded at run time --
  nothing to link -- through new optional relays (`GpuRelays`: EGL on X11
  and Android, WGL on Windows). Every command becomes rectangles: glyphs
  and shapes from a texture of masks the CPU makes as it always has (the
  text looks the same), icons from a texture of pictures, bitmaps from
  textures of their own (only the rows that changed sent again), the 3.1
  dither and the marching ants worked out by the shader. A self-test at
  the start, a fall back to the CPU when anything fails, and a guard file:
  a crash while starting the GPU means the CPU next time. `setGpuMode`
  (`gmAuto`: a real GPU, not a software one; `gmGpu`; `gmCpu`),
  `drawnWithGpu`, `gpuDescription`, "Drawing" in `appearanceSettings`,
  `RETRO_GPU=0/1`. On the GPU the CPU's framebuffer is let go (33 MB at
  4K). Under Mesa's llvmpipe the GPU's frames are the CPU's to the pixel
  (tests/test_gpu).
- `gpuImage` / `drawGpuImage` / `gpuHasImage`: an app's own picture on the
  GPU, sent while its pixels are there, drawn at any size (the photo
  editor's canvas: zoomed and scrolled by the GPU). `checkerAt`, a
  checkerboard command; `marchingAnts`, a selection's outline as a command
  (no copy of the picture under it).
- **The CPU draws less:** the screen in tiles (256 x 32) -- only those that
  changed drawn and sent; a bitmap changed in part (`changed(b, r)`) only
  there; the tiles drawn on all cores (the texts made ready first on the
  drawing thread); a bitmap drawn 1:1 copied by rows. At 3840 x 2160, the
  photo editor: a whole redraw 18.1 -> 10.2 ms, scrolling 18.4 -> 8.3 ms,
  zooming 26.0 -> 17.1 ms, a 64-pixel dab 18.9 -> 1.3 ms; the cursor over a
  menu sends 16 k pixels instead of 245 k. `parallelFor(keepAlive = false)`
  and `drawingRows` for work that is part of a frame (no events read).
- X11: only what pictures covered is copied to the window, and pictures are
  no longer hashed pixel by pixel.
- **HD and 4K:** MS W98 UI HD (tools/genw98hd.py): the W98 pixels traced
  into smooth outlines, the same advances; text whose pixels would be 1.5x
  or more is drawn from it -- 2x and 4K screens, large text, and a tablet's
  1.5x at exactly its size (not the next multiple of 11). Pixel icons
  magnified 2x, 3x, 4x by Scale2x / Scale3x (smooth diagonals, hard
  edges). Check marks, radio dots and arrows at the screen's resolution
  (`hdDetail`). `setHdText(false)` (or "Pixels" in the settings): the 1998
  look magnified. The OLED Black theme (`Oled`).
- `tabStrip(look = tlPalette)`: document tabs drawn as a palette's.
  Docked MDI windows can be `sizable` (their right and bottom edges, a grip
  at the corner; `userSized`). `scrubLabel` -- Photoshop's scrubby
  sliders: a label dragged sideways changes its number.
- `retro/adobefiles`: color books (.acb: `readAcb`, `writeAcb`,
  `ColorBook`, `builtinBooks` -- the web's colors, CSS's, process tints,
  grays); `retro/photosmart`: `refineHair`, `segment` / `regionAt` /
  `findObject` (an Object Finder), `removeBackground`.
- **Retro Photo 3.7**:
  - The canvas on the GPU when there is one (Preferences > Performance >
    Use Graphics Processor), only the part painted on sent.
  - Document tabs like the palettes'; the documents' panel sized by its
    edges and its grip (Window > Arrange > Fit Documents Panel).
  - Photoshop's held keys (Space the Hand, Ctrl+Space the Zoom, Ctrl the
    Move tool, Alt the Eyedropper), Alt+drag a copy, Alt+[ / Alt+], Stamp
    Visible, Alt/Ctrl+Backspace fills, Reselect, Ctrl+click a thumbnail to
    select its pixels, Alt+click between layers to clip, scrubby labels.
  - The Move tool's transform controls: the current layer's blue box,
    eight handles (Shift: proportions, Alt: from the middle), turning
    outside the corners, Auto-Select with the layer under the mouse
    outlined; type sized stays type, shapes stay sharp; Free Transform
    (Ctrl+T) on a layer's own box; W and H % in the options bar.
  - New in Bitmap, Grayscale, RGB, CMYK and Lab, at 8 or 16 bits; Edit >
    Color Settings; CMYK and Lab numbers in the color picker; Color
    Libraries (the books above, and the user's .acb files -- Pantone's
    included, which cannot come with it).
  - Layer > Layer Mask (Reveal / Hide All or the selection, Gradient
    Mask), Place Into (a picture inside type, a shape or a frame), New
    Frame; the Type Mask tool; paint on a mask in grays.
  - Select > Remove Background, the Object Finder, Refine Hair.
- **Big photos, live:** a change made with the mouse is shown before it
  is done (`LivePart`, `setLive`, `liveChanged`, `endLive`): the view's
  pixels made straight from the layers at their own size
  (`compositeSampled`: groups, masks, clipping, adjustment layers, effects
  -- at 1:1 exactly what putting it down makes), the full-size pixels
  changed once, when it is put down. `moveTo` / `endMove` work this way
  (nothing copied when a layer is lifted), and Free Transform, and an
  adjustment's slider on a big photo. On a 70-megapixel photo (2 cores):
  dragging a layer 440 -> 8 ms a frame, Free Transform's corner 3.3 s ->
  25 ms, Ctrl+T 313 -> 23 ms, the Move tool's press 282 -> 1 ms.
- `touchWhole`: a change of all of a layer hands its old pixels to the
  undo step (no copy; undo and redo swap them); filters on all of a layer,
  moves and transforms use it. `liftForWarp` / `warpOnto` / `vacatedCopy`:
  a transform's pixels taken up once and put down on all the cores (a
  stretch without perspective a row at a time, in fixed point; shrunk
  from a copy halved as often as it shrinks).
- `selBounds` kept while the selection stays (`selVer`) and found on all
  the cores; the marching ants' edges traced row by row on all the cores:
  Select All on 70 megapixels 820 -> 140 ms, its ants 100 -> 0.4 ms a frame.
- The composite: the first layer of a row copied; the zoomed-out copies of
  an opaque photo averaged four channels at a time. Old undo steps' files
  deleted by the scratch disk's writer (`waitScratch`), a step being
  written stopped in pieces. JPEG: a component's pixels no longer copied
  for each scan (a 70-megapixel file opens in 1.75 s instead of 2.45 s).
  The undo history keeps at most 512 MB in memory (the rest on the scratch
  disk).
- **Line icons:** every pixel icon has a twin among the Nerd Fonts symbols
  (`setPixelTwin`, `lineTwins`, tools/genlineicons.py: 176 symbols added to
  the icon font); `setIconStyle(isAuto / isPixel / isLine)` -- by default
  line icons in a dark theme, where the pixel art's black outlines do not
  show, in the text's color (folders, warnings, stars keep their own),
  crisp at any size. "Icons" in `appearanceSettings`; `storeAppearance`
  keeps it. Symbols asked for in black are drawn in the text's color in a
  dark theme. Six new pixel icons (`pxMarqueeRow`, `pxMarqueeColumn`,
  `pxPolyLasso`, `pxTypeMask`, `pxPatternStamp`, `pxMoreTools`).
- **OLED black and Dark:** the tabs behind (palettes', documents',
  notebooks') lifted from the black and labelled in what shows on it
  (`contrastInk`, `lumaOfColor`); `themeIsDark`. `RETRO_THEME` picks a
  theme by name for tests and screenshots.
- MS W98 UI HD (the smooth one: tablets, 4K, large text) as big as the
  other fonts -- its x-height theirs -- and on its own pixel grid only
  where that is within 9 % (it was rounded to the grid at any error: up to
  a fifth smaller on a 2.25x screen).
- **Retro Photo 3.8**:
  - Photoshop's toolbar: one column (two with the arrows; as many as fit
    when left to itself), the tools in Photoshop's groups -- a group shows
    the tool used last, a triangle when it holds more; hold it down,
    right-click or long-press: its tools beside it with their names and
    keys; Alt+click the next one; the letter picks the group, Shift and the
    letter the next tool in it; "..." and Edit > Toolbar for the groups
    taken off. The Pen, the Path Selection tools, the Pattern Stamp, the
    single row and column marquees, the Type Mask tool are on it.
  - The Polygonal Lasso (click the corners; on the first one, a
    double-click or Enter closes it; Backspace takes one back).
  - A big photo: moving, Free Transform and the adjustments' sliders live
    (above), the Object Finder and the palettes not made again meanwhile.
  - OLED Black and Dark: line icons, brush previews in the text's color,
    a dark workspace.

## 0.8.0

The 3.1 look, down to the pixel, that holds up on a 4K screen and a phone.

- **Retro Sans**, the new default font of every app: a recreation of the
  Windows 3.1 MS Sans Serif (after lou's, CC BY-SA 3.0), regular and bold,
  with the characters it lacked drawn in the same style (all of ASCII in
  bold, Latin-1, Latin Extended-A, punctuation) and the Arabic of GNU
  Unifont, joined and right to left. Drawn from its bitmaps at 100 % (one
  screen pixel per font pixel) and from smoothed outlines of the same
  letters when larger and on HD, 2K and 4K screens. Also shipped as
  TrueType files (`src/retro/fonts/RetroSans*.ttf`); the Arabic is a
  separate file, as its licence (OFL) cannot be merged with the Latin
  letters' (CC BY-SA).
- **Choose the font:** `setUiFont(ufRetro)` / `setUiFont(ufSmooth)`
  (DejaVu Sans), `uiFont()`; a "Font" choice in `appearanceSettings`, kept
  by `storeAppearance` ("look.font"). The layout's sizes follow a change
  at once. `setPixelFont` is deprecated (it maps to `setUiFont`).
- **The Windows 3.1 look**, studied from the Win31 project by Wiesław
  Šoltés: black outlines and two-step bevels (`Theme.face2`), the default
  button's ring, a dotted focus inside the face, embossed disabled labels,
  dithered scroll tracks, etched group boxes, separators and status bar
  parts, roomy menus with a hard black shadow, 3.1 window frames with the
  control-menu box and the caption buttons on dialogs and MDI windows,
  navy title bars in front and white ones behind
  (`Theme.inactiveTitle`, `inactiveTitleText`), tool buttons that stay
  down on a dither. New drawing helpers for your own controls:
  `raisedFace`, `buttonFace`, `fieldFrame`, `etchedBox`, `etchedLine`,
  `windowFrame`, `captionButton`, `controlMenuMark`, `titleColors`,
  `ditherFill`, `checker`.
- **Smooth scrolling everywhere:** lists, grids, trees, text areas, panels
  and pages glide a short way per wheel notch or key, follow a finger
  pixel for pixel and fly on after a flick (a finger landing stops them
  without picking an item); rows scroll by pixels, not whole rows.
  `setSmoothScrolling(false)` (a setting in `appearanceSettings`) turns it
  off. For your own views: `scrollWheel`, `scrollPan`, `scrollPan2`,
  `scrollTo`, `scrollBy`, `scrollShow`, `scrollTick`, `scrollStop`,
  `scrolling`, `scrollTarget`, `scrollCaught`.
- **109 pixel icons** (from 78), redrawn in the manner of the period:
  charts, reports, maps, mail, calendar, clock, database, terminal, media
  keys, zoom, filter, sort and more. They are stored compressed (12 KB),
  so apps are smaller: "hello" is 0.77 MB.
- **Notepad** (`examples/notepad.nim`) is a full 3.1 Notepad: New, Open,
  Save, Save As, Cut / Copy / Paste / Delete, Select All, Time/Date (F5),
  Find (Ctrl+F, F3), a status bar and "Save changes?".
- The gallery's Canvas, HTML, Reports and System pages; its pages use the
  room of big screens (the map, 3D, canvas and HTML views grow to the
  bottom) and fold on phones.
- `scrollPanel -1` fills down to the bottom; `buttonWidth(label)` tells
  how wide a button is.
- Fixes: a tool bar's "more" button or a status bar drawn before the
  content could give a phone-sized window needless scroll bars both ways;
  a banner's buttons could cover its close box; Markdown table cells could
  wrap a short word; struck-through and underlined text lost its line at
  100 %; the breadcrumb's last (bold) part could overflow its hover box;
  Android builds failed where `osproc` needs `posix_spawn` (before API
  28): commands now run through `popen` there; `setLineDash` read freed
  memory; the copy dialog's choices could lose their ids; PDFs are written
  to a temporary file and moved into place.

## 0.7.0

The business and desktop release: everything a business app is made of,
the system's own APIs, and a full reference of every control.

- **Data grids as business screens:** cells hold check boxes
  (`checkColumn`), status colours (`colorColumn`), progress bars
  (`progressColumn`), drop-down lists (`choiceColumn`), push buttons and
  links (`buttonColumn`, `linkColumn`), icons (`iconColumn`) or anything
  you draw (`customColumn`); `style(row, col)` gives any cell its own text
  and background colours and bold; `rowHeaders` adds the record indicator,
  `footer` a totals row. Clicks, Space and F4 work on the cells
  (`ev.toggled`, `ev.clicked`, `ev.edited`).
- **Records and forms** (`retro/records`): `maskedEdit` (phone numbers,
  codes, dates; Arabic-Indic digits), `recordNav` (|< < 3 of 20 > >| New
  Delete Save, Ctrl+Home / End / PageUp / PageDown), `dateRange` with
  presets (this month, last quarter...), `dualList`, `propertyGrid`,
  `treeGrid`, `wizard`.
- **Desktop apps** (`retro/desktop`): windows in the window (`mdiArea`,
  `mdiWindow`: move, size, minimize, maximize, the control menu, Ctrl+F6,
  Ctrl+F4, cascade, tile, the Window menu), `findBar` with `findIn` and
  `replaceAllIn`, hot keys the user picks (`hotkeyEdit`,
  `hotkeyPressed`), `aboutBox`.
- **Charts** (`retro/charts`): 21 kinds -- bars (grouped, stacked, 100 %,
  sideways), lines, areas, combo with a second axis, pies, donuts,
  scatter, bubbles, waterfalls, funnels, gauges, candlesticks,
  histograms, heat maps, radars, tree maps, bullets -- with legends that
  hide series, tooltips by mouse, finger and keys, click events, money /
  percent / 1.2K formats, CSV tables (`readCsv`, `chart(..., table, ...)`)
  and PNG export. `examples/charts.nim` is a ready chart viewer.
- **Reports, PDF and printing** (`retro/report`, `retro/pdf`,
  `retro/templates`): reports from Nim code or from HTML templates with
  data (Mustache style), laid out in pages with headers, footers, page
  numbers, repeated table headers and totals; on screen (`reportView`),
  as PDF (real text, the built-in fonts, Arabic), PNG pages, or printed
  through the system. `examples/invoice.nim`.
- **Planning views** (`retro/planning`): `kanbanBoard`, `ganttView`,
  `agendaView`, `orgChart`, `kpiTile`, `statCard`, `kpiRow`.
- **Maps** (`retro/mapview`): a world map with the countries of Natural
  Earth built in -- values by country, markers, routes, zoom and pan, no
  network.
- **3D** (`retro/view3d`): scenes of boxes, spheres, cylinders, cones,
  OBJ and STL models, 3D bar charts; turn, move, zoom, pick; no GPU.
- **Canvas** (`retro/canvas2d`): the HTML5 Canvas 2D API -- paths,
  curves, gradients, patterns, dashes, transforms, text, pictures,
  shadows, compositing, hit tests -- drawn anti-aliased by the kit.
- **HTML and the web** (`retro/htmlview`): `htmlView` / `htmlBlock` show a
  safe subset of HTML (no scripts, no network), `htmlToMarkdown`;
  `webView` is the system's WebView on Android and local HTML elsewhere.
- **Sound and video** (`retro/media`): WAV and tones made and mixed by the
  kit and played through the system's own audio (PulseAudio / ALSA,
  waveOut, AudioQueue, MediaPlayer), other formats through the system's
  player, `videoView`, animated GIFs (`loadGif`, `animation`), `uiSound`.
- **The system's own APIs** (`retro/native`): any shared library
  (`nativeLib`, `nativeProc`), any Java API on Android by reflection
  (`javaStatic`, `javaCall`...), Objective-C on macOS and iOS (`objcSend`),
  Win32 and COM, Termux:API; `vibrate`, `deviceName`, `osVersion`,
  `batteryLevel`, `systemDarkMode`, `keepScreenOn`...
- **Standard scroll bars everywhere:** on touch screens too, content
  larger than its place scrolls in a 3.1 scroll bar (and by finger); the
  page scrolls sideways as well (Shift + the wheel), dialogs clip and
  scroll, Ctrl+Home / End jump. Labels wrap to their room (no more cut
  text in About boxes); `tabs(..., sameHeight = true)` keeps a dialog the
  same size on every tab; `popupMenu` drops a menu under a button.
- **Path bar as in Explorer:** a click on a folder goes there, the arrow
  after it drops a menu of the folders in it, "<<" lists the hidden ones.
  The drive bar scrolls when it does not fit; the preview pane scrolls.
- **retrokit:** `retrokit new` (hello, form, business, files and charts
  apps), `doctor` (checks the machine and says what is missing), `run`,
  `small` (the smallest build) and `apk`.
- **Smaller:** the fonts are stored compressed and unpacked on first use
  (an app is about 180 KB smaller); a stripped "hello" is about 920 KB.
- **Hardening:** every widget audited for mouse, keyboard and touch; NaN,
  negative and huge values clamped; new fuzzers for charts, HTML, 3D
  models, sounds, the canvas and report templates; the tests run under
  AddressSanitizer. Faster file lists (-54 %), icon views (-54 %) and
  label mnemonics.
- **Fixes found by the new tests and sanitizers:** a dash list of odd
  length read freed memory (`setLineDash`); the file job dialogs lost
  their keyboard when their state lived on the stack; a tree with nothing
  selected showed no focus (and Down now picks the first node); a masked
  field showed its caret late; map labels covered each other; Android
  builds no longer need `posix_spawn` (Android 9+) for system commands.
- **docs/controls.md:** every control with its signature, documentation,
  example and pictures in each state (normal, focus, mouse over, pressed,
  open, disabled, touch, dark), drawn by `tools/shots.nim`; the API
  reference in `docs/api/`.
- Retro Files 1.5: Settings in tabs, the Explorer path bar, About that
  fits, Termux access in the settings. The gallery has new pages:
  Records, Windows, Planning, Map & 3D, HTML, Canvas, Reports, System
  (native APIs, sound and video).


## 0.6.0

- **Windows 3.1 pixel icons everywhere** (`retro/pixelicons`): 78 icons
  drawn pixel by pixel in the manner of 3.1 (folders, drives, the
  computer, file kinds, tool bar actions, message box signs, the
  hourglass...), each in 16x16 and 32x32, used as text like the icon font
  (`pxFolder`, `toolButton(pxCopy, "Copy")`). They grow by whole pixels
  only (sharp at any size), and show embossed when disabled.
  `retroOr(px, nf)` picks between them and the Nerd icons (`retroIcons`).
  Original art (not copied from Windows); `tools/genicons.py` makes them
  and the app icons.
- **The classic pixel font reads Arabic:** the Arabic glyphs of GNU
  Unifont (SIL OFL 1.1) are built in, joined and ordered right to left
  like the vector text. With the pixel font, 150% screens get 2x (it
  cannot grow by part of a pixel).
- **Fits the screen:** on X11 the scale comes from Xft.dpi, `GDK_SCALE`,
  `QT_SCALE_FACTOR` or, without them, the monitor's real size (XRandR),
  in steps of 25%: 4K monitors get 2x, small HD laptops stay 1x with
  larger text.
- **3.1 look:** a slide switch drawn as a 3.1 control (`toggle`,
  `settingToggle`; click, slide, keys), cards as group boxes with their
  title in the frame line, dialogs with the navy frame, bold menus
  (`boldMenus`), settings rows without hover fills, tiles that highlight
  only their text (Program Manager), the hourglass as the busy sign,
  color schemes Ocean, Desert, Plum, Hot Dog and Paper ("Color scheme" in
  `appearanceSettings`, `settingCombo`), `driveBar` (the drive buttons of
  File Manager).
- **Mouse, keyboard and touch everywhere:** the mouse's back and forward
  buttons (`mouseBack`, `mouseForward`; X11, Windows, macOS), the middle
  button (`middleClicked`: `tabStrip` closes, `fileList` reports
  `ev.middle`), the menu key and Shift+F10 open the menu of the focused
  row; `tabStrip` takes the arrows, Home and End, scrolls with the wheel
  and a finger, reports `ev.menu`; chips, steps, banners, the bottom bar
  and the floating button take the focus and keys; `tabStop`,
  `takePanX`, `heldFor`, `lifted`.
- **Other apps' files** (`retro/docfs`): folders that another app shares
  through Android's documents providers -- Termux's home -- are listed,
  opened, copied, moved, zipped, renamed and deleted like folders on
  disk (`vIsDir`, `vOpen`, `vMove`... and the file jobs use them).
  `FolderModel` shows "Allow access" for such a folder (`needsAccess`,
  `askAccess`: the system's folder picker, asked once); `localCopy` for
  viewers. Inside Termux, its places ("Termux home", "Termux system",
  "Shared storage") are listed. `retroapk --query:PACKAGE`, and
  `--storage` lets the app see Termux.
- **Faster folders:** a folder not shown yet is listed in two steps --
  the names at once, then sizes and dates (`listFolder(quick = true)`,
  `FileItem.stub`) -- so a folder of thousands of photos on a phone's
  shared storage shows without waiting. `RETRO_STATS=1` prints frame
  times.
- **Selection fixes:** a click on the empty part, or a new rectangle,
  no longer leaves the first item selected (`clearMarks`); Ctrl plus a
  rectangle adds to the selection; Space selects, Ctrl+Space toggles.
- Classic tabs are measured in bold, so their labels sit centered in
  both weights.
- Retro Files 1.4: pixel icons, the drive bar, a tab menu (duplicate,
  close others, move to the other pane), the middle button opens a
  folder in a new tab, the mouse's side buttons go back and forward, a
  selection bar on phones, Termux's files, a cache of copies for other
  apps' documents.
- The gallery shows all the pixel icons and the new widgets.

## 0.5.0

- **Drag and drop** in the core: `startDrag`, `dragging`, `dropTarget`
  (`dsOver`, `dsDropped`), `dropHighlight`, `dragCopies` (Ctrl), `cancelDrag`
  (Esc), a label that follows the pointer; on touch screens a held, then
  moved, finger drags (`lifted`). Grids and icon views drag their rows
  (`dragRows`, `dragItems`) and take drops on rows (`dropOk`), draw a
  selection rectangle from the empty part, scroll while dragging near an
  edge, and report the row under the mouse (`hot`).
- **Explorer parts:** `tabStrip` (closable tabs, a + button, Ctrl+Tab,
  drop on a tab), `pathBar` (folder buttons, typing with suggestions),
  `placesView` ("This device"), tiles (`fvTiles`) and icon sizes with
  Ctrl + the wheel (`ev.zoom`), the preview following the mouse, drops on
  file lists, the tree and the path (`FileDrop`, `jobFor`, `jobTitle`),
  the trash (`moveToTrash`, `trashItems`, `restore`, `deleteForever`,
  `emptyTrash`, `trashList`, `jkTrash`), undo (`remember`, `canUndo`,
  `undoLabel`, `undo`), copy speed and time left in job boxes.
- **Balloons:** `toast` is a pale yellow Windows 95 / 98 balloon with a
  tail, an icon, a bold `title` and a close box; a click closes it
  (`dismissToast`, `toastShown`, `toastArea`).
- **Classic tabs that do not fit** scroll with two arrow buttons, as on
  Windows 95, and keep the chosen tab in view.
- `encodePng`, `savePng`; `RetroVersion`; `beginScroll` takes a key.
- Fixes: a frame asked for with `wakeIn` is no longer lost when another
  frame runs first (hover delays, background results); a key or click
  that changes something late in the frame shows on the next one;
  modifier keys are read from mouse and wheel events and cleared when let
  go (X11 reported them one event late, so Ctrl stuck); suggestions of
  `comboEdit` are not picked until Down, so Enter keeps what was typed;
  touch screens no longer focus the first text box by themselves (no
  keyboard popping up).
- The gallery has a **Files** tab (two lists on a sandbox folder, tabs,
  path bars, views, the details pane, "This device", the trash, undo) and
  is built as an APK too.
- **File widgets in the toolkit** (`retro/filewidgets`): `FolderModel`
  (listing on a worker thread, filter, natural sort, search through
  subfolders, history, selection, make / rename, watching for changes),
  `fileList` (details or icons with thumbnails), `filePreview` (the
  details pane), `folderTree`, `PictureCache` / `cachedPicture` /
  `drawPicture` / `pictureBox`, `textFileView`, `hexFileView`,
  `runJobDialog`, `jobSummary`, `propertiesDialog`, `filePicker` (a modern
  Open / Save dialog), `fileGlyph`, `fileIcon`, `placeGlyph`, `placeList`,
  `diskSpaceCached`, `permissionsText`. Retro Files is now a thin app on
  top of them (1,000 lines instead of 1,800).
- **New widgets:** settings rows (`settingToggle`, `settingChoice`,
  `settingSlider`, `settingButtons`, `settingLink`), `appearanceSettings`
  with `storeAppearance` / `restoreAppearance`, `avatar`, `stepper`,
  `banner`, `pager`, `bottomNav`, `fab`, `sparkline`, `progressRing`,
  `emptyState`, `busyState`, `factList`, `drawFacts`, `drawSpinner`,
  `drawFit`; `sidePane` (beside the content, under it on phones),
  `paneBeside`, `splitBar`; `buttonRow` is public; `builtinThemes`,
  `themeIndex`.
- **Tool bars** put the buttons that do not fit into a "more" menu.
- **Background work:** requests take an `onDone` callback (run on the UI
  thread at the start of a frame) and a `group` to cancel together;
  cancelled requests tell their callback. `beginFrameHooks`.
- **Faster:** drawing loops use a local framebuffer pointer (a full
  redraw takes half the time), text and pictures blend with two
  multiplies, pictures scale with a column table; inflate decodes with
  lookup tables (PNG 3x faster); JPEG uses an integer IDCT and smooth
  chroma upsampling (1.8x faster, within 3 levels of libjpeg).
- **Safer:** fuzzed decoders and parsers (`tests/fuzz`); fixed crashes on
  damaged PNG headers and depths, BMP offsets, JPEG Huffman tables,
  coefficient ranges, scans and segment lengths, zip dates, Arabic
  tatweel, type-ahead with an out-of-range selection, deeply nested
  Markdown (stack), long Markdown words (time), shrinking text files;
  `maxPicturePixels`, inflate output limits (zip bombs), atomic bitmap
  stamps across threads, `saveSettings` no longer raises.
- The slider is finger-sized on touch screens; `wrapLines` and Markdown
  break long words by bisection; composite widgets set `ui.lastRect` to
  their whole area.

## 0.4.0

- **Faster drawing:** each drawing command carries a hash and the frame is
  redrawn in bands 32 pixels high, only where commands changed (a changed
  value costs 0.2 ms instead of 0.8); glyph masks in a direct-mapped
  cache; kerning of ASCII text from a table; cheaper alpha blending.
  Android keeps its frame in the window's pixel format, so showing it is
  a copy.
- **Work off the UI thread** (`retro/background`): `folderAsync`,
  `pictureAsync`, `finished`, `cancelTasks`, `busy`, `toBitmap`. Android
  decodes pictures with the system decoder, scaled straight to the size
  asked for (and turned by EXIF), from any thread.
- **Files of any size** (`retro/textfile`): `TextFile` (lines found in
  slices, read as shown) and `HexFile`; zip listings read only the
  archive's directory; listings ask the file system once per file;
  `cmpNatural` and natural sorting; `pictureSize` from the file header.
- **Hover:** a `hover` theme color; buttons, tool buttons, list and grid
  rows, tree nodes, icon tiles, scroll bars, combo boxes and menu titles
  light up under a mouse -- also a mouse on a phone (Android tells the
  tool type) -- and never under a finger. `hovered`, `canHover`, `finger`.
- **Back is not Exit:** `backPressed()` is true only for the phone's Back,
  so apps go back on Back and leave on Exit or the close box.
- `wrapLines` breaks long paths after a "/" (and finds the break by
  bisection); kinds "Markdown Document" and "Log File".
- APKs ask for a large heap (big photos).
- **Retro Files 1.2:** folders listed and pictures decoded in the
  background (big folders open at once, a spinner while they read),
  thumbnails without stalls, big texts and logs open at once (hex for
  anything), photos fitted to the screen and 1:1 on demand, a preview
  pane beside the listing (under it on phones) with the picture or text,
  sizes, folder contents and Open / Share / Properties, a Settings dialog,
  natural sorting, mouse hover, single tap to open (optional), Back goes
  back through folders and File > Exit leaves.

## 0.3.0 -- Retro Nim UI

- The project is now **Retro Nim UI**: package and module `retro`, tools
  `retroapk` and `retroios`, `RETRO_*` environment variables, Java
  package `org.retro`, default app ids `org.retro.<name>`.
- **Vector text:** DejaVu Sans, Sans Bold, Sans Mono and Mono Bold built
  in, with a TrueType reader and an anti-aliased rasterizer in plain Nim
  (exact area coverage, light hinting on 1x screens, glyph cache); kerning;
  `TextStyle` (bold, italic, mono, underline, strike, size, rtl);
  `lineHeight`; the 3.1 bitmap font stays as `setPixelFont(true)`.
- **Arabic and right-to-left text:** letters join (presentation forms,
  lam-alef ligatures, Persian and Urdu letters), marks sit over their
  letters, lines follow the Unicode bidi algorithm (numbers, brackets).
- **Icons:** 300 Nerd Fonts symbols (`nfFolder`, `nfCog`, ...) usable in
  any text, `glyphIcon` for an `Icon` at any size, `toolButton(nfSave,
  size = 1.3)`.
- **Sizes and layout:** sizes follow fractional densities, `setUiScale`,
  `setTextScale`, Ctrl + / - / 0 and the phone title-bar menu; `dp`;
  weighted row shares, `spring`, `adaptive` columns, `card`, size classes
  (`sizeClass`, `isCompact`, `responsive`, `columnsFor`), forms with an
  automatic label column that stack on phones, the window's content
  scrolls when it is taller than the window, tall dialogs scroll.
- **Shapes:** `disc`, `ring`, `roundRect`, `polygon`, `thickLine`,
  `pieSlice`, anti-aliased at full resolution.
- **New widgets:** `searchBox`, `toggle`, `segmented`, `expander`, `card`,
  `chips`, `badge`, `rating`, `spinner`, `toast`, `colorPicker`,
  `timePicker`, `lineView`, `icon`, `iconLabel`, `heading`, `styledText`.
- **Markdown:** `markdownView` and `markdown` (CommonMark plus GitHub
  tables, task lists, strikethrough and autolinks), `parseMarkdown`,
  `toggleTask`.
- **Files and pictures:** a JPEG decoder (baseline, progressive, EXIF
  orientation, fast 1/8 thumbnails); file jobs, zip and imaging from 0.2
  are part of the library.
- **Retro Files** (`examples/filemanager.nim`): a full file manager for
  desktops, tablets and phones.
- Gallery: "More" and "Markdown" tabs. Check boxes and radio buttons stay
  round and crisp when scaled; grids, trees and icon views scale too.

## 0.2.0

- uirelays is included (`retro/uirelays`); retro needs only Nim.
- Android: a NativeActivity driver in C (touch, soft keyboard including
  Arabic text, Back, pause/resume, system-bar and keyboard insets,
  clipboard, links, system-font text) and `retroapk`, which builds,
  signs and installs an APK with no Gradle, Java or SDK -- also on the
  device itself in Termux. A 3 KB Java activity ships precompiled.
- iOS: a UIKit driver and `retroios`, which builds the .app (Simulator
  and device signing on a Mac).
- Business widgets: `grid` (virtual rows, sort, resize, in-place edit),
  `tree`, `split`/`vsplit`, `calendar`, `datePicker`, `checkList`,
  `numberEdit`, `intEdit`, `comboEdit` (auto-complete), `form`/`field`,
  `link`, `inputBox`, `fileDialog` (3.1 Open / Save As), `barChart`,
  `lineChart`, `pieChart`; `Date` helpers, `formatNumber`, `sortRows`.
- High DPI: zoom follows the display (2x, 3x), `setZoom`, touch metrics on
  touch screens, drag to scroll, long press for context menus.
- Platform services: `dataDir`, `loadSettings`/`saveSettings`/`put`,
  `openUrl`, `platformName`, `isMobile`.
- Windows: Alt shortcuts and F10 work (`WM_SYSKEYDOWN`), mouse capture.
- Popups (menus, drop-downs, date picker) keep their dialog's layer and are
  not clipped by the panel they open from.
- Examples: `ledger.nim` (a small business app), gallery tabs for the
  business widgets and charts.

## 0.1.0

- First release: the Windows 3.1 widgets, menus, dialogs, themes, the pixel
  font, X11 / GDI / Cocoa / SDL3 through uirelays.
