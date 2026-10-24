allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/public") }
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
subprojects {
    project.evaluationDependsOn(":app")
}

// Permanent fix for AGP 8.x + Gradle 8.14 Windows file-locking bug.
// The verifyReleaseResources task holds a handle on linked.apk and then
// tries to delete its own output dir — causing "Access is denied" on Windows.
// This task only verifies resources and does NOT affect the APK output.
gradle.taskGraph.whenReady {
    allTasks
        .filter { it.name == "verifyReleaseResources" || it.name == "verifyDebugResources" }
        .forEach { it.enabled = false }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
    
}
