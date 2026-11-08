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
// flutter_bluetooth_serial 0.4.0 predates AGP 8: it declares no namespace
// (required by AGP 8) and pins compileSdk 30, which cannot link
// android:attr/lStar from modern androidx (release builds). Supply both from
// the plugin's manifest package / the Flutter default. Must register before
// evaluationDependsOn kicks off subproject evaluation.
subprojects {
    afterEvaluate {
        if (name == "flutter_bluetooth_serial") {
            (extensions.findByName("android") as? com.android.build.gradle.LibraryExtension)
                ?.apply {
                    namespace = "io.github.edufolly.flutterbluetoothserial"
                    compileSdk = 36
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
