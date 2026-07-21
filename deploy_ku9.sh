#!/bin/bash
set -e

echo "🔥 部署酷9播放器（完全复刻版 - 三栏UI + EPG）"

# ========== 1. 生成模板目录（仅首次） ==========
TEMPLATE_DIR="./template"
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "📁 首次运行，生成模板文件..."
    mkdir -p "$TEMPLATE_DIR"/{src,res/layout,res/drawable,res/values}
    mkdir -p "$TEMPLATE_DIR/src/epg"
    mkdir -p "$TEMPLATE_DIR/src/player"
    mkdir -p "$TEMPLATE_DIR/src/favorite"

    # configuration.json（内置源为 null）
    cat > "$TEMPLATE_DIR/configuration.json" <<'EOF'
{"Configuration":{"LIVE_URLS":null,"EPG_URLS":null,"PLAY_TYPE":7,"PLAY_SCALE":3,"LIVE_CONNECT_TIMEOUT":1,"LIVE_SHOW_TIME":false,"LIVE_SHOW_NET_SPEED":false,"HIDE_Channel_LOGO":true,"HIDE_Bottom_LOGO":true,"CLOSE_EPG":false,"HIDE_FAVOR":false,"HIDE_NUMBER":false,"PL_MEMORYS_ET_SELECT":false,"LIVE_CHANNEL_REVERSE":false,"LIVE_CROSS_GROUP":false,"LIVE_SKIP_PASSWORD":false,"PIC_IN_PIC":false,"BOOT_START":false,"QUICK_EXIT":false,"EYE_PROTECTION":false,"PLAYBACK_ID":false,"TIME_SHIFT_ON":true,"PLAY_RENDER":1,"DOH_URL":0,"THEME_SELECT":2,"PLAY_BACK_TYPE":0,"RECONNECT_INDEX":0,"EXO_TUNNELING_SELECT":false,"RTSP_TCP_SELECT":0,"NAVIGATION_SELECT":0,"EPG_SHOW_TYPE_SELECT":0,"TEXT_SIZE":0,"LIST_WIDTH":0,"BOTTOM_WIDTH":0,"EPGCACHE_SELECT":4,"IMAGECACHE_SELECT":false,"SCRIPT_CACHE":true,"MEMORYS_SOURCE":true,"MEMORYS_POSITION":true,"BACKGROUND_THEME_SELECT":6,"BOOTRECEIVER_SET_SELECT":true,"SHORTCUTS_MENU":false,"SHORTCUTS_MENU_SELECT":"列表订阅,EPG订阅,无线投屏,频道搜索,APP信息","GROUP_PARS_SET_SELECT":3,"PLAY_ALL_SOURCE":true,"RESOLUTION_MODE_SELECT":0,"TIME_ZONE_SELECT":0,"TIME_SHIFT_MODE":0,"ENABLE_LOCAL_VIDEO":false,"M3U_LOGO_PRIORITY":false,"EPG_DESC_SET":false,"BOTTOM_DESC_SET":true,"ICON_INITIAL_SET":true,"EPG_CACHE_PATH_SET":false,"AUDIO_WAKKPAPER":false,"DE_INTERLACING":false}}
EOF

    # ==================== Java 源文件 ====================
    # SourceManager.java
    cat > "$TEMPLATE_DIR/src/SourceManager.java" <<'EOF'
package com.whyun.witv.source;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class SourceManager {
    private Context context;
    private Map<String, List<Channel>> groupMap = new HashMap<>();
    private List<String> groupNames = new ArrayList<>();
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    public interface OnSourceLoadListener { void onLoaded(Map<String, List<Channel>> groupMap, List<String> groupNames); void onError(String error); }
    public SourceManager(Context context) { this.context = context; }
    public void loadFromUrl(String url, OnSourceLoadListener listener) {
        new Thread(() -> {
            try {
                OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                    .build();
                Request request = new Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                    .build();
                Response response = client.newCall(request).execute();
                if (response.code() != 200) throw new Exception("HTTP " + response.code());
                String content = response.body().string();
                if (content == null || content.trim().isEmpty()) throw new Exception("内容为空");
                if (url.endsWith(".m3u") || url.endsWith(".m3u8") || content.contains("#EXTM3U")) {
                    parseM3U(content);
                } else {
                    parseTXT(content);
                }
                if (groupMap.isEmpty()) throw new Exception("未解析到任何频道");
                mainHandler.post(() -> listener.onLoaded(groupMap, groupNames));
            } catch (Exception e) {
                mainHandler.post(() -> listener.onError(e.getMessage()));
            }
        }).start();
    }
    private void parseTXT(String content) {
        groupMap.clear();
        groupNames.clear();
        for (String line : content.split("\n")) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] parts = line.split(",");
            if (parts.length >= 2) {
                String name = parts[0].trim();
                String url = parts[1].trim();
                String group = (parts.length >= 3 && !parts[2].trim().isEmpty()) ? parts[2].trim() : "默认分组";
                Channel ch = new Channel(name, url, group);
                if (!groupMap.containsKey(group)) {
                    groupMap.put(group, new ArrayList<>());
                    groupNames.add(group);
                }
                groupMap.get(group).add(ch);
            }
        }
    }
    private void parseM3U(String content) {
        groupMap.clear();
        groupNames.clear();
        String[] lines = content.split("\n");
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.startsWith("#EXTINF:")) {
                String name = line.substring(line.indexOf(",") + 1);
                if (i + 1 < lines.length) {
                    String url = lines[i + 1].trim();
                    if (!url.isEmpty() && !url.startsWith("#")) {
                        String group = "默认分组";
                        int gidx = line.indexOf("group-title=\"");
                        if (gidx != -1) {
                            int end = line.indexOf("\"", gidx + 13);
                            if (end != -1) group = line.substring(gidx + 13, end);
                        }
                        Channel ch = new Channel(name, url, group);
                        if (!groupMap.containsKey(group)) {
                            groupMap.put(group, new ArrayList<>());
                            groupNames.add(group);
                        }
                        groupMap.get(group).add(ch);
                    }
                }
            }
        }
    }
    public static class Channel {
        public String name, url, group;
        public Channel(String n, String u, String g) { name=n; url=u; group=g; }
    }
}
EOF

    # EPGParser.java
    cat > "$TEMPLATE_DIR/src/epg/EPGParser.java" <<'EOF'
