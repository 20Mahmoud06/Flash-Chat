# ── Huawei HMS Core ──────────────────────────────────────────────────────────
# The Push SDK references stub classes that only exist on real Huawei devices
# (BuildEx) and optional analytics classes (hianalytics). These are guarded at
# runtime, so R8 must not fail on their absence.
-dontwarn com.huawei.android.os.BuildEx$VERSION
-dontwarn com.huawei.hianalytics.process.HiAnalyticsConfig$Builder
-dontwarn com.huawei.hianalytics.process.HiAnalyticsConfig
-dontwarn com.huawei.hianalytics.process.HiAnalyticsInstance$Builder
-dontwarn com.huawei.hianalytics.process.HiAnalyticsInstance
-dontwarn com.huawei.hianalytics.process.HiAnalyticsManager
-dontwarn com.huawei.hianalytics.util.HiAnalyticTools
-dontwarn com.huawei.libcore.io.ExternalStorageFile
-dontwarn com.huawei.libcore.io.ExternalStorageFileInputStream
-dontwarn com.huawei.libcore.io.ExternalStorageFileOutputStream
-dontwarn com.huawei.libcore.io.ExternalStorageRandomAccessFile
-dontwarn org.bouncycastle.crypto.BlockCipher
-dontwarn org.bouncycastle.crypto.engines.AESEngine
-dontwarn org.bouncycastle.crypto.prng.SP800SecureRandom
-dontwarn org.bouncycastle.crypto.prng.SP800SecureRandomBuilder

# Keep HMS / AGConnect classes so their reflection-based code keeps working
# after shrinking (Huawei's official recommendation for minified builds).
-keep class com.huawei.hms.** { *; }
-keep class com.huawei.agconnect.** { *; }
-keep class com.huawei.push.** { *; }

# ── Firebase / Google Play Services ──────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firebase Firestore: keep FirestoreReflectiveSilentListener and
# model/data classes referenced via reflection by the SDK.
-keep class com.google.firebase.firestore.** { *; }
-keepclassmembers class * {
    @com.google.firebase.firestore.IgnoreExtraProperties *;
}

# ── Google Sign-In ───────────────────────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── Agora RTC SDK ───────────────────────────────────────────────────────────
-keep class io.agora.** { *; }
-keep class io.agora.rtc.** { *; }

# ── FlutterCallkitIncoming (vendored plugin) ──────────────────────────────────
-keep class com.hiennv.flutter_callkit_incoming.** { *; }

# ── App classes (keep all Dart-generated platform channel code) ───────────────
-keep class com.example.flash_chat_app.** { *; }
-keep class ** extends io.flutter.plugin.** { *; }
-keep class ** extends io.flutter.view.** { *; }
-keep class ** extends io.flutter.embedding.** { *; }

# ── Google Play Core (Split Install / deferred components) ────────────────────
# Flutter's PlayStoreDeferredComponentManager references these classes at
# runtime but they are not on the compile classpath (optional dependency).
# R8 must not fail on their absence.
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# ── Keep Kotlin data / serializable classes ──────────────────────────────────
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}

# ── Suppress warnings for optional / runtime-only APIs ───────────────────────
-dontwarn javax.annotation.**
-dontwarn sun.misc.Unsafe
