# iRidi cloud diagnostics for Windows 10/11 and Windows PowerShell 5.1 / PowerShell 7+.
# Examples:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product i3knx
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product iridi-pro -Region EU

[CmdletBinding()]
param(
    [string]$Product = "",

    [ValidateSet("RU", "EU", "CN")]
    [string]$Region = "RU",

    [switch]$Quality
)

$ToolVersion = "1.5"

if (-not $Product) {
    while (-not $Product) {
        Clear-Host
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "               iRidi Cloud Diagnostics (Windows)" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Select product to diagnose:"
        Write-Host "  1. i3 KNX"
        Write-Host "  2. Bus77 Home"
        Write-Host "  3. Bus77 Lite"
        Write-Host "  4. iRidi Pro - RU region"
        Write-Host "  5. iRidi Pro - EU region"
        Write-Host "  6. iRidi Pro - CN region"
        Write-Host "  0. Exit"
        Write-Host ""
        $selection = Read-Host "Enter choice (0-6)"
        switch ($selection) {
            "1" { $Product = "i3knx" }
            "2" { $Product = "bus77-home" }
            "3" { $Product = "bus77-lite" }
            "4" { $Product = "iridi-pro"; $Region = "RU" }
            "5" { $Product = "iridi-pro"; $Region = "EU" }
            "6" { $Product = "iridi-pro"; $Region = "CN" }
            "0" { exit 0 }
            default {
                Write-Host "Invalid selection. Press Enter and try again..."
                [void](Read-Host)
                continue
            }
        }
        Write-Host ""
        $qualChoice = Read-Host "Run extended quality & stability test (latency, loss, throughput, MTU)? [y/N]"
        if ($qualChoice -match "^[yY]") { $Quality = $true }
    }
}

$Product = $Product.ToLowerInvariant()
$SupportedProducts = @("i3knx", "bus77-home", "bus77-lite", "iridi-pro")
if (-not ($SupportedProducts -contains $Product)) {
    Write-Host ("[NOT OK] Unknown product: {0}" -f $Product) -ForegroundColor Red
    Write-Host "Allowed values: i3knx, bus77-home, bus77-lite, iridi-pro"
    exit 2
}

$Region = $Region.ToUpperInvariant()
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDirectory) {
    $ScriptDirectory = (Get-Location).Path
}
$LogDirectory = Join-Path $ScriptDirectory "logs"
if (-not (Test-Path -LiteralPath $LogDirectory)) {
    try {
        [void](New-Item -ItemType Directory -Path $LogDirectory -ErrorAction Stop)
    } catch {
        $LogDirectory = [System.IO.Path]::GetTempPath()
    }
}

$LogProduct = $Product.Replace("-", "_")
if ($Product -eq "iridi-pro") {
    $LogProduct = $LogProduct + "_" + $Region.ToLowerInvariant()
}
$LogPath = Join-Path $LogDirectory ($LogProduct + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

function Write-TechLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[{0}] {1}" -f $timestamp, $Message
    try {
        Add-Content -LiteralPath $LogPath -Value $logLine -ErrorAction SilentlyContinue
    } catch {
    }
}

$ErrorActionPreference = "Continue"
$MaxAttempts = 3
$RetryDelaySeconds = 1
$ConnectTimeoutMilliseconds = 6000
$RequestTimeoutMilliseconds = 15000
$GateTimeoutMilliseconds = 5000
$HttpTotal = 0
$HttpOk = 0
$HttpFail = 0
$WarningCount = 0

# TLS 1.2 setup
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Enum]::ToObject(
        [System.Net.SecurityProtocolType],
        3072
    )
} catch {
}

# Bypass certificate validation for connectivity preflight
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {
}

function New-Resource {
    param(
        [string]$Id,
        [string]$Label,
        [string]$Url,
        [string]$ExpectedIp
    )

    $resource = New-Object PSObject
    $resource | Add-Member NoteProperty Id $Id
    $resource | Add-Member NoteProperty Label $Label
    $resource | Add-Member NoteProperty Url $Url
    $resource | Add-Member NoteProperty ExpectedIp $ExpectedIp
    return $resource
}

