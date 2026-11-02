## Tests of the asset store (retro/assetstore): every source's request and
## answer (tests/data/assetstore: excerpts of real answers where they could
## be had, else shaped as the APIs document them), the library catalog,
## texture zips, and the download pool (retro/assetfetch) on local files --
## plus GitHub when the network is there.

import std/[os, strutils, times, osproc]
import retro/[assetstore, core, zip]

const data = currentSourcePath().parentDir / "data" / "assetstore"

proc fixture(name: string): string = readFile(data / name)

proc q(s: AssetSource; k: AssetKind; text = ""; category = ""; page = 1; perPage = 0): AssetQuery =
  AssetQuery(source: s, kind: k, text: text, category: category, page: page, perPage: perPage)

# ---- what is offered ---------------------------------------------------------------

block offered:
  doAssert sourcesFor(akPhoto) == @[asOpenverse, asWikimedia, asPixabay, asPexels, asUnsplash]
  doAssert sourcesFor(akIllustration) == @[asOpenverse, asWikimedia, asPixabay]
  doAssert sourcesFor(akIcon) == @[asIconify]
  doAssert sourcesFor(akTexture) == @[asPolyHaven, asAmbientCG]
  doAssert asPolyHaven in sourcesFor(akBackground) and asPixabay in sourcesFor(akBackground)
  for k in [akBrush, akPattern, akGradient, akSwatches, akStyle, akDesign]:
    doAssert sourcesFor(k) == @[asLibrary]
  doAssert needsKey(asPixabay) and needsKey(asPexels) and needsKey(asUnsplash) and not needsKey(asOpenverse)
  doAssert hasKey(asOpenverse) and not hasKey(asPexels)
  doAssert categoriesOf(asPexels, akPhoto).len >= 16 and categoriesOf(asUnsplash, akBackground).len > 5
  doAssert categoriesOf(asOpenverse, akPhoto).len >= 16
  doAssert categoriesOf(asPixabay, akPhoto)[0].key == "backgrounds"
  doAssert categoriesOf(asPolyHaven, akTexture).len > 10
  doAssert categoriesOf(asPolyHaven, akBackground)[0].key == "category=pure-skies"
  doAssert categoriesOf(asAmbientCG, akTexture).len > 10
  doAssert categoriesOf(asIconify, akPhoto).len == 0
  let icons = categoriesOf(asIconify, akIcon)
  doAssert icons[0] == AssetCategory(name: "Material", key: "group:Material")
  doAssert AssetCategory(name: "Material / Material Design Icons", key: "mdi") in icons
  doAssert iconSets.len > 50 and iconSetOf("mdi") >= 0 and iconSetOf("openmoji") < 0
  for s in iconSets:
    doAssert s.spdx in ["MIT", "Apache-2.0", "ISC", "CC0-1.0", "CC-BY-4.0", "CC-BY-3.0", "OFL-1.1",
                        "Unlicense", "BSD-3-Clause"], s.prefix
  doAssert "Emoji" in iconGroups() and "Flags & Maps" in iconGroups()
  doAssert sourceCredit(asPolyHaven) == "Powered by Poly Haven"
  doAssert answerMaxAge(asPixabay) <= 24 * 3600

block addresses:
  doAssert extOfUrl("https://a.org/x/Photo.JPEG?w=3") == "jpg"
  doAssert extOfUrl("https://cdn.polyhaven.com/asset_img/thumbs/a.png?width=256&format=webp") == "webp"
  doAssert extOfUrl("https://ambientcg.com/get?file=Wood096_2K-JPG.zip") == "zip"
  doAssert extOfUrl("https://api.openverse.org/v1/images/abc/thumb/") == ""
  doAssert extOfUrl("https://commons.wikimedia.org/w/api.php?action=query") == "php"

# ---- requests ----------------------------------------------------------------------

