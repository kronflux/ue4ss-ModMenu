# Reads named pixels from the Windows reference screenshots and writes the colour fixture that
# tooling/lua/windows_presets_spec.lua checks every preset against.
#
# Usage (from the repository root):
#   pwsh -NoProfile -File tools/sample-reference.ps1 -Screens <dir> -Out <json> [-Only <id,...>]
#
#   -Screens  the directory that holds the 480 by 400 *_sample.png screenshots
#   -Out      the fixture to write, for example tooling/lua/fixtures/windows-reference.json
#   -Only     preset ids to write; without it, every id
#
# The fixture is { "<preset id>": [ { name, x, y, color, field } ] }. `field` is the resolved style
# path the pixel colour must equal: a dotted path, with [n] (1-based) to pick a stop of a stops
# field, for example header.barStops[1] or button.xp.edge.
#
# Each point is a pixel of the screenshot, which is the ground truth for a colour. A stops field
# lists one point per stop, in order, so a preset copies the gradient the screenshot shows. The
# extracted Luna theme data (WinUI-Samples/assets/xp-retail/luna) supplies what a screenshot does not
# show: hover and pressed faces, the hover rings and the pointer thumb's hover state. Those are not
# in the fixture.
#
# The seven XP screenshots share one layout, so one table (XpPoints) covers them, with the few
# coordinates that differ given as options per screenshot. The Windows Classic screenshot has its own
# layout and its own table (ClassicPoints).

param(
    [Parameter(Mandatory = $true)][string]$Screens,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Only = ""
)

Add-Type -AssemblyName System.Drawing

function P([string]$name, [int]$x, [int]$y, [string]$field) {
    [pscustomobject]@{ name = $name; x = $x; y = $y; field = $field }
}

# One point per stop of a vertical gradient: the stops sit at these rows of column $x.
function VStops([string]$name, [string]$field, [int]$x, [int[]]$rows) {
    for ($i = 0; $i -lt $rows.Count; $i++) {
        P ("{0} {1}" -f $name, ($i + 1)) $x $rows[$i] ("{0}[{1}]" -f $field, ($i + 1))
    }
}

# One point per stop along a list of (x, y) pairs.
function PStops([string]$name, [string]$field, [int[][]]$points) {
    for ($i = 0; $i -lt $points.Count; $i++) {
        P ("{0} {1}" -f $name, ($i + 1)) $points[$i][0] $points[$i][1] ("{0}[{1}]" -f $field, ($i + 1))
    }
}

