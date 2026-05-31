#!/usr/bin/env bash
# =============================================================================
# build_mxplayer.sh  –  Builds com.example.mxplayer (javagoat) from scratch
#                        and produces a signed release APK.
# Run from the directory that should become the project root.
# =============================================================================
set -euo pipefail

log()  { echo -e "\n\033[1;34m>>> $*\033[0m"; }
ok()   { echo -e "\033[1;32m    OK: $*\033[0m"; }

# ─────────────────────────── 1. Java 17 force ────────────────────────────────
log "Setting up Java 17..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    openjdk-17-jdk unzip wget curl ca-certificates 2>/dev/null

# Force Java 17 — ignore whatever default is installed
JAVA17=$(update-alternatives --list java 2>/dev/null | grep "java-17" | head -1)
if [ -z "$JAVA17" ]; then
    JAVA17=$(find /usr/lib/jvm -name "java" | grep "17" | head -1)
fi
if [ -z "$JAVA17" ]; then
    echo "ERROR: Java 17 not found after install"; exit 1
fi
export JAVA_HOME=$(dirname $(dirname "$JAVA17"))
export PATH="$JAVA_HOME/bin:$PATH"
ok "Java: $(java -version 2>&1 | head -1)"

# ─────────────────────────── 2. Android SDK ──────────────────────────────────
log "Setting up Android SDK command-line tools..."
ANDROID_HOME="$HOME/android-sdk"
SDK_ZIP="commandlinetools-linux-10406996_latest.zip"
SDK_URL="https://dl.google.com/android/repository/${SDK_ZIP}"
CMDLINE_DIR="$ANDROID_HOME/cmdline-tools/latest"

mkdir -p "$ANDROID_HOME/cmdline-tools"

if [ ! -f "/tmp/${SDK_ZIP}" ]; then
    wget -q --show-progress -O "/tmp/${SDK_ZIP}" "$SDK_URL"
fi

TMP_UNZIP=$(mktemp -d)
unzip -q "/tmp/${SDK_ZIP}" -d "$TMP_UNZIP"
rm -rf "$CMDLINE_DIR"
mv "$TMP_UNZIP/cmdline-tools" "$CMDLINE_DIR"
rm -rf "$TMP_UNZIP"

export ANDROID_HOME
export PATH="$CMDLINE_DIR/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"
ok "sdkmanager: $(sdkmanager --version)"

# ─────────────────────────── 3. SDK packages ─────────────────────────────────
log "Accepting SDK licenses and installing packages..."
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager --install \
    "platforms;android-34" \
    "build-tools;34.0.0" \
    "platform-tools"
ok "SDK packages installed."

# ─────────────────────────── 4. local.properties ─────────────────────────────
log "Writing local.properties..."
cat > local.properties <<EOF
sdk.dir=$ANDROID_HOME
EOF

# ─────────────────────────── 5. Keystore ─────────────────────────────────────
log "Generating release keystore..."
keytool -genkeypair \
    -keystore my-release-key.jks \
    -alias my-key-alias \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass mypassword123 \
    -keypass  mypassword123 \
    -dname "CN=javagoat, OU=ID, O=Example, L=City, ST=State, C=US" \
    -noprompt 2>/dev/null || true
ok "Keystore ready."

# ─────────────────────────── 6. Root Gradle files ────────────────────────────
log "Writing root Gradle files..."

cat > settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "MXPlayer"
include ':app'
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
EOF

cat > build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
}
EOF

# ─────────────────────────── 7. Gradle wrapper ───────────────────────────────
log "Downloading Gradle 8.2 and generating wrapper..."
GRADLE_ZIP="gradle-8.2-bin.zip"
GRADLE_URL="https://services.gradle.org/distributions/${GRADLE_ZIP}"
GRADLE_INSTALL="/opt/gradle/gradle-8.2"

if [ ! -d "$GRADLE_INSTALL" ]; then
    wget -q --show-progress -O "/tmp/${GRADLE_ZIP}" "$GRADLE_URL"
    sudo mkdir -p /opt/gradle
    sudo unzip -q "/tmp/${GRADLE_ZIP}" -d /opt/gradle
fi

"$GRADLE_INSTALL/bin/gradle" wrapper --gradle-version 8.2
chmod +x gradlew
ok "Gradle wrapper created."

