#!/bin/bash
set -e

echo "🔥 开始部署酷9风格播放器（最终修复版）..."

PKG="com.whyun.witv"
PKG_PATH="com/whyun/witv"
MAIN_ACT_SIMPLE="MainActivity"
MAIN_ACT_FILE="app/src/main/java/$PKG_PATH/$MAIN_ACT_SIMPLE.java"
SETTINGS_ACT_SIMPLE="SettingsActivity"
SETTINGS_ACT_FILE="app/src/main/java/$PKG_PATH/$SETTINGS_ACT_SIMPLE.java"
CONFIG_MGR_FILE="app/src/main/java/$PKG_PATH/ConfigurationManager.java"
LAYOUT_NAME="activity_main"
LAYOUT_FILE="app/src/main/res/layout/$LAYOUT_NAME.xml"
SETTINGS_LAYOUT="app/src/main/res/layout/activity_settings.xml"
ITEM_CONFIG_LAYOUT="app/src/main/res/layout/item_config.xml"
ITEM_CHANNEL_LAYOUT="app/src/main/res/layout/item_channel.xml"
MANIFEST="app/src/main/AndroidManifest.xml"
ASSETS_DIR="app/src/main/assets"

# ========== 清理旧的 ui 目录（避免冲突） ==========
rm -rf "app/src/main/java/com/whyun/witv/ui"
echo "✅ 已清理旧的 ui 目录"

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
sed -i '/dependencies {/a \    // 酷9依赖\n    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
echo "✅ 依赖已添加"

# ========== 2. 添加权限 ==========
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
echo "✅ 权限已添加"

# ========== 3. 修改 AndroidManifest（注册 SettingsActivity） ==========
echo "🛠️ 修改 AndroidManifest.xml..."
python3 <<PYTHON_SCRIPT
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom

ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')

manifest_file = "$MANIFEST"
pkg = "com.whyun.witv"
act = "MainActivity"
settings_act = "SettingsActivity"

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

# 删除所有旧 activity
for activity in application.findall('activity'):
    application.remove(activity)

# 主 Activity
main_act = ET.Element('activity')
main_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.{act}")
main_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
intent_filter = ET.SubElement(main_act, 'intent-filter')
action = ET.SubElement(intent_filter, 'action')
action.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.action.MAIN')
category = ET.SubElement(intent_filter, 'category')
category.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.category.LAUNCHER')
application.append(main_act)

# Settings Activity
settings_act_el = ET.Element('activity')
settings_act_el.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.{settings_act}")
settings_act_el.set('{http://schemas.android.com/apk/res/android}exported', 'true')
application.append(settings_act_el)

xml_str = ET.tostring(root, encoding='unicode')
dom = minidom.parseString(xml_str)
pretty_xml = dom.toprettyxml(indent="    ")
pretty_xml = '\n'.join(pretty_xml.split('\n')[1:]) if pretty_xml.startswith('<?xml') else pretty_xml
with open(manifest_file, 'w') as f:
    f.write(pretty_xml)

print("✅ AndroidManifest.xml 已修改（含 SettingsActivity）")
PYTHON_SCRIPT

