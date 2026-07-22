#!/bin/bash
set -e

echo "🔥 部署 witv 播放器（EPG完整节目单版 - 右侧显示全部节目）"

TEMPLATE_DIR="./config"

# 强制重新生成
rm -rf "$TEMPLATE_DIR"
mkdir -p "$TEMPLATE_DIR"/{src,res/layout,res/drawable,res/values,assets}
mkdir -p "$TEMPLATE_DIR/src/epg" "$TEMPLATE_DIR/src/player" "$TEMPLATE_DIR/src/favorite" "$TEMPLATE_DIR/src/utils"

# ==================== 下载 epg_data.json（别名映射） ====================
echo "📥 下载别名映射 epg_data.json ..."
curl -s -L -o "$TEMPLATE_DIR/assets/epg_data.json" "https://raw.githubusercontent.com/tytestelle/witv/main/assets/epg_data.json" || \
wget -q -O "$TEMPLATE_DIR/assets/epg_data.json" "https://raw.githubusercontent.com/tytestelle/witv/main/assets/epg_data.json"

if [ ! -f "$TEMPLATE_DIR/assets/epg_data.json" ]; then
    echo "⚠️ 下载失败，创建空占位文件"
    echo '{"epgs":[]}' > "$TEMPLATE_DIR/assets/epg_data.json"
fi

# ==================== configuration.json ====================
cat > "$TEMPLATE_DIR/configuration.json" <<'EOF'
{"Configuration":{"LIVE_URLS":null,"EPG_URLS":"https://raw.githubusercontent.com/9602894/sandiJMYG/main/epg_data/epg_merged.xml","PLAY_TYPE":7,"PLAY_SCALE":3,"LIVE_CONNECT_TIMEOUT":1,"LIVE_SHOW_TIME":false,"LIVE_SHOW_NET_SPEED":false,"HIDE_Channel_LOGO":true,"HIDE_Bottom_LOGO":true,"CLOSE_EPG":false,"HIDE_FAVOR":false,"HIDE_NUMBER":false,"PL_MEMORYS_ET_SELECT":false,"LIVE_CHANNEL_REVERSE":false,"LIVE_CROSS_GROUP":false,"LIVE_SKIP_PASSWORD":false,"PIC_IN_PIC":false,"BOOT_START":false,"QUICK_EXIT":false,"EYE_PROTECTION":false,"PLAYBACK_ID":false,"TIME_SHIFT_ON":true,"PLAY_RENDER":1,"DOH_URL":0,"THEME_SELECT":2,"PLAY_BACK_TYPE":0,"RECONNECT_INDEX":0,"EXO_TUNNELING_SELECT":false,"RTSP_TCP_SELECT":0,"NAVIGATION_SELECT":0,"EPG_SHOW_TYPE_SELECT":0,"TEXT_SIZE":0,"LIST_WIDTH":0,"BOTTOM_WIDTH":0,"EPGCACHE_SELECT":4,"IMAGECACHE_SELECT":false,"SCRIPT_CACHE":true,"MEMORYS_SOURCE":true,"MEMORYS_POSITION":true,"BACKGROUND_THEME_SELECT":6,"BOOTRECEIVER_SET_SELECT":true,"SHORTCUTS_MENU":false,"SHORTCUTS_MENU_SELECT":"列表订阅,EPG订阅,无线投屏,频道搜索,APP信息","GROUP_PARS_SET_SELECT":3,"PLAY_ALL_SOURCE":true,"RESOLUTION_MODE_SELECT":0,"TIME_ZONE_SELECT":0,"TIME_SHIFT_MODE":0,"ENABLE_LOCAL_VIDEO":false,"M3U_LOGO_PRIORITY":false,"EPG_DESC_SET":false,"BOTTOM_DESC_SET":true,"ICON_INITIAL_SET":true,"EPG_CACHE_PATH_SET":false,"AUDIO_WAKKPAPER":false,"DE_INTERLACING":false}}
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

# ==================== LogUtils.java ====================
cat > "$TEMPLATE_DIR/src/utils/LogUtils.java" <<'EOF'
package com.whyun.witv.utils;

import android.content.Context;
import android.os.Environment;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class LogUtils {
    private static final String APP_DIR = "witv";
    private static final String LOG_DIR_NAME = "logs";
    private static final String LOG_FILE = "app.log";
    private static String sLogDirPath = null;

    public static void init(Context context) {
        if (sLogDirPath != null) return;
        File baseDir = null;
        try {
            if (Environment.getExternalStorageState().equals(Environment.MEDIA_MOUNTED)) {
                File extDir = new File(Environment.getExternalStorageDirectory(), APP_DIR);
                if (extDir.exists() || extDir.mkdirs()) {
                    baseDir = extDir;
                }
            }
        } catch (Exception e) {
            Log.e("LogUtils", "外部存储不可用", e);
        }
        if (baseDir == null) {
            File internalDir = new File(context.getFilesDir(), APP_DIR);
            if (internalDir.exists() || internalDir.mkdirs()) {
                baseDir = internalDir;
            }
        }
        if (baseDir == null) {
            baseDir = new File(context.getCacheDir(), APP_DIR);
            baseDir.mkdirs();
        }
        createAppDirectories(baseDir);
        File logDir = new File(baseDir, LOG_DIR_NAME);
        if (!logDir.exists()) logDir.mkdirs();
        sLogDirPath = logDir.getAbsolutePath();
        writeLog("=== 日志系统初始化成功，日志目录: " + sLogDirPath + " ===");
    }

    public static String getLogDir() {
        return sLogDirPath != null ? sLogDirPath : "";
    }

    public static void writeLog(String message) {
        if (sLogDirPath == null) return;
        try {
            String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date());
            String log = time + " - " + message + "\n";
            File logFile = new File(sLogDirPath, LOG_FILE);
            File parent = logFile.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            FileOutputStream fos = new FileOutputStream(logFile, true);
            fos.write(log.getBytes());
            fos.close();
        } catch (Exception e) {
            Log.e("LogUtils", "写入日志失败", e);
        }
    }

    public static void writeCrashLog(Throwable t) {
        if (sLogDirPath == null) return;
        try {
            String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date());
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            t.printStackTrace(pw);
            String stack = sw.toString();
            String log = "========== CRASH at " + time + " ==========\n" + stack + "\n\n";
            String fileName = "crash_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(new Date()) + ".txt";
            File logFile = new File(sLogDirPath, fileName);
            File parent = logFile.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            FileOutputStream fos = new FileOutputStream(logFile);
            fos.write(log.getBytes());
            fos.close();
            writeLog("CRASH: " + t.getMessage());
        } catch (Exception e) {
            Log.e("LogUtils", "写入崩溃日志失败", e);
        }
    }

    public static void createAppDirectories(File baseDir) {
        if (baseDir == null) return;
        String[] subDirs = {"localData", "backup", "download", "videoFile", "configuration", "logo", "js", "py", "webviewJscode", "epgCache", "logs"};
        for (String sub : subDirs) {
            File dir = new File(baseDir, sub);
            if (!dir.exists()) {
                dir.mkdirs();
            }
        }
        writeLog("应用目录创建完成: " + baseDir.getAbsolutePath());
    }

    public static String getAppRootDir() {
        if (sLogDirPath == null) return "";
        File baseDir = new File(sLogDirPath).getParentFile();
        return baseDir != null ? baseDir.getAbsolutePath() : "";
    }

    public static String getEpgCacheDir() {
        String root = getAppRootDir();
        return root.isEmpty() ? "" : root + "/epgCache";
    }
}
EOF

