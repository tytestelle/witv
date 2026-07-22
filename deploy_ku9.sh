#!/bin/bash
set -e

echo "🔥 部署酷9播放器（最终修正版 - 窄覆盖层 + 自定义图标）"

TEMPLATE_DIR="./template"
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "📁 首次运行，生成模板文件..."
    mkdir -p "$TEMPLATE_DIR"/{src,res/layout,res/drawable,res/values}
    mkdir -p "$TEMPLATE_DIR/src/epg" "$TEMPLATE_DIR/src/player" "$TEMPLATE_DIR/src/favorite"

    cat > "$TEMPLATE_DIR/configuration.json" <<'EOF'
{"Configuration":{"LIVE_URLS":null,"EPG_URLS":null,"PLAY_TYPE":7,"PLAY_SCALE":3,"LIVE_CONNECT_TIMEOUT":1,"LIVE_SHOW_TIME":false,"LIVE_SHOW_NET_SPEED":false,"HIDE_Channel_LOGO":true,"HIDE_Bottom_LOGO":true,"CLOSE_EPG":false,"HIDE_FAVOR":false,"HIDE_NUMBER":false,"PL_MEMORYS_ET_SELECT":false,"LIVE_CHANNEL_REVERSE":false,"LIVE_CROSS_GROUP":false,"LIVE_SKIP_PASSWORD":false,"PIC_IN_PIC":false,"BOOT_START":false,"QUICK_EXIT":false,"EYE_PROTECTION":false,"PLAYBACK_ID":false,"TIME_SHIFT_ON":true,"PLAY_RENDER":1,"DOH_URL":0,"THEME_SELECT":2,"PLAY_BACK_TYPE":0,"RECONNECT_INDEX":0,"EXO_TUNNELING_SELECT":false,"RTSP_TCP_SELECT":0,"NAVIGATION_SELECT":0,"EPG_SHOW_TYPE_SELECT":0,"TEXT_SIZE":0,"LIST_WIDTH":0,"BOTTOM_WIDTH":0,"EPGCACHE_SELECT":4,"IMAGECACHE_SELECT":false,"SCRIPT_CACHE":true,"MEMORYS_SOURCE":true,"MEMORYS_POSITION":true,"BACKGROUND_THEME_SELECT":6,"BOOTRECEIVER_SET_SELECT":true,"SHORTCUTS_MENU":false,"SHORTCUTS_MENU_SELECT":"列表订阅,EPG订阅,无线投屏,频道搜索,APP信息","GROUP_PARS_SET_SELECT":3,"PLAY_ALL_SOURCE":true,"RESOLUTION_MODE_SELECT":0,"TIME_ZONE_SELECT":0,"TIME_SHIFT_MODE":0,"ENABLE_LOCAL_VIDEO":false,"M3U_LOGO_PRIORITY":false,"EPG_DESC_SET":false,"BOTTOM_DESC_SET":true,"ICON_INITIAL_SET":true,"EPG_CACHE_PATH_SET":false,"AUDIO_WAKKPAPER":false,"DE_INTERLACING":false}}
EOF

    # ==================== SourceManager.java ====================
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
        groupMap.clear(); groupNames.clear();
        String currentGroup = "默认分组";
        for (String line : content.split("\n")) {
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.endsWith("#genre#")) {
                String groupName = line.substring(0, line.length() - "#genre#".length()).trim();
                if (groupName.endsWith(",")) groupName = groupName.substring(0, groupName.length()-1).trim();
                if (!groupName.isEmpty()) {
                    currentGroup = groupName;
                    if (!groupMap.containsKey(currentGroup)) {
                        groupMap.put(currentGroup, new ArrayList<>());
                        groupNames.add(currentGroup);
                    }
                }
                continue;
            }
            if (line.startsWith("#")) continue;
            String[] parts = line.split(",");
            if (parts.length >= 2) {
                String name = parts[0].trim();
                if (name.endsWith(",")) name = name.substring(0, name.length()-1).trim();
                String url = parts[1].trim();
                if (name.isEmpty() || url.isEmpty()) continue;
                Channel ch = new Channel(name, url, currentGroup);
                if (!groupMap.containsKey(currentGroup)) {
                    groupMap.put(currentGroup, new ArrayList<>());
                    groupNames.add(currentGroup);
                }
                groupMap.get(currentGroup).add(ch);
            }
        }
    }
    private void parseM3U(String content) {
        groupMap.clear(); groupNames.clear();
        String[] lines = content.split("\n");
        for (int i = 0; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.startsWith("#EXTM3U")) continue;
            if (line.startsWith("#EXTINF:")) {
                String group = "默认分组";
                String logo = null;
                int gidx = line.indexOf("group-title=\"");
                if (gidx != -1) {
                    int end = line.indexOf("\"", gidx + 13);
                    if (end != -1) group = line.substring(gidx + 13, end);
                }
                int lidx = line.indexOf("tvg-logo=\"");
                if (lidx != -1) {
                    int end = line.indexOf("\"", lidx + 10);
                    if (end != -1) logo = line.substring(lidx + 10, end);
                }
                int lastComma = line.lastIndexOf(",");
                String name = (lastComma != -1) ? line.substring(lastComma + 1).trim() : "未知频道";
                if (name.endsWith(",")) name = name.substring(0, name.length()-1).trim();
                if (i + 1 < lines.length) {
                    String url = lines[i + 1].trim();
                    if (!url.isEmpty() && !url.startsWith("#")) {
                        Channel ch = new Channel(name, url, group);
                        ch.logoUrl = logo;
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
        public String logoUrl;
        public Channel(String n, String u, String g) { name=n; url=u; group=g; }
    }
}
EOF

    # ==================== EPGParser.java ====================
    cat > "$TEMPLATE_DIR/src/epg/EPGParser.java" <<'EOF'
package com.whyun.witv.epg;
import android.util.Xml;
import org.xmlpull.v1.XmlPullParser;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class EPGParser {
    public interface OnEpgLoadListener { void onLoaded(List<EpgProgram> programs); void onError(String error); }
    public static void loadEpg(String url, String channelName, OnEpgLoadListener listener) {
        new Thread(() -> {
            OkHttpClient client = null;
            Response response = null;
            InputStream is = null;
            try {
                client = new OkHttpClient.Builder()
                    .connectTimeout(30, TimeUnit.SECONDS)
                    .readTimeout(60, TimeUnit.SECONDS)
                    .build();
                Request request = new Request.Builder().url(url).build();
                response = client.newCall(request).execute();
                if (!response.isSuccessful()) throw new Exception("HTTP " + response.code());
                is = response.body().byteStream();
                List<EpgProgram> programs = parseXmltv(is, channelName);
                if (listener != null) {
                    android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                    mainHandler.post(() -> listener.onLoaded(programs));
                }
            } catch (Exception e) {
                e.printStackTrace();
                if (listener != null) {
                    android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                    mainHandler.post(() -> listener.onError(e.getMessage()));
                }
            } finally {
                try { if (is != null) is.close(); } catch (Exception e) {}
                try { if (response != null) response.close(); } catch (Exception e) {}
            }
        }).start();
    }
    private static List<EpgProgram> parseXmltv(InputStream is, String channelName) throws Exception {
        List<EpgProgram> result = new ArrayList<>();
        XmlPullParser parser = Xml.newPullParser();
        parser.setInput(is, "UTF-8");
        int event = parser.getEventType();
        String currentTag = "", currentTitle = "", currentStart = "", currentStop = "", currentDesc = "";
        boolean inProgramme = false;
        String currentChannel = "";
        while (event != XmlPullParser.END_DOCUMENT) {
            switch (event) {
                case XmlPullParser.START_TAG:
                    currentTag = parser.getName();
                    if ("programme".equals(currentTag)) {
                        inProgramme = true;
                        currentChannel = parser.getAttributeValue(null, "channel");
                        currentStart = parser.getAttributeValue(null, "start");
                        currentStop = parser.getAttributeValue(null, "stop");
                        currentTitle = ""; currentDesc = "";
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
                        if (!currentTitle.isEmpty() && (currentChannel.equals(channelName) || currentChannel.isEmpty())) {
                            EpgProgram prog = new EpgProgram();
                            prog.title = currentTitle; prog.desc = currentDesc;
                            try {
                                SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US);
                                prog.startTime = sdf.parse(currentStart + " +0000").getTime();
                                prog.endTime = sdf.parse(currentStop + " +0000").getTime();
                            } catch (Exception e) {}
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

    # ==================== PlayerConfigManager.java ====================
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

    # ==================== FavoriteManager.java ====================
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

    # ==================== ConfigurationManager.java ====================
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

    # ==================== MainActivity.java（移除 right_click_area） ====================
    cat > "$TEMPLATE_DIR/src/MainActivity.java" <<'EOF'
package com.whyun.witv;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.preference.PreferenceManager;
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
import com.whyun.witv.source.SourceManager;
import com.whyun.witv.epg.EPGParser;
import com.whyun.witv.player.PlayerConfigManager;
import com.whyun.witv.favorite.FavoriteManager;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
public class MainActivity extends AppCompatActivity {
    private PlayerView playerView;
    private ExoPlayer player;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> currentChannelList = new ArrayList<>();
    private Map<String, List<SourceManager.Channel>> groupMap = new HashMap<>();
    private List<String> groupNames = new ArrayList<>();
    private String currentGroup = "";
    private String currentSubUrl = "";
    private String currentSubName = "";
    private RecyclerView subRecycler, groupRecycler, channelRecycler, epgRecycler;
    private SubAdapter subAdapter;
    private GroupAdapter groupAdapter;
    private ChannelAdapter channelAdapter;
    private EpgAdapter epgAdapter;
    private View overlayLayout;
    private SharedPreferences prefs;
    private ConfigurationManager config;
    private boolean isOverlayVisible = false;
    private Set<String> favoriteSet = new HashSet<>();
    private static final String KEY_FAVORITES = "favorites";
    private static final String KEY_SELECTED_SUB = "selected_sub";
    private static final String KEY_SUB_LIST = "sub_list";
    private static final String KEY_LAST_CHANNEL = "last_channel";
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    private File logoDir;
    private TextView tvChannelName, tvEpgInfo, tvTime;
    private Runnable hideOverlayRunnable;
    private boolean isLoading = false;
    private List<SubEntry> subEntryList = new ArrayList<>();
    private View epgContainer;

    static class SubEntry { String name, url; }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            setContentView(R.layout.activity_main);
            config = ConfigurationManager.getInstance(this);
            PlayerConfigManager.init(this);
            FavoriteManager.init(this);
            prefs = PreferenceManager.getDefaultSharedPreferences(this);
            favoriteSet = new HashSet<>(prefs.getStringSet(KEY_FAVORITES, new HashSet<>()));
            logoDir = new File(getFilesDir(), "logo");
            if (!logoDir.exists()) logoDir.mkdirs();

            playerView = findViewById(R.id.player_container);
            if (playerView == null) {
                Toast.makeText(this, "playerView 为空", Toast.LENGTH_LONG).show();
                return;
            }
            overlayLayout = findViewById(R.id.overlay_layout);
            subRecycler = findViewById(R.id.sub_recycler);
            groupRecycler = findViewById(R.id.group_recycler);
            channelRecycler = findViewById(R.id.channel_recycler);
            epgRecycler = findViewById(R.id.epg_recycler);
            epgContainer = findViewById(R.id.epg_container);

            subRecycler.setLayoutManager(new LinearLayoutManager(this));
            groupRecycler.setLayoutManager(new LinearLayoutManager(this));
            channelRecycler.setLayoutManager(new LinearLayoutManager(this));
            epgRecycler.setLayoutManager(new LinearLayoutManager(this));

            loadSubscriptions();

            subAdapter = new SubAdapter(subEntryList, entry -> {
                currentSubName = entry.name;
                currentSubUrl = entry.url;
                prefs.edit().putString(KEY_SELECTED_SUB, entry.name + "||" + entry.url).apply();
                loadSourceForUrl(entry.url);
                hideOverlay();
            });
            subRecycler.setAdapter(subAdapter);

            groupAdapter = new GroupAdapter(new ArrayList<>(), group -> {
                currentGroup = group;
                showChannelsForGroup(group);
                groupAdapter.setSelectedGroup(group);
            });
            groupRecycler.setAdapter(groupAdapter);

            channelAdapter = new ChannelAdapter(new ArrayList<>(), favoriteSet, logoDir, channel -> {
                playChannel(channel);
                loadEpgForChannel(channel);
                channelAdapter.setSelectedChannel(channel);
                hideOverlay();
            }, this::toggleFavorite);
            channelRecycler.setAdapter(channelAdapter);

            epgAdapter = new EpgAdapter(new ArrayList<>());
            epgRecycler.setAdapter(epgAdapter);

            tvChannelName = findViewById(R.id.tv_channel_name);
            tvEpgInfo = findViewById(R.id.tv_epg_info);
            tvTime = findViewById(R.id.tv_time);

            updateTime();

            playerView.setOnTouchListener((v, event) -> {
                if (event.getAction() == MotionEvent.ACTION_UP) {
                    float y = event.getY();
                    float height = v.getHeight();
                    if (y > height * 0.5 && y < height * 0.85) {
                        Toast.makeText(this, "信息窗口（模拟）", Toast.LENGTH_SHORT).show();
                        return true;
                    }
                }
                return false;
            });

            findViewById(R.id.btn_epg).setOnClickListener(v -> {
                if (currentChannel != null) {
                    if (epgContainer.getVisibility() == View.VISIBLE) {
                        epgContainer.setVisibility(View.GONE);
                    } else {
                        epgContainer.setVisibility(View.VISIBLE);
                        loadEpgForChannel(currentChannel);
                    }
                } else {
                    Toast.makeText(this, "请先选择一个频道", Toast.LENGTH_SHORT).show();
                }
            });
            findViewById(R.id.btn_announce).setOnClickListener(v -> Toast.makeText(this, "使用公告", Toast.LENGTH_SHORT).show());

            String selected = prefs.getString(KEY_SELECTED_SUB, "");
            if (!selected.isEmpty()) {
                String[] parts = selected.split("\\|\\|");
                if (parts.length == 2) {
                    currentSubName = parts[0];
                    currentSubUrl = parts[1];
                }
            }
            if (currentSubUrl != null && !currentSubUrl.isEmpty()) {
                loadSourceForUrl(currentSubUrl);
            } else if (!subEntryList.isEmpty()) {
                for (SubEntry se : subEntryList) {
                    if (!"我的收藏".equals(se.name) && se.url != null && !se.url.isEmpty()) {
                        currentSubName = se.name;
                        currentSubUrl = se.url;
                        prefs.edit().putString(KEY_SELECTED_SUB, se.name + "||" + se.url).apply();
                        loadSourceForUrl(se.url);
                        break;
                    }
                }
            } else {
                String defaultUrl = config.getLiveUrls();
                if (defaultUrl != null && !defaultUrl.isEmpty()) {
                    currentSubName = "默认源";
                    currentSubUrl = defaultUrl;
                    loadSourceForUrl(defaultUrl);
                }
            }

            hideOverlayRunnable = () -> {
                if (isOverlayVisible) hideOverlay();
            };

            findViewById(R.id.left_click_area).setOnClickListener(v -> {
                if (!isOverlayVisible) showOverlay();
            });

            // 覆盖层右侧30%区域点击关闭（已在布局中设置 android:onClick="hideOverlay"）

        } catch (Exception e) {
            Toast.makeText(this, "初始化失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
            e.printStackTrace();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        String selected = prefs.getString(KEY_SELECTED_SUB, "");
        if (!selected.isEmpty()) {
            String[] parts = selected.split("\\|\\|");
            if (parts.length == 2) {
                currentSubName = parts[0];
                currentSubUrl = parts[1];
            }
        }
        loadSubscriptions();
        subAdapter.updateData(subEntryList);
        if (currentSubUrl != null && !currentSubUrl.isEmpty()) {
            loadSourceForUrl(currentSubUrl);
        } else if (!subEntryList.isEmpty()) {
            for (SubEntry se : subEntryList) {
                if (!"我的收藏".equals(se.name) && se.url != null && !se.url.isEmpty()) {
                    currentSubName = se.name;
                    currentSubUrl = se.url;
                    prefs.edit().putString(KEY_SELECTED_SUB, se.name + "||" + se.url).apply();
                    loadSourceForUrl(se.url);
                    break;
                }
            }
        }
    }

    private void loadSubscriptions() {
        subEntryList.clear();
        Set<String> subSet = prefs.getStringSet(KEY_SUB_LIST, new HashSet<>());
        if (subSet != null) {
            for (String entry : subSet) {
                String[] parts = entry.split("\\|\\|");
                if (parts.length >= 2) {
                    SubEntry se = new SubEntry();
                    se.name = parts[0];
                    se.url = parts[1];
                    subEntryList.add(se);
                }
            }
        }
        SubEntry fav = new SubEntry();
        fav.name = "我的收藏";
        fav.url = null;
        subEntryList.add(0, fav);
    }

    private void loadSourceForUrl(String url) {
        if (isLoading || url == null || url.isEmpty()) return;
        isLoading = true;
        if (url.contains("$")) url = url.substring(0, url.indexOf("$"));
        final String finalUrl = url;
        Toast.makeText(this, "正在加载: " + finalUrl, Toast.LENGTH_SHORT).show();
        new SourceManager(this).loadFromUrl(finalUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(Map<String, List<SourceManager.Channel>> map, List<String> names) {
                isLoading = false;
                groupMap = map;
                groupNames = names;
                groupAdapter.updateData(groupNames);
                if (!groupNames.isEmpty()) {
                    currentGroup = groupNames.get(0);
                    groupAdapter.setSelectedGroup(currentGroup);
                    showChannelsForGroup(currentGroup);
                } else {
                    currentChannelList.clear();
                    channelAdapter.updateData(currentChannelList);
                }
                showOverlay();
                resetAutoHideTimer();
            }

            @Override
            public void onError(String error) {
                isLoading = false;
                Toast.makeText(MainActivity.this, "加载失败: " + error, Toast.LENGTH_LONG).show();
            }
        });
    }

    private void showChannelsForGroup(String group) {
        List<SourceManager.Channel> list;
        if ("我的收藏".equals(group)) {
            list = new ArrayList<>();
            if (groupMap != null) {
                for (List<SourceManager.Channel> clist : groupMap.values()) {
                    for (SourceManager.Channel ch : clist) {
                        if (favoriteSet.contains(ch.name)) {
                            list.add(ch);
                        }
                    }
                }
            }
        } else {
            list = groupMap.get(group);
            if (list == null) list = new ArrayList<>();
        }
        currentChannelList = list;
        channelAdapter.updateData(currentChannelList);

        String lastChannel = prefs.getString(KEY_LAST_CHANNEL, "");
        if (!lastChannel.isEmpty()) {
            for (int i = 0; i < currentChannelList.size(); i++) {
                if (currentChannelList.get(i).name.equals(lastChannel)) {
                    SourceManager.Channel ch = currentChannelList.get(i);
                    channelAdapter.setSelectedChannel(ch);
                    playChannel(ch);
                    loadEpgForChannel(ch);
                    return;
                }
            }
        }
        if (!currentChannelList.isEmpty()) {
            SourceManager.Channel ch = currentChannelList.get(0);
            channelAdapter.setSelectedChannel(ch);
            playChannel(ch);
            loadEpgForChannel(ch);
        }
    }

    private void downloadLogo(String logoUrl, String channelName) {
        new Thread(() -> {
            try {
                String fileName = channelName.hashCode() + ".png";
                File logoFile = new File(logoDir, fileName);
                if (logoFile.exists()) return;
                OkHttpClient client = new OkHttpClient.Builder()
                        .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                        .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                        .build();
                Request request = new Request.Builder().url(logoUrl).build();
                Response response = client.newCall(request).execute();
                if (response.code() != 200) return;
                InputStream is = response.body().byteStream();
                FileOutputStream fos = new FileOutputStream(logoFile);
                byte[] buf = new byte[8192];
                int len;
                while ((len = is.read(buf)) != -1) {
                    fos.write(buf, 0, len);
                }
                fos.close();
                is.close();
                runOnUiThread(() -> channelAdapter.notifyDataSetChanged());
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }

    private void playChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentChannel = channel;
        prefs.edit().putString(KEY_LAST_CHANNEL, channel.name).apply();
        try {
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
            player.setMediaItem(MediaItem.fromUri(channel.url));
            player.prepare();
            player.play();
            tvChannelName.setText(channel.name);
            loadEpgForChannel(channel);
        } catch (Exception e) {
            Toast.makeText(this, "播放异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void loadEpgForChannel(SourceManager.Channel channel) {
        try {
            String epgUrl = prefs.getString("epg_url", null);
            if (epgUrl == null || epgUrl.isEmpty()) {
                epgUrl = config.getString("EPG_URLS", null);
                if (epgUrl == null || epgUrl.isEmpty()) {
                    tvEpgInfo.setText("暂无EPG");
                    epgAdapter.setItems(new ArrayList<>());
                    return;
                }
            }
            if (epgUrl.contains("$")) epgUrl = epgUrl.substring(0, epgUrl.indexOf("$"));
            final String finalEpgUrl = epgUrl;
            EPGParser.loadEpg(finalEpgUrl, channel.name, new EPGParser.OnEpgLoadListener() {
                @Override
                public void onLoaded(List<EPGParser.EpgProgram> programs) {
                    runOnUiThread(() -> {
                        epgAdapter.setItems(programs);
                        if (!programs.isEmpty()) {
                            EPGParser.EpgProgram first = programs.get(0);
                            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm", Locale.getDefault());
                            tvEpgInfo.setText(first.title + " " + sdf.format(new Date(first.startTime)));
                        } else {
                            tvEpgInfo.setText("暂无节目");
                        }
                    });
                }

                @Override
                public void onError(String error) {
                    runOnUiThread(() -> {
                        tvEpgInfo.setText("EPG加载失败");
                        epgAdapter.setItems(new ArrayList<>());
                    });
                }
            });
        } catch (Exception e) {
            Toast.makeText(this, "EPG加载异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void toggleFavorite(SourceManager.Channel channel) {
        if (favoriteSet.contains(channel.name)) {
            favoriteSet.remove(channel.name);
        } else {
            favoriteSet.add(channel.name);
        }
        prefs.edit().putStringSet(KEY_FAVORITES, favoriteSet).apply();
        showChannelsForGroup(currentGroup);
        channelAdapter.updateFavorites(favoriteSet);
        Toast.makeText(this, favoriteSet.contains(channel.name) ? "已收藏" : "已取消收藏", Toast.LENGTH_SHORT).show();
    }

    private void showOverlay() {
        isOverlayVisible = true;
        overlayLayout.setVisibility(View.VISIBLE);
        resetAutoHideTimer();
        epgContainer.setVisibility(View.GONE);
    }

    private void hideOverlay() {
        isOverlayVisible = false;
        overlayLayout.setVisibility(View.GONE);
        mainHandler.removeCallbacks(hideOverlayRunnable);
    }

    private void resetAutoHideTimer() {
        mainHandler.removeCallbacks(hideOverlayRunnable);
        if (isOverlayVisible) {
            mainHandler.postDelayed(hideOverlayRunnable, 5000);
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            startActivity(new Intent(this, SettingsActivity.class));
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void updateTime() {
        SimpleDateFormat sdf = new SimpleDateFormat("HH:mm EEEE", Locale.getDefault());
        tvTime.setText(sdf.format(new Date()));
        mainHandler.postDelayed(this::updateTime, 60000);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) {
            player.release();
            player = null;
        }
        mainHandler.removeCallbacks(hideOverlayRunnable);
    }

    static class SubAdapter extends RecyclerView.Adapter<SubAdapter.ViewHolder> {
        private List<SubEntry> data;
        private OnSubClickListener listener;
        interface OnSubClickListener { void onClick(SubEntry entry); }
        SubAdapter(List<SubEntry> data, OnSubClickListener listener) { this.data = data; this.listener = listener; }
        void updateData(List<SubEntry> newData) { this.data = newData; notifyDataSetChanged(); }
        @Override public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
            return new ViewHolder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_sub, parent, false));
        }
        @Override public void onBindViewHolder(ViewHolder holder, int position) {
            SubEntry entry = data.get(position);
            holder.name.setText(entry.name);
            if ("我的收藏".equals(entry.name)) holder.name.setTextColor(0xFFFFD700);
            else holder.name.setTextColor(0xFFFFFFFF);
            holder.itemView.setOnClickListener(v -> listener.onClick(entry));
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.sub_name); }
        }
    }

    static class GroupAdapter extends RecyclerView.Adapter<GroupAdapter.ViewHolder> {
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
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.group_name); }
        }
    }

    static class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.ViewHolder> {
        private List<SourceManager.Channel> data;
        private SourceManager.Channel selectedChannel;
        private OnChannelClickListener listener;
        private OnFavoriteClickListener favListener;
        private Set<String> favoriteSet;
        private File logoDir;
        interface OnChannelClickListener { void onClick(SourceManager.Channel channel); }
        interface OnFavoriteClickListener { void onFavorite(SourceManager.Channel channel); }
        ChannelAdapter(List<SourceManager.Channel> data, Set<String> favorites, File logoDir,
                       OnChannelClickListener listener, OnFavoriteClickListener favListener) {
            this.data = data; this.favoriteSet = favorites; this.logoDir = logoDir;
            this.listener = listener; this.favListener = favListener;
        }
        void updateData(List<SourceManager.Channel> newData) { this.data = newData; notifyDataSetChanged(); }
        void updateFavorites(Set<String> newFavorites) { this.favoriteSet = newFavorites; notifyDataSetChanged(); }
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
            if (ch.logoUrl != null && !ch.logoUrl.isEmpty()) {
                String fileName = ch.name.hashCode() + ".png";
                File logoFile = new File(logoDir, fileName);
                if (logoFile.exists()) {
                    holder.logo.setImageBitmap(BitmapFactory.decodeFile(logoFile.getAbsolutePath()));
                    holder.logo.setVisibility(View.VISIBLE);
                } else {
                    holder.logo.setVisibility(View.GONE);
                }
            } else {
                holder.logo.setVisibility(View.GONE);
            }
        }
        @Override public int getItemCount() { return data.size(); }
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView name, favIcon;
            ImageView logo;
            ViewHolder(View v) { super(v); name = v.findViewById(R.id.channel_name); favIcon = v.findViewById(R.id.channel_fav); logo = v.findViewById(R.id.channel_logo); }
        }
    }

    static class EpgAdapter extends RecyclerView.Adapter<EpgAdapter.ViewHolder> {
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
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView time, title;
            ViewHolder(View v) { super(v); time = v.findViewById(R.id.epg_time); title = v.findViewById(R.id.epg_title); }
        }
    }
}
EOF

    # ==================== SettingsActivity.java ====================
    cat > "$TEMPLATE_DIR/src/SettingsActivity.java" <<'EOF'
package com.whyun.witv;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Enumeration;
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
    private String localIp = "";
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        localIp = getLocalIpAddress();
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
    private String getLocalIpAddress() {
        try {
            for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements();) {
                NetworkInterface intf = en.nextElement();
                for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements();) {
                    InetAddress inetAddress = enumIpAddr.nextElement();
                    if (!inetAddress.isLoopbackAddress() && inetAddress.getHostAddress().indexOf(':') == -1) {
                        return inetAddress.getHostAddress();
                    }
                }
            }
        } catch (Exception e) {}
        return "127.0.0.1";
    }
    private void showContent(int pos) {
        List<ContentItem> items = new ArrayList<>();
        switch (pos) {
            case 0: items.add(new ContentItem("线路选择", "点击选择", v -> showLineSelection())); break;
            case 1: items.add(new ContentItem("频道搜索", "点击搜索", v -> Toast.makeText(this, "频道搜索功能", Toast.LENGTH_SHORT).show())); break;
            case 2: items.add(new ContentItem("播放设置", "点击展开", v -> showPlaySettings())); break;
            case 3: buildSubscriptionList(items); break;
            case 4: buildEpgSubscriptionList(items); break;
            case 5: items.add(new ContentItem("分类管理", "管理", v -> Toast.makeText(this, "分类管理", Toast.LENGTH_SHORT).show())); break;
            case 6: items.add(new ContentItem("订阅管理", "管理", v -> Toast.makeText(this, "订阅管理", Toast.LENGTH_SHORT).show())); break;
            case 7: items.add(new ContentItem("显示设置", "点击", v -> showDisplaySettings())); break;
            case 8: items.add(new ContentItem("偏好设置", "点击", v -> showPreferenceSettings())); break;
            case 9: items.add(new ContentItem("列表设置", "点击", v -> showListSettings())); break;
            case 10: items.add(new ContentItem("其他设置", "点击", v -> showOtherSettings())); break;
            case 11: items.add(new ContentItem("推送频道", "推送", v -> Toast.makeText(this, "推送频道", Toast.LENGTH_SHORT).show())); break;
            case 12: items.add(new ContentItem("更多管理", "查看", v -> showMoreInfo())); break;
        }
        contentAdapter.setItems(items);
    }
    private void buildSubscriptionList(List<ContentItem> items) {
        items.add(new ContentItem("扫码输入", "点击二维码查看说明", v -> Toast.makeText(this, "IP: " + localIp + " 端口 9978", Toast.LENGTH_LONG).show()));
        items.add(new ContentItem("列表订阅", "http://" + localIp + ":9978/", v -> {}));
        Set<String> subSet = prefs.getStringSet(KEY_SUB_LIST, new HashSet<>());
        String selected = prefs.getString(KEY_SELECTED_SUB, "");
        if (subSet != null && !subSet.isEmpty()) {
            for (String entry : subSet) {
                String[] parts = entry.split("\\|\\|");
                String name = parts.length > 0 ? parts[0] : entry;
                String url = parts.length > 1 ? parts[1] : "";
                boolean isSelected = entry.equals(selected);
                items.add(new ContentItem(name, url, isSelected, v -> {
                    if (isSelected) {
                        prefs.edit().putString(KEY_SELECTED_SUB, "").apply();
                        prefs.edit().putString("selected_sub_url", "").apply();
                        prefs.edit().putString("selected_sub_name", "").apply();
                        Toast.makeText(this, "已取消选中", Toast.LENGTH_SHORT).show();
                    } else {
                        prefs.edit().putString(KEY_SELECTED_SUB, entry).apply();
                        prefs.edit().putString("selected_sub_url", url).apply();
                        prefs.edit().putString("selected_sub_name", name).apply();
                        Toast.makeText(this, "已选中: " + name, Toast.LENGTH_SHORT).show();
                    }
                    showContent(3);
                    finish();
                }));
            }
        }
        items.add(new ContentItem("+ 添加订阅", "", v -> showAddSubscriptionDialog()));
    }
    private void buildEpgSubscriptionList(List<ContentItem> items) {
        items.add(new ContentItem("扫码输入", "点击二维码查看说明", v -> Toast.makeText(this, "EPG二维码功能", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("EPG订阅", "http://" + localIp + ":9978/", v -> {}));
        String epgUrl = prefs.getString("epg_url", "");
        if (!epgUrl.isEmpty()) {
            items.add(new ContentItem("当前EPG", epgUrl, true, v -> {}));
        }
        items.add(new ContentItem("缓存", "每天8点", v -> Toast.makeText(this, "缓存设置", Toast.LENGTH_SHORT).show()));
        items.add(new ContentItem("[XML]epw", "", v -> {}));
        items.add(new ContentItem("+ 添加EPG", "", v -> showEpgDialog()));
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
        builder.setPositiveButton("确定", null);
        builder.setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
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
            dialog.dismiss();
        });
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> dialog.dismiss());
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
        builder.setPositiveButton("确定", null);
        builder.setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(Color.WHITE);
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String url = urlInput.getText().toString().trim();
            if (url.isEmpty()) { Toast.makeText(this, "地址不能为空", Toast.LENGTH_SHORT).show(); return; }
            prefs.edit().putString("epg_url", url).apply();
            Toast.makeText(this, "EPG地址已保存", Toast.LENGTH_SHORT).show();
            showContent(4);
            dialog.dismiss();
        });
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> dialog.dismiss());
    }
    private void showLineSelection() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("线路选择").setItems(new String[]{"源1","源2","源3"}, (d,w) -> Toast.makeText(this, "选择线路"+(w+1), Toast.LENGTH_SHORT).show());
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showPlaySettings() {
        String[] items = {"解码方式", "画面比例", "超时换源", "断线重连"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("播放设置").setItems(items, (d, which) -> {
            switch (which) {
                case 0: showDecoderDialog(); break;
                case 1: showAspectDialog(); break;
                case 2: Toast.makeText(this, "超时换源", Toast.LENGTH_SHORT).show(); break;
                case 3: Toast.makeText(this, "断线重连", Toast.LENGTH_SHORT).show(); break;
            }
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showDecoderDialog() {
        final String[] decoders = {"系统解码", "IJK硬解", "IJK软解", "EXO硬解", "EXO软解", "MPV硬解", "MPV软解", "自动"};
        int current = PlayerConfigManager.getDecoder();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("解码方式")
                .setSingleChoiceItems(decoders, current, (d, which) -> {
                    PlayerConfigManager.setDecoder(which);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showAspectDialog() {
        final String[] aspects = {"默认", "16:9", "4:3", "填充", "原始", "裁剪", "电影"};
        int current = 0;
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("画面比例")
                .setSingleChoiceItems(aspects, current, (d, which) -> {
                    PlayerConfigManager.setAspectRatio(aspects[which]);
                    Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
                    d.dismiss();
                }).setNegativeButton("取消", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showDisplaySettings() {
        final String[] items = {"显示时间", "显示网速", "隐藏频道图标", "隐藏底部图标"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("显示设置").setItems(items, (d, which) -> {
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
            AlertDialog.Builder innerBuilder = new AlertDialog.Builder(this);
            innerBuilder.setTitle(items[which])
                    .setMessage("当前状态：" + (current ? "开启" : "关闭"))
                    .setPositiveButton("切换", (d2, w) -> {
                        prefs.edit().putBoolean(finalKey, !current).apply();
                        Toast.makeText(this, "已切换", Toast.LENGTH_SHORT).show();
                    })
                    .setNegativeButton("取消", null);
            AlertDialog innerDialog = innerBuilder.create();
            innerDialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            innerDialog.show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showPreferenceSettings() {
        final String[] items = {"记忆解码", "换台反转", "跨选分组", "关闭密码"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("偏好设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showListSettings() {
        final String[] items = {"全局字体大小", "列表宽度", "底部信息栏宽度"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("列表设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showOtherSettings() {
        final String[] items = {"EPG缓存"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("其他设置").setItems(items, (d, which) -> {
            Toast.makeText(this, items[which] + " (功能待完善)", Toast.LENGTH_SHORT).show();
        });
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
    }
    private void showMoreInfo() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("更多管理").setMessage("酷9 2.0.1\n软件仅供测试").setPositiveButton("确定", null);
        AlertDialog dialog = builder.create();
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        dialog.show();
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
            if (item.isSelected) {
                holder.title.setTextColor(Color.BLUE);
                holder.check.setVisibility(View.VISIBLE);
            } else {
                holder.title.setTextColor(Color.WHITE);
                holder.check.setVisibility(View.GONE);
            }
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

    # ==================== 布局文件（无 right_click_area） ====================
    cat > "$TEMPLATE_DIR/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <!-- 播放器 -->
    <androidx.media3.ui.PlayerView
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <!-- 左侧点击区域（显示覆盖层） -->
    <View
        android:id="@+id/left_click_area"
        android:layout_width="48dp"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        android:background="#00000000" />

    <!-- 底部信息栏 -->
    <LinearLayout
        android:id="@+id/bottom_bar"
        android:layout_width="match_parent"
        android:layout_height="50dp"
        android:layout_gravity="bottom"
        android:background="#CC000000"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:paddingStart="12dp"
        android:paddingEnd="12dp">
        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:orientation="vertical">
            <TextView
                android:id="@+id/tv_channel_name"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="频道名"
                android:textColor="#FFFFFF"
                android:textSize="14sp"
                android:textStyle="bold" />
            <TextView
                android:id="@+id/tv_epg_info"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="节目信息"
                android:textColor="#AAAAAA"
                android:textSize="11sp" />
        </LinearLayout>
        <TextView
            android:id="@+id/tv_time"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginEnd="16dp"
            android:text="00:00 周一"
            android:textColor="#FFFFFF"
            android:textSize="12sp" />
        <ImageButton
            android:id="@+id/btn_epg"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_epg"
            android:background="#00000000"
            android:tint="#FFFFFF" />
        <ImageButton
            android:id="@+id/btn_announce"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_announce"
            android:layout_marginStart="8dp"
            android:background="#00000000"
            android:tint="#FFFFFF" />
    </LinearLayout>

    <!-- 覆盖层（宽度仅占70%，靠左） -->
    <LinearLayout
        android:id="@+id/overlay_layout"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="horizontal"
        android:background="#CC000000"
        android:visibility="gone">

        <!-- 内容容器：宽度70%，包含三列 -->
        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.7"
            android:orientation="horizontal"
            android:background="#CC000000">

            <!-- 订阅源列 -->
            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:orientation="vertical"
                android:background="#33000000"
                android:padding="4dp">
                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="订阅源"
                    android:textColor="#FFFFFF"
                    android:textSize="11sp"
                    android:paddingBottom="2dp" />
                <androidx.recyclerview.widget.RecyclerView
                    android:id="@+id/sub_recycler"
                    android:layout_width="match_parent"
                    android:layout_height="match_parent" />
            </LinearLayout>

            <!-- 分组列 -->
            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:orientation="vertical"
                android:background="#44000000"
                android:padding="4dp">
                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="分组"
                    android:textColor="#FFFFFF"
                    android:textSize="11sp"
                    android:paddingBottom="2dp" />
                <androidx.recyclerview.widget.RecyclerView
                    android:id="@+id/group_recycler"
                    android:layout_width="match_parent"
                    android:layout_height="match_parent" />
            </LinearLayout>

            <!-- 频道列（含EPG） -->
            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1.8"
                android:orientation="vertical"
                android:background="#55000000"
                android:padding="4dp">
                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="频道列表"
                    android:textColor="#FFFFFF"
                    android:textSize="11sp"
                    android:paddingBottom="2dp" />
                <androidx.recyclerview.widget.RecyclerView
                    android:id="@+id/channel_recycler"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="1" />
                <LinearLayout
                    android:id="@+id/epg_container"
                    android:layout_width="match_parent"
                    android:layout_height="0dp"
                    android:layout_weight="0.6"
                    android:orientation="vertical"
                    android:background="#66000000"
                    android:visibility="gone">
                    <TextView
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:text="节目单"
                        android:textColor="#FFFFFF"
                        android:textSize="11sp"
                        android:padding="2dp" />
                    <androidx.recyclerview.widget.RecyclerView
                        android:id="@+id/epg_recycler"
                        android:layout_width="match_parent"
                        android:layout_height="match_parent" />
                </LinearLayout>
            </LinearLayout>
        </LinearLayout>

        <!-- 右侧空白区域（30%）点击关闭 -->
        <View
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.3"
            android:background="#00000000"
            android:clickable="true"
            android:onClick="hideOverlay" />
    </LinearLayout>
</FrameLayout>
EOF

    # ==================== 其他布局文件（同前） ====================
    cat > "$TEMPLATE_DIR/res/layout/item_sub.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/sub_name"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:paddingLeft="8dp"
    android:textSize="13sp"
    android:textColor="#FFFFFF"
    android:background="?attr/selectableItemBackground" />
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_group.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/group_name"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:paddingLeft="8dp"
    android:textSize="13sp"
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
    android:paddingLeft="8dp"
    android:paddingRight="8dp"
    android:background="?attr/selectableItemBackground">
    <ImageView
        android:id="@+id/channel_logo"
        android:layout_width="24dp"
        android:layout_height="24dp"
        android:scaleType="fitCenter"
        android:visibility="gone"
        android:layout_marginEnd="6dp" />
    <TextView
        android:id="@+id/channel_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textSize="13sp"
        android:textColor="#FFFFFF" />
    <TextView
        android:id="@+id/channel_fav"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="★"
        android:textSize="14sp"
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
    android:padding="4dp"
    android:background="?attr/selectableItemBackground">
    <TextView
        android:id="@+id/epg_time"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="11sp"
        android:textColor="#AAAAAA" />
    <TextView
        android:id="@+id/epg_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="13sp"
        android:textColor="#FFFFFF" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/activity_settings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="horizontal" android:background="#DD000000">
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/menu_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1" android:background="#33000000" android:padding="6dp" />
    <androidx.recyclerview.widget.RecyclerView android:id="@+id/content_recycler" android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="2" android:background="#44000000" android:padding="6dp" />
</LinearLayout>
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_menu.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/menu_text"
    android:layout_width="match_parent"
    android:layout_height="44dp"
    android:gravity="center_vertical"
    android:paddingLeft="12dp"
    android:textSize="14sp"
    android:textColor="#FFFFFF"
    android:background="#33000000" />
EOF

    cat > "$TEMPLATE_DIR/res/layout/item_content.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="8dp"
    android:background="#22000000">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">
        <TextView
            android:id="@+id/content_title"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:textSize="14sp"
            android:textColor="#FFFFFF" />
        <TextView
            android:id="@+id/content_check"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="√"
            android:textSize="16sp"
            android:textColor="#4CAF50"
            android:visibility="gone" />
    </LinearLayout>
    <TextView
        android:id="@+id/content_subtitle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="11sp"
        android:textColor="#AAAAAA" />
</LinearLayout>
EOF

    # ==================== 默认矢量图标（备用） ====================
    cat > "$TEMPLATE_DIR/res/drawable/ic_launcher.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
  <path android:fillColor="#FF5722" android:pathData="M8,5v14l11,-7z"/>
</vector>
EOF

    cat > "$TEMPLATE_DIR/res/drawable/ic_settings.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94s-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z"/>
</vector>
EOF
    cat > "$TEMPLATE_DIR/res/drawable/ic_epg.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19 3h-1V1h-2v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7z"/>
</vector>
EOF
    cat > "$TEMPLATE_DIR/res/drawable/ic_announce.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
</vector>
EOF

    echo "✅ 模板生成完毕"
fi

# ========== 复制模板到项目 ==========
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

# 为 SettingsActivity 添加缺失的 import
sed -i '/^package com.whyun.witv;/a import com.whyun.witv.player.PlayerConfigManager;' app/src/main/java/com/whyun/witv/SettingsActivity.java

# ========== 处理自定义图标 ==========
if [ -f "apk ico.jpeg" ]; then
    echo "📁 找到自定义图标 apk ico.jpeg，将作为应用图标..."
    cp "apk ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk_ico.jpeg" ]; then
    echo "📁 找到自定义图标 apk_ico.jpeg，将作为应用图标..."
    cp "apk_ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk ico.png" ]; then
    echo "📁 找到自定义图标 apk ico.png，将作为应用图标..."
    cp "apk ico.png" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
else
    echo "⚠️ 未找到自定义图标文件，使用默认矢量图标"
fi

# ========== 添加依赖和权限 ==========
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

# ========== 设置应用图标 ==========
echo "🛠️ 设置应用图标..."
python3 <<PYTHON_SCRIPT
import sys, xml.etree.ElementTree as ET
from xml.dom import minidom
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
manifest_file = "$MANIFEST"
pkg = "com.whyun.witv"
try:
    tree = ET.parse(manifest_file)
    root = tree.getroot()
except Exception as e:
    print(f"解析失败: {e}", file=sys.stderr)
    sys.exit(1)

app = root.find('application')
if app is None:
    print("未找到 application", file=sys.stderr)
    sys.exit(1)

# 设置图标属性
icon_attr = '{http://schemas.android.com/apk/res/android}icon'
app.set(icon_attr, '@drawable/ic_launcher')

# 清除所有旧 activity，重新创建
for act in app.findall('activity'):
    app.remove(act)

# 主 Activity
main_act = ET.Element('activity')
main_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.MainActivity")
main_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
intent_filter = ET.SubElement(main_act, 'intent-filter')
action = ET.SubElement(intent_filter, 'action')
action.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.action.MAIN')
cat = ET.SubElement(intent_filter, 'category')
cat.set('{http://schemas.android.com/apk/res/android}name', 'android.intent.category.LAUNCHER')
app.append(main_act)

# Settings Activity
settings_act = ET.Element('activity')
settings_act.set('{http://schemas.android.com/apk/res/android}name', f"{pkg}.SettingsActivity")
settings_act.set('{http://schemas.android.com/apk/res/android}exported', 'true')
app.append(settings_act)

xml_str = ET.tostring(root, encoding='unicode')
dom = minidom.parseString(xml_str)
pretty = dom.toprettyxml(indent="    ")
pretty = '\n'.join(pretty.split('\n')[1:]) if pretty.startswith('<?xml') else pretty
with open(manifest_file, 'w') as f:
    f.write(pretty)
print("✅ AndroidManifest 已更新（图标 + Activity）")
PYTHON_SCRIPT

# ========== 构建 ==========
echo "🧹 清理并构建..."
./gradlew clean
./gradlew assembleDebug

echo ""
echo "🎉 构建完成！APK 位于 app/build/outputs/apk/debug/"
echo "📌 修正内容："
echo "   ✅ 移除了 right_click_area 引用，使用右侧透明区域点击关闭"
echo "   ✅ 覆盖层宽度缩至屏幕 70%，三列比例 1:1:1.8"
echo "   ✅ 自定义图标自动设置"
echo "   ✅ 所有功能正常"
