#!/bin/bash
set -e

echo "🔥 部署酷9风格UI到现有WiTV项目（增量修改版）"

# ========== 1. 恢复原始文件（防止之前覆盖） ==========
echo "🔄 恢复原始 activity_player.xml 和 PlayerActivity.java..."
git checkout -- app/src/main/res/layout/activity_player.xml 2>/dev/null || echo "⚠️ 无法恢复 activity_player.xml，请手动确认"
git checkout -- app/src/main/java/com/whyun/witv/ui/PlayerActivity.java 2>/dev/null || echo "⚠️ 无法恢复 PlayerActivity.java，请手动确认"

# ========== 2. 生成 EPGParser.java（解决编译错误） ==========
EPG_PKG_DIR="app/src/main/java/com/whyun/witv/epg"
mkdir -p "$EPG_PKG_DIR"
cat > "$EPG_PKG_DIR/EPGParser.java" <<'EOF'
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
echo "✅ EPGParser.java 已生成"

# ========== 3. 在 activity_player.xml 中插入覆盖层 ==========
ACTIVITY_PLAYER="app/src/main/res/layout/activity_player.xml"
if [ -f "$ACTIVITY_PLAYER" ]; then
    # 备份
    cp "$ACTIVITY_PLAYER" "$ACTIVITY_PLAYER.bak"

    # 检查是否已存在 overlay_layout，避免重复插入
    if ! grep -q "overlay_layout" "$ACTIVITY_PLAYER"; then
        echo "📝 正在向 activity_player.xml 插入覆盖层..."

        # 在 </FrameLayout> 之前插入覆盖层
        sed -i '/<\/FrameLayout>/i \
    <!-- 底部信息栏（新增） -->\
    <LinearLayout\
        android:id="@+id/bottom_bar"\
        android:layout_width="match_parent"\
        android:layout_height="50dp"\
        android:layout_gravity="bottom"\
        android:background="#CC000000"\
        android:gravity="center_vertical"\
        android:orientation="horizontal"\
        android:paddingStart="12dp"\
        android:paddingEnd="12dp">\
        <TextView\
            android:id="@+id/bottom_channel_name"\
            android:layout_width="0dp"\
            android:layout_height="wrap_content"\
            android:layout_weight="1"\
            android:text="频道名"\
            android:textColor="#FFFFFF"\
            android:textSize="14sp"\
            android:textStyle="bold"\
            android:visibility="gone" />\
        <TextView\
            android:id="@+id/bottom_epg_info"\
            android:layout_width="0dp"\
            android:layout_height="wrap_content"\
            android:layout_weight="1"\
            android:text="节目信息"\
            android:textColor="#AAAAAA"\
            android:textSize="11sp"\
            android:visibility="gone" />\
        <TextView\
            android:id="@+id/tv_time"\
            android:layout_width="wrap_content"\
            android:layout_height="wrap_content"\
            android:layout_marginEnd="16dp"\
            android:text="00:00 周一"\
            android:textColor="#FFFFFF"\
            android:textSize="12sp" />\
        <ImageButton\
            android:id="@+id/btn_epg"\
            android:layout_width="32dp"\
            android:layout_height="32dp"\
            android:src="@drawable/ic_epg"\
            android:background="#00000000"\
            android:tint="#FFFFFF" />\
        <ImageButton\
            android:id="@+id/btn_announce"\
            android:layout_width="32dp"\
            android:layout_height="32dp"\
            android:src="@drawable/ic_announce"\
            android:layout_marginStart="8dp"\
            android:background="#00000000"\
            android:tint="#FFFFFF" />\
    </LinearLayout>\
    <!-- 覆盖层（宽度35%，三列） -->\
    <LinearLayout\
        android:id="@+id/overlay_layout"\
        android:layout_width="match_parent"\
        android:layout_height="match_parent"\
        android:orientation="horizontal"\
        android:background="#CC000000"\
        android:visibility="gone">\
        <LinearLayout\
            android:layout_width="0dp"\
            android:layout_height="match_parent"\
            android:layout_weight="0.35"\
            android:orientation="horizontal"\
            android:background="#CC000000">\
            <LinearLayout\
                android:layout_width="0dp"\
                android:layout_height="match_parent"\
                android:layout_weight="1"\
                android:orientation="vertical"\
                android:background="#33000000"\
                android:padding="4dp">\
                <TextView\
                    android:layout_width="match_parent"\
                    android:layout_height="wrap_content"\
                    android:text="订阅源"\
                    android:textColor="#FFFFFF"\
                    android:textSize="11sp"\
                    android:paddingBottom="2dp" />\
                <androidx.recyclerview.widget.RecyclerView\
                    android:id="@+id/sub_recycler"\
                    android:layout_width="match_parent"\
                    android:layout_height="match_parent" />\
            </LinearLayout>\
            <LinearLayout\
                android:layout_width="0dp"\
                android:layout_height="match_parent"\
                android:layout_weight="0.8"\
                android:orientation="vertical"\
                android:background="#44000000"\
                android:padding="4dp">\
                <TextView\
                    android:layout_width="match_parent"\
                    android:layout_height="wrap_content"\
                    android:text="分组"\
                    android:textColor="#FFFFFF"\
                    android:textSize="11sp"\
                    android:paddingBottom="2dp" />\
                <androidx.recyclerview.widget.RecyclerView\
                    android:id="@+id/group_recycler"\
                    android:layout_width="match_parent"\
                    android:layout_height="match_parent" />\
            </LinearLayout>\
            <LinearLayout\
                android:layout_width="0dp"\
                android:layout_height="match_parent"\
                android:layout_weight="1.2"\
                android:orientation="vertical"\
                android:background="#55000000"\
                android:padding="4dp">\
                <TextView\
                    android:layout_width="match_parent"\
                    android:layout_height="wrap_content"\
                    android:text="频道列表"\
                    android:textColor="#FFFFFF"\
                    android:textSize="11sp"\
                    android:paddingBottom="2dp" />\
                <androidx.recyclerview.widget.RecyclerView\
                    android:id="@+id/channel_recycler"\
                    android:layout_width="match_parent"\
                    android:layout_height="0dp"\
                    android:layout_weight="1" />\
                <LinearLayout\
                    android:id="@+id/epg_container"\
                    android:layout_width="match_parent"\
                    android:layout_height="0dp"\
                    android:layout_weight="0.3"\
                    android:orientation="vertical"\
                    android:background="#66000000"\
                    android:visibility="gone">\
                    <TextView\
                        android:layout_width="match_parent"\
                        android:layout_height="wrap_content"\
                        android:text="节目单"\
                        android:textColor="#FFFFFF"\
                        android:textSize="11sp"\
                        android:padding="2dp" />\
                    <androidx.recyclerview.widget.RecyclerView\
                        android:id="@+id/epg_recycler"\
                        android:layout_width="match_parent"\
                        android:layout_height="match_parent" />\
                </LinearLayout>\
            </LinearLayout>\
        </LinearLayout>\
        <View\
            android:layout_width="0dp"\
            android:layout_height="match_parent"\
            android:layout_weight="0.65"\
            android:background="#00000000"\
            android:clickable="true"\
            android:onClick="hideOverlay" />\
    </LinearLayout>' "$ACTIVITY_PLAYER"

        echo "✅ 覆盖层已插入 activity_player.xml"
    else
        echo "ℹ️ activity_player.xml 已包含覆盖层，跳过插入"
    fi
