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
// Algunos plugins transitivos (p. ej. file_picker) se compilan contra un
// compileSdk antiguo (34) y flutter_plugin_android_lifecycle exige 36+.
// Forzamos compileSdk 36 en cualquier subproyecto Android que se quede corto.
// Debe registrarse antes del evaluationDependsOn(":app") de abajo, que ya
// dispara la evaluación de los proyectos.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val current = androidExt.javaClass
                .getMethod("getCompileSdkVersion")
                .invoke(androidExt) as String?
            val level = current?.removePrefix("android-")?.toIntOrNull()
            if (level == null || level < 36) {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, 36)
            }
        } catch (_: Exception) {
            // Si la extensión no expone estos métodos, no forzamos nada.
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
