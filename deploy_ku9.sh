#!/bin/bash
set -e

echo "🔥 开始部署酷9风格播放器（模板外置版）..."

# 定义模板目录
TEMPLATE_DIR="./template"
PKG="com.whyun.witv"
PKG_PATH="com/whyun/witv"
SRC_JAVA="app/src/main/java/$PKG_PATH"
RES_LAYOUT="app/src/main/res/layout"
RES_DRAWABLE="app/src/main/res/drawable"
ASSETS_DIR="app/src/main/assets"
MANIFEST="app/src/main/AndroidManifest.xml"
APP_GRADLE="app/build.gradle"

# ========== 1. 检查模板目录是否存在，若不存在则创建 ==========
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "📁 首次运行，创建模板目录并写入所有文件..."
    mkdir -p "$TEMPLATE_DIR/java" "$TEMPLATE_DIR/res/layout" "$TEMPLATE_DIR/res/drawable" "$TEMPLATE_DIR/assets"

    # 写入 Java 源文件 (所有类)
    cat > "$TEMPLATE_DIR/java/SourceManager.java" <<'EOF'
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
    public interface OnSourceLoadListener {
        void onLoaded(List<Channel> channels);
        void onError(String error);
    }
    public SourceManager(Context context) { this.context = context; }
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
    private void parseTXT(String content) {
        String[] lines = content.split("\n");
        for (String line : lines) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] parts = line.split(",");
            if (parts.length >= 2) {
                String name = parts[0].trim();
                String url = parts[1].trim();
                String group = parts.length >= 3 ? parts[2].trim() : "";
                channels.add(new Channel(name, url, group));
            }
        }
    }
    private void parseM3U(String content) { /* 暂不实现 */ }
    public static class Channel {
        public String name, url, group;
        public Channel(String n, String u, String g) { name = n; url = u; group = g; }
    }
}
EOF

    cat > "$TEMPLATE_DIR/java/PlayerConfigManager.java" <<'EOF'
package com.whyun.witv.player;
import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
public class PlayerConfigManager {
    private static SharedPreferences prefs;
    public static void init(Context ctx) { prefs = PreferenceManager.getDefaultSharedPreferences(ctx); }
    public static String getAspectRatio() { return prefs.getString("aspect_ratio", "16:9"); }
    public static void setAspectRatio(String ratio) { prefs.edit().putString("aspect_ratio", ratio).apply(); }
}
EOF

    cat > "$TEMPLATE_DIR/java/FavoriteManager.java" <<'EOF'
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
    }
}
EOF

    cat > "$TEMPLATE_DIR/java/ConfigurationManager.java" <<'EOF'
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
        if (instance == null) instance = new ConfigurationManager(context.getApplicationContext());
        return instance;
    }
    private void loadConfig(Context context) {
        try {
            InputStream is = context.getAssets().open("configuration.json");
            JsonObject root = new Gson().fromJson(new InputStreamReader(is), JsonObject.class);
            config = root.getAsJsonObject("Configuration");
            is.close();
        } catch (Exception e) { config = new JsonObject(); }
    }
    public String getString(String key, String def) {
        if (prefs.contains(key)) return prefs.getString(key, def);
        if (config.has(key)) return config.get(key).getAsString();
        return def;
    }
    public int getInt(String key, int def) {
        if (prefs.contains(key)) return prefs.getInt(key, def);
        if (config.has(key)) return config.get(key).getAsInt();
        return def;
    }
    public boolean getBoolean(String key, boolean def) {
        if (prefs.contains(key)) return prefs.getBoolean(key, def);
        if (config.has(key)) return config.get(key).getAsBoolean();
        return def;
    }
    public void putInt(String key, int value) { prefs.edit().putInt(key, value).apply(); }
    public void putBoolean(String key, boolean value) { prefs.edit().putBoolean(key, value).apply(); }
    public void putString(String key, String value) { prefs.edit().putString(key, value).apply(); }
    public int getPlayType() { return getInt("PLAY_TYPE", 7); }
    public int getPlayScale() { return getInt("PLAY_SCALE", 3); }
    public boolean getShowTime() { return getBoolean("LIVE_SHOW_TIME", false); }
    public boolean getShowNetSpeed() { return getBoolean("LIVE_SHOW_NET_SPEED", false); }
    public boolean getHideLogo() { return getBoolean("HIDE_Channel_LOGO", true); }
    public boolean getHideBottomLogo() { return getBoolean("HIDE_Bottom_LOGO", true); }
    public boolean getCloseEpg() { return getBoolean("CLOSE_EPG", false); }
    public boolean getHideFavor() { return getBoolean("HIDE_FAVOR", false); }
    public boolean getHideNumber() { return getBoolean("HIDE_NUMBER", false); }
}
EOF

    cat > "$TEMPLATE_DIR/java/SettingsActivity.java" <<'EOF'
