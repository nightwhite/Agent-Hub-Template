#!/usr/bin/env bash
set -euo pipefail

mkdir -p /opt/agent/lib /opt/change-me/bin /opt/change-me/etc

cat >/opt/change-me/bin/change-me-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "change-me agent scaffold is not implemented yet."
echo "Replace agents/change-me/install.sh and install the real agent runtime."
exit 1
EOF

chmod +x /opt/change-me/bin/change-me-run