function Add-CommonBus77Resources {
    param(
        [string]$ProductHost,
        [string]$ProductLabel,
        [string]$IpHubHost,
        [string]$IpHubLabel,
        [string]$IpHubIp
    )

    $items = @()
    $items += New-Resource "www" "Website & Downloads" "https://www.iridi.com/" "89.169.183.139"
    $items += New-Resource "auth-ru" "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245"
    $items += New-Resource "endpoint" "Cloud Endpoint" "https://endpoint.iridi.com/" "95.181.182.182"
    $items += New-Resource "bus77" $ProductLabel ("https://" + $ProductHost + "/") "84.201.152.245"
    $items += New-Resource "iphub" $IpHubLabel ("https://" + $IpHubHost + "/") $IpHubIp
    $items += New-Resource "commercial" "Commercial Offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191"
    $items += New-Resource "voice-cws" "Voice Assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60"
    return $items
}

$Resources = @()
$GateHosts = @()
$ProductLabel = ""

switch ($Product) {
    "i3knx" {
        $ProductLabel = "i3 KNX"
        $GateHosts = @("37.27.5.98", "85.192.35.27")
        $QualityLatencyUrl = "https://auth.eu.iridi.com/"
        $QualityLatencyLabel = "Authorization EU"
        $QualityThroughputUrl = "https://www.iridi.com/"
        $QualityThroughputLabel = "iRidi portal (www.iridi.com)"
        $QualityMtuHost = "auth.eu.iridi.com"
        $Resources += New-Resource "www" "Website & Downloads" "https://www.iridi.com/" "89.169.183.139"
        $Resources += New-Resource "auth-eu" "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71"
        $Resources += New-Resource "proxy-auth-eu" "Auth Proxy EU" "https://proxy.auth.eu.iridi.com/" "72.56.78.171"
        $Resources += New-Resource "proxy-auth-cloud" "Auth Proxy Cloud" "https://proxy.auth.eu.iridi.cloud/" "94.131.83.102"
        $Resources += New-Resource "i3knx-eu" "i3 KNX Cloud EU" "https://i3knx.eu.iridi.com/" "95.216.162.71"
        $Resources += New-Resource "proxy-i3knx-eu" "i3 KNX Proxy EU" "https://proxy.i3knx.eu.iridi.com/" "147.45.238.146"
        $Resources += New-Resource "proxy-knx-cloud" "KNX Proxy Cloud" "https://proxy.knx.eu.iridi.cloud/" "94.131.87.121"
        $Resources += New-Resource "proxy-s3-eu" "Storage Proxy EU" "https://proxy.s3.eu.iridi.com/" "72.56.68.146"
        $Resources += New-Resource "ping" "Control Endpoint" "https://ping.iridiummobile.net/" "52.222.136.36"
        $Resources += New-Resource "s3-eu" "Project Storage EU" "https://s3.eu.iridi.com/" "95.217.164.135"
    }
    "bus77-home" {
        $ProductLabel = "Bus77 Home"
        $GateHosts = @("37.27.5.98", "85.192.35.27")
        $QualityLatencyUrl = "https://auth.ru.iridi.com/"
        $QualityLatencyLabel = "Authorization RU"
        $QualityThroughputUrl = "https://www.iridi.com/"
        $QualityThroughputLabel = "iRidi portal (www.iridi.com)"
        $QualityMtuHost = "auth.ru.iridi.com"
        $Resources = Add-CommonBus77Resources `
            "bus77home.ru.iridi.com" `
            "Bus77 Home Cloud" `
            "iphubhome.ru.iridi.com" `
            "IP-Hub Home Cloud" `
            "37.139.42.137"
    }
    "bus77-lite" {
        $ProductLabel = "Bus77 Lite"
        $GateHosts = @("37.27.5.98", "85.192.35.27")
        $QualityLatencyUrl = "https://auth.ru.iridi.com/"
        $QualityLatencyLabel = "Authorization RU"
        $QualityThroughputUrl = "https://www.iridi.com/"
        $QualityThroughputLabel = "iRidi portal (www.iridi.com)"
        $QualityMtuHost = "auth.ru.iridi.com"
        $Resources = Add-CommonBus77Resources `
            "bus77lite.ru.iridi.com" `
            "Bus77 Lite Cloud" `
            "iphub.ru.iridi.com" `
            "IP-Hub Lite Cloud" `
            "51.250.30.171"
    }
    "iridi-pro" {
        $ProductLabel = "iRidi Pro " + $Region
        if ($Region -eq "EU") {
            $GateHosts = @("37.27.5.98")
            $QualityLatencyUrl = "https://auth.eu.iridi.com/"
            $QualityLatencyLabel = "Authorization EU"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update service (iridi.com)"
            $QualityMtuHost = "auth.eu.iridi.com"
            $Resources += New-Resource "auth-eu" "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-eu" "i3 Pro Cloud EU" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-eu" "AWS Storage EU" "https://s3.us-east-1.amazonaws.com/" "dynamic"
            $Resources += New-Resource "projects-eu" "i3 Pro Projects EU" "https://iridium-cloud-files.s3.amazonaws.com/" "dynamic"
            $Resources += New-Resource "updates-site" "Update Service" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-s3" "Update Files (S3)" "http://iridium3download.s3.amazonaws.com/" "dynamic"
        } elseif ($Region -eq "CN") {
            $GateHosts = @("37.27.5.98")
            $QualityLatencyUrl = "https://auth.eu.iridi.com/"
            $QualityLatencyLabel = "Authorization CN (Global)"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update service (iridi.com)"
            $QualityMtuHost = "auth.eu.iridi.com"
            $Resources += New-Resource "auth-cn" "Authorization CN (Global)" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-cn" "i3 Pro Cloud CN" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-cn" "CN Object Storage" "https://ir-endpoint.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182"
            $Resources += New-Resource "projects-cn" "i3 Pro Projects CN" "https://ir-proj-sh.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182"
            $Resources += New-Resource "updates-site" "Update Service" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-cn" "CN Update Files" "http://iridium3download.oss-cn-hangzhou.aliyuncs.com/" "118.178.60.104"
        } else {
            $GateHosts = @("85.192.35.27")
            $QualityLatencyUrl = "https://auth.ru.iridi.com/"
            $QualityLatencyLabel = "Authorization RU"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update service (iridi.com)"
            $QualityMtuHost = "auth.ru.iridi.com"
            $Resources += New-Resource "auth-ru" "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245"
            $Resources += New-Resource "i3pro-ru" "i3 Pro Cloud RU" "https://i3pro.ru.iridi.com/" "84.201.152.245"
            $Resources += New-Resource "storage-ru" "RU Object Storage" "https://storage.yandexcloud.net/" "213.180.193.243"
            $Resources += New-Resource "projects-ru" "i3 Pro Projects RU" "https://i3pro.storage.yandexcloud.net/" "213.180.193.243"
            $Resources += New-Resource "updates-site" "Update Service" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-s3" "Update Files (S3)" "http://iridium3download.s3.amazonaws.com/" "dynamic"
        }
    }
}

