<#
.SYNOPSIS
    Returns the Polycom admin password RingCentral sets on a desk phone.

.DESCRIPTION
    RingCentral sets the Polycom web/admin password to:  admn<DeviceID>pwd
    The DeviceID is the number in the admin-portal URL when you open a phone
    (Phone System > Phones & Devices > User Phones > click the phone).

    This script pulls the device list from the RingCentral REST API and
    matches on serial number or extension number, then prints the password.

    Auth uses a RingCentral JWT (Server/No UI app, "Read Accounts" permission).
    Config lives in RCConfig.json next to this script.

.EXAMPLE
    .\Get-RCPhonePassword.ps1 -Serial 64167F123456
    .\Get-RCPhonePassword.ps1 -Extension 1042
    .\Get-RCPhonePassword.ps1 -All          # dump every phone + password to a grid
#>

[CmdletBinding(DefaultParameterSetName = 'Prompt')]
param(
    [Parameter(ParameterSetName = 'Serial')]    [string]$Serial,
    [Parameter(ParameterSetName = 'Extension')] [string]$Extension,
    [Parameter(ParameterSetName = 'All')]       [switch]$All,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'RCConfig.json')
)

$ErrorActionPreference = 'Stop'

# ---------- Config ----------
if (-not (Test-Path $ConfigPath)) {
    $template = [ordered]@{
        ClientId     = 'YOUR_APP_CLIENT_ID'
        ClientSecret = 'YOUR_APP_CLIENT_SECRET'
        Jwt          = 'YOUR_JWT_CREDENTIAL'
        Server       = 'https://platform.ringcentral.com'
        PasswordPrefix = 'admn'
        PasswordSuffix = 'pwd'
    }
    $template | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Host "Created template config at $ConfigPath - fill it in and run again." -ForegroundColor Yellow
    return
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'ClientId','ClientSecret','Jwt') {
    if (-not $cfg.$k -or $cfg.$k -like 'YOUR_*') { throw "RCConfig.json: '$k' is not set." }
}
if (-not $cfg.Server)         { $cfg | Add-Member -NotePropertyName Server -NotePropertyValue 'https://platform.ringcentral.com' }
if (-not $cfg.PasswordPrefix) { $cfg | Add-Member -NotePropertyName PasswordPrefix -NotePropertyValue 'admn' }
if (-not $cfg.PasswordSuffix) { $cfg | Add-Member -NotePropertyName PasswordSuffix -NotePropertyValue 'pwd' }

# ---------- Auth (JWT) ----------
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($cfg.ClientId):$($cfg.ClientSecret)"))
$tokenResp = Invoke-RestMethod -Method Post -Uri "$($cfg.Server)/restapi/oauth/token" `
    -Headers @{ Authorization = "Basic $basic" } `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{
        grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
        assertion  = $cfg.Jwt
    }
$headers = @{ Authorization = "Bearer $($tokenResp.access_token)" }

# ---------- Pull all devices (paged) ----------
$devices = [System.Collections.Generic.List[object]]::new()
$page = 1
do {
    $uri  = "$($cfg.Server)/restapi/v1.0/account/~/device?perPage=1000&page=$page"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    foreach ($d in $resp.records) { $devices.Add($d) }
    $totalPages = $resp.paging.totalPages
    $page++
} while ($page -le $totalPages)

if ($devices.Count -eq 0) { throw "No devices returned from RingCentral." }

# ---------- Shape output ----------
$rows = foreach ($d in $devices) {
    [pscustomobject]@{
        Extension  = $d.extension.extensionNumber
        Name       = $d.name
        Model      = $d.model.name
        Serial     = $d.serial
        DeviceId   = $d.id
        Status     = $d.status
        AdminPass  = "$($cfg.PasswordPrefix)$($d.id)$($cfg.PasswordSuffix)"
    }
}

# ---------- Select ----------
switch ($PSCmdlet.ParameterSetName) {
    'Serial'    { $match = $rows | Where-Object { $_.Serial -and $_.Serial -ieq $Serial.Trim() } }
    'Extension' { $match = $rows | Where-Object { $_.Extension -eq $Extension.Trim() } }
    'All'       { $rows | Sort-Object Extension | Out-GridView -Title 'RingCentral Phones - Admin Passwords'; return }
    default {
        $lookup = Read-Host 'Enter phone SERIAL or EXTENSION number'
        $lookup = $lookup.Trim()
        $match = $rows | Where-Object { ($_.Serial -and $_.Serial -ieq $lookup) -or $_.Extension -eq $lookup }
    }
}

if (-not $match) {
    Write-Host "No phone matched. Partial serial hits:" -ForegroundColor Yellow
    $needle = if ($Serial) { $Serial } elseif ($Extension) { $Extension } else { $lookup }
    $rows | Where-Object { $_.Serial -like "*$needle*" -or $_.Extension -like "*$needle*" } |
        Format-Table Extension, Name, Model, Serial -AutoSize
    return
}

foreach ($m in $match) {
    Write-Host ""
    Write-Host "Extension : $($m.Extension)  ($($m.Name))"
    Write-Host "Model     : $($m.Model)"
    Write-Host "Serial    : $($m.Serial)"
    Write-Host "Device ID : $($m.DeviceId)"
    Write-Host "Status    : $($m.Status)"
    Write-Host "Login     : admin" -ForegroundColor Cyan
    Write-Host "Password  : $($m.AdminPass)" -ForegroundColor Green
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
        $m.AdminPass | Set-Clipboard
        Write-Host "(password copied to clipboard)" -ForegroundColor DarkGray
    }
}