# ─────────────────────────── 8. Directory scaffold ───────────────────────────
log "Creating project directory structure..."
JAVA_ROOT="app/src/main/java/com/example/mxplayer"
RES_ROOT="app/src/main/res"
mkdir -p "$JAVA_ROOT"
mkdir -p "$RES_ROOT/layout"
mkdir -p "$RES_ROOT/values"
mkdir -p "$RES_ROOT/drawable"
mkdir -p "$RES_ROOT/mipmap-anydpi-v26"
mkdir -p "$RES_ROOT/mipmap-hdpi"
mkdir -p "app/src/main/res/xml"

# ─────────────────────────── 9. app/build.gradle ─────────────────────────────
log "Writing app/build.gradle..."
mkdir -p app
cat > app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.example.mxplayer'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.mxplayer"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    signingConfigs {
        release {
            storeFile file('../my-release-key.jks')
            storePassword 'mypassword123'
            keyAlias     'my-key-alias'
            keyPassword  'mypassword123'
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'androidx.cardview:cardview:1.0.0'
    implementation 'androidx.media3:media3-exoplayer:1.2.0'
    implementation 'androidx.media3:media3-ui:1.2.0'
    implementation 'com.github.bumptech.glide:glide:4.16.0'
    annotationProcessor 'com.github.bumptech.glide:compiler:4.16.0'
}
EOF

# ─────────────────────────── 10. AndroidManifest.xml ─────────────────────────
log "Writing AndroidManifest.xml..."
cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

    <application
        android:label="javagoat"
        android:requestLegacyExternalStorage="true"
        android:usesCleartextTraffic="true"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.MXClone">

        <activity
            android:name=".SplashActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".MainActivity"
            android:exported="false" />

        <activity
            android:name=".PlayerActivity"
            android:exported="false"
            android:screenOrientation="sensor"
            android:configChanges="orientation|keyboardHidden|screenSize|smallestScreenSize|screenLayout" />

    </application>
</manifest>
EOF

# ─────────────────────────── 11. Resources ───────────────────────────────────
log "Writing resource files..."

cat > "$RES_ROOT/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="primary">#0F0F0F</color>
    <color name="primary_dark">#000000</color>
    <color name="accent">#E53935</color>
    <color name="bg_dark">#0A0A0A</color>
    <color name="surface_dark">#1A1A1A</color>
    <color name="text_light">#FFFFFF</color>
    <color name="text_secondary">#9E9E9E</color>
</resources>
EOF

cat > "$RES_ROOT/values/themes.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.MXClone" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/primary</item>
        <item name="colorPrimaryDark">@color/primary_dark</item>
        <item name="colorAccent">@color/accent</item>
        <item name="android:statusBarColor">@color/primary_dark</item>
        <item name="android:windowBackground">@color/bg_dark</item>
    </style>
</resources>
EOF

cat > "$RES_ROOT/values/strings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">javagoat</string>
</resources>
EOF

cat > "$RES_ROOT/drawable/bg_duration.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#CC000000" />
    <corners android:radius="4dp" />
</shape>
EOF

cat > "$RES_ROOT/drawable/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#E53935" />
</shape>
EOF

cat > "$RES_ROOT/drawable/ic_launcher_foreground.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M8,5v14l11,-7z" />
</vector>
EOF

cat > "$RES_ROOT/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF

cp "$RES_ROOT/mipmap-anydpi-v26/ic_launcher.xml" \
   "$RES_ROOT/mipmap-anydpi-v26/ic_launcher_round.xml"

# ─────────────────────────── 12. Layouts ─────────────────────────────────────
log "Writing layout XML files..."

cat > "$RES_ROOT/layout/activity_splash.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bg_dark">
    <TextView
        android:id="@+id/splashText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_centerInParent="true"
        android:text="javagoat"
        android:textColor="#E53935"
        android:textSize="44sp"
        android:textStyle="bold"
        android:letterSpacing="0.05"
        android:alpha="0" />
</RelativeLayout>
EOF

cat > "$RES_ROOT/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/bg_dark">
    <com.google.android.material.appbar.AppBarLayout
        android:id="@+id/appBarLayout"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@color/primary">
        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize"
            android:background="@color/primary"
            app:title="Local Videos"
            app:titleTextColor="#FFFFFF" />
    </com.google.android.material.appbar.AppBarLayout>
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/videoRecyclerView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingTop="8dp"
        android:paddingBottom="8dp"
        android:clipToPadding="false"
        app:layout_behavior="@string/appbar_scrolling_view_behavior" />
    <ProgressBar
        android:id="@+id/progressBar"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:visibility="gone" />
    <TextView
        android:id="@+id/emptyText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:text="No videos found"
        android:textColor="@color/text_secondary"
        android:visibility="gone" />
</androidx.coordinatorlayout.widget.CoordinatorLayout>
EOF