# The sample window of the XP screenshots: Luna Blue, Silver and Olive Green, Embedded, Royale,
# Royale Noir and Zune. Each option below is a place where a screenshot's control sits off the
# Luna Blue coordinates; a table that gives none samples the Luna Blue ones.
#   dy          rows the check boxes and radio buttons sit above Luna's (Embedded and Zune: -1)
#   capRows     the rows of the minimise button's face
#   closeX      the column, and closeRows the rows, of the close button's face
#   edge, ring  the pixels of a push button's edge and of the default button's ring
#   faceRows    the rows of a push button's face
#   arrowEdgeX  the column of a drop-down arrow button's edge
#   tabEdge     the pixel of an inactive tab's edge
#   titlePt     a pixel in a thick stroke of the title text
#   shadowPt    a pixel of the title text's drop shadow
function XpPoints([hashtable]$o = @{}) {
    $d = @{
        dy = 0
        capRows = @(7, 11, 15, 19, 23)
        closeX = 456
        closeRows = @(7, 11, 15, 19, 23)
        edge = @(171, 335)
        ring = @(172, 335)
        faceRows = @(320, 324, 327, 331, 334, 338)
        arrowEdgeX = 280
        tabEdge = @(95, 84)
        titlePt = @(25, 9)
        shadowPt = @(26, 10)
    }
    foreach ($k in $o.Keys) { $d[$k] = $o[$k] }
    $dy = [int]$d.dy
    @(
        P 'window fill' 300 70 'panel.fill'
        P 'window frame' 3 200 'panel.outline'
        P 'title text' $d.titlePt[0] $d.titlePt[1] 'title.color'
        P 'title shadow' $d.shadowPt[0] $d.shadowPt[1] 'header.titleShadow'
        VStops 'title bar' 'header.barStops' 200 @(1, 4, 7, 10, 13, 17, 20, 23, 26, 29)
        VStops 'caption button face' 'header.controlStops' 419 $d.capRows
        VStops 'close button face' 'header.closeStops' $d.closeX $d.closeRows
        P 'push button edge' $d.edge[0] $d.edge[1] 'button.xp.edge'
        P 'default button ring' $d.ring[0] $d.ring[1] 'button.xp.defaultRing'
        VStops 'push button face' 'button.xp.face' 256 $d.faceRows
        P 'field outline' 200 112 'field.outline'
        P 'field fill' 200 129 'field.fill'
        VStops 'dropdown arrow face' 'field.arrow.face' 281 @(188, 191, 196, 200)
        P 'dropdown arrow edge' $d.arrowEdgeX 194 'field.arrow.edge'
        P 'dropdown arrow glyph' 284 193 'field.arrow.glyph'
        P 'check edge' 32 (142 + $dy) 'toggle.checkEdge'
        P 'check edge, mixed' 32 (162 + $dy) 'toggle.checkEdgeOn'
        PStops 'check face' 'toggle.checkFace' @(@(33, (137 + $dy)), @(35, (139 + $dy)), @(37, (141 + $dy)), @(39, (143 + $dy)), @(41, (145 + $dy)), @(43, (147 + $dy)))
        P 'check mark (the radio dot colour)' 39 (202 + $dy) 'toggle.checkMark'
        P 'radio edge' 32 (222 + $dy) 'choice.radioEdge'
        PStops 'radio ring' 'choice.radioRings' @(@(34, (222 + $dy)), @(36, (222 + $dy)), @(38, (222 + $dy)))
        P 'radio dot' 39 (202 + $dy) 'choice.markFill'
        P 'active tab fill' 40 86 'tabs.markFill'
        P 'tab line' 40 83 'tabs.markLine'
        VStops 'tab line stop' 'tabs.markLineStops' 40 @(82, 83, 84)
        VStops 'tab face' 'tabs.faceStops' 68 @(85, 89, 92, 96, 99, 103)
        P 'tab edge' $d.tabEdge[0] $d.tabEdge[1] 'tabs.edge'
        VStops 'progress block' 'progress.block' 328 @(85, 86, 87, 88, 89, 90, 91, 92)
        P 'progress frame edge' 320 89 'progress.frame.edge'
        P 'progress frame fill' 323 89 'progress.frame.fill'
        P 'progress track' 323 89 'progress.track'
        P 'slider track' 350 113 'slider.track'
        P 'slider track light' 350 116 'slider.trackLight'
        P 'slider thumb fill' 383 115 'slider.thumbFill'
        P 'slider thumb edge' 378 112 'slider.thumbEdge'
        P 'slider tick' 333 130 'slider.tickColor'
        P 'tooltip fill' 400 145 'tooltip.fill'
        P 'tooltip outline' 400 138 'tooltip.outline'
        P 'status bar fill' 100 380 'panel.statusBar.fill'
        P 'status bar line' 100 374 'panel.statusBar.line'
        P 'list fill' 250 215 'list.fill'
        P 'selection highlight' 250 230 'list.hover'
        P 'group box line' 22 180 'section.line'
        P 'scroll track' 462 110 'scroll.track'
        P 'scroll thumb' 462 140 'scroll.thumb'
        P 'scroll thumb edge' 473 140 'scroll.thumbEdge'
    )
}