block requests:
  var u = queryUrl(q(asOpenverse, akPhoto, "mosque", page = 2))
  doAssert u.startsWith("https://api.openverse.org/v1/images/?q=mosque&page=2&page_size=20")
  doAssert "license_type=commercial,modification" in u and "category=photograph" in u
  u = queryUrl(q(asOpenverse, akVector, category = "islamic pattern", perPage = 50))
  doAssert "q=islamic%20pattern" in u and "extension=svg" in u and "page_size=20" in u, u
  doAssert "q=nature" in queryUrl(q(asOpenverse, akPhoto)), "something to browse"
  u = queryUrl(q(asWikimedia, akPhoto, "قلعة نزوى", page = 3, perPage = 10))
  doAssert u.startsWith("https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2&generator=search&gsrnamespace=6")
  doAssert "gsrsearch=%D9%82" in u and "filetype%3Abitmap" in u and "gsrlimit=10" in u and "gsroffset=20" in u
  doAssert "iiurlwidth=330" in u and "extmetadata" in u
  doAssert "filetype%3Adrawing" in queryUrl(q(asWikimedia, akVector, "flag"))
  doAssert queryUrl(q(asWikimedia, akIcon, "x")) == "", "not a kind Commons gives here"
  pixabayKey = ""
  doAssert queryUrl(q(asPixabay, akPhoto, "flowers")) == "", "no key, no Pixabay"
  pixabayKey = "123-abc"
  u = queryUrl(q(asPixabay, akVector, "bird", category = "animals"))
  doAssert u == "https://pixabay.com/api/?key=123-abc&image_type=vector&per_page=30&page=1&safesearch=true&q=bird&category=animals", u
  doAssert "category=backgrounds" in queryUrl(q(asPixabay, akBackground))
  doAssert "lang=ar" in queryUrl(q(asPixabay, akPhoto, "ورد"))
  u = queryUrl(q(asIconify, akIcon, "home", category = "mdi", page = 2, perPage = 40))
  doAssert u == "https://api.iconify.design/search?query=home&limit=81&start=40&prefixes=mdi", u
  u = queryUrl(q(asIconify, akIcon, "home"))
  doAssert "limit=61" in u and "prefixes=material-symbols,ic,mdi," in u and "openmoji" notin u
  doAssert queryUrl(q(asIconify, akIcon, category = "mdi")) == "https://api.iconify.design/collection?prefix=mdi&info=true"
  u = queryUrl(q(asIconify, akIcon, category = "group:Emoji"))
  doAssert u.startsWith("https://api.iconify.design/collections?prefixes=twemoji,noto,"), u
  doAssert queryUrl(q(asIconify, akIcon, "x", page = 40)) == "", "Iconify finds 999 at most"
  doAssert queryUrl(q(asPolyHaven, akTexture)) == "https://api.polyhaven.com/assets?t=textures"
  doAssert queryUrl(q(asPolyHaven, akTexture, category = "category=wood/boards-planks")) ==
           "https://api.polyhaven.com/assets?t=textures&category=wood/boards-planks"
  doAssert queryUrl(q(asPolyHaven, akBackground, category = "time_of_day=sunrise,sunset")) ==
           "https://api.polyhaven.com/assets?t=hdris&time_of_day=sunrise,sunset"
  doAssert queryUrl(q(asPolyHaven, akBackground, category = "pure skies")).endsWith("&c=pure%20skies")
  u = queryUrl(q(asAmbientCG, akTexture, "oak", category = "wood", page = 3, perPage = 20))
  doAssert u.startsWith("https://ambientcg.com/api/v2/full_json?type=Material&sort=Popular&limit=20&offset=40")
  doAssert u.endsWith("&q=oak%20wood"), u
  doAssert queryUrl(q(asLibrary, akBrush)) == ""

# ---- Openverse ------------------------------------------------------------------------

block openverse:
  let p = parsePage(q(asOpenverse, akPhoto, "cat"), fixture("openverse_search.json"))
  doAssert p.error == "" and p.total == 240 and p.hasMore
  doAssert p.items.len == 5, "the CC BY-NC-ND one is left out: " & $p.items.len
  let a = p.items[0]
  doAssert a.id == "bf16c0a0-cb9d-4587-b89c-7a89b301fbca" and a.license == "CC BY 2.0"
  doAssert a.thumbUrl == "https://api.openverse.org/v1/images/bf16c0a0-cb9d-4587-b89c-7a89b301fbca/thumb/"
  doAssert a.fullUrl.endsWith("_b.jpg") and a.previewUrl == a.fullUrl and a.ext == "jpg"
  doAssert a.width == 1024 and a.height == 732
  doAssert a.attribution.startsWith("\"A White Cat Crosses My Path") and "CC BY 2.0" in a.attribution
  doAssert a.licenseUrl == "https://creativecommons.org/licenses/by/2.0/" and a.pageUrl.startsWith("https://www.flickr.com/")
  doAssert p.items[1].license == "CC0 1.0"
  let svg = p.items[3]
  doAssert svg.ext == "svg" and svg.license == "CC BY-SA 4.0" and svg.author == "Jorge Stolfi"
  let big = p.items[4]
  doAssert big.width == 3888 and big.previewUrl == "", "too big for a preview"
  let v = parsePage(q(asOpenverse, akVector, "x"), fixture("openverse_search.json"))
  doAssert v.items.len == 1 and v.items[0].ext == "svg"
  doAssert parsePage(q(asOpenverse, akPhoto), """{"detail": "Too many requests"}""").error == "Too many requests"
  doAssert licenseNote(a).startsWith("\"A White Cat") and licenseNote(a).endsWith(" by " & a.author & " · CC BY 2.0 · Openverse")

