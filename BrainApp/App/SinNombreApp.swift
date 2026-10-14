import SwiftUI

/// Entry point. The project has no name yet: "SinNombre" ("Unnamed") is a placeholder.
@main
struct SinNombreApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
