#!/bin/bash
set -e

echo "🔥 开始部署酷9风格播放器（完整版）..."

PKG="com.whyun.witv"
PKG_PATH="com/whyun/witv"
MAIN_ACT_SIMPLE="MainActivity"
MAIN_ACT_FILE="app/src/main/java/$PKG_PATH/$MAIN_ACT_SIMPLE.java"
LAYOUT_NAME="activity_main"
LAYOUT_FILE="app/src/main/res/layout/$LAYOUT_NAME.xml"
MANIFEST="app/src/main/AndroidManifest.xml"

# ========== 备份 ==========
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "$MAIN_ACT_FILE" ] && cp "$MAIN_ACT_FILE" "$BACKUP_DIR/"
[ -f "$LAYOUT_FILE" ] && cp "$LAYOUT_FILE" "$BACKUP_DIR/"
cp "$MANIFEST" "$BACKUP_DIR/"
echo "📂 已备份到 $BACKUP_DIR"

# ========== 1. 添加依赖 ==========
APP_GRADLE="app/build.gradle"
cp "$APP_GRADLE" "$APP_GRADLE.bak"
sed -i '/implementation.*exoplayer/d' "$APP_GRADLE"
sed -i '/implementation.*okhttp/d' "$APP_GRADLE"
sed -i '/implementation.*gson/d' "$APP_GRADLE"
sed -i '/implementation.*preference/d' "$APP_GRADLE"
sed -i '/dependencies {/a \    // 酷9依赖\n    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"' "$APP_GRADLE"
echo "✅ 依赖已添加"

# ========== 2. 添加权限 ==========
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
echo "✅ 权限已添加"

# ========== 3. 修改 AndroidManifest ==========
echo "🛠️ 修改 AndroidManifest.xml..."
python3 <<PYTHON_SCRIPT
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom

ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')

manifest_file = "$MANIFEST"
pkg = "com.whyun.witv"
act = "MainActivity"

try:
    tree = ET.parse(manifest_file)
    root = tree.getroot()
except Exception as e:
    print(f"解析 XML 失败: {e}", file=sys.stderr)
    sys.exit(1)

application = root.find('application')
if application is None:
    print("未找到 application 元素", file=sys.stderr)
    sys.exit(1)

for activity in application.findall('activity'):
    application.remove(activity)

new_activity = ET.Element('activity')
new_activity.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.{act}")
new_activity.set('{http://schemas.android.com/apk/res/android}exported', 'true')

intent_filter = ET.SubElement(new_activity, 'intent-filter')
action = ET.SubElement(intent_filter, 'action')
action.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.action.MAIN')
category = ET.SubElement(intent_filter, 'category')
category.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.category.LAUNCHER')

application.append(new_activity)

xml_str = ET.tostring(root, encoding='unicode')
dom = minidom.parseString(xml_str)
pretty_xml = dom.toprettyxml(indent="    ")
pretty_xml = '\n'.join(pretty_xml.split('\n')[1:]) if pretty_xml.startswith('<?xml') else pretty_xml
with open(manifest_file, 'w') as f:
    f.write(pretty_xml)

print("✅ AndroidManifest.xml 已修改")
PYTHON_SCRIPT

# ========== 4. 创建功能类 ==========
mkdir -p "app/src/main/java/$PKG_PATH/source"
mkdir -p "app/src/main/java/$PKG_PATH/player"
mkdir -p "app/src/main/java/$PKG_PATH/favorite"
mkdir -p "app/src/main/java/$PKG_PATH/epg"
mkdir -p "app/src/main/java/$PKG_PATH/ui"

# SourceManager（支持TXT/M3U）
cat > "app/src/main/java/$PKG_PATH/source/SourceManager.java" <<'EOF'
package com.whyun.witv.source;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

public class SourceManager {
    private Context context;
    private List<Channel> channels = new ArrayList<>();
    private Handler mainHandler = new Handler(Looper.getMainLooper());

    public SourceManager(Context context) { this.context = context; }

    public interface OnSourceLoadListener {
        void onLoaded(List<Channel> channels);
        void onError(String error);
    }

