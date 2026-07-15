# Defensivo: si en el futuro se activa isMinifyEnabled, evita que R8 elimine las
# clases de ML Kit que se instancian por reflexión (provoca NullPointerException).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text** { *; }

-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# WorkManager/Room: R8 (modo full) elimina el constructor sin argumentos de las
# implementaciones que Room genera (p. ej. WorkDatabase_Impl), instanciadas por
# reflexión → NoSuchMethodException al arrancar el proceso. Blindaje por si algún
# consumidor de androidx.work vuelve a entrar en el build.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
