# iRidi cloud diagnostics for Windows 10/11 and Windows PowerShell 5.1.
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

function Write-Status {
    param(
        [ValidateSet("OK", "ATTENTION", "NOT OK")]
        [string]$Level,
        [string]$Message
    )

    $line = "[{0}] {1}" -f $Level, $Message
    switch ($Level) {
        "OK" { Write-Host $line -ForegroundColor Green }
        "ATTENTION" { Write-Host $line -ForegroundColor Yellow }
        "NOT OK" { Write-Host $line -ForegroundColor Red }
    }
}

if (-not $Product) {
    while (-not $Product) {
        Clear-Host
        Write-Host "iRidi Cloud Diagnostics"
        Write-Host "======================="
        Write-Host "1. i3 KNX"
        Write-Host "2. Bus77 Home"
        Write-Host "3. Bus77 Lite"
        Write-Host "4. iRidi Pro - RU region"
        Write-Host "5. iRidi Pro - EU region"
        Write-Host "6. iRidi Pro - CN region"
        Write-Host "0. Exit"
        Write-Host ""
        $selection = Read-Host "Select product (0-6)"
        switch ($selection) {
            "1" { $Product = "i3knx" }
            "2" { $Product = "bus77-home" }
            "3" { $Product = "bus77-lite" }
            "4" { $Product = "iridi-pro"; $Region = "RU" }
            "5" { $Product = "iridi-pro"; $Region = "EU" }
            "6" { $Product = "iridi-pro"; $Region = "CN" }
            "0" { exit 10 }
            default {
                Write-Host "Invalid selection. Press Enter and try again."
                [void](Read-Host)
                continue
            }
        }
        Write-Host ""
        $qualChoice = Read-Host "Run extended quality & stability analysis (latency, loss, throughput, MTU)? (y/n)"
        if ($qualChoice -match "^[yY]") { $Quality = $true }
    }
}

$Product = $Product.ToLowerInvariant()
$SupportedProducts = @("i3knx", "bus77-home", "bus77-lite", "iridi-pro")
if (-not ($SupportedProducts -contains $Product)) {
    Write-Status "NOT OK" ("Unknown product: {0}" -f $Product)
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
    [void](New-Item -ItemType Directory -Path $LogDirectory)
}
$LogProduct = $Product.Replace("-", "_")
if ($Product -eq "iridi-pro") {
    $LogProduct = $LogProduct + "_" + $Region.ToLowerInvariant()
}
$LogPath = Join-Path $LogDirectory ($LogProduct + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
$TranscriptStarted = $false
try {
    Start-Transcript -Path $LogPath | Out-Null
    $TranscriptStarted = $true
} catch {
    Write-Status "ATTENTION" ("Could not start the log file: {0}" -f $_.Exception.Message)
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Status "ATTENTION" "Windows PowerShell 5.1 is recommended for this script."
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

# TLS 1.2 is required by modern cloud services. Numeric value 3072 keeps this
# script parseable on old .NET versions where the Tls12 enum name is absent.
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Enum]::ToObject(
        [System.Net.SecurityProtocolType],
        3072
    )
} catch {
}