package com.whyun.witv.epg;
import android.util.Xml;
import org.xmlpull.v1.XmlPullParser;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class EPGParser {
    public interface OnEpgLoadListener { void onLoaded(List<EpgProgram> programs); void onError(String error); }
    public static void loadEpg(String url, String channelName, OnEpgLoadListener listener) {
        new Thread(() -> {
            try {
                OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                    .build();
                Request request = new Request.Builder().url(url).build();
                Response response = client.newCall(request).execute();
                if (response.code() != 200) throw new Exception("HTTP " + response.code());
                InputStream is = response.body().byteStream();
                List<EpgProgram> programs = parseXmltv(is, channelName);
                listener.onLoaded(programs);
            } catch (Exception e) {
                listener.onError(e.getMessage());
            }
        }).start();
    }
    private static List<EpgProgram> parseXmltv(InputStream is, String channelName) throws Exception {
        List<EpgProgram> result = new ArrayList<>();
        XmlPullParser parser = Xml.newPullParser();
        parser.setInput(is, "UTF-8");
        int event = parser.getEventType();
        String currentTag = "";
        String currentTitle = "";
        String currentStart = "";
        String currentStop = "";
        String currentDesc = "";
        boolean inProgramme = false;
        while (event != XmlPullParser.END_DOCUMENT) {
            switch (event) {
                case XmlPullParser.START_TAG:
                    currentTag = parser.getName();
                    if ("programme".equals(currentTag)) {
                        inProgramme = true;
                        currentStart = parser.getAttributeValue(null, "start");
                        currentStop = parser.getAttributeValue(null, "stop");
                        currentTitle = "";
                        currentDesc = "";
                    }
                    break;
                case XmlPullParser.TEXT:
                    if (inProgramme) {
                        String text = parser.getText().trim();
                        if ("title".equals(currentTag)) currentTitle += text;
                        else if ("desc".equals(currentTag)) currentDesc += text;
                    }
                    break;
                case XmlPullParser.END_TAG:
                    if ("programme".equals(parser.getName())) {
                        inProgramme = false;
                        if (!currentTitle.isEmpty()) {
                            EpgProgram prog = new EpgProgram();
                            prog.title = currentTitle;
                            prog.desc = currentDesc;
                            try {
                                SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US);
                                prog.startTime = sdf.parse(currentStart + " +0000").getTime();
                                prog.endTime = sdf.parse(currentStop + " +0000").getTime();
                            } catch (Exception e) { /* 忽略 */ }
                            result.add(prog);
                        }
                    }
                    break;
            }
            event = parser.next();
        }
        return result;
    }
    public static class EpgProgram {
        public long startTime, endTime;
        public String title, desc;
    }
}
EOF

    # PlayerConfigManager.java
    cat > "$TEMPLATE_DIR/src/player/PlayerConfigManager.java" <<'EOF'
package com.whyun.witv.player;
import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
public class PlayerConfigManager {
    private static SharedPreferences prefs;
    public static void init(Context ctx) { prefs = PreferenceManager.getDefaultSharedPreferences(ctx); }
    public static String getAspectRatio() { return prefs.getString("aspect_ratio", "默认"); }
    public static void setAspectRatio(String ratio) { prefs.edit().putString("aspect_ratio", ratio).apply(); }
    public static int getDecoder() { return prefs.getInt("decoder", 7); }
    public static void setDecoder(int mode) { prefs.edit().putInt("decoder", mode).apply(); }
    public static boolean getShowTime() { return prefs.getBoolean("show_time", false); }
    public static void setShowTime(boolean val) { prefs.edit().putBoolean("show_time", val).apply(); }
    public static boolean getShowNetSpeed() { return prefs.getBoolean("show_net_speed", false); }
    public static void setShowNetSpeed(boolean val) { prefs.edit().putBoolean("show_net_speed", val).apply(); }
}
EOF

    # FavoriteManager.java
    cat > "$TEMPLATE_DIR/src/favorite/FavoriteManager.java" <<'EOF'
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
        if (!cur) favSet.add(channelId); else favSet.remove(channelId);
        prefs.edit().putStringSet("fav_list", favSet).apply();
    }
    public static Set<String> getAllFavorites() {
        return new HashSet<>(prefs.getStringSet("fav_list", new HashSet<>()));
    }
}
EOF

    # ConfigurationManager.java
    cat > "$TEMPLATE_DIR/src/ConfigurationManager.java" <<'EOF'
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
    public String getLiveUrls() { return getString("LIVE_URLS", null); }
}
EOF

    # MainActivity.java（三栏UI）
    cat > "$TEMPLATE_DIR/src/MainActivity.java" <<'EOF'
