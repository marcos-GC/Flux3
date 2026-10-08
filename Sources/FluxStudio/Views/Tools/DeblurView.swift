import FluxCore
import SwiftUI

/// Barra inferior de Deblur.
struct DeblurBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: DeblurModel
    @ObservedObject private var runner: ToolRunner

    init(model: DeblurModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        ToolBarContainer {
            HStack(spacing: 8) {
                Text("Quita el desenfoque de la imagen seleccionada. No necesita prompt.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                ToolSettingsChip(model: model)
                ToolGenerateControls(runner: runner, enabled: model.input != nil) { model.generate(state: state) }
            }
        }
    }
}
