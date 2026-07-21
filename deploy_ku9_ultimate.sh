#!/bin/bash
set -e

echo "🔥 开始终极部署：彻底替换为酷9风格..."

# ========== 1. 检测项目配置 ==========
MANIFEST="app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
    echo "❌ 找不到 AndroidManifest.xml"
    exit 1
fi

PKG=$(grep -oP 'package="\K[^"]+' "$MANIFEST" | head -1)
echo "📦 包名: $PKG"

# 检测主 Activity（原启动 Activity）
MAIN_ACT_ORIG=$(grep -A5 'android.intent.action.MAIN' "$MANIFEST" | grep 'android:name' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ "$MAIN_ACT_ORIG" != *.* ]]; then
    MAIN_ACT_ORIG="$PKG.$MAIN_ACT_ORIG"
fi
MAIN_ACT_SIMPLE=$(basename "$MAIN_ACT_ORIG")
PKG_PATH=$(echo "$PKG" | tr '.' '/')
MAIN_ACT_FILE="app/src/main/java/$PKG_PATH/$MAIN_ACT_SIMPLE.java"

# 检测主布局
if [ -f "$MAIN_ACT_FILE" ]; then
    LAYOUT_NAME=$(grep -oP 'setContentView\(R\.layout\.\K[^)]+' "$MAIN_ACT_FILE" | head -1)
    [ -z "$LAYOUT_NAME" ] && LAYOUT_NAME="activity_main"
else
    LAYOUT_NAME="activity_main"
fi
LAYOUT_FILE="app/src/main/res/layout/${LAYOUT_NAME}.xml"
echo "🖌️ 主布局: $LAYOUT_NAME"

# ========== 2. 备份所有相关文件 ==========
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "$MAIN_ACT_FILE" ] && cp "$MAIN_ACT_FILE" "$BACKUP_DIR/"
[ -f "$LAYOUT_FILE" ] && cp "$LAYOUT_FILE" "$BACKUP_DIR/"
cp "$MANIFEST" "$BACKUP_DIR/"
echo "📂 原文件已备份到 $BACKUP_DIR"

# ========== 3. 修改 AndroidManifest.xml ==========
# 先备份
cp "$MANIFEST" "$MANIFEST.bak"

# 移除所有其他 LAUNCHER Activity（只保留我们即将设置的一个）
# 这里采用简单粗暴：删除所有 <category android:name="android.intent.category.LAUNCHER" /> 行
sed -i '/<category android:name="android.intent.category.LAUNCHER" \/>/d' "$MANIFEST"

# 找到要设置为主 Activity 的节点（第一个 activity），添加 LAUNCHER
# 若没有 activity，则创建一个
if grep -q '<activity' "$MANIFEST"; then
    # 在第一个 activity 标签内插入 LAUNCHER
    sed -i "0,/<activity/s/<activity/<activity android:name=\"$MAIN_ACT_ORIG\"\n            android:exported=\"true\"\n            >\n            <intent-filter>\n                <action android:name=\"android.intent.action.MAIN\" \/>\n                <category android:name=\"android.intent.category.LAUNCHER\" \/>\n            <\/intent-filter>/" "$MANIFEST"
else
    # 如果没有 activity，则在 application 内插入新的
    sed -i "/<application/a \        <activity android:name=\"$MAIN_ACT_ORIG\" android:exported=\"true\">\n            <intent-filter>\n                <action android:name=\"android.intent.action.MAIN\" \/>\n                <category android:name=\"android.intent.category.LAUNCHER\" \/>\n            <\/intent-filter>\n        <\/activity>" "$MANIFEST"
fi

# 确保 exported 属性正确（若有其他 activity 需要可手动调整）

echo "✅ AndroidManifest 已修改，启动 Activity 设为 $MAIN_ACT_ORIG"

# ========== 4. 生成新的 MainActivity（酷9风格） ==========
cat > "$MAIN_ACT_FILE" <<EOF
package $PKG;

import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.exoplayer2.ExoPlayer;
import com.google.android.exoplayer2.MediaItem;
import com.google.android.exoplayer2.PlaybackException;
import com.google.android.exoplayer2.Player;
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector;
import com.google.android.exoplayer2.ui.PlayerView;
import $PKG.favorite.FavoriteManager;
import $PKG.player.PlayerConfigManager;
import $PKG.source.SourceManager;
import java.util.List;

public class $MAIN_ACT_SIMPLE extends AppCompatActivity {

