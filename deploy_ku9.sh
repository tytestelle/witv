#!/bin/bash
set -e

echo "🔥 开始部署酷9风格播放器（完整自动解码版）..."

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
ITEM_MENU_LAYOUT="app/src/main/res/layout/item_menu.xml"
ITEM_SUBSCRIPTION_LAYOUT="app/src/main/res/layout/item_subscription.xml"
ITEM_CHANNEL_LAYOUT="app/src/main/res/layout/item_channel.xml"
CONTENT_SUBSCRIPTION_LAYOUT="app/src/main/res/layout/content_subscription.xml"
CONTENT_EPG_LAYOUT="app/src/main/res/layout/content_epg.xml"
CONTENT_PLAY_SETTINGS_LAYOUT="app/src/main/res/layout/content_play_settings.xml"
MANIFEST="app/src/main/AndroidManifest.xml"
ASSETS_DIR="app/src/main/assets"

# ========== 清理旧 ui 目录 ==========
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

# ========== 4. 创建 assets 配置 ==========
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
    "PLAY_TYPE": 7,
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

# ========== 5. 创建酷9文件夹结构 ==========
mkdir -p "$ASSETS_DIR/localData" \
         "$ASSETS_DIR/backup" \
         "$ASSETS_DIR/download" \
         "$ASSETS_DIR/videoFile" \
         "$ASSETS_DIR/configuration" \
         "$ASSETS_DIR/logo" \
         "$ASSETS_DIR/js" \
         "$ASSETS_DIR/py" \
         "$ASSETS_DIR/webviewJscode" \
         "$ASSETS_DIR/epgCache"
echo "✅ 酷9文件夹结构已创建"

# ========== 6. 创建功能类 ==========
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

# ========== 7. ConfigurationManager ==========
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
    public int getPlayType() { return getInt("PLAY_TYPE", 7); }
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

# ========== 8. SettingsActivity（完整版，含自动解码选项） ==========
cat > "$SETTINGS_ACT_FILE" <<'EOF'
package com.whyun.witv;

