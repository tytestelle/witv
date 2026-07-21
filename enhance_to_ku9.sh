#!/bin/bash
set -e

echo "🔥 开始增强 witv → 酷9风格..."

PKG="com/whyun/witv"
SRC="app/src/main/java/$PKG"

# ============================================================
# 1. 修改 PreferenceManager —— 增加解码、比例、收藏等设置
# ============================================================
PREF_FILE="$SRC/data/PreferenceManager.java"
if [ -f "$PREF_FILE" ]; then
    # 在类末尾添加新方法（在最后一个 } 之前插入）
    sed -i '/^}/i \
    // ========== 酷9增强设置 ==========\n\
    private static final String KEY_DECODER_MODE = "decoder_mode";\n\
    private static final String KEY_ASPECT_RATIO = "aspect_ratio";\n\
    private static final String KEY_FAVORITE_PREFIX = "fav_";\n\
    public static final int DECODER_HARDWARE = 0;\n\
    public static final int DECODER_SOFTWARE = 1;\n\
    public void setDecoderMode(int mode) { prefs.edit().putInt(KEY_DECODER_MODE, mode).apply(); }\n\
    public int getDecoderMode() { return prefs.getInt(KEY_DECODER_MODE, DECODER_HARDWARE); }\n\
    public void setAspectRatio(String ratio) { prefs.edit().putString(KEY_ASPECT_RATIO, ratio).apply(); }\n\
    public String getAspectRatio() { return prefs.getString(KEY_ASPECT_RATIO, "16:9"); }\n\
    public boolean isFavorite(long channelId) { return prefs.getBoolean(KEY_FAVORITE_PREFIX + channelId, false); }\n\
    public void toggleFavorite(long channelId) {\n\
        boolean cur = isFavorite(channelId);\n\
        prefs.edit().putBoolean(KEY_FAVORITE_PREFIX + channelId, !cur).apply();\n\
    }\n' "$PREF_FILE"
    echo "✅ PreferenceManager 已增强"
else
    echo "⚠️ 未找到 PreferenceManager.java"
fi

# ============================================================
# 2. 修改 PlayerManager —— 支持硬解/软解切换
# ============================================================
PLAYER_FILE="$SRC/player/PlayerManager.java"
if [ -f "$PLAYER_FILE" ]; then
    # 在 initialize 方法中，ExoPlayer.Builder 创建之前插入渲染器配置
    sed -i '/ExoPlayer.Builder context/i \
        // 酷9: 根据设置选择解码器\n\
        PreferenceManager pm = new PreferenceManager(context);\n\
        int decoderMode = pm.getDecoderMode();\n\
        DefaultRenderersFactory renderersFactory = new DefaultRenderersFactory(context);\n\
        if (decoderMode == PreferenceManager.DECODER_SOFTWARE) {\n\
            renderersFactory.setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF);\n\
        } else {\n\
            renderersFactory.setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER);\n\
        }\n' "$PLAYER_FILE"
    
    # 修改 ExoPlayer.Builder 创建，使用自定义渲染器工厂
    sed -i 's/new ExoPlayer.Builder(context)/new ExoPlayer.Builder(context, renderersFactory)/' "$PLAYER_FILE"
    echo "✅ PlayerManager 已增强（支持硬解/软解切换）"
else
    echo "⚠️ 未找到 PlayerManager.java"
fi