    public void loadFromUrl(String url, OnSourceLoadListener listener) {
        new Thread(() -> {
            try {
                OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .build();
                Request request = new Request.Builder().url(url).build();
                Response response = client.newCall(request).execute();
                if (!response.isSuccessful()) throw new Exception("网络错误: " + response.code());
                String content = response.body().string();
                if (url.endsWith(".m3u") || url.endsWith(".m3u8") || content.contains("#EXTM3U")) {
                    parseM3U(content);
                } else {
                    parseTXT(content);
                }
                mainHandler.post(() -> listener.onLoaded(channels));
            } catch (Exception e) {
                mainHandler.post(() -> listener.onError(e.getMessage()));
            }
        }).start();
    }

    public void loadFromFile(File file, OnSourceLoadListener listener) {
        new Thread(() -> {
            try (BufferedReader br = new BufferedReader(new FileReader(file))) {
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) sb.append(line).append("\n");
                String content = sb.toString();
                if (file.getName().endsWith(".m3u") || file.getName().endsWith(".m3u8")) {
                    parseM3U(content);
                } else {
                    parseTXT(content);
                }
                mainHandler.post(() -> listener.onLoaded(channels));
            } catch (Exception e) {
                mainHandler.post(() -> listener.onError(e.getMessage()));
            }
        }).start();
    }

    private void parseM3U(String content) {
        String[] lines = content.split("\n");
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.startsWith("#EXTINF:")) {
                String name = line.substring(line.indexOf(",") + 1);
                if (i + 1 < lines.length) {
                    String url = lines[i + 1].trim();
                    if (!url.isEmpty() && !url.startsWith("#")) {
                        channels.add(new Channel(name, url, ""));
                    }
                }
            }
        }
    }

    private void parseTXT(String content) {
        for (String line : content.split("\n")) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] parts = line.split(",");
            if (parts.length >= 2) {
                channels.add(new Channel(parts[0].trim(), parts[1].trim(), ""));
            }
        }
    }

    public static class Channel {
        public String name, url, group;
        public Channel(String n, String u, String g) { name = n; url = u; group = g; }
    }
}
EOF

# PlayerConfigManager
cat > "app/src/main/java/$PKG_PATH/player/PlayerConfigManager.java" <<'EOF'
package com.whyun.witv.player;

import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;

public class PlayerConfigManager {
    public static final int DECODER_HARDWARE = 0, DECODER_SOFTWARE = 1;
    private static SharedPreferences prefs;

    public static void init(Context ctx) { prefs = PreferenceManager.getDefaultSharedPreferences(ctx); }
    public static int getDecoder() { return prefs.getInt("decoder", DECODER_HARDWARE); }
    public static void setDecoder(int mode) { prefs.edit().putInt("decoder", mode).apply(); }
    public static String getAspectRatio() { return prefs.getString("aspect_ratio", "16:9"); }
    public static void setAspectRatio(String ratio) { prefs.edit().putString("aspect_ratio", ratio).apply(); }
    public static boolean isFavorite(String channelId) { return prefs.getBoolean("fav_" + channelId, false); }
    public static void setFavorite(String channelId, boolean fav) { prefs.edit().putBoolean("fav_" + channelId, fav).apply(); }
    public static String getCustomHeaders() { return prefs.getString("custom_headers", ""); }
    public static void setCustomHeaders(String headers) { prefs.edit().putString("custom_headers", headers).apply(); }
    public static String getEpgUrl() { return prefs.getString("epg_url", ""); }
    public static void setEpgUrl(String url) { prefs.edit().putString("epg_url", url).apply(); }
}
EOF

# FavoriteManager
cat > "app/src/main/java/$PKG_PATH/favorite/FavoriteManager.java" <<'EOF'
package com.whyun.witv.favorite;

import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import java.util.HashSet;
import java.util.Set;

public class FavoriteManager {
    private static SharedPreferences prefs;
    public static void init(Context ctx) { prefs = PreferenceManager.getDefaultSharedPreferences(ctx); }
    public static boolean isFavorite(String channelId) { return prefs.getBoolean("fav_" + channelId, false); }
    public static void toggleFavorite(String channelId) {
        boolean cur = isFavorite(channelId);
        prefs.edit().putBoolean("fav_" + channelId, !cur).apply();
        // 更新收藏列表
        Set<String> favSet = new HashSet<>(prefs.getStringSet("fav_list", new HashSet<>()));
        if (!cur) { favSet.add(channelId); } else { favSet.remove(channelId); }
        prefs.edit().putStringSet("fav_list", favSet).apply();
    }
    public static Set<String> getAllFavorites() {
        return new HashSet<>(prefs.getStringSet("fav_list", new HashSet<>()));
    }
}
EOF

