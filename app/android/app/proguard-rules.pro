# Go (gomobile) calls these classes by name through JNI; keep them as is.
-keep class go.** { *; }
-keep class gatexcore.** { *; }
-keep class ru.gatexx.gatex.** { *; }
# Plugins on package:jni are called from Dart by name through JNI too.
-keep class io.flutter.plugins.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