# ==================== EPGParser.java ====================
cat > "$TEMPLATE_DIR/src/epg/EPGParser.java" <<'EOF'
package com.whyun.witv.epg;

import android.content.Context;
import android.util.Xml;

import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserException;

import org.json.JSONObject;
import org.json.JSONArray;

import com.whyun.witv.utils.LogUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

public class EPGParser {

    public interface OnEpgLoadListener {
        void onLoaded(List<EpgProgram> programs);
        void onError(String error);
    }

    private static Map<String, String> sAliasMap = null;

    private static synchronized Map<String, String> loadAliasMap(Context context) {
        if (sAliasMap != null) return sAliasMap;
        Map<String, String> map = new HashMap<>();
        try {
            InputStream is = context.getAssets().open("epg_data.json");
            byte[] buffer = new byte[is.available()];
            is.read(buffer);
            is.close();
            String json = new String(buffer, "UTF-8");
            JSONObject root = new JSONObject(json);
            JSONArray epgs = root.getJSONArray("epgs");
            for (int i = 0; i < epgs.length(); i++) {
                JSONObject obj = epgs.getJSONObject(i);
                String epgid = obj.getString("epgid");
                String nameStr = obj.getString("name");
                String[] names = nameStr.split(",");
                for (String name : names) {
                    String normalized = normalizeChannelName(name.trim());
                    if (!normalized.isEmpty()) {
                        map.put(normalized, epgid);
                    }
                }
                String normalizedEpgid = normalizeChannelName(epgid);
                if (!normalizedEpgid.isEmpty()) {
                    map.put(normalizedEpgid, epgid);
                }
            }
            LogUtils.writeLog("别名映射加载完成，条目数: " + map.size());
        } catch (Exception e) {
            LogUtils.writeLog("加载别名映射失败: " + e.getMessage());
        }
        sAliasMap = map;
        return sAliasMap;
    }

    public static void loadEpg(Context context, String url, String channelName, OnEpgLoadListener listener) {
        LogUtils.writeLog("EPG加载开始: url=" + url + ", channel=" + channelName);
        new Thread(() -> {
            InputStream is = null;
            try {
                String cacheDir = LogUtils.getEpgCacheDir();
                File cacheDirFile = new File(cacheDir);
                if (!cacheDirFile.exists()) cacheDirFile.mkdirs();
                String fileName = "epg_" + System.currentTimeMillis() + ".xml";
                File cacheFile = new File(cacheDirFile, fileName);

                OkHttpClient client = new OkHttpClient.Builder()
                        .connectTimeout(30, TimeUnit.SECONDS)
                        .readTimeout(60, TimeUnit.SECONDS)
                        .addInterceptor(chain -> {
                            Request original = chain.request();
                            Request request = original.newBuilder()
                                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                                    .build();
                            return chain.proceed(request);
                        })
                        .build();
                Request request = new Request.Builder()
                        .url(url)
                        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                        .build();
                LogUtils.writeLog("EPG 请求发送: " + url);
                Response response = client.newCall(request).execute();
                if (!response.isSuccessful()) {
                    throw new Exception("HTTP " + response.code());
                }

                InputStream responseStream = response.body().byteStream();
                FileOutputStream fos = new FileOutputStream(cacheFile);
                byte[] buffer = new byte[8192];
                int len;
                while ((len = responseStream.read(buffer)) != -1) {
                    fos.write(buffer, 0, len);
                }
                fos.close();
                responseStream.close();
                LogUtils.writeLog("EPG 下载完成，缓存文件: " + cacheFile.getAbsolutePath());

                is = new FileInputStream(cacheFile);
                Map<String, String> aliasMap = loadAliasMap(context);
                String logoDir = LogUtils.getAppRootDir() + "/logo";
                List<EpgProgram> programs = parseXmltvStream(is, channelName, aliasMap, logoDir);
                LogUtils.writeLog("EPG 解析成功，节目数: " + (programs != null ? programs.size() : 0));

                android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                mainHandler.post(() -> listener.onLoaded(programs));

            } catch (Exception e) {
                LogUtils.writeCrashLog(e);
                LogUtils.writeLog("EPG 加载异常: " + e.getMessage());
                android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
                mainHandler.post(() -> listener.onError(e.getMessage()));
            } finally {
                try { if (is != null) is.close(); } catch (Exception ignored) {}
            }
        }).start();
    }

