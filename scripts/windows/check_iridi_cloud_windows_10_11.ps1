# iRidi cloud diagnostics for Windows 10/11 and Windows PowerShell 5.1.
# Examples:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product i3knx
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product iridi-pro -Region EU

[CmdletBinding()]
param(
    [string]$Product = "",

    [ValidateSet("RU", "EU", "CN")]
    [string]$Region = "RU"
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
            }
        }
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
            $Resources += New-Resource "auth-eu" "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-eu" "i3 Pro cloud EU" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-eu" "AWS storage EU" "https://s3.us-east-1.amazonaws.com/" "dynamic"
            $Resources += New-Resource "projects-eu" "i3 Pro projects EU" "https://iridium-cloud-files.s3.amazonaws.com/" "dynamic"
            $Resources += New-Resource "updates-site" "Update website" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-s3" "Update files" "http://iridium3download.s3.amazonaws.com/" "dynamic"
        } elseif ($Region -eq "CN") {
            $GateHosts = @("37.27.5.98")
            $Resources += New-Resource "auth-cn" "Authorization CN" "https://auth.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "i3pro-cn" "i3 Pro cloud CN" "https://i3pro.eu.iridi.com/" "95.216.162.71"
            $Resources += New-Resource "storage-cn" "Alibaba storage CN" "https://ir-endpoint.oss-cn-shanghai.aliyuncs.com/" "dynamic"
            $Resources += New-Resource "projects-cn" "i3 Pro projects CN" "https://ir-proj-sh.oss-cn-shanghai.aliyuncs.com/" "dynamic"
            $Resources += New-Resource "updates-site" "Update website" "http://iridi.com/" "89.169.183.139"
            $Resources += New-Resource "updates-cn" "CN update files" "http://iridium3download.oss-cn-hangzhou.aliyuncs.com/" "dynamic"
        } else {
            $GateHosts = @("85.192.35.27")
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

Write-Host ("iRidi Cloud Check - {0}" -f $ProductLabel)
Write-Host ("Target: Windows 10/11 / Windows PowerShell 5.1")
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

Write-Separator
Write-Host ("SUMMARY {0}: HTTP checked {1}, available {2}, failed {3}, warnings {4}" -f $ProductLabel, $HttpTotal, $HttpOk, $HttpFail, $WarningCount)
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
if ($TranscriptStarted) {
    Stop-Transcript | Out-Null
}
exit $ExitCode
