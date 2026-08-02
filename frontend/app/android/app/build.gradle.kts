plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.runnersjeju.runners_jeju"
    // webview_flutter_android(카카오 로그인 SDK가 끌어옴)가 36 이상을 요구해서 flutter 기본값(35)을 올려둔다.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.runnersjeju.runners_jeju"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 팀 공용 디버그 키스토어. 각자 PC마다 다른 ~/.android/debug.keystore 대신 이걸 써서,
    // 카카오 콘솔에 키 해시를 한 번만 등록하면 팀원 전체가 로컬에서 로그인이 된다.
    // 디버그 전용이라 git에 커밋해도 안전하다(비밀번호 고정, 배포에는 안 쓰임).
    signingConfigs {
        getByName("debug") {
            storeFile = file("../keystore/shared-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // 코드 축소는 아직 켜지 않았지만, 켜는 시점에 카카오맵 keep 규칙이
            // 빠져 릴리즈에서만 지도가 죽는 일이 없도록 미리 연결해둔다.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
