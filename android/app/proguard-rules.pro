-keep public interface com.google.mediapipe.framework.* { public *; }
-keep public class com.google.mediapipe.framework.Packet {
    public static *** create(***);
    public long getNativeHandle();
    public void release();
}
-keep public class com.google.mediapipe.framework.PacketCreator {
    *** releaseWithSyncToken(...);
}
-keep public class com.google.mediapipe.framework.MediaPipeException {
    <init>(int, byte[]);
}
-keep class com.google.mediapipe.framework.ProtoUtil$SerializedMessage { *; }
-keep public class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keepclassmembers class com.google.common.flogger.** { *; }
-keep class ai.onnxruntime.** { *; }
-keep class ai.quickpose.core.Status$* { *; }