Write-TechLog "================================================================================"
Write-TechLog ("iRidi Cloud Diagnostics (Windows) - Technical Log")
Write-TechLog ("Version: {0} | Product: {1} | Region: {2}" -f $ToolVersion, $ProductLabel, $Region)
Write-TechLog ("Host: {0} | OS: {1}" -f $env:COMPUTERNAME, [System.Environment]::OSVersion.VersionString)
Write-TechLog ("Log File: {0}" -f $LogPath)
Write-TechLog "================================================================================"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ("  iRidi Cloud Diagnostics — {0} (v{1})" -f $ProductLabel, $ToolVersion) -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ("Host: {0} | OS: Windows ({1})" -f $env:COMPUTERNAME, [System.Environment]::OSVersion.Version.ToString())
if ($Quality) {
    Write-Host "Mode: Extended Quality & Stability Analysis" -ForegroundColor Cyan
}
Write-Host ""

function Test-HttpResource {
    param($Resource)

    $uri = New-Object System.Uri($Resource.Url)
    $resolvedAddresses = @()
    try {
        $hostAddresses = [System.Net.Dns]::GetHostAddresses($uri.Host)
        foreach ($address in $hostAddresses) {
            $resolvedAddresses += $address.IPAddressToString
        }
    } catch {
    }

    if ($resolvedAddresses.Count -gt 0) {
        $dnsText = [System.String]::Join(", ", [string[]]$resolvedAddresses)
    } else {
        $dnsText = "unresolved"
    }

    Write-TechLog ("PROBE START: {0} ({1})" -f $Resource.Label, $Resource.Url)
    Write-TechLog ("  Host: {0} -> DNS: {1} (Expected: {2})" -f $uri.Host, $dnsText, $Resource.ExpectedIp)

    $attempt = 1
    $response = $null
    $statusCode = 0
    $contentType = "not provided"
    $payloadBytes = 0
    $lastError = ""
    $elapsedSeconds = 0

    while ($attempt -le $MaxAttempts) {
        $response = $null
        $lastError = ""
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $request = [System.Net.HttpWebRequest]::Create($Resource.Url)
            $request.Method = "GET"
            $request.UserAgent = "iridi-diag/windows-$Product/$ToolVersion"
            $request.Accept = "application/json, text/plain, */*"
            $request.AllowAutoRedirect = $true
            $request.MaximumAutomaticRedirections = 3
            $request.Timeout = $RequestTimeoutMilliseconds
            $request.ReadWriteTimeout = $RequestTimeoutMilliseconds
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            if ($_.Exception.Response -ne $null) {
                $response = $_.Exception.Response
            } else {
                $lastError = $_.Exception.Message
            }
        } catch {
            $lastError = $_.Exception.Message
        }
        $stopwatch.Stop()
        $elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)

        Write-TechLog ("  Attempt {0}/{1}: code={2} elapsed={3}s error={4}" -f $attempt, $MaxAttempts, $statusCode, $elapsedSeconds, $lastError)

        if ($response -ne $null) {
            break
        }
        if ($attempt -ge $MaxAttempts) {
            break
        }
        Start-Sleep -Seconds $RetryDelaySeconds
        $attempt = $attempt + 1
    }

    if ($response -ne $null) {
        try {
            $statusCode = [int]$response.StatusCode
            if ($response.ContentType) {
                $contentType = [string]$response.ContentType
            }
            $stream = $response.GetResponseStream()
            if ($stream -ne $null) {
                $buffer = New-Object byte[] 8192
                do {
                    $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                    $payloadBytes = $payloadBytes + $bytesRead
                } while ($bytesRead -gt 0)
                $stream.Close()
            }
        } catch {
            $lastError = $_.Exception.Message
        }
        try {
            $response.Close()
        } catch {
        }
    }

    $elapsedMs = [int]($elapsedSeconds * 1000)
    $ipInfo = if ($resolvedAddresses.Count -gt 0) { $resolvedAddresses[0] } else { "unresolved" }
    $ipMismatch = $false
    if (($Resource.ExpectedIp -ne "dynamic") -and ($resolvedAddresses.Count -gt 0)) {
        if (-not ($resolvedAddresses -contains $Resource.ExpectedIp)) {
            $ipMismatch = $true
        }
    }

    $isOk = ($statusCode -ge 200) -and ($statusCode -lt 500)
    $labelPadded = $Resource.Label.PadRight(26)

    if ($isOk) {
        if ($ipMismatch -or ($attempt -gt 1)) {
            $script:WarningCount = $script:WarningCount + 1
            Write-Host "  [ATTENTION] " -ForegroundColor Yellow -NoNewline
            Write-Host ("{0} {1} (HTTP {2}, {3}ms, IP: {4})" -f $labelPadded, $uri.Host, $statusCode, $elapsedMs, $ipInfo)
            if ($attempt -gt 1) {
                Write-Host ("              ! Succeeded on retry attempt {0} of {1}" -f $attempt, $MaxAttempts) -ForegroundColor DarkGray
            }
            if ($ipMismatch) {
                Write-Host ("              ! Actual IP ({0}) differs from documented ({1})" -f $ipInfo, $Resource.ExpectedIp) -ForegroundColor DarkGray
            }
            Write-TechLog ("PROBE RESULT: ATTENTION for {0}" -f $Resource.Label)
        } else {
            Write-Host "  [OK]        " -ForegroundColor Green -NoNewline
            Write-Host ("{0} {1} (HTTP {2}, {3}ms, IP: {4})" -f $labelPadded, $uri.Host, $statusCode, $elapsedMs, $ipInfo)
            Write-TechLog ("PROBE RESULT: OK for {0}" -f $Resource.Label)
        }
        return $true
    } else {
        Write-Host "  [NOT OK]    " -ForegroundColor Red -NoNewline
        Write-Host ("{0} {1} (HTTP {2}, {3})" -f $labelPadded, $uri.Host, $statusCode, $ipInfo)
        if ($lastError) {
            Write-Host ("              ! Error: {0}" -f $lastError) -ForegroundColor Red
        }
        Write-TechLog ("PROBE RESULT: FAIL for {0} (HTTP {1}, error: {2})" -f $Resource.Label, $statusCode, $lastError)
        return $false
    }
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port
    )

    $client = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $null
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($GateTimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $client.Connected
    } catch {
        return $false
    } finally {
        if ($asyncResult -ne $null) {
            try {
                $asyncResult.AsyncWaitHandle.Close()
            } catch {
            }
        }
        $client.Close()
    }
}

