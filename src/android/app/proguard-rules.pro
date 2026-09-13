# Tink references errorprone annotations that aren't shipped at runtime
-dontwarn com.google.errorprone.annotations.**

# VAD native C++ 通过方法名回调 Java,onVoiceStart/onVoiceEnd 等不能被 R8 混淆
-keep class io.codeconcept.realtimecutvadlibrary.** { *; }