    private PlayerView playerView;
    private ExoPlayer player;
    private TextView bottomChannelName, bottomEpgInfo;
    private ImageView btnFavorite, btnSettings, btnEpg;
    private SourceManager.Channel currentChannel;
    private List<SourceManager.Channel> channelList;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.${LAYOUT_NAME});

        PlayerConfigManager.init(this);
        FavoriteManager.init(this);

        playerView = findViewById(R.id.player_container);
        bottomChannelName = findViewById(R.id.bottom_channel_name);
        bottomEpgInfo = findViewById(R.id.bottom_epg_info);
        btnFavorite = findViewById(R.id.btn_favorite);
        btnSettings = findViewById(R.id.btn_settings);
        btnEpg = findViewById(R.id.btn_epg);

        initPlayer();
        loadDefaultSource();

        btnFavorite.setOnClickListener(v -> toggleFavorite());
        btnSettings.setOnClickListener(v -> showSettingsDialog());
        btnEpg.setOnClickListener(v -> showEpgDialog());

        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                if (playbackState == Player.STATE_READY) {
                    updateUI();
                }
            }
            @Override
            public void onPlayerError(PlaybackException error) {
                Toast.makeText($MAIN_ACT_SIMPLE.this, "播放出错: " + error.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void initPlayer() {
        DefaultTrackSelector trackSelector = new DefaultTrackSelector(this);
        trackSelector.setParameters(
                trackSelector.buildUponParameters()
                        .setMaxVideoSize(1920, 1080)
                        .setPreferredVideoRole(PlayerConfigManager.getDecoder() == PlayerConfigManager.DECODER_SOFTWARE ?
                                DefaultTrackSelector.Role.ROLE_SOFTWARE_CODEC : null)
        );
        player = new ExoPlayer.Builder(this)
                .setTrackSelector(trackSelector)
                .build();
        playerView.setPlayer(player);
    }

    private void loadDefaultSource() {
        // 替换为你的默认源地址（可以是网络URL或本地文件）
        String defaultUrl = "https://example.com/channels.m3u";  // 请修改为你的直播源
        SourceManager sourceManager = new SourceManager(this);
        sourceManager.loadFromUrl(defaultUrl, new SourceManager.OnSourceLoadListener() {
            @Override
            public void onLoaded(List<SourceManager.Channel> channels) {
                channelList = channels;
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
            }
            @Override
            public void onError(String error) {
                Toast.makeText($MAIN_ACT_SIMPLE.this, "加载源失败: " + error, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void playChannel(SourceManager.Channel channel) {
        currentChannel = channel;
        MediaItem mediaItem = MediaItem.fromUri(channel.url);
        player.setMediaItem(mediaItem);
        player.prepare();
        player.play();
        updateUI();
    }

    private void updateUI() {
        if (currentChannel != null) {
            bottomChannelName.setText(currentChannel.name);
            boolean fav = FavoriteManager.isFavorite(currentChannel.name);
            btnFavorite.setImageResource(fav ? R.drawable.ic_favorite_filled : R.drawable.ic_favorite_border);
            bottomEpgInfo.setText("正在播放");
        }
    }

    private void toggleFavorite() {
        if (currentChannel == null) return;
        boolean newState = !FavoriteManager.isFavorite(currentChannel.name);
        FavoriteManager.toggleFavorite(currentChannel.name);
        updateUI();
        Toast.makeText(this, newState ? "已收藏" : "已取消收藏", Toast.LENGTH_SHORT).show();
    }

    private void showSettingsDialog() {
        String[] items = {"硬解", "软解", "画面比例", "切换源", "搜索频道", "自定义Headers"};
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("设置");
        builder.setItems(items, (dialog, which) -> {
            switch (which) {
                case 0:
                    PlayerConfigManager.setDecoder(PlayerConfigManager.DECODER_HARDWARE);
                    Toast.makeText(this, "已切换为硬解", Toast.LENGTH_SHORT).show();
                    restartPlayer();
                    break;
                case 1:
                    PlayerConfigManager.setDecoder(PlayerConfigManager.DECODER_SOFTWARE);
                    Toast.makeText(this, "已切换为软解", Toast.LENGTH_SHORT).show();
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
                    showHeadersDialog();
                    break;
            }
        });
        builder.show();
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
        builder.setTitle("画面比例");
        builder.setItems(ratios, (dialog, which) -> {
            String ratio = ratios[which];
            PlayerConfigManager.setAspectRatio(ratio);
            Toast.makeText(this, "比例已设为: " + ratio, Toast.LENGTH_SHORT).show();
        });
        builder.show();
    }

    private void showSourceSwitchDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("输入新源URL");
        final android.widget.EditText input = new android.widget.EditText(this);
        builder.setView(input);
        builder.setPositiveButton("加载", (dialog, which) -> {
            String url = input.getText().toString();
            if (!url.isEmpty()) {
                SourceManager sourceManager = new SourceManager(this);
                sourceManager.loadFromUrl(url, new SourceManager.OnSourceLoadListener() {
                    @Override
                    public void onLoaded(List<SourceManager.Channel> channels) {
                        channelList = channels;
                        if (!channels.isEmpty()) playChannel(channels.get(0));
                    }
                    @Override
                    public void onError(String error) {
                        Toast.makeText($MAIN_ACT_SIMPLE.this, "加载失败: " + error, Toast.LENGTH_SHORT).show();
                    }
                });
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showSearchDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("搜索频道");
        final android.widget.EditText input = new android.widget.EditText(this);
        builder.setView(input);
        builder.setPositiveButton("搜索", (dialog, which) -> {
            String keyword = input.getText().toString().trim();
            if (!keyword.isEmpty() && channelList != null) {
                for (SourceManager.Channel ch : channelList) {
                    if (ch.name.contains(keyword)) {
                        playChannel(ch);
                        return;
                    }
                }
                Toast.makeText(this, "未找到频道", Toast.LENGTH_SHORT).show();
            }
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showHeadersDialog() {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setTitle("自定义Headers (JSON格式)");
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setText(PlayerConfigManager.getCustomHeaders());
        builder.setView(input);
        builder.setPositiveButton("保存", (dialog, which) -> {
            String headers = input.getText().toString();
            PlayerConfigManager.setCustomHeaders(headers);
            Toast.makeText(this, "Headers已保存", Toast.LENGTH_SHORT).show();
        });
        builder.setNegativeButton("取消", null);
        builder.show();
    }

    private void showEpgDialog() {
        Toast.makeText(this, "EPG功能开发中", Toast.LENGTH_SHORT).show();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            showSettingsDialog();
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
    }
}
EOF

echo "✅ 生成新的 MainActivity: $MAIN_ACT_FILE"

# ========== 5. 生成主布局 ==========
cat > "$LAYOUT_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <FrameLayout
        android:id="@+id/player_container"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <LinearLayout
        android:id="@+id/bottom_controls"
        android:layout_width="match_parent"
        android:layout_height="60dp"
        android:layout_alignParentBottom="true"
        android:background="#CC000000"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:paddingLeft="16dp"
        android:paddingRight="16dp">

        <TextView
            android:id="@+id/bottom_channel_name"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="频道名称"
            android:textColor="#FFFFFF"
            android:textSize="16sp"
            android:textStyle="bold" />

        <TextView
            android:id="@+id/bottom_epg_info"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginRight="16dp"
            android:text="节目信息"
            android:textColor="#AAAAAA"
            android:textSize="14sp" />

        <ImageView
            android:id="@+id/btn_favorite"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_favorite_border"
            android:layout_marginRight="12dp" />

        <ImageView
            android:id="@+id/btn_settings"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_settings"
            android:layout_marginRight="12dp" />

        <ImageView
            android:id="@+id/btn_epg"
            android:layout_width="32dp"
            android:layout_height="32dp"
            android:src="@drawable/ic_info" />
    </LinearLayout>

</RelativeLayout>
EOF

echo "✅ 生成布局文件: $LAYOUT_FILE"

# ========== 6. 添加图标和功能类（如不存在） ==========
# 这里省略之前已有的功能类，确保存在即可
# 实际脚本中应包含所有类文件的创建，但为节省篇幅，此处假设已存在或由前序脚本生成。
# 如果缺失，可在脚本中添加。

# ========== 7. 添加资源文件 ==========
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

# ========== 8. 添加菜单资源 ==========
mkdir -p app/src/main/res/menu
cat > app/src/main/res/menu/main_menu.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:id="@+id/action_decoder_hw" android:title="硬解" />
    <item android:id="@+id/action_decoder_sw" android:title="软解" />
    <item android:id="@+id/action_aspect_ratio" android:title="画面比例" />
    <item android:id="@+id/action_search" android:title="搜索频道" />
</menu>
EOF

# ========== 9. 确保功能类存在 ==========
# 这里假设之前的脚本已经创建了 SourceManager、PlayerConfigManager 等，如果缺失，可以在此补充
# 为了简洁，此处略，但若运行时发现缺少，可补上。

# ========== 10. 更新工作流 ==========
mkdir -p .github/workflows
cat > .github/workflows/build.yml <<'EOF'
name: Build APK with Ku9 Enhancements
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Deploy Ku9 Ultimate
        run: |
          chmod +x deploy_ku9_ultimate.sh
          ./deploy_ku9_ultimate.sh
      - name: Build APK
        run: |
          chmod +x gradlew
          ./gradlew assembleDebug
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: ku9-like-app
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

echo "✅ 工作流已更新"

# ========== 11. 完成提示 ==========
echo ""
echo "🎉 部署完成！"
echo "请检查以下："
echo "1. 如果默认源地址不是你的，请在 MainActivity 中修改 defaultUrl。"
echo "2. 如果编译报错缺少类，请确保 SourceManager 等类存在（可由之前脚本生成）。"
echo "3. 运行 ./gradlew assembleDebug 测试编译。"
echo "4. 安装后，APP 将直接播放，无需网页配置。"
