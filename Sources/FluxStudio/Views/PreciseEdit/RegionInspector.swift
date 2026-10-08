import AppKit
import FluxCore
import SwiftUI

/// Tarjeta "REGIÓN N" junto a la región seleccionada.
struct RegionInspector: View {
    @EnvironmentObject private var model: PreciseEditModel
    let region: RegionDraft
    @FocusState private var focused: Bool

    private var number: Int { model.number(of: region.id) }

    private var placeholder: String {
        switch region.kind {
        case .edit: return "¿Qué debe cambiar aquí?"
        case .new: return "¿Qué debe aparecer aquí?"
        case .move: return "Detalle opcional (p. ej. «gírala hacia la ventana»)"
        case .anchor: return "Nota opcional"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.regionColor(number - 1, kind: region.kind))
                    .frame(width: 10, height: 10)
                SectionLabel("Región \(number)")
                Spacer()
                Button { model.selectedRegionID = nil } label: {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Hecho")
                Button { model.removeRegion(region.id) } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.danger)
                .help("Borrar región (⌫)")
            }

            Picker("Tipo", selection: Binding(
                get: { region.kind },
                set: { model.setKind($0, for: region.id) }
            )) {
                ForEach(RegionKind.allCases, id: \.self) { Text($0.spanishName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Editar: cambia lo de dentro · Nuevo: crea algo · Mover: lleva un elemento a otra caja · Ancla: no cambiar")

            if region.kind == .anchor {
                Text("Esta zona se mantendrá exactamente igual.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                TextField(placeholder, text: Binding(
                    get: { region.instruction },
                    set: { text in model.update(region.id) { $0.instruction = text } }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($focused)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .onSubmit { model.selectedRegionID = nil }
            }

            if region.kind == .move {
                Text("Arrastra la caja de puntos finos («\(number)→») hasta donde debe ir el elemento.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if region.kind != .anchor {
                referenceRow
            }

            if model.isTooSmall(region) {
                Label("Caja muy pequeña: los elementos de unos 40×25 px suelen fallar.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .surfaceStyle(cornerRadius: 14)
        .onAppear { if region.instruction.isEmpty && region.kind != .anchor { focused = true } }
    }

    @ViewBuilder
    private var referenceRow: some View {
        if let reference = region.reference {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.placeholder)
                    if let thumb = reference.thumbnail {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    }
                    if reference.isProcessing { ProgressView().controlSize(.mini) }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Referencia de esta región").font(.system(size: 11, weight: .medium))
                    Text(reference.error ?? reference.url.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(reference.error == nil ? Theme.textSecondary : Theme.danger)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Quitar") { model.update(region.id) { $0.reference = nil } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
            }
        } else {
            Button {
                if let url = chooseImages(allowsMultiple: false).first {
                    model.setRegionReference(url, for: region.id)
                }
            } label: {
                Label("Añadir imagen de referencia", systemImage: "photo.badge.plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
        }
    }
}
