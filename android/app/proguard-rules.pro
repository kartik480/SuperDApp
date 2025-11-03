# Razorpay ProGuard Rules
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# Keep ProGuard annotations
-keep class proguard.annotation.** { *; }
-dontwarn proguard.annotation.**

# Keep Kotlin coroutines
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory {
    public static <methods>;
}

