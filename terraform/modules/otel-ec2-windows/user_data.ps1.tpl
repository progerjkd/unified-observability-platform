<powershell>
$ErrorActionPreference = "Stop"

Write-Output "=== Installing OpenTelemetry Collector v${otel_version} ==="

$OtelVersion = "${otel_version}"
$MsiUrl = "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v$OtelVersion/otelcol-contrib_$${OtelVersion}_windows_amd64.msi"
$TempDir = "C:\Temp"
$ConfigDir = "C:\ProgramData\OpenTelemetry Collector"

# Create temp directory
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force
}

# Download MSI
Write-Output "Downloading OTel Collector MSI..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $MsiUrl -OutFile "$TempDir\otelcol.msi" -UseBasicParsing

# Install silently
Write-Output "Installing OTel Collector..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$TempDir\otelcol.msi`" /quiet /norestart"

# Ensure config directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force
}

# Create persistent queue directory
$QueueDir = "C:\ProgramData\otelcol\queue"
if (-not (Test-Path $QueueDir)) {
    New-Item -ItemType Directory -Path $QueueDir -Force
}

# Download config from S3
Write-Output "Downloading config from S3..."
Read-S3Object -BucketName "${config_bucket}" -Key "${config_key}" -File "$ConfigDir\config.yaml"

# Configure and start the service
Write-Output "Configuring Windows Service..."
$ServiceName = "OpenTelemetry Collector"

# Stop service if running
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Start service
Start-Service -Name $ServiceName
Set-Service -Name $ServiceName -StartupType Automatic

Write-Output "=== OpenTelemetry Collector installation complete ==="
</powershell>
