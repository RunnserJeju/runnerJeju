import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명 정보. 실제 값(키스토어 경로·비밀번호)은 git에 안 올라가는
// android/key.properties에 둔다. 파일이 없는 개발자는 release가 debug 키로
// 서명되어 빌드만 되게 둔다(아래 buildTypes 참고) — 로그인은 안 되지만
// `flutter run --release` 자체는 통과한다.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.runnersjeju.runners_jeju"
    // webview_flutter_android(카카오 로그인 SDK가 끌어옴)가 36 이상을 요구해서 flutter 기본값(35)을 올려둔다.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications(잠금화면 러닝 위젯)가 요구하는 core library
        // desugaring. 옛 Android에서도 최신 java.time 등을 쓰게 해준다.
        isCoreLibraryDesugaringEnabled = true
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

        // key.properties가 있을 때만 만든다. 없으면 참조 자체가 없어야 하므로
        // (없는 서명 설정을 release가 가리키면 빌드가 깨진다) 조건부로 생성한다.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            ndk {
                abiFilters += "arm64-v8a"
            }
        }

        release {
            // key.properties가 있으면 진짜 릴리즈 키로 서명한다. 없으면 debug 키로
            // 폴백해서 빌드만 통과시킨다(키스토어가 없는 개발자의 로컬 release 빌드용).
            // 스토어에 올릴 바이너리는 반드시 key.properties가 있는 환경에서 빌드할 것.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

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

dependencies {
    // isCoreLibraryDesugaringEnabled을 켜면 반드시 함께 있어야 하는 런타임.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