function Test-QualityLatency {
    param([string]$Url, [string]$Label)

    Write-Host ("  • Latency & Loss ({0}):" -f $Label)
    Write-TechLog ("QUALITY LATENCY: target={0}" -f $Url)

    $successCount = 0
    $totalCount = 10
    $times = @()

    for ($i = 1; $i -le $totalCount; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "GET"
            $req.UserAgent = "iridi-diag/windows-$Product/$ToolVersion"
            $req.Timeout = 5000
            $resp = $req.GetResponse()
            $sw.Stop()
            $resp.Close()
            $times += $sw.ElapsedMilliseconds
            $successCount++
            Write-TechLog ("    Probe {0}/{1}: {2}ms" -f $i, $totalCount, $sw.ElapsedMilliseconds)
        } catch {
            $sw.Stop()
            Write-TechLog ("    Probe {0}/{1}: FAILED ({2})" -f $i, $totalCount, $_.Exception.Message)
        }
    }

    $loss = [int]((($totalCount - $successCount) * 100) / $totalCount)
    if ($successCount -gt 0) {
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        $avg = [int](($times | Measure-Object -Average).Average)

        if ($loss -eq 0) {
            if ($avg -gt 1000) {
                Write-Host "    [ATTENTION] " -ForegroundColor Yellow -NoNewline
                Write-Host ("0% loss | min {0}ms, avg {1}ms, max {2}ms (high latency)" -f $min, $avg, $max)
                $script:WarningCount = $script:WarningCount + 1
            } else {
                Write-Host "    [OK]        " -ForegroundColor Green -NoNewline
                Write-Host ("0% loss (10/10) | min {0}ms, avg {1}ms, max {2}ms" -f $min, $avg, $max)
            }
        } elseif ($loss -le 20) {
            Write-Host "    [ATTENTION] " -ForegroundColor Yellow -NoNewline
            Write-Host ("{0}% packet loss ({1}/{2}) | min {3}ms, avg {4}ms, max {5}ms" -f $loss, $successCount, $totalCount, $min, $avg, $max)
            $script:WarningCount = $script:WarningCount + 1
        } else {
            Write-Host "    [NOT OK]    " -ForegroundColor Red -NoNewline
            Write-Host ("{0}% packet loss ({1}/{2}) | connection unstable" -f $loss, $successCount, $totalCount)
            $script:WarningCount = $script:WarningCount + 1
        }
    } else {
        Write-Host "    [NOT OK]    " -ForegroundColor Red -NoNewline
        Write-Host ("100% packet loss (0/{0} probes succeeded)" -f $totalCount)
        $script:WarningCount = $script:WarningCount + 1
    }
}

