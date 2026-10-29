import SwiftUI

// Container app: setup guide and a test field. Free Apple ID teams get no App Group,
// so there is nothing to configure here.
@main
struct ProtlyApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

struct SetupView: View {
    @State private var test = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Text("1. Settings > General > Keyboard > Keyboards > Add New Keyboard > Protly")
                    Text("2. Tap Protly and turn on Allow Full Access")
                    Text("3. Keep the Emoji keyboard")
                }
                Section("Test") {
                    TextField("Type here", text: $test, axis: .vertical)
                }
            }
            .navigationTitle("Protly")
        }
    }
}
