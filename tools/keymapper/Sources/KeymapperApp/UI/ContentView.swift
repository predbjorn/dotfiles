import SwiftUI
import Keymapper

struct ContentView: View {
    @ObservedObject var vm: KeymapperViewModel

    var body: some View {
        VStack {
            Text("Keymapper — loading…")
                .font(.headline)
                .padding()
        }
        .frame(width: 820, height: 620)
    }
}