function Test-QualityThroughput {
    param([string]$Url, [string]$Label)

    Write-Host ("  • Download Throughput ({0}):" -f $Label)
    Write-TechLog ("QUALITY THROUGHPUT: target={0}" -f $Url)

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = "GET"
        $req.UserAgent = "iridi-diag/windows-$Product/$ToolVersion"
        $req.Timeout = 15000
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $buffer = New-Object byte[] 65536
        $totalBytes = 0
        do {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $totalBytes += $read
        } while ($read -gt 0)
        $stream.Close()
        $resp.Close()
        $sw.Stop()

        $seconds = $sw.Elapsed.TotalSeconds
        if ($seconds -gt 0 -and $totalBytes -gt 0) {
            $bytesPerSec = $totalBytes / $seconds
            $kbPerSec = [int]($bytesPerSec / 1024)
            $transferredKb = [int]($totalBytes / 1024)
            $timeFmt = [Math]::Round($seconds, 2)

            $speedStr = ""
            if ($kbPerSec -ge 1024) {
                $mbVal = [Math]::Round(($kbPerSec / 1024), 2)
                $speedStr = "{0} MB/s" -f $mbVal
            } else {
                $speedStr = "{0} KB/s" -f $kbPerSec
            }

            Write-TechLog ("    Throughput: {0} ({1} KB in {2}s)" -f $speedStr, $transferredKb, $timeFmt)

            if ($kbPerSec -lt 128) {
                Write-Host "    [ATTENTION] " -ForegroundColor Yellow -NoNewline
                Write-Host ("{0} ({1} KB in {2}s) — low speed for large projects" -f $speedStr, $transferredKb, $timeFmt)
                $script:WarningCount = $script:WarningCount + 1
            } else {
                Write-Host "    [OK]        " -ForegroundColor Green -NoNewline
                Write-Host ("{0} ({1} KB in {2}s)" -f $speedStr, $transferredKb, $timeFmt)
            }
        }
    } catch {
        Write-Host "    [INFO]      Throughput test skipped or endpoint protected" -ForegroundColor DarkGray
        Write-TechLog ("    Throughput failed: {0}" -f $_.Exception.Message)
    }
}

