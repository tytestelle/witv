#!/bin/bash
mkdir -p config
cat > config/configuration.json <<'EOF'
{"Configuration":{"LIVE_URLS":null}}
EOF
echo "✅ 文件已生成: $(pwd)/config/configuration.json"
ls -l config/