package com.whyun.witv;
import android.app.AlertDialog;
import android.os.Bundle;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;
public class SettingsActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        Toast.makeText(this, "设置界面", Toast.LENGTH_SHORT).show();
    }
}
EOF

    cat > "$TEMPLATE_DIR/java/MainActivity.java" <<'EOF'
package com.whyun.witv;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
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

public class MainActivity extends AppCompatActivity {
    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> channelList = new ArrayList<>();
    private RecyclerView channelListView;
    private ChannelAdapter channelAdapter;
    private ConfigurationManager config;
    private boolean isChannelListVisible = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        config = ConfigurationManager.getInstance(this);
        PlayerConfigManager.init(this);
        FavoriteManager.init(this);

        playerView = findViewById(R.id.player_container);
        channelListView = findViewById(R.id.channel_list);
        channelListView.setLayoutManager(new LinearLayoutManager(this));
        channelAdapter = new ChannelAdapter(new ArrayList<>(), channel -> {
            playChannel(channel);
            hideChannelList();
        });
        channelListView.setAdapter(channelAdapter);

        findViewById(R.id.btn_settings).setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));

        loadDefaultSource();
        playerView.setOnClickListener(v -> toggleChannelList());
    }

    private void loadDefaultSource() {
        String url = config.getString("LIVE_URLS", "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8");
        if (url.contains("$")) url = url.substring(0, url.indexOf("$"));
        new SourceManager(this).loadFromUrl(url, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(List<SourceManager.Channel> channels) {
                channelList = channels;
                if (!channels.isEmpty()) {
                    channelAdapter.updateData(channels);
                    playChannel(channels.get(0));
                }
                showChannelList();
            }
            @Override
            public void onError(String error) {
                Toast.makeText(MainActivity.this, "加载失败: " + error, Toast.LENGTH_LONG).show();
            }
        });
    }

    private void playChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentChannel = channel;
        if (player == null) {
            DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
            player = new ExoPlayer.Builder(this).setTrackSelector(trackSelector).build();
            playerView.setPlayer(player);
            player.addListener(new Player.Listener() {
                @Override
                public void onPlayerError(PlaybackException error) {
                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "播放错误: " + error.getMessage(), Toast.LENGTH_SHORT).show());
                }
            });
        }
        MediaItem mediaItem = MediaItem.fromUri(channel.url);
        player.setMediaItem(mediaItem);
        player.prepare();
        player.play();
        Toast.makeText(this, "正在播放: " + channel.name, Toast.LENGTH_SHORT).show();
    }

    private void toggleChannelList() {
        if (isChannelListVisible) hideChannelList();
        else showChannelList();
    }
    private void showChannelList() { isChannelListVisible = true; channelListView.setVisibility(View.VISIBLE); }
    private void hideChannelList() { isChannelListVisible = false; channelListView.setVisibility(View.GONE); }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) { player.release(); player = null; }
    }

    private static class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private OnChannelClickListener listener;
        interface OnChannelClickListener { void onClick(SourceManager.Channel channel); }
        ChannelAdapter(List<SourceManager.Channel> data, OnChannelClickListener listener) {
            this.data = data; this.listener = listener;
        }
        void updateData(List<SourceManager.Channel> newData) { this.data = newData; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_channel, parent, false);
            return new ViewHolder(view);
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SourceManager.Channel channel = data.get(position);
            holder.name.setText(channel.name);
            holder.itemView.setOnClickListener(v -> listener.onClick(channel));
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View itemView) { super(itemView); name = itemView.findViewById(R.id.channel_name); }
        }
    }
}
EOF

    # 布局文件
    cat > "$TEMPLATE_DIR/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">
    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:background="#000000" />
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/channel_list"
        android:layout_width="280dp"
        android:layout_height="match_parent"
        android:background="#CC000000"
        android:visibility="gone"
        android:paddingTop="60dp"
        android:paddingBottom="60dp" />
    <ImageView
        android:id="@+id/btn_settings"
        android:layout_width="40dp"
        android:layout_height="40dp"
        android:src="@drawable/ic_settings"
        android:layout_alignParentTop="true"
        android:layout_alignParentEnd="true"
        android:layout_margin="16dp"
        android:padding="8dp"
        android:background="#88000000"
        android:tint="#FFFFFF" />
</RelativeLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/activity_settings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content" android:text="设置界面" android:textSize="20sp" android:gravity="center" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_channel.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/channel_name"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:paddingLeft="16dp"
    android:textColor="#FFFFFF"
    android:textSize="16sp"
    android:background="?attr/selectableItemBackground" />
EOF

    # 图标资源
    cat > "$TEMPLATE_DIR/res/drawable/ic_settings.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94s-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z"/>
</vector>
EOF

    # assets/configuration.json (默认使用测试源，用户可自行修改)
    cat > "$TEMPLATE_DIR/assets/configuration.json" <<'EOF'
{
  "Configuration": {
    "LIVE_URLS": "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8$Apple测试",
    "EPG_URLS": null,
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

    echo "✅ 模板已生成到 $TEMPLATE_DIR/"
fi

# ========== 2. 从模板复制文件到项目 ==========
echo "📂 从模板复制文件到项目..."

# 备份已有的 gradle 和 manifest (已在前面备份)
# 这里直接覆盖或复制

# 复制 Java 源文件
mkdir -p "$SRC_JAVA/source" "$SRC_JAVA/player" "$SRC_JAVA/favorite"
cp "$TEMPLATE_DIR/java/SourceManager.java" "$SRC_JAVA/source/"
cp "$TEMPLATE_DIR/java/PlayerConfigManager.java" "$SRC_JAVA/player/"
cp "$TEMPLATE_DIR/java/FavoriteManager.java" "$SRC_JAVA/favorite/"
cp "$TEMPLATE_DIR/java/ConfigurationManager.java" "$SRC_JAVA/"
cp "$TEMPLATE_DIR/java/SettingsActivity.java" "$SRC_JAVA/"
cp "$TEMPLATE_DIR/java/MainActivity.java" "$SRC_JAVA/"

# 复制布局文件
mkdir -p "$RES_LAYOUT"
cp "$TEMPLATE_DIR/res/layout/activity_main.xml" "$RES_LAYOUT/"
cp "$TEMPLATE_DIR/res/layout/activity_settings.xml" "$RES_LAYOUT/"
cp "$TEMPLATE_DIR/res/layout/item_channel.xml" "$RES_LAYOUT/"

# 复制图标
mkdir -p "$RES_DRAWABLE"
cp "$TEMPLATE_DIR/res/drawable/ic_settings.xml" "$RES_DRAWABLE/"

# 复制 assets
mkdir -p "$ASSETS_DIR"
cp "$TEMPLATE_DIR/assets/configuration.json" "$ASSETS_DIR/"

echo "✅ 文件复制完成"

# ========== 3. 其他必要步骤（依赖、权限、Manifest 等） ==========
# 这些步骤与之前类似，但不再包含大量文件内容，故精简

# 添加依赖（必须）
cp "$APP_GRADLE" "$APP_GRADLE.bak"
sed -i '/implementation.*exoplayer/d' "$APP_GRADLE"
sed -i '/implementation.*okhttp/d' "$APP_GRADLE"
sed -i '/implementation.*gson/d' "$APP_GRADLE"
sed -i '/implementation.*preference/d' "$APP_GRADLE"
sed -i '/dependencies {/a \    // 酷9依赖\n    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
echo "✅ 依赖已添加"

# 权限（略，已在前备份中处理）
# 但为了保证，可再添加一次
sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
echo "✅ 权限已添加"

# AndroidManifest 修改（注册 Activity），使用 Python 脚本（略，与之前相同，但为了精简可保留）

# 构建
echo "🧹 清理构建缓存..."
./gradlew clean

echo "🚀 开始构建 APK..."
chmod +x gradlew
./gradlew assembleDebug

echo ""
echo "🎉 构建完成！APK 位于 app/build/outputs/apk/debug/"
echo "📌 如需修改源地址，请编辑 template/assets/configuration.json 或直接修改 app/src/main/assets/configuration.json"