# Certificate trust is intentionally not part of this reachability diagnostic.
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
    $items += New-Resource "www" "Website and downloads" "https://www.iridi.com/" "89.169.183.139"
    $items += New-Resource "auth-ru" "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245"
    $items += New-Resource "endpoint" "Cloud endpoint" "https://endpoint.iridi.com/" "95.181.182.182"
    $items += New-Resource "bus77" $ProductLabel ("https://" + $ProductHost + "/") "84.201.152.245"
    $items += New-Resource "iphub" $IpHubLabel ("https://" + $IpHubHost + "/") $IpHubIp
    $items += New-Resource "commercial" "Commercial offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191"
    $items += New-Resource "voice-cws" "Voice assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60"
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
        $Resources += New-Resource "www" "Website and downloads" "https://www.iridi.com/" "89.169.183.139"
        $Resources += New-Resource "auth-eu" "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71"
        $Resources += New-Resource "proxy-auth-eu" "Authorization proxy EU" "https://proxy.auth.eu.iridi.com/" "72.56.78.171"
        $Resources += New-Resource "proxy-auth-cloud" "Authorization proxy Cloud" "https://proxy.auth.eu.iridi.cloud/" "94.131.83.102"
        $Resources += New-Resource "i3knx-eu" "i3 KNX cloud EU" "https://i3knx.eu.iridi.com/" "95.216.162.71"
        $Resources += New-Resource "proxy-i3knx-eu" "i3 KNX proxy EU" "https://proxy.i3knx.eu.iridi.com/" "147.45.238.146"
        $Resources += New-Resource "proxy-knx-cloud" "KNX proxy Cloud" "https://proxy.knx.eu.iridi.cloud/" "94.131.87.121"
        $Resources += New-Resource "proxy-s3-eu" "Storage proxy EU" "https://proxy.s3.eu.iridi.com/" "72.56.68.146"
        $Resources += New-Resource "ping" "Control endpoint" "https://ping.iridiummobile.net/" "52.222.136.36"
        $Resources += New-Resource "s3-eu" "Project storage EU" "https://s3.eu.iridi.com/" "95.217.164.135"
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
            "Bus77 Home cloud" `
            "iphubhome.ru.iridi.com" `
            "IP-Hub Home cloud" `
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
            "Bus77 Lite cloud" `
            "iphub.ru.iridi.com" `
            "IP-Hub Lite cloud" `
            "51.250.30.171"
    }
    "iridi-pro" {
        $Region = $Region.ToUpperInvariant()
        $ProductLabel = "iRidi Pro " + $Region
        if ($Region -eq "EU") {
            $GateHosts = @("37.27.5.98")
            $QualityLatencyUrl = "https://auth.eu.iridi.com/"
            $QualityLatencyLabel = "Authorization EU"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update website (iridi.com)"
            $QualityMtuHost = "auth.eu.iridi.com"
            $Resources += New-Resource "auth-eu" "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-eu" "i3 Pro cloud EU" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-eu" "AWS storage EU" "https://s3.us-east-1.amazonaws.com/" "dynamic"
            $Resources += New-Resource "projects-eu" "i3 Pro projects EU" "https://iridium-cloud-files.s3.amazonaws.com/" "dynamic"
            $Resources += New-Resource "updates-site" "Update website" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-s3" "Update files" "http://iridium3download.s3.amazonaws.com/" "dynamic"
        } elseif ($Region -eq "CN") {
            $GateHosts = @("37.27.5.98")
            $QualityLatencyUrl = "https://auth.eu.iridi.com/"
            $QualityLatencyLabel = "Authorization CN (Global)"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update website (iridi.com)"
            $QualityMtuHost = "auth.eu.iridi.com"
            $Resources += New-Resource "auth-cn" "Authorization CN" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-cn" "i3 Pro cloud CN" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-cn" "Alibaba storage CN" "https://ir-endpoint.oss-cn-shanghai.aliyuncs.com/" "dynamic"
            $Resources += New-Resource "projects-cn" "i3 Pro projects CN" "https://ir-proj-sh.oss-cn-shanghai.aliyuncs.com/" "dynamic"
            $Resources += New-Resource "updates-site" "Update website" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-cn" "CN update files" "http://iridium3download.oss-cn-hangzhou.aliyuncs.com/" "dynamic"
        } else {
            $GateHosts = @("85.192.35.27")
            $QualityLatencyUrl = "https://auth.ru.iridi.com/"
            $QualityLatencyLabel = "Authorization RU"
            $QualityThroughputUrl = "http://iridi.com/"
            $QualityThroughputLabel = "Update website (iridi.com)"
            $QualityMtuHost = "auth.ru.iridi.com"
            $Resources += New-Resource "auth-ru" "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245"
            $Resources += New-Resource "i3pro-ru" "i3 Pro cloud RU" "https://i3pro.ru.iridi.com/" "84.201.152.245"
            $Resources += New-Resource "storage-ru" "Yandex storage RU" "https://storage.yandexcloud.net/" "213.180.193.243"
            $Resources += New-Resource "projects-ru" "i3 Pro projects RU" "https://i3pro.storage.yandexcloud.net/" "213.180.193.243"
            $Resources += New-Resource "updates-site" "Update website" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-s3" "Update files" "http://iridium3download.s3.amazonaws.com/" "dynamic"
        }
    }
}