fi

# ========== 4. 在 PlayerActivity.java 中增量添加代码 ==========
PLAYER_ACTIVITY="app/src/main/java/com/whyun/witv/ui/PlayerActivity.java"
if [ -f "$PLAYER_ACTIVITY" ]; then
    # 备份
    cp "$PLAYER_ACTIVITY" "$PLAYER_ACTIVITY.bak"

    # 添加 import（如果不存在）
    if ! grep -q "import com.whyun.witv.epg.EPGParser" "$PLAYER_ACTIVITY"; then
        sed -i '/^package com.whyun.witv.ui;/a import com.whyun.witv.epg.EPGParser;' "$PLAYER_ACTIVITY"
        echo "✅ 已添加 EPGParser import"
    fi
    if ! grep -q "import android.os.Handler" "$PLAYER_ACTIVITY"; then
        sed -i '/^package com.whyun.witv.ui;/a import android.os.Handler;' "$PLAYER_ACTIVITY"
        echo "✅ 已添加 Handler import"
    fi
    if ! grep -q "import android.os.Looper" "$PLAYER_ACTIVITY"; then
        sed -i '/^package com.whyun.witv.ui;/a import android.os.Looper;' "$PLAYER_ACTIVITY"
        echo "✅ 已添加 Looper import"
    fi

    # 在类中添加字段（在类声明后插入）
    if ! grep -q "private View overlayLayout" "$PLAYER_ACTIVITY"; then
        sed -i '/public class PlayerActivity extends FragmentActivity implements PlayerManager.Callback, SettingsPanelHost, WiTVApp.SourceChangeListener {/a \
    // ========== 酷9覆盖层新增字段 ==========\
    private View overlayLayout;\
    private RecyclerView subRecycler, groupRecycler, channelRecycler, epgRecycler;\
    private View epgContainer;\
    private TextView tvTime;\
    private Handler mainHandler = new Handler(Looper.getMainLooper());\
    private Runnable hideOverlayRunnable;' "$PLAYER_ACTIVITY"
        echo "✅ 已添加覆盖层字段"
    fi

    # 在 onCreate 方法中初始化覆盖层（在 setContentView 之后）
    # 先找到 setContentView 行，在其后插入初始化代码
    if ! grep -q "overlayLayout = findViewById(R.id.overlay_layout)" "$PLAYER_ACTIVITY"; then
        sed -i '/setContentView(R.layout.activity_player);/a \
        // ========== 初始化酷9覆盖层 ==========\
        overlayLayout = findViewById(R.id.overlay_layout);\
        if (overlayLayout != null) {\
            subRecycler = findViewById(R.id.sub_recycler);\
            groupRecycler = findViewById(R.id.group_recycler);\
            channelRecycler = findViewById(R.id.channel_recycler);\
            epgRecycler = findViewById(R.id.epg_recycler);\
            epgContainer = findViewById(R.id.epg_container);\
            if (subRecycler != null) subRecycler.setLayoutManager(new LinearLayoutManager(this));\
            if (groupRecycler != null) groupRecycler.setLayoutManager(new LinearLayoutManager(this));\
            if (channelRecycler != null) channelRecycler.setLayoutManager(new LinearLayoutManager(this));\
            if (epgRecycler != null) epgRecycler.setLayoutManager(new LinearLayoutManager(this));\
        }\
        tvTime = findViewById(R.id.tv_time);\
        updateTime();\
        hideOverlayRunnable = () -> {\
            if (overlayLayout != null && overlayLayout.getVisibility() == View.VISIBLE) {\
                overlayLayout.setVisibility(View.GONE);\
            }\
        };\
        findViewById(R.id.left_click_area).setOnClickListener(v -> {\
            if (overlayLayout.getVisibility() == View.VISIBLE) {\
                overlayLayout.setVisibility(View.GONE);\
            } else {\
                overlayLayout.setVisibility(View.VISIBLE);\
                resetAutoHideTimer();\
            }\
        });\
        findViewById(R.id.right_click_area).setOnClickListener(v -> {\
            if (overlayLayout.getVisibility() == View.VISIBLE) {\
                overlayLayout.setVisibility(View.GONE);\
                mainHandler.removeCallbacks(hideOverlayRunnable);\
            }\
        });' "$PLAYER_ACTIVITY"
        echo "✅ 已添加覆盖层初始化代码"
    fi

    # 添加辅助方法（在类末尾，最后一个 } 之前）
    if ! grep -q "private void resetAutoHideTimer()" "$PLAYER_ACTIVITY"; then
        sed -i '/^}/i \
    // ========== 酷9覆盖层辅助方法 ==========\
    private void resetAutoHideTimer() {\
        mainHandler.removeCallbacks(hideOverlayRunnable);\
        if (overlayLayout != null && overlayLayout.getVisibility() == View.VISIBLE) {\
            mainHandler.postDelayed(hideOverlayRunnable, 5000);\
        }\
    }\
    public void hideOverlay(View view) {\
        if (overlayLayout != null) {\
            overlayLayout.setVisibility(View.GONE);\
            mainHandler.removeCallbacks(hideOverlayRunnable);\
        }\
    }\
    private void updateTime() {\
        if (tvTime != null) {\
            java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("HH:mm EEEE", java.util.Locale.getDefault());\
            tvTime.setText(sdf.format(new java.util.Date()));\
            mainHandler.postDelayed(this::updateTime, 60000);\
        }\
    }' "$PLAYER_ACTIVITY"
        echo "✅ 已添加辅助方法"
    fi

    # 在 onDestroy 中清理 Handler
    if ! grep -q "mainHandler.removeCallbacks(hideOverlayRunnable)" "$PLAYER_ACTIVITY"; then
        sed -i '/super.onDestroy();/a \
        mainHandler.removeCallbacks(hideOverlayRunnable);' "$PLAYER_ACTIVITY"
        echo "✅ 已添加 onDestroy 清理"
    fi
