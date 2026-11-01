import AppKit
import FluxCore
import SwiftUI
import UniformTypeIdentifiers

/// Panel lateral del Asistente de prompts (chat con Claude).
struct AssistantPanel: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: AssistantStore
    @State private var dropTargeted = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            messages
            Rectangle().fill(Theme.border).frame(height: 1)
            composer
        }
        .background(Theme.surface)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.region, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Theme.region.opacity(0.08))
                    .overlay(Text("Suelta para añadir al mensaje").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.region))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadURL(provider) { urls.append(url) }
                }
                store.attach(urls)
            }
            return true
        }
        .onAppear { store.loadRecent() }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 13))
            Text("Asistente")
                .font(.system(size: 13, weight: .semibold))
            Menu {
                ForEach(PromptAssistant.Model.allCases) { model in
                    Button {
                        store.model = model
                    } label: {
                        if store.model == model {
                            Label("\(model.displayName) · \(model.detail)", systemImage: "checkmark")
                        } else {
                            Text("\(model.displayName) · \(model.detail)")
                        }
                    }
                }
            } label: {
                Text(store.model.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.border.opacity(0.6)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Modelo de Claude: Sonnet para el día a día, Opus para los casos difíciles")
            Spacer()
            ToolIconButton(icon: "square.and.pencil", help: "Conversación nueva") { store.newConversation() }
                .disabled(store.conversation.turns.isEmpty && store.pending.isEmpty)
            Menu {
                if store.recent.isEmpty {
                    Text("Aún no hay conversaciones guardadas")
                } else {
                    Section("Conversaciones recientes") {
                        ForEach(store.recent) { summary in
                            Button("\(summary.title) · \(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))") {
                                store.open(summary)
                            }
                        }
                    }
                }
                Divider()
                Button("Notas propias para la guía de FLUX…") { store.revealFolder() }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Conversaciones guardadas y notas propias para la guía")
            ToolIconButton(icon: "xmark", help: "Cerrar el asistente (⌘L)") { store.isOpen = false }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 44)
    }

    // MARK: Mensajes

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.conversation.turns.isEmpty {
                        intro
                    }
                    ForEach(store.conversation.turns) { turn in
                        TurnView(turn: turn, store: store)
                            .id(turn.id)
                    }
                    if store.isSending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("\(store.model.displayName) está mirando las imágenes y pensando…")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button("Cancelar") { store.cancel() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.danger)
                        }
                        .id("sending")
                    }
                    if let error = store.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.danger)
                                .textSelection(.enabled)
                            if store.conversation.turns.last?.role == .user && !store.isSending {
                                Button("Reintentar") { store.retry() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .underline()
                            }
                        }
                        .id("error")
                    }
                }
                .padding(12)
            }
            .onChange(of: store.conversation.turns.count) {
                if let last = store.conversation.turns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                }
            }
            .onChange(of: store.isSending) {
                if store.isSending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analiza imágenes y escribe prompts de FLUX 3 contigo, con la guía de FLUX en la cabeza. Los prompts que proponga llevan botones para usarlos en Editar o Generar.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Añade imágenes (la que tienes en grande, arrastrándolas desde la tira o el Finder) y elige su papel: imagen a transformar, referencia de estilo…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(AssistantStore.QuickAction.allCases) { action in
                Button {
                    store.apply(action)
                    if store.pending.isEmpty, let url = state.focusedURL, !VideoModel.isVideo(url) {
                        store.attach([url], role: .target)
                    }
                    composerFocused = true
                } label: {
                    Chip(icon: action.icon, text: action.title)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Escribir

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.pending) { attachment in
                            PendingAttachmentChip(attachment: attachment, store: store)
                        }
                    }
                }
            }
            TextField("Qué quieres conseguir… (↩ envía, ⌥↩ salto de línea)", text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...8)
                .focused($composerFocused)
                .onSubmit { send() }
            HStack(spacing: 4) {
                if let url = state.focusedURL, !VideoModel.isVideo(url) {
                    Button {
                        store.attach([url])
                    } label: {
                        Chip(icon: "photo.badge.plus", text: "Imagen en grande")
                    }
                    .buttonStyle(.plain)
                    .help("Añadir al mensaje la imagen que tienes en grande (por ejemplo, el resultado de un prompt para que lo revise)")
                }
                ToolIconButton(icon: "paperclip", help: "Añadir imágenes desde el disco") { store.attach(chooseImages()) }
                Spacer()
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.action.opacity(store.canSend ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!store.canSend)
                .help("Enviar (↩)")
            }
        }
        .padding(10)
    }

    private func send() {
        store.send(focusedURL: state.focusedURL)
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url)
                case let data as Data: continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Un mensaje