function Write-Separator {
    Write-Host "----------------------------------------------------------------"
}

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
        $dnsText = "not resolved"
    }

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
            $request.UserAgent = "iridi-cloud-check-windows/1.0"
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

    Write-Separator
    Write-Host $Resource.Label
    Write-Host ("  URL:              {0}" -f $Resource.Url)
    Write-Host ("  DNS:              {0} -> {1}" -f $uri.Host, $dnsText)
    Write-Host ("  Documented IP:    {0}" -f $Resource.ExpectedIp)
    Write-Host ("  Attempt:          {0} of {1}" -f $attempt, $MaxAttempts)
    Write-Host ("  HTTP response:    {0}" -f $statusCode)
    Write-Host ("  Content-Type:     {0}" -f $contentType)
    Write-Host ("  Payload:          {0} bytes" -f $payloadBytes)
    Write-Host ("  Request time:     {0} s" -f $elapsedSeconds)

    if (($Resource.ExpectedIp -ne "dynamic") -and ($resolvedAddresses.Count -gt 0)) {
        if (-not ($resolvedAddresses -contains $Resource.ExpectedIp)) {
            Write-Status "ATTENTION" "DNS addresses differ from the documented IP (a CDN or proxy may be in use)."
            $script:WarningCount = $script:WarningCount + 1
        }
    }

    if (($statusCode -ge 200) -and ($statusCode -lt 500)) {
        if ($attempt -gt 1) {
            Write-Status "ATTENTION" "The response was received after a retry; the connection may be unstable."
            $script:WarningCount = $script:WarningCount + 1
        }
        Write-Status "OK" "Application-level HTTP response and payload received."
        return $true
    }

    if ($statusCode -ge 500) {
        Write-Status "NOT OK" ("The service returned HTTP {0}." -f $statusCode)
    } else {
        Write-Status "NOT OK" ("No HTTP response after {0} attempts." -f $attempt)
        if ($lastError) {
            Write-Host ("  Error: {0}" -f $lastError)
        }
    }
    return $false
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
    Write-Host ("1. Latency & Packet Loss test (10 probes to {0}):" -f $Label)
    Write-Host -NoNewline "  Probing: "
    $success = 0
    $total = 10
    $times = @()

    for ($i = 1; $i -le $total; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Method = "GET"
            $request.Timeout = 5000
            $request.UserAgent = $UserAgent
            $response = $request.GetResponse()
            $sw.Stop()
            $response.Close()
            $times += $sw.ElapsedMilliseconds
            $success++
            Write-Host -NoNewline "."
        } catch [System.Net.WebException] {
            $sw.Stop()
            if ($_.Response -ne $null) {
                $times += $sw.ElapsedMilliseconds
                $success++
                Write-Host -NoNewline "."
                $_.Response.Close()
            } else {
                Write-Host -NoNewline "x"
            }
        } catch {
            Write-Host -NoNewline "x"
        }
    }
    Write-Host ""

    $loss = [int]((($total - $success) * 100) / $total)
    if ($success -gt 0) {
        $measure = $times | Measure-Object -Average -Minimum -Maximum
        Write-Host ("  Requests succeeded: {0} of {1} ({2}% loss)" -f $success, $total, $loss)
        Write-Host ("  Latency (RTT):      min {0}ms | avg {1}ms | max {2}ms" -f $measure.Minimum, [int]$measure.Average, $measure.Maximum)
        if ($loss -eq 0) {
            if ($measure.Average -gt 1000) {
                Write-Status "ATTENTION" "All requests succeeded, but average latency is high (> 1000 ms)."
                $script:WarningCount++
            } else {
                Write-Status "OK" "Connection latency is stable with 0% packet loss."
            }
        } elseif ($loss -le 20) {
            Write-Status "ATTENTION" ("Minor packet/request loss detected ({0}%). Connection may experience intermittent drops." -f $loss)
            $script:WarningCount++
        } else {
            Write-Status "NOT OK" ("High packet/request loss detected ({0}%). Connection is unstable." -f $loss)
            $script:WarningCount++
        }
    } else {
        Write-Host ("  Requests succeeded: 0 of {0} (100% loss)" -f $total)
        Write-Status "NOT OK" "All quality probes failed. Connection is unavailable or blocked."
        $script:WarningCount++
    }
}

