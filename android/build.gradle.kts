import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// Root-level plugins (Kotlin DSL way)
plugins {
    id("com.google.gms.google-services") version "4.4.3" apply false
}

// Global repositories
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Custom build directory logic
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
