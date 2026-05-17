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

    private let serviceUuid = CBUUID(string: "c6372234-79d6-4a5e-8a57-08a3b7a8a7d1")
    private let stateCharacteristicUuid = CBUUID(string: "f6c8d747-fc2c-4ef4-906a-7c8cbf552814")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var pendingPayload: Data?
    private var packet = Data()
    private var offset = 0

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
        pendingPayload = payload

        if let peripheral, let characteristic, peripheral.state == .connected {
            send(payload, to: characteristic)
            return
        }

        guard central?.state == .poweredOn else {
            status = "Bluetooth unavailable"
            return
        }

        status = "Scanning"
        central?.scanForPeripherals(withServices: [serviceUuid])
    }

    /**
     * Sends the supplied payload to the discovered characteristic.
     *
     * - Parameters:
     *   - payload: JSON payload bytes.
     *   - characteristic: Writable SteedPilot BLE characteristic.
     */
    private func send(_ payload: Data, to characteristic: CBCharacteristic) {
        packet = payload
        packet.append(0x0A)
        offset = 0
        self.characteristic = characteristic
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
            pendingPayload = nil
            return
        }

        let chunkSize = min(128, max(20, peripheral.maximumWriteValueLength(for: .withResponse)))
        let end = min(offset + chunkSize, packet.count)
        peripheral.writeValue(packet.subdata(in: offset..<end), for: characteristic, type: .withResponse)
        offset = end
    }
}

extension BluetoothNavSender: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status = central.state == .poweredOn ? "Ready" : "Bluetooth unavailable"
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        status = "Connecting"
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Discovering"
        peripheral.discoverServices([serviceUuid])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = "Disconnected"
        characteristic = nil
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connect failed"
    }
}

extension BluetoothNavSender: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            status = "Service failed"
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else {
            status = "Service missing"
            return
        }

        peripheral.discoverCharacteristics([stateCharacteristicUuid], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            status = "Characteristic failed"
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == stateCharacteristicUuid }) else {
            status = "Characteristic missing"
            return
        }

        self.characteristic = characteristic
        if let pendingPayload {
            send(pendingPayload, to: characteristic)
        } else {
            status = "Connected"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            status = "Write failed"
            return
        }

        writeNextChunk()
    }
}
