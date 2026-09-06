<#
    build.ps1 - rakit src/ jadi satu file place.rbxlx yang bisa dibuka Studio.

    Untuk dipakai saat Rojo belum terpasang. Jalankan ulang tiap kali source
    berubah, lalu buka place.rbxlx di Studio.

    Alur kerjanya satu arah: file di src/ adalah sumber kebenaran, place.rbxlx
    adalah hasil rakitan. Jangan edit skrip di dalam Studio lalu berharap
    perubahannya kembali ke src/ - tidak akan.

    Begitu Rojo terpasang, hapus skrip ini dan pakai 'rojo serve'.

    CATATAN: file ini sengaja ASCII murni. PowerShell 5.1 membaca skrip
    UTF-8 tanpa BOM sebagai CP1252, dan byte ketiga dari em dash menjadi
    tanda kutip pintar yang diperlakukan PowerShell sebagai pembuka string.
    Satu em dash di dalam komentar cukup untuk mematahkan seluruh file.
#>

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$out = Join-Path $root 'place.rbxlx'

$script:refCounter = 0
function New-Ref {
    $script:refCounter++
    return "RBX$($script:refCounter)"
}

function Get-Source([string]$relative) {
    $path = Join-Path $root $relative
    if (-not (Test-Path $path)) {
        throw "File tidak ditemukan: $path"
    }
    $text = Get-Content -Path $path -Raw -Encoding UTF8

    # Blok CDATA berakhir pada "]]>". Kode Luau memakai "]]" untuk menutup
    # komentar blok, jadi urutan itu bisa muncul. Dipecah supaya XML tetap sah.
    return $text -replace ']]>', ']]]]><![CDATA[>'
}

function New-ScriptItem([string]$class, [string]$name, [string]$relative, [int]$indent) {
    $pad = ' ' * $indent
    $source = Get-Source $relative
    $ref = New-Ref

    return @"
$pad<Item class="$class" referent="$ref">
$pad  <Properties>
$pad    <string name="Name">$name</string>
$pad    <ProtectedString name="Source"><![CDATA[
$source
]]></ProtectedString>
$pad  </Properties>
$pad</Item>
"@
}

function New-ContainerOpen([string]$class, [string]$name, [int]$indent) {
    $pad = ' ' * $indent
    $ref = New-Ref

    return @"
$pad<Item class="$class" referent="$ref">
$pad  <Properties>
$pad    <string name="Name">$name</string>
$pad  </Properties>
"@
}

function New-ContainerClose([int]$indent) {
    return (' ' * $indent) + '</Item>'
}

$parts = New-Object System.Collections.Generic.List[string]

$parts.Add('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

# ReplicatedStorage/Shared
$parts.Add((New-ContainerOpen 'ReplicatedStorage' 'ReplicatedStorage' 2))
$parts.Add((New-ContainerOpen 'Folder' 'Shared' 4))
$parts.Add((New-ScriptItem 'ModuleScript' 'Config' 'src/shared/Config.luau' 6))
$parts.Add((New-ScriptItem 'ModuleScript' 'Remotes' 'src/shared/Remotes.luau' 6))
$parts.Add((New-ContainerClose 4))
$parts.Add((New-ContainerClose 2))

# ServerScriptService/Server
$parts.Add((New-ContainerOpen 'ServerScriptService' 'ServerScriptService' 2))
$parts.Add((New-ContainerOpen 'Folder' 'Server' 4))
$parts.Add((New-ScriptItem 'ModuleScript' 'PitService' 'src/server/PitService.luau' 6))
$parts.Add((New-ScriptItem 'ModuleScript' 'PlayerData' 'src/server/PlayerData.luau' 6))
$parts.Add((New-ScriptItem 'Script' 'Main' 'src/server/Main.server.luau' 6))
$parts.Add((New-ContainerClose 4))
$parts.Add((New-ContainerClose 2))

# StarterPlayer/StarterPlayerScripts
$parts.Add((New-ContainerOpen 'StarterPlayer' 'StarterPlayer' 2))
$parts.Add((New-ContainerOpen 'StarterPlayerScripts' 'StarterPlayerScripts' 4))
$parts.Add((New-ScriptItem 'LocalScript' 'Client' 'src/client/Main.client.luau' 6))
$parts.Add((New-ContainerClose 4))
$parts.Add((New-ContainerClose 2))

$parts.Add('</roblox>')

$xml = ($parts -join "`r`n")

# UTF-8 tanpa BOM. Set-Content -Encoding utf8 di PowerShell 5.1 menulis BOM,
# dan BOM di depan deklarasi XML bisa membuat parser menolak file.
[System.IO.File]::WriteAllText($out, $xml, (New-Object System.Text.UTF8Encoding($false)))

$size = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "place.rbxlx dirakit - $size KB"
Write-Host "Buka di Studio, lalu tekan Play."