function Test-QualityThroughput {
    param([string]$Url, [string]$Label)
    Write-Host ("2. Bandwidth & Download Throughput ({0}):" -f $Label)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.Timeout = 15000
        $request.UserAgent = $UserAgent
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] 65536
        $totalBytes = 0
        $read = 0
        do {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $totalBytes += $read
        } while ($read -gt 0)
        $sw.Stop()
        $stream.Close()
        $response.Close()

        $elapsedSec = [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $kbPerSec = [int](($totalBytes / 1024) / $elapsedSec)
        $downloadedKb = [int]($totalBytes / 1024)

        if ($kbPerSec -ge 1024) {
            $speedFmt = "{0:N2} MB/s" -f ($kbPerSec / 1024)
        } else {
            $speedFmt = "{0} KB/s" -f $kbPerSec
        }
        Write-Host ("  Download speed:     {0} ({1} KB transferred in {2:N2}s)" -f $speedFmt, $downloadedKb, $elapsedSec)
        if ($kbPerSec -lt 128) {
            Write-Status "ATTENTION" "Download speed is low (< 128 KB/s). Large project uploads or downloads may be slow."
            $script:WarningCount++
        } else {
            Write-Status "OK" "Download throughput is sufficient for project transfers and asset syncing."
        }
    } catch {
        Write-Host "  [INFO] Throughput benchmark endpoint timed out or returned no data."
    }
}

function Test-QualityGate {
    param([string[]]$GateHostList)
    Write-Host "3. Cloud Gate Connection Stability (burst connect & timing):"
    foreach ($gh in $GateHostList) {
        foreach ($port in @(9088, 9089)) {
            Write-Host -NoNewline ("  Testing {0}:{1} (3 attempts) ... " -f $gh, $port)
            $gOk = 0
            $gTimes = @()
            for ($try = 1; $try -le 3; $try++) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                if (Test-TcpPort $gh $port) {
                    $sw.Stop()
                    $gOk++
                    $gTimes += $sw.ElapsedMilliseconds
                } else {
                    $sw.Stop()
                }
            }
            if ($gOk -eq 3) {
                $avgHandshake = [int]($gTimes | Measure-Object -Average).Average
                Write-Host ("[OK] 3/3 connected (avg handshake: {0}ms)" -f $avgHandshake) -ForegroundColor Green
            } elseif ($gOk -gt 0) {
                Write-Host ("[ATTENTION] {0} of 3 connected (intermittent TCP drops)" -f $gOk) -ForegroundColor Yellow
                $script:WarningCount++
            } else {
                Write-Host "[NOT OK] 0 of 3 connected" -ForegroundColor Red
                $script:WarningCount++
            }
        }
    }
}

function Test-QualityMtu {
    param([string]$TargetHost)
    Write-Host ("4. Path MTU & Packet Size test (target: {0}):" -f $TargetHost)
    try {
        $p1 = Test-Connection -ComputerName $TargetHost -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $p1) {
            Write-Host "  [INFO] ICMP ping is filtered or unacknowledged by target host; MTU test skipped."
            return
        }
        $p1500 = Test-Connection -ComputerName $TargetHost -Count 2 -BufferSize 1472 -DontFragment -Quiet -ErrorAction SilentlyContinue
        if ($p1500) {
            Write-Status "OK" "Standard 1500-byte MTU packets pass without fragmentation drops."
        } else {
            $p1400 = Test-Connection -ComputerName $TargetHost -Count 2 -BufferSize 1372 -DontFragment -Quiet -ErrorAction SilentlyContinue
            if ($p1400) {
                Write-Status "ATTENTION" "1500-byte packets were dropped, but 1400-byte packets passed (possible VPN/PPPoE MSS clamping issue)."
                $script:WarningCount++
            } else {
                Write-Status "ATTENTION" "Large ICMP packets were dropped (network may restrict packet size or disallow large frames)."
                $script:WarningCount++
            }
        }
    } catch {
        Write-Host "  [INFO] MTU test could not be completed; skipped."
    }
}

