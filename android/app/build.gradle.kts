plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin (must be last)
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.attendance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required for modern Java features + notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        
    applicationId = "com.example.attendance_app"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
    multiDexEnabled = true
    manifestPlaceholders["appAuthRedirectScheme"] = "attendanceapp"  

    }

    buildTypes {
        release {
            // Using debug signing for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Java 8+ API support on older Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    // REQUIRED: Google Play Services Location (Geofence)
    implementation("com.google.android.gms:play-services-location:21.0.1")
}