# ========== 4. 创建 assets 目录并放置 configuration.json ==========
mkdir -p "$ASSETS_DIR"
cat > "$ASSETS_DIR/configuration.json" <<'EOF'
{
  "Configuration": {
    "提醒": "配置文件在configuration文件夹内不存在的情况下会自动复制到app的configuration文件夹下，已存在就不会复制及覆盖，首次安装也就是无任何缓存数据的情况下才会读取配置文件，提示部分只读取一次，只读取一次，只读取一次！！！",
    "loginPng": "/storage/emulated/0/酷9/bg.png",
    "exitPng": "https://ExitImageUrl",
    "updateUrl": "http://ku9/app/update.json",
    "hideLoginText": false,
    "loginText": "正在加载数据，请稍后...",
    "loginTextColor": "#FF000000",
    "progressBarColor": "#FF00BCD4",
    "speed_timeColor": "#26000000",
    "speed_timeRadius": 10,
    "EXO_bufferForPlaybackMs": 2500,
    "IJK_analyzeduration": 2000000,
    "IJK_probesize": 4096000,
    "MPV_analyzeduration": 0,
    "selected_ChannelNumber_Color": "#FF70C439",
    "loginPng_Dwell_time": 200,
    "CUSTOM_BACKGROUND_COLOR": "#036D80,#052D49$BL_TR",
    "time_format": "HH:mm EE",
    "Speed_value": "0.5,3,0.25,0.5,1,2",
    "icon_background_color": "#32FFFFFF",
    "LIVE_URLS": "http://io8.myartsonline.com/z/5c.txt$5c直播",
    "EPG_URLS": null,
    "LIVE_JSONS": null,
    "HEADERS_URLS": null,
    "USER_AGENTS": "OKhttp/1.31 || Mozilla/5.0 || SYTV/1.6$预置SYTV/1.6",
    "PLAY_TYPE": 1,
    "PLAY_SCALE": 3,
    "LIVE_CONNECT_TIMEOUT": 1,
    "LIVE_SHOW_TIME": false,
    "LIVE_SHOW_NET_SPEED": false,
    "HIDE_Channel_LOGO": true,
    "HIDE_Bottom_LOGO": true,
    "CLOSE_EPG": false,
    "HIDE_FAVOR": false,
    "HIDE_NUMBER": false,
    "PL_MEMORYS_ET_SELECT": false,
    "LIVE_CHANNEL_REVERSE": false,
    "LIVE_CROSS_GROUP": false,
    "LIVE_SKIP_PASSWORD": false,
    "PIC_IN_PIC": false,
    "BOOT_START": false,
    "QUICK_EXIT": false,
    "EYE_PROTECTION": false,
    "PLAYBACK_ID": false,
    "TIME_SHIFT_ON": true,
    "PLAY_RENDER": 1,
    "DOH_URL": 0,
    "THEME_SELECT": 2,
    "PLAY_BACK_TYPE": 0,
    "RECONNECT_INDEX": 0,
    "EXO_TUNNELING_SELECT": false,
    "RTSP_TCP_SELECT": 0,
    "NAVIGATION_SELECT": 0,
    "EPG_SHOW_TYPE_SELECT": 0,
    "TEXT_SIZE": 0,
    "LIST_WIDTH": 0,
    "BOTTOM_WIDTH": 0,
    "EPGCACHE_SELECT": 4,
    "IMAGECACHE_SELECT": false,
    "SCRIPT_CACHE": true,
    "MEMORYS_SOURCE": true,
    "MEMORYS_POSITION": true,
    "BACKGROUND_THEME_SELECT": 6,
    "BOOTRECEIVER_SET_SELECT": true,
    "SHORTCUTS_MENU": false,
    "SHORTCUTS_MENU_SELECT": "列表订阅,EPG订阅,无线投屏,频道搜索,APP信息",
    "GROUP_PARS_SET_SELECT": 3,
    "PLAY_ALL_SOURCE": true,
    "RESOLUTION_MODE_SELECT": 0,
    "TIME_ZONE_SELECT": 0,
    "TIME_SHIFT_MODE": 0,
    "ENABLE_LOCAL_VIDEO": false,
    "M3U_LOGO_PRIORITY": false,
    "EPG_DESC_SET": false,
    "BOTTOM_DESC_SET": true,
    "ICON_INITIAL_SET": true,
    "EPG_CACHE_PATH_SET": false,
    "AUDIO_WAKKPAPER": false,
    "DE_INTERLACING": false
  }
}
EOF
echo "✅ configuration.json 已创建"

# ========== 5. 创建功能类 ==========
mkdir -p "app/src/main/java/$PKG_PATH/source"
mkdir -p "app/src/main/java/$PKG_PATH/player"
mkdir -p "app/src/main/java/$PKG_PATH/favorite"
mkdir -p "app/src/main/java/$PKG_PATH/epg"

# SourceManager
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

# ========== 6. 创建 ConfigurationManager ==========
cat > "$CONFIG_MGR_FILE" <<'EOF'
package com.whyun.witv;

import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import java.io.InputStream;
import java.io.InputStreamReader;

public class ConfigurationManager {
    private static ConfigurationManager instance;
    private JsonObject config;
    private SharedPreferences prefs;

    private ConfigurationManager(Context context) {
        prefs = PreferenceManager.getDefaultSharedPreferences(context);
        loadConfig(context);
    }

    public static synchronized ConfigurationManager getInstance(Context context) {
        if (instance == null) {
            instance = new ConfigurationManager(context.getApplicationContext());
        }
        return instance;
    }

    private void loadConfig(Context context) {
        try {
            InputStream is = context.getAssets().open("configuration.json");
            InputStreamReader reader = new InputStreamReader(is);
            JsonObject root = new Gson().fromJson(reader, JsonObject.class);
            config = root.getAsJsonObject("Configuration");
            is.close();
        } catch (Exception e) {
            e.printStackTrace();
            config = new JsonObject();
        }
    }

    public String getString(String key, String def) {
        if (prefs.contains(key)) {
            return prefs.getString(key, def);
        }
        if (config.has(key)) {
            return config.get(key).getAsString();
        }
        return def;
    }

    public int getInt(String key, int def) {
        if (prefs.contains(key)) {
            return prefs.getInt(key, def);
        }
        if (config.has(key)) {
            return config.get(key).getAsInt();
        }
        return def;
    }

    public boolean getBoolean(String key, boolean def) {
        if (prefs.contains(key)) {
            return prefs.getBoolean(key, def);
        }
        if (config.has(key)) {
            return config.get(key).getAsBoolean();
        }
        return def;
    }

