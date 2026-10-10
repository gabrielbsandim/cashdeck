# WorkManager opens its Room database by reflection; without this R8 strips the
# generated constructor and the app crashes at startup in release builds.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
