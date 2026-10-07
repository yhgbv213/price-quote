allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ============ 新增：强制所有 Android 子模块使用 compileSdk 36 ============
subprojects {
    afterEvaluate {
        // 尝试作为 Android Library 处理（share_plus 等插件都是 library 类型）
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.apply {
            compileSdk = 36
        }
        // 如果将来有 Application 类型的子模块，也一并处理
        extensions.findByType<com.android.build.api.dsl.ApplicationExtension>()?.apply {
            compileSdk = 36
        }
    }
}
// ====================================================================

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}