    private static List<EpgProgram> parseXmltvStream(InputStream is, String channelName, Map<String, String> aliasMap, String logoDir)
            throws XmlPullParserException, IOException, ParseException {

        Map<String, ChannelInfo> channelMap = new HashMap<>();
        Map<String, List<EpgProgram>> programMap = new HashMap<>();

        XmlPullParser parser = Xml.newPullParser();
        parser.setInput(is, "UTF-8");

        int eventType = parser.getEventType();
        String currentTag = null;
        boolean inChannel = false;
        boolean inProgramme = false;
        String currentChannelId = null;
        String currentDisplayName = null;
        String currentIconUrl = null;
        String progChannelId = null;
        String progStart = null;
        String progStop = null;
        String progTitle = null;
        String progDesc = null;

        SimpleDateFormat sdfWithZone = new SimpleDateFormat("yyyyMMddHHmmss Z", Locale.US);
        SimpleDateFormat sdfNoZone = new SimpleDateFormat("yyyyMMddHHmmss", Locale.US);

        while (eventType != XmlPullParser.END_DOCUMENT) {
            switch (eventType) {
                case XmlPullParser.START_TAG:
                    currentTag = parser.getName();
                    if ("channel".equals(currentTag)) {
                        inChannel = true;
                        currentChannelId = parser.getAttributeValue(null, "id");
                        currentDisplayName = null;
                        currentIconUrl = null;
                    } else if (inChannel && "display-name".equals(currentTag)) {
                    } else if (inChannel && "icon".equals(currentTag)) {
                        currentIconUrl = parser.getAttributeValue(null, "src");
                    } else if ("programme".equals(currentTag)) {
                        inProgramme = true;
                        progChannelId = parser.getAttributeValue(null, "channel");
                        progStart = parser.getAttributeValue(null, "start");
                        progStop = parser.getAttributeValue(null, "stop");
                        progTitle = null;
                        progDesc = null;
                    }
                    break;

                case XmlPullParser.TEXT:
                    if (inChannel && "display-name".equals(currentTag) && parser.getText() != null) {
                        currentDisplayName = parser.getText().trim();
                    }
                    if (inProgramme && parser.getText() != null) {
                        String text = parser.getText().trim();
                        if ("title".equals(currentTag)) {
                            if (progTitle == null) progTitle = text;
                            else progTitle += text;
                        } else if ("desc".equals(currentTag)) {
                            if (progDesc == null) progDesc = text;
                            else progDesc += text;
                        }
                    }
                    break;

                case XmlPullParser.END_TAG:
                    if ("channel".equals(parser.getName())) {
                        inChannel = false;
                        if (currentChannelId != null && currentDisplayName != null) {
                            ChannelInfo info = new ChannelInfo();
                            info.id = currentChannelId;
                            info.displayName = currentDisplayName;
                            info.iconUrl = currentIconUrl;
                            channelMap.put(currentChannelId, info);
                            LogUtils.writeLog("找到频道: " + currentDisplayName + " (" + currentChannelId + ")");
                        }
                    } else if ("programme".equals(parser.getName())) {
                        inProgramme = false;
                        if (progChannelId != null && progTitle != null && !progTitle.isEmpty()) {
                            EpgProgram prog = new EpgProgram();
                            prog.title = progTitle;
                            prog.desc = (progDesc != null) ? progDesc : "";

                            if (progStart != null && !progStart.isEmpty()) {
                                try {
                                    prog.startTime = sdfWithZone.parse(progStart).getTime();
                                } catch (ParseException e) {
                                    try {
                                        prog.startTime = sdfNoZone.parse(progStart).getTime();
                                    } catch (ParseException ignored) {}
                                }
                            }
                            if (progStop != null && !progStop.isEmpty()) {
                                try {
                                    prog.endTime = sdfWithZone.parse(progStop).getTime();
                                } catch (ParseException e) {
                                    try {
                                        prog.endTime = sdfNoZone.parse(progStop).getTime();
                                    } catch (ParseException ignored) {}
                                }
                            }

                            List<EpgProgram> list = programMap.get(progChannelId);
                            if (list == null) {
                                list = new ArrayList<>();
                                programMap.put(progChannelId, list);
                            }
                            list.add(prog);
                        }
                    }
                    break;
            }
            eventType = parser.next();
        }

        LogUtils.writeLog("共找到 " + channelMap.size() + " 个频道, " + programMap.size() + " 个有节目");

        String normalizedChannelName = normalizeChannelName(channelName);
        String targetChannelId = null;
        String targetDisplayName = null;

        // 1. 别名映射匹配
        String mappedEpgid = aliasMap.get(normalizedChannelName);
        if (mappedEpgid != null) {
            String normMapped = normalizeChannelName(mappedEpgid);
            for (Map.Entry<String, ChannelInfo> entry : channelMap.entrySet()) {
                String normDisp = normalizeChannelName(entry.getValue().displayName);
                if (normDisp.equals(normMapped) || normDisp.contains(normMapped) || normMapped.contains(normDisp)) {
                    targetChannelId = entry.getKey();
                    targetDisplayName = entry.getValue().displayName;
                    LogUtils.writeLog("别名映射匹配成功: " + channelName + " -> " + mappedEpgid + " -> " + targetDisplayName);
                    break;
                }
            }
        }

        // 2. 若未命中，取第一个 displayName 包含频道名的
        if (targetChannelId == null) {
            for (Map.Entry<String, ChannelInfo> entry : channelMap.entrySet()) {
                String normDisp = normalizeChannelName(entry.getValue().displayName);
                if (normDisp.contains(normalizedChannelName) || normalizedChannelName.contains(normDisp)) {
                    targetChannelId = entry.getKey();
                    targetDisplayName = entry.getValue().displayName;
                    LogUtils.writeLog("包含匹配成功: " + channelName + " -> " + targetDisplayName);
                    break;
                }
            }
        }

        if (targetChannelId == null) {
            LogUtils.writeLog("未找到匹配的频道，节目数为0");
            return new ArrayList<>();
        }

        // 下载图标
        ChannelInfo targetInfo = channelMap.get(targetChannelId);
        if (targetInfo != null && targetInfo.iconUrl != null && !targetInfo.iconUrl.isEmpty()) {
            downloadIcon(targetInfo.iconUrl, channelName, logoDir);
        }

        List<EpgProgram> result = programMap.get(targetChannelId);
        if (result == null) result = new ArrayList<>();

        Collections.sort(result, new Comparator<EpgProgram>() {
            @Override
            public int compare(EpgProgram o1, EpgProgram o2) {
                return Long.compare(o1.startTime, o2.startTime);
            }
        });

        LogUtils.writeLog("最终返回节目数: " + result.size());
        return result;
    }