    public void putInt(String key, int value) {
        prefs.edit().putInt(key, value).apply();
    }

    public void putBoolean(String key, boolean value) {
        prefs.edit().putBoolean(key, value).apply();
    }

    public void putString(String key, String value) {
        prefs.edit().putString(key, value).apply();
    }

    // 常用配置快捷方法
    public int getPlayType() { return getInt("PLAY_TYPE", 1); }
    public int getPlayScale() { return getInt("PLAY_SCALE", 3); }
    public boolean getShowTime() { return getBoolean("LIVE_SHOW_TIME", false); }
    public boolean getShowNetSpeed() { return getBoolean("LIVE_SHOW_NET_SPEED", false); }
    public boolean getHideLogo() { return getBoolean("HIDE_Channel_LOGO", true); }
    public boolean getHideBottomLogo() { return getBoolean("HIDE_Bottom_LOGO", true); }
    public boolean getCloseEpg() { return getBoolean("CLOSE_EPG", false); }
    public boolean getHideFavor() { return getBoolean("HIDE_FAVOR", false); }
    public boolean getHideNumber() { return getBoolean("HIDE_NUMBER", false); }
    public boolean getMemorizeDecoder() { return getBoolean("PL_MEMORYS_ET_SELECT", false); }
    public boolean getChannelReverse() { return getBoolean("LIVE_CHANNEL_REVERSE", false); }
    public boolean getCrossGroup() { return getBoolean("LIVE_CROSS_GROUP", false); }
    public boolean getSkipPassword() { return getBoolean("LIVE_SKIP_PASSWORD", false); }
    public boolean getPicInPic() { return getBoolean("PIC_IN_PIC", false); }
    public boolean getBootStart() { return getBoolean("BOOT_START", false); }
    public boolean getQuickExit() { return getBoolean("QUICK_EXIT", false); }
    public boolean getEyeProtection() { return getBoolean("EYE_PROTECTION", false); }
    public boolean getPlaybackId() { return getBoolean("PLAYBACK_ID", false); }
    public boolean getTimeShiftOn() { return getBoolean("TIME_SHIFT_ON", true); }
    public int getPlayRender() { return getInt("PLAY_RENDER", 1); }
    public int getDohUrl() { return getInt("DOH_URL", 0); }
    public int getThemeSelect() { return getInt("THEME_SELECT", 2); }
    public int getPlayBackType() { return getInt("PLAY_BACK_TYPE", 0); }
    public int getReconnectIndex() { return getInt("RECONNECT_INDEX", 0); }
    public boolean getExoTunneling() { return getBoolean("EXO_TUNNELING_SELECT", false); }
    public int getRtspTcpSelect() { return getInt("RTSP_TCP_SELECT", 0); }
    public int getNavigationSelect() { return getInt("NAVIGATION_SELECT", 0); }
    public int getEpgShowType() { return getInt("EPG_SHOW_TYPE_SELECT", 0); }
    public int getTextSize() { return getInt("TEXT_SIZE", 0); }
    public int getListWidth() { return getInt("LIST_WIDTH", 0); }
    public int getBottomWidth() { return getInt("BOTTOM_WIDTH", 0); }
    public int getEpgCacheSelect() { return getInt("EPGCACHE_SELECT", 4); }
    public boolean getImageCache() { return getBoolean("IMAGECACHE_SELECT", false); }
    public boolean getScriptCache() { return getBoolean("SCRIPT_CACHE", true); }
    public boolean getMemorizeSource() { return getBoolean("MEMORYS_SOURCE", true); }
    public boolean getMemorizePosition() { return getBoolean("MEMORYS_POSITION", true); }
    public int getBackgroundTheme() { return getInt("BACKGROUND_THEME_SELECT", 6); }
    public boolean getBootReceiverSet() { return getBoolean("BOOTRECEIVER_SET_SELECT", true); }
    public boolean getShortcutsMenu() { return getBoolean("SHORTCUTS_MENU", false); }
    public String getShortcutsMenuSelect() { return getString("SHORTCUTS_MENU_SELECT", "列表订阅,EPG订阅,无线投屏,频道搜索,APP信息"); }
    public int getGroupParsSet() { return getInt("GROUP_PARS_SET_SELECT", 3); }
    public boolean getPlayAllSource() { return getBoolean("PLAY_ALL_SOURCE", true); }
    public int getResolutionMode() { return getInt("RESOLUTION_MODE_SELECT", 0); }
    public int getTimeZoneSelect() { return getInt("TIME_ZONE_SELECT", 0); }
    public int getTimeShiftMode() { return getInt("TIME_SHIFT_MODE", 0); }
    public boolean getEnableLocalVideo() { return getBoolean("ENABLE_LOCAL_VIDEO", false); }
    public boolean getM3uLogoPriority() { return getBoolean("M3U_LOGO_PRIORITY", false); }
    public boolean getEpgDesc() { return getBoolean("EPG_DESC_SET", false); }
    public boolean getBottomDesc() { return getBoolean("BOTTOM_DESC_SET", true); }
    public boolean getIconInitial() { return getBoolean("ICON_INITIAL_SET", true); }
    public boolean getEpgCachePath() { return getBoolean("EPG_CACHE_PATH_SET", false); }
    public boolean getAudioWallpaper() { return getBoolean("AUDIO_WAKKPAPER", false); }
    public boolean getDeInterlacing() { return getBoolean("DE_INTERLACING", false); }
}
EOF
echo "✅ ConfigurationManager 已创建"

