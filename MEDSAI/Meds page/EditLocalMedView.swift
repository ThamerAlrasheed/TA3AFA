import SwiftUI

struct EditLocalMedView: View {
    var med: LocalMed
    var onSave: (LocalMed) -> Void

    var body: some View {
        AddLocalMedView(editingMed: med, onSave: onSave)
    }
}
