Run chmod +x gradlew
Downloading https://services.gradle.org/distributions/gradle-8.9-bin.zip
............10%.............20%.............30%.............40%.............50%.............60%.............70%.............80%.............90%.............100%

Welcome to Gradle 8.9!

Here are the highlights of this release:
 - Enhanced Error and Warning Messages
 - IDE Integration Improvements
 - Daemon JVM Information

For more details see https://docs.gradle.org/8.9/release-notes.html

Starting a Gradle Daemon (subsequent builds will be faster)
> Task :app:preBuild UP-TO-DATE
> Task :app:preDebugBuild UP-TO-DATE
> Task :app:mergeDebugNativeDebugMetadata NO-SOURCE
> Task :app:generateDebugBuildConfig
> Task :app:javaPreCompileDebug
> Task :app:generateDebugResValues
> Task :app:checkDebugAarMetadata
> Task :app:mapDebugSourceSetPaths
> Task :app:generateDebugResources
> Task :app:packageDebugResources
> Task :app:mergeDebugResources
> Task :app:createDebugCompatibleScreenManifests
> Task :app:extractDeepLinksDebug
> Task :app:parseDebugLocalResources
> Task :app:processDebugMainManifest
> Task :app:processDebugManifest
> Task :app:mergeDebugShaders
> Task :app:compileDebugShaders NO-SOURCE
> Task :app:generateDebugAssets UP-TO-DATE
> Task :app:mergeDebugAssets
> Task :app:processDebugManifestForPackage
> Task :app:compressDebugAssets
> Task :app:processDebugResources
> Task :app:checkDebugDuplicateClasses

> Task :app:compileDebugJavaWithJavac
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/data/db/entity/FavoriteChannel.java:18: warning: There are multiple good constructors and Room will pick the no-arg constructor. You can use the @Ignore annotation to eliminate unwanted constructors.
public class FavoriteChannel {
       ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:11: error: package com.google.android.exoplayer2 does not exist
import com.google.android.exoplayer2.ExoPlayer;

                                    ^
> Task :app:compileDebugJavaWithJavac FAILED
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:12: error: package com.google.android.exoplayer2 does not exist
import com.google.android.exoplayer2.MediaItem;
                                    ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:13: error: package com.google.android.exoplayer2 does not exist
import com.google.android.exoplayer2.PlaybackException;
                                    ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:14: error: package com.google.android.exoplayer2 does not exist
import com.google.android.exoplayer2.Player;
                                    ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:15: error: package com.google.android.exoplayer2.trackselection does not exist
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector;
                                                   ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:16: error: package com.google.android.exoplayer2.ui does not exist
import com.google.android.exoplayer2.ui.PlayerView;
                                       ^
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:24: error: cannot find symbol
    private PlayerView playerView;
            ^
  symbol:   class PlayerView
  location: class MainActivity
/home/runner/work/witv/witv/app/src/main/java/com/whyun/witv/MainActivity.java:25: error: cannot find symbol
    private ExoPlayer player;
            ^
  symbol:   class ExoPlayer
  location: class MainActivity
Note: Some input files use or override a deprecated API.
Note: Recompile with -Xlint:deprecation for details.
8 errors
1 warning

FAILURE: Build failed with an exception.

* What went wrong:
20 actionable tasks: 20 executed
Execution failed for task ':app:compileDebugJavaWithJavac'.
> Compilation failed; see the compiler error output for details.

* Try:
> Run with --info option to get more log output.
> Run with --scan to get full insights.

BUILD FAILED in 46s
Error: Process completed with exit code 1.