function Test-QualityGateBurst {
    param($Hosts)

    Write-Host "  • Gate Burst Stability:"
    Write-TechLog ("QUALITY GATE BURST: hosts={0}" -f ($Hosts -join ", "))

    foreach ($gh in $Hosts) {
        foreach ($port in @(9088, 9089)) {
            $gOk = 0
            $times = @()
            for ($try = 1; $try -le 3; $try++) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                if (Test-TcpPort -HostName $gh -Port $port) {
                    $sw.Stop()
                    $gOk++
                    $times += $sw.ElapsedMilliseconds
                } else {
                    $sw.Stop()
                }
            }

            $endpointStr = ("{0}:{1}" -f $gh, $port).PadRight(21)
            if ($gOk -eq 3) {
                $avg = [int](($times | Measure-Object -Average).Average)
                Write-Host "    [OK]        " -ForegroundColor Green -NoNewline
                Write-Host ("{0} 3/3 connections (avg handshake: {1}ms)" -f $endpointStr, $avg)
            } elseif ($gOk -gt 0) {
                Write-Host "    [ATTENTION] " -ForegroundColor Yellow -NoNewline
                Write-Host ("{0} {1}/3 connections (intermittent resets)" -f $endpointStr, $gOk)
                $script:WarningCount = $script:WarningCount + 1
            } else {
                Write-Host "    [NOT OK]    " -ForegroundColor Red -NoNewline
                Write-Host ("{0} 0/3 connections failed" -f $endpointStr)
                $script:WarningCount = $script:WarningCount + 1
            }
        }
    }
}

function Test-QualityMtu {
    param([string]$TargetHost)

    Write-Host "  • Path MTU & Packet Fragmentation:"
    Write-TechLog ("QUALITY MTU: host={0}" -f $TargetHost)

    try {
        $pinger = New-Object System.Net.NetworkInformation.Ping
        $options = New-Object System.Net.NetworkInformation.PingOptions
        $options.DontFragment = $true
        $buffer1500 = New-Object byte[] 1472

        $reply = $pinger.Send($TargetHost, 3000, $buffer1500, $options)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            Write-Host "    [OK]        Standard 1500-byte MTU supported without fragmentation" -ForegroundColor Green
            Write-TechLog "    MTU 1500: OK"
            return
        }

        $buffer1400 = New-Object byte[] 1372
        $reply2 = $pinger.Send($TargetHost, 3000, $buffer1400, $options)
        if ($reply2.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            Write-Host "    [ATTENTION] 1500-byte dropped, 1400-byte passed (MSS clamping/VPN active)" -ForegroundColor Yellow
            $script:WarningCount = $script:WarningCount + 1
            Write-TechLog "    MTU 1500: FAILED, MTU 1400: OK"
        } else {
            Write-Host "    [ATTENTION] Large ICMP frames dropped (network restricted)" -ForegroundColor Yellow
            $script:WarningCount = $script:WarningCount + 1
            Write-TechLog "    MTU Large: FAILED"
        }
    } catch {
        Write-Host "    [INFO]      Ping utility or ICMP restricted; MTU test skipped" -ForegroundColor DarkGray
        Write-TechLog ("    MTU check error: {0}" -f $_.Exception.Message)
    }
}