package com.whyun.witv;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
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
import com.whyun.witv.source.SourceManager;
import com.whyun.witv.epg.EPGParser;
import com.whyun.witv.player.PlayerConfigManager;
import com.whyun.witv.favorite.FavoriteManager;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
public class MainActivity extends AppCompatActivity {
    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> currentChannelList = new ArrayList<>();
    private Map<String, List<SourceManager.Channel>> groupMap = new HashMap<>();
    private List<String> groupNames = new ArrayList<>();
    private String currentGroup = "";
    private RecyclerView groupRecycler, channelRecycler, epgRecycler;
    private GroupAdapter groupAdapter;
    private ChannelAdapter channelAdapter;
    private EpgAdapter epgAdapter;
    private View overlayLayout;
    private SharedPreferences prefs;
    private ConfigurationManager config;
    private boolean isOverlayVisible = false;
    private Set<String> favoriteSet = new HashSet<>();
    private static final String KEY_FAVORITES = "favorites";
    private static final String KEY_SELECTED_GROUP = "selected_group";
    private static final String KEY_SELECTED_CHANNEL = "selected_channel";
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        config = ConfigurationManager.getInstance(this);
        PlayerConfigManager.init(this);
        FavoriteManager.init(this);
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        favoriteSet = new HashSet<>(prefs.getStringSet(KEY_FAVORITES, new HashSet<>()));
        playerView = findViewById(R.id.player_container);
        overlayLayout = findViewById(R.id.overlay_layout);
        groupRecycler = findViewById(R.id.group_recycler);
        channelRecycler = findViewById(R.id.channel_recycler);
        epgRecycler = findViewById(R.id.epg_recycler);
        groupRecycler.setLayoutManager(new LinearLayoutManager(this));
        channelRecycler.setLayoutManager(new LinearLayoutManager(this));
        epgRecycler.setLayoutManager(new LinearLayoutManager(this));
        groupAdapter = new GroupAdapter(new ArrayList<>(), group -> {
            currentGroup = group;
            prefs.edit().putString(KEY_SELECTED_GROUP, group).apply();
            showChannelsForGroup(group);
            groupAdapter.setSelectedGroup(group);
        });
        groupRecycler.setAdapter(groupAdapter);
        channelAdapter = new ChannelAdapter(new ArrayList<>(), channel -> {
            playChannel(channel);
            loadEpgForChannel(channel);
            prefs.edit().putString(KEY_SELECTED_CHANNEL, channel.name).apply();
            channelAdapter.setSelectedChannel(channel);
        }, this::toggleFavorite);
        channelRecycler.setAdapter(channelAdapter);
        epgAdapter = new EpgAdapter(new ArrayList<>());
        epgRecycler.setAdapter(epgAdapter);
        playerView.setOnClickListener(v -> toggleOverlay());
        ImageButton btnSettings = findViewById(R.id.btn_settings);
        btnSettings.setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        loadSource();
        String lastGroup = prefs.getString(KEY_SELECTED_GROUP, "");
        String lastChannel = prefs.getString(KEY_SELECTED_CHANNEL, "");
        if (!lastGroup.isEmpty()) currentGroup = lastGroup;
        if (!lastChannel.isEmpty()) { /* 将在加载完成后恢复 */ }
    }
    private void loadSource() {
        String url = prefs.getString("selected_sub_url", null);
        if (url == null || url.isEmpty()) {
            url = config.getLiveUrls();
            if (url == null || url.isEmpty()) {
                Toast.makeText(this, "请先添加并选中一个订阅源（设置 -> 列表订阅）", Toast.LENGTH_LONG).show();
                return;
            }
        }
        if (url.contains("$")) url = url.substring(0, url.indexOf("$"));
        new SourceManager(this).loadFromUrl(url, new SourceManager.OnSourceLoadListener() {
            @Override public void onLoaded(Map<String, List<SourceManager.Channel>> map, List<String> names) {
                groupMap = map;
                groupNames = names;
                if (!groupNames.contains("我的收藏")) {
                    groupNames.add(0, "我的收藏");
                }
                List<String> displayGroups = new ArrayList<>(groupNames);
                groupAdapter.updateData(displayGroups);
                String targetGroup = currentGroup;
                if (!groupNames.contains(targetGroup) && !groupNames.isEmpty()) {
                    targetGroup = groupNames.get(0);
                }
                if (!targetGroup.isEmpty()) {
                    currentGroup = targetGroup;
                    groupAdapter.setSelectedGroup(targetGroup);
                    showChannelsForGroup(targetGroup);
                }
                String lastChannelName = prefs.getString(KEY_SELECTED_CHANNEL, "");
                if (!lastChannelName.isEmpty()) {
                    for (SourceManager.Channel ch : currentChannelList) {
                        if (ch.name.equals(lastChannelName)) {
                            channelAdapter.setSelectedChannel(ch);
                            playChannel(ch);
                            loadEpgForChannel(ch);
                            break;
                        }
                    }
                }
                showOverlay();
            }
            @Override public void onError(String error) {
                Toast.makeText(MainActivity.this, "加载源失败: " + error, Toast.LENGTH_LONG).show();
            }
        });
    }
    private void showChannelsForGroup(String group) {
        if ("我的收藏".equals(group)) {
            List<SourceManager.Channel> favChannels = new ArrayList<>();
            for (List<SourceManager.Channel> list : groupMap.values()) {
                for (SourceManager.Channel ch : list) {
                    if (favoriteSet.contains(ch.name)) {
                        favChannels.add(ch);
                    }
                }
            }
            currentChannelList = favChannels;
        } else {
            List<SourceManager.Channel> list = groupMap.get(group);
            if (list == null) list = new ArrayList<>();
            currentChannelList = list;
        }
        channelAdapter.updateData(currentChannelList);
        if (currentChannel != null && !currentChannelList.contains(currentChannel)) {
            epgAdapter.setItems(new ArrayList<>());
        }
    }
    private void playChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentChannel = channel;
        try {
            if (player == null) {
                DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
                player = new ExoPlayer.Builder(this).setTrackSelector(trackSelector).build();
                playerView.setPlayer(player);
                player.addListener(new Player.Listener() {
                    @Override public void onPlayerError(PlaybackException error) {
                        runOnUiThread(() -> Toast.makeText(MainActivity.this, "播放错误: " + error.getMessage(), Toast.LENGTH_SHORT).show());
                    }
                });
            }
            player.setMediaItem(MediaItem.fromUri(channel.url));
            player.prepare();
            player.play();
        } catch (Exception e) {
            Toast.makeText(this, "播放异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }
    private void loadEpgForChannel(SourceManager.Channel channel) {
        String epgUrl = prefs.getString("epg_url", null);
        if (epgUrl == null || epgUrl.isEmpty()) {
            epgUrl = config.getString("EPG_URLS", null);
            if (epgUrl == null || epgUrl.isEmpty()) {
                epgAdapter.setItems(new ArrayList<>());
                return;
            }
        }
        if (epgUrl.contains("$")) epgUrl = epgUrl.substring(0, epgUrl.indexOf("$"));
        EPGParser.loadEpg(epgUrl, channel.name, new EPGParser.OnEpgLoadListener() {
            @Override public void onLoaded(List<EPGParser.EpgProgram> programs) {
                runOnUiThread(() -> epgAdapter.setItems(programs));
            }
            @Override public void onError(String error) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "EPG加载失败: " + error, Toast.LENGTH_SHORT).show());
            }
        });
    }
    private void toggleFavorite(SourceManager.Channel channel) {
        if (favoriteSet.contains(channel.name)) {
            favoriteSet.remove(channel.name);
        } else {
            favoriteSet.add(channel.name);
        }
        prefs.edit().putStringSet(KEY_FAVORITES, favoriteSet).apply();
        if ("我的收藏".equals(currentGroup)) {
            showChannelsForGroup("我的收藏");
        }
        channelAdapter.notifyDataSetChanged();
        Toast.makeText(this, favoriteSet.contains(channel.name) ? "已收藏" : "已取消收藏", Toast.LENGTH_SHORT).show();
    }
    private void toggleOverlay() {
        if (isOverlayVisible) hideOverlay();
        else showOverlay();
    }
    private void showOverlay() {
        isOverlayVisible = true;
        overlayLayout.setVisibility(View.VISIBLE);
    }
    private void hideOverlay() {
        isOverlayVisible = false;
        overlayLayout.setVisibility(View.GONE);
    }
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_UP) {
            float x = event.getX();
            float width = getWindowManager().getDefaultDisplay().getWidth();
            if (x < width * 0.2) {
                toggleOverlay();
                return true;
            }
        }
        return super.onTouchEvent(event);
    }
    @Override protected void onDestroy() { super.onDestroy(); if (player != null) { player.release(); player = null; } }
    // ------------------- Adapters -------------------
    class GroupAdapter extends RecyclerView.Adapter<GroupAdapter.ViewHolder> {
        private List<String> data;
        private String selectedGroup;
        private OnGroupClickListener listener;
        interface OnGroupClickListener { void onClick(String group); }
        GroupAdapter(List<String> data, OnGroupClickListener listener) { this.data = data; this.listener = listener; }
        void updateData(List<String> newData) { this.data = newData; notifyDataSetChanged(); }
        void setSelectedGroup(String group) { this.selectedGroup = group; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_group, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            String group = data.get(position);
            holder.name.setText(group);
            holder.itemView.setBackgroundColor(group.equals(selectedGroup) ? 0x3300A0FF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(group));
        }
        @Override public int getItemCount() { return data.size(); }
        class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.group_name); }
        }
    }
    class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private SourceManager.Channel selectedChannel;
        private OnChannelClickListener listener;
        private OnFavoriteClickListener favListener;
        interface OnChannelClickListener { void onClick(SourceManager.Channel channel); }
        interface OnFavoriteClickListener { void onFavorite(SourceManager.Channel channel); }
        ChannelAdapter(List<SourceManager.Channel> data, OnChannelClickListener listener, OnFavoriteClickListener favListener) {
            this.data = data; this.listener = listener; this.favListener = favListener;
        }
        void updateData(List<SourceManager.Channel> newData) { this.data = newData; notifyDataSetChanged(); }
        void setSelectedChannel(SourceManager.Channel ch) { this.selectedChannel = ch; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_channel, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SourceManager.Channel ch = data.get(position);
            holder.name.setText(ch.name);
            boolean isFav = favoriteSet.contains(ch.name);
            holder.favIcon.setVisibility(isFav ? View.VISIBLE : View.GONE);
            holder.itemView.setBackgroundColor(ch.equals(selectedChannel) ? 0x3300A0FF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(ch));
            holder.itemView.setOnLongClickListener(v -> { favListener.onFavorite(ch); return true; });
        }
        @Override public int getItemCount() { return data.size(); }
        class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            TextView favIcon;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.channel_name); favIcon = v.findViewById(R.id.channel_fav); }
        }
    }
    class EpgAdapter extends RecyclerView.Adapter<EpgAdapter.ViewHolder> {
        private List<EPGParser.EpgProgram> data = new ArrayList<>();
        EpgAdapter(List<EPGParser.EpgProgram> data) { this.data = data; }
        void setItems(List<EPGParser.EpgProgram> newData) { this.data = newData; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_epg, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            EPGParser.EpgProgram prog = data.get(position);
            SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.getDefault());
            String time = timeFormat.format(new Date(prog.startTime)) + "-" + timeFormat.format(new Date(prog.endTime));
            holder.time.setText(time);
            holder.title.setText(prog.title);
        }
        @Override public int getItemCount() { return data.size(); }
        class ViewHolder extends RecyclerView.ViewHolder {
            TextView time, title;
            ViewHolder(View v) { super(v); time = v.findViewById(R.id.epg_time); title = v.findViewById(R.id.epg_title); }
        }
    }
}
EOF

    # SettingsActivity.java（保留，但已包含完整功能）
    cat > "$TEMPLATE_DIR/src/SettingsActivity.java" <<'EOF'
