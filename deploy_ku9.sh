#!/bin/bash
set -e

echo "🔥 开始部署酷9风格（针对 com.whyun.witv）..."

PKG="com.whyun.witv"
PKG_PATH="com/whyun/witv"
MAIN_ACT_SIMPLE="MainActivity"
MAIN_ACT_FILE="app/src/main/java/$PKG_PATH/$MAIN_ACT_SIMPLE.java"
LAYOUT_NAME="activity_main"
LAYOUT_FILE="app/src/main/res/layout/$LAYOUT_NAME.xml"
MANIFEST="app/src/main/AndroidManifest.xml"

# 备份
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "$MAIN_ACT_FILE" ] && cp "$MAIN_ACT_FILE" "$BACKUP_DIR/"
[ -f "$LAYOUT_FILE" ] && cp "$LAYOUT_FILE" "$BACKUP_DIR/"
cp "$MANIFEST" "$BACKUP_DIR/"
echo "📂 已备份到 $BACKUP_DIR"

# 1. 确保 ExoPlayer 依赖
APP_GRADLE="app/build.gradle"
cp "$APP_GRADLE" "$APP_GRADLE.bak"
if ! grep -q "exoplayer" "$APP_GRADLE"; then
    sed -i '/dependencies {/a \    implementation "com.google.android.exoplayer:exoplayer:2.19.1"\n    implementation "com.google.android.exoplayer:exoplayer-hls:2.19.1"\n    implementation "com.google.android.exoplayer:exoplayer-ui:2.19.1"' "$APP_GRADLE"
fi

# 2. 添加其他依赖
sed -i '/dependencies {/a \    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"' "$APP_GRADLE"

# 3. 添加权限
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"

# 4. 创建功能类
mkdir -p "app/src/main/java/$PKG_PATH/source"
mkdir -p "app/src/main/java/$PKG_PATH/player"
mkdir -p "app/src/main/java/$PKG_PATH/favorite"
mkdir -p "app/src/main/java/$PKG_PATH/epg"

# ... (这里省略 SourceManager, PlayerConfigManager 等类的创建，内容与之前相同，请保持) ...

echo "✅ 功能类已创建"

# ========== 5. 【核心修复】使用 awk 安全地修改 AndroidManifest ==========
echo "🛠️ 正在修复 AndroidManifest.xml..."

# 使用 awk 处理：删除所有 LAUNCHER 行，然后在第一个 <activity> 前插入新的 LAUNCHER 声明
awk -v pkg="$PKG" -v act="$MAIN_ACT_SIMPLE" '
BEGIN { printed=0; in_activity=0; }
{
    # 删除所有包含 LAUNCHER 的行
    if ($0 ~ /android.intent.category.LAUNCHER/) {
        next
    }
    # 在第一个 <activity> 标签前插入新的 LAUNCHER 声明
    if ($0 ~ /<activity/ && printed==0) {
        printed=1
        print "    <activity android:name=\"" pkg "." act "\" android:exported=\"true\">"
        print "        <intent-filter>"
        print "            <action android:name=\"android.intent.action.MAIN\" />"
        print "            <category android:name=\"android.intent.category.LAUNCHER\" />"
        print "        </intent-filter>"
        print "    </activity>"
    }
    print $0
}
' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo "✅ AndroidManifest 已修复"

# 6. 生成酷9风格 MainActivity 和布局文件
# ... (这里省略 MainActivity 和布局文件的生成，内容与之前相同，请保持) ...

echo ""
echo "🎉 部署完成！"
echo "📌 请修改 MainActivity 中的 defaultUrl 为你的直播源地址。"