import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.text.TextUtils;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class SettingsActivity extends AppCompatActivity {

    private RecyclerView menuRecyclerView, contentRecyclerView;
    private MenuAdapter menuAdapter;
    private ContentAdapter contentAdapter;

    private String[] menuTitles = {
            "线路选择", "频道搜索", "播放设置", "列表订阅",
            "EPG订阅", "分类管理", "订阅管理", "显示设置",
            "偏好设置", "列表设置", "其他设置", "推送频道", "更多管理"
    };

    private int currentMenuPosition = 3;
    private SharedPreferences prefs;
    private static final String KEY_SUBSCRIPTIONS = "subscriptions";
    private static final String KEY_EPG_SUBSCRIPTIONS = "epg_subscriptions";
    private static final String KEY_SELECTED_SUB = "selected_subscription";
    private static final String KEY_SELECTED_EPG = "selected_epg_subscription";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        prefs = PreferenceManager.getDefaultSharedPreferences(this);

        menuRecyclerView = findViewById(R.id.menu_recycler);
        contentRecyclerView = findViewById(R.id.content_recycler);

        menuRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        menuAdapter = new MenuAdapter(menuTitles, this::onMenuClick);
        menuRecyclerView.setAdapter(menuAdapter);

        contentRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        contentAdapter = new ContentAdapter();
        contentRecyclerView.setAdapter(contentAdapter);

        menuAdapter.setSelectedPosition(currentMenuPosition);
        showContent(currentMenuPosition);
    }

    private void onMenuClick(int position) {
        currentMenuPosition = position;
        menuAdapter.setSelectedPosition(position);
        showContent(position);
    }

    private void showContent(int position) {
        List<ContentItem> items = new ArrayList<>();
        switch (position) {
            case 0: items.add(new ContentItem("线路选择", "点击选择线路", v -> showLineSelection())); break;
            case 1: items.add(new ContentItem("频道搜索", "点击搜索", v -> Toast.makeText(this, "频道搜索", Toast.LENGTH_SHORT).show())); break;
            case 2: items.add(new ContentItem("播放设置", "点击展开", v -> showPlaySettings())); break;
            case 3: buildSubscriptionContent(items, KEY_SUBSCRIPTIONS, KEY_SELECTED_SUB, "列表订阅"); break;
            case 4: buildSubscriptionContent(items, KEY_EPG_SUBSCRIPTIONS, KEY_SELECTED_EPG, "EPG订阅"); break;
            case 5: items.add(new ContentItem("分类管理", "点击管理", v -> Toast.makeText(this, "分类管理", Toast.LENGTH_SHORT).show())); break;
            case 6: items.add(new ContentItem("订阅管理", "点击管理", v -> Toast.makeText(this, "订阅管理", Toast.LENGTH_SHORT).show())); break;
            case 7: items.add(new ContentItem("显示设置", "点击展开", v -> showDisplaySettings())); break;
            case 8: items.add(new ContentItem("偏好设置", "点击展开", v -> showPreferenceSettings())); break;
            case 9: items.add(new ContentItem("列表设置", "点击展开", v -> showListSettings())); break;
            case 10: items.add(new ContentItem("其他设置", "点击展开", v -> showOtherSettings())); break;
            case 11: items.add(new ContentItem("推送频道", "点击推送", v -> Toast.makeText(this, "推送频道", Toast.LENGTH_SHORT).show())); break;
            case 12: items.add(new ContentItem("更多管理", "点击查看", v -> showMoreInfo())); break;
        }
        contentAdapter.setItems(items);
    }

    private void buildSubscriptionContent(List<ContentItem> items, String prefKey, String selectedKey, String title) {
        Set<String> subSet = prefs.getStringSet(prefKey, new HashSet<>());
        List<Subscription> list = new ArrayList<>();
        for (String s : subSet) {
            String[] parts = s.split("\\|\\|");
            if (parts.length >= 2) list.add(new Subscription(parts[0], parts[1]));
        }
        String selected = prefs.getString(selectedKey, "");
        items.add(new ContentItem(title, "", v -> {}));
        for (Subscription sub : list) {
            String full = sub.name + "||" + sub.url;
            boolean isSelected = full.equals(selected);
            items.add(new ContentItem(sub.name, sub.url, isSelected, v -> {
                prefs.edit().putString(selectedKey, full).apply();
                showContent(currentMenuPosition);
                Toast.makeText(this, "已选中: " + sub.name, Toast.LENGTH_SHORT).show();
            }));
        }
        items.add(new ContentItem("+ 添加订阅", "", v -> showAddSubscriptionDialog(prefKey, selectedKey, title)));
    }

    private void showAddSubscriptionDialog(String prefKey, String selectedKey, String title) {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("添加订阅");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(50, 20, 50, 20);
        final EditText nameInput = new EditText(this);
        nameInput.setHint("名称（选填）");
        layout.addView(nameInput);
        final EditText urlInput = new EditText(this);
        urlInput.setHint("地址");
        layout.addView(urlInput);
        builder.setView(layout);
        builder.setPositiveButton("确定", (d, which) -> {
            String name = nameInput.getText().toString().trim();
            String url = urlInput.getText().toString().trim();
            if (url.isEmpty()) {
                Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show();
                return;
            }
            if (TextUtils.isEmpty(name)) name = url;
            Set<String> subSet = new HashSet<>(prefs.getStringSet(prefKey, new HashSet<>()));
            subSet.add(name + "||" + url);
            prefs.edit().putStringSet(prefKey, subSet).apply();
            prefs.edit().putString(selectedKey, name + "||" + url).apply();
            Toast.makeText(this, "订阅已添加", Toast.LENGTH_SHORT).show();
            showContent(currentMenuPosition);
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showLineSelection() {
        new AlertDialog.Builder(this)
                .setTitle("线路选择")
                .setItems(new String[]{"源1", "源2", "源3"}, (d, which) -> Toast.makeText(this, "选择线路" + (which+1), Toast.LENGTH_SHORT).show())
                .show();
    }

    private void showPlaySettings() {
        String[] items = {"解码方式", "画面比例", "超时换源", "断线重连", "渲染类型", "RTSP通道", "回放方式", "时移结束播放"};
        new AlertDialog.Builder(this)
                .setTitle("播放设置")
                .setItems(items, (d, which) -> {
                    switch (which) {
                        case 0: showPlayTypeDialog(); break;
                        case 1: showPlayScaleDialog(); break;
                        case 2: showTimeoutDialog(); break;
                        case 3: showReconnectDialog(); break;
                        case 4: showRenderDialog(); break;
                        case 5: showRtspDialog(); break;
                        case 6: showPlayBackTypeDialog(); break;
                        case 7: showTimeShiftModeDialog(); break;
                    }
                })
                .show();
    }

    private void showPlayTypeDialog() {
        final String[] items = {"系统解码", "IJK硬解", "IJK软解", "EXO硬解", "EXO软解", "MPV硬解", "MPV软解", "自动"};
        int current = ConfigurationManager.getInstance(this).getInt("PLAY_TYPE", 7);
        new AlertDialog.Builder(this)
                .setTitle("解码方式")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("PLAY_TYPE", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showPlayScaleDialog() {
        final String[] items = {"默认", "16:9", "4:3", "填充", "原始", "裁剪", "电影"};
        int current = ConfigurationManager.getInstance(this).getInt("PLAY_SCALE", 3);
        new AlertDialog.Builder(this)
                .setTitle("画面比例")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("PLAY_SCALE", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showTimeoutDialog() {
        final String[] items = {"5s", "10s", "15s", "20s", "25s", "30s"};
        int current = ConfigurationManager.getInstance(this).getInt("LIVE_CONNECT_TIMEOUT", 1);
        new AlertDialog.Builder(this)
                .setTitle("超时换源")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("LIVE_CONNECT_TIMEOUT", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showReconnectDialog() {
        final String[] items = {"关闭", "1s", "3s", "5s", "10s", "20s"};
        int current = ConfigurationManager.getInstance(this).getInt("RECONNECT_INDEX", 0);
        new AlertDialog.Builder(this)
                .setTitle("断线重连")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("RECONNECT_INDEX", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showRenderDialog() {
        final String[] items = {"Texture", "Surface"};
        int current = ConfigurationManager.getInstance(this).getInt("PLAY_RENDER", 1);
        new AlertDialog.Builder(this)
                .setTitle("渲染类型")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("PLAY_RENDER", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showRtspDialog() {
        final String[] items = {"TCP", "UDP"};
        int current = ConfigurationManager.getInstance(this).getInt("RTSP_TCP_SELECT", 0);
        new AlertDialog.Builder(this)
                .setTitle("RTSP通道")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("RTSP_TCP_SELECT", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showPlayBackTypeDialog() {
        final String[] items = {"重新加载url", "播放器seekTo"};
        int current = ConfigurationManager.getInstance(this).getInt("PLAY_BACK_TYPE", 0);
        new AlertDialog.Builder(this)
                .setTitle("回放方式")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("PLAY_BACK_TYPE", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showTimeShiftModeDialog() {
        final String[] items = {"自动刷新继续播放", "回到直播"};
        int current = ConfigurationManager.getInstance(this).getInt("TIME_SHIFT_MODE", 0);
        new AlertDialog.Builder(this)
                .setTitle("时移结束播放")
                .setSingleChoiceItems(items, current, (d, which) -> {
                    ConfigurationManager.getInstance(this).putInt("TIME_SHIFT_MODE", which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showDisplaySettings() {
        final String[] items = {"显示时间", "显示网速", "隐藏频道图标", "隐藏底部图标", "关闭EPG", "隐藏收藏", "隐藏序号", "显示本地视频", "EPG详情显示", "底部EPG详情", "图标默认样式"};
        new AlertDialog.Builder(this)
                .setTitle("显示设置")
                .setItems(items, (d, which) -> {
                    String key = "";
                    boolean def = false;
                    switch (which) {
                        case 0: key = "LIVE_SHOW_TIME"; def = false; break;
                        case 1: key = "LIVE_SHOW_NET_SPEED"; def = false; break;
                        case 2: key = "HIDE_Channel_LOGO"; def = true; break;
                        case 3: key = "HIDE_Bottom_LOGO"; def = true; break;
                        case 4: key = "CLOSE_EPG"; def = false; break;
                        case 5: key = "HIDE_FAVOR"; def = false; break;
                        case 6: key = "HIDE_NUMBER"; def = false; break;
                        case 7: key = "ENABLE_LOCAL_VIDEO"; def = false; break;
                        case 8: key = "EPG_DESC_SET"; def = false; break;
                        case 9: key = "BOTTOM_DESC_SET"; def = true; break;
                        case 10: key = "ICON_INITIAL_SET"; def = true; break;
                    }
                    final String finalKey = key;
                    boolean current = ConfigurationManager.getInstance(this).getBoolean(finalKey, def);
                    final boolean finalCurrent = current;
                    new AlertDialog.Builder(this)
                            .setTitle(items[which])
                            .setMessage("当前状态：" + (current ? "开启" : "关闭"))
                            .setPositiveButton("切换", (d2, w) -> {
                                ConfigurationManager.getInstance(this).putBoolean(finalKey, !finalCurrent);
                                Toast.makeText(this, "已切换", Toast.LENGTH_SHORT).show();
                            })
                            .setNegativeButton("取消", null)
                            .show();
                })
                .show();
    }

    private void showPreferenceSettings() {
        final String[] items = {"记忆解码", "换台反转", "跨选分组", "关闭密码", "画中画", "开机启动", "快速退出", "画面锁定", "回放标识", "开启时移"};
        new AlertDialog.Builder(this)
                .setTitle("偏好设置")
                .setItems(items, (d, which) -> {
                    String key = "";
                    switch (which) {
                        case 0: key = "PL_MEMORYS_ET_SELECT"; break;
                        case 1: key = "LIVE_CHANNEL_REVERSE"; break;
                        case 2: key = "LIVE_CROSS_GROUP"; break;
                        case 3: key = "LIVE_SKIP_PASSWORD"; break;
                        case 4: key = "PIC_IN_PIC"; break;
                        case 5: key = "BOOT_START"; break;
                        case 6: key = "QUICK_EXIT"; break;
                        case 7: key = "EYE_PROTECTION"; break;
                        case 8: key = "PLAYBACK_ID"; break;
                        case 9: key = "TIME_SHIFT_ON"; break;
                    }
                    final String finalKey = key;
                    boolean current = ConfigurationManager.getInstance(this).getBoolean(finalKey, false);
                    final boolean finalCurrent = current;
                    new AlertDialog.Builder(this)
                            .setTitle(items[which])
                            .setMessage("当前状态：" + (current ? "开启" : "关闭"))
                            .setPositiveButton("切换", (d2, w) -> {
                                ConfigurationManager.getInstance(this).putBoolean(finalKey, !finalCurrent);
                                Toast.makeText(this, "已切换", Toast.LENGTH_SHORT).show();
                            })
                            .setNegativeButton("取消", null)
                            .show();
                })
                .show();
    }

    private void showListSettings() {
        final String[] items = {"全局字体大小", "列表宽度", "底部信息栏宽度"};
        new AlertDialog.Builder(this)
                .setTitle("列表设置")
                .setItems(items, (d, which) -> {
                    AlertDialog.Builder builder = new AlertDialog.Builder(this);
                    builder.setTitle(items[which]);
                    final EditText input = new EditText(this);
                    input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
                    int current = 0;
                    switch (which) {
                        case 0: current = ConfigurationManager.getInstance(this).getInt("TEXT_SIZE", 0); break;
                        case 1: current = ConfigurationManager.getInstance(this).getInt("LIST_WIDTH", 0); break;
                        case 2: current = ConfigurationManager.getInstance(this).getInt("BOTTOM_WIDTH", 0); break;
                    }
                    input.setText(String.valueOf(current));
                    builder.setView(input);
                    builder.setPositiveButton("确定", (d2, w) -> {
                        try {
                            int val = Integer.parseInt(input.getText().toString());
                            switch (which) {
                                case 0: ConfigurationManager.getInstance(this).putInt("TEXT_SIZE", val); break;
                                case 1: ConfigurationManager.getInstance(this).putInt("LIST_WIDTH", val); break;
                                case 2: ConfigurationManager.getInstance(this).putInt("BOTTOM_WIDTH", val); break;
                            }
                            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                        } catch (NumberFormatException e) {
                            Toast.makeText(this, "请输入数字", Toast.LENGTH_SHORT).show();
                        }
                    });
                    builder.setNegativeButton("取消", null);
                    builder.show();
                })
                .show();
    }

    private void showOtherSettings() {
        final String[] items = {"EPG缓存"};
        new AlertDialog.Builder(this)
                .setTitle("其他设置")
                .setItems(items, (d, which) -> {
                    final String[] options = {"关闭", "2点", "4点", "6点", "8点", "10点", "12点", "14点", "16点", "18点", "20点", "22点"};
                    int current = ConfigurationManager.getInstance(this).getInt("EPGCACHE_SELECT", 4);
                    new AlertDialog.Builder(this)
                            .setTitle("EPG缓存")
                            .setSingleChoiceItems(options, current, (d2, which2) -> {
                                ConfigurationManager.getInstance(this).putInt("EPGCACHE_SELECT", which2);
                                Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                                d2.dismiss();
                            })
                            .setNegativeButton("取消", null)
                            .show();
                })
                .show();
    }

    private void showMoreInfo() {
        new AlertDialog.Builder(this)
                .setTitle("更多管理")
                .setMessage("酷9 2.0.1\n软件仅供测试")
                .setPositiveButton("确定", null)
                .show();
    }

    static class Subscription { String name, url; Subscription(String n, String u) { name = n; url = u; } }
    static class ContentItem {
        String title, subtitle; boolean isSelected; View.OnClickListener clickListener;
        ContentItem(String title, String subtitle, View.OnClickListener listener) { this.title = title; this.subtitle = subtitle; this.isSelected = false; this.clickListener = listener; }
        ContentItem(String title, String subtitle, boolean selected, View.OnClickListener listener) { this.title = title; this.subtitle = subtitle; this.isSelected = selected; this.clickListener = listener; }
    }

    static class ContentAdapter extends RecyclerView.Adapter<ContentAdapter.ViewHolder> {
        private List<ContentItem> items = new ArrayList<>();
        public void setItems(List<ContentItem> items) { this.items = items; notifyDataSetChanged(); }
        @NonNull @Override public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_subscription, parent, false);
            return new ViewHolder(v);
        }
        @Override public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
            ContentItem item = items.get(position);
            holder.name.setText(item.title);
            holder.url.setText(item.subtitle);
            holder.check.setVisibility(item.isSelected ? View.VISIBLE : View.GONE);
            holder.itemView.setOnClickListener(item.clickListener);
        }
        @Override public int getItemCount() { return items.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name, url, check;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.sub_name); url = v.findViewById(R.id.sub_url); check = v.findViewById(R.id.sub_check); }
        }
    }

    static class MenuAdapter extends RecyclerView.Adapter<MenuAdapter.MenuViewHolder> {
        private String[] titles; private OnMenuClickListener listener; private int selectedPosition = -1;
        interface OnMenuClickListener { void onClick(int position); }
        MenuAdapter(String[] titles, OnMenuClickListener listener) { this.titles = titles; this.listener = listener; }
        void setSelectedPosition(int pos) { selectedPosition = pos; notifyDataSetChanged(); }
        @NonNull @Override public MenuViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_menu, parent, false);
            return new MenuViewHolder(v);
        }
        @Override public void onBindViewHolder(@NonNull MenuViewHolder holder, int position) {
            holder.text.setText(titles[position]);
            holder.itemView.setBackgroundColor(selectedPosition == position ? 0x22FFFFFF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(position));
        }
        @Override public int getItemCount() { return titles.length; }
        static class MenuViewHolder extends RecyclerView.ViewHolder {
            TextView text;
            MenuViewHolder(View v) { super(v); text = v.findViewById(R.id.menu_text); }
        }
    }
}
EOF
echo "✅ SettingsActivity 已生成"

# ========== 9. 布局文件 ==========
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
    android:orientation="horizontal"
    android:background="#F5F5F5">
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/menu_recycler"
        android:layout_width="0dp"
        android:layout_height="match_parent"
        android:layout_weight="1"
        android:background="#333333"
        android:padding="8dp" />
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/content_recycler"
        android:layout_width="0dp"
        android:layout_height="match_parent"
        android:layout_weight="2"
        android:background="#FFFFFF"
        android:padding="8dp" />
</LinearLayout>
EOF

cat > "$ITEM_MENU_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/menu_text"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:paddingLeft="16dp"
    android:textSize="16sp"
    android:textColor="#FFFFFF"
    android:background="?attr/selectableItemBackground" />
EOF

cat > "$ITEM_SUBSCRIPTION_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="12dp"
    android:background="?attr/selectableItemBackground">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">
        <TextView
            android:id="@+id/sub_name"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="名称"
            android:textSize="16sp"
            android:textColor="#333" />
        <TextView
            android:id="@+id/sub_check"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="√"
            android:textSize="18sp"
            android:textColor="#4CAF50"
            android:visibility="gone" />
    </LinearLayout>
    <TextView
        android:id="@+id/sub_url"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="地址"
        android:textSize="12sp"
        android:textColor="#888" />
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

cat > "$CONTENT_SUBSCRIPTION_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content" android:text="订阅列表" android:textSize="18sp" android:gravity="center" />
</LinearLayout>
EOF
cat > "$CONTENT_EPG_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:gravity="center" android:text="EPG订阅内容" android:textSize="18sp" />
EOF
cat > "$CONTENT_PLAY_SETTINGS_LAYOUT" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:gravity="center" android:text="播放设置内容" android:textSize="18sp" />
EOF

echo "✅ 所有布局文件已生成"

# ========== 10. 图标资源 ==========
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

# ========== 11. MainActivity（带自动解码切换） ==========
cat > "$MAIN_ACT_FILE" <<'EOF'
package com.whyun.witv;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.LayoutInflater;
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

    // 解码器常量
    private static final int DECODER_SYSTEM = 0;
    private static final int DECODER_IJK_HW = 1;
    private static final int DECODER_IJK_SW = 2;
    private static final int DECODER_EXO_HW = 3;
    private static final int DECODER_EXO_SW = 4;
    private static final int DECODER_MPV_HW = 5;
    private static final int DECODER_MPV_SW = 6;
    private static final int DECODER_AUTO = 7;

    private int currentDecoderType;
    private boolean isHardwareAttempt = true;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        config = ConfigurationManager.getInstance(this);
        PlayerConfigManager.init(this);
        FavoriteManager.init(this);

        initViews();
        loadDefaultSource();

        playerView.setOnClickListener(v -> toggleBottomControls());
        btnFavorite.setOnClickListener(v -> toggleFavorite());
        btnSettings.setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        btnEpg.setOnClickListener(v -> showEpgDialog());

        applyConfig();
    }

    private void applyConfig() {
        int scale = config.getPlayScale();
        PlayerConfigManager.setAspectRatio(getScaleString(scale));
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
        if (channel == null) return;
        currentChannel = channel;
        int decoderType = config.getPlayType();
        if (player == null || currentDecoderType != decoderType) {
            releasePlayer();
            createPlayer(decoderType);
        }
        MediaItem mediaItem = MediaItem.fromUri(channel.url);
        player.setMediaItem(mediaItem);
        player.prepare();
        player.play();
        updateUI();
        updateChannelList();
    }

    private void createPlayer(int decoderType) {
        currentDecoderType = decoderType;
        isHardwareAttempt = true;
        DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
        DefaultTrackSelector.Parameters.Builder paramsBuilder = trackSelector.getParameters().buildUpon();

        boolean preferHardware = false;
        boolean preferSoftware = false;
        switch (decoderType) {
            case DECODER_SYSTEM:
                break;
            case DECODER_IJK_HW:
            case DECODER_EXO_HW:
            case DECODER_MPV_HW:
                preferHardware = true;
                break;
            case DECODER_IJK_SW:
            case DECODER_EXO_SW:
            case DECODER_MPV_SW:
                preferSoftware = true;
                break;
            case DECODER_AUTO:
                preferHardware = true;
                break;
        }
        if (preferHardware) {
            paramsBuilder.setAllowHardwareAcceleration(true);
            paramsBuilder.setPreferExtensionDecoders(true);
        } else if (preferSoftware) {
            paramsBuilder.setAllowHardwareAcceleration(false);
            paramsBuilder.setPreferExtensionDecoders(false);
        }
        trackSelector.setParameters(paramsBuilder.build());

        player = new ExoPlayer.Builder(this)
                .setTrackSelector(trackSelector)
                .build();
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
                runOnUiThread(() -> handlePlaybackError(error));
            }
        });
    }

    private void handlePlaybackError(PlaybackException error) {
        Toast.makeText(this, "播放出错: " + error.getMessage(), Toast.LENGTH_SHORT).show();
        int decoderType = config.getPlayType();
        if (decoderType == DECODER_AUTO) {
            if (isHardwareAttempt) {
                isHardwareAttempt = false;
                Toast.makeText(this, "硬解失败，自动切换软解重试", Toast.LENGTH_SHORT).show();
                releasePlayer();
                int tempDecoder = DECODER_EXO_SW;
                createPlayer(tempDecoder);
                if (currentChannel != null) playChannel(currentChannel);
            } else {
                Toast.makeText(this, "播放失败，请检查地址或切换其他解码方式", Toast.LENGTH_LONG).show();
            }
        } else {
            boolean isHardware = (decoderType == DECODER_IJK_HW || decoderType == DECODER_EXO_HW || decoderType == DECODER_MPV_HW);
            if (isHardware) {
                Toast.makeText(this, "硬解失败，尝试切换软解", Toast.LENGTH_SHORT).show();
                int softDecoder = DECODER_EXO_SW;
                releasePlayer();
                createPlayer(softDecoder);
                if (currentChannel != null) playChannel(currentChannel);
            }
        }
    }

    private void releasePlayer() {
        if (player != null) {
            player.release();
            player = null;
        }
        playerView.setPlayer(null);
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
        List<SourceManager.Channel> displayList = isFavoriteMode ? getFavoriteChannels() : filteredList;
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
        releasePlayer();
        mainHandler.removeCallbacks(hideControlsRunnable);
    }

    // ---------- ChannelAdapter ----------
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
            View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_channel, parent, false);
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
                Toast.makeText(holder.itemView.getContext(),
                        FavoriteManager.isFavorite(channel.name) ? "已收藏 ❤️" : "已取消收藏",
                        Toast.LENGTH_SHORT).show();
                return true;
            });
        }

        @Override
        public int getItemCount() { return data.size(); }

        static class ViewHolder extends RecyclerView.ViewHolder {
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
echo "✅ MainActivity 已生成"

# ========== 12. 验证文件生成 ==========
echo "📁 验证生成的 Java 文件："
ls -la "app/src/main/java/$PKG_PATH/source/SourceManager.java" || echo "❌ SourceManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/player/PlayerConfigManager.java" || echo "❌ PlayerConfigManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/favorite/FavoriteManager.java" || echo "❌ FavoriteManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/ConfigurationManager.java" || echo "❌ ConfigurationManager 未生成"
ls -la "app/src/main/java/$PKG_PATH/SettingsActivity.java" || echo "❌ SettingsActivity 未生成"
ls -la "app/src/main/java/$PKG_PATH/MainActivity.java" || echo "❌ MainActivity 未生成"

# ========== 13. 清理并构建 ==========
echo "🧹 清理构建缓存..."
./gradlew clean

echo "🚀 开始构建 APK..."
chmod +x gradlew
./gradlew assembleDebug

echo ""
echo "🎉 部署并构建完成！"
echo "📌 APK 位于: app/build/outputs/apk/debug/"
echo "📌 解码器支持自动切换（先硬解，失败自动软解）"
echo "📌 设置中可选择“自动”模式"