# ============================================================
# 3. 修改 PlayerActivity —— 添加菜单、搜索、收藏交互
# ============================================================
ACTIVITY_FILE="$SRC/ui/PlayerActivity.java"
if [ -f "$ACTIVITY_FILE" ]; then
    # 在类中注入菜单处理方法（在最后一个 } 之前插入）
    sed -i '/^}/i \
    // ========== 酷9: 菜单处理 ==========\n\
    @Override\n\
    public boolean onCreateOptionsMenu(Menu menu) {\n\
        getMenuInflater().inflate(R.menu.player_menu, menu);\n\
        return true;\n\
    }\n\
    @Override\n\
    public boolean onOptionsItemSelected(MenuItem item) {\n\
        int id = item.getItemId();\n\
        if (id == R.id.action_decoder_hw) {\n\
            preferenceManager.setDecoderMode(PreferenceManager.DECODER_HARDWARE);\n\
            Toast.makeText(this, "已切换为硬解，重启播放生效", Toast.LENGTH_SHORT).show();\n\
            restartPlayer();\n\
            return true;\n\
        } else if (id == R.id.action_decoder_sw) {\n\
            preferenceManager.setDecoderMode(PreferenceManager.DECODER_SOFTWARE);\n\
            Toast.makeText(this, "已切换为软解，重启播放生效", Toast.LENGTH_SHORT).show();\n\
            restartPlayer();\n\
            return true;\n\
        } else if (id == R.id.action_aspect_ratio) {\n\
            showAspectRatioDialog();\n\
            return true;\n\
        } else if (id == R.id.action_search) {\n\
            showSearchDialog();\n\
            return true;\n\
        }\n\
        return super.onOptionsItemSelected(item);\n\
    }\n\
    private void showAspectRatioDialog() {\n\
        String[] ratios = {"16:9", "4:3", "全屏"};\n\
        new AlertDialog.Builder(this)\n\
            .setTitle("选择画面比例")\n\
            .setItems(ratios, (d, which) -> {\n\
                String ratio = ratios[which];\n\
                preferenceManager.setAspectRatio(ratio);\n\
                applyAspectRatio(ratio);\n\
            })\n\
            .show();\n\
    }\n\
    private void applyAspectRatio(String ratio) {\n\
        View videoView = findViewById(R.id.player_view);\n\
        if (videoView == null) return;\n\
        ViewGroup.LayoutParams params = videoView.getLayoutParams();\n\
        if ("16:9".equals(ratio)) {\n\
            params.width = ViewGroup.LayoutParams.MATCH_PARENT;\n\
            params.height = (int) (getResources().getDisplayMetrics().widthPixels * 9f / 16f);\n\
        } else if ("4:3".equals(ratio)) {\n\
            params.width = ViewGroup.LayoutParams.MATCH_PARENT;\n\
            params.height = (int) (getResources().getDisplayMetrics().widthPixels * 3f / 4f);\n\
        } else { // 全屏\n\
            params.width = ViewGroup.LayoutParams.MATCH_PARENT;\n\
            params.height = ViewGroup.LayoutParams.MATCH_PARENT;\n\
        }\n\
        videoView.setLayoutParams(params);\n\
    }\n\
    private void showSearchDialog() {\n\
        EditText input = new EditText(this);\n\
        input.setHint("输入频道名称");\n\
        new AlertDialog.Builder(this)\n\
            .setTitle("搜索频道")\n\
            .setView(input)\n\
            .setPositiveButton("搜索", (d, which) -> {\n\
                String keyword = input.getText().toString().trim();\n\
                if (keyword.isEmpty()) return;\n\
                filterChannelList(keyword);\n\
            })\n\
            .setNegativeButton("取消", null)\n\
            .show();\n\
    }\n\
    private void filterChannelList(String keyword) {\n\
        if (allChannels == null) return;\n\
        List<Channel> filtered = new ArrayList<>();\n\
        for (Channel ch : allChannels) {\n\
            if (ch.displayName != null && ch.displayName.contains(keyword)) {\n\
                filtered.add(ch);\n\
            }\n\
        }\n\
        // 更新频道列表适配器（假设使用 channelListAdapter）\n\
        if (channelListAdapter != null) {\n\
            channelListAdapter.updateData(filtered);\n\
        }\n\
    }\n\
    private void restartPlayer() {\n\
        if (currentChannel != null) {\n\
            playChannel(currentChannel);\n\
        }\n\
    }\n\
    // 收藏按钮点击处理（在现有 favoriteIcon 点击事件中调用）\n\
    private void toggleFavorite() {\n\
        if (currentChannel == null) return;\n\
        preferenceManager.toggleFavorite(currentChannel.id);\n\
        updateFavoriteIcon();\n\
    }\n\
    private void updateFavoriteIcon() {\n\
        if (currentChannel == null || favoriteIcon == null) return;\n\
        boolean fav = preferenceManager.isFavorite(currentChannel.id);\n\
        favoriteIcon.setImageResource(fav ? R.drawable.ic_favorite_filled : R.drawable.ic_favorite_border);\n\
    }\n' "$ACTIVITY_FILE"
    
    # 在 onCreate 中初始化收藏图标点击事件（在 setContentView 之后插入）
    sed -i '/setContentView/i \
        // 酷9: 收藏图标点击\n\
        favoriteIcon = findViewById(R.id.iv_favorite);\n\
        if (favoriteIcon != null) {\n\
            favoriteIcon.setOnClickListener(v -> toggleFavorite());\n\
        }\n' "$ACTIVITY_FILE"
    
    echo "✅ PlayerActivity 已增强（菜单、搜索、收藏、比例）"
else
    echo "⚠️ 未找到 PlayerActivity.java"
fi