# ========== 7. 创建 SettingsActivity（使用 RecyclerView） ==========
cat > "$SETTINGS_ACT_FILE" <<'EOF'
package com.whyun.witv;

import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.switchmaterial.SwitchMaterial;
import java.util.ArrayList;
import java.util.List;

public class SettingsActivity extends AppCompatActivity {

    private ConfigurationManager config;
    private RecyclerView recyclerView;
    private ConfigAdapter adapter;
    private List<ConfigItem> items = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        config = ConfigurationManager.getInstance(this);
        recyclerView = findViewById(R.id.settings_recycler);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));

        buildConfigItems();
        adapter = new ConfigAdapter(items);
        recyclerView.setAdapter(adapter);
    }

    private void buildConfigItems() {
        items.add(new ConfigItem("解码方式", "PLAY_TYPE", ConfigItem.TYPE_SPINNER,
                new String[]{"系统解码", "IJK硬解", "IJK软解", "EXO硬解", "EXO软解", "MPV硬解", "MPV软解"},
                config.getInt("PLAY_TYPE", 1)));

        items.add(new ConfigItem("画面比例", "PLAY_SCALE", ConfigItem.TYPE_SPINNER,
                new String[]{"默认", "16:9", "4:3", "填充", "原始", "裁剪", "电影"},
                config.getInt("PLAY_SCALE", 3)));

        items.add(new ConfigItem("超时换源", "LIVE_CONNECT_TIMEOUT", ConfigItem.TYPE_SPINNER,
                new String[]{"5s", "10s", "15s", "20s", "25s", "30s"},
                config.getInt("LIVE_CONNECT_TIMEOUT", 1)));

        items.add(new ConfigItem("显示时间", "LIVE_SHOW_TIME", ConfigItem.TYPE_SWITCH,
                config.getBoolean("LIVE_SHOW_TIME", false)));

        items.add(new ConfigItem("显示网速", "LIVE_SHOW_NET_SPEED", ConfigItem.TYPE_SWITCH,
                config.getBoolean("LIVE_SHOW_NET_SPEED", false)));

        items.add(new ConfigItem("隐藏频道图标", "HIDE_Channel_LOGO", ConfigItem.TYPE_SWITCH,
                config.getBoolean("HIDE_Channel_LOGO", true)));

        items.add(new ConfigItem("隐藏底部图标", "HIDE_Bottom_LOGO", ConfigItem.TYPE_SWITCH,
                config.getBoolean("HIDE_Bottom_LOGO", true)));

        items.add(new ConfigItem("关闭EPG", "CLOSE_EPG", ConfigItem.TYPE_SWITCH,
                config.getBoolean("CLOSE_EPG", false)));

        items.add(new ConfigItem("隐藏收藏", "HIDE_FAVOR", ConfigItem.TYPE_SWITCH,
                config.getBoolean("HIDE_FAVOR", false)));

        items.add(new ConfigItem("隐藏序号", "HIDE_NUMBER", ConfigItem.TYPE_SWITCH,
                config.getBoolean("HIDE_NUMBER", false)));

        items.add(new ConfigItem("记忆解码", "PL_MEMORYS_ET_SELECT", ConfigItem.TYPE_SWITCH,
                config.getBoolean("PL_MEMORYS_ET_SELECT", false)));

        items.add(new ConfigItem("换台反转", "LIVE_CHANNEL_REVERSE", ConfigItem.TYPE_SWITCH,
                config.getBoolean("LIVE_CHANNEL_REVERSE", false)));

        items.add(new ConfigItem("跨选分组", "LIVE_CROSS_GROUP", ConfigItem.TYPE_SWITCH,
                config.getBoolean("LIVE_CROSS_GROUP", false)));

        items.add(new ConfigItem("关闭密码", "LIVE_SKIP_PASSWORD", ConfigItem.TYPE_SWITCH,
                config.getBoolean("LIVE_SKIP_PASSWORD", false)));

        items.add(new ConfigItem("画中画", "PIC_IN_PIC", ConfigItem.TYPE_SWITCH,
                config.getBoolean("PIC_IN_PIC", false)));

        items.add(new ConfigItem("开机启动", "BOOT_START", ConfigItem.TYPE_SWITCH,
                config.getBoolean("BOOT_START", false)));

        items.add(new ConfigItem("快速退出", "QUICK_EXIT", ConfigItem.TYPE_SWITCH,
                config.getBoolean("QUICK_EXIT", false)));

        items.add(new ConfigItem("画面锁定", "EYE_PROTECTION", ConfigItem.TYPE_SWITCH,
                config.getBoolean("EYE_PROTECTION", false)));

        items.add(new ConfigItem("回放标识", "PLAYBACK_ID", ConfigItem.TYPE_SWITCH,
                config.getBoolean("PLAYBACK_ID", false)));

        items.add(new ConfigItem("开启时移", "TIME_SHIFT_ON", ConfigItem.TYPE_SWITCH,
                config.getBoolean("TIME_SHIFT_ON", true)));

        items.add(new ConfigItem("渲染类型", "PLAY_RENDER", ConfigItem.TYPE_SPINNER,
                new String[]{"Texture", "Surface"},
                config.getInt("PLAY_RENDER", 1)));

        items.add(new ConfigItem("安全DNS", "DOH_URL", ConfigItem.TYPE_SPINNER,
                new String[]{"关闭", "腾讯", "阿里", "360", "Google", "AdGuard", "Quad9"},
                config.getInt("DOH_URL", 0)));

        items.add(new ConfigItem("主题类型", "THEME_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"},
                config.getInt("THEME_SELECT", 2)));

        items.add(new ConfigItem("回放方式", "PLAY_BACK_TYPE", ConfigItem.TYPE_SPINNER,
                new String[]{"重新加载url", "播放器seekTo"},
                config.getInt("PLAY_BACK_TYPE", 0)));

        items.add(new ConfigItem("断线重连", "RECONNECT_INDEX", ConfigItem.TYPE_SPINNER,
                new String[]{"关闭", "1s", "3s", "5s", "10s", "20s"},
                config.getInt("RECONNECT_INDEX", 0)));

        items.add(new ConfigItem("EXO隧道模式", "EXO_TUNNELING_SELECT", ConfigItem.TYPE_SWITCH,
                config.getBoolean("EXO_TUNNELING_SELECT", false)));

        items.add(new ConfigItem("RTSP通道", "RTSP_TCP_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"TCP", "UDP"},
                config.getInt("RTSP_TCP_SELECT", 0)));

        items.add(new ConfigItem("导航栏模式", "NAVIGATION_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"滑动显示", "一直显示", "触摸显示"},
                config.getInt("NAVIGATION_SELECT", 0)));

        items.add(new ConfigItem("EPG展示", "EPG_SHOW_TYPE_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"折叠展示", "一直展示"},
                config.getInt("EPG_SHOW_TYPE_SELECT", 0)));

        items.add(new ConfigItem("全局字体大小", "TEXT_SIZE", ConfigItem.TYPE_EDIT,
                config.getInt("TEXT_SIZE", 0)));

        items.add(new ConfigItem("列表宽度", "LIST_WIDTH", ConfigItem.TYPE_EDIT,
                config.getInt("LIST_WIDTH", 0)));

        items.add(new ConfigItem("底部信息栏宽度", "BOTTOM_WIDTH", ConfigItem.TYPE_EDIT,
                config.getInt("BOTTOM_WIDTH", 0)));

        items.add(new ConfigItem("EPG缓存", "EPGCACHE_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"关闭", "2点", "4点", "6点", "8点", "10点", "12点", "14点", "16点", "18点", "20点", "22点"},
                config.getInt("EPGCACHE_SELECT", 4)));

        items.add(new ConfigItem("图标缓存", "IMAGECACHE_SELECT", ConfigItem.TYPE_SWITCH,
                config.getBoolean("IMAGECACHE_SELECT", false)));

        items.add(new ConfigItem("脚本缓存", "SCRIPT_CACHE", ConfigItem.TYPE_SWITCH,
                config.getBoolean("SCRIPT_CACHE", true)));

        items.add(new ConfigItem("记忆多源", "MEMORYS_SOURCE", ConfigItem.TYPE_SWITCH,
                config.getBoolean("MEMORYS_SOURCE", true)));

        items.add(new ConfigItem("记忆进度", "MEMORYS_POSITION", ConfigItem.TYPE_SWITCH,
                config.getBoolean("MEMORYS_POSITION", true)));

        items.add(new ConfigItem("背景色系", "BACKGROUND_THEME_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"},
                config.getInt("BACKGROUND_THEME_SELECT", 6)));

        items.add(new ConfigItem("列表分组模式", "GROUP_PARS_SET_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"传统分组", "列表分组", "二级分组模式1", "二级分组模式2"},
                config.getInt("GROUP_PARS_SET_SELECT", 3)));

        items.add(new ConfigItem("遍历多源循环", "PLAY_ALL_SOURCE", ConfigItem.TYPE_SWITCH,
                config.getBoolean("PLAY_ALL_SOURCE", true)));

        items.add(new ConfigItem("分辨率显示样式", "RESOLUTION_MODE_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"缩写", "数字x数字"},
                config.getInt("RESOLUTION_MODE_SELECT", 0)));

        items.add(new ConfigItem("XML时间偏移", "TIME_ZONE_SELECT", ConfigItem.TYPE_SPINNER,
                new String[]{"默认", "-12", "-11", "-10", "-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1",
                        "0", "+1", "+2", "+3", "+4", "+5", "+6", "+7", "+8", "+9", "+10", "+11", "+12"},
                config.getInt("TIME_ZONE_SELECT", 0)));

        items.add(new ConfigItem("时移结束播放", "TIME_SHIFT_MODE", ConfigItem.TYPE_SPINNER,
                new String[]{"自动刷新继续播放", "回到直播"},
                config.getInt("TIME_SHIFT_MODE", 0)));

        items.add(new ConfigItem("显示本地视频", "ENABLE_LOCAL_VIDEO", ConfigItem.TYPE_SWITCH,
                config.getBoolean("ENABLE_LOCAL_VIDEO", false)));

        items.add(new ConfigItem("图标优先级", "M3U_LOGO_PRIORITY", ConfigItem.TYPE_SWITCH,
                config.getBoolean("M3U_LOGO_PRIORITY", false)));

        items.add(new ConfigItem("EPG详情显示", "EPG_DESC_SET", ConfigItem.TYPE_SWITCH,
                config.getBoolean("EPG_DESC_SET", false)));

        items.add(new ConfigItem("底部EPG详情", "BOTTOM_DESC_SET", ConfigItem.TYPE_SWITCH,
                config.getBoolean("BOTTOM_DESC_SET", true)));

        items.add(new ConfigItem("图标默认样式", "ICON_INITIAL_SET", ConfigItem.TYPE_SWITCH,
                config.getBoolean("ICON_INITIAL_SET", true)));

        items.add(new ConfigItem("EPG缓存路径", "EPG_CACHE_PATH_SET", ConfigItem.TYPE_SWITCH,
                config.getBoolean("EPG_CACHE_PATH_SET", false)));

        items.add(new ConfigItem("音频壁纸", "AUDIO_WAKKPAPER", ConfigItem.TYPE_SWITCH,
                config.getBoolean("AUDIO_WAKKPAPER", false)));

        items.add(new ConfigItem("反交错", "DE_INTERLACING", ConfigItem.TYPE_SWITCH,
                config.getBoolean("DE_INTERLACING", false)));
    }

    // ---------- ConfigItem 数据类 ----------
    static class ConfigItem {
        static final int TYPE_SWITCH = 0;
        static final int TYPE_SPINNER = 1;
        static final int TYPE_EDIT = 2;

        String title, key;
        int type;
        Object value;
        String[] spinnerOptions;

        ConfigItem(String title, String key, int type, boolean val) {
            this.title = title; this.key = key; this.type = type;
            this.value = val;
        }
        ConfigItem(String title, String key, int type, String[] options, int selected) {
            this.title = title; this.key = key; this.type = type;
            this.spinnerOptions = options;
            this.value = selected;
        }
        ConfigItem(String title, String key, int type, int val) {
            this.title = title; this.key = key; this.type = type;
            this.value = val;
        }
    }

    // ---------- Adapter ----------
    class ConfigAdapter extends RecyclerView.Adapter<ConfigAdapter.ViewHolder> {
        private List<ConfigItem> data;

        ConfigAdapter(List<ConfigItem> data) { this.data = data; }

        @Override
        public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View view = getLayoutInflater().inflate(R.layout.item_config, parent, false);
            return new ViewHolder(view);
        }

        @Override
        public void onBindViewHolder(ViewHolder holder, int position) {
            ConfigItem item = data.get(position);
            holder.title.setText(item.title);
            holder.container.removeAllViews();

            if (item.type == ConfigItem.TYPE_SWITCH) {
                SwitchMaterial sw = new SwitchMaterial(SettingsActivity.this);
                sw.setChecked((Boolean) item.value);
                sw.setOnCheckedChangeListener((buttonView, isChecked) -> {
                    config.putBoolean(item.key, isChecked);
                    item.value = isChecked;
                    Toast.makeText(SettingsActivity.this, "已保存", Toast.LENGTH_SHORT).show();
                });
                holder.container.addView(sw);
            } else if (item.type == ConfigItem.TYPE_SPINNER) {
                Spinner spinner = new Spinner(SettingsActivity.this);
                ArrayAdapter<String> adapter = new ArrayAdapter<>(SettingsActivity.this,
                        android.R.layout.simple_spinner_dropdown_item, item.spinnerOptions);
                spinner.setAdapter(adapter);
                spinner.setSelection((Integer) item.value);
                spinner.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent, View view, int pos, long id) {
                        config.putInt(item.key, pos);
                        item.value = pos;
                    }
                    @Override
                    public void onNothingSelected(android.widget.AdapterView<?> parent) {}
                });
                holder.container.addView(spinner);
            } else if (item.type == ConfigItem.TYPE_EDIT) {
                EditText edit = new EditText(SettingsActivity.this);
                edit.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
                edit.setText(String.valueOf(item.value));
                edit.setHint("数值");
                edit.setOnFocusChangeListener((v, hasFocus) -> {
                    if (!hasFocus) {
                        try {
                            int val = Integer.parseInt(edit.getText().toString());
                            config.putInt(item.key, val);
                            item.value = val;
                            Toast.makeText(SettingsActivity.this, "已保存", Toast.LENGTH_SHORT).show();
                        } catch (NumberFormatException ignored) {}
                    }
                });
                holder.container.addView(edit);
            }
        }

        @Override
        public int getItemCount() { return data.size(); }

        class ViewHolder extends RecyclerView.ViewHolder {
            TextView title;
            LinearLayout container;
            ViewHolder(View itemView) {
                super(itemView);
                title = itemView.findViewById(R.id.config_title);
                container = itemView.findViewById(R.id.config_container);
            }
        }
    }
}
EOF
echo "✅ SettingsActivity 已创建"

