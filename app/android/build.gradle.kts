allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Some transitive plugins drag in a newer kotlin-stdlib (2.3.x) than the
    // Kotlin Gradle plugin compiles against (2.1.x), failing metadata checks in
    // plugin subprojects (e.g. screen_brightness_android). Force the stdlib to
    // the plugin's version across ALL modules so every compile agrees.
    configurations.all {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-stdlib:2.1.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.1.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-common:2.1.20")
        }
    }
}

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
