# R8 rules for release builds.
#
# Release has isMinifyEnabled = true but was never actually built before the
# Play Store work — CI only ever produced debug APKs. Everything below exists
# because R8 would otherwise rename or strip symbols that are resolved by
# *name* at runtime, which fails at runtime rather than at build time.

# --- JNI bridge -------------------------------------------------------------
# src/main/cpp/wimg_jni.c exports Java_com_wimg_app_bridge_WimgJni_<name>, so
# the class name, package and every native method name must survive intact.
-keep class com.wimg.app.bridge.WimgJni { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Called FROM native: wimg_jni.c does
#   GetMethodID(cls, "execute", "(Ljava/lang/String;[B)[B")
# to run the FinTS HTTP request through OkHttp. Renaming `execute` or dropping
# the no-arg constructor breaks every bank connection.
-keep class com.wimg.app.services.FintsHttpCallback {
    <init>();
    byte[] execute(java.lang.String, byte[]);
}

# --- WorkManager ------------------------------------------------------------
# Workers are instantiated reflectively from a class name persisted in
# WorkManager's own database, so the name has to stay stable across releases.
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# --- kotlinx.serialization --------------------------------------------------
# The library ships consumer rules, but generated serializers are looked up via
# the Companion, which R8 can strip when the class is only used reflectively.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class **$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    *** serializer(...);
}