# ---- Wikimedia Commons -----------------------------------------------------------------

block commons:
  let p = parsePage(q(asWikimedia, akPhoto, "mosque"), fixture("wikimedia_search.json"))
  doAssert p.error == "" and p.total == -1 and p.hasMore
  doAssert p.items.len == 2, "the SVG is no photo, GFDL is not kept: " & $p.items.len
  let m = p.items[0]
  doAssert m.id == "File:Sultan Qaboos Grand Mosque courtyard.jpg" and m.title == "Sultan Qaboos Grand Mosque courtyard"
  doAssert m.author == "Example Photographer" and m.license == "CC BY-SA 4.0"
  doAssert m.fullUrl == "https://upload.wikimedia.org/wikipedia/commons/5/5f/Sultan_Qaboos_Grand_Mosque_courtyard.jpg"
  doAssert m.previewUrl == "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5f/Sultan_Qaboos_Grand_Mosque_courtyard.jpg/1280px-Sultan_Qaboos_Grand_Mosque_courtyard.jpg"
  doAssert m.thumbUrl.endsWith("/330px-Sultan_Qaboos_Grand_Mosque_courtyard.jpg") and m.width == 5472
  doAssert m.attribution == "Example Photographer, CC BY-SA 4.0 <https://creativecommons.org/licenses/by-sa/4.0>, via Wikimedia Commons"
  let t = p.items[1]
  doAssert t.license == "CC0" and t.author == "Survey Office" and t.ext == "jpg"
  doAssert t.fullUrl.endsWith("/lossy-page1-3840px-Old_harbour_map.tif.jpg") and t.width == 3840 and t.height == 2715
  doAssert t.previewUrl.endsWith("/lossy-page1-1280px-Old_harbour_map.tif.jpg")
  doAssert t.attribution == "Survey Office, CC0, via Wikimedia Commons"
  let v = parsePage(q(asWikimedia, akVector, "arabesque"), fixture("wikimedia_search.json"))
  doAssert v.items.len == 1 and v.items[0].ext == "svg" and v.items[0].license == "Public domain"
  doAssert v.items[0].title == "Arabesque pattern 01"
  doAssert v.items[0].previewUrl.endsWith("/1280px-Arabesque_pattern_01.svg.png")
  doAssert parsePage(q(asWikimedia, akPhoto), """{"batchcomplete": true}""").items.len == 0
  doAssert parsePage(q(asWikimedia, akPhoto),
    """{"error": {"code": "maxlag", "info": "Waiting for a database server"}}""").error == "Waiting for a database server"
  doAssert stripHtml("""<a href="x">Ali &amp; Sara</a>&#160;<b>Al&#x2D;Said</b>""") == "Ali & Sara Al-Said"

# ---- Pixabay ----------------------------------------------------------------------

block pixabay:
  let p = parsePage(q(asPixabay, akPhoto, "flower"), fixture("pixabay_search.json"))
  doAssert p.error == "" and p.total == 500 and p.hasMore and p.items.len == 2
  let a = p.items[0]
  doAssert a.id == "195893" and a.title == "Blossom" and a.tags == @["blossom", "bloom", "flower"]
  doAssert a.thumbUrl.endsWith("_150.jpg") and a.previewUrl.endsWith("_640.jpg") and a.fullUrl.endsWith("_1280.jpg")
  doAssert a.width == 1280 and a.height == 720 and a.ext == "jpg"
  doAssert a.license == "Pixabay Content License" and a.attribution == "Image by Josch13 from Pixabay"
  doAssert a.authorUrl == "https://pixabay.com/users/Josch13-48777/"
  doAssert p.items[1].ext == "png"
  let bad = parsePage(q(asPixabay, akPhoto), "[ERROR 400] Invalid or missing API key")
  doAssert bad.error == "[ERROR 400] Invalid or missing API key" and bad.items.len == 0