cat > "$RES_ROOT/layout/item_video.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="12dp"
    android:background="?attr/selectableItemBackground">
    <androidx.cardview.widget.CardView
        android:layout_width="140dp"
        android:layout_height="80dp"
        app:cardBackgroundColor="@color/surface_dark"
        app:cardCornerRadius="8dp"
        app:cardElevation="0dp">
        <RelativeLayout
            android:layout_width="match_parent"
            android:layout_height="match_parent">
            <ImageView
                android:id="@+id/videoThumbnail"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="centerCrop" />
            <TextView
                android:id="@+id/videoDuration"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_alignParentEnd="true"
                android:layout_alignParentBottom="true"
                android:layout_margin="4dp"
                android:background="@drawable/bg_duration"
                android:paddingStart="6dp"
                android:paddingEnd="6dp"
                android:paddingTop="2dp"
                android:paddingBottom="2dp"
                android:textSize="11sp"
                android:textStyle="bold"
                android:textColor="#FFFFFF" />
        </RelativeLayout>
    </androidx.cardview.widget.CardView>
    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_gravity="center_vertical"
        android:orientation="vertical"
        android:paddingStart="16dp"
        android:paddingEnd="8dp">
        <TextView
            android:id="@+id/videoTitle"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="2"
            android:ellipsize="end"
            android:textSize="15sp"
            android:textColor="@color/text_light" />
        <TextView
            android:id="@+id/videoSize"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="6dp"
            android:textSize="13sp"
            android:textColor="@color/text_secondary" />
    </LinearLayout>
    <ImageView
        android:layout_width="24dp"
        android:layout_height="24dp"
        android:layout_gravity="center_vertical"
        android:src="@android:drawable/ic_menu_more"
        android:contentDescription="More options"
        android:tint="@color/text_secondary" />
</LinearLayout>
EOF

cat > "$RES_ROOT/layout/activity_player.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">
    <androidx.media3.ui.PlayerView
        android:id="@+id/playerView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:use_controller="true"
        app:resize_mode="fit" />
    <LinearLayout
        android:id="@+id/indicatorLayout"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:background="@drawable/bg_duration"
        android:padding="24dp"
        android:orientation="vertical"
        android:gravity="center"
        android:visibility="gone">
        <TextView
            android:id="@+id/indicatorText"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="22sp"
            android:textStyle="bold"
            android:textColor="#FFFFFF" />
    </LinearLayout>
</FrameLayout>
EOF

# ─────────────────────────── 13. Java sources ────────────────────────────────
log "Writing Java source files..."

cat > "$JAVA_ROOT/SplashActivity.java" <<'EOF'
package com.example.mxplayer;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

public class SplashActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_splash);
        TextView splashText = findViewById(R.id.splashText);
        splashText.animate()
                .alpha(1f)
                .scaleX(1.2f)
                .scaleY(1.2f)
                .setDuration(1200)
                .withEndAction(() -> new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    startActivity(new Intent(SplashActivity.this, MainActivity.class));
                    finish();
                }, 400))
                .start();
    }
}
EOF