# The sample window of the Windows Classic screenshot (Windows Standard scheme). Its bevels are two
# rings: the point names the ring it reads, the outer one first. The scrollbar track is a dither of
# white and the face colour, so it has no single pixel to check and is not in the table.
function ClassicPoints {
    @(
        P 'window fill' 300 70 'panel.fill'
        P 'window frame, outer light' 0 200 'panel.bevel.light'
        P 'window frame, inner light' 1 200 'panel.bevel.innerLight'
        P 'window frame, inner dark' 478 200 'panel.bevel.innerDark'
        P 'window frame, outer dark' 479 200 'panel.bevel.dark'
        P 'title text' 26 8 'title.color'
        P 'title bar, left end' 4 12 'header.barStops[1]'
        P 'title bar, right end' 474 12 'header.barStops[2]'
        P 'caption button face' 430 12 'header.controlFace'
        P 'push button face' 260 316 'button.faces.secondary.fill'
        P 'push button, outer light' 250 322 'button.bevel.light'
        P 'push button, inner light' 251 322 'button.bevel.innerLight'
        P 'push button, inner dark' 323 322 'button.bevel.innerDark'
        P 'push button, outer dark' 324 322 'button.bevel.dark'
        P 'default button edge' 170 322 'button.defaultEdge'
        P 'field fill' 200 108 'field.fill'
        P 'field, outer dark' 168 110 'field.bevel.dark'
        P 'field, inner dark' 169 110 'field.bevel.innerDark'
        P 'field, inner light' 200 124 'field.bevel.innerLight'
        P 'field, outer light' 200 125 'field.bevel.light'
        P 'dropdown arrow face' 288 184 'field.arrow.face[1]'
        P 'dropdown arrow face, lower' 288 190 'field.arrow.face[2]'
        P 'dropdown arrow glyph' 288 187 'field.arrow.glyph'
        P 'dropdown arrow, outer light' 285 180 'field.arrow.bevel.light'
        P 'dropdown arrow, inner light' 285 181 'field.arrow.bevel.innerLight'
        P 'dropdown arrow, inner dark' 294 186 'field.arrow.bevel.innerDark'
        P 'dropdown arrow, outer dark' 295 186 'field.arrow.bevel.dark'
        P 'check box fill' 38 135 'toggle.checkOff'
        P 'check box fill, checked' 38 135 'toggle.checkOn'
        P 'check box, outer dark' 38 129 'toggle.checkBevel.dark'
        P 'check box, inner dark' 38 130 'toggle.checkBevel.innerDark'
        P 'check box, inner light' 38 140 'toggle.checkBevel.innerLight'
        P 'check box, outer light' 38 141 'toggle.checkBevel.light'
        P 'check mark (the radio dot colour)' 38 195 'toggle.checkMark'
        P 'radio dot' 38 195 'choice.markFill'
        P 'radio fill' 38 215 'choice.radioFill'
        P 'radio, outer dark' 32 214 'choice.radioBevel.dark'
        P 'radio, inner dark' 33 214 'choice.radioBevel.innerDark'
        P 'radio, inner light' 43 214 'choice.radioBevel.innerLight'
        P 'radio, outer light' 44 214 'choice.radioBevel.light'
        P 'active tab fill' 40 85 'tabs.markFill'
        P 'tab face' 90 80 'tabs.faceStops[1]'
        P 'tab face, lower' 90 92 'tabs.faceStops[2]'
        P 'tab edge' 63 90 'tabs.edge'
        P 'progress block' 325 80 'progress.fill'
        P 'progress track' 410 80 'progress.track'
        P 'progress frame fill' 321 80 'progress.frame.fill'
        P 'progress frame, dark' 320 80 'progress.frame.bevel.dark'
        P 'progress frame, light' 400 88 'progress.frame.bevel.light'
        P 'slider track' 370 106 'slider.track'
        P 'slider track light' 370 109 'slider.trackLight'
        P 'slider thumb fill' 383 105 'slider.thumbFill'
        P 'slider thumb edge' 388 105 'slider.thumbEdge'
        P 'slider tick' 383 122 'slider.tickColor'
        P 'tooltip fill' 330 135 'tooltip.fill'
        P 'tooltip outline' 320 140 'tooltip.outline'
        P 'status bar fill' 100 385 'panel.statusBar.fill'
        P 'status bar line' 100 376 'panel.statusBar.line'
        P 'list fill' 200 208 'list.fill'
        P 'selection highlight' 200 228 'list.hover'
        P 'group box line' 22 210 'section.line'
        P 'scroll thumb' 465 140 'scroll.thumb'
        P 'scroll thumb edge' 471 125 'scroll.thumbEdge'
    )
}