# --- 1. Cloud HTTP Services ---
Write-Host "1. Cloud HTTP/HTTPS Services:" -ForegroundColor White

foreach ($r in $Resources) {
    $script:HttpTotal++
    if (Test-HttpResource -Resource $r) {
        $script:HttpOk++
    } else {
        $script:HttpFail++
    }
}

# --- 2. Gate TCP ---
Write-Host ""
Write-Host "2. Cloud Gate TCP Connectivity (ports 9088/9089):" -ForegroundColor White
$GateOk = 0
$GateTotal = 0

foreach ($gh in $GateHosts) {
    foreach ($port in @(9088, 9089)) {
        $GateTotal++
        $endpointStr = ("{0}:{1}" -f $gh, $port).PadRight(21)
        if (Test-TcpPort -HostName $gh -Port $port) {
            Write-Host "  [OK]        " -ForegroundColor Green -NoNewline
            Write-Host ("{0} (TCP port connected successfully)" -f $endpointStr)
            $GateOk++
            Write-TechLog ("  Gate TCP {0}:{1}: OK" -f $gh, $port)
        } else {
            Write-Host "  [ATTENTION] " -ForegroundColor Yellow -NoNewline
            Write-Host ("{0} (connection timeout after {1}s)" -f $endpointStr, ($GateTimeoutMilliseconds/1000))
            $script:WarningCount = $script:WarningCount + 1
            Write-TechLog ("  Gate TCP {0}:{1}: TIMEOUT" -f $gh, $port)
        }
    }
}

$GateStatus = ""
$GateFailed = $false
if ($GateOk -eq 0) {
    $GateStatus = ("not reachable (0 of {0})" -f $GateTotal)
    Write-Host "  [NOT OK]    No Cloud Gate endpoints accepted a connection" -ForegroundColor Red
    $GateFailed = $true
} else {
    $GateStatus = ("reachable ({0} of {1})" -f $GateOk, $GateTotal)
}

# --- 3. Quality Tests ---
if ($Quality) {
    Write-Host ""
    Write-Host "3. Extended Channel Quality & Stability Analysis:" -ForegroundColor White
    Test-QualityLatency -Url $QualityLatencyUrl -Label $QualityLatencyLabel
    Test-QualityThroughput -Url $QualityThroughputUrl -Label $QualityThroughputLabel
    Test-QualityGateBurst -Hosts $GateHosts
    Test-QualityMtu -TargetHost $QualityMtuHost
}

# --- Summary ---
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTIC SUMMARY" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ("HTTP Services: {0} of {1} available ({2} failed)" -f $HttpOk, $HttpTotal, $HttpFail)
Write-Host ("Cloud Gate:    {0}" -f $GateStatus)
Write-Host ("Warnings:      {0}" -f $WarningCount)

Write-TechLog ("SUMMARY: total={0} ok={1} fail={2} warn={3} gate_status={4}" -f $HttpTotal, $HttpOk, $HttpFail, $WarningCount, $GateStatus)

if (($HttpFail -gt 0) -or $GateFailed) {
    Write-Host ""
    Write-Host "RESULT: FAIL — One or more critical cloud resources are unavailable." -ForegroundColor Red
    Write-Host ("Detailed technical log: {0}`n" -f $LogPath)
    Write-TechLog "RESULT: FAIL"
    exit 2
}

if ($WarningCount -gt 0) {
    Write-Host ""
    Write-Host "RESULT: WARN — Cloud services are reachable, but warnings were detected." -ForegroundColor Yellow
    Write-Host ("Detailed technical log: {0}`n" -f $LogPath)
    Write-TechLog "RESULT: WARN"
    exit 1
}

Write-Host ""
Write-Host "RESULT: PASS — All required cloud resources and Cloud Gate are reachable." -ForegroundColor Green
if (-not $Quality) {
    Write-Host "Tip: For deeper channel quality and latency benchmarks, run with: -Quality" -ForegroundColor DarkGray
}
Write-Host ("Detailed technical log: {0}`n" -f $LogPath)
Write-TechLog "RESULT: PASS"
exit 0