package com.whyun.witv;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import com.whyun.witv.player.PlayerConfigManager;
public class SettingsActivity extends AppCompatActivity {
    private RecyclerView menuRecycler, contentRecycler;
    private MenuAdapter menuAdapter;
    private ContentAdapter contentAdapter;
    private String[] menuTitles = {"线路选择", "频道搜索", "播放设置", "列表订阅", "EPG订阅", "分类管理", "订阅管理", "显示设置", "偏好设置", "列表设置", "其他设置", "推送频道", "更多管理"};
    private int currentPos = 0;
    private SharedPreferences prefs;
    private static final String KEY_SUB_LIST = "sub_list";
    private static final String KEY_SELECTED_SUB = "selected_sub";
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        menuRecycler = findViewById(R.id.menu_recycler);
        contentRecycler = findViewById(R.id.content_recycler);
        menuRecycler.setLayoutManager(new LinearLayoutManager(this));
        menuAdapter = new MenuAdapter(menuTitles, pos -> {
            currentPos = pos;
            menuAdapter.setSelected(pos);
            showContent(pos);
        });
        menuRecycler.setAdapter(menuAdapter);
        contentRecycler.setLayoutManager(new LinearLayoutManager(this));
        contentAdapter = new ContentAdapter();
        contentRecycler.setAdapter(contentAdapter);
        menuAdapter.setSelected(0);
        showContent(0);
    }
    private void showContent(int pos) {
        List<ContentItem> items = new ArrayList<>();
        try {
            switch (pos) {
                case 0: items.add(new ContentItem("线路选择", "点击选择", v -> showLineSelection())); break;
                case 1: items.add(new ContentItem("频道搜索", "点击搜索", v -> Toast.makeText(this, "频道搜索功能", Toast.LENGTH_SHORT).show())); break;
                case 2: items.add(new ContentItem("播放设置", "点击展开", v -> showPlaySettings())); break;
                case 3: buildSubscriptionList(items); break;
                case 4: items.add(new ContentItem("EPG订阅", "添加EPG", v -> showEpgDialog())); break;
                case 5: items.add(new ContentItem("分类管理", "管理", v -> Toast.makeText(this, "分类管理", Toast.LENGTH_SHORT).show())); break;
                case 6: items.add(new ContentItem("订阅管理", "管理", v -> Toast.makeText(this, "订阅管理", Toast.LENGTH_SHORT).show())); break;
                case 7: items.add(new ContentItem("显示设置", "点击", v -> showDisplaySettings())); break;
                case 8: items.add(new ContentItem("偏好设置", "点击", v -> showPreferenceSettings())); break;
                case 9: items.add(new ContentItem("列表设置", "点击", v -> showListSettings())); break;
                case 10: items.add(new ContentItem("其他设置", "点击", v -> showOtherSettings())); break;
                case 11: items.add(new ContentItem("推送频道", "推送", v -> Toast.makeText(this, "推送频道", Toast.LENGTH_SHORT).show())); break;
                case 12: items.add(new ContentItem("更多管理", "查看", v -> showMoreInfo())); break;
            }
        } catch (Exception e) {
            items.add(new ContentItem("加载失败", e.getMessage(), v -> {}));
        }
        contentAdapter.setItems(items);
    }
    private void buildSubscriptionList(List<ContentItem> items) {
        Set<String> subSet = prefs.getStringSet(KEY_SUB_LIST, new HashSet<>());
        String selected = prefs.getString(KEY_SELECTED_SUB, "");
        if (subSet == null || subSet.isEmpty()) {
            items.add(new ContentItem("暂无订阅", "点击下方添加", v -> {}));
        } else {
            for (String entry : subSet) {
                String[] parts = entry.split("\\|\\|");
                String name = parts.length > 0 ? parts[0] : entry;
                String url = parts.length > 1 ? parts[1] : "";
                boolean isSelected = entry.equals(selected);
                items.add(new ContentItem(name, url, isSelected, v -> {
                    prefs.edit().putString(KEY_SELECTED_SUB, entry).apply();
                    prefs.edit().putString("selected_sub_url", url).apply();
                    prefs.edit().putString("selected_sub_name", name).apply();
                    Toast.makeText(this, "已选中: " + name, Toast.LENGTH_SHORT).show();
                    showContent(3);
                    finish();
                }));
            }
        }
        items.add(new ContentItem("+ 添加订阅", "", v -> showAddSubscriptionDialog()));
    }
    private void showAddSubscriptionDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("添加列表订阅");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(50,20,50,20);
        final EditText nameInput = new EditText(this);
        nameInput.setHint("名称（选填）");
        layout.addView(nameInput);
        final EditText urlInput = new EditText(this);
        urlInput.setHint("地址（必填）");
        layout.addView(urlInput);
        builder.setView(layout);
        builder.setPositiveButton("确定", (d, which) -> {
            try {
                String name = nameInput.getText().toString().trim();
                String url = urlInput.getText().toString().trim();
                if (url.isEmpty()) { Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show(); return; }
                if (name.isEmpty()) name = url;
                String entry = name + "||" + url;
                Set<String> subSet = new HashSet<>(prefs.getStringSet(KEY_SUB_LIST, new HashSet<>()));
                subSet.add(entry);
                prefs.edit().putStringSet(KEY_SUB_LIST, subSet).apply();
                prefs.edit().putString(KEY_SELECTED_SUB, entry).apply();
                prefs.edit().putString("selected_sub_url", url).apply();
                prefs.edit().putString("selected_sub_name", name).apply();
                Toast.makeText(this, "订阅已添加并选中", Toast.LENGTH_SHORT).show();
                showContent(3);
                finish();
            } catch (Exception e) {
                Toast.makeText(this, "添加失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }
    private void showEpgDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("EPG订阅");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(50,20,50,20);
        final EditText urlInput = new EditText(this);
        urlInput.setHint("EPG地址（XMLTV格式）");
        layout.addView(urlInput);
        builder.setView(layout);
        builder.setPositiveButton("确定", (d, which) -> {
            String url = urlInput.getText().toString().trim();
            if (url.isEmpty()) { Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show(); return; }
            prefs.edit().putString("epg_url", url).apply();
            Toast.makeText(this, "EPG地址已保存", Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }
    private void showLineSelection() {
        new AlertDialog.Builder(this).setTitle("线路选择").setItems(new String[]{"源1","源2","源3"}, (d,w) -> Toast.makeText(this, "选择线路"+(w+1), Toast.LENGTH_SHORT).show()).show();
    }
    private void showPlaySettings() {
        String[] items = {"解码方式", "画面比例", "超时换源", "断线重连"};
        new AlertDialog.Builder(this).setTitle("播放设置").setItems(items, (d, which) -> {
            switch (which) {
                case 0: showDecoderDialog(); break;
                case 1: showAspectDialog(); break;
                case 2: Toast.makeText(this, "超时换源", Toast.LENGTH_SHORT).show(); break;
                case 3: Toast.makeText(this, "断线重连", Toast.LENGTH_SHORT).show(); break;
            }
        }).show();
    }
    private void showDecoderDialog() {
        final String[] decoders = {"系统解码", "IJK硬解", "IJK软解", "EXO硬解", "EXO软解", "MPV硬解", "MPV软解", "自动"};
        int current = PlayerConfigManager.getDecoder();
        new AlertDialog.Builder(this).setTitle("解码方式")
                .setSingleChoiceItems(decoders, current, (d, which) -> {
                    PlayerConfigManager.setDecoder(which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null).show();
    }
    private void showAspectDialog() {
        final String[] aspects = {"默认", "16:9", "4:3", "填充", "原始", "裁剪", "电影"};
        int current = 0;
        new AlertDialog.Builder(this).setTitle("画面比例")
                .setSingleChoiceItems(aspects, current, (d, which) -> {
                    PlayerConfigManager.setAspectRatio(aspects[which]);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null).show();
    }
    private void showDisplaySettings() {
        final String[] items = {"显示时间", "显示网速", "隐藏频道图标", "隐藏底部图标"};
        new AlertDialog.Builder(this).setTitle("显示设置").setItems(items, (d, which) -> {
            String key = "";
            boolean def = false;
            switch (which) {
                case 0: key="show_time"; break;
                case 1: key="show_net_speed"; break;
                case 2: key="hide_channel_logo"; def=true; break;
                case 3: key="hide_bottom_logo"; def=true; break;
            }
            final String finalKey = key;
            boolean current = prefs.getBoolean(finalKey, def);
            new AlertDialog.Builder(this)
                    .setTitle(items[which])
                    .setMessage("当前状态：" + (current ? "开启" : "关闭"))
                    .setPositiveButton("切换", (d2, w) -> {
                        prefs.edit().putBoolean(finalKey, !current).apply();
                        Toast.makeText(this, "已切换", Toast.LENGTH_SHORT).show();
                    })
                    .setNegativeButton("取消", null)
                    .show();
        }).show();
    }
    private void showPreferenceSettings() {
        final String[] items = {"记忆解码", "换台反转", "跨选分组", "关闭密码"};
        new AlertDialog.Builder(this).setTitle("偏好设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        }).show();
    }
    private void showListSettings() {
        final String[] items = {"全局字体大小", "列表宽度", "底部信息栏宽度"};
        new AlertDialog.Builder(this).setTitle("列表设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        }).show();
    }
    private void showOtherSettings() {
        final String[] items = {"EPG缓存"};
        new AlertDialog.Builder(this).setTitle("其他设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        }).show();
    }
    private void showMoreInfo() {
        new AlertDialog.Builder(this).setTitle("更多管理").setMessage("酷9 2.0.1\n软件仅供测试").setPositiveButton("确定", null).show();
    }
    static class ContentItem {
        String title, subtitle; boolean isSelected; View.OnClickListener listener;
        ContentItem(String t, String s, View.OnClickListener l) { title=t; subtitle=s; isSelected=false; listener=l; }
        ContentItem(String t, String s, boolean sel, View.OnClickListener l) { title=t; subtitle=s; isSelected=sel; listener=l; }
    }
    static class MenuAdapter extends RecyclerView.Adapter<MenuAdapter.ViewHolder> {
        private String[] titles; private OnMenuClickListener listener; private int selected=-1;
        interface OnMenuClickListener { void onClick(int pos); }
        MenuAdapter(String[] t, OnMenuClickListener l) { titles=t; listener=l; }
        void setSelected(int pos) { selected=pos; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_menu, parent, false);
            return new ViewHolder(v);
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            holder.text.setText(titles[position]);
            holder.itemView.setBackgroundColor(selected==position ? 0x33FFFFFF : 0x00000000);
            holder.itemView.setOnClickListener(v -> listener.onClick(position));
        }
        @Override public int getItemCount() { return titles.length; }
        static class ViewHolder extends RecyclerView.ViewHolder { TextView text; ViewHolder(View v) { super(v); text=v.findViewById(R.id.menu_text); } }
    }
    static class ContentAdapter extends RecyclerView.Adapter<ContentAdapter.ViewHolder> {
        private List<ContentItem> items = new ArrayList<>();
        void setItems(List<ContentItem> list) { items=list; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_content, parent, false);
            return new ViewHolder(v);
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            ContentItem item = items.get(position);
            holder.title.setText(item.title);
            holder.subtitle.setText(item.subtitle);
            holder.check.setVisibility(item.isSelected ? View.VISIBLE : View.GONE);
            holder.itemView.setOnClickListener(item.listener);
        }
        @Override public int getItemCount() { return items.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView title, subtitle, check;
            ViewHolder(View v) { super(v); title=v.findViewById(R.id.content_title); subtitle=v.findViewById(R.id.content_subtitle); check=v.findViewById(R.id.content_check); }
        }
    }
}
EOF

    # ==================== 布局文件 ====================
    cat > "$TEMPLATE_DIR/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">
    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />
    <LinearLayout
        android:id="@+id/overlay_layout"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="horizontal"
        android:background="#CC000000"
        android:visibility="gone">
        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/group_recycler"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1"
            android:background="#33000000"
            android:padding="8dp" />
        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/channel_recycler"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="2"
            android:background="#44000000"
            android:padding="8dp" />
        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/epg_recycler"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="2"
            android:background="#55000000"
            android:padding="8dp" />
    </LinearLayout>
    <ImageButton
        android:id="@+id/btn_settings"
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:src="@drawable/ic_settings"
        android:layout_gravity="top|end"
        android:layout_margin="16dp"
        android:background="#88000000"
        android:tint="#FFFFFF" />
</FrameLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/activity_settings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="horizontal" android:background="#F5F5F5">
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/menu_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:background="#333333" android:padding="8dp" />
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/content_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="2" android:background="#FFFFFF" android:padding="8dp" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_group.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/group_name"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:paddingLeft="12dp"
    android:textSize="14sp"
    android:textColor="#FFFFFF"
    android:background="?attr/selectableItemBackground" />
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_channel.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:paddingLeft="12dp"
    android:paddingRight="12dp"
    android:background="?attr/selectableItemBackground">
    <TextView
        android:id="@+id/channel_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textSize="14sp"
        android:textColor="#FFFFFF" />
    <TextView
        android:id="@+id/channel_fav"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="★"
        android:textSize="16sp"
        android:textColor="#FFD700"
        android:visibility="gone" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_epg.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="8dp"
    android:background="?attr/selectableItemBackground">
    <TextView
        android:id="@+id/epg_time"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="12sp"
        android:textColor="#AAAAAA" />
    <TextView
        android:id="@+id/epg_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="14sp"
        android:textColor="#FFFFFF" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_menu.xml" <<'EOF'
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

    cat > "$TEMPLATE_DIR/res/layout/item_content.xml" <<'EOF'
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
            android:id="@+id/content_title"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:textSize="16sp"
            android:textColor="#333" />
        <TextView
            android:id="@+id/content_check"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="√"
            android:textSize="18sp"
            android:textColor="#4CAF50"
            android:visibility="gone" />
    </LinearLayout>
    <TextView
        android:id="@+id/content_subtitle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="12sp"
        android:textColor="#888" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/drawable/ic_settings.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94s-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z"/>
</vector>
EOF
    cat > "$TEMPLATE_DIR/res/drawable/ic_menu.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M3,18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/>
</vector>
EOF

    echo "✅ 模板生成完毕"
fi

# ========== 2. 复制模板到项目 ==========
echo "📂 复制模板文件..."
rm -rf app/src/main/java/com/whyun/witv/ui
rm -f app/src/main/java/com/whyun/witv/SettingsActivity.java
rm -rf app/build
cp -r "$TEMPLATE_DIR/src/." app/src/main/java/com/whyun/witv/
cp -r "$TEMPLATE_DIR/res/." app/src/main/res/
cp "$TEMPLATE_DIR/configuration.json" app/src/main/assets/

mkdir -p app/src/main/assets/localData app/src/main/assets/backup app/src/main/assets/download \
         app/src/main/assets/videoFile app/src/main/assets/configuration app/src/main/assets/logo \
         app/src/main/assets/js app/src/main/assets/py app/src/main/assets/webviewJscode app/src/main/assets/epgCache

echo "✅ 文件复制完成"

# 修复 SettingsActivity 缺少 import
sed -i '/^package com.whyun.witv;/a import com.whyun.witv.player.PlayerConfigManager;' app/src/main/java/com/whyun/witv/SettingsActivity.java

# ========== 3. 添加依赖和权限 ==========
APP_GRADLE="app/build.gradle"
MANIFEST="app/src/main/AndroidManifest.xml"
cp "$APP_GRADLE" "$APP_GRADLE.bak"
sed -i '/implementation.*exoplayer/d' "$APP_GRADLE"
sed -i '/implementation.*okhttp/d' "$APP_GRADLE"
sed -i '/implementation.*gson/d' "$APP_GRADLE"
sed -i '/implementation.*preference/d' "$APP_GRADLE"
sed -i '/dependencies {/a \    implementation "androidx.media3:media3-exoplayer:1.3.1"\n    implementation "androidx.media3:media3-exoplayer-hls:1.3.1"\n    implementation "androidx.media3:media3-ui:1.3.1"\n    implementation "androidx.media3:media3-datasource:1.3.1"\n    implementation "com.squareup.okhttp3:okhttp:4.12.0"\n    implementation "com.google.code.gson:gson:2.10.1"\n    implementation "androidx.preference:preference:1.2.1"\n    implementation "androidx.recyclerview:recyclerview:1.3.2"\n    implementation "com.google.android.material:material:1.9.0"' "$APP_GRADLE"
echo "✅ 依赖已添加"

sed -i '/android.permission.INTERNET/d' "$MANIFEST"
sed -i '/<manifest /a \    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
echo "✅ 权限已添加"

# 注册 Activity
python3 <<PYTHON_SCRIPT
import sys, xml.etree.ElementTree as ET
from xml.dom import minidom
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
manifest_file = "$MANIFEST"
pkg = "com.whyun.witv"
try:
    tree = ET.parse(manifest_file); root = tree.getroot()
except Exception as e:
    print(f"解析失败: {e}", file=sys.stderr); sys.exit(1)
app = root.find('application')
if app is None:
    print("未找到 application", file=sys.stderr); sys.exit(1)
for act in app.findall('activity'): app.remove(act)
main_act = ET.Element('activity')
main_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.MainActivity")
main_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
intent_filter = ET.SubElement(main_act, 'intent-filter')
action = ET.SubElement(intent_filter, 'action')
action.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.action.MAIN')
cat = ET.SubElement(intent_filter, 'category')
cat.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.category.LAUNCHER')
app.append(main_act)
settings_act = ET.Element('activity')
settings_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.SettingsActivity")
settings_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
app.append(settings_act)
xml_str = ET.tostring(root, encoding='unicode')
dom = minidom.parseString(xml_str)
pretty = dom.toprettyxml(indent="    ")
pretty = '\n'.join(pretty.split('\n')[1:]) if pretty.startswith('<?xml') else pretty
with open(manifest_file, 'w') as f: f.write(pretty)
print("✅ AndroidManifest 注册完成")
PYTHON_SCRIPT

# ========== 4. 构建 ==========
echo "🧹 清理并构建..."
./gradlew clean
./gradlew assembleDebug

echo ""
echo "🎉 构建完成！APK 位于 app/build/outputs/apk/debug/"
echo "📌 使用说明："
echo "   1. 打开应用，点击右上角齿轮进入设置"
echo "   2. 选择「列表订阅」，点击「+ 添加订阅」输入名称和地址"
echo "   3. 添加后自动选中，返回主界面即可加载频道"
echo "   4. 点击播放画面左侧区域（或点击屏幕）可呼出频道列表"
echo "   5. 左侧分组列表，中间频道列表，右侧 EPG 节目单"
echo "   6. 长按频道可收藏/取消收藏"
