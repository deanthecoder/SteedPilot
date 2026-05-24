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
import Foundation
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sender = BluetoothNavSender()
    @StateObject private var locationProvider = LocationProvider()
    @StateObject private var keyboard = KeyboardObserver()
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
    @State private var selectedRideMode = RideMode.directions
    @State private var smoothedDestinationBearing: Double?
    @State private var debugRideDistanceMeters: CLLocationDistance?
    @State private var waypoints: [RouteWaypoint] = []
    @State private var routeLegs: [RouteLeg] = []
    @State private var isCalculatingRoute = false
    @State private var routeCalculationTask: Task<Void, Never>?
    @State private var showingSaveRouteDialog = false
    @State private var showingRouteLibrary = false
    @State private var showingSettings = false
    @State private var showingMapKitDebug = false
    @State private var searchEditorPresented = false
    @State private var navigationDebugLog: [String] = []
    @State private var saveRouteName = ""
    @State private var savedRoutes: [SavedRoute] = []
    @State private var homeLocation: SavedRoutePoint?
    @State private var homeSearchText = ""
    @State private var homeMessage: String?
    @State private var isSearchingHome = false
    @AppStorage("SteedPilot.distanceUnitPreference") private var distanceUnitPreferenceRaw = DistanceUnitPreference.miles.rawValue
    @AppStorage("SteedPilot.avoidMotorways") private var avoidMotorways = false
    @AppStorage("SteedPilot.mapStyle") private var selectedMapStyleRaw = MapStyleOption.standard.rawValue
    @AppStorage("SteedPilot.speedWarningLimitMph") private var speedWarningLimitMph = 65
    @AppStorage("SteedPilot.showRideTestControls") private var showRideTestControls = false
    @FocusState private var searchFocused: Bool

    private let fixtures = NavFixtures.loadFixtures()
    private let navigationDebugLogFileName = "SteedPilotNavigation.log"
    private let replayRoute = NavFixtures.loadReplayRoute()
    private let rideUpdateTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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

                if routeActive {
                    rideStatusOverlay(screenHeight: geometry.size.height, bottomInset: geometry.safeAreaInsets.bottom)
                }

                if searchEditorPresented {
                    searchEditorOverlay(topInset: geometry.safeAreaInsets.top)
                }
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
            .onChange(of: speedWarningLimitMph) { _, _ in
                sendRideUpdate()
            }
            .onReceive(rideUpdateTimer) { _ in
                sendRideUpdate()
            }
            .onChange(of: sender.isConnected) { _, isConnected in
                guard isConnected else {
                    return
                }

                pingDevice()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    return
                }

                pingDevice()
            }
            .onChange(of: routeActive) { _, isActive in
                UIApplication.shared.isIdleTimerDisabled = isActive
            }
            .onChange(of: searchFocused) { _, isFocused in
                if !isFocused {
                    searchEditorPresented = false
                }
            }
            .onAppear(perform: configureView)
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .sheet(isPresented: $showingRouteLibrary) {
                routeLibrarySheet
            }
            .sheet(isPresented: $showingSaveRouteDialog) {
                saveRouteSheet
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
            .sheet(isPresented: $showingMapKitDebug) {
                MapKitDebugSheet(
                    legs: routeLegs,
                    snapshot: rideNavigationSnapshot(),
                    navigationDebugLog: navigationDebugLog,
                    clearNavigationDebugLog: clearNavigationDebugLog,
                    distanceFormatter: formatDistance,
                    travelTimeFormatter: formatTravelTime
                )
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

                if let debugMapCoordinate {
                    Annotation("Test position", coordinate: debugMapCoordinate) {
                        DebugRidePositionPin()
                    }
                }

                if let rideMapCoordinate {
                    Annotation("Current position", coordinate: rideMapCoordinate) {
                        RidePositionPin()
                    }
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
        .foregroundStyle(.white)
        .background(Color(red: 0.045, green: 0.050, blue: 0.060).opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
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
        }
    }

    private func routeBuilderSheet(screenHeight: CGFloat, bottomInset: CGFloat) -> some View {
        let keyboardLift = searchFocused ? max(0, keyboard.height - bottomInset) : 0
        let contentHeight = routeBuilderHeight(for: screenHeight, keyboardLift: keyboardLift)

        return VStack(spacing: 0) {
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
                .frame(height: panelState == .collapsed ? 58 : 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, panelState == .collapsed ? 8 : 6)
            .padding(.bottom, panelState == .collapsed ? max(bottomInset, 12) : 0)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        updatePanel(after: value.translation.height)
                    }
            )

            if panelState != .collapsed {
                Divider()
                    .overlay(Color.white.opacity(0.10))

                VStack(spacing: 12) {
                    placeSearchRow
                    homeQuickStartRow
                    selectedTargetRow
                    routeBuilderActions
                    waypointEditList
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, bottomInset + 14)
                .frame(height: contentHeight)
                .clipped()
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
        .padding(.bottom, keyboardLift)
        .animation(.snappy(duration: 0.22), value: panelState)
        .animation(.snappy(duration: 0.22), value: keyboardLift)
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

                Button(action: showSearchEditor) {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search for a place" : searchText)
                        .foregroundStyle(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Search for a place")

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

            Button(action: showSettings) {
                Image(systemName: "gearshape.fill")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel("Settings")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
    }

    private func searchEditorOverlay(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search for a place", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .onSubmit {
                        searchForPlace()
                        hideSearchEditor()
                    }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    searchForPlace()
                    hideSearchEditor()
                } label: {
                    Image(systemName: "arrow.forward.circle.fill")
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)

                Button(action: hideSearchEditor) {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(Color(red: 0.045, green: 0.050, blue: 0.060).opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.36), radius: 16, y: 6)
            .padding(.horizontal, 14)
            .padding(.top, topInset + 8)

            Spacer()
        }
        .foregroundStyle(.white)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            searchFocused = true
        }
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
            VStack(spacing: 10) {
                if canStartRide {
                    HStack(spacing: 6) {
                        ForEach(RideMode.allCases) { mode in
                            Button {
                                selectedRideMode = mode
                            } label: {
                                Label(mode.title, systemImage: mode.icon)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RideModeButtonStyle(isSelected: selectedRideMode == mode))
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    Button(action: startRoute) {
                        Label("Start ride", systemImage: "motorcycle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StartRideButtonStyle())
                    .disabled(isCalculatingRoute || routeLegs.isEmpty)
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))

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
    }

    private func rideStatusOverlay(screenHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: selectedRideMode.icon)
                        .font(.headline)
                        .foregroundStyle(.cyan)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedRideMode.activeTitle)
                            .font(.subheadline.weight(.semibold))
                        Text("SteedPilot \(sender.status.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: endRoute) {
                        Text("End")
                    }
                    .buttonStyle(SecondaryRouteButtonStyle())
                }

                if showRideTestControls {
                    debugRideControls
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.045, green: 0.050, blue: 0.060).opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
            .padding(.horizontal, 14)
            .padding(.bottom, routeBuilderVisibleHeight(for: screenHeight, bottomInset: bottomInset) + 10)
        }
    }

    private var debugRideControls: some View {
        let totalDistance = totalRouteDistance
        let activeDistance = debugRideDistanceMeters ?? 0

        return VStack(spacing: 8) {
            HStack {
                Label("Test ride", systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(debugRideDistanceMeters.map { "\(formatDistance($0)) / \(formatDistance(totalDistance))" } ?? "Live GPS")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: showMapKitDebug) {
                    Label("MapKit", systemImage: "map")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)
                .disabled(routeLegs.isEmpty)
            }

            HStack(spacing: 8) {
                Button(action: resetDebugRideProgress) {
                    Image(systemName: "location")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Use live GPS")

                Button {
                    stepDebugRide(by: -50)
                } label: {
                    Image(systemName: "minus")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Step back")

                Button {
                    stepDebugRide(by: 50)
                } label: {
                    Text("+50 m")
                        .frame(maxWidth: .infinity)
                }

                Button(action: jumpDebugRideToNextInstruction) {
                    Image(systemName: "forward.end")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Jump to next instruction")
            }
            .buttonStyle(DebugRideButtonStyle())
            .disabled(totalDistance <= 0)

            ProgressView(value: totalDistance > 0 ? activeDistance / totalDistance : 0)
                .tint(.cyan)
        }
    }

    private var debugMapCoordinate: CLLocationCoordinate2D? {
        guard let debugRideDistanceMeters else {
            return nil
        }

        return simulatedRouteProgress(at: debugRideDistanceMeters)?.coordinate
    }

    private var rideMapCoordinate: CLLocationCoordinate2D? {
        guard routeActive, debugRideDistanceMeters == nil else {
            return nil
        }

        return locationProvider.currentCoordinate
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
            .frame(minHeight: 92, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxHeight: .infinity)
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
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
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

                Section("Home") {
                    HStack {
                        TextField(homeLocation?.name ?? "Search home location", text: $homeSearchText)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)

                        Button {
                            setHomeFromSearch()
                        } label: {
                            Image(systemName: "arrow.forward.circle.fill")
                        }
                        .disabled(homeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingHome)
                        .accessibilityLabel("Set home")

                        if homeLocation != nil {
                            Button(role: .destructive, action: clearHomeLocation) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Clear home")
                        }
                    }

                    Button("Set from current location") {
                        setHomeFromCurrentLocation()
                    }

                    if isSearchingHome {
                        ProgressView()
                    } else if let homeMessage {
                        Text(homeMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Speed warning") {
                    Stepper(value: $speedWarningLimitMph, in: 20...100, step: 5) {
                        HStack {
                            Text("Warn above")
                            Spacer()
                            Text("\(speedWarningLimitMph) mph")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Map") {
                    Picker("Style", selection: selectedMapStyleBinding) {
                        ForEach(MapStyleOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Testing") {
                    Toggle("Show ride test controls", isOn: $showRideTestControls)
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

    private var saveRouteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Name this route so it can be found in your library later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SelectAllTextField(text: $saveRouteName, placeholder: "Route name")
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle("Save route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSaveRouteDialog = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: savePlannedRoute)
                        .disabled(saveRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .background(Color(red: 0.045, green: 0.050, blue: 0.060))
        }
        .presentationDetents([.height(190)])
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

    @ViewBuilder
    private var homeQuickStartRow: some View {
        if waypoints.isEmpty, let homeLocation {
            Button(action: addHomeStartToRoute) {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start from home")
                            .font(.subheadline.weight(.semibold))
                        Text(homeLocation.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var connectionColor: Color {
        sender.isConnected ? .green : .red
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

    private var canStartRide: Bool {
        waypoints.count > 1 && !routeActive
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
        return formatTravelTime(seconds)
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

    private func formatTravelTime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else {
            return "N/A"
        }

        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
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
                return canStartRide ? min(430, screenHeight * 0.50) : min(330, screenHeight * 0.38)
            case .expanded:
                return min(610, screenHeight * 0.70)
        }
    }

    private func routeBuilderHeight(for screenHeight: CGFloat, keyboardLift: CGFloat) -> CGFloat {
        let normalHeight = routeBuilderHeight(for: screenHeight)
        guard keyboardLift > 0 else {
            return normalHeight
        }

        let gripAndChromeHeight: CGFloat = 6 + 34 + 1
        let topMargin: CGFloat = 18
        let availableHeight = screenHeight - keyboardLift - gripAndChromeHeight - topMargin
        return max(180, min(normalHeight, availableHeight))
    }

    private func routeBuilderVisibleHeight(for screenHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        switch panelState {
            case .collapsed:
                return 8 + 58 + max(bottomInset, 12)
            case .medium, .expanded:
                return 6 + 34 + 1 + routeBuilderHeight(for: screenHeight)
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
        guard let payload = rideStartPayload() else {
            return
        }

        smoothedDestinationBearing = nil
        debugRideDistanceMeters = nil
        locationProvider.startRideTracking()
        sender.send(payload)
        routeActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        panelState = .collapsed
    }

    private func configureView() {
        loadSavedRoutes()
        loadHomeLocation()
        pingDevice()
    }

    private func endRoute() {
        sender.send(NavFixtures.clearRoute)
        locationProvider.stopRideTracking()
        smoothedDestinationBearing = nil
        debugRideDistanceMeters = nil
        routeActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        panelState = .medium
    }

    private func sendRideUpdate() {
        guard routeActive else {
            return
        }

        locationProvider.requestCurrentLocation()
        guard let payload = rideStartPayload() else {
            return
        }

        sender.send(payload)
    }

    private func pingDevice() {
        if routeActive {
            sendRideUpdate()
        } else {
            sender.send(NavFixtures.heartbeat)
        }
    }

    private var totalRouteDistance: CLLocationDistance {
        routeLegs.reduce(0) { $0 + $1.distance }
    }

    private func stepDebugRide(by meters: CLLocationDistance) {
        let startingDistance = debugRideDistanceMeters ?? 0
        setDebugRideDistance(startingDistance + meters)
    }

    private func jumpDebugRideToNextInstruction() {
        let startingDistance = debugRideDistanceMeters ?? 0
        var totalBeforeLeg: CLLocationDistance = 0

        for leg in routeLegs {
            if let instruction = leg.instructions.first(where: { $0.maneuver.isMeaningfulDirection && totalBeforeLeg + $0.distanceFromLegStart > startingDistance + 20 }) {
                setDebugRideDistance(totalBeforeLeg + instruction.distanceFromLegStart)
                return
            }

            totalBeforeLeg += leg.distance
        }

        setDebugRideDistance(totalRouteDistance)
    }

    private func resetDebugRideProgress() {
        debugRideDistanceMeters = nil
        sendRideUpdate()
    }

    private func setDebugRideDistance(_ distance: CLLocationDistance) {
        debugRideDistanceMeters = max(0, min(totalRouteDistance, distance))
        sendRideUpdate()
    }

    private func nearestCurrentRouteDistance() -> CLLocationDistance? {
        guard let currentCoordinate = locationProvider.currentCoordinate,
              let routeProgress = nearestRouteProgress(to: currentCoordinate) else {
            return nil
        }

        return routeProgress.distanceFromRouteStart
    }

    private func rideStartPayload() -> Data? {
        switch selectedRideMode {
            case .directions:
                return directionsRideStartPayload()
            case .heading:
                return headingRideStartPayload()
        }
    }

    private func directionsRideStartPayload() -> Data? {
        let snapshot = rideNavigationSnapshot()
        appendNavigationDebugLog(snapshot: snapshot, mode: "navigation")

        if snapshot.isOffRoute {
            return makeNavStatePayload([
                "mode": "destination",
                "offRoute": true,
                "distanceToDestinationMeters": snapshot.distanceToDestinationMeters,
                "destinationBearingDegrees": snapshot.destinationBearingDegrees,
                "tripProgressComplete": snapshot.tripProgressComplete
            ])
        }

        var fields: [String: Any] = [
            "mode": "navigation",
            "offRoute": false,
            "maneuver": snapshot.maneuver.rawValue,
            "distanceToManeuverMeters": snapshot.distanceToManeuverMeters,
            "distanceToDestinationMeters": snapshot.distanceToDestinationMeters,
            "maneuverProgressRemaining": snapshot.maneuverProgressRemaining,
            "tripProgressComplete": snapshot.tripProgressComplete
        ]

        if let roundaboutExit = snapshot.roundaboutExit {
            fields["exit"] = roundaboutExit
        }
        if !snapshot.roundaboutExitAngles.isEmpty {
            fields["exitCount"] = snapshot.roundaboutExitAngles.count
            fields["exits"] = snapshot.roundaboutExitAngles.map { angle in
                [
                    "index": angle.index,
                    "angleDegrees": angle.angleDegrees
                ]
            }
        }

        return makeNavStatePayload(fields)
    }

    private func headingRideStartPayload() -> Data? {
        let snapshot = rideNavigationSnapshot()
        appendNavigationDebugLog(snapshot: snapshot, mode: "destination")

        return makeNavStatePayload([
            "mode": "destination",
            "offRoute": snapshot.isOffRoute,
            "distanceToDestinationMeters": snapshot.distanceToDestinationMeters,
            "destinationBearingDegrees": snapshot.destinationBearingDegrees,
            "tripProgressComplete": snapshot.tripProgressComplete
        ])
    }

    private func appendNavigationDebugLog(snapshot: RideNavigationSnapshot, mode: String) {
        let selectedOffset = snapshot.selectedInstructionOffsetMeters.map(formatDebugDistance) ?? "none"
        let entry = [
            Date.now.formatted(date: .omitted, time: .standard),
            "mode=\(mode)",
            "send=\(snapshot.maneuver.debugTitle)",
            "toManeuver=\(formatDebugDistance(CLLocationDistance(snapshot.distanceToManeuverMeters)))",
            "toDest=\(formatDebugDistance(CLLocationDistance(snapshot.distanceToDestinationMeters)))",
            "routeProgress=\(formatDebugDistance(snapshot.routeProgressMeters))",
            "routeGap=\(formatDebugDistance(snapshot.distanceToRouteMeters))",
            "selectedOffset=\(selectedOffset)",
            "selectedEnd=\(snapshot.selectedInstructionEndMeters.map(formatDebugDistance) ?? "none")",
            "selected='\(snapshot.selectedInstructionText)'",
            "decision='\(snapshot.selectionReason)'"
        ].joined(separator: " | ")

        navigationDebugLog.append(entry)
        if navigationDebugLog.count > 80 {
            navigationDebugLog.removeFirst(navigationDebugLog.count - 80)
        }

        writeNavigationDebugLogEntry(entry)
        NSLog("SteedPilotNav %@", entry)
    }

    private func clearNavigationDebugLog() {
        navigationDebugLog.removeAll()
        guard let url = navigationDebugLogURL else {
            return
        }

        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    private var navigationDebugLogURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(navigationDebugLogFileName)
    }

    private func writeNavigationDebugLogEntry(_ entry: String) {
        guard
            let url = navigationDebugLogURL,
            let data = "\(entry)\n".data(using: .utf8)
        else {
            return
        }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private func formatDebugDistance(_ meters: CLLocationDistance) -> String {
        "\(Int(meters.rounded()))m"
    }

    private func rideNavigationSnapshot() -> RideNavigationSnapshot {
        let totalDistance = totalRouteDistance
        let fallbackDistance = Int(totalDistance.rounded())
        let fallbackManeuver = Int((routeLegs.first?.distance ?? CLLocationDistance(fallbackDistance)).rounded())
        let fallbackBearing = fallbackDestinationBearing()

        guard totalDistance > 0 else {
            return RideNavigationSnapshot(
                distanceToDestinationMeters: max(fallbackDistance, 0),
                distanceToManeuverMeters: max(fallbackManeuver, 0),
                destinationBearingDegrees: fallbackBearing,
                tripProgressComplete: 0,
                maneuverProgressRemaining: 100,
                maneuver: .continueAhead,
                roundaboutExit: nil,
                roundaboutExitAngles: [],
                selectedInstructionText: "No route",
                selectedInstructionOffsetMeters: nil,
                selectedInstructionEndMeters: nil,
                routeProgressMeters: 0,
                distanceToRouteMeters: 0,
                isOffRoute: false,
                selectionReason: "No route distance"
            )
        }

        let fallbackInstruction = nextInstructionFallback()
        if let debugRideDistanceMeters,
           let routeProgress = simulatedRouteProgress(at: debugRideDistanceMeters) {
            return rideNavigationSnapshot(totalDistance: totalDistance, routeProgress: routeProgress, currentCoordinate: nil)
        }

        guard let currentCoordinate = locationProvider.currentCoordinate else {
            return RideNavigationSnapshot(
                distanceToDestinationMeters: max(fallbackDistance, 0),
                distanceToManeuverMeters: max(fallbackManeuver, 0),
                destinationBearingDegrees: fallbackBearing,
                tripProgressComplete: 0,
                maneuverProgressRemaining: 100,
                maneuver: fallbackInstruction?.maneuver ?? .continueAhead,
                roundaboutExit: fallbackInstruction?.roundaboutExit,
                roundaboutExitAngles: fallbackInstruction?.roundaboutExitAngles ?? [],
                selectedInstructionText: fallbackInstruction?.rawInstruction ?? "Fallback instruction",
                selectedInstructionOffsetMeters: fallbackInstruction?.distanceFromLegStart,
                selectedInstructionEndMeters: fallbackInstruction.map { $0.distanceFromLegStart + $0.distance },
                routeProgressMeters: 0,
                distanceToRouteMeters: 0,
                isOffRoute: false,
                selectionReason: "No nearby GPS/debug position"
            )
        }

        let routeProgress = nearestRouteProgress(to: currentCoordinate)
        if routeProgress == nil || routeProgress!.distanceToRoute > offRouteThresholdMeters {
            return offRouteSnapshot(
                totalDistance: totalDistance,
                currentCoordinate: currentCoordinate,
                routeProgress: routeProgress,
                reason: routeProgress.map { "Off route: \(formatDebugDistance($0.distanceToRoute)) from route" } ?? "Off route: no route projection"
            )
        }

        return rideNavigationSnapshot(totalDistance: totalDistance, routeProgress: routeProgress!, currentCoordinate: currentCoordinate)
    }

    private func rideNavigationSnapshot(totalDistance: CLLocationDistance, routeProgress: RouteProgress, currentCoordinate: CLLocationCoordinate2D?) -> RideNavigationSnapshot {
        let remainingDistance = max(totalDistance - routeProgress.distanceFromRouteStart, 0)
        let instruction = nextInstruction(after: routeProgress)
        let instructionIsActive = instruction.map {
            routeProgress.distanceFromLegStart >= $0.distanceFromLegStart
                && routeProgress.distanceFromLegStart <= $0.distanceFromLegStart + $0.distance
        } ?? false
        let remainingManeuver = instruction.map { instruction in
            let targetDistance = instructionIsActive ? instruction.distanceFromLegStart + instruction.distance : instruction.distanceFromLegStart
            return max(targetDistance - routeProgress.distanceFromLegStart, 0)
        } ?? max(routeProgress.legDistance - routeProgress.distanceFromLegStart, 0)
        let instructionDistance = instruction?.distance ?? max(routeProgress.legDistance - routeProgress.distanceFromLegStart, 1)
        let tripProgress = totalDistance > 0 ? Int(((routeProgress.distanceFromRouteStart / totalDistance) * 100).rounded()) : 0
        let maneuverProgress = instructionDistance > 0 ? Int(((remainingManeuver / instructionDistance) * 100).rounded()) : 0
        let destinationBearing = currentCoordinate.map {
            relativeDestinationBearing(from: $0, routeProgress: routeProgress)
        } ?? relativeDestinationBearing(routeProgress: routeProgress)
        let isArriving = remainingDistance <= 40 || (instruction?.maneuver == .arrive && remainingManeuver <= 40)
        let continueThresholdMeters: CLLocationDistance = 200
        let shouldContinue = !isArriving && !instructionIsActive && remainingManeuver > continueThresholdMeters
        let maneuver = isArriving ? DeviceManeuver.arrive : (shouldContinue ? .continueAhead : (instruction?.maneuver ?? .continueAhead))
        let selectionReason = isArriving ? "Arriving" : (shouldContinue ? "Synthetic continue: selected instruction is over \(Int(continueThresholdMeters))m away" : "Selected instruction")

        return RideNavigationSnapshot(
            distanceToDestinationMeters: Int(remainingDistance.rounded()),
            distanceToManeuverMeters: Int((isArriving ? remainingDistance : remainingManeuver).rounded()),
            destinationBearingDegrees: destinationBearing,
            tripProgressComplete: max(0, min(100, tripProgress)),
            maneuverProgressRemaining: max(0, min(100, maneuverProgress)),
            maneuver: maneuver,
            roundaboutExit: shouldContinue || isArriving ? nil : instruction?.roundaboutExit,
            roundaboutExitAngles: shouldContinue || isArriving ? [] : (instruction?.roundaboutExitAngles ?? []),
            selectedInstructionText: instruction?.rawInstruction ?? "No remaining instruction",
            selectedInstructionOffsetMeters: instruction?.distanceFromLegStart,
            selectedInstructionEndMeters: instruction.map { $0.distanceFromLegStart + $0.distance },
            routeProgressMeters: routeProgress.distanceFromRouteStart,
            distanceToRouteMeters: routeProgress.distanceToRoute,
            isOffRoute: false,
            selectionReason: selectionReason
        )
    }

    private var offRouteThresholdMeters: CLLocationDistance {
        65
    }

    private func offRouteSnapshot(totalDistance: CLLocationDistance, currentCoordinate: CLLocationCoordinate2D, routeProgress: RouteProgress?, reason: String) -> RideNavigationSnapshot {
        let routeProgressMeters = routeProgress?.distanceFromRouteStart ?? nearestCurrentRouteDistance() ?? 0
        let remainingDistance = distanceToDestination(from: currentCoordinate)
        let tripProgress = totalDistance > 0 ? Int(((routeProgressMeters / totalDistance) * 100).rounded()) : 0
        let destinationBearing = relativeDestinationBearingForOffRoute(from: currentCoordinate, routeProgress: routeProgress)

        return RideNavigationSnapshot(
            distanceToDestinationMeters: Int(max(remainingDistance, 0).rounded()),
            distanceToManeuverMeters: Int(max(remainingDistance, 0).rounded()),
            destinationBearingDegrees: destinationBearing,
            tripProgressComplete: max(0, min(100, tripProgress)),
            maneuverProgressRemaining: -1,
            maneuver: .continueAhead,
            roundaboutExit: nil,
            roundaboutExitAngles: [],
            selectedInstructionText: "Off route",
            selectedInstructionOffsetMeters: nil,
            selectedInstructionEndMeters: nil,
            routeProgressMeters: routeProgressMeters,
            distanceToRouteMeters: routeProgress?.distanceToRoute ?? -1,
            isOffRoute: true,
            selectionReason: reason
        )
    }

    private func simulatedRouteProgress(at distance: CLLocationDistance) -> RouteProgress? {
        var totalBeforeLeg: CLLocationDistance = 0

        for leg in routeLegs {
            let legEnd = totalBeforeLeg + leg.distance
            if distance <= legEnd || leg.id == routeLegs.last?.id {
                let distanceFromLegStart = max(0, min(leg.distance, distance - totalBeforeLeg))
                let sample = leg.polyline.sample(at: leg.distance > 0 ? distanceFromLegStart / leg.distance : 0)
                return RouteProgress(
                    legID: leg.id,
                    distanceToRoute: 0,
                    distanceFromLegStart: distanceFromLegStart,
                    distanceFromRouteStart: totalBeforeLeg + distanceFromLegStart,
                    legDistance: leg.distance,
                    routeBearingDegrees: Double(sample?.bearingDegrees ?? leg.polyline.approximateBearingDegrees ?? 0),
                    coordinate: sample?.coordinate
                )
            }

            totalBeforeLeg = legEnd
        }

        return nil
    }

    private func nearestRouteProgress(to coordinate: CLLocationCoordinate2D) -> RouteProgress? {
        var totalBeforeLeg: CLLocationDistance = 0
        var nearestProgress: RouteProgress?

        for leg in routeLegs {
            guard let legProgress = leg.polyline.progressNearest(to: coordinate) else {
                totalBeforeLeg += leg.distance
                continue
            }

            let distanceFraction = legProgress.polylineLength > 0 ? legProgress.distanceFromStart / legProgress.polylineLength : 0
            let distanceFromLegStart = max(0, min(leg.distance, leg.distance * distanceFraction))
            let routeProgress = RouteProgress(
                legID: leg.id,
                distanceToRoute: legProgress.distanceToRoute,
                distanceFromLegStart: distanceFromLegStart,
                distanceFromRouteStart: totalBeforeLeg + distanceFromLegStart,
                legDistance: leg.distance,
                routeBearingDegrees: legProgress.routeBearingDegrees,
                coordinate: legProgress.coordinate
            )

            if nearestProgress == nil || routeProgress.distanceToRoute < nearestProgress!.distanceToRoute {
                nearestProgress = routeProgress
            }

            totalBeforeLeg += leg.distance
        }

        return nearestProgress
    }

    private func nextInstruction(after routeProgress: RouteProgress) -> RouteInstruction? {
        guard let leg = routeLegs.first(where: { $0.id == routeProgress.legID }) else {
            return nil
        }

        let lookbehindMeters: CLLocationDistance = 15
        if let activeInstruction = leg.instructions.last(where: {
            $0.maneuver.isMeaningfulDirection && $0.distanceFromLegStart <= routeProgress.distanceFromLegStart + lookbehindMeters
        }) {
            let activeInstructionEnd = activeInstruction.distanceFromLegStart + activeInstruction.distance
            if routeProgress.distanceFromLegStart <= activeInstructionEnd + lookbehindMeters {
                return activeInstruction
            }
        }

        if let instruction = leg.instructions.first(where: { $0.maneuver.isMeaningfulDirection && $0.distanceFromLegStart >= routeProgress.distanceFromLegStart - lookbehindMeters }) {
            return instruction
        }

        let nextLegStart = routeLegs.drop(while: { $0.id != routeProgress.legID }).dropFirst().first
        return nextLegStart?.instructions.first { $0.maneuver.isMeaningfulDirection }
    }

    private func nextInstructionFallback() -> RouteInstruction? {
        routeLegs.lazy.flatMap(\.instructions).first { $0.maneuver.isMeaningfulDirection }
    }

    private func fallbackDestinationBearing() -> Int {
        guard let start = waypoints.first?.coordinate,
              let destination = waypoints.last?.coordinate else {
            return 0
        }

        return start.bearingDegrees(to: destination)
    }

    private func destinationBearing(from coordinate: CLLocationCoordinate2D) -> Int {
        guard let destination = waypoints.last?.coordinate else {
            return fallbackDestinationBearing()
        }

        return coordinate.bearingDegrees(to: destination)
    }

    private func distanceToDestination(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let destination = waypoints.last?.coordinate else {
            return totalRouteDistance
        }

        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    private func relativeDestinationBearingForOffRoute(from coordinate: CLLocationCoordinate2D, routeProgress: RouteProgress?) -> Int {
        let destinationBearing = Double(destinationBearing(from: coordinate))
        let riderBearing = locationProvider.currentCourseDegrees ?? routeProgress?.routeBearingDegrees ?? destinationBearing
        let relativeBearing = normalizedBearing(destinationBearing - riderBearing)
        let smoothedBearing = smoothedBearing(from: smoothedDestinationBearing, to: relativeBearing, alpha: 0.35)
        smoothedDestinationBearing = smoothedBearing

        return Int(smoothedBearing.rounded()) % 360
    }

    private func relativeDestinationBearing(from coordinate: CLLocationCoordinate2D, routeProgress: RouteProgress) -> Int {
        let destinationBearing = Double(destinationBearing(from: coordinate))
        let riderBearing = locationProvider.currentCourseDegrees ?? routeProgress.routeBearingDegrees
        let relativeBearing = normalizedBearing(destinationBearing - riderBearing)
        let smoothedBearing = smoothedBearing(from: smoothedDestinationBearing, to: relativeBearing, alpha: 0.35)
        smoothedDestinationBearing = smoothedBearing

        return Int(smoothedBearing.rounded()) % 360
    }

    private func relativeDestinationBearing(routeProgress: RouteProgress) -> Int {
        guard let coordinate = routeProgress.coordinate else {
            return fallbackDestinationBearing()
        }

        let destinationBearing = Double(destinationBearing(from: coordinate))
        let relativeBearing = normalizedBearing(destinationBearing - routeProgress.routeBearingDegrees)
        let smoothedBearing = smoothedBearing(from: smoothedDestinationBearing, to: relativeBearing, alpha: 0.35)
        smoothedDestinationBearing = smoothedBearing

        return Int(smoothedBearing.rounded()) % 360
    }

    private func normalizedBearing(_ degrees: Double) -> Double {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private func smoothedBearing(from previous: Double?, to next: Double, alpha: Double) -> Double {
        guard let previous else {
            return normalizedBearing(next)
        }

        let delta = ((next - previous + 540).truncatingRemainder(dividingBy: 360)) - 180
        return normalizedBearing(previous + (delta * alpha))
    }

    private func makeNavStatePayload(_ fields: [String: Any]) -> Data? {
        var payload: [String: Any] = [
            "v": 1,
            "type": "state",
            "link": "connected",
            "speed": speedWarningPayload
        ]

        fields.forEach { key, value in
            payload[key] = value
        }

        return try? JSONSerialization.data(withJSONObject: payload)
    }

    private var speedWarningPayload: [String: Any] {
        [
            "current": currentSpeedMph,
            "limit": speedWarningLimitMph,
            "unit": "mph"
        ]
    }

    private var currentSpeedMph: Int {
        guard let speedMetersPerSecond = locationProvider.currentSpeedMetersPerSecond,
              speedMetersPerSecond > 0 else {
            return 0
        }

        return Int((speedMetersPerSecond * 2.2369362921).rounded())
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

    private func showSearchEditor() {
        withAnimation(.snappy(duration: 0.22)) {
            searchEditorPresented = true
            panelState = .medium
        }

        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func hideSearchEditor() {
        searchFocused = false
        withAnimation(.snappy(duration: 0.22)) {
            searchEditorPresented = false
        }
    }

    private func addHomeStartToRoute() {
        guard waypoints.isEmpty, let homeLocation else {
            return
        }

        waypoints.append(RouteWaypoint(kind: .start, number: nil, name: homeLocation.name, coordinate: homeLocation.coordinate))
        normalizeRouteWaypoints()
        centerMap(on: homeLocation.coordinate, span: SampleRoute.localSpan)
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
                    polyline: route.polyline,
                    steps: route.steps,
                    isFinalLeg: index == routePoints.count - 1
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

    private func showMapKitDebug() {
        showingMapKitDebug = true
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
        guard waypoints.count > 1 else {
            return
        }

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

    private func setHomeFromSearch() {
        let query = homeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearchingHome else {
            return
        }

        isSearchingHome = true
        homeMessage = nil

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
                        isSearchingHome = false
                        homeMessage = "No places found for \"\(query)\"."
                    }
                    return
                }

                let point = SavedRoutePoint(
                    name: mapItem.name ?? query,
                    latitude: mapItem.placemark.coordinate.latitude,
                    longitude: mapItem.placemark.coordinate.longitude
                )
                await MainActor.run {
                    saveHomeLocation(point)
                    homeSearchText = ""
                    homeMessage = nil
                    isSearchingHome = false
                }
            } catch {
                await MainActor.run {
                    isSearchingHome = false
                    homeMessage = "Home search failed. Try a more specific place name."
                }
            }
        }
    }

    private func setHomeFromCurrentLocation() {
        guard let coordinate = locationProvider.currentCoordinate else {
            pendingLocationRecenter = true
            locationProvider.requestCurrentLocation()
            homeMessage = "Waiting for current location."
            return
        }

        isSearchingHome = true
        homeMessage = nil

        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let name = (try? await CLGeocoder().reverseGeocodeLocation(location).first?.name) ?? "Current Location"
            await MainActor.run {
                saveHomeLocation(SavedRoutePoint(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude))
                homeMessage = nil
                isSearchingHome = false
            }
        }
    }

    private func clearHomeLocation() {
        homeLocation = nil
        homeMessage = nil
        UserDefaults.standard.removeObject(forKey: SavedRoutePoint.homeStorageKey)
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

    private func loadHomeLocation() {
        guard let data = UserDefaults.standard.data(forKey: SavedRoutePoint.homeStorageKey),
              let point = try? JSONDecoder().decode(SavedRoutePoint.self, from: data) else {
            return
        }

        homeLocation = point
    }

    private func saveHomeLocation(_ point: SavedRoutePoint) {
        homeLocation = point
        guard let data = try? JSONEncoder().encode(point) else {
            return
        }

        UserDefaults.standard.set(data, forKey: SavedRoutePoint.homeStorageKey)
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

private struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.text = text
        textField.textColor = .white
        textField.tintColor = .systemCyan
        textField.returnKeyType = .done
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)

        DispatchQueue.main.async {
            textField.becomeFirstResponder()
            textField.selectAll(nil)
        }

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
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

private struct DebugRidePositionPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.72))
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.cyan, lineWidth: 2))

            Image(systemName: "speedometer")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
        }
        .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
    }
}

private struct RidePositionPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.24))
                .frame(width: 34, height: 34)

            Circle()
                .fill(Color.cyan)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
        }
        .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
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
    static let homeStorageKey = "SteedPilot.homeLocation"

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

private struct MapKitDebugSheet: View {
    let legs: [RouteLeg]
    let snapshot: RideNavigationSnapshot
    let navigationDebugLog: [String]
    let clearNavigationDebugLog: () -> Void
    let distanceFormatter: (CLLocationDistance) -> String
    let travelTimeFormatter: (TimeInterval) -> String

    var body: some View {
        NavigationStack {
            List {
                Section("Route") {
                    DebugValueRow(label: "Legs", value: "\(legs.count)")
                    DebugValueRow(label: "Distance", value: distanceFormatter(legs.reduce(0) { $0 + $1.distance }))
                    DebugValueRow(label: "Ride time", value: travelTimeFormatter(legs.reduce(0) { $0 + $1.expectedTravelTime }))
                    DebugValueRow(label: "Instructions", value: "\(legs.reduce(0) { $0 + $1.instructions.count })")
                    DebugValueRow(label: "Raw MapKit steps", value: "\(legs.reduce(0) { $0 + $1.debugSteps.count })")
                }

                Section("Device now") {
                    DebugValueRow(label: "Maneuver", value: snapshot.maneuver.debugTitle)
                    DebugValueRow(label: "To maneuver", value: distanceFormatter(CLLocationDistance(snapshot.distanceToManeuverMeters)))
                    DebugValueRow(label: "To destination", value: distanceFormatter(CLLocationDistance(snapshot.distanceToDestinationMeters)))
                    DebugValueRow(label: "Trip progress", value: "\(snapshot.tripProgressComplete)%")
                    DebugValueRow(label: "Maneuver progress", value: "\(snapshot.maneuverProgressRemaining)%")
                    DebugValueRow(label: "Roundabout exit", value: snapshot.roundaboutExit.map(String.init) ?? "none")
                    DebugValueRow(label: "Roundabout angles", value: anglesText(snapshot.roundaboutExitAngles))
                    DebugValueRow(label: "Route progress", value: distanceFormatter(snapshot.routeProgressMeters))
                    DebugValueRow(label: "Route gap", value: snapshot.distanceToRouteMeters >= 0 ? distanceFormatter(snapshot.distanceToRouteMeters) : "unknown")
                    DebugValueRow(label: "Off route", value: snapshot.isOffRoute ? "yes" : "no")
                    DebugValueRow(label: "Selected offset", value: snapshot.selectedInstructionOffsetMeters.map(distanceFormatter) ?? "none")
                    DebugValueRow(label: "Selected source", value: snapshot.selectedInstructionText)
                    DebugValueRow(label: "Decision", value: snapshot.selectionReason)
                }

                Section {
                    if navigationDebugLog.isEmpty {
                        Text("No navigation packets logged yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(navigationDebugLog.suffix(30).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(.vertical, 3)
                        }
                    }
                } header: {
                    HStack {
                        Text("Navigation Log")
                        Spacer()
                        Button("Clear", action: clearNavigationDebugLog)
                            .font(.caption.weight(.semibold))
                    }
                }

                ForEach(Array(legs.enumerated()), id: \.element.id) { legIndex, leg in
                    Section("Leg \(legIndex + 1)") {
                        DebugValueRow(label: "Distance", value: distanceFormatter(leg.distance))
                        DebugValueRow(label: "Ride time", value: travelTimeFormatter(leg.expectedTravelTime))

                        ForEach(Array(leg.debugSteps.enumerated()), id: \.offset) { stepIndex, step in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(stepIndex + 1). \(step.rawInstruction.isEmpty ? "(empty instruction)" : step.rawInstruction)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(distanceFormatter(step.distance))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                if let notice = step.rawNotice, !notice.isEmpty {
                                    DebugValueRow(label: "Notice", value: notice)
                                }

                                DebugValueRow(label: "MapKit text ->", value: step.sourceManeuver.debugTitle)
                                DebugValueRow(label: "Device sends", value: step.deviceManeuver?.debugTitle ?? "skipped")
                                DebugValueRow(label: "Pipeline", value: step.skipReason ?? "kept")
                                DebugValueRow(label: "Leg offset", value: distanceFormatter(step.distanceFromLegStart))
                                DebugValueRow(label: "Bearings", value: bearingText(step))

                                if step.sourceManeuver == .roundabout || step.mapKitRoundaboutExit != nil {
                                    DebugValueRow(label: "Raw exit guess", value: step.mapKitRoundaboutExit.map(String.init) ?? "none")
                                    DebugValueRow(label: "Raw exit angles", value: anglesText(step.mapKitRoundaboutExitAngles))
                                    DebugValueRow(label: "Sent exit", value: step.deviceRoundaboutExit.map(String.init) ?? "none")
                                    DebugValueRow(label: "Sent exit angles", value: anglesText(step.deviceRoundaboutExitAngles))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("MapKit Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bearingText(_ step: RouteDebugStep) -> String {
        let incoming = step.incomingBearing.map { "\($0) deg" } ?? "none"
        let outgoing = step.outgoingBearing.map { "\($0) deg" } ?? "none"
        return "\(incoming) -> \(outgoing)"
    }

    private func anglesText(_ angles: [RoundaboutExitAngle]) -> String {
        guard !angles.isEmpty else {
            return "none"
        }

        return angles.map { "\($0.index): \($0.angleDegrees) deg" }.joined(separator: ", ")
    }
}

private struct DebugValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct RouteLeg: Identifiable {
    let id = UUID()
    let fromWaypointID: UUID
    let toWaypointID: UUID
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let polyline: MKPolyline
    let instructions: [RouteInstruction]
    let debugSteps: [RouteDebugStep]

    init(fromWaypointID: UUID, toWaypointID: UUID, distance: CLLocationDistance, expectedTravelTime: TimeInterval, polyline: MKPolyline, steps: [MKRoute.Step], isFinalLeg: Bool) {
        self.fromWaypointID = fromWaypointID
        self.toWaypointID = toWaypointID
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.polyline = polyline

        var distanceFromLegStart: CLLocationDistance = 0
        let debugSteps = steps.enumerated().map { index, step in
            let roundaboutExit = RouteInstruction.roundaboutExit(from: step.instructions)
            let maneuverDistance = distanceFromLegStart
            let incomingBearing = roundaboutExit == nil ? (index > 0 ? steps[index - 1].polyline.lastSegmentBearingDegrees : nil) : polyline.bearing(atDistance: maneuverDistance - 50)
            let outgoingBearing = roundaboutExit == nil ? step.polyline.lastSegmentBearingDegrees : polyline.bearing(atDistance: maneuverDistance + 50)
            let sourceManeuver = DeviceManeuver(instruction: step.instructions)
            let inferredManeuver = RouteInstruction.inferredManeuver(
                sourceManeuver,
                instruction: step.instructions,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let roundaboutAngles = RouteInstruction.roundaboutExitAngles(
                exit: roundaboutExit,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let deviceManeuver = RouteInstruction.normalizedManeuver(
                inferredManeuver,
                roundaboutExit: roundaboutExit,
                roundaboutExitAngles: roundaboutAngles,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let skipReason: String?
            if step.distance <= 1 {
                skipReason = "distance <= 1m"
            } else if !isFinalLeg && sourceManeuver == .arrive {
                skipReason = "intermediate leg arrival"
            } else if sourceManeuver == .continueAhead && step.instructions.isEmpty {
                skipReason = "empty continue"
            } else {
                skipReason = nil
            }

            let debugStep = RouteDebugStep(
                distanceFromLegStart: distanceFromLegStart,
                distance: step.distance,
                rawInstruction: step.instructions,
                rawNotice: step.notice,
                sourceManeuver: sourceManeuver,
                deviceManeuver: skipReason == nil ? deviceManeuver : nil,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing,
                mapKitRoundaboutExit: roundaboutExit,
                mapKitRoundaboutExitAngles: roundaboutAngles,
                deviceRoundaboutExit: skipReason == nil && deviceManeuver == .roundabout ? roundaboutExit : nil,
                deviceRoundaboutExitAngles: skipReason == nil && deviceManeuver == .roundabout ? roundaboutAngles : [],
                skipReason: skipReason
            )

            distanceFromLegStart += step.distance
            return debugStep
        }
        self.debugSteps = debugSteps
        self.instructions = debugSteps.compactMap(RouteInstruction.init)
    }
}

private struct RideNavigationSnapshot {
    let distanceToDestinationMeters: Int
    let distanceToManeuverMeters: Int
    let destinationBearingDegrees: Int
    let tripProgressComplete: Int
    let maneuverProgressRemaining: Int
    let maneuver: DeviceManeuver
    let roundaboutExit: Int?
    let roundaboutExitAngles: [RoundaboutExitAngle]
    let selectedInstructionText: String
    let selectedInstructionOffsetMeters: CLLocationDistance?
    let selectedInstructionEndMeters: CLLocationDistance?
    let routeProgressMeters: CLLocationDistance
    let distanceToRouteMeters: CLLocationDistance
    let isOffRoute: Bool
    let selectionReason: String
}

private struct RouteProgress {
    let legID: UUID
    let distanceToRoute: CLLocationDistance
    let distanceFromLegStart: CLLocationDistance
    let distanceFromRouteStart: CLLocationDistance
    let legDistance: CLLocationDistance
    let routeBearingDegrees: Double
    let coordinate: CLLocationCoordinate2D?
}

private struct PolylineProgress {
    let distanceToRoute: CLLocationDistance
    let distanceFromStart: CLLocationDistance
    let polylineLength: CLLocationDistance
    let routeBearingDegrees: Double
    let coordinate: CLLocationCoordinate2D
}

private struct PolylineRouteSample {
    let coordinate: CLLocationCoordinate2D
    let bearingDegrees: Int
}

private struct RouteDebugStep {
    let distanceFromLegStart: CLLocationDistance
    let distance: CLLocationDistance
    let rawInstruction: String
    let rawNotice: String?
    let sourceManeuver: DeviceManeuver
    let deviceManeuver: DeviceManeuver?
    let incomingBearing: Int?
    let outgoingBearing: Int?
    let mapKitRoundaboutExit: Int?
    let mapKitRoundaboutExitAngles: [RoundaboutExitAngle]
    let deviceRoundaboutExit: Int?
    let deviceRoundaboutExitAngles: [RoundaboutExitAngle]
    let skipReason: String?
}

private struct RouteInstruction {
    let distanceFromLegStart: CLLocationDistance
    let distance: CLLocationDistance
    let rawInstruction: String
    let rawNotice: String?
    let sourceManeuver: DeviceManeuver
    let maneuver: DeviceManeuver
    let incomingBearing: Int?
    let outgoingBearing: Int?
    let roundaboutExit: Int?
    let roundaboutExitAngles: [RoundaboutExitAngle]
    let mapKitRoundaboutExit: Int?
    let mapKitRoundaboutExitAngles: [RoundaboutExitAngle]

    init?(_ debugStep: RouteDebugStep) {
        guard let maneuver = debugStep.deviceManeuver,
              debugStep.skipReason == nil else {
            return nil
        }

        self.distanceFromLegStart = debugStep.distanceFromLegStart
        self.distance = debugStep.distance
        self.rawInstruction = debugStep.rawInstruction
        self.rawNotice = debugStep.rawNotice
        self.sourceManeuver = debugStep.sourceManeuver
        self.maneuver = maneuver
        self.incomingBearing = debugStep.incomingBearing
        self.outgoingBearing = debugStep.outgoingBearing
        self.roundaboutExit = debugStep.deviceRoundaboutExit
        self.roundaboutExitAngles = debugStep.deviceRoundaboutExitAngles
        self.mapKitRoundaboutExit = debugStep.mapKitRoundaboutExit
        self.mapKitRoundaboutExitAngles = debugStep.mapKitRoundaboutExitAngles
    }

    static func roundaboutExit(from instruction: String) -> Int? {
        let lowercased = instruction.lowercased()
        guard lowercased.contains("roundabout") else {
            return nil
        }

        let words = lowercased
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")

        for word in words {
            if let exit = Int(word) {
                return exit
            }

            switch word {
                case "first", "1st": return 1
                case "second", "2nd": return 2
                case "third", "3rd": return 3
                case "fourth", "4th": return 4
                case "fifth", "5th": return 5
                case "sixth", "6th": return 6
                default: break
            }
        }

        return nil
    }

    static func inferredManeuver(_ maneuver: DeviceManeuver, instruction: String, incomingBearing: Int?, outgoingBearing: Int?) -> DeviceManeuver {
        guard (maneuver == .continueAhead || maneuver == .exitLeft),
              instruction.lowercased().contains("take the exit") || instruction.lowercased().contains("take exit") else {
            return maneuver
        }

        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return .exitLeft
        }

        if angle < -100 {
            return .exitLeft
        }
        if angle < -25 {
            return .exitLeft
        }
        if angle > 100 {
            return .exitRight
        }
        if angle > 25 {
            return .exitRight
        }

        return .continueAhead
    }

    static func roundaboutExitAngles(exit: Int?, incomingBearing: Int?, outgoingBearing: Int?) -> [RoundaboutExitAngle] {
        guard let exit else {
            return []
        }

        let targetAngle = relativeExitAngle(exit: exit, incomingBearing: incomingBearing, outgoingBearing: outgoingBearing)
        let target = normalizedRoundaboutTargetAngle(targetAngle, exit: exit)
        let entryAngle = 180
        var sweep = normalizePositiveDegrees(target) - entryAngle
        if sweep <= 0 {
            sweep += 360
        }
        if exit > 1 && sweep < exit * 45 {
            sweep += 360
        }

        return (0..<exit).map { index in
            let ratio = Double(index + 1) / Double(exit)
            let angle = normalizedSignedAngle(Int((Double(entryAngle) + (Double(sweep) * ratio)).rounded()))
            return RoundaboutExitAngle(index: index + 1, angleDegrees: angle)
        }
    }

    private static func normalizedRoundaboutTargetAngle(_ targetAngle: Int?, exit: Int) -> Int {
        let fallback = fallbackExitAngle(for: exit)
        guard let targetAngle else {
            return fallback
        }

        if exit >= 3 && abs(targetAngle) < 35 {
            return fallback
        }

        return clamp(targetAngle, min: -150, max: 150)
    }

    private static func normalizePositiveDegrees(_ degrees: Int) -> Int {
        var angle = degrees
        while angle < 0 {
            angle += 360
        }
        while angle >= 360 {
            angle -= 360
        }

        return angle
    }

    private static func normalizedSignedAngle(_ degrees: Int) -> Int {
        var angle = degrees
        while angle > 180 {
            angle -= 360
        }
        while angle < -180 {
            angle += 360
        }

        return angle
    }

    static func normalizedManeuver(_ maneuver: DeviceManeuver, roundaboutExit: Int?, roundaboutExitAngles: [RoundaboutExitAngle], incomingBearing: Int?, outgoingBearing: Int?) -> DeviceManeuver {
        guard maneuver != .roundabout || roundaboutExit != nil else {
            return fallbackManeuver(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing)
        }

        guard maneuver == .roundabout,
              roundaboutExit == 1 else {
            return maneuver
        }

        if roundaboutExitAngles.first?.angleDegrees ?? 0 < -110 {
            return .turnLeft
        }

        return maneuver
    }

    private static func fallbackManeuver(incomingBearing: Int?, outgoingBearing: Int?) -> DeviceManeuver {
        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return .continueAhead
        }

        if angle < -60 {
            return .turnLeft
        }
        if angle < -20 {
            return .slightLeft
        }
        if angle > 60 {
            return .turnRight
        }
        if angle > 20 {
            return .slightRight
        }

        return .continueAhead
    }

    private static func relativeExitAngle(exit: Int, incomingBearing: Int?, outgoingBearing: Int?) -> Int? {
        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return nil
        }

        if exit == 1 && abs(angle) <= 120 {
            return 0
        }

        return angle
    }

    private static func relativeAngle(incomingBearing: Int?, outgoingBearing: Int?) -> Int? {
        guard let incomingBearing,
              let outgoingBearing else {
            return nil
        }

        var angle = outgoingBearing - incomingBearing
        while angle > 180 {
            angle -= 360
        }
        while angle < -180 {
            angle += 360
        }

        return angle
    }

    private static func fallbackExitAngle(for exit: Int) -> Int {
        min(150, max(-150, -70 + ((exit - 1) * 55)))
    }

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct RoundaboutExitAngle {
    let index: Int
    let angleDegrees: Int
}

private enum DeviceManeuver: String {
    case bendLeft
    case exitLeft
    case slightLeft
    case turnLeft
    case sharpLeft
    case uTurn
    case continueAhead = "continue"
    case exitRight
    case slightRight
    case turnRight
    case sharpRight
    case roundabout
    case arrive

    init(instruction: String) {
        let text = instruction.lowercased()

        if text.contains("roundabout") {
            self = .roundabout
        } else if text.contains("u-turn") || text.contains("u turn") {
            self = .uTurn
        } else if text.contains("arrive") || text.contains("destination") {
            self = .arrive
        } else if text.contains("take the exit") || text.contains("take exit") {
            self = .exitLeft
        } else if text.contains("sharp left") {
            self = .sharpLeft
        } else if text.contains("slight left") {
            self = .slightLeft
        } else if text.contains("bear left") || text.contains("keep left") {
            self = .bendLeft
        } else if text.contains("left") {
            self = .turnLeft
        } else if text.contains("sharp right") {
            self = .sharpRight
        } else if text.contains("slight right") {
            self = .slightRight
        } else if text.contains("bear right") || text.contains("keep right") {
            self = .slightRight
        } else if text.contains("right") {
            self = .turnRight
        } else {
            self = .continueAhead
        }
    }

    var isMeaningfulDirection: Bool {
        self != .continueAhead
    }

    var debugTitle: String {
        switch self {
            case .bendLeft: return "bend left"
            case .exitLeft: return "exit left"
            case .slightLeft: return "slight left"
            case .turnLeft: return "left"
            case .sharpLeft: return "sharp left"
            case .uTurn: return "u-turn"
            case .continueAhead: return "continue"
            case .exitRight: return "exit right"
            case .slightRight: return "slight right"
            case .turnRight: return "right"
            case .sharpRight: return "sharp right"
            case .roundabout: return "roundabout"
            case .arrive: return "arrive"
        }
    }
}

private enum RideMode: String, CaseIterable, Identifiable {
    case directions
    case heading

    var id: String { rawValue }

    var title: String {
        switch self {
            case .directions: return "Directions"
            case .heading: return "Heading"
        }
    }

    var activeTitle: String {
        switch self {
            case .directions: return "Turn-by-turn"
            case .heading: return "Destination heading"
        }
    }

    var icon: String {
        switch self {
            case .directions: return "arrow.triangle.turn.up.right.diamond.fill"
            case .heading: return "location.north.line.fill"
        }
    }
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

    func bearingDegrees(to destination: CLLocationCoordinate2D) -> Int {
        let startLatitude = latitude * .pi / 180
        let startLongitude = longitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let destinationLongitude = destination.longitude * .pi / 180
        let longitudeDelta = destinationLongitude - startLongitude
        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(startLatitude) * sin(destinationLatitude) - sin(startLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        let bearing = atan2(y, x) * 180 / .pi

        return Int((bearing + 360).truncatingRemainder(dividingBy: 360).rounded())
    }
}

private extension MKPolyline {
    var routeCoordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }

    var approximateBearingDegrees: Int? {
        let coordinates = routeCoordinates
        guard let start = coordinates.first,
              let end = coordinates.last,
              start.latitude != end.latitude || start.longitude != end.longitude else {
            return nil
        }

        return start.bearingDegrees(to: end)
    }

    var lastSegmentBearingDegrees: Int? {
        let coordinates = routeCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        for index in stride(from: coordinates.count - 1, through: 1, by: -1) {
            let start = coordinates[index - 1]
            let end = coordinates[index]
            if start.latitude != end.latitude || start.longitude != end.longitude {
                return start.bearingDegrees(to: end)
            }
        }

        return nil
    }

    func sample(at fraction: Double) -> PolylineRouteSample? {
        let coordinates = routeCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        let segments = zip(coordinates, coordinates.dropFirst()).map { start, end in
            (start: start, end: end, distance: MKMapPoint(start).distance(to: MKMapPoint(end)))
        }
        let totalDistance = segments.reduce(0) { $0 + $1.distance }
        guard totalDistance > 0 else {
            return nil
        }

        let targetDistance = max(0, min(totalDistance, totalDistance * fraction))
        var distanceSoFar: CLLocationDistance = 0

        for segment in segments {
            if distanceSoFar + segment.distance >= targetDistance {
                let segmentFraction = segment.distance > 0 ? (targetDistance - distanceSoFar) / segment.distance : 0
                let startPoint = MKMapPoint(segment.start)
                let endPoint = MKMapPoint(segment.end)
                let point = MKMapPoint(
                    x: startPoint.x + ((endPoint.x - startPoint.x) * segmentFraction),
                    y: startPoint.y + ((endPoint.y - startPoint.y) * segmentFraction)
                )
                return PolylineRouteSample(
                    coordinate: point.coordinate,
                    bearingDegrees: segment.start.bearingDegrees(to: segment.end)
                )
            }

            distanceSoFar += segment.distance
        }

        guard let segment = segments.last else {
            return nil
        }

        return PolylineRouteSample(
            coordinate: segment.end,
            bearingDegrees: segment.start.bearingDegrees(to: segment.end)
        )
    }

    func bearing(atDistance targetDistance: CLLocationDistance) -> Int? {
        let coordinates = routeCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        let segments = zip(coordinates, coordinates.dropFirst()).map { start, end in
            (start: start, end: end, distance: MKMapPoint(start).distance(to: MKMapPoint(end)))
        }
        let totalDistance = segments.reduce(0) { $0 + $1.distance }
        guard totalDistance > 0 else {
            return nil
        }

        let clampedDistance = max(0, min(totalDistance, targetDistance))
        var distanceSoFar: CLLocationDistance = 0

        for segment in segments {
            if distanceSoFar + segment.distance >= clampedDistance && segment.distance > 0 {
                return segment.start.bearingDegrees(to: segment.end)
            }

            distanceSoFar += segment.distance
        }

        return segments.last.map { $0.start.bearingDegrees(to: $0.end) }
    }

    func progressNearest(to coordinate: CLLocationCoordinate2D) -> PolylineProgress? {
        let coordinates = routeCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        let targetPoint = MKMapPoint(coordinate)
        var distanceFromStart: CLLocationDistance = 0
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestDistanceFromStart: CLLocationDistance = 0
        var bestBearing = 0.0
        var bestCoordinate = coordinates[0]

        for (startCoordinate, endCoordinate) in zip(coordinates, coordinates.dropFirst()) {
            let startPoint = MKMapPoint(startCoordinate)
            let endPoint = MKMapPoint(endCoordinate)
            let segmentDistance = startPoint.distance(to: endPoint)
            let projectedDistance = targetPoint.projectedDistance(from: startPoint, to: endPoint)

            if projectedDistance.distanceToSegment < bestDistance {
                bestDistance = projectedDistance.distanceToSegment
                bestDistanceFromStart = distanceFromStart + (segmentDistance * projectedDistance.fractionAlongSegment)
                bestBearing = Double(startCoordinate.bearingDegrees(to: endCoordinate))
                bestCoordinate = MKMapPoint(
                    x: startPoint.x + ((endPoint.x - startPoint.x) * projectedDistance.fractionAlongSegment),
                    y: startPoint.y + ((endPoint.y - startPoint.y) * projectedDistance.fractionAlongSegment)
                ).coordinate
            }

            distanceFromStart += segmentDistance
        }

        return PolylineProgress(
            distanceToRoute: bestDistance,
            distanceFromStart: bestDistanceFromStart,
            polylineLength: distanceFromStart,
            routeBearingDegrees: bestBearing,
            coordinate: bestCoordinate
        )
    }
}

private extension MKMapPoint {
    func projectedDistance(from start: MKMapPoint, to end: MKMapPoint) -> (distanceToSegment: CLLocationDistance, fractionAlongSegment: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)

        guard lengthSquared > 0 else {
            return (distance(to: start), 0)
        }

        let rawFraction = (((x - start.x) * dx) + ((y - start.y) * dy)) / lengthSquared
        let fraction = max(0, min(1, rawFraction))
        let projectedPoint = MKMapPoint(x: start.x + (dx * fraction), y: start.y + (dy * fraction))

        return (distance(to: projectedPoint), fraction)
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
    @Published var currentCourseDegrees: Double?
    @Published var currentSpeedMetersPerSecond: CLLocationSpeed?

    private let manager = CLLocationManager()
    private var shouldTrackRide = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .automotiveNavigation
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

    func startRideTracking() {
        shouldTrackRide = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false

        switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways:
                configureBackgroundLocationIfAvailable()
                manager.startUpdatingLocation()
            case .authorizedWhenInUse:
                manager.requestAlwaysAuthorization()
                manager.startUpdatingLocation()
            case .denied, .restricted:
                break
            @unknown default:
                break
        }
    }

    func stopRideTracking() {
        shouldTrackRide = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }

        if shouldTrackRide {
            if manager.authorizationStatus == .authorizedAlways {
                configureBackgroundLocationIfAvailable()
            }
            manager.startUpdatingLocation()
        } else {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        currentCoordinate = location.coordinate
        currentSpeedMetersPerSecond = max(location.speed, 0)

        if location.course >= 0 && location.speed > 1.4 {
            currentCourseDegrees = location.course
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    private func configureBackgroundLocationIfAvailable() {
        guard backgroundLocationModeDeclared else {
            return
        }

        manager.allowsBackgroundLocationUpdates = true
    }

    private var backgroundLocationModeDeclared: Bool {
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            return modes.contains("location")
        }

        if let mode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? String {
            return mode.contains("location")
        }

        return false
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

private struct StartRideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.62 : 0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct RideModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                isSelected ? Color.cyan.opacity(configuration.isPressed ? 0.56 : 0.72) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.07),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

private struct DebugRideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.cyan)
            .frame(height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }

                self?.height = max(0, UIScreen.main.bounds.height - frame.minY)
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.height = 0
            }
        )
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
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
