import FluxCore
import SwiftUI

/// Deblur: soltar imagen → resultado con comparador antes/después.
struct DeblurView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: DeblurModel
    @ObservedObject private var runner: ToolRunner

    init(model: DeblurModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Deblur", subtitle: "Quita el desenfoque y recupera nitidez.") {
                if model.input != nil {
                    Button("Cambiar imagen") { model.reset() }
                }
            }
            Group {
                if let input = model.input {
                    if runner.current != nil {
                        ToolResultView(runner: runner, before: input.image) { model.useCurrentResultAsInput() }
                    } else {
                        FittedImage(image: input.image)
                    }
                } else if model.isLoading {
                    ProgressView()
                } else {
                    ToolDropZone(title: "Subir imagen") { model.load($0) }
                        .frame(maxWidth: 560, maxHeight: 320)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            if let error = model.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger).padding(.bottom, 6)
            }
            if model.input != nil {
                ToolBarContainer {
                    HStack(spacing: 8) {
                        Text("Se envía la imagen tal cual; no necesita prompt.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        ToolSettingsChip(model: model)
                        ToolGenerateControls(runner: runner, enabled: true) { model.generate(state: state) }
                    }
                }
            }
        }
        .onAppear(perform: takeHandoff)
        .onChange(of: state.handoff) { takeHandoff() }
    }

    private func takeHandoff() {
        guard let handoff = state.handoff, handoff.mode == .deblur else { return }
        model.load(handoff.fileURL)
        state.handoff = nil
    }
}
