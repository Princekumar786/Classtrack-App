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
// Some plugins (e.g. file_picker 8.x) hardcode an older `compileSdk` in their
// own Gradle, which fails AAR metadata checks when a transitive dependency
// requires a newer one. Bump any plugin compiling below the app's level up to
// 36. Reflection keeps this compatible across AGP 8/9 (where the old
// `compileSdkVersion(int)` DSL method was removed in favour of the `compileSdk`
// property).
fun bumpCompileSdk(project: Project) {
    val android = project.extensions.findByName("android") ?: return
    val current = try {
        android.javaClass.getMethod("getCompileSdk").invoke(android) as? Int
    } catch (e: Exception) {
        null
    }
    if (current == null || current < 36) {
        try {
            android.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(android, 36)
        } catch (e: Exception) {
            // Leave the plugin's own compileSdk untouched if the reflective
            // setter isn't available; the build will surface any issue.
        }
    }

    // Align the plugin's Java compile target with the Kotlin target forced
    // below (17). AGP derives the JavaCompile task target from the android
    // extension's `compileOptions`, so a task-level override alone is undone;
    // set the extension's source/target compatibility reflectively. Some older
    // plugins (e.g. receive_sharing_intent 1.8.x, file_picker) default Java to
    // 11, which then mismatches Kotlin 17 and fails the AGP consistency check.
    try {
        val compileOptions =
            android.javaClass.getMethod("getCompileOptions").invoke(android)
        val v17 = JavaVersion.VERSION_17
        compileOptions.javaClass.methods
            .firstOrNull {
                it.name == "setSourceCompatibility" &&
                    it.parameterTypes.firstOrNull() == JavaVersion::class.java
            }
            ?.invoke(compileOptions, v17)
        compileOptions.javaClass.methods
            .firstOrNull {
                it.name == "setTargetCompatibility" &&
                    it.parameterTypes.firstOrNull() == JavaVersion::class.java
            }
            ?.invoke(compileOptions, v17)
    } catch (e: Exception) {
        // Non-fatal: fall back to the task-level Java target set below.
    }
}

subprojects {
    // Register the compileSdk bump before evaluationDependsOn forces `:app`
    // (and its dependents) to evaluate. Projects that are already evaluated by
    // the time this block reaches them are configured directly.
    if (project.state.executed) {
        bumpCompileSdk(project)
    } else {
        afterEvaluate { bumpCompileSdk(project) }
    }
    project.evaluationDependsOn(":app")
}

// Third-party plugin modules still compile their Java against version 8, which
// the JDK reports as "obsolete". The app module is already on 17; this forces
// every subproject's Java compilation to 17 too, silencing those warnings.
// (Java 17 compiles 8-level source fine, so this is safe.)
subprojects {
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

// Some third-party plugins (e.g. receive_sharing_intent 1.8.x, posthog_flutter)
// ship an older Gradle config whose Kotlin compile task ends up on a different
// JVM target than the Java one, which AGP 9 / Kotlin 2.x rejects with
// "Inconsistent JVM Target Compatibility". Pin every subproject's Kotlin
// compilation to 17 to match the Java target set above.
//
// This MUST run in `afterEvaluate`: plugins like posthog_flutter register their
// own `KotlinCompile.configureEach { jvmTarget = JVM_1_8 }` inside their build
// script, and `configureEach` callbacks win in registration order. Registering
// ours after the subproject has been evaluated guarantees it runs last (and
// therefore wins) over the plugin's 1.8 setting.
subprojects {
    // Applied late (after the subproject's own build script) so it wins over a
    // plugin's own `KotlinCompile.configureEach { jvmTarget = JVM_1_8 }`.
    // `evaluationDependsOn(":app")` above may have already evaluated some
    // subprojects, and afterEvaluate throws on those — so apply directly when
    // already evaluated, otherwise defer to afterEvaluate.
    if (project.state.executed) {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    } else {
        afterEvaluate {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
