# Retro Photo -- included by photo.nim
#
# File > Export > SVG: the shapes as paths, the type as text, the rest as
# a picture inside it (retro/photosvg).

var
  svgSave: tuple[pick: bool; path: string]          ## File > Export > SVG: the file asked for

proc startSvgExport() =
  let d = cur()
  if d == nil: return
  let base = if d.path.len > 0: d.path.splitFile.dir / d.path.splitFile.name
             else: picturesDir() / (if d.name.len > 0: d.name else: "Untitled")
  svgSave = (true, base & ".svg")

proc svgDialogs() =
  if filePicker(svgSave.pick, svgSave.path, fmSave, ["*.svg"], "Export SVG"):
    let d = cur()
    if d != nil:
      var p = svgSave.path
      if p.splitFile.ext.toLowerAscii != ".svg": p.add ".svg"
      try:
        writeFile(p, d.svgOf())
        status = "Saved " & p.extractFilename & ": shapes as paths, type as text"
      except IOError, OSError:
        status = "Could not save " & p.extractFilename
