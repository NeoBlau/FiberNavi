import SwiftUI
import CoreLocation

/// Поиск адреса или места, избранное и история.
struct SearchView: View {
    @Environment(PlacesStore.self) private var places
    @Environment(\.dismiss) private var dismiss
    let near: CLLocationCoordinate2D?
    let onSelect: (Place) -> Void

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var error: String?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    quickSection
                    if !places.favorites.isEmpty {
                        Section("Избранное") { ForEach(places.favorites) { row($0) } }
                    }
                    if !places.history.isEmpty {
                        Section {
                            ForEach(places.history) { row($0) }
                        } header: {
                            HStack {
                                Text("Недавние")
                                Spacer()
                                Button("Очистить") { places.clearHistory() }.font(.caption)
                            }
                        }
                    }
                } else {
                    if let error {
                        Text(error).foregroundStyle(.secondary)
                    } else if results.isEmpty, !isSearching {
                        Text("Ничего не найдено").foregroundStyle(.secondary)
                    }
                    ForEach(results) { row($0) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Адрес или место")
            .task(id: query) { await search() }
            .navigationTitle("Куда едем")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var quickSection: some View {
        Section {
            quick("Дом", symbol: "house.fill", place: places.home)
            quick("Работа", symbol: "briefcase.fill", place: places.work)
        } footer: {
            Text("Чтобы задать дом или работу, найди адрес и удержи строку.")
        }
    }

    private func quick(_ title: String, symbol: String, place: Place?) -> some View {
        Button {
            if let place { choose(place) }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(place?.name ?? "Не задан").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
        .disabled(place == nil)
    }

    private func row(_ place: Place) -> some View {
        Button {
            choose(place)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button("Сделать домом", systemImage: "house") { places.setHome(place) }
            Button("Сделать работой", systemImage: "briefcase") { places.setWork(place) }
            Button(places.isFavorite(place) ? "Убрать из избранного" : "В избранное", systemImage: "star") {
                places.toggleFavorite(place)
            }
        }
    }

    private func choose(_ place: Place) {
        places.remember(place)
        onSelect(place)
        dismiss()
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            error = nil
            return
        }
        guard let url = AppConfig.current.searchURL else {
            error = "Не задан адрес сервера поиска (Настройки → Сервер)."
            return
        }
        // Дебаунс: новый ввод отменяет задачу.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await PhotonClient(baseURL: url).search(text, near: near)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Выбор маршрута из альтернатив, режим передвижения, старт и симуляция.
struct RoutePreviewPanel: View {
    @Bindable var session: NavigationSession
    let tokens: ThemeTokens
    let onStart: () -> Void
    let onSimulate: () -> Void
    let onReplan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing) {
            HStack {
                Text(session.destination?.name ?? "Маршрут")
                    .font(.headline)
                    .foregroundStyle(tokens.palette.panelText)
                    .lineLimit(1)
                Spacer()
                Button {
                    session.cancelPreview()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .tint(tokens.palette.secondaryText)
                .accessibilityLabel("Отменить")
            }
            Picker("Способ", selection: $session.mode) {
                Label("Авто", systemImage: "car.fill").tag(TravelMode.auto)
                Label("Пешком", systemImage: "figure.walk").tag(TravelMode.pedestrian)
                Label("Вело", systemImage: "bicycle").tag(TravelMode.bicycle)
            }
            .pickerStyle(.segmented)
            .onChange(of: session.mode) { onReplan() }

            ForEach(Array(session.routes.enumerated()), id: \.element.id) { index, route in
                Button {
                    session.selectedRouteIndex = index
                } label: {
                    HStack {
                        Text(Format.duration(route.duration)).font(.title3.bold())
                        Text(Format.distance(route.distance)).foregroundStyle(tokens.palette.secondaryText)
                        Spacer()
                        if index == 0 { Text("быстрее").font(.caption).foregroundStyle(tokens.palette.accent) }
                    }
                    .foregroundStyle(tokens.palette.panelText)
                    .padding(10)
                    .background(index == session.selectedRouteIndex ? tokens.palette.accent.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button(action: onStart) {
                    Label("Поехали", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tokens.palette.accent)
                Button(action: onSimulate) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Симуляция поездки")
            }
            .controlSize(.large)
        }
        .padding(tokens.spacing)
        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
    }
}