block pexelsAndUnsplash:
  # no key: no request
  pexelsKey = ""
  unsplashKey = ""
  doAssert queryUrl(q(asPexels, akPhoto, "sea")) == "" and queryUrl(q(asUnsplash, akPhoto, "sea")) == ""
  pexelsKey = "PX-KEY"
  unsplashKey = "UN-KEY"
  # the key goes as a header, not in the address
  let pu = queryUrl(q(asPexels, akPhoto, "desert sun", page = 2))
  let (pa, ph) = splitHeaders(pu)
  doAssert pa == "https://api.pexels.com/v1/search?query=desert%20sun&per_page=30&page=2", pa
  doAssert ph == @[("Authorization", "PX-KEY")] and "PX-KEY" notin pa
  doAssert splitHeaders(queryUrl(q(asPexels, akPhoto))).url.startsWith("https://api.pexels.com/v1/curated?")
  let (ua, uh) = splitHeaders(queryUrl(q(asUnsplash, akBackground, "", "sky")))
  doAssert ua.startsWith("https://api.unsplash.com/search/photos?query=sky&") and "orientation=landscape" in ua, ua
  doAssert ("Authorization", "Client-ID UN-KEY") in uh and ("Accept-Version", "v1") in uh
  doAssert splitHeaders(queryUrl(q(asUnsplash, akPhoto))).url.startsWith("https://api.unsplash.com/photos?")
  doAssert extOfUrl(withHeaders("https://x.org/a.png", [("A", "b")])) == "png"
  # the answers
  let p = parsePage(q(asPexels, akPhoto, "nature"), fixture("pexels_search.json"))
  doAssert p.error == "" and p.total == 8000 and p.hasMore and p.items.len == 2
  let a = p.items[0]
  doAssert a.id == "2014422" and a.title == "Brown Rocks During Golden Hour"
  doAssert a.thumbUrl.endsWith("h=350") and "dpr=2" in a.fullUrl and a.ext == "jpg"
  doAssert a.width == 1300 and a.height == 1300, $a.width & "x" & $a.height
  doAssert a.author == "Joey Farina" and a.attribution == "Photo by Joey Farina on Pexels"
  doAssert a.license == "Pexels License" and a.pingUrl == ""
  doAssert p.items[1].title == "Pexels 1181244" and p.items[1].width == 1880
  let u = parsePage(q(asUnsplash, akPhoto, "coffee"), fixture("unsplash_search.json"))
  doAssert u.error == "" and u.total == 133 and u.hasMore and u.items.len == 1
  let b = u.items[0]
  doAssert b.id == "eOLpJytrbsQ" and b.title == "A man drinking a coffee."
  doAssert b.fullUrl == "https://images.unsplash.com/photo-1416339306562-f3d12fefd36f?ixid=abc&w=2400&fm=jpg&q=85&fit=max"
  doAssert b.width == 2400 and b.height == 1800
  doAssert b.authorUrl == "https://unsplash.com/@ugmonk?utm_source=retro_photo&utm_medium=referral"
  doAssert b.attribution == "Photo by Jeff Sheldon on Unsplash" and b.tags == @["coffee", "man"]
  let (pingUrl, pingHeaders) = splitHeaders(b.pingUrl)
  doAssert pingUrl == "https://api.unsplash.com/photos/eOLpJytrbsQ/download?ixid=abc"
  doAssert ("Authorization", "Client-ID UN-KEY") in pingHeaders
  let pop = parsePage(q(asUnsplash, akPhoto), fixture("unsplash_popular.json"))
  doAssert pop.error == "" and pop.items.len == 1 and pop.items[0].title == "A red car"
  let err = parsePage(q(asUnsplash, akPhoto), """{"errors": ["OAuth error: The access token is invalid"]}""")
  doAssert err.error == "OAuth error: The access token is invalid" and err.items.len == 0
  doAssert parsePage(q(asPexels, akPhoto), """{"error": "Unauthorized"}""").error == "Unauthorized"
  pexelsKey = ""
  unsplashKey = ""

# ---- Iconify --------------------------------------------------------------------

block iconify:
  let s = parsePage(q(asIconify, akIcon, "coffee"), fixture("iconify_search.json"))
  doAssert s.error == "" and s.items.len == 6, "openmoji (CC BY-SA) is left out"
  doAssert s.total == 7 and not s.hasMore
  let c = s.items[0]
  doAssert c.id == "mdi:coffee" and c.title == "coffee" and c.category == "mdi"
  doAssert c.thumbUrl == "https://api.iconify.design/mdi/coffee.svg" and c.fullUrl == c.thumbUrl and c.ext == "svg"
  doAssert c.license == "Apache 2.0" and c.author == "Pictogrammers" and c.width == 24
  doAssert c.attribution == "\"coffee\" icon from Material Design Icons by Pictogrammers, Apache 2.0"
  doAssert licenseNote(c) == "\"coffee\" from Material Design Icons by Pictogrammers · Apache 2.0 · Iconify"
  doAssert s.items[5].id == "twemoji:hot-beverage" and s.items[5].license == "CC BY 4.0"
  doAssert not needsResolve(c)
  let p1 = parsePage(q(asIconify, akIcon, category = "mdi", perPage = 10), fixture("iconify_collection_mdi.json"))
  doAssert p1.error == "" and p1.total == 18 and p1.items.len == 10 and p1.hasMore
  doAssert p1.items[0].id == "mdi:bat"
  let p2 = parsePage(q(asIconify, akIcon, category = "mdi", page = 2, perPage = 10), fixture("iconify_collection_mdi.json"))
  doAssert p2.items.len == 8 and not p2.hasMore and p2.items[^1].id == "mdi:access-point-minus"
  let g = parsePage(q(asIconify, akIcon, category = "group:Material"), fixture("iconify_collections_material.json"))
  doAssert g.items.len == 18 and g.items[0].id == "mdi:account-check", $g.items.len
  doAssert iconSvgUrl("mdi", "home", "#fff", 48) == "https://api.iconify.design/mdi/home.svg?color=%23fff&height=48"

