plugins {
    kotlin("multiplatform") version "2.4.21"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21"
    id("org.jetbrains.compose") version "1.12.2"
}
kotlin {
    iosSimulatorArm64 { binaries.framework { baseName = "ComposeFix"; isStatic = true } }
    sourceSets {
        iosMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
        }
    }
}
