# ML Kit Fix
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Flutter ML Kit plugin
-keep class com.google_mlkit.** { *; }
-dontwarn com.google_mlkit.**