# ---- Poly Haven ------------------------------------------------------------------

block polyHaven:
  let p = parsePage(q(asPolyHaven, akTexture), fixture("polyhaven_textures.json"))
  doAssert p.error == "" and p.total == 3 and not p.hasMore
  doAssert p.items[0].id == "concrete_floor_01", "the most downloaded first"
  var t = p.items[0]
  doAssert t.title == "Concrete Floor 01" and t.license == "CC0" and t.author == "Rob Tuytel"
  doAssert t.thumbUrl == "https://cdn.polyhaven.com/asset_img/thumbs/concrete_floor_01.png?width=256&height=256&v=b2c8d05e"
  doAssert t.pageUrl == "https://polyhaven.com/a/concrete_floor_01" and "Exposed Aggregate" in t.tags
  doAssert t.fullUrl == "" and needsResolve(t) and resolveUrl(t) == "https://api.polyhaven.com/files/concrete_floor_01"
  doAssert parsePage(q(asPolyHaven, akTexture, "beach SAND"), fixture("polyhaven_textures.json")).items.len == 1
  doAssert parsePage(q(asPolyHaven, akTexture, perPage = 2, page = 2), fixture("polyhaven_textures.json")).items.len == 1
  doAssert parsePage(q(asPolyHaven, akBackground), fixture("polyhaven_textures.json")).items.len == 0
  var t2 = t
  applyResolve(t, fixture("polyhaven_files_texture.json"))
  doAssert t.fullUrl == "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/4k/concrete_floor_01/concrete_floor_01_diff_4k.jpg"
  doAssert t.ext == "jpg" and t.width == 4096 and t.height == 4096 and not needsResolve(t)
  doAssert t.previewUrl.endsWith("_diff_1k.jpg")
  applyResolve(t2, fixture("polyhaven_files_texture.json"), maxSide = 2048)
  doAssert t2.fullUrl.endsWith("_diff_2k.jpg") and t2.width == 2048
  doAssert licenseNote(t) == "\"Concrete Floor 01\" by Rob Tuytel · CC0 · Poly Haven (Powered by Poly Haven)"
  let h = parsePage(q(asPolyHaven, akBackground), fixture("polyhaven_hdris.json"))
  doAssert h.items.len == 2 and h.items[0].id == "sunset_jhbcentral"
  var hd = h.items[0]
  doAssert hd.author == "Greg Zaal, Dimitrios Savva" and hd.kind == akBackground
  doAssert hd.previewUrl == "https://cdn.polyhaven.com/asset_img/primary/sunset_jhbcentral.png?width=1280&format=webp&v=7f3a91c4"
  var hd8 = hd
  applyResolve(hd, fixture("polyhaven_files_hdri.json"))
  doAssert hd.fullUrl == "https://cdn.polyhaven.com/asset_img/primary/sunset_jhbcentral.png?width=4096&format=webp"
  doAssert hd.ext == "webp" and hd.width == 4096 and hd.height == 2048
  applyResolve(hd8, fixture("polyhaven_files_hdri.json"), maxSide = 8192)
  doAssert hd8.fullUrl == "https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/sunset_jhbcentral.jpg"
  doAssert hd8.ext == "jpg" and hd8.width == 8192 and hd8.height == 4096
  var none = p.items[1]
  applyResolve(none, "No asset with that ID")
  doAssert none.fullUrl == ""

# ---- ambientCG ----------------------------------------------------------------------

