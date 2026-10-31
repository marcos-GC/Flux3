import AppKit
import FluxCore
import SwiftUI

/// «Prompts guardados»: prompts con sus parámetros, título y explicación, para volver a ellos.
struct PromptLibraryView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var library: PromptLibrary
    @State private var search = ""
    @State private var toDelete: PromptRecipe?

    private var filtered: [PromptRecipe] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return library.recipes }
        return library.recipes.filter {
            $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) || $0.prompt.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if library.recipes.isEmpty {
                empty
            } else if filtered.isEmpty {
                Text("Ningún prompt coincide con la búsqueda.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { recipe in
                            RecipeCard(recipe: recipe, thumbnail: library.thumbnailURL(recipe),
                                       onUse: { state.apply(recipe) },
                                       onEdit: { state.recipeDraft = RecipeDraft(recipe: recipe, image: nil, isNew: false) },
                                       onCopy: { state.copiedRecipe = recipe; copyText(recipe.prompt)
                                                 state.notice = "Prompt y parámetros copiados." },
                                       onDelete: { toDelete = recipe })
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear { library.reloadIfNeeded() }
        .confirmationDialog("¿Borrar «\(toDelete?.title ?? "")»?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        )) {
            Button("Borrar", role: .destructive) {
                if let toDelete { library.delete(toDelete) }
                toDelete = nil
            }
            Button("Cancelar", role: .cancel) { toDelete = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Prompts guardados")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(filtered.count)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Buscar por título, explicación o texto", text: $search)
                    .textFieldStyle(.plain)
                    .frame(width: 240)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .surfaceStyle(cornerRadius: 18)
            Button {
                state.recipeDraft = RecipeDraft(
                    recipe: PromptRecipe(title: "", prompt: "", tool: WorkspaceTool.generate.title,
                                         endpoint: BFLEndpoint.flux3Image.path),
                    image: nil, isNew: true)
            } label: {
                Chip(icon: "plus", text: "Nuevo")
            }
            .buttonStyle(.plain)
            .help("Escribir un prompt nuevo para guardarlo")
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 18)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical").font(.system(size: 30, weight: .light))
            Text("Todavía no has guardado ningún prompt")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Cuando algo te salga bien, haz clic derecho en la foto → «Guardar en Prompts guardados…», o usa el botón de libros junto a la caja del prompt. Podrás ponerle título y una explicación.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: 440, maxHeight: .infinity)
    }
}

private struct RecipeCard: View {
    let recipe: PromptRecipe
    let thumbnail: URL?
    let onUse: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if thumbnail != nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.placeholder)
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title.isEmpty ? "Sin título" : recipe.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if !recipe.notes.isEmpty {
                        Text(recipe.notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                    }
                    Text([recipe.tool, recipe.parameterSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(recipe.prompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.7)))
                .textSelection(.enabled)
                .help(recipe.prompt)
            HStack(spacing: 8) {
                Button(action: onUse) { Chip(icon: "arrow.down.doc", text: "Usar", isActive: true) }
                    .buttonStyle(.plain)
                    .help("Pone el prompt y los parámetros en la herramienta abierta")
                Button(action: onCopy) { Chip(icon: "doc.on.doc", text: "Copiar") }
                    .buttonStyle(.plain)
                Button(action: onEdit) { Chip(icon: "pencil", text: "Editar") }
                    .buttonStyle(.plain)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
                .help("Borrar")
            }
        }
        .padding(14)
        .surfaceStyle(cornerRadius: 14)
        .contextMenu {
            Button("Usar", action: onUse)
            Button("Copiar prompt y parámetros", action: onCopy)
            Button("Editar…", action: onEdit)
            Divider()
            Button("Borrar", role: .destructive, action: onDelete)
        }
        .task(id: recipe.updated) {
            guard let thumbnail else { return }
            image = await Task.detached { NSImage(contentsOf: thumbnail) }.value
        }
    }
}

/// Hoja para guardar o editar un prompt: título, explicación y texto.
struct RecipeEditorSheet: View {
    @EnvironmentObject private var state: AppState
    @State var draft: RecipeDraft
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.isNew ? "Guardar en Prompts guardados" : "Editar prompt")
                .font(.system(size: 16, weight: .semibold))
            field("Título") {
                TextField("Por ejemplo: «Librería de salón, luz de tarde»", text: $draft.recipe.title)
                    .textFieldStyle(.roundedBorder)
            }
            field("Explicación (opcional)") {
                TextEditor(text: $draft.recipe.notes)
                    .font(.system(size: 12))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
            field("Prompt") {
                TextEditor(text: $draft.recipe.prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
            let summary = [draft.recipe.tool, draft.recipe.parameterSummary].filter { !$0.isEmpty }.joined(separator: " · ")
            if !summary.isEmpty {
                Label("Parámetros: \(summary)", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Spacer()
                Button("Cancelar", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    var recipe = draft.recipe
                    recipe.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if recipe.title.isEmpty { recipe.title = PromptRecipe.defaultTitle(for: recipe.prompt) }
                    state.library.save(recipe, image: draft.image)
                    state.notice = "«\(recipe.title)» guardado en Prompts."
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.recipe.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title)
            content()
        }
    }
}

/// Menú de libros junto a la caja del prompt: guardar lo escrito, pegar lo copiado o usar uno guardado.
struct PromptLibraryMenu: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var library: PromptLibrary

    var body: some View {
        Menu {
            Button("Guardar este prompt…") { state.saveCurrentRecipe() }
            if let copied = state.copiedRecipe {
                Button("Pegar prompt y parámetros copiados (⌥⌘V)") { state.apply(copied) }
            }
            if !library.recipes.isEmpty {
                Divider()
                ForEach(library.recipes.prefix(15)) { recipe in
                    Button(recipe.title.isEmpty ? recipe.prompt : recipe.title) { state.apply(recipe) }
                }
            }
            Divider()
            Button("Ver todos los prompts guardados") { state.mode = .library }
        } label: {
            Image(systemName: "books.vertical")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 28)
                .background(Capsule().fill(Color.white.opacity(0.7)))
                .overlay(Capsule().strokeBorder(Theme.border))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Prompts guardados: guardar el que has escrito o usar uno guardado")
        .onAppear { library.reloadIfNeeded() }
    }
}