    private static void downloadIcon(String iconUrl, String channelName, String logoDir) {
        try {
            if (iconUrl == null || iconUrl.isEmpty()) return;
            String decoded = java.net.URLDecoder.decode(iconUrl, "UTF-8");
            File logoFolder = new File(logoDir);
            if (!logoFolder.exists()) logoFolder.mkdirs();
            String fileName = channelName.hashCode() + ".png";
            File logoFile = new File(logoFolder, fileName);
            if (logoFile.exists()) {
                LogUtils.writeLog("图标已存在: " + logoFile.getAbsolutePath());
                return;
            }
            OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(10, TimeUnit.SECONDS)
                    .readTimeout(10, TimeUnit.SECONDS)
                    .build();
            Request request = new Request.Builder().url(decoded).build();
            Response response = client.newCall(request).execute();
            if (response.code() != 200) {
                LogUtils.writeLog("下载图标失败: " + response.code());
                return;
            }
            InputStream is = response.body().byteStream();
            FileOutputStream fos = new FileOutputStream(logoFile);
            byte[] buf = new byte[8192];
            int len;
            while ((len = is.read(buf)) != -1) {
                fos.write(buf, 0, len);
            }
            fos.close();
            is.close();
            LogUtils.writeLog("图标下载成功: " + logoFile.getAbsolutePath());
        } catch (Exception e) {
            LogUtils.writeLog("下载图标异常: " + e.getMessage());
        }
    }

    private static String normalizeChannelName(String name) {
        if (name == null) return "";
        String normalized = name.replaceAll("[\\s\\-_.()（）【】\\[\\]·:：]", "")
                .replaceAll("(?i)高清|HD|标清|SD|4K|8K|超清|FHD|UHD|\\d+p", "")
                .toLowerCase(Locale.getDefault());
        if (normalized.length() < 2) {
            return name.toLowerCase(Locale.getDefault()).replaceAll("[\\s\\-_.()（）【】\\[\\]·:：]", "");
        }
        return normalized;
    }

    private static class ChannelInfo {
        String id;
        String displayName;
        String iconUrl;
    }

    public static class EpgProgram {
        public long startTime;
        public long endTime;
        public String title;
        public String desc;