cat > "$JAVA_ROOT/MainActivity.java" <<'EOF'
package com.example.mxplayer;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.View;
import android.widget.ProgressBar;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.bumptech.glide.Glide;
import com.bumptech.glide.load.engine.DiskCacheStrategy;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {

    private static final int PERMISSION_REQUEST_CODE = 100;
    private RecyclerView videoRecyclerView;
    private ProgressBar progressBar;
    private TextView emptyText;

    static class VideoModel {
        String path, title;
        long duration, size;
        VideoModel(String path, String title, long duration, long size) {
            this.path = path; this.title = title;
            this.duration = duration; this.size = size;
        }
    }

    static class VideoAdapter extends RecyclerView.Adapter<VideoAdapter.VH> {
        interface OnVideoClickListener { void onVideoClick(VideoModel video); }
        private final List<VideoModel> videos;
        private final OnVideoClickListener listener;
        VideoAdapter(List<VideoModel> videos, OnVideoClickListener listener) {
            this.videos = videos; this.listener = listener;
        }
        @NonNull @Override
        public VH onCreateViewHolder(@NonNull android.view.ViewGroup parent, int viewType) {
            android.view.View v = android.view.LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_video, parent, false);
            return new VH(v);
        }
        @Override
        public void onBindViewHolder(@NonNull VH h, int pos) {
            VideoModel m = videos.get(pos);
            h.title.setText(m.title);
            long totalSec = m.duration / 1000;
            String durStr = (totalSec >= 3600)
                ? String.format("%02d:%02d:%02d", totalSec/3600, (totalSec%3600)/60, totalSec%60)
                : String.format("%02d:%02d", totalSec/60, totalSec%60);
            h.duration.setText(durStr);
            String sizeStr = (m.size >= 1073741824L)
                ? String.format("%.2f GB", m.size/1073741824.0)
                : String.format("%.2f MB", m.size/1048576.0);
            h.size.setText(sizeStr);
            Glide.with(h.itemView.getContext()).load(m.path)
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .placeholder(android.R.color.darker_gray).into(h.thumbnail);
            h.itemView.setOnClickListener(v -> listener.onVideoClick(m));
        }
        @Override public int getItemCount() { return videos.size(); }
        static class VH extends RecyclerView.ViewHolder {
            android.widget.ImageView thumbnail;
            android.widget.TextView duration, title, size;
            VH(android.view.View v) {
                super(v);
                thumbnail = v.findViewById(R.id.videoThumbnail);
                duration  = v.findViewById(R.id.videoDuration);
                title     = v.findViewById(R.id.videoTitle);
                size      = v.findViewById(R.id.videoSize);
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        videoRecyclerView = findViewById(R.id.videoRecyclerView);
        progressBar       = findViewById(R.id.progressBar);
        emptyText         = findViewById(R.id.emptyText);
        videoRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        checkPermissionAndLoad();
    }

    private void checkPermissionAndLoad() {
        String perm = (Build.VERSION.SDK_INT >= 33)
                ? Manifest.permission.READ_MEDIA_VIDEO
                : Manifest.permission.READ_EXTERNAL_STORAGE;
        if (ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED) {
            loadVideos();
        } else {
            ActivityCompat.requestPermissions(this, new String[]{perm}, PERMISSION_REQUEST_CODE);
        }
    }

    @Override
    public void onRequestPermissionsResult(int req, @NonNull String[] perms, @NonNull int[] res) {
        super.onRequestPermissionsResult(req, perms, res);
        if (req == PERMISSION_REQUEST_CODE && res.length > 0
                && res[0] == PackageManager.PERMISSION_GRANTED) loadVideos();
    }

    private void loadVideos() {
        progressBar.setVisibility(View.VISIBLE);
        new Thread(() -> {
            List<VideoModel> list = queryVideos();
            runOnUiThread(() -> {
                progressBar.setVisibility(View.GONE);
                if (list.isEmpty()) {
                    emptyText.setVisibility(View.VISIBLE);
                } else {
                    VideoAdapter adapter = new VideoAdapter(list, video -> {
                        Intent i = new Intent(this, PlayerActivity.class);
                        i.putExtra("videoPath",  video.path);
                        i.putExtra("videoTitle", video.title);
                        startActivity(i);
                    });
                    videoRecyclerView.setAdapter(adapter);
                }
            });
        }).start();
    }

    private List<VideoModel> queryVideos() {
        List<VideoModel> list = new ArrayList<>();
        Uri uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
        String[] proj = { MediaStore.Video.Media.DATA, MediaStore.Video.Media.TITLE,
                MediaStore.Video.Media.DURATION, MediaStore.Video.Media.SIZE };
        try (Cursor c = getContentResolver().query(uri, proj, null, null,
                MediaStore.Video.Media.DATE_ADDED + " DESC")) {
            if (c == null) return list;
            int colData=c.getColumnIndexOrThrow(MediaStore.Video.Media.DATA);
            int colTitle=c.getColumnIndexOrThrow(MediaStore.Video.Media.TITLE);
            int colDur=c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION);
            int colSize=c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE);
            while (c.moveToNext()) {
                String path = c.getString(colData);
                if (path == null || !new File(path).exists()) continue;
                list.add(new VideoModel(path, c.getString(colTitle),
                        c.getLong(colDur), c.getLong(colSize)));
            }
        }
        return list;
    }
}
EOF

cat > "$JAVA_ROOT/PlayerActivity.java" <<'EOF'
package com.example.mxplayer;

import android.content.Context;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import androidx.media3.common.MediaItem;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;

public class PlayerActivity extends AppCompatActivity {

    private ExoPlayer player;
    private PlayerView playerView;
    private LinearLayout indicatorLayout;
    private TextView indicatorText;
    private GestureDetector gestureDetector;
    private ScaleGestureDetector scaleGestureDetector;
    private AudioManager audioManager;
    private float scaleFactor = 1.0f;
    private int screenWidth, screenHeight;
    private boolean isLeftHalf;
    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        hideSystemUI();
        setContentView(R.layout.activity_player);
        playerView      = findViewById(R.id.playerView);
        indicatorLayout = findViewById(R.id.indicatorLayout);
        indicatorText   = findViewById(R.id.indicatorText);
        audioManager    = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        android.util.DisplayMetrics dm = new android.util.DisplayMetrics();
        getWindowManager().getDefaultDisplay().getMetrics(dm);
        screenWidth  = dm.widthPixels;
        screenHeight = dm.heightPixels;