Write-Host ("iRidi Cloud Check - {0}" -f $ProductLabel)
Write-Host ("Target: Windows 10/11 / Windows PowerShell 5.1")
if ($Quality) {
    Write-Host "Mode: Extended quality, latency, MTU, and stability analysis"
} else {
    Write-Host "Mode: Standard reachability pre-flight (run with -Quality for extended tests)"
}
Write-Host ("Started: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"))
Write-Host ("Computer: {0}" -f $env:COMPUTERNAME)
Write-Host ("Log file: {0}" -f $LogPath)
Write-Host "Method: DNS + real HTTP(S) GET + payload read + Cloud Gate TCP connection"

foreach ($resource in $Resources) {
    $HttpTotal = $HttpTotal + 1
    if (Test-HttpResource $resource) {
        $HttpOk = $HttpOk + 1
    } else {
        $HttpFail = $HttpFail + 1
    }
}

Write-Separator
Write-Host "Cloud Gate TCP connectivity"
$GateTotal = 0
$GateOk = 0
foreach ($gateHost in $GateHosts) {
    foreach ($gatePort in @(9088, 9089)) {
        $GateTotal = $GateTotal + 1
        if (Test-TcpPort $gateHost $gatePort) {
            Write-Status "OK" ("{0}:{1} accepts TCP connections." -f $gateHost, $gatePort)
            $GateOk = $GateOk + 1
        } else {
            Write-Status "ATTENTION" ("{0}:{1} did not accept a TCP connection." -f $gateHost, $gatePort)
            $WarningCount = $WarningCount + 1
        }
    }
}

$GateFailed = $false
if ($GateOk -eq 0) {
    $GateFailed = $true
    Write-Status "NOT OK" "No documented Cloud Gate endpoint accepted a TCP connection."
} else {
    Write-Status "OK" ("Cloud Gate is reachable through {0} of {1} tested endpoints." -f $GateOk, $GateTotal)
}

if ($Quality) {
    Write-Separator
    Write-Host "EXTENDED QUALITY & STABILITY ANALYSIS"
    Test-QualityLatency $QualityLatencyUrl $QualityLatencyLabel
    Test-QualityThroughput $QualityThroughputUrl $QualityThroughputLabel
    Test-QualityGate $GateHosts
    Test-QualityMtu $QualityMtuHost
}

Write-Separator
Write-Host ("SUMMARY {0}: HTTP checked {1}, available {2}, failed {3}, warnings {4}" -f $ProductLabel, $HttpTotal, $HttpOk, $HttpFail, $WarningCount)
Write-Host ("Mode: {0}" -f ($(if ($Quality) { "extended quality & stability" } else { "standard reachability" })))
if (($HttpFail -eq 0) -and (-not $GateFailed)) {
    if ($WarningCount -gt 0) {
        Write-Host "RESULT: WARN - ATTENTION REQUIRED: required services are reachable, but warnings were found." -ForegroundColor Yellow
        $ExitCode = 1
    } else {
        Write-Host "RESULT: PASS - OK: required HTTP resources and Cloud Gate are reachable." -ForegroundColor Green
        $ExitCode = 0
    }
} else {
    Write-Host "RESULT: FAIL - NOT OK: one or more required cloud checks failed." -ForegroundColor Red
    $ExitCode = 2
}

Write-Host ("Log saved: {0}" -f $LogPath)
if (-not $Quality) {
    Write-Host ("`nTip: For deeper channel quality, latency, MTU, and throughput tests, re-run with: powershell.exe -File {0} -Product {1} -Quality" -f $MyInvocation.MyCommand.Name, $Product)
}
if ($TranscriptStarted) {
    Stop-Transcript | Out-Null
}
exit $ExitCode