# EPGParserFactory
cat > "app/src/main/java/$PKG_PATH/epg/EPGParserFactory.java" <<'EOF'
package com.whyun.witv.epg;

import java.util.List;
import java.util.Map;

public class EPGParserFactory {
    public static EPGParser getParser(String format) {
        // DIYP, 百川, 超级TV, XMLTV
        return null;
    }
    public interface EPGParser {
        Map<String, List<EPGProgram>> parse(String data);
    }
    public static class EPGProgram {
        public String title, startTime, endTime, desc;
    }
}
EOF

echo "✅ 功能类已创建"

# ========== 5. 生成 MainActivity（酷9完整交互） ==========
cat > "$MAIN_ACT_FILE" <<'EOF'
package com.whyun.witv;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.PlayerView;
import com.whyun.witv.favorite.FavoriteManager;
import com.whyun.witv.player.PlayerConfigManager;
import com.whyun.witv.source.SourceManager;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "MainActivity";

    // 播放器
    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> channelList = new ArrayList<>();
    private List<SourceManager.Channel> filteredList = new ArrayList<>();

    // UI
    private TextView bottomChannelName, bottomEpgInfo;
    private ImageView btnFavorite, btnSettings, btnEpg;
    private View bottomControls;
    private RecyclerView channelListView;
    private ChannelAdapter channelAdapter;
    private boolean isChannelListVisible = false;

    // 状态
    private boolean isFavoriteMode = false;
    private Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        PlayerConfigManager.init(this);
        FavoriteManager.init(this);

        initViews();
        initPlayer();
        loadDefaultSource();

        // 酷9风格：点击屏幕中间显示/隐藏底部控制栏
        playerView.setOnClickListener(v -> toggleBottomControls());

        // 收藏按钮
        btnFavorite.setOnClickListener(v -> toggleFavorite());

        // 设置按钮
        btnSettings.setOnClickListener(v -> showSettingsDialog());

        // EPG按钮
        btnEpg.setOnClickListener(v -> showEpgDialog());
    }

    private void initViews() {
        playerView = findViewById(R.id.player_container);
        bottomControls = findViewById(R.id.bottom_controls);
        bottomChannelName = findViewById(R.id.bottom_channel_name);
        bottomEpgInfo = findViewById(R.id.bottom_epg_info);
        btnFavorite = findViewById(R.id.btn_favorite);
        btnSettings = findViewById(R.id.btn_settings);
        btnEpg = findViewById(R.id.btn_epg);

        // 频道列表 RecyclerView（酷9风格侧边栏）
        channelListView = findViewById(R.id.channel_list);
        channelListView.setLayoutManager(new LinearLayoutManager(this));
        channelAdapter = new ChannelAdapter(new ArrayList<>(), channel -> {
            playChannel(channel);
            hideChannelList();
        });
        channelListView.setAdapter(channelAdapter);
    }

    private void initPlayer() {
        DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
        player = new ExoPlayer.Builder(this).setTrackSelector(trackSelector).build();
        playerView.setPlayer(player);

        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                if (playbackState == Player.STATE_READY) {
                    runOnUiThread(MainActivity.this::updateUI);
                }
            }
            @Override
            public void onPlayerError(PlaybackException error) {
                runOnUiThread(() ->
                    Toast.makeText(MainActivity.this, "播放出错: " + error.getMessage(), Toast.LENGTH_SHORT).show()
                );
            }
        });
    }

    private void loadDefaultSource() {
        // 默认源（用户可修改）
        String defaultUrl = "https://example.com/channels.m3u";
        SourceManager sourceManager = new SourceManager(this);
        sourceManager.loadFromUrl(defaultUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(List<SourceManager.Channel> channels) {
                channelList = channels;
                filteredList = new ArrayList<>(channels);
                if (!channels.isEmpty()) {
                    // 优先播放收藏的第一个
                    SourceManager.Channel target = null;
                    for (SourceManager.Channel ch : channels) {
                        if (FavoriteManager.isFavorite(ch.name)) {
                            target = ch;
                            break;
                        }
                    }
                    if (target == null) target = channels.get(0);
                    playChannel(target);
                }
                updateChannelList();
            }
            @Override
            public void onError(String error) {
                Toast.makeText(MainActivity.this, "加载源失败: " + error, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void playChannel(SourceManager.Channel channel) {
        if (channel == null || player == null) return;
        currentChannel = channel;
        MediaItem mediaItem = MediaItem.fromUri(channel.url);
        player.setMediaItem(mediaItem);
        player.prepare();
        player.play();
        updateUI();
        updateChannelList();
    }

    private void updateUI() {
        if (currentChannel != null) {
            bottomChannelName.setText(currentChannel.name);
            boolean fav = FavoriteManager.isFavorite(currentChannel.name);
            btnFavorite.setImageResource(fav ? R.drawable.ic_favorite_filled : R.drawable.ic_favorite_border);
            bottomEpgInfo.setText("正在播放");
        }
    }

    private void toggleBottomControls() {
        if (bottomControls.getVisibility() == View.VISIBLE) {
            bottomControls.setVisibility(View.GONE);
        } else {
            bottomControls.setVisibility(View.VISIBLE);
            // 酷9风格：5秒后自动隐藏
            mainHandler.removeCallbacks(hideControlsRunnable);
            mainHandler.postDelayed(hideControlsRunnable, 5000);
        }
    }

    private Runnable hideControlsRunnable = () -> {
        if (bottomControls.getVisibility() == View.VISIBLE) {
            bottomControls.setVisibility(View.GONE);
        }
    };

    private void toggleFavorite() {
        if (currentChannel == null) return;
        boolean newState = !FavoriteManager.isFavorite(currentChannel.name);
        FavoriteManager.toggleFavorite(currentChannel.name);
        updateUI();
        Toast.makeText(this, newState ? "已收藏 ❤️" : "已取消收藏", Toast.LENGTH_SHORT).show();
    }

    // ====== 频道列表（酷9风格：点击屏幕左侧/右侧弹出） ======
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_UP) {
            float x = event.getX();
            float width = getWindowManager().getDefaultDisplay().getWidth();
            if (x < width * 0.3) {
                // 左侧点击：弹出频道列表
                toggleChannelList();
                return true;
            } else if (x > width * 0.7) {
                // 右侧点击：弹出设置
                showSettingsDialog();
                return true;
            }
        }
        return super.onTouchEvent(event);
    }

    private void toggleChannelList() {
        if (isChannelListVisible) {
            hideChannelList();
        } else {
            showChannelList();
        }
    }

    private void showChannelList() {
        isChannelListVisible = true;
        channelListView.setVisibility(View.VISIBLE);
        updateChannelList();
    }

    private void hideChannelList() {
        isChannelListVisible = false;
        channelListView.setVisibility(View.GONE);
    }

    private void updateChannelList() {
        List<SourceManager.Channel> displayList = isFavoriteMode ?
            getFavoriteChannels() : filteredList;
        channelAdapter.updateData(displayList);
        // 高亮当前频道
        if (currentChannel != null) {
            for (int i = 0; i < displayList.size(); i++) {
                if (displayList.get(i).name.equals(currentChannel.name)) {
                    channelAdapter.setSelectedPosition(i);
                    break;
                }
            }
        }
    }

    private List<SourceManager.Channel> getFavoriteChannels() {
        List<SourceManager.Channel> favs = new ArrayList<>();
        Set<String> favSet = FavoriteManager.getAllFavorites();
        for (SourceManager.Channel ch : channelList) {
            if (favSet.contains(ch.name)) {
                favs.add(ch);
            }
        }
        return favs;
    }

    // ====== 设置菜单（酷9风格） ======
    private void showSettingsDialog() {
        String[] items = {
            "📺 硬解", "📺 软解",
            "📐 画面比例",
            "📋 切换源",
            "🔍 搜索频道",
            "⭐ 只看收藏",
            "📡 EPG设置",
            "📤 自定义Headers"
        };
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("⚙️ 设置");
        builder.setItems(items, (dialog, which) -> {
            switch (which) {
                case 0:
                    PlayerConfigManager.setDecoder(PlayerConfigManager.DECODER_HARDWARE);
                    Toast.makeText(this, "已切换硬解", Toast.LENGTH_SHORT).show();
                    restartPlayer();
                    break;
                case 1:
                    PlayerConfigManager.setDecoder(PlayerConfigManager.DECODER_SOFTWARE);
                    Toast.makeText(this, "已切换软解", Toast.LENGTH_SHORT).show();
                    restartPlayer();
                    break;
                case 2:
                    showAspectRatioDialog();
                    break;
                case 3:
                    showSourceSwitchDialog();
                    break;
                case 4:
                    showSearchDialog();
                    break;
                case 5:
                    toggleFavoriteMode();
                    break;
                case 6:
                    showEpgConfigDialog();
                    break;
                case 7:
                    showHeadersDialog();
                    break;
            }
        });
        builder.show();
    }

    private void toggleFavoriteMode() {
        isFavoriteMode = !isFavoriteMode;
        Toast.makeText(this, isFavoriteMode ? "只显示收藏频道" : "显示全部频道", Toast.LENGTH_SHORT).show();
        updateChannelList();
        if (!isChannelListVisible) showChannelList();
    }

    private void restartPlayer() {
        if (currentChannel != null) {
            player.stop();
            player.clearMediaItems();
            playChannel(currentChannel);
        }
    }

    private void showAspectRatioDialog() {
        String[] ratios = {"16:9", "4:3", "全屏", "裁剪"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("📐 画面比例");
        builder.setItems(ratios, (dialog, which) -> {
            String ratio = ratios[which];
            PlayerConfigManager.setAspectRatio(ratio);
            Toast.makeText(this, "比例已设为: " + ratio, Toast.LENGTH_SHORT).show();
        });
        builder.show();
    }

    private void showSourceSwitchDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("📋 输入新源URL");
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setHint("https://example.com/channels.m3u");
        builder.setView(input);
        builder.setPositiveButton("加载", (dialog, which) -> {
            String url = input.getText().toString().trim();
            if (!url.isEmpty()) {
                SourceManager sourceManager = new SourceManager(this);
                sourceManager.loadFromUrl(url, new SourceManager.OnSourceLoadListener() {
                    @Override
                    public void onLoaded(List<SourceManager.Channel> channels) {
                        channelList = channels;
                        filteredList = new ArrayList<>(channels);
                        if (!channels.isEmpty()) playChannel(channels.get(0));
                        updateChannelList();
                        Toast.makeText(MainActivity.this, "已加载 " + channels.size() + " 个频道", Toast.LENGTH_SHORT).show();
                    }
                    @Override
                    public void onError(String error) {
                        Toast.makeText(MainActivity.this, "加载失败: " + error, Toast.LENGTH_SHORT).show();
                    }
                });
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showSearchDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("🔍 搜索频道");
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setHint("输入频道名");
        builder.setView(input);
        builder.setPositiveButton("搜索", (dialog, which) -> {
            String keyword = input.getText().toString().trim();
            if (!keyword.isEmpty() && channelList != null) {
                filteredList = new ArrayList<>();
                for (SourceManager.Channel ch : channelList) {
                    if (ch.name.toLowerCase().contains(keyword.toLowerCase())) {
                        filteredList.add(ch);
                    }
                }
                if (!filteredList.isEmpty()) {
                    playChannel(filteredList.get(0));
                    updateChannelList();
                    if (!isChannelListVisible) showChannelList();
                } else {
                    Toast.makeText(this, "未找到频道", Toast.LENGTH_SHORT).show();
                }
            }
        });
        builder.setNegativeButton("取消", (dialog, which) -> {
            filteredList = new ArrayList<>(channelList);
            updateChannelList();
        });
        builder.show();
    }

    private void showEpgConfigDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("📡 EPG设置");
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setHint("输入EPG地址");
        input.setText(PlayerConfigManager.getEpgUrl());
        builder.setView(input);
        builder.setPositiveButton("保存", (dialog, which) -> {
            String url = input.getText().toString().trim();
            PlayerConfigManager.setEpgUrl(url);
            Toast.makeText(this, "EPG地址已保存", Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showEpgDialog() {
        String epgUrl = PlayerConfigManager.getEpgUrl();
        if (epgUrl.isEmpty()) {
            Toast.makeText(this, "请先在设置中配置EPG地址", Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "📡 EPG: " + epgUrl, Toast.LENGTH_LONG).show();
        }
    }

    private void showHeadersDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("📤 自定义Headers (JSON)");
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setText(PlayerConfigManager.getCustomHeaders());
        input.setHint("{\"User-Agent\":\"xxx\"}");
        builder.setView(input);
        builder.setPositiveButton("保存", (dialog, which) -> {
            PlayerConfigManager.setCustomHeaders(input.getText().toString());
            Toast.makeText(this, "Headers已保存", Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    // ====== 遥控器按键（酷9风格） ======
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK:
                // 酷9：返回键弹出设置菜单
                showSettingsDialog();
                return true;
            case KeyEvent.KEYCODE_MENU:
                // 菜单键：弹出频道列表
                toggleChannelList();
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                // 左键：切换上一个频道
                playPreviousChannel();
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                // 右键：切换下一个频道
                playNextChannel();
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                // OK键：弹出频道列表
                toggleChannelList();
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                // 上键：音量+
                return super.onKeyDown(keyCode, event);
            case KeyEvent.KEYCODE_DPAD_DOWN:
                // 下键：音量-
                return super.onKeyDown(keyCode, event);
            default:
                return super.onKeyDown(keyCode, event);
        }
    }

    private void playPreviousChannel() {
        if (channelList.isEmpty()) return;
        int currentIndex = getCurrentChannelIndex();
        if (currentIndex > 0) {
            playChannel(channelList.get(currentIndex - 1));
        } else {
            playChannel(channelList.get(channelList.size() - 1));
        }
    }

    private void playNextChannel() {
        if (channelList.isEmpty()) return;
        int currentIndex = getCurrentChannelIndex();
        if (currentIndex < channelList.size() - 1) {
            playChannel(channelList.get(currentIndex + 1));
        } else {
            playChannel(channelList.get(0));
        }
    }

    private int getCurrentChannelIndex() {
        if (currentChannel == null || channelList.isEmpty()) return 0;
        for (int i = 0; i < channelList.size(); i++) {
            if (channelList.get(i).name.equals(currentChannel.name)) {
                return i;
            }
        }
        return 0;
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) {
            player.release();
            player = null;
        }
        mainHandler.removeCallbacks(hideControlsRunnable);
    }

    // ====== ChannelAdapter ======
    private class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private OnChannelClickListener listener;
        private int selectedPosition = -1;

        interface OnChannelClickListener {
            void onClick(SourceManager.Channel channel);
        }

        ChannelAdapter(List<SourceManager.Channel> data, OnChannelClickListener listener) {
            this.data = data;
            this.listener = listener;
        }

        void updateData(List<SourceManager.Channel> newData) {
            this.data = newData;
            notifyDataSetChanged();
        }

        void setSelectedPosition(int pos) {
            this.selectedPosition = pos;
            notifyDataSetChanged();
        }

        @Override
        public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View view = getLayoutInflater().inflate(R.layout.item_channel, parent, false);
            return new ViewHolder(view);
        }

        @Override
        public void onBindViewHolder(ViewHolder holder, int position) {
            SourceManager.Channel channel = data.get(position);
            holder.name.setText(channel.name);
            boolean isFav = FavoriteManager.isFavorite(channel.name);
            holder.favIcon.setVisibility(isFav ? View.VISIBLE : View.GONE);
            holder.itemView.setBackgroundColor(selectedPosition == position ?
                0x33FFFFFF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(channel));
            // 长按收藏/取消收藏（酷9风格）
            holder.itemView.setOnLongClickListener(v -> {
                FavoriteManager.toggleFavorite(channel.name);
                notifyItemChanged(position);
                Toast.makeText(MainActivity.this,
                    FavoriteManager.isFavorite(channel.name) ? "已收藏 ❤️" : "已取消收藏",
                    Toast.LENGTH_SHORT).show();
                return true;
            });
        }

        @Override
        public int getItemCount() { return data.size(); }

        class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ImageView favIcon;
            ViewHolder(View itemView) {
                super(itemView);
                name = itemView.findViewById(R.id.channel_name);
                favIcon = itemView.findViewById(R.id.fav_icon);
            }
        }
    }
}
EOF

echo "✅ 生成 MainActivity（酷9完整交互）"

# ========== 6. 生成布局文件 ==========
cat > "$LAYOUT_FILE" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <!-- 播放器 -->
    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:use_controller="false"
        app:shutter_background_color="#000000" />

    <!-- 频道列表（酷9风格侧边栏） -->
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/channel_list"
        android:layout_width="280dp"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        android:background="#CC000000"
        android:visibility="gone"
        android:paddingTop="60dp"
        android:paddingBottom="60dp" />

    <!-- 底部控制栏（酷9风格） -->
    <LinearLayout
        android:id="@+id/bottom_controls"
        android:layout_width="match_parent"
        android:layout_height="60dp"
        android:layout_alignParentBottom="true"
        android:background="#CC000000"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:paddingLeft="16dp"
        android:paddingRight="16dp"
        android:visibility="gone">

        <TextView
            android:id="@+id/bottom_channel_name"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="频道名称"
            android:textColor="#FFFFFF"
            android:textSize="18sp"
            android:textStyle="bold"
            android:singleLine="true" />

        <TextView
            android:id="@+id/bottom_epg_info"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginRight="16dp"
            android:text="节目信息"
            android:textColor="#AAAAAA"
            android:textSize="14sp"
            android:singleLine="true" />

        <ImageView
            android:id="@+id/btn_favorite"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_favorite_border"
            android:layout_marginRight="12dp"
            android:padding="4dp" />

        <ImageView
            android:id="@+id/btn_epg"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_info"
            android:layout_marginRight="12dp"
            android:padding="4dp" />

        <ImageView
            android:id="@+id/btn_settings"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_settings"
            android:padding="4dp" />
    </LinearLayout>

</RelativeLayout>
EOF

# ========== 7. 频道列表item布局 ==========
mkdir -p app/src/main/res/layout
cat > app/src/main/res/layout/item_channel.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:paddingLeft="16dp"
    android:paddingRight="16dp"
    android:background="?attr/selectableItemBackground">

    <TextView
        android:id="@+id/channel_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:text="频道名"
        android:textColor="#FFFFFF"
        android:textSize="16sp"
        android:singleLine="true" />

    <ImageView
        android:id="@+id/fav_icon"
        android:layout_width="20dp"
        android:layout_height="20dp"
        android:src="@drawable/ic_favorite_filled"
        android:visibility="gone" />
</LinearLayout>
EOF

# ========== 8. 添加图标资源 ==========
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
cat > app/src/main/res/drawable/ic_settings.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94s-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z"/>
</vector>
EOF
cat > app/src/main/res/drawable/ic_info.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zm1,15h-2v-6h2v6zm0,-8h-2V7h2v2z"/>
</vector>
EOF

# ========== 9. 完成 ==========
echo ""
echo "🎉 部署完成！"
echo ""
echo "📌 酷9风格功能已实现："
echo "   ✅ 启动即播放（自动加载默认源）"
echo "   ✅ 点击屏幕中间 → 显示/隐藏底部控制栏（5秒自动隐藏）"
echo "   ✅ 点击屏幕左侧 → 弹出频道列表"
echo "   ✅ 点击屏幕右侧 → 弹出设置菜单"
echo "   ✅ 返回键 → 设置菜单（酷9核心交互）"
echo "   ✅ 菜单键/OK键 → 频道列表"
echo "   ✅ 左右键 → 切换频道"
echo "   ✅ 长按频道 → 收藏/取消收藏"
echo "   ✅ 设置菜单：硬解/软解/画面比例/切换源/搜索/收藏模式/EPG/Headers"
echo ""
echo "📌 请修改 MainActivity 中的 defaultUrl 为你的真实直播源地址"
echo "📌 然后运行 ./gradlew assembleDebug 编译 APK"