# Where the Embedded and Zune screenshots differ from the Luna ones: their check boxes and radio
# buttons sit one row up, their push buttons are one row shorter, and their caption buttons and
# drop-down arrows have a white inner line, so the face and edge pixels move.
$flat = @{
    dy = -1
    capRows = @(7, 11, 15, 19, 22)
    closeX = 458
    closeRows = @(8, 12, 15, 18, 22)
    edge = @(251, 330)
    ring = @(172, 330)
    faceRows = @(321, 324, 327, 329, 332, 336)
    arrowEdgeX = 279
    tabEdge = @(68, 84)
    titlePt = @(25, 10)
    shadowPt = @(79, 13)
}
# Royale and Royale Noir keep Luna's rows, but their push button edge is the Cancel button's (the
# default button's is a brighter blue), and their arrow button edge sits at column 279.
$royale = @{
    capRows = @(7, 11, 15, 19, 22)
    closeX = 458
    closeRows = @(8, 12, 15, 18, 22)
    edge = @(251, 330)
    ring = @(172, 330)
    faceRows = @(321, 324, 327, 331, 335, 338)
    arrowEdgeX = 279
    tabEdge = @(68, 84)
}

# Preset id, screenshot, and the points.
$tables = [ordered]@{
    'xp-luna'         = @{ file = 'xp_luna_sample.png';         points = XpPoints }
    'xp-luna-silver'  = @{ file = 'xp_luna_silver_sample.png';  points = (XpPoints @{ arrowEdgeX = 279 }) + @(P 'caption glyph' 410 20 'header.captionGlyph') }
    'xp-luna-olive'   = @{ file = 'xp_luna_olive_sample.png';   points = XpPoints }
    'xp-embedded'     = @{ file = 'xp_embedded_sample.png';     points = XpPoints $flat }
    'xp-royale'       = @{ file = 'xp_royale_sample.png';       points = XpPoints $royale }
    'xp-royale-noir'  = @{ file = 'xp_royale_noir_sample.png';  points = XpPoints $royale }
    'xp-zune'         = @{ file = 'xp_zune_sample.png';         points = XpPoints $flat }
    'windows-classic' = @{ file = '9x_classic_sample.png';      points = ClassicPoints }
}

$wanted = @()
if ($Only -ne "") {
    $wanted = $Only.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    foreach ($id in $wanted) {
        if (-not $tables.Contains($id)) {
            throw "No point table for '$id'. Known ids: $($tables.Keys -join ', ')"
        }
    }
}

$screensDir = [System.IO.Path]::GetFullPath($Screens)
$blocks = @()
$summary = @()
foreach ($id in $tables.Keys) {
    $entry = $tables[$id]
    if ($wanted.Count -gt 0 -and $wanted -notcontains $id) { continue }
    $path = Join-Path $screensDir $entry.file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing screenshot $path"
    }
    $bmp = [System.Drawing.Bitmap]::new($path)
    try {
        $lines = @()
        foreach ($pt in $entry.points) {
            if ($pt.x -lt 0 -or $pt.y -lt 0 -or $pt.x -ge $bmp.Width -or $pt.y -ge $bmp.Height) {
                throw "$id '$($pt.name)' is outside the screenshot: $($pt.x),$($pt.y)"
            }
            $x = $pt.x
            $y = $pt.y
            $c = $bmp.GetPixel($x, $y)
            $hex = '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
            $lines += ('    {{ "name": "{0}", "x": {1}, "y": {2}, "color": "{3}", "field": "{4}" }}' -f $pt.name, $x, $y, $hex, $pt.field)
        }
    }
    finally {
        $bmp.Dispose()
    }
    $blocks += ('  "{0}": [{1}{2}{1}  ]' -f $id, "`n", ($lines -join ",`n"))
    $summary += ("{0}: {1} points" -f $id, $entry.points.Count)
}

if ($blocks.Count -eq 0) {
    throw "No preset selected."
}
$json = "{`n" + ($blocks -join ",`n") + "`n}`n"
$outPath = [System.IO.Path]::GetFullPath($Out)
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
$summary | ForEach-Object { Write-Output $_ }
Write-Output "wrote $outPath"