block ambient:
  let p = parsePage(q(asAmbientCG, akTexture, "wood", perPage = 2), fixture("ambientcg_search.json"))
  doAssert p.error == "" and p.total == 131 and p.hasMore and p.items.len == 2
  let w = p.items[0]
  doAssert w.id == "Wood096" and w.title == "Wood 096" and w.license == "CC0"
  doAssert w.thumbUrl.endsWith("/256-JPG-FFFFFF/Wood096.jpg") and w.previewUrl.endsWith("/1024-JPG-FFFFFF/Wood096.jpg")
  doAssert w.fullUrl == "https://ambientcg.com/get?file=Wood096_2K-JPG.zip" and w.ext == "zip"
  doAssert w.width == 2048 and w.height == 2048 and w.pageUrl == "https://ambientcg.com/a/Wood096"
  doAssert "wood" in w.tags and not needsResolve(w)
  let f = p.items[1]
  doAssert f.fullUrl.endsWith("WoodFloor051_1K-JPG.zip") and f.width == 1024
  doAssert f.thumbUrl.endsWith("/256-PNG/WoodFloor051.png") and f.previewUrl == ""
  doAssert licenseNote(w) == "\"Wood 096\" · CC0 · ambientCG.com"

block textureZips:
  var z = newZipWriter()
  z.addFile("Wood096.png", "\x89PNG preview")
  z.addFile("Wood096_1K-JPG_NormalGL.jpg", repeat("n", 5000))
  z.addFile("Wood096_1K-JPG_Color.jpg", "\xFF\xD8\xFF color map")
  z.addFile("Wood096_1K-JPG.mtlx", repeat("<materialx/>", 100))
  let zipped = z.finish()
  doAssert textureFromZip(zipped) == ("Wood096_1K-JPG_Color.jpg", "\xFF\xD8\xFF color map")
  var d = newZipWriter()                         # a deflated one, in a folder
  let tif = repeat("albedo pixels ", 400)
  d.addFile("maps/rock_albedo.tif", tif)
  d.addFile("maps/rock_rough.tif", repeat("r", 100))
  let dz = d.finish()
  doAssert dz.len < 2000, "it was deflated"
  doAssert textureFromZip(dz) == ("rock_albedo.tif", tif)
  var o = newZipWriter()                         # no name says color: the biggest plain picture
  o.addFile("a_normal.png", repeat("x", 900))
  o.addFile("small.png", "tiny")
  o.addFile("big.jpg", repeat("y", 300))
  doAssert textureFromZip(o.finish()).name == "big.jpg"
  doAssert textureFromZip("") == ("", "") and textureFromZip("PK\x05\x06 broken") == ("", "")
  var damaged = zipped
  damaged[damaged.find("color map")] = 'C'
  doAssert textureFromZip(damaged) == ("", ""), "the checksum catches it"
  let zf = getTempDir() / "retro-assetstore-test.zip"
  writeFile(zf, zipped)
  doAssert textureFromZipFile(zf) == ("Wood096_1K-JPG_Color.jpg", "\xFF\xD8\xFF color map")
  removeFile(zf)

# ---- the Retro Photo Library ------------------------------------------------------

block library:
  let items = parseLibrary(fixture("library_catalog.json"), "https://example.org/lib/catalog.json")
  doAssert items.len == 8, "the item without a kind is left out"
  let b = items[0]
  doAssert b.kind == akBrush and b.source == asLibrary and b.category == "Ink"
  doAssert b.thumbUrl == "https://example.org/lib/brushes/dry-ink.png"
  doAssert b.fullUrl == "https://example.org/lib/brushes/dry-ink.abr" and b.ext == "abr"
  doAssert items[1].ext == "abr", "from the file's name"
  doAssert items[2].fullUrl == "https://cdn.example.org/retro/girih.pat"
  doAssert items[2].attribution == "\"Girih Tiles\" by Retro Photo, CC BY 4.0" and items[0].attribution == ""
  doAssert items[3].kind == akGradient and items[3].ext == "grd"
  doAssert items[4].kind == akSwatches and items[5].kind == akDesign and items[5].ext == "rpd"
  doAssert items[7].kind == akStyle and items[7].thumbUrl == "https://example.org/lib/styles/gold.png"
  doAssert parseLibrary(fixture("library_catalog.json"), "/data/lib/")[0].thumbUrl == "/data/lib/brushes/dry-ink.png"
  doAssert parseLibrary("{not json", "x").len == 0
  doAssert libraryCategories(items, akBrush) == @[AssetCategory(name: "Dry Media", key: "Dry Media"),
                                                  AssetCategory(name: "Ink", key: "Ink")]
  doAssert asLibrary notin sourcesFor(akTexture)
  setLibrary(items)
  doAssert sourcesFor(akTexture) == @[asPolyHaven, asAmbientCG, asLibrary]
  doAssert asLibrary notin sourcesFor(akPhoto)
  doAssert categoriesOf(asLibrary, akBrush).len == 2
  doAssert libraryPage(q(asLibrary, akBrush)).items.len == 2
  doAssert libraryPage(q(asLibrary, akBrush, "INK")).items.len == 1
  doAssert libraryPage(q(asLibrary, akBrush, category = "dry media")).items[0].id == "brush-chalk"
  doAssert libraryPage(q(asLibrary, akPattern, "islamic geometry")).items.len == 1
  let one = libraryPage(q(asLibrary, akBrush, perPage = 1))
  doAssert one.items.len == 1 and one.total == 2 and one.hasMore
  libraryCatalogUrl = "https://example.org/lib/catalog.json"
  let pp = parsePage(q(asLibrary, akStyle), fixture("library_catalog.json"))
  doAssert pp.error == "" and pp.items.len == 1 and pp.items[0].id == "style-gold"
  setLibrary(@[])

