// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import Combine
import CoreBluetooth
import Foundation

final class BluetoothNavSender: NSObject, ObservableObject {
    @Published private(set) var status = "Idle"
    @Published private(set) var isConnected = false
    @Published private(set) var isReplaying = false
    @Published private(set) var replayProgress = ""

    private let serviceUuid = CBUUID(string: "c6372234-79d6-4a5e-8a57-08a3b7a8a7d1")
    private let stateCharacteristicUuid = CBUUID(string: "f6c8d747-fc2c-4ef4-906a-7c8cbf552814")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var pendingPayloads: [Data] = []
    private var packet = Data()
    private var currentPayload: Data?
    private var offset = 0
    private var isWriting = false
    private var heartbeatTimer: Timer?
    private var writeTimeoutTimer: Timer?
    private var replayWorkItems: [DispatchWorkItem] = []
    private var isConnecting = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /**
     * Queues a packet for transmission and connects if needed.
     *
     * - Parameter payload: JSON payload bytes.
     */
    func send(_ payload: Data) {
        if isReplaying {
            pendingPayloads.append(payload)
        } else {
            pendingPayloads = [payload]
        }

        if let peripheral, let characteristic, peripheral.state == .connected {
            sendNextPayload(to: characteristic)
            return
        }

        guard central?.state == .poweredOn else {
            status = "Bluetooth unavailable"
            return
        }

        scanForSteedPilot()
    }

    /**
     * Sends a heartbeat only when the link is otherwise idle.
     */
    private func sendHeartbeat() {
        guard !isWriting,
              pendingPayloads.isEmpty,
              let peripheral,
              let characteristic,
              peripheral.state == .connected else {
            return
        }

        pendingPayloads.append(NavFixtures.heartbeat)
        sendNextPayload(to: characteristic)
    }

    /**
     * Starts scanning for the SteedPilot peripheral if not already connected.
     */
    private func scanForSteedPilot() {
        guard let central, central.state == .poweredOn else {
            status = "Bluetooth unavailable"
            return
        }

        if peripheral?.state == .connected || isConnecting {
            return
        }

        status = "Scanning"
        central.scanForPeripherals(withServices: [serviceUuid])
    }

    /**
     * Starts a timed route replay.
     *
     * - Parameter route: Replay route containing timed packet steps.
     */
    func replay(_ route: ReplayRoute) {
        cancelReplay()
        isReplaying = true

        var delayMs = 0
        for (index, step) in route.steps.enumerated() {
            let item = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }

                if let payload = NavFixtures.payload(for: step) {
                    replayProgress = "\(index + 1) / \(route.steps.count)"
                    send(payload)
                }

                if index + 1 == route.steps.count {
                    isReplaying = false
                }
            }

            replayWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: item)
            delayMs += step.delayMs
        }
    }

    /**
     * Cancels any queued replay steps.
     */
    func cancelReplay() {
        for item in replayWorkItems {
            item.cancel()
        }

        replayWorkItems.removeAll()
        isReplaying = false
        replayProgress = ""
    }

    /**
     * Sends the next queued payload to the discovered characteristic.
     *
     * - Parameter characteristic: Writable SteedPilot BLE characteristic.
     */
    private func sendNextPayload(to characteristic: CBCharacteristic) {
        guard !isWriting, !pendingPayloads.isEmpty else {
            return
        }

        let payload = pendingPayloads.removeFirst()
        currentPayload = payload
        packet = payload
        packet.append(0x0A)
        offset = 0
        self.characteristic = characteristic
        isWriting = true
        status = "Sending"
        writeNextChunk()
    }

    /**
     * Writes the next BLE packet chunk.
     */
    private func writeNextChunk() {
        guard let peripheral, let characteristic else {
            status = "Not connected"
            return
        }

        if offset >= packet.count {
            status = "Sent"
            isWriting = false
            currentPayload = nil
            stopWriteTimeoutTimer()
            sendNextPayload(to: characteristic)
            return
        }

        let chunkSize = min(128, max(20, peripheral.maximumWriteValueLength(for: .withResponse)))
        let end = min(offset + chunkSize, packet.count)
        startWriteTimeoutTimer()
        peripheral.writeValue(packet.subdata(in: offset..<end), for: characteristic, type: .withResponse)
        offset = end
    }

    /**
     * Starts a guard timer for write-with-response callbacks.
     */
    private func startWriteTimeoutTimer() {
        writeTimeoutTimer?.invalidate()
        writeTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.handleWriteTimeout()
        }
    }

    /**
     * Stops the active write timeout timer.
     */
    private func stopWriteTimeoutTimer() {
        writeTimeoutTimer?.invalidate()
        writeTimeoutTimer = nil
    }

    /**
     * Reconnects and retries when a write acknowledgement never arrives.
     */
    private func handleWriteTimeout() {
        if let currentPayload {
            pendingPayloads.insert(currentPayload, at: 0)
        }

        packet = Data()
        currentPayload = nil
        offset = 0
        isWriting = false
        isConnected = false
        characteristic = nil
        status = "Reconnecting"
        stopHeartbeatTimer()

        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            scanForSteedPilot()
        }
    }

    /**
     * Starts periodic heartbeat packets while the peripheral remains connected.
     */
    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    /**
     * Stops periodic heartbeat packets.
     */
    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /**
     * Clears the active write state when the connection drops.
     */
    private func clearWriteState(requeueCurrentPayload: Bool) {
        stopWriteTimeoutTimer()
        if requeueCurrentPayload, let currentPayload {
            pendingPayloads.insert(currentPayload, at: 0)
        }

        packet = Data()
        currentPayload = nil
        offset = 0
        isWriting = false
    }
}

extension BluetoothNavSender: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanForSteedPilot()
        } else {
            status = "Bluetooth unavailable"
            isConnected = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if isConnecting || self.peripheral?.state == .connected {
            return
        }

        status = "Connecting"
        isConnecting = true
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Discovering"
        isConnecting = false
        peripheral.discoverServices([serviceUuid])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = "Disconnected"
        isConnected = false
        isConnecting = false
        characteristic = nil
        clearWriteState(requeueCurrentPayload: true)
        stopHeartbeatTimer()
        scanForSteedPilot()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connect failed"
        isConnected = false
        isConnecting = false
        scanForSteedPilot()
    }
}

extension BluetoothNavSender: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            status = "Service failed"
            isConnected = false
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else {
            status = "Service missing"
            isConnected = false
            return
        }

        peripheral.discoverCharacteristics([stateCharacteristicUuid], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            status = "Characteristic failed"
            isConnected = false
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == stateCharacteristicUuid }) else {
            status = "Characteristic missing"
            isConnected = false
            return
        }

        self.characteristic = characteristic
        isConnected = true
        startHeartbeatTimer()
        if !pendingPayloads.isEmpty {
            sendNextPayload(to: characteristic)
        } else {
            status = "Connected"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            status = "Write failed"
            isConnected = peripheral.state == .connected
            clearWriteState(requeueCurrentPayload: true)
            return
        }

        stopWriteTimeoutTimer()
        writeNextChunk()
    }
}