        @Override
        public String toString() {
            return "EpgProgram{" +
                    "startTime=" + startTime +
                    ", endTime=" + endTime +
                    ", title='" + title + '\'' +
                    ", desc='" + desc + '\'' +
                    '}';
        }
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

# ==================== MainActivity.java ====================
cat > "$TEMPLATE_DIR/src/MainActivity.java" <<'EOF'
package com.whyun.witv;
import android.Manifest;
import android.app.ProgressDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.preference.PreferenceManager;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.PopupWindow;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
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
import com.whyun.witv.utils.LogUtils;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
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
    private static final int REQUEST_PERMISSIONS = 100;
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
    private static final String KEY_LAST_GROUP = "last_group";
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    private File logoDir;
    private Runnable hideOverlayRunnable;
    private boolean isLoading = false;
    private List<SubEntry> subEntryList = new ArrayList<>();
    private View epgContainer;
    private List<EPGParser.EpgProgram> currentEpgList = new ArrayList<>();
    private ProgressDialog progressDialog;
    private boolean loadFinished = false;
    private View overlayClickArea;
    static class SubEntry { String name; String url; }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            try { LogUtils.writeCrashLog(throwable); } catch (Exception ignored) {}
            android.os.Process.killProcess(android.os.Process.myPid());
            System.exit(1);
        });
        try { Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Exception e) {}
        super.onCreate(savedInstanceState);

        LogUtils.init(this);
        LogUtils.writeLog("=== 应用启动 ===");

        String logDir = LogUtils.getLogDir();
        if (!logDir.isEmpty()) {
            Toast.makeText(this, "日志目录: " + logDir, Toast.LENGTH_LONG).show();
        } else {
            Toast.makeText(this, "日志目录创建失败", Toast.LENGTH_LONG).show();
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this,
                        new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE,
                                Manifest.permission.READ_EXTERNAL_STORAGE},
                        REQUEST_PERMISSIONS);
            }
        }

        try {
            setContentView(R.layout.activity_main);
            Toast.makeText(this, "界面加载完成", Toast.LENGTH_SHORT).show();
            LogUtils.writeLog("界面加载完成");

            config = ConfigurationManager.getInstance(this);
            PlayerConfigManager.init(this);
            FavoriteManager.init(this);
            prefs = PreferenceManager.getDefaultSharedPreferences(this);
            favoriteSet = new HashSet<>(prefs.getStringSet(KEY_FAVORITES, new HashSet<>()));
            logoDir = new File(LogUtils.getAppRootDir(), "logo");
            if (!logoDir.exists()) logoDir.mkdirs();

            String epgUrlPref = prefs.getString("epg_url", null);
            if (epgUrlPref == null || epgUrlPref.isEmpty()) {
                String configEpg = config.getString("EPG_URLS", null);
                if (configEpg != null && !configEpg.isEmpty()) {
                    prefs.edit().putString("epg_url", configEpg).apply();
                    LogUtils.writeLog("已从配置加载 EPG_URL: " + configEpg);
                    Toast.makeText(this, "EPG地址已自动配置", Toast.LENGTH_SHORT).show();
                }
            }

            playerView = findViewById(R.id.player_container);
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
            }, this::toggleFavorite);
            channelRecycler.setAdapter(channelAdapter);

            epgAdapter = new EpgAdapter(new ArrayList<>());
            epgRecycler.setAdapter(epgAdapter);

            playerView.setOnTouchListener((v, event) -> {
                if (event.getAction() == MotionEvent.ACTION_UP) {
                    float y = event.getY();
                    float height = v.getHeight();
                    if (y > height * 0.5 && y < height * 0.85) {
                        showInfoPopup();
                        return true;
                    }
                }
                return false;
            });

            overlayClickArea = findViewById(R.id.overlay_click_area);
            if (overlayClickArea != null) {
                overlayClickArea.setOnClickListener(v -> hideOverlay());
            }

            mainHandler.postDelayed(() -> {
                boolean hasSub = false;
                String selected = prefs.getString(KEY_SELECTED_SUB, "");
                if (!selected.isEmpty()) {
                    String[] parts = selected.split("\\|\\|");
                    if (parts.length == 2 && parts[1] != null && !parts[1].isEmpty()) {
                        currentSubName = parts[0];
                        currentSubUrl = parts[1];
                        hasSub = true;
                    }
                }
                if (!hasSub) {
                    for (SubEntry se : subEntryList) {
                        if (!"我的收藏".equals(se.name) && se.url != null && !se.url.isEmpty()) {
                            currentSubName = se.name;
                            currentSubUrl = se.url;
                            prefs.edit().putString(KEY_SELECTED_SUB, se.name + "||" + se.url).apply();
                            hasSub = true;
                            break;
                        }
                    }
                }

                if (!hasSub || currentSubUrl == null || currentSubUrl.isEmpty()) {
                    LogUtils.writeLog("没有可用的订阅源，显示引导对话框");
                    showNoSourceDialog();
                } else {
                    LogUtils.writeLog("加载订阅源: " + currentSubUrl);
                    showLoadingDialog("正在加载订阅源...");
                    loadSourceForUrl(currentSubUrl);
                }
            }, 500);

            hideOverlayRunnable = () -> {
                if (isOverlayVisible) hideOverlay();
            };
            findViewById(R.id.left_click_area).setOnClickListener(v -> {
                if (!isOverlayVisible) showOverlay();
            });

            LogUtils.writeLog("应用启动成功");
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            showFatalErrorDialog("初始化失败: " + e.getMessage());
        }
    }

    private void showLoadingDialog(String message) {
        if (progressDialog == null) {
            progressDialog = new ProgressDialog(this);
            progressDialog.setCancelable(false);
        }
        progressDialog.setMessage(message);
        progressDialog.show();
    }

    private void dismissLoadingDialog() {
        if (progressDialog != null && progressDialog.isShowing()) {
            progressDialog.dismiss();
        }
    }

    private void showNoSourceDialog() {
        dismissLoadingDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("提示");
        builder.setMessage("当前没有可用的订阅源，请先添加订阅源。");
        builder.setPositiveButton("去设置", (dialog, which) -> {
            startActivity(new Intent(this, SettingsActivity.class));
        });
        builder.setNegativeButton("退出", (dialog, which) -> {
            finish();
        });
        builder.setCancelable(false);
        AlertDialog dialog = builder.create();
        dialog.show();
    }

    private void showLoadErrorDialog(String errorMsg) {
        dismissLoadingDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("加载失败");
        builder.setMessage("订阅源加载失败：\n" + errorMsg + "\n\n请检查网络或源地址是否正确。");
        builder.setPositiveButton("去设置", (dialog, which) -> {
            startActivity(new Intent(this, SettingsActivity.class));
        });
        builder.setNegativeButton("重试", (dialog, which) -> {
            if (currentSubUrl != null && !currentSubUrl.isEmpty()) {
                showLoadingDialog("正在重试...");
                loadSourceForUrl(currentSubUrl);
            } else {
                showNoSourceDialog();
            }
        });
        builder.setCancelable(false);
        AlertDialog dialog = builder.create();
        dialog.show();
    }

    private void showFatalErrorDialog(String errorMsg) {
        dismissLoadingDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("严重错误");
        builder.setMessage("应用初始化失败：\n" + errorMsg + "\n\n请查看日志文件：\n" + LogUtils.getLogDir());
        builder.setPositiveButton("退出", (dialog, which) -> {
            finish();
        });
        builder.setCancelable(false);
        AlertDialog dialog = builder.create();
        dialog.show();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_PERMISSIONS) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                LogUtils.writeLog("存储权限已获取");
                LogUtils.init(this);
                Toast.makeText(this, "日志目录: " + LogUtils.getLogDir(), Toast.LENGTH_SHORT).show();
            } else {
                LogUtils.writeLog("存储权限被拒绝");
                Toast.makeText(this, "存储权限被拒绝，日志可能无法保存", Toast.LENGTH_SHORT).show();
            }
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        loadSubscriptions();
        subAdapter.updateData(subEntryList);
        if (groupMap.isEmpty() && !subEntryList.isEmpty() && !isLoading) {
            String selected = prefs.getString(KEY_SELECTED_SUB, "");
            if (!selected.isEmpty()) {
                String[] parts = selected.split("\\|\\|");
                if (parts.length == 2 && parts[1] != null && !parts[1].isEmpty()) {
                    currentSubName = parts[0];
                    currentSubUrl = parts[1];
                    showLoadingDialog("正在加载订阅源...");
                    loadSourceForUrl(currentSubUrl);
                }
            } else {
                for (SubEntry se : subEntryList) {
                    if (!"我的收藏".equals(se.name) && se.url != null && !se.url.isEmpty()) {
                        currentSubName = se.name;
                        currentSubUrl = se.url;
                        prefs.edit().putString(KEY_SELECTED_SUB, se.name + "||" + se.url).apply();
                        showLoadingDialog("正在加载订阅源...");
                        loadSourceForUrl(se.url);
                        break;
                    }
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
        if (isLoading || url == null || url.isEmpty()) {
            if (url == null || url.isEmpty()) {
                showNoSourceDialog();
            }
            return;
        }
        isLoading = true;
        loadFinished = false;
        if (url.contains("$")) url = url.substring(0, url.indexOf("$"));
        final String finalUrl = url;
        LogUtils.writeLog("开始加载源: " + finalUrl);
        Toast.makeText(this, "正在加载: " + finalUrl, Toast.LENGTH_SHORT).show();

        mainHandler.postDelayed(() -> {
            if (!loadFinished) {
                isLoading = false;
                dismissLoadingDialog();
                LogUtils.writeLog("加载源超时");
                showLoadErrorDialog("加载超时，请检查网络或源地址是否有效。");
            }
        }, 20000);

        new SourceManager(this).loadFromUrl(finalUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(Map<String, List<SourceManager.Channel>> map, List<String> names) {
                loadFinished = true;
                isLoading = false;
                dismissLoadingDialog();
                try {
                    groupMap = map;
                    groupNames = names;
                    groupAdapter.updateData(groupNames);
                    String lastGroup = prefs.getString(KEY_LAST_GROUP, "");
                    if (!lastGroup.isEmpty() && groupNames.contains(lastGroup)) {
                        currentGroup = lastGroup;
                    } else if (!groupNames.isEmpty()) {
                        currentGroup = groupNames.get(0);
                    }
                    if (!currentGroup.isEmpty()) {
                        groupAdapter.setSelectedGroup(currentGroup);
                        showChannelsForGroup(currentGroup);
                    } else {
                        currentChannelList.clear();
                        channelAdapter.updateData(currentChannelList);
                        Toast.makeText(MainActivity.this, "解析成功但无频道数据", Toast.LENGTH_LONG).show();
                    }
                    showOverlay();
                    resetAutoHideTimer();
                    LogUtils.writeLog("源加载成功，分组数: " + (map != null ? map.size() : 0));
                } catch (Exception e) {
                    LogUtils.writeCrashLog(e);
                    showLoadErrorDialog("数据处理异常: " + e.getMessage());
                }
            }
            @Override
            public void onError(String error) {
                loadFinished = true;
                isLoading = false;
                dismissLoadingDialog();
                LogUtils.writeLog("加载源失败: " + error);
                showLoadErrorDialog(error);
            }
        });
    }

    private void showChannelsForGroup(String group) {
        try {
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
            SourceManager.Channel target = null;
            if (!lastChannel.isEmpty()) {
                for (SourceManager.Channel ch : currentChannelList) {
                    if (ch.name.equals(lastChannel)) {
                        target = ch;
                        break;
                    }
                }
            }
            if (target == null && !currentChannelList.isEmpty()) {
                target = currentChannelList.get(0);
            }
            if (target != null) {
                channelAdapter.setSelectedChannel(target);
                playChannel(target);
                loadEpgForChannel(target);
            } else {
                Toast.makeText(this, "该分组无频道", Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "显示分组异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
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
                LogUtils.writeCrashLog(e);
            }
        }).start();
    }

    private void playChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        currentChannel = channel;
        prefs.edit().putString(KEY_LAST_CHANNEL, channel.name).apply();
        prefs.edit().putString(KEY_LAST_GROUP, currentGroup).apply();
        try {
            if (player == null) {
                DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
                player = new ExoPlayer.Builder(this)
                        .setTrackSelector(trackSelector)
                        .setLoadControl(new androidx.media3.exoplayer.DefaultLoadControl.Builder()
                                .setBufferDurationsMs(50000, 80000, 2500, 5000)
                                .build())
                        .build();
                playerView.setPlayer(player);
                player.addListener(new Player.Listener() {
                    @Override
                    public void onPlayerError(PlaybackException error) {
                        runOnUiThread(() -> {
                            LogUtils.writeCrashLog(error);
                            Toast.makeText(MainActivity.this, "播放错误: " + error.getMessage(), Toast.LENGTH_SHORT).show();
                        });
                    }
                });
            }
            player.setMediaItem(MediaItem.fromUri(channel.url));
            player.prepare();
            player.play();
            loadEpgForChannel(channel);
            LogUtils.writeLog("播放频道: " + channel.name + " URL: " + channel.url);
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "播放异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void loadEpgForChannel(SourceManager.Channel channel) {
        if (channel == null) return;
        String epgUrl = prefs.getString("epg_url", null);
        if (epgUrl == null || epgUrl.isEmpty()) {
            epgUrl = config.getString("EPG_URLS", null);
            if (epgUrl != null && !epgUrl.isEmpty()) {
                prefs.edit().putString("epg_url", epgUrl).apply();
            }
        }
        if (epgUrl == null || epgUrl.isEmpty()) {
            LogUtils.writeLog("未配置EPG URL");
            Toast.makeText(this, "未设置EPG地址", Toast.LENGTH_SHORT).show();
            epgAdapter.setItems(new ArrayList<>());
            currentEpgList.clear();
            epgContainer.setVisibility(View.GONE);
            return;
        }
        if (epgUrl.contains("$")) epgUrl = epgUrl.substring(0, epgUrl.indexOf("$"));
        final String finalEpgUrl = epgUrl;
        LogUtils.writeLog("开始加载EPG: " + finalEpgUrl + " for " + channel.name);
        Toast.makeText(this, "正在加载EPG...", Toast.LENGTH_SHORT).show();

        EPGParser.loadEpg(this, finalEpgUrl, channel.name, new EPGParser.OnEpgLoadListener() {
            @Override
            public void onLoaded(List<EPGParser.EpgProgram> programs) {
                runOnUiThread(() -> {
                    currentEpgList = programs;
                    epgAdapter.setItems(programs);
                    LogUtils.writeLog("EPG加载成功，节目数: " + programs.size());
                    Toast.makeText(MainActivity.this, "EPG加载成功，共" + programs.size() + "个节目", Toast.LENGTH_SHORT).show();
                    epgContainer.setVisibility(View.VISIBLE);
                });
            }
            @Override
            public void onError(String error) {
                runOnUiThread(() -> {
                    epgAdapter.setItems(new ArrayList<>());
                    currentEpgList.clear();
                    LogUtils.writeLog("EPG加载失败: " + error);
                    Toast.makeText(MainActivity.this, "EPG加载失败: " + error, Toast.LENGTH_SHORT).show();
                    epgContainer.setVisibility(View.GONE);
                });
            }
        });
    }

    private void toggleFavorite(SourceManager.Channel channel) {
        try {
            if (favoriteSet.contains(channel.name)) {
                favoriteSet.remove(channel.name);
            } else {
                favoriteSet.add(channel.name);
            }
            prefs.edit().putStringSet(KEY_FAVORITES, favoriteSet).apply();
            showChannelsForGroup(currentGroup);
            channelAdapter.updateFavorites(favoriteSet);
            Toast.makeText(this, favoriteSet.contains(channel.name) ? "已收藏" : "已取消收藏", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "收藏操作异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
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

    private void showInfoPopup() {
        if (currentChannel == null) return;
        try {
            View popupView = getLayoutInflater().inflate(R.layout.popup_info, null);
            ImageView ivLogo = popupView.findViewById(R.id.popup_logo);
            TextView tvName = popupView.findViewById(R.id.popup_channel_name);
            TextView tvResolution = popupView.findViewById(R.id.popup_resolution);
            TextView tvFps = popupView.findViewById(R.id.popup_fps);
            TextView tvAudio = popupView.findViewById(R.id.popup_audio);
            TextView tvIp = popupView.findViewById(R.id.popup_ip);
            TextView tvLine = popupView.findViewById(R.id.popup_line);
            TextView tvDuration = popupView.findViewById(R.id.popup_duration);
            TextView tvCurrentEpg = popupView.findViewById(R.id.popup_current_epg);
            TextView tvNextEpg = popupView.findViewById(R.id.popup_next_epg);
            tvName.setText(currentChannel.name);
            File logoFile = null;
            if (currentChannel.logoUrl != null && !currentChannel.logoUrl.isEmpty()) {
                String fileName = currentChannel.name.hashCode() + ".png";
                logoFile = new File(logoDir, fileName);
            }
            if (logoFile != null && logoFile.exists()) {
                ivLogo.setImageBitmap(BitmapFactory.decodeFile(logoFile.getAbsolutePath()));
                ivLogo.setVisibility(View.VISIBLE);
            } else {
                ivLogo.setVisibility(View.GONE);
            }
            tvResolution.setText("720x576");
            tvFps.setText("25FPS");
            tvAudio.setText("立体声");
            tvIp.setText("IPV4");
            tvLine.setText("线路1/1");
            long now = System.currentTimeMillis();
            if (!currentEpgList.isEmpty()) {
                EPGParser.EpgProgram currentProg = currentEpgList.get(0);
                long endTime = currentProg.endTime;
                long duration = endTime - now;
                if (duration < 0) duration = 0;
                long minutes = duration / 60000;
                tvDuration.setText("距结束：" + minutes + "分钟");
                SimpleDateFormat sdf = new SimpleDateFormat("HH:mm", Locale.getDefault());
                String currentTime = sdf.format(new Date(currentProg.startTime)) + "-" + sdf.format(new Date(currentProg.endTime));
                String desc = (currentProg.desc != null && !currentProg.desc.isEmpty()) ? currentProg.desc : "暂无描述信息";
                tvCurrentEpg.setText("正在播放：" + currentTime + " " + currentProg.title + " " + desc);
                if (currentEpgList.size() > 1) {
                    EPGParser.EpgProgram next = currentEpgList.get(1);
                    tvNextEpg.setText("下一节目：" + sdf.format(new Date(next.startTime)) + "-" + sdf.format(new Date(next.endTime)) + " " + next.title + (next.desc != null ? " " + next.desc : ""));
                } else {
                    tvNextEpg.setText("下一节目：暂无");
                }
            } else {
                tvDuration.setText("距结束：--");
                tvCurrentEpg.setText("正在播放：暂无EPG");
                tvNextEpg.setText("下一节目：暂无");
            }
            PopupWindow popup = new PopupWindow(popupView,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    true);
            popup.setBackgroundDrawable(null);
            popup.setOutsideTouchable(true);
            popup.showAtLocation(findViewById(android.R.id.content), Gravity.BOTTOM, 0, 0);
            popupView.setOnClickListener(v -> popup.dismiss());
        } catch (Exception e) {
            LogUtils.writeCrashLog(e);
            Toast.makeText(this, "信息窗口异常: " + e.getMessage(), Toast.LENGTH_SHORT).show();
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

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (player != null) {
            player.release();
            player = null;
        }
        mainHandler.removeCallbacks(hideOverlayRunnable);
        dismissLoadingDialog();
        LogUtils.writeLog("=== 应用退出 ===");
    }

    // ---------- Adapters ----------
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
            ViewHolder(View v) { super(v); 
                time = v.findViewById(R.id.epg_time);
                title = v.findViewById(R.id.epg_title);
            }
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
        builder.setTitle("更多管理").setMessage("witv 1.0.0\n软件仅供测试").setPositiveButton("确定", null);
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

# ==================== 布局文件 ====================
mkdir -p "$TEMPLATE_DIR/res/layout"
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
    <View
        android:id="@+id/left_click_area"
        android:layout_width="48dp"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        android:background="#00000000" />
    <LinearLayout
        android:id="@+id/overlay_layout"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="horizontal"
        android:background="#CC000000"
        android:visibility="gone">
        <!-- 左侧：订阅源、分组、频道列表 -->
        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.35"
            android:orientation="horizontal"
            android:background="#CC000000">
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
            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="0.8"
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
            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1.2"
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
            </LinearLayout>
        </LinearLayout>
        <!-- 右侧：EPG 节目单 -->
        <LinearLayout
            android:id="@+id/epg_container"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0.65"
            android:orientation="vertical"
            android:background="#66000000"
            android:padding="4dp"
            android:visibility="gone">
            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="节目单"
                android:textColor="#FFFFFF"
                android:textSize="14sp"
                android:padding="4dp"
                android:background="#44000000" />
            <androidx.recyclerview.widget.RecyclerView
                android:id="@+id/epg_recycler"
                android:layout_width="match_parent"
                android:layout_height="match_parent" />
        </LinearLayout>
        <View
            android:id="@+id/overlay_click_area"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="0"
            android:background="#00000000"
            android:clickable="true" />
    </LinearLayout>
</FrameLayout>
EOF

cat > "$TEMPLATE_DIR/res/layout/popup_info.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:background="#DD000000"
    android:padding="16dp">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <ImageView
            android:id="@+id/popup_logo"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:scaleType="fitCenter"
            android:visibility="gone" />
        <TextView
            android:id="@+id/popup_channel_name"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="12dp"
            android:text="频道名"
            android:textColor="#FFFFFF"
            android:textSize="18sp"
            android:textStyle="bold" />
    </LinearLayout>
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:orientation="horizontal">
        <TextView
            android:id="@+id/popup_resolution"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="720x576"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_fps"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="25FPS"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_audio"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="立体声"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_ip"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="IPV4"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
        <TextView
            android:id="@+id/popup_line"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="线路1/1"
            android:textColor="#AAAAAA"
            android:textSize="12sp" />
    </LinearLayout>
    <TextView
        android:id="@+id/popup_duration"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text="距结束：--分钟"
        android:textColor="#AAAAAA"
        android:textSize="12sp" />
    <TextView
        android:id="@+id/popup_current_epg"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:text="正在播放："
        android:textColor="#FFFFFF"
        android:textSize="14sp" />
    <TextView
        android:id="@+id/popup_next_epg"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text="下一节目："
        android:textColor="#AAAAAA"
        android:textSize="12sp" />
</LinearLayout>
EOF

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
    android:orientation="horizontal"
    android:padding="4dp"
    android:background="?attr/selectableItemBackground">
    <TextView
        android:id="@+id/epg_time"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="12sp"
        android:textColor="#AAAAAA"
        android:minWidth="80dp" />
    <TextView
        android:id="@+id/epg_title"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textSize="13sp"
        android:textColor="#FFFFFF"
        android:paddingStart="8dp" />
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

# ==================== 图标资源 ====================
mkdir -p "$TEMPLATE_DIR/res/drawable"
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

# ========== 复制模板到项目 ==========
echo "📂 复制模板文件到项目..."
rm -rf app/src/main/java/com/whyun/witv/ui
rm -f app/src/main/java/com/whyun/witv/SettingsActivity.java
rm -rf app/build
cp -r "$TEMPLATE_DIR/src/." app/src/main/java/com/whyun/witv/
cp -r "$TEMPLATE_DIR/res/." app/src/main/res/
cp "$TEMPLATE_DIR/configuration.json" app/src/main/assets/
cp "$TEMPLATE_DIR/assets/epg_data.json" app/src/main/assets/

mkdir -p app/src/main/assets/localData app/src/main/assets/backup app/src/main/assets/download \
         app/src/main/assets/videoFile app/src/main/assets/configuration app/src/main/assets/logo \
         app/src/main/assets/js app/src/main/assets/py app/src/main/assets/webviewJscode app/src/main/assets/epgCache
echo "✅ 文件复制完成"

# 修复 SettingsActivity import
sed -i '/^package com.whyun.witv;/a import com.whyun.witv.player.PlayerConfigManager;' app/src/main/java/com/whyun/witv/SettingsActivity.java

# ========== 自定义图标 ==========
if [ -f "apk ico.jpeg" ]; then
    cp "apk ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk_ico.jpeg" ]; then
    cp "apk_ico.jpeg" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
elif [ -f "apk ico.png" ]; then
    cp "apk ico.png" "app/src/main/res/drawable/ic_launcher.png"
    rm -f app/src/main/res/drawable/ic_launcher.xml
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
sed -i '/<application /a \        android:usesCleartextTraffic="true"' "$MANIFEST"
echo "✅ 权限和 cleartext 已添加"

# ========== 设置应用图标（使用临时文件） ==========
cat > /tmp/fix_manifest.py <<'PYEOF'
import sys, xml.etree.ElementTree as ET
from xml.dom import minidom
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
manifest_file = "app/src/main/AndroidManifest.xml"
pkg = "com.whyun.witv"
try:
    tree = ET.parse(manifest_file); root = tree.getroot()
except Exception as e:
    print(f"解析失败: {e}", file=sys.stderr); sys.exit(1)
app = root.find('application')
if app is None:
    print("未找到 application", file=sys.stderr); sys.exit(1)
icon_attr = '{http://schemas.android.com/apk/res/android}icon'
app.set(icon_attr, '@drawable/ic_launcher')
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
print("✅ AndroidManifest 已更新")
PYEOF

python3 /tmp/fix_manifest.py
rm -f /tmp/fix_manifest.py

# ========== 构建 ==========
echo "🧹 清理并构建..."
./gradlew clean
./gradlew assembleDebug

echo ""
echo "🎉 构建完成！APK 位于 app/build/outputs/apk/debug/"
echo "📌 模板已生成到 ./config/ 目录"
echo "📂 应用安装后会在外部存储或内部存储的 witv 目录下创建所需文件夹"
echo "📋 日志文件位置会在应用启动时 Toast 显示"
echo "💡 提示：若仍需手动添加别名，请编辑 assets/epg_data.json 后重新构建"