# ========== 8. 生成布局文件 ==========
cat > "$LAYOUT_FILE" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:use_controller="false"
        app:shutter_background_color="#000000" />

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/channel_list"
        android:layout_width="280dp"
        android:layout_height="match_parent"
        android:background="#CC000000"
        android:visibility="gone"
        android:paddingTop="60dp"
        android:paddingBottom="60dp" />

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

cat > "$SETTINGS_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="#F5F5F5">

    <androidx.appcompat.widget.Toolbar
        android:id="@+id/toolbar"
        android:layout_width="match_parent"
        android:layout_height="?attr/actionBarSize"
        android:background="?attr/colorPrimary"
        android:title="设置"
        android:titleTextColor="#FFFFFF" />

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/settings_recycler"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:padding="8dp" />
</LinearLayout>
EOF

cat > "$ITEM_CONFIG_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="12dp"
    android:background="#FFFFFF"
    android:layout_marginBottom="4dp">

    <TextView
        android:id="@+id/config_title"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:text="标题"
        android:textSize="16sp"
        android:textColor="#333333"
        android:layout_gravity="center_vertical" />

    <LinearLayout
        android:id="@+id/config_container"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical" />
</LinearLayout>
EOF

cat > "$ITEM_CHANNEL_LAYOUT" <<'EOF'
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
echo "✅ 布局文件已生成"

