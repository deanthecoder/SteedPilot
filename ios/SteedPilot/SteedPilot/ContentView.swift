// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var sender = BluetoothNavSender()
    @StateObject private var locationProvider = LocationProvider()
    @State private var routeActive = false
    @State private var destination = "Princes Risborough"
    @State private var searchText = ""
    @State private var selectedTarget: MapTarget?
    @State private var searchMessage: String?
    @State private var isSearching = false
    @State private var isAddingRouteTarget = false
    @State private var cameraPosition = MapCameraPosition.region(SampleRoute.region)
    @State private var panelState = RoutePanelState.medium
    @State private var waypointEditMode = EditMode.inactive
    @State private var showDeveloperTools = false
    @State private var pendingLocationRecenter = false
    @State private var waypoints: [RouteWaypoint] = []
    @State private var routeLegs: [RouteLeg] = []
    @State private var isCalculatingRoute = false
    @State private var routeCalculationTask: Task<Void, Never>?
    @State private var showingSaveRouteDialog = false
    @State private var showingRouteLibrary = false
    @State private var showingSettings = false
    @State private var saveRouteName = ""
    @State private var savedRoutes: [SavedRoute] = []
    @AppStorage("SteedPilot.distanceUnitPreference") private var distanceUnitPreferenceRaw = DistanceUnitPreference.miles.rawValue
    @AppStorage("SteedPilot.avoidMotorways") private var avoidMotorways = false
    @AppStorage("SteedPilot.mapStyle") private var selectedMapStyleRaw = MapStyleOption.standard.rawValue
    @FocusState private var searchFocused: Bool

    private let fixtures = NavFixtures.loadFixtures()
    private let replayRoute = NavFixtures.loadReplayRoute()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                routeMap
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    routeHeader
                        .padding(.horizontal, 12)

                    mapControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 10)
                        .padding(.trailing, 14)

                    Spacer(minLength: 0)
                }

                routeBuilderSheet(screenHeight: geometry.size.height, bottomInset: geometry.safeAreaInsets.bottom)
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .onReceive(locationProvider.$currentCoordinate.compactMap { $0 }) { coordinate in
                guard pendingLocationRecenter else {
                    return
                }

                centerMap(on: coordinate, span: SampleRoute.localSpan)
                pendingLocationRecenter = false
            }
            .onChange(of: waypoints.map(\.id)) { _, _ in
                recalculateRoute()
            }
            .onChange(of: avoidMotorways) { _, _ in
                recalculateRoute()
            }
            .onAppear(perform: loadSavedRoutes)
            .alert("Save route", isPresented: $showingSaveRouteDialog) {
                TextField("Route name", text: $saveRouteName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)

                Button("Cancel", role: .cancel) {}
                Button("Save", action: savePlannedRoute)
                    .disabled(saveRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Name this route so it can be found in your library later.")
            }
            .sheet(isPresented: $showingRouteLibrary) {
                routeLibrarySheet
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
        }
    }

    private var routeMap: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(routeLegs) { leg in
                    MapPolyline(leg.polyline)
                        .stroke(routeLineColor, style: StrokeStyle(lineWidth: routeLineWidth, lineCap: .round, lineJoin: .round))
                }

                if let selectedTarget {
                    Annotation(selectedTarget.name, coordinate: selectedTarget.coordinate) {
                        Button(action: clearSelectedTarget) {
                            TargetPin()
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(visibleMapWaypoints) { waypoint in
                    Annotation(waypoint.name, coordinate: waypoint.coordinate) {
                        Button {
                            reuseWaypointAsRouteEnd(waypoint)
                        } label: {
                            WaypointPin(waypoint: waypoint)
                        }
                        .buttonStyle(.plain)
                        .disabled(waypoint.id == waypoints.last?.id)
                    }
                }
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .mapControls {
                MapCompass()
            }
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else {
                    return
                }

                selectedTarget = MapTarget(name: "Dropped pin", coordinate: coordinate)
                searchMessage = nil
            }
        }
    }

    private var routeHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RouteStat(icon: "point.topleft.down.curvedto.point.bottomright.up", value: routeDistanceText, label: "Distance")
                RouteStat(icon: "clock", value: routeTravelTimeText, label: "Ride time")
            }
            .padding(.vertical, 9)
        }
        .buttonStyle(IconButtonStyle())
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var selectedMapStyle: MapStyleOption {
        get {
            MapStyleOption(rawValue: selectedMapStyleRaw) ?? .standard
        }
        nonmutating set {
            selectedMapStyleRaw = newValue.rawValue
        }
    }

    private var distanceUnitPreference: DistanceUnitPreference {
        get {
            DistanceUnitPreference(rawValue: distanceUnitPreferenceRaw) ?? .miles
        }
        nonmutating set {
            distanceUnitPreferenceRaw = newValue.rawValue
        }
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            Button(action: {}) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .accessibilityLabel("SteedPilot \(sender.status)")
            }
            .buttonStyle(ConnectionMapButtonStyle(color: connectionColor))

            Button(action: recenterMap) {
                Image(systemName: "location.fill")
            }
            .buttonStyle(FloatingMapButtonStyle())

            Button(action: showSettings) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(FloatingMapButtonStyle())
        }
    }

    private func routeBuilderSheet(screenHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Button(action: togglePanel) {
                VStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.36))
                        .frame(width: 52, height: 6)

                    if panelState == .collapsed {
                        Text(routeSheetTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: panelState == .collapsed ? 58 : 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, panelState == .collapsed ? 8 : 10)
            .padding(.bottom, panelState == .collapsed ? max(bottomInset, 12) : 8)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        updatePanel(after: value.translation.height)
                    }
            )

            if panelState != .collapsed {
                VStack(spacing: 12) {
                    placeSearchRow
                    selectedTargetRow
                    routeBuilderActions
                    waypointEditList
                }
                .padding(.horizontal, 14)
                .padding(.bottom, bottomInset + 14)
                .frame(maxHeight: routeBuilderHeight(for: screenHeight))
            }
        }
        .foregroundStyle(.white)
        .background(
            Color(red: 0.045, green: 0.050, blue: 0.060).opacity(0.96),
            in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.36), radius: 18, y: -6)
        .animation(.snappy(duration: 0.22), value: panelState)
        .ignoresSafeArea(edges: .bottom)
    }

    private var placeSearchRow: some View {
        HStack(spacing: 8) {
            Button(action: showRouteLibrary) {
                Image(systemName: "books.vertical")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel("Route library")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search for a place", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .onSubmit(searchForPlace)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: searchForPlace) {
                    Image(systemName: "arrow.forward.circle.fill")
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .font(.subheadline)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedTargetRow: some View {
        if let selectedTarget {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTarget.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(waypoints.isEmpty ? "Ready to add as start" : "Ready to add as waypoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: addSelectedTargetToRoute) {
                    if isAddingRouteTarget {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add to route")
                    }
                }
                .disabled(isAddingRouteTarget)

                Button(action: clearSelectedTarget) {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .buttonStyle(SecondaryRouteButtonStyle())
        } else if let searchMessage {
            Text(searchMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var routeBuilderActions: some View {
        if !waypoints.isEmpty {
            HStack {
                Button(action: showSaveRouteDialog) {
                    Label("Save route", systemImage: "square.and.arrow.down")
                }
                .disabled(waypoints.count < 2 || isCalculatingRoute)

                Spacer()

                Button(role: .destructive, action: clearPlannedRoute) {
                    Label("Clear route", systemImage: "trash")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(SecondaryRouteButtonStyle())
        }
    }

    private var waypointEditList: some View {
        VStack(spacing: 8) {
            if waypointEditMode.isEditing {
                HStack {
                    Label("Reorder waypoints", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Done", action: finishWaypointReorder)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 4)
            }

            List {
                if waypoints.isEmpty {
                    Text("Search or tap the map to choose a start point.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(waypoints) { waypoint in
                        RouteWaypointListRow(waypoint: waypoint, legDistanceText: legDistanceText(to: waypoint))
                            .listRowBackground(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                centerMap(on: waypoint.coordinate, span: SampleRoute.localSpan)
                            }
                            .onLongPressGesture(perform: beginWaypointReorder)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteRouteWaypoint(id: waypoint.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onMove(perform: moveRouteWaypoints)
                }
            }
            .environment(\.editMode, $waypointEditMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(minHeight: 92)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var routeLibrarySheet: some View {
        NavigationStack {
            List {
                if savedRoutes.isEmpty {
                    ContentUnavailableView(
                        "No Saved Routes",
                        systemImage: "books.vertical",
                        description: Text("Saved rides will appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(savedRoutes) { route in
                        Button {
                            restoreSavedRoute(route)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .foregroundStyle(.cyan)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text(savedRouteSummaryText(route))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.uturn.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.white.opacity(0.04))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSavedRoute(id: route.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Route Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingRouteLibrary = false
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.050, blue: 0.060))
        }
        .preferredColorScheme(.dark)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: distanceUnitPreferenceBinding) {
                        ForEach(DistanceUnitPreference.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Route") {
                    Toggle("Avoid motorways", isOn: $avoidMotorways)
                }

                Section("Map") {
                    Picker("Style", selection: selectedMapStyleBinding) {
                        ForEach(MapStyleOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingSettings = false
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.050, blue: 0.060))
        }
        .preferredColorScheme(.dark)
    }

    private var distanceUnitPreferenceBinding: Binding<DistanceUnitPreference> {
        Binding {
            distanceUnitPreference
        } set: { unit in
            distanceUnitPreference = unit
        }
    }

    private var selectedMapStyleBinding: Binding<MapStyleOption> {
        Binding {
            selectedMapStyle
        } set: { style in
            selectedMapStyle = style
        }
    }

    private func routeEditor(maxHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            Button(action: togglePanel) {
                VStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 52, height: 6)

                    if panelState == .collapsed {
                        Text("Route")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: panelState == .collapsed ? 70 : 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, panelState == .collapsed ? 6 : 10)
            .padding(.bottom, panelState == .collapsed ? max(bottomInset, 14) : 0)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        updatePanel(after: value.translation.height)
                    }
            )

            if panelState != .collapsed {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        routeControls
                        waypointList
                        routeTools
                        developerDisclosure
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, bottomInset + 14)
                }
                .frame(maxHeight: maxHeight)
            }
        }
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var routeControls: some View {
        HStack(spacing: 10) {
            TextField("Destination", text: $destination)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: routeActive ? endRoute : startRoute) {
                Text(routeActive ? "End" : "Start")
            }
            .buttonStyle(PrimaryRouteButtonStyle(active: routeActive))
            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var waypointList: some View {
        VStack(spacing: 0) {
            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, waypoint in
                WaypointRow(
                    waypoint: waypoint,
                    canMoveUp: index > 1,
                    canMoveDown: index < waypoints.count - 2,
                    canDelete: waypoint.kind == .stop,
                    moveUp: { moveWaypoint(at: index, by: -1) },
                    moveDown: { moveWaypoint(at: index, by: 1) },
                    delete: { deleteWaypoint(at: index) }
                )

                if waypoint.id != waypoints.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.leading, 44)
                }
            }
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var routeTools: some View {
        HStack(spacing: 10) {
            Button(action: addWaypoint) {
                Label("Add Waypoint", systemImage: "plus.circle")
            }

            Spacer()

            Button(action: reverseRoute) {
                Label("Reverse", systemImage: "arrow.up.arrow.down")
            }

            Button(role: .destructive, action: clearWaypoints) {
                Label("Clear", systemImage: "trash")
            }
        }
        .buttonStyle(SecondaryRouteButtonStyle())
        .padding(.vertical, 2)
    }

    private var developerDisclosure: some View {
        DisclosureGroup(isExpanded: $showDeveloperTools) {
            developerTools
                .padding(.top, 10)
        } label: {
            Label("Developer fixtures", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
        }
        .tint(.cyan)
    }

    private var developerTools: some View {
        VStack(spacing: 10) {
            if let replayRoute {
                Button(sender.isReplaying ? "Stop Replay" : "Replay Demo Route") {
                    if sender.isReplaying {
                        sender.cancelReplay()
                    } else {
                        sender.replay(replayRoute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(fixtures) { fixture in
                    Button(fixture.title) {
                        sender.send(fixture.data)
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionColor: Color {
        sender.status == "Connected" || sender.status == "Sent" ? .green : .red
    }

    private var routeLineColor: Color {
        switch selectedMapStyle {
            case .standard:
                return .blue
            case .satellite, .hybrid:
                return .cyan
        }
    }

    private var routeLineWidth: CGFloat {
        switch selectedMapStyle {
            case .standard:
                return 7
            case .satellite, .hybrid:
                return 5
        }
    }

    private var visibleMapWaypoints: [RouteWaypoint] {
        var visible: [RouteWaypoint] = []
        for waypoint in waypoints {
            guard !visible.contains(where: { $0.coordinate.isVisuallySame(as: waypoint.coordinate) }) else {
                continue
            }

            visible.append(waypoint)
        }

        return visible
    }

    private var routeSheetTitle: String {
        if waypoints.isEmpty {
            return "Add route start"
        }

        return "\(waypoints.count) route point\(waypoints.count == 1 ? "" : "s")"
    }

    private var routeDistanceText: String {
        if isCalculatingRoute {
            return "..."
        }

        return formatDistance(routeLegs.reduce(0) { $0 + $1.distance })
    }

    private var routeTravelTimeText: String {
        if isCalculatingRoute {
            return "..."
        }

        let seconds = routeLegs.reduce(0) { $0 + $1.expectedTravelTime }
        guard seconds > 0 else {
            return "-"
        }

        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    private func legDistanceText(to waypoint: RouteWaypoint) -> String? {
        guard waypoint.kind != .start else {
            return nil
        }

        if isCalculatingRoute {
            return "..."
        }

        guard let leg = routeLegs.first(where: { $0.toWaypointID == waypoint.id }) else {
            return nil
        }

        return "+\(formatDistance(leg.distance))"
    }

    private func savedRouteSummaryText(_ route: SavedRoute) -> String {
        let pointText = "\(route.points.count) route point\(route.points.count == 1 ? "" : "s")"
        let distance = route.distanceMeters ?? estimatedRouteDistance(for: route.points.map(\.coordinate))

        guard distance > 0 else {
            return pointText
        }

        return "\(pointText) - \(formatDistance(distance))"
    }

    private func estimatedRouteDistance(for coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count > 1 else {
            return 0
        }

        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + start.distance(from: end)
        }
    }

    private func routeBuilderHeight(for screenHeight: CGFloat) -> CGFloat {
        switch panelState {
            case .collapsed:
                return 0
            case .medium:
                return min(330, screenHeight * 0.38)
            case .expanded:
                return min(610, screenHeight * 0.70)
        }
    }

    private func panelHeight(for screenHeight: CGFloat) -> CGFloat {
        switch panelState {
            case .collapsed:
                return 0
            case .medium:
                return min(330, screenHeight * 0.42)
            case .expanded:
                return min(590, screenHeight * 0.72)
        }
    }

    private func togglePanel() {
        withAnimation(.snappy(duration: 0.22)) {
            switch panelState {
                case .collapsed:
                    panelState = .medium
                case .medium:
                    panelState = .collapsed
                case .expanded:
                    panelState = .medium
            }
        }
    }

    private func updatePanel(after verticalDrag: CGFloat) {
        withAnimation(.snappy(duration: 0.22)) {
            if verticalDrag > 35 {
                panelState = panelState == .expanded ? .medium : .collapsed
            } else if verticalDrag < -35 {
                panelState = panelState == .collapsed ? .medium : .expanded
            }
        }
    }

    private func startRoute() {
        if let payload = NavFixtures.loadStubRouteStart() {
            sender.send(payload)
            routeActive = true
            panelState = .collapsed
        }
    }

    private func endRoute() {
        sender.send(NavFixtures.clearRoute)
        routeActive = false
        panelState = .medium
    }

    private func recenterMap() {
        if let coordinate = locationProvider.currentCoordinate {
            centerMap(on: coordinate, span: SampleRoute.localSpan)
            return
        }

        pendingLocationRecenter = true
        locationProvider.requestCurrentLocation()
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
    }

    private func fitMap(to routePoints: [RouteWaypoint]) {
        guard let firstPoint = routePoints.first else {
            return
        }

        guard routePoints.count > 1 else {
            centerMap(on: firstPoint.coordinate, span: SampleRoute.localSpan)
            return
        }

        let pointRects = routePoints.map { waypoint in
            MKMapRect(
                origin: MKMapPoint(waypoint.coordinate),
                size: MKMapSize(width: 1, height: 1)
            )
        }

        let routeRect = pointRects.dropFirst().reduce(pointRects[0]) { partialResult, pointRect in
            partialResult.union(pointRect)
        }

        let padding = max(routeRect.width, routeRect.height) * 0.22
        cameraPosition = .rect(routeRect.insetBy(dx: -padding, dy: -padding))
    }

    private func zoomIn() {
        updateZoom(scale: 0.65)
    }

    private func zoomOut() {
        updateZoom(scale: 1.45)
    }

    private func updateZoom(scale: CLLocationDegrees) {
        guard let region = cameraPosition.region else {
            cameraPosition = .region(SampleRoute.region)
            return
        }

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.015, min(2.0, region.span.latitudeDelta * scale)),
            longitudeDelta: max(0.015, min(2.0, region.span.longitudeDelta * scale))
        )
        cameraPosition = .region(MKCoordinateRegion(center: region.center, span: span))
    }

    private func searchForPlace() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else {
            return
        }

        isSearching = true
        searchMessage = nil
        searchFocused = false

        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let region = cameraPosition.region {
                request.region = region
            }

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard let mapItem = response.mapItems.first else {
                    await MainActor.run {
                        isSearching = false
                        selectedTarget = nil
                        searchMessage = "No places found for \"\(query)\"."
                    }
                    return
                }

                let coordinate = mapItem.placemark.coordinate
                await MainActor.run {
                    isSearching = false
                    selectedTarget = MapTarget(name: mapItem.name ?? query, coordinate: coordinate)
                    centerMap(on: coordinate, span: SampleRoute.localSpan)
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    selectedTarget = nil
                    searchMessage = "Search failed. Try a more specific place name."
                }
            }
        }
    }

    private func addSelectedTargetToRoute() {
        guard let selectedTarget, !isAddingRouteTarget else {
            return
        }

        isAddingRouteTarget = true

        Task {
            let snappedTarget = await snappedRouteTarget(from: selectedTarget)
            await MainActor.run {
                let kind: WaypointKind = waypoints.isEmpty ? .start : .stop
                let waypoint = RouteWaypoint(kind: kind, number: nil, name: snappedTarget.name, coordinate: snappedTarget.coordinate)
                waypoints.append(waypoint)
                normalizeRouteWaypoints()
                self.selectedTarget = nil
                searchText = ""
                searchMessage = nil
                isAddingRouteTarget = false
            }
        }
    }

    private func snappedRouteTarget(from target: MapTarget) async -> MapTarget {
        do {
            let location = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
            guard let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first else {
                return target
            }

            let snappedCoordinate = placemark.location?.coordinate ?? target.coordinate
            return MapTarget(name: routeTargetName(from: placemark, fallback: target.name), coordinate: snappedCoordinate)
        } catch {
            return target
        }
    }

    private func routeTargetName(from placemark: CLPlacemark, fallback: String) -> String {
        if let name = placemark.thoroughfare, !name.isEmpty {
            return name
        }

        if let name = placemark.name, !name.isEmpty {
            return name
        }

        if let name = placemark.locality, !name.isEmpty {
            return name
        }

        return fallback
    }

    private func reuseWaypointAsRouteEnd(_ waypoint: RouteWaypoint) {
        guard waypoint.id != waypoints.last?.id else {
            return
        }

        waypoints.append(
            RouteWaypoint(
                kind: .stop,
                number: nil,
                name: waypoint.name,
                coordinate: waypoint.coordinate
            )
        )
        normalizeRouteWaypoints()
    }

    private func recalculateRoute() {
        routeCalculationTask?.cancel()

        guard waypoints.count > 1 else {
            routeLegs = []
            isCalculatingRoute = false
            return
        }

        let routePoints = waypoints
        isCalculatingRoute = true
        routeCalculationTask = Task {
            do {
                let legs = try await calculateRouteLegs(for: routePoints)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    routeLegs = legs
                    isCalculatingRoute = false
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    routeLegs = []
                    isCalculatingRoute = false
                    searchMessage = "Could not calculate a road route for those points."
                }
            }
        }
    }

    private func calculateRouteLegs(for routePoints: [RouteWaypoint]) async throws -> [RouteLeg] {
        var legs: [RouteLeg] = []

        for index in 1..<routePoints.count {
            try Task.checkCancellation()

            let start = routePoints[index - 1]
            let end = routePoints[index]
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
            request.transportType = .automobile
            request.requestsAlternateRoutes = avoidMotorways
            request.highwayPreference = avoidMotorways ? .avoid : .any

            let routes = try await MKDirections(request: request).calculate().routes
            let route = avoidMotorways ? routes.first { !$0.hasHighways } ?? routes.first : routes.first

            guard let route else {
                continue
            }

            legs.append(
                RouteLeg(
                    fromWaypointID: start.id,
                    toWaypointID: end.id,
                    distance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    polyline: route.polyline
                )
            )
        }

        return legs
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        switch distanceUnitPreference {
            case .miles:
                let miles = meters / 1609.344
                if miles < 10 {
                    return String(format: "%.1f mi", miles)
                }

                return String(format: "%.0f mi", miles)
            case .kilometres:
                let kilometres = meters / 1000
                if kilometres < 10 {
                    return String(format: "%.1f km", kilometres)
                }

                return String(format: "%.0f km", kilometres)
        }
    }

    private func clearSelectedTarget() {
        selectedTarget = nil
        searchMessage = nil
    }

    private func clearPlannedRoute() {
        routeCalculationTask?.cancel()
        waypoints = []
        routeLegs = []
        routeActive = false
        selectedTarget = nil
        searchMessage = nil
        finishWaypointReorder()
    }

    private func moveRouteWaypoints(from source: IndexSet, to destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        normalizeRouteWaypoints()
    }

    private func deleteRouteWaypoints(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        normalizeRouteWaypoints()
        if waypoints.isEmpty {
            finishWaypointReorder()
        }
    }

    private func deleteRouteWaypoint(id: UUID) {
        waypoints.removeAll { $0.id == id }
        normalizeRouteWaypoints()
        if waypoints.isEmpty {
            finishWaypointReorder()
        }
    }

    private func beginWaypointReorder() {
        guard waypoints.count > 1 else {
            return
        }

        withAnimation(.snappy(duration: 0.18)) {
            waypointEditMode = .active
        }
    }

    private func finishWaypointReorder() {
        withAnimation(.snappy(duration: 0.18)) {
            waypointEditMode = .inactive
        }
    }

    private func normalizeRouteWaypoints() {
        waypoints = waypoints.enumerated().map { index, waypoint in
            let isStart = index == 0
            let isDestination = waypoints.count > 1 && index == waypoints.count - 1

            return RouteWaypoint(
                id: waypoint.id,
                kind: isStart ? .start : (isDestination ? .destination : .stop),
                number: isStart || isDestination ? nil : index,
                name: waypoint.name,
                coordinate: waypoint.coordinate
            )
        }
    }

    private func addWaypoint() {
        let nextNumber = waypoints.filter { $0.kind == .stop }.count + 1
        let waypoint = RouteWaypoint(kind: .stop, number: nextNumber, name: "New waypoint", coordinate: CLLocationCoordinate2D(latitude: 51.735, longitude: -0.650))
        waypoints.insert(waypoint, at: max(1, waypoints.count - 1))
        renumberWaypoints()
        panelState = .expanded
    }

    private func moveWaypoint(at index: Int, by offset: Int) {
        let target = index + offset
        guard index > 0, target > 0, index < waypoints.count - 1, target < waypoints.count - 1 else {
            return
        }

        let waypoint = waypoints.remove(at: index)
        waypoints.insert(waypoint, at: target)
        renumberWaypoints()
    }

    private func deleteWaypoint(at index: Int) {
        guard waypoints.indices.contains(index), waypoints[index].kind == .stop else {
            return
        }

        waypoints.remove(at: index)
        renumberWaypoints()
    }

    private func reverseRoute() {
        guard waypoints.count > 1 else {
            return
        }

        let reversed = waypoints.reversed().map { waypoint -> RouteWaypoint in
            switch waypoint.kind {
                case .start:
                    return waypoint.with(kind: .destination, number: nil)
                case .destination:
                    return waypoint.with(kind: .start, number: nil)
                case .stop:
                    return waypoint
            }
        }
        waypoints = Array(reversed)
        renumberWaypoints()
    }

    private func clearWaypoints() {
        waypoints = SampleRoute.defaultWaypoints.filter { $0.kind != .stop }
        routeActive = false
        sender.send(NavFixtures.clearRoute)
    }

    private func showSaveRouteDialog() {
        saveRouteName = defaultRouteSaveName
        showingSaveRouteDialog = true
    }

    private func showRouteLibrary() {
        loadSavedRoutes()
        showingRouteLibrary = true
    }

    private func showSettings() {
        showingSettings = true
    }

    private func savePlannedRoute() {
        let trimmedName = saveRouteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, waypoints.count > 1 else {
            return
        }

        let routeDistance = routeLegs.reduce(0) { $0 + $1.distance }
        let savedRoute = SavedRoute(name: trimmedName, waypoints: waypoints, distanceMeters: routeDistance > 0 ? routeDistance : nil)
        savedRoutes.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
        savedRoutes.insert(savedRoute, at: 0)
        persistSavedRoutes()
        saveRouteName = ""
    }

    private func restoreSavedRoute(_ route: SavedRoute) {
        routeCalculationTask?.cancel()
        let restoredWaypoints = route.routeWaypoints
        waypoints = restoredWaypoints
        normalizeRouteWaypoints()
        routeLegs = []
        routeActive = false
        selectedTarget = nil
        searchMessage = nil
        finishWaypointReorder()
        showingRouteLibrary = false
        fitMap(to: restoredWaypoints)
    }

    private func deleteSavedRoute(id: UUID) {
        savedRoutes.removeAll { $0.id == id }
        persistSavedRoutes()
    }

    private func loadSavedRoutes() {
        guard let data = UserDefaults.standard.data(forKey: SavedRoute.storageKey),
              let routes = try? JSONDecoder().decode([SavedRoute].self, from: data) else {
            return
        }

        savedRoutes = routes
    }

    private func persistSavedRoutes() {
        guard let data = try? JSONEncoder().encode(savedRoutes) else {
            return
        }

        UserDefaults.standard.set(data, forKey: SavedRoute.storageKey)
    }

    private var defaultRouteSaveName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Ride \(formatter.string(from: Date()))"
    }

    private func renumberWaypoints() {
        var number = 1
        waypoints = waypoints.map { waypoint in
            guard waypoint.kind == .stop else {
                return waypoint.with(number: nil)
            }

            defer { number += 1 }
            return waypoint.with(number: number)
        }
    }
}

private struct RouteStat: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.cyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct WaypointRow: View {
    let waypoint: RouteWaypoint
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            WaypointBadge(waypoint: waypoint)

            VStack(alignment: .leading, spacing: 2) {
                Text(waypoint.name)
                    .font(.subheadline.weight(.semibold))
                Text(waypoint.kind.title)
                    .font(.caption)
                    .foregroundStyle(waypoint.kind.color)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)

                if canDelete {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct RouteWaypointListRow: View {
    let waypoint: RouteWaypoint
    let legDistanceText: String?

    var body: some View {
        HStack(spacing: 12) {
            WaypointBadge(waypoint: waypoint)

            VStack(alignment: .leading, spacing: 1) {
                Text(waypoint.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(waypoint.kind.title)
                    .font(.caption)
                    .foregroundStyle(waypoint.kind.color)
            }

            Spacer()

            if let legDistanceText {
                Text(legDistanceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WaypointPin: View {
    let waypoint: RouteWaypoint

    var body: some View {
        ZStack {
            Circle()
                .fill(waypoint.kind.color)
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            if let number = waypoint.number {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            } else if waypoint.kind == .destination {
                CheckeredFlagIcon(size: 18)
            } else {
                Image(systemName: "location.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct TargetPin: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .cyan)

            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .offset(x: 7, y: -7)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

private struct WaypointBadge: View {
    let waypoint: RouteWaypoint

    var body: some View {
        ZStack {
            Circle()
                .fill(waypoint.kind.color)
                .frame(width: 24, height: 24)

            if let number = waypoint.number {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
            } else if waypoint.kind == .destination {
                CheckeredFlagIcon(size: 13)
            } else {
                Text("A")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(.white)
    }
}

private struct CheckeredFlagIcon: View {
    let size: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.08) {
            Capsule()
                .fill(Color.white)
                .frame(width: max(1, size * 0.10), height: size * 0.92)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(Color.white)

                ForEach(0..<2, id: \.self) { row in
                    ForEach(0..<3, id: \.self) { column in
                        if (row + column).isMultiple(of: 2) {
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: size * 0.20, height: size * 0.18)
                                .offset(x: CGFloat(column) * size * 0.20, y: CGFloat(row) * size * 0.18)
                        }
                    }
                }
            }
            .frame(width: size * 0.60, height: size * 0.36)
        }
        .frame(width: size, height: size)
    }
}

private struct MapTarget {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

private struct RouteWaypoint: Identifiable {
    let id: UUID
    let kind: WaypointKind
    let number: Int?
    let name: String
    let coordinate: CLLocationCoordinate2D

    init(id: UUID = UUID(), kind: WaypointKind, number: Int?, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.kind = kind
        self.number = number
        self.name = name
        self.coordinate = coordinate
    }

    func with(kind: WaypointKind? = nil, number: Int? = nil) -> RouteWaypoint {
        RouteWaypoint(id: id, kind: kind ?? self.kind, number: number, name: name, coordinate: coordinate)
    }
}

private struct SavedRoute: Codable, Identifiable {
    static let storageKey = "SteedPilot.savedRoutes"

    let id: UUID
    let name: String
    let savedAt: Date
    let points: [SavedRoutePoint]
    let distanceMeters: CLLocationDistance?

    init(id: UUID = UUID(), name: String, savedAt: Date = Date(), points: [SavedRoutePoint], distanceMeters: CLLocationDistance?) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.points = points
        self.distanceMeters = distanceMeters
    }

    init(name: String, waypoints: [RouteWaypoint], distanceMeters: CLLocationDistance?) {
        self.init(name: name, points: waypoints.map(SavedRoutePoint.init), distanceMeters: distanceMeters)
    }

    var routeWaypoints: [RouteWaypoint] {
        points.map { point in
            RouteWaypoint(kind: .stop, number: nil, name: point.name, coordinate: point.coordinate)
        }
    }
}

private struct SavedRoutePoint: Codable {
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(name: String, latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(waypoint: RouteWaypoint) {
        self.init(name: waypoint.name, latitude: waypoint.coordinate.latitude, longitude: waypoint.coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct RouteLeg: Identifiable {
    let id = UUID()
    let fromWaypointID: UUID
    let toWaypointID: UUID
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let polyline: MKPolyline
}

private enum DistanceUnitPreference: String, CaseIterable, Identifiable {
    case miles
    case kilometres

    var id: String { rawValue }

    var title: String {
        switch self {
            case .miles: return "Miles"
            case .kilometres: return "Kilometres"
        }
    }
}

private enum RoutePanelState {
    case collapsed
    case medium
    case expanded
}

private enum WaypointKind {
    case start
    case stop
    case destination

    var title: String {
        switch self {
            case .start: return "Start"
            case .stop: return "Waypoint"
            case .destination: return "Destination"
        }
    }

    var color: Color {
        switch self {
            case .start: return .green
            case .stop: return .purple
            case .destination: return .cyan
        }
    }
}

private extension CLLocationCoordinate2D {
    func isVisuallySame(as other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 0.00001 && abs(longitude - other.longitude) < 0.00001
    }
}

private enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
            case .standard: return "Standard"
            case .satellite: return "Satellite"
            case .hybrid: return "Hybrid"
        }
    }

    var mapStyle: MapStyle {
        switch self {
            case .standard: return .standard(elevation: .realistic)
            case .satellite: return .imagery(elevation: .realistic)
            case .hybrid: return .hybrid(elevation: .realistic)
        }
    }

}

private enum SampleRoute {
    static let defaultWaypoints = [
        RouteWaypoint(kind: .start, number: nil, name: "Route start", coordinate: CLLocationCoordinate2D(latitude: 51.8200, longitude: -0.6600)),
        RouteWaypoint(kind: .stop, number: 1, name: "Wendover", coordinate: CLLocationCoordinate2D(latitude: 51.7617, longitude: -0.7420)),
        RouteWaypoint(kind: .stop, number: 2, name: "Little Gaddesden", coordinate: CLLocationCoordinate2D(latitude: 51.8080, longitude: -0.5600)),
        RouteWaypoint(kind: .stop, number: 3, name: "Great Missenden", coordinate: CLLocationCoordinate2D(latitude: 51.7030, longitude: -0.7070)),
        RouteWaypoint(kind: .stop, number: 4, name: "Amersham", coordinate: CLLocationCoordinate2D(latitude: 51.6670, longitude: -0.6160)),
        RouteWaypoint(kind: .destination, number: nil, name: "Princes Risborough", coordinate: CLLocationCoordinate2D(latitude: 51.7250, longitude: -0.8300))
    ]

    static let alternateCoordinates = [
        CLLocationCoordinate2D(latitude: 51.8200, longitude: -0.6600),
        CLLocationCoordinate2D(latitude: 51.7900, longitude: -0.6150),
        CLLocationCoordinate2D(latitude: 51.7450, longitude: -0.6500),
        CLLocationCoordinate2D(latitude: 51.7250, longitude: -0.8300)
    ]

    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.744, longitude: -0.686),
        span: MKCoordinateSpan(latitudeDelta: 0.23, longitudeDelta: 0.34)
    )

    static let localSpan = MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
}

private final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                break
            @unknown default:
                break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }

        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct FloatingMapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.black.opacity(configuration.isPressed ? 0.72 : 0.58), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

private struct ConnectionMapButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 46, height: 46)
            .background(Color.black.opacity(configuration.isPressed ? 0.72 : 0.58), in: Circle())
            .overlay(Circle().stroke(color.opacity(0.50), lineWidth: 1.5))
    }
}

private struct PrimaryRouteButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(active ? Color.red.opacity(0.82) : Color.cyan.opacity(configuration.isPressed ? 0.65 : 0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SecondaryRouteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.role == .destructive ? .red : .cyan)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