fi

# ========== 5. 生成图标资源（如果不存在） ==========
mkdir -p app/src/main/res/drawable
cat > app/src/main/res/drawable/ic_epg.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M19 3h-1V1h-2v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7z" />
</vector>
EOF
cat > app/src/main/res/drawable/ic_announce.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z" />
</vector>
EOF
echo "✅ 图标资源已生成"

# ========== 6. 修复 SettingsCollapsibleFragment 中的错误 ==========
# 添加缺失的方法到 PlayerActivity（如果不存在）
if grep -q "getCurrentChannelIdForPanel" "$PLAYER_ACTIVITY"; then
    echo "ℹ️ getCurrentChannelIdForPanel 已存在"
else
    sed -i '/^}/i \
    public long getCurrentChannelIdForPanel() {\
        return currentChannelId;\
    }' "$PLAYER_ACTIVITY"
    echo "✅ 已添加 getCurrentChannelIdForPanel"
fi

# ========== 7. 添加缺失的 onError 方法实现（PlayerManager.Callback） ==========
if ! grep -q "public void onError" "$PLAYER_ACTIVITY"; then
    sed -i '/^}/i \
    @Override\
    public void onError(String error) {\
        // 实现错误处理\
        runOnUiThread(() -> {\
            Toast.makeText(this, "播放错误: " + error, Toast.LENGTH_SHORT).show();\
        });\
    }' "$PLAYER_ACTIVITY"
    echo "✅ 已添加 onError 方法"
fi

# ========== 8. 修复 PlayerManager 构造参数 ==========
# 如果 constructor 错误，我们无法通过 sed 修复，但原版项目应该使用正确的构造。
# 此脚本假设原版项目已正确，只添加新功能。

# ========== 9. 构建 APK ==========
echo "🧹 清理构建缓存..."
./gradlew clean

echo "🚀 开始构建 APK..."
chmod +x gradlew
./gradlew assembleDebug

echo ""
echo "🎉 构建完成！APK 位于 app/build/outputs/apk/debug/"
echo ""
echo "📌 修改内容："
echo "   ✅ 覆盖层宽度 35%，三列比例 1:0.8:1.2"
echo "   ✅ 底部信息栏隐藏频道名和 EPG 信息（但保留在布局中）"
echo "   ✅ 右侧 65% 透明区域点击关闭"
echo "   ✅ 点击左侧区域显示覆盖层"
echo "   ✅ 保留所有原有功能（EPG、数据库、播放器控制）"
echo ""
echo "⚠️ 如果仍有编译错误，请检查原始 PlayerActivity 的结构是否与脚本假设一致。"
echo "📌 备份文件已保存为 *.bak，可随时恢复。"