# ========== 9. 添加图标资源 ==========
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
echo "✅ 图标资源已添加"

# ========== 10. 生成最终的 MainActivity（ChannelAdapter 改为静态内部类） ==========
cat > "$MAIN_ACT_FILE" <<'EOF'
package com.whyun.witv;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
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
import java.util.Set;

public class MainActivity extends AppCompatActivity {

    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> channelList = new ArrayList<>();
    private List<SourceManager.Channel> filteredList = new ArrayList<>();

    private TextView bottomChannelName, bottomEpgInfo;
    private ImageView btnFavorite, btnSettings, btnEpg;
    private View bottomControls;
    private RecyclerView channelListView;
    private ChannelAdapter channelAdapter;
    private boolean isChannelListVisible = false;
    private boolean isFavoriteMode = false;
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    private ConfigurationManager config;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        config = ConfigurationManager.getInstance(this);
        PlayerConfigManager.init(this);
        FavoriteManager.init(this);

        initViews();
        initPlayer();
        loadDefaultSource();

        playerView.setOnClickListener(v -> toggleBottomControls());
        btnFavorite.setOnClickListener(v -> toggleFavorite());
        btnSettings.setOnClickListener(v -> {
            startActivity(new Intent(this, SettingsActivity.class));
        });
        btnEpg.setOnClickListener(v -> showEpgDialog());

