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
}
// 强制所有插件使用 compileSdk 37（receive_sharing_intent 要求；老插件如 file_picker 默认 34）
subprojects {
    val bump = Action<Project> {
        val ext = extensions.findByName("android")
        if (ext != null) {
            try {
                ext.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(ext, 37)
            } catch (e: Exception) {
                logger.warn("compileSdk bump failed for $name: $e")
            }
        }
    }
    if (state.executed) bump.execute(this) else afterEvaluate(bump)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