# ============================================================
# 4. 添加菜单资源文件
# ============================================================
mkdir -p app/src/main/res/menu
cat > app/src/main/res/menu/player_menu.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:id="@+id/action_decoder_hw" android:title="硬解" />
    <item android:id="@+id/action_decoder_sw" android:title="软解" />
    <item android:id="@+id/action_aspect_ratio" android:title="画面比例" />
    <item android:id="@+id/action_search" android:title="搜索频道" />
</menu>
EOF
echo "✅ 菜单资源已添加"

# ============================================================
# 5. 添加收藏图标资源
# ============================================================
mkdir -p app/src/main/res/drawable
cat > app/src/main/res/drawable/ic_favorite_border.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z"/>
</vector>
EOF
cat > app/src/main/res/drawable/ic_favorite_filled.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFD700" android:pathData="M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z"/>
</vector>
EOF
echo "✅ 收藏图标已添加"

# ============================================================
# 6. 修改频道列表布局，添加收藏按钮
# ============================================================
ITEM_LAYOUT="app/src/main/res/layout/item_channel.xml"
if [ -f "$ITEM_LAYOUT" ]; then
    sed -i '/<\/LinearLayout>/ i \    <ImageView\n        android:id="@+id/iv_favorite"\n        android:layout_width="24dp"\n        android:layout_height="24dp"\n        android:src="@drawable/ic_favorite_border"\n        android:layout_gravity="center_vertical"\n        android:padding="4dp" />' "$ITEM_LAYOUT"
    echo "✅ 频道列表布局已添加收藏按钮"
else
    echo "⚠️ 未找到 item_channel.xml，请手动添加"
fi

# ============================================================
# 7. 添加 TXT 源支持（修改 M3UParser）
# ============================================================
M3U_PARSER="$SRC/data/parser/M3UParser.java"
if [ -f "$M3U_PARSER" ]; then
    sed -i '/public.*parse/i \
    // 酷9: 支持 TXT 格式解析\n\
    public static List<Channel> parseTxt(String content) {\n\
        List<Channel> channels = new ArrayList<>();\n\
        String[] lines = content.split("\\n");\n\
        for (String line : lines) {\n\
            line = line.trim();\n\
            if (line.isEmpty() || line.startsWith("#")) continue;\n\
            String[] parts = line.split(",", 2);\n\
            if (parts.length >= 2) {\n\
                Channel ch = new Channel();\n\
                ch.displayName = parts[0].trim();\n\
                ch.url = parts[1].trim();\n\
                channels.add(ch);\n\
            }\n\
        }\n\
        return channels;\n\
    }\n' "$M3U_PARSER"
    echo "✅ M3UParser 已添加 TXT 解析支持"
else
    echo "⚠️ 未找到 M3UParser.java"
fi

# ============================================================
# 8. 更新 build.gradle 依赖
# ============================================================
APP_GRADLE="app/build.gradle"
if [ -f "$APP_GRADLE" ]; then
    # 检查是否已添加 glide，避免重复
    if ! grep -q "glide" "$APP_GRADLE"; then
        sed -i '/dependencies {/a \    implementation "com.github.bumptech.glide:glide:4.16.0"\n    implementation "androidx.preference:preference:1.2.1"' "$APP_GRADLE"
        echo "✅ build.gradle 依赖已更新"
    else
        echo "✅ build.gradle 依赖已存在"
    fi
else
    echo "⚠️ 未找到 build.gradle"
fi

# ============================================================
# 9. 添加 AndroidManifest 权限（U盘读取）
# ============================================================
MANIFEST="app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
    if ! grep -q "READ_EXTERNAL_STORAGE" "$MANIFEST"; then
        sed -i '/<manifest /a \    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
        echo "✅ AndroidManifest 权限已添加"
    else
        echo "✅ AndroidManifest 权限已存在"
    fi
else
    echo "⚠️ 未找到 AndroidManifest.xml"
fi

echo ""
echo "🎉 增强完成！"
echo ""
echo "📝 接下来你需要："
echo "1. 在 PlayerActivity 中导入缺失的类："
echo "   - import android.view.Menu;"
echo "   - import android.view.MenuItem;"
echo "   - import android.widget.EditText;"
echo "   - import androidx.appcompat.app.AlertDialog;"
echo "2. 确保 PlayerActivity 中有 allChannels 和 channelListAdapter 变量"
echo "3. 编译测试：./gradlew assembleDebug"
echo ""
echo "⚠️ 脚本修改了多个 Java 文件，可能需要手动调整导入语句"