block answersThatAreNot:
  for s in [asOpenverse, asWikimedia, asPixabay, asIconify, asPolyHaven, asAmbientCG, asLibrary]:
    for body in ["", "<html>Bad gateway</html>", "{\"broken\": ", "[1, 2", "null", "{}", "[]"]:
      let p = parsePage(q(s, (if s == asIconify: akIcon elif s in {asPolyHaven, asAmbientCG}: akTexture
                              elif s == asLibrary: akBrush else: akPhoto), "x"), body)
      doAssert p.items.len == 0
  doAssert parsePage(q(asOpenverse, akPhoto), "{\"broken\": ").error.startsWith("the answer cannot be read")

# ---- the download pool ----------------------------------------------------------------

proc waitFor(n: int; seconds = 30.0): seq[FetchResult] =
  let until = epochTime() + seconds
  while result.len < n and epochTime() < until:
    result.add fetchDone()
    sleep(5)

let root = getTempDir() / "retro-assetstore-test"
removeDir(root)
createDir(root / "src")
assetCacheDir = root / "cache"
assetFetchThreads = 3

block pool:
  if findExe("curl").len == 0 and findExe("wget").len == 0:
    echo "no curl or wget: the download pool is not tested"
  else:
    for i in 1 .. 4: writeFile(root / "src" / ("f" & $i & ".txt"), "file " & $i & repeat(".", i * 1000))
    writeFile(root / "src" / "answer.php", """{"ok": true}""")
    writeFile(root / "src" / "pic.png", "\xFF\xD8\xFF\xE0 a JPEG behind a .png name")
    let url = proc (name: string): string = "file://" & root / "src" / name

    # parallel tickets
    var tickets: seq[int]
    for i in 1 .. 4: tickets.add fetchAsync(url("f" & $i & ".txt"), group = 1)
    doAssert fetchPending() == 4
    doAssert ui.wakeAt > 0, "frames are asked for"
    var got = waitFor(4)
    doAssert got.len == 4 and fetchPending() == 0
    for r in got:
      let i = tickets.find(r.ticket) + 1
      doAssert i > 0 and r.error == "" and r.group == 1 and not r.cached, r.error
      doAssert readFile(r.path) == "file " & $i & repeat(".", i * 1000)
      doAssert r.path.startsWith(assetCacheDir) and r.path.endsWith(".txt")
    doAssert cachedPath(url("f1.txt")).len > 0 and cachedPath(url("f9.txt")) == ""

    # cache hits come at once, through fetchDone
    let hit = fetchAsync(url("f2.txt"))
    got = fetchDone()
    doAssert got.len == 1 and got[0].ticket == hit and got[0].cached and got[0].path.len > 0

    # the kind of file is read from what came
    let a = fetchAsync(url("answer.php"))
    let b = fetchAsync(url("pic.png"))
    got = waitFor(2)
    doAssert got.len == 2
    for r in got:
      if r.ticket == a: doAssert r.path.endsWith(".json"), r.path
      else: doAssert r.ticket == b and r.path.endsWith(".jpg"), r.path
    doAssert cachedPath(url("answer.php")).endsWith(".json")

    # failures say why
    let missing = fetchAsync(url("nothing-here.txt"), group = 2)
    got = waitFor(1)
    doAssert got.len == 1 and got[0].ticket == missing and got[0].path == "" and got[0].error.len > 0
    doAssert fetchAsync("", group = 2) > 0
    got = fetchDone()
    doAssert got.len == 1 and got[0].error == "no address"

    # held, the same address twice is downloaded once; cancelled, nothing comes
    pauseFetches(true)
    writeFile(root / "src" / "twice.txt", "twice")
    let t1 = fetchAsync(url("twice.txt"), group = 3)
    let t2 = fetchAsync(url("twice.txt"), group = 4, priority = 5)
    for i in 1 .. 5: discard fetchAsync(url("g" & $i & ".txt"), group = 7)
    doAssert fetchPending() == 7
    ui.wakeAt = 0
    doAssert fetchDone().len == 0 and ui.wakeAt > 0, "waiting downloads keep the frames coming"
    cancelFetches(7)
    doAssert fetchPending() == 2
    cancelFetches(4)
    doAssert fetchPending() == 1
    pauseFetches(false)
    got = waitFor(1)
    sleep(300)
    got.add fetchDone()
    doAssert got.len == 1 and got[0].ticket == t1 and readFile(got[0].path) == "twice", $got.len
    doAssert t2 != t1
    doAssert fetchPending() == 0
    ui.wakeAt = 0
    doAssert fetchDone().len == 0 and ui.wakeAt == 0, "no frames are asked for when nothing waits"

    # an older copy stands in when the address fails
    let old = cachedPath(url("f3.txt"))
    setLastModificationTime(old, getTime() - initDuration(hours = 1))
    removeFile(root / "src" / "f3.txt")
    let s = fetchAsync(url("f3.txt"), maxAgeSec = 0)
    got = waitFor(1)
    doAssert got.len == 1 and got[0].ticket == s and got[0].stale and got[0].path == old and got[0].error == ""

    # a download that waits for it
    doAssert fetchNow(url("f4.txt"), root / "out" / "f4.txt") == ""
    doAssert readFile(root / "out" / "f4.txt").startsWith("file 4")
    doAssert fetchNow(url("nope.txt"), root / "out" / "nope.txt").len > 0
    doAssert not fileExists(root / "out" / "nope.txt")

    trimAssetCache(0)
    doAssert cachedPath(url("f1.txt")) == ""

