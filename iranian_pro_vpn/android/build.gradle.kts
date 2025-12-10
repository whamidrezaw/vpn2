tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory.get().asFile)  // fix: deprecated buildDir → layout.buildDirectory
}