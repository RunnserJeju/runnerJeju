allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // kakao_map_sdk(1.2.6)가 자체 compileSdk를 34로 고정해둬서 webview_flutter_android(36 요구)와
    // 충돌한다. 플러그인이 올라올 때까지 여기서 강제로 맞춘다. :app은 이미 36으로 직접 설정돼 있어서 제외.
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { android ->
                if (android.compileSdkVersion != "android-36") {
                    android.compileSdkVersion(36)
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
