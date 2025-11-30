buildscript {    
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Google Services plugin for Firebase
        classpath("com.google.gms:google-services:4.4.2")
    }

}

allprojects {
    ext {
        set("appCompatVersion", "1.7.1")
        set("playServicesLocationVersion", "21.3.0")
    }
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        maven {
            url = uri(project(":flutter_background_geolocation").projectDir.resolve("libs"))
        }
        maven {
            url = uri(project(":background_fetch").projectDir.resolve("libs"))
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
