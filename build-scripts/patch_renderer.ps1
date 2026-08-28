param(
    [string]$InputFile = "$PSScriptRoot/vendor/opengl-render-qnx.upstream",
    [string]$OutputFile = "$PSScriptRoot/build/opengl-render-qnx-audi"
)

$bytes = [IO.File]::ReadAllBytes($InputFile)
$encoding = [Text.Encoding]::ASCII

function Replace-ExactAscii([byte[]]$Data, [string]$Old, [string]$New) {
    $oldBytes = $encoding.GetBytes($Old)
    $newBytes = $encoding.GetBytes($New)
    if ($oldBytes.Length -ne $newBytes.Length) {
        throw "Replacement length mismatch: '$Old' -> '$New'"
    }

    $matches = [Collections.Generic.List[int]]::new()
    for ($i = 0; $i -le $Data.Length - $oldBytes.Length; $i++) {
        $equal = $true
        for ($j = 0; $j -lt $oldBytes.Length; $j++) {
            if ($Data[$i + $j] -ne $oldBytes[$j]) { $equal = $false; break }
        }
        if ($equal) { $matches.Add($i) }
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Old', found $($matches.Count)"
    }
    for ($j = 0; $j -lt $newBytes.Length; $j++) {
        $Data[$matches[0] + $j] = $newBytes[$j]
    }
}

function Replace-ArmWordAtOffset([byte[]]$Data, [int]$Offset, [byte[]]$Expected, [byte[]]$Replacement) {
    if ($Expected.Length -ne 4 -or $Replacement.Length -ne 4) {
        throw "ARM instruction patches must be exactly four bytes"
    }
    for ($i = 0; $i -lt 4; $i++) {
        if ($Data[$Offset + $i] -ne $Expected[$i]) {
            throw ('Unexpected ARM word at file offset 0x{0:X}: expected {1}, found {2}' -f
                $Offset,
                (($Expected | ForEach-Object { $_.ToString('X2') }) -join ''),
                ((0..3 | ForEach-Object { $Data[$Offset + $_].ToString('X2') }) -join ''))
        }
    }
    for ($i = 0; $i -lt 4; $i++) { $Data[$Offset + $i] = $Replacement[$i] }
}

# The embedded routing commands target VW display/context IDs.  Audi P1404
# already has a verified route: displayable 20 inside stock context 74.  The
# worker owns the context-74 declaration and watchdog restore, so every
# renderer-internal dmdt command is replaced by a same-length POSIX-shell ':'
# no-op. P1404 QNX has no /bin/true, but ':' is provided by /bin/sh.
# This guarantees that the binary can never switch the live display context.
$noopRestore = ':'.PadRight('/eso/bin/apps/dmdt dc 70 33'.Length)
$noopSwitch  = ':'.PadRight('/eso/bin/apps/dmdt sc 4 70'.Length)
$noopStart   = ':'.PadRight('/eso/bin/apps/dmdt dc 70 3'.Length)
Replace-ExactAscii $bytes '/eso/bin/apps/dmdt dc 70 33' $noopRestore
Replace-ExactAscii $bytes '/eso/bin/apps/dmdt sc 4 70' $noopSwitch
Replace-ExactAscii $bytes '/eso/bin/apps/dmdt dc 70 3' $noopStart

# Audi's stock libdisplayinit keeps its Screen context in library globals.
# This renderer closes the handle immediately after display_init(), then
# reopens it for display_create_window(), which unloads those globals on P1404.
# NOP both dlclose calls so the original Audi library and its state remain
# alive for the whole renderer process. Virtual addresses are 0x113664 and
# 0x11376c; the executable LOAD segment maps VA 0x100000 to file offset 0.
$armNop = [byte[]](0x00, 0x00, 0xA0, 0xE1) # mov r0,r0
Replace-ArmWordAtOffset $bytes 0x13664 ([byte[]](0x11, 0xB9, 0xFF, 0xEB)) $armNop
Replace-ArmWordAtOffset $bytes 0x1376C ([byte[]](0xCF, 0xB8, 0xFF, 0xEB)) $armNop

# The upstream renderer passes VW displayable 3 as the fifth argument to
# display_create_window. With the stock Audi library there is no shim to
# rewrite it, so change `mov r1,#3` to `mov r1,#20` at VA 0x11373c
# (file offset 0x1373c).
Replace-ArmWordAtOffset $bytes 0x1373C `
    ([byte[]](0x03, 0x10, 0xA0, 0xE3)) `
    ([byte[]](0x14, 0x10, 0xA0, 0xE3))

[IO.File]::WriteAllBytes($OutputFile, $bytes)
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $OutputFile
Write-Output "$($hash.Hash)  $OutputFile"