        scaleGestureDetector = new ScaleGestureDetector(this,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override public boolean onScale(ScaleGestureDetector d) {
                    scaleFactor *= d.getScaleFactor();
                    scaleFactor = Math.max(0.5f, Math.min(scaleFactor, 5.0f));
                    View s = playerView.getVideoSurfaceView();
                    if (s != null) { s.setScaleX(scaleFactor); s.setScaleY(scaleFactor); }
                    return true;
                }
            });

        gestureDetector = new GestureDetector(this,
            new GestureDetector.SimpleOnGestureListener() {
                @Override public boolean onDown(MotionEvent e) {
                    isLeftHalf = e.getX() < screenWidth / 2f;
                    return true;
                }
                @Override public boolean onScroll(MotionEvent e1, MotionEvent e2,
                        float distX, float distY) {
                    if (Math.abs(distX) > Math.abs(distY)) return false;
                    float percent = (e1.getY() - e2.getY()) / screenHeight;
                    if (isLeftHalf) {
                        WindowManager.LayoutParams lp = getWindow().getAttributes();
                        float b = (lp.screenBrightness < 0) ? 0.5f : lp.screenBrightness;
                        b = Math.max(0.01f, Math.min(b + percent * 1.5f, 1.0f));
                        lp.screenBrightness = b;
                        getWindow().setAttributes(lp);
                        showIndicator("☀ " + (int)(b * 100) + "%");
                    } else {
                        int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                        int change = (int)(percent * maxVol * 1.5f);
                        if (change == 0) return true;
                        int cur = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
                        int newVol = Math.max(0, Math.min(cur + change, maxVol));
                        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, newVol,
                                AudioManager.FLAG_REMOVE_SOUND_AND_VIBRATE);
                        showIndicator("🔊 " + (int)((newVol * 100f) / maxVol) + "%");
                    }
                    return true;
                }
                @Override public boolean onDoubleTap(MotionEvent e) {
                    scaleFactor = 1.0f;
                    View s = playerView.getVideoSurfaceView();
                    if (s != null) { s.setScaleX(1.0f); s.setScaleY(1.0f); }
                    if (playerView.getResizeMode() == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
                        playerView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_ZOOM);
                        showIndicator("Crop to Fit");
                    } else {
                        playerView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);
                        showIndicator("Fit Screen");
                    }
                    return true;
                }
            });
    }

    @Override public boolean dispatchTouchEvent(MotionEvent ev) {
        scaleGestureDetector.onTouchEvent(ev);
        gestureDetector.onTouchEvent(ev);
        return super.dispatchTouchEvent(ev);
    }

    private void showIndicator(String text) {
        indicatorText.setText(text);
        indicatorLayout.setVisibility(View.VISIBLE);
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(() -> indicatorLayout.setVisibility(View.GONE), 1000);
    }

    private void initializePlayer() {
        if (player != null) return;
        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        String path = getIntent().getStringExtra("videoPath");
        if (path != null) {
            player.setMediaItem(MediaItem.fromUri(Uri.parse("file://" + path)));
            player.prepare();
            player.setPlayWhenReady(true);
        }
    }

    private void releasePlayer() {
        if (player != null) { player.pause(); player.release(); player = null; }
    }

    @Override protected void onStart()  { super.onStart();  initializePlayer(); }
    @Override protected void onResume() { super.onResume(); if (player == null) initializePlayer(); }
    @Override protected void onPause()  { super.onPause();  if (player != null) player.pause(); }
    @Override protected void onStop()   { super.onStop();   releasePlayer(); }

    private void hideSystemUI() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController ctrl = getWindow().getInsetsController();
            if (ctrl != null) {
                ctrl.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                ctrl.setSystemBarsBehavior(
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }
    }
}
EOF

# ─────────────────────────── 14. Final build ─────────────────────────────────
log "Running ./gradlew clean assembleRelease..."
./gradlew clean assembleRelease

RELEASE_APK=$(find . -path "*/release/*.apk" | head -1)
if [ -n "$RELEASE_APK" ]; then
    ok "✅ Signed release APK: $RELEASE_APK"
else
    echo "Build done — check app/build/outputs/apk/release/"
fi

log "Done! 🎉"
