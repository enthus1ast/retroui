## Built-in 16x16 tool bar icons, and `icon` to draw your own.

import gfx

proc icon*(rows: openArray[string]): Icon =
  ## Pixel art in the 16 VGA colors: k black, w white, s silver, g gray,
  ## r red, m maroon, y yellow, o olive, l lime, G green, c cyan, t teal,
  ## b blue, n navy, p pink, P purple; '.' is transparent.
  result.h = rows.len
  result.w = if rows.len > 0: rows[0].len else: 0
  for row in rows:
    doAssert row.len == result.w, "icon rows must be equally long"
    for ch in row:
      result.px.add(case ch
        of 'k': 0xFF000000'u32
        of 'w': 0xFFFFFFFF'u32
        of 's': 0xFFC0C0C0'u32
        of 'g': 0xFF808080'u32
        of 'r': 0xFFFF0000'u32
        of 'm': 0xFF800000'u32
        of 'y': 0xFFFFFF00'u32
        of 'o': 0xFF808000'u32
        of 'l': 0xFF00FF00'u32
        of 'G': 0xFF008000'u32
        of 'c': 0xFF00FFFF'u32
        of 't': 0xFF008080'u32
        of 'b': 0xFF0000FF'u32
        of 'n': 0xFF000080'u32
        of 'p': 0xFFFF00FF'u32
        of 'P': 0xFF800080'u32
        else: 0'u32)

const
  icNew* = icon([
    "................",
    "..kkkkkkkk......",
    "..kwwwwwwkk.....",
    "..kwwwwwwkwk....",
    "..kwwwwwwkkkk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...",
    "..kkkkkkkkkkk...",
    "................"])
  icOpen* = icon([
    "................",
    "................",
    "..........kkk...",
    ".........k...k.k",
    "..............kk",
    ".kkk.........kkk",
    "kyyykkkkkkk.....",
    "kywyyyyyyyk.....",
    "kyykkkkkkkkkk...",
    "kywkoooooooook..",
    "kykoooooooook...",
    "kkoooooooook....",
    "kkoooooooook....",
    "kkkkkkkkkkk.....",
    "................",
    "................"])
  icSave* = icon([
    "................",
    ".kkkkkkkkkkkkkk.",
    ".knkwwwwwwwwknk.",
    ".knkwwwwwwwwkkk.",
    ".knkwwwwwwwwknk.",
    ".knkwwwwwwwwknk.",
    ".knkkkkkkkkkknk.",
    ".knnnnnnnnnnnnk.",
    ".knnkkkkkkkknnk.",
    ".knnkssssskknnk.",
    ".knnkssssskknnk.",
    ".knnkssssskknnk.",
    ".kknkssssskknnk.",
    "..kkkkkkkkkkkkk.",
    "................",
    "................"])
  icCut* = icon([
    "................",
    "....k.....k.....",
    "....k.....k.....",
    "....k.....k.....",
    "....kk...kk.....",
    ".....k...k......",
    ".....kk.kk......",
    "......k.k.......",
    ".......k........",
    "......n.n.......",
    "....nnn.nnn.....",
    "...n..n.n..n....",
    "...n..n.n..n....",
    "...n..n.n..n....",
    "....nn...nn.....",
    "................"])
  icCopy* = icon([
    "kkkkkkk.........",
    "kwwwwwkk........",
    "kwkkkwkwk.......",
    "kwwwwwkkkk......",
    "kwkkkkkkkkkkk...",
    "kwwwwkwwwwwkkk..",
    "kwkkkkwkkkwkwk..",
    "kwwwwkwwwwwkkkk.",
    "kwkkkkwkkkkkkwk.",
    "kwwwwkwwwwwwwwk.",
    "kkkkkkwkkkkkkwk.",
    "......wwwwwwwwk.",
    "......kkkkkkkwk.",
    "......kwwwwwwwk.",
    "......kkkkkkkkk.",
    "................"])
  icPaste* = icon([
    "................",
    ".....kkkkk......",
    "..kkkkyyykkkk...",
    ".kooko...okook..",
    ".kookkkkkkkook..",
    ".kooooooooooook.",
    ".kooookkkkkkkkk.",
    ".kooookwwwwwwwk.",
    ".kooookwkkkkkwkk",
    ".kooookwwwwwwwk.",
    ".kooookwkkkkkwk.",
    ".kooookwwwwwwwk.",
    ".kooookwkkkkwwk.",
    "..kkkkkwwwwwwwk.",
    "......kkkkkkkkk.",
    "................"])
  icPrint* = icon([
    "................",
    "....kkkkkkkk....",
    "....kwwwwwwk....",
    "....kwkkkkwk....",
    "....kwwwwwwk....",
    "..kkkkkkkkkkkk..",
    ".kssssssssssssk.",
    ".kwwwwwwwwwwwwk.",
    ".kssssssssssllk.",
    ".kssssssssssssk.",
    ".kggggggggggggk.",
    ".kkkkkkkkkkkkkk.",
    "..kwwwwwwwwwwk..",
    "..kkkkkkkkkkkk..",
    "................",
    "................"])
  icHelp* = icon([
    "................",
    ".....kkkkkk.....",
    "....kbbbbbbk....",
    "...kbbwwwwbbk...",
    "...kbwwbbwwbk...",
    "...kbbbbbwwbk...",
    "....kbbbwwbbk...",
    ".....kbwwbbk....",
    ".....kbwwbk.....",
    ".....kbbbbk.....",
    ".....kbwwbk.....",
    ".....kbwwbk.....",
    "......kkkk......",
    "................",
    "................",
    "................"])

# ---- files, folders and places (for file managers and file dialogs) ----

const
  icFolder* = icon([
    "................", "................", ".oooo...........", "oyyyyo..........",
    "oywwwyoooooooo..", "owyyyyyyyyyyyyo.", "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok",
    "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok",
    "owyyyyyyyyyyyyok", "oooooooooooooook", ".kkkkkkkkkkkkkkk", "................"])
    ## A closed folder.
  icFolderOpen* = icon([
    "................", "................", ".oooo...........", "oyyyyo..........",
    "oywwwyoooooooo..", "owyyyyyyyyyyyyo.", "owyyoooooooooooo", "owyowwwwwwwwwwwo",
    "owyowyyyyyyyyyo.", "owowyyyyyyyyyyo.", "owowyyyyyyyyyo..", "oowyyyyyyyyyyo..",
    "oowyyyyyyyyyo...", "ooooooooooooo...", ".kkkkkkkkkkkk...", "................"])
    ## An open folder.
  icFile* = icon([
    "................", "..kkkkkkkk......", "..kwwwwwwkk.....", "..kwwwwwwkwk....",
    "..kwwwwwwkkkk...", "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kkkkkkkkkkk...", "................"])
    ## A document.
  icText* = icon([
    "................", "..kkkkkkkk......", "..kwwwwwwkk.....", "..kwggggwkwk....",
    "..kwwwwwwkkkk...", "..kwggggggwwk...", "..kwwwwwwwwwk...", "..kwgggggggwk...",
    "..kwwwwwwwwwk...", "..kwggggggwwk...", "..kwwwwwwwwwk...", "..kwgggggggwk...",
    "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kkkkkkkkkkk...", "................"])
    ## A text file.
  icImage* = icon([
    "................", ".kkkkkkkkkkkkkk.", ".kcccccccccccck.", ".kccccccccyyyck.",
    ".kcccccccyyyyck.", ".kccccccccyyyck.", ".kcccccccccccck.", ".kccccGccccccck.",
    ".kcccGGGcccGcck.", ".kccGGGGGcGGGck.", ".kcGGGGGGGGGGGk.", ".kGGGGGGGGGGGGk.",
    ".kGGGGGGGGGGGGk.", ".kkkkkkkkkkkkkk.", "................", "................"])
    ## A picture.
  icAudio* = icon([
    "................", ".........kk.....", ".........kkkk...", ".........k.kkk..",
    ".........k...kk.", ".........k....k.", ".........k......", ".........k......",
    ".........k......", ".....kkkkk......", "....knnnnk......", "...knnnnnk......",
    "...knnnnnk......", "....knnnk.......", ".....kkk........", "................"])
    ## Music.
  icVideo* = icon([
    "................", "kkkkkkkkkkkkkkkk", "kwkwkwkwkwkwkwkk", "kkkkkkkkkkkkkkkk",
    "knnnnnnnnnnnnnnk", "knnnnnnwnnnnnnnk", "knnnnnnwwnnnnnnk", "knnnnnnwwwnnnnnk",
    "knnnnnnwwnnnnnnk", "knnnnnnwnnnnnnnk", "knnnnnnnnnnnnnnk", "kkkkkkkkkkkkkkkk",
    "kwkwkwkwkwkwkwkk", "kkkkkkkkkkkkkkkk", "................", "................"])
    ## A video.
  icArchive* = icon([
    "................", "..kkkkkkkkkkk...", "..koooyoooooook.", "..kyyykyyyyyyok.",
    "..kyyywyyyyyyok.", "..kyyykyyyyyyok.", "..kyyywyyyyyyok.", "..kyykkkyyyyyok.",
    "..kyykykyyyyyok.", "..kyykkkyyyyyok.", "..kyyyyyyyyyyok.", "..kyyyyyyyyyyok.",
    "..koooooooooook.", "..kkkkkkkkkkkkk.", "................", "................"])
    ## A zip archive.
  icCode* = icon([
    "................", "..kkkkkkkk......", "..kwwwwwwkk.....", "..kwwwwwwkwk....",
    "..kwwwwwwkkkk...", "..kwwwwwwwwwk...", "..kwwbwwwbwwk...", "..kwbwwwwwbwk...",
    "..kbwwwrwwwbk...", "..kwbwwrwwbwk...", "..kwwbwrwbwwk...", "..kwwwwwwwwwk...",
    "..kwwwwwwwwwk...", "..kwwwwwwwwwk...", "..kkkkkkkkkkk...", "................"])
    ## Source code.
  icApp* = icon([
    "................", "kkkkkkkkkkkkkkkk", "knnnnnnnnnnnnnnk", "knwnnnnnnnnnsnsk",
    "kkkkkkkkkkkkkkkk", "kwwwwwwwwwwwwwwk", "kwwwwwwwwwwwwwwk", "kwwGGwwwwwwwwwwk",
    "kwwGGwwwwbbbbwwk", "kwwwwwwwwwwwwwwk", "kwwrrwwwwbbbbwwk", "kwwrrwwwwwwwwwwk",
    "kwwwwwwwwwwwwwwk", "kkkkkkkkkkkkkkkk", "................", "................"])
    ## A program.
  icDrive* = icon([
    "................", "................", "................", "................",
    "................", "..kkkkkkkkkkkk..", ".kssssssssssssk.", "kwwwwwwwwwwwwwwk",
    "kssssssssssssssk", "kssssssssssslsgk", "kssssssssssssssk", "kggggggggggggggk",
    ".kkkkkkkkkkkkkk.", "................", "................", "................"])
    ## A disk.
  icSdCard* = icon([
    "................", "....kkkkkkkk....", "...kssksksksk...", "..ksskskskssk...",
    "..ksssssssssk...", "..ksssssssssk...", "..ksnnnnnnnsk...", "..ksnwwwwwnsk...",
    "..ksnwwwwwnsk...", "..ksnnnnnnnsk...", "..ksssssssssk...", "..ksssssssssk...",
    "..ksssssssssk...", "..kkkkkkkkkkk...", "................", "................"])
    ## An SD card.
  icHome* = icon([
    "................", ".......mm.......", "......mmmm..kk..", ".....mmmmmm.kk..",
    "....mmmmmmmmmk..", "...mmmmmmmmmmm..", "..mmmmmmmmmmmmm.", ".kkkkkkkkkkkkkkk",
    "..kwwwwwwwwwwwk.", "..kwkkkwwwkkkwk.", "..kwkckwwwkokwk.", "..kwkkkwwwkokwk.",
    "..kwwwwwwwkokwk.", "..kwwwwwwwkokwk.", "..kkkkkkkkkkkkk.", "................"])
    ## Home.
  icComputer* = icon([
    "................", ".kkkkkkkkkkkkkk.", ".kssssssssssssk.", ".ksnnnnnnnnnnsk.",
    ".ksnttttttttnsk.", ".ksnttttttttnsk.", ".ksnttttttttnsk.", ".ksnnnnnnnnnnsk.",
    ".kssssssssssssk.", ".kkkkkkkkkkkkkk.", ".....kssssk.....", "...kkkkkkkkkk...",
    "..kssssssssssk..", "..kggggggggggk..", "..kkkkkkkkkkkk..", "................"])
    ## The computer.
  icBack* = icon([
    "................", "................", ".......k........", "......kGk.......",
    ".....kGGk.......", "....kGGGkkkkkkk.", "...kGGGGGGGGGGk.", "..kGGGGGGGGGGGk.",
    "...kGGGGGGGGGGk.", "....kGGGkkkkkkk.", ".....kGGk.......", "......kGk.......",
    ".......k........", "................", "................", "................"])
    ## Back.
  icForward* = icon([
    "................", "................", "........k.......", ".......kGk......",
    ".......kGGk.....", ".kkkkkkkGGGk....", ".kGGGGGGGGGGk...", ".kGGGGGGGGGGGk..",
    ".kGGGGGGGGGGk...", ".kkkkkkkGGGk....", ".......kGGk.....", ".......kGk......",
    "........k.......", "................", "................", "................"])
    ## Forward.
  icUp* = icon([
    "................", ".oooo...........", "oyyyyo..........", "oyyyyyoooooooo..",
    "oyyyyyyyykyyyyo.", "oyyyyyyykkkyyyok", "oyyyyyykkkkkyyok", "oyyyyykkkkkkkyok",
    "oyyyyyyykkkyyyok", "oyyyyyyykkkyyyok", "oyyyyyyykkkkkkok", "oyyyyyyyyyyyyyok",
    "oyyyyyyyyyyyyyok", "oooooooooooooook", ".kkkkkkkkkkkkkkk", "................"])
    ## Up one folder.
  icRefresh* = icon([
    "................", ".....kkkkk......", "...kkGGGGGkk.k..", "..kGGkkkkkGGkGk.",
    ".kGGk.....kGGGk.", ".kGk.....kGGGGk.", "kGk.......kkkkk.", "kGk.............",
    "............kGk.", "............kGk.", ".kkkkk.......kGk", ".kGGGGk.....kGk.",
    ".kGGGk.....kGGk.", ".kGkGGkkkkkGGk..", "..k.kkGGGGGkk...", "......kkkkk....."])
    ## Refresh.
  icDelete* = icon([
    "................", "................", "..kk.......kk...", ".krrk.....krrk..",
    ".krrrk...krrrk..", "..krrrk.krrrk...", "...krrrkrrrk....", "....krrrrrk.....",
    ".....krrrk......", "....krrrrrk.....", "...krrrkrrrk....", "..krrrk.krrrk...",
    ".krrrk...krrrk..", ".krrk.....krrk..", "..kk.......kk...", "................"])
    ## Delete.
  icRename* = icon([
    "................", "................", "................", "kkkkkkkkkkkkk...",
    "kwwwwwwwwwwwkk..", "kwwkwwwwwwwwkkk.", "kwkwkwwwwkwwkk..", "kwkkkwwkkwwwkk..",
    "kwkwkwkwkwwwkk..", "kwkwkwwkkkwwkk..", "kwwwwwwwwwwwkkk.", "kkkkkkkkkkkkk...",
    "................", "................", "................", "................"])
    ## Rename.
  icNewFolder* = icon([
    "...........y....", ".........y.y.y..", "..........yyy...", ".oooo....yyyyy..",
    "oyyyyo....yyy...", "oywwwyoooy.y.y..", "owyyyyyyyyy.yo..", "owyyyyyyyyyyyyok",
    "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok", "owyyyyyyyyyyyyok",
    "owyyyyyyyyyyyyok", "oooooooooooooook", ".kkkkkkkkkkkkkkk", "................"])
    ## A new folder.
  icProperties* = icon([
    "................", "..kkkkkkkk......", "..kwwwwwwkk.....", "..kwwwwwwkwk....",
    "..kwwwwwwkkkk...", "..kwwwwwwwwwk...", "..kwbbbbbbbwk...", "..kwwwwwwwwwk...",
    "..kwbbbbbbwwk...", "..kwwwwwwwwwk...", "..kwbbbbbbbwk...", "..kwwwwwwkkkkkk.",
    "..kwwwwwkGGGGGk.", "..kwwwwwkGGkGGk.", "..kkkkkkkGkkkGk.", ".........kkkkkk."])
    ## Properties.
  icSearch* = icon([
    "................", "....kkkk........", "..kkwwwwkk......", "..kwwccwwk......",
    ".kwwcwwwwwk.....", ".kwcwwwwwwk.....", ".kwwwwwwwwk.....", ".kwwwwwwwwk.....",
    "..kwwwwwwk......", "..kkwwwwkkk.....", "....kkkk.kkk....", "..........kkk...",
    "...........kkk..", "............kkk.", ".............kk.", "................"])
    ## Search.
  icViewDetails* = icon([
    "................", "................", ".nn.kkkkkkkkkkk.", ".nn.............",
    "................", ".nn.kkkkkkkkkkk.", ".nn.............", "................",
    ".nn.kkkkkkkkkkk.", ".nn.............", "................", ".nn.kkkkkkkkkkk.",
    ".nn.............", "................", "................", "................"])
    ## A details view.
  icViewIcons* = icon([
    "................", "................", ".nnnnn...nnnnn..", ".nnnnn...nnnnn..",
    ".nnnnn...nnnnn..", ".nnnnn...nnnnn..", "................", ".kkkkk...kkkkk..",
    "................", ".nnnnn...nnnnn..", ".nnnnn...nnnnn..", ".nnnnn...nnnnn..",
    ".nnnnn...nnnnn..", "................", ".kkkkk...kkkkk..", "................"])
    ## An icons view.
  icStar* = icon([
    "................", ".......k........", "......kyk.......", "......kyk.......",
    ".....kyyyk......", "kkkkkkyyykkkkkk.", ".kyyyyyyyyyyyk..", "..kyyyyyyyyyk...",
    "...kyyyyyyyk....", "...kyyyyyyyk....", "..kyyyykyyyyk...", "..kyyyk.kyyyk...",
    ".kyyk.....kyyk..", ".kkk.......kkk..", "................", "................"])
    ## A favorite.
  icShare* = icon([
    "................", "..........k.....", "..........kk....", "..kkkkkkkkkbk...",
    ".kbbbbbbbbbbbk..", ".kbbbbbbbbbbbbk.", ".kbbkkkkkkkbbk..", ".kbk......kbk...",
    ".kbk......kk....", ".kbk......k.....", ".kbk............", ".kbk......kkkk..",
    ".kbkkkkkkkkbbk..", ".kbbbbbbbbbbbk..", "..kkkkkkkkkkk...", "................"])
    ## Share.
  icSelect* = icon([
    "................", "................", ".kkkkkkkkkkkk...", ".kwwwwwwwwwwk...",
    ".kwwwwwwwwwkk...", ".kwwwwwwwwkkk...", ".kwkwwwwwkkwk...", ".kwkkwwwkkwwk...",
    ".kwwkkwkkwwwk...", ".kwwwkkkwwwwk...", ".kwwwwkwwwwwk...", ".kwwwwwwwwwwk...",
    ".kkkkkkkkkkkk...", "................", "................", "................"])
    ## Select.