        applyConfig();
    }

    private void applyConfig() {
        PlayerConfigManager.setDecoder(config.getPlayType());
        PlayerConfigManager.setAspectRatio(getScaleString(config.getPlayScale()));
    }

    private String getScaleString(int scale) {
        switch (scale) {
            case 1: return "16:9";
            case 2: return "4:3";
            case 3: return "填充";
            case 4: return "原始";
            case 5: return "裁剪";
            case 6: return "电影";
            default: return "默认";
        }
    }

    private void initViews() {
        playerView = findViewById(R.id.player_container);
        bottomControls = findViewById(R.id.bottom_controls);
        bottomChannelName = findViewById(R.id.bottom_channel_name);
        bottomEpgInfo = findViewById(R.id.bottom_epg_info);
        btnFavorite = findViewById(R.id.btn_favorite);
        btnSettings = findViewById(R.id.btn_settings);
        btnEpg = findViewById(R.id.btn_epg);

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
        String defaultUrl = config.getString("LIVE_URLS", "https://example.com/channels.m3u");
        if (defaultUrl.contains("$")) {
            defaultUrl = defaultUrl.substring(0, defaultUrl.indexOf("$"));
        }
        SourceManager sourceManager = new SourceManager(this);
        sourceManager.loadFromUrl(defaultUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(List<SourceManager.Channel> channels) {
                channelList = channels;
                filteredList = new ArrayList<>(channels);
                if (!channels.isEmpty()) {
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

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_UP) {
            float x = event.getX();
            float width = getWindowManager().getDefaultDisplay().getWidth();
            if (x < width * 0.3) {
                toggleChannelList();
                return true;
            } else if (x > width * 0.7) {
                startActivity(new Intent(this, SettingsActivity.class));
                return true;
            }
        }
        return super.onTouchEvent(event);
    }

    private void toggleChannelList() {
        if (isChannelListVisible) hideChannelList();
        else showChannelList();
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
            if (favSet.contains(ch.name)) favs.add(ch);
        }
        return favs;
    }

    private void showEpgDialog() {
        String epgUrl = config.getString("EPG_URLS", "");
        if (epgUrl.isEmpty()) {
            Toast.makeText(this, "请先在设置中配置EPG地址", Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "📡 EPG: " + epgUrl, Toast.LENGTH_LONG).show();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK:
                startActivity(new Intent(this, SettingsActivity.class));
                return true;
            case KeyEvent.KEYCODE_MENU:
                toggleChannelList();
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                playPreviousChannel();
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                playNextChannel();
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                toggleChannelList();
                return true;
            default:
                return super.onKeyDown(keyCode, event);
        }
    }

    private void playPreviousChannel() {
        if (channelList.isEmpty()) return;
        int idx = getCurrentChannelIndex();
        if (idx > 0) playChannel(channelList.get(idx - 1));
        else playChannel(channelList.get(channelList.size() - 1));
    }

    private void playNextChannel() {
        if (channelList.isEmpty()) return;
        int idx = getCurrentChannelIndex();
        if (idx < channelList.size() - 1) playChannel(channelList.get(idx + 1));
        else playChannel(channelList.get(0));
    }

    private int getCurrentChannelIndex() {
        if (currentChannel == null || channelList.isEmpty()) return 0;
        for (int i = 0; i < channelList.size(); i++) {
            if (channelList.get(i).name.equals(currentChannel.name)) return i;
        }
        return 0;
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) { player.release(); player = null; }
        mainHandler.removeCallbacks(hideControlsRunnable);
    }

    // ---------- 静态内部类 ChannelAdapter ----------
    private static class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
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
            View view = parent.getContext().getSystemService(android.view.LayoutInflater.class)
                    .inflate(R.layout.item_channel, parent, false);
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
            holder.itemView.setOnLongClickListener(v -> {
                FavoriteManager.toggleFavorite(channel.name);
                notifyItemChanged(position);
                Toast.makeText(parent.getContext(),
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
echo "✅ MainActivity 已生成（ChannelAdapter 为静态内部类）"

# ========== 11. 验证文件生成 ==========
echo "📁 验证生成的 Java 文件："
ls -la "app/src/main/java/$PKG_PATH/source/SourceManager.java" || echo "❌ SourceManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/player/PlayerConfigManager.java" || echo "❌ PlayerConfigManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/favorite/FavoriteManager.java" || echo "❌ FavoriteManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/ConfigurationManager.java" || echo "❌ ConfigurationManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/SettingsActivity.java" || echo "❌ SettingsActivity 未生成"
ls -la "app/src/main/java/$PKG_PATH/MainActivity.java" || echo "❌ MainActivity 未生成"

# ========== 12. 清理并构建 APK ==========
echo "🧹 清理构建缓存..."
./gradlew clean

echo "🚀 开始构建 APK..."
chmod +x gradlew
./gradlew assembleDebug

# ========== 13. 完成 ==========
echo ""
echo "🎉 部署并构建完成！"
echo "📌 APK 位于: app/build/outputs/apk/debug/"
echo ""
echo "📌 酷9配置系统已集成："
echo "   ✅ assets/configuration.json – 完整配置"
echo "   ✅ ConfigurationManager – 配置管理"
echo "   ✅ SettingsActivity – 完整设置界面"
echo "   ✅ MainActivity – 应用解码、比例等核心配置"
echo ""
echo "📌 如需修改直播源，请编辑 assets/configuration.json 中的 LIVE_URLS"