block headersSent:
  # the headers of `withHeaders` reach the server (a small one on this computer)
  let py = findExe("python3")
  if py.len == 0 or findExe("curl").len == 0:
    echo "no python3 or curl: the headers are not tested"
  else:
    let script = root / "echo_server.py"
    writeFile(script, """
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = ("auth=" + str(self.headers.get("Authorization")) + "\n").encode()
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.handle_request(); s.handle_request()
""")
    let portFile = root / "port.txt"
    let srv = startProcess(py, args = [script, portFile], options = {poParentStreams})
    var tries = 0
    while not fileExists(portFile) and tries < 200:
      sleep(20)
      inc tries
    sleep(50)
    let port = readFile(portFile).strip
    let u = withHeaders("http://127.0.0.1:" & port & "/x.txt", [("Authorization", "Client-ID SECRET")])
    doAssert fetchNow(u, root / "out" / "auth.txt", 10) == ""
    doAssert readFile(root / "out" / "auth.txt").strip == "auth=Client-ID SECRET"
    let t = fetchAsync(withHeaders("http://127.0.0.1:" & port & "/y.txt", [("Authorization", "K2")]))
    let got = waitFor(1)
    doAssert got.len == 1 and got[0].ticket == t and readFile(got[0].path).strip == "auth=K2", $got
    discard srv.waitForExit(5000)
    srv.close()
    echo "headers: ok"

# ---- the real network: GitHub (skipped when it cannot be reached) -------------------------

block network:
  const base = "https://raw.githubusercontent.com/Poly-Haven/Public-API/master/"
  if findExe("curl").len == 0 or fetchNow(base & "asset_types.json", root / "probe.json", 30) != "":
    echo "the network is not there: GitHub downloads are not tested"
  else:
    doAssert readFile(root / "probe.json").contains("\"textures\"")
    let names = ["README.md", "ToS.md", "LICENSE", "asset_types.json"]
    var tickets: seq[int]
    for n in names: tickets.add fetchAsync(base & n, group = 9)
    let lost = fetchAsync(base & "no-such-file-here.json", group = 9)
    let got = waitFor(5, 90)
    doAssert got.len == 5, $got.len
    for r in got:
      if r.ticket == lost:
        doAssert r.path == "" and "404" in r.error, r.error
      else:
        let n = names[tickets.find(r.ticket)]
        doAssert r.error == "" and r.path.len > 0, n & ": " & r.error
        if n == "asset_types.json": doAssert r.path.endsWith(".json")
        if n == "ToS.md": doAssert "Poly Haven" in readFile(r.path)
    let again = fetchAsync(base & "ToS.md")
    let g2 = fetchDone()
    doAssert g2.len == 1 and g2[0].ticket == again and g2[0].cached
    echo "GitHub downloads: ok"

removeDir(root)
echo "assetstore: ok"
