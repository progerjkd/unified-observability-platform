#!/bin/bash
set -euo pipefail

echo "=== Installing OpenTelemetry Collector v${otel_version} ==="

# Create service user
useradd --system --no-create-home --shell /usr/sbin/nologin otelcol || true

# Download and install OTel Collector Contrib
OTEL_VERSION="${otel_version}"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
esac

curl -fsSL "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v$${OTEL_VERSION}/otelcol-contrib_$${OTEL_VERSION}_linux_$${ARCH}.tar.gz" \
  | tar xz -C /usr/local/bin otelcol-contrib

chmod +x /usr/local/bin/otelcol-contrib

# Create directories
mkdir -p /etc/otelcol-contrib
mkdir -p /var/lib/otelcol/queue
mkdir -p /var/log/otelcol
chown -R otelcol:otelcol /var/lib/otelcol /var/log/otelcol

# Download config from S3
aws s3 cp "s3://${config_bucket}/${config_key}" /etc/otelcol-contrib/config.yaml

# Create systemd service
cat > /etc/systemd/system/otelcol-contrib.service <<'UNIT'
[Unit]
Description=OpenTelemetry Collector Contrib
Documentation=https://opentelemetry.io/docs/collector/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=otelcol
Group=otelcol
ExecStart=/usr/local/bin/otelcol-contrib --config /etc/otelcol-contrib/config.yaml
Restart=always
RestartSec=5
MemoryMax=512M
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
SyslogIdentifier=otelcol

[Install]
WantedBy=multi-user.target
UNIT

# Enable and start
systemctl daemon-reload
systemctl enable --now otelcol-contrib

echo "=== OpenTelemetry Collector installation complete ==="