private struct TurnView: View {
    let turn: PromptAssistant.Turn
    @ObservedObject var store: AssistantStore

    var body: some View {
        switch turn.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if !turn.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(turn.attachments) { AttachmentThumb(attachment: $0) }
                    }
                }
                if !turn.text.isEmpty {
                    Text(turn.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.border.opacity(0.55)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 30)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(PromptAssistant.segments(turn.text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(Self.markdown(text))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    case .prompt(let suggestion):
                        PromptCard(suggestion: suggestion, store: store)
                    }
                }
                if let model = turn.model {
                    Text(model.contains("opus") ? "Opus" : (model.contains("sonnet") ? "Sonnet" : model))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Un prompt propuesto, con botones para usarlo.
private struct PromptCard: View {
    @EnvironmentObject private var state: AppState
    let suggestion: PromptAssistant.Suggestion
    @ObservedObject var store: AssistantStore
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(suggestion.target == .edit ? "EDICIÓN" : "IMAGEN NUEVA")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.region)
                ForEach(Array(suggestion.images.enumerated()), id: \.offset) { index, number in
                    Text("image \(index + 1) = #\(number)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Text([suggestion.aspectRatio, suggestion.resolution].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(suggestion.prompt)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if !suggestion.images.isEmpty {
                    Button { store.use(suggestion, as: .edit, state: state) } label: {
                        Chip(icon: "pencil.and.outline", text: "Usar en Editar", isActive: suggestion.target == .edit)
                    }
                    .buttonStyle(.plain)
                    .help("Abre la imagen \(suggestion.images.first.map { "#\($0)" } ?? "") en Editar con este prompt (y las demás como referencias)")
                }
                Button { store.use(suggestion, as: .generate, state: state) } label: {
                    Chip(icon: "sparkles", text: "Usar en Generar", isActive: suggestion.target == .generate)
                }
                .buttonStyle(.plain)
                .help("Pone el prompt en Generar con sus imágenes como referencias, en orden")
                Spacer(minLength: 0)
                ToolIconButton(icon: copied ? "checkmark" : "doc.on.doc", help: "Copiar el prompt") {
                    store.copy(suggestion)
                    copied = true
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.region.opacity(0.35)))
    }
}

// MARK: - Imágenes

private struct AttachmentThumb: View {
    let attachment: PromptAssistant.Attachment
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Theme.placeholder
                if let image { Image(nsImage: image).resizable().scaledToFill() }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("#\(attachment.number)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(3)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: attachment.role.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(Theme.region))
                .padding(3)
        }
        .help("#\(attachment.number) · \(attachment.role.spanishName) · \(attachment.fileURL.lastPathComponent)")
        .task(id: attachment.path) {
            image = await ThumbnailLoader.load(attachment.fileURL, maxPixelSize: 160)
        }
    }
}

/// Imagen del mensaje que se está escribiendo: su papel se cambia desde el menú.
private struct PendingAttachmentChip: View {
    let attachment: PromptAssistant.Attachment
    @ObservedObject var store: AssistantStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AttachmentThumb(attachment: attachment)
                .overlay(alignment: .topTrailing) {
                    Button { store.removePending(attachment.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white, Color.black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help("Quitar")
                }
            Menu {
                ForEach(PromptAssistant.ImageRole.allCases) { role in
                    Button(role.spanishName) { store.setRole(role, for: attachment.id) }
                }
            } label: {
                Text(attachment.role.spanishName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 56)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Papel de esta imagen")
        }
        .padding(.top, 4)
    }
}
