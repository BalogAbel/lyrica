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
subprojects {
    project.evaluationDependsOn(":app")
}

// sentry_flutter 8.14.2 pins Kotlin languageVersion/apiVersion to 1.6 in its
// own android/build.gradle, which Kotlin 2.2 rejects ("Language version 1.6
// is no longer supported"). Raise it to the minimum the compiler accepts.
// Registered in projectsEvaluated so it runs after the plugin's own
// kotlinOptions. Remove once sentry_flutter is upgraded to 9.x (see
// docs/deferred/2026-08-28-observability-remaining-use-cases.md).
gradle.projectsEvaluated {
    project(":sentry_flutter").tasks
        .withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
        .configureEach {
            compilerOptions {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
            }
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
