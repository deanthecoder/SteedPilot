#!/usr/bin/env swift
// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import CoreBluetooth
import Foundation

private let serviceUuid = CBUUID(string: "c6372234-79d6-4a5e-8a57-08a3b7a8a7d1")
private let stateCharacteristicUuid = CBUUID(string: "f6c8d747-fc2c-4ef4-906a-7c8cbf552814")

private struct Payload {
    let data: Data
    let delayMs: Int
}

private final class Sender: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let payloads: [Payload]
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var packet = Data()
    private var offset = 0
    private var payloadIndex = 0

    init(payloads: [Payload]) {
        self.payloads = payloads
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /**
     * Handles CoreBluetooth power-state changes.
     *
     * - Parameter central: The central manager reporting its current state.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth is not powered on: \(central.state.rawValue)")
            return
        }

        print("Scanning for SteedPilot...")
        central.scanForPeripherals(withServices: [serviceUuid], options: nil)
    }

    /**
     * Connects to the first advertising SteedPilot peripheral.
     */
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        self.peripheral = peripheral
        central.stopScan()
        print("Connecting to \(peripheral.name ?? "SteedPilot")...")
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    /**
     * Discovers the SteedPilot BLE service after connection.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected. Discovering service...")
        peripheral.discoverServices([serviceUuid])
    }

    /**
     * Reports connection failures before exiting.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        exit(1)
    }

    /**
     * Discovers the writable navigation-state characteristic.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            print("Service discovery failed: \(error.localizedDescription)")
            exit(1)
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else {
            print("SteedPilot service not found")
            exit(1)
        }

        peripheral.discoverCharacteristics([stateCharacteristicUuid], for: service)
    }

    /**
     * Sends the selected JSON fixture to the device.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            print("Characteristic discovery failed: \(error.localizedDescription)")
            exit(1)
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == stateCharacteristicUuid }) else {
            print("SteedPilot state characteristic not found")
            exit(1)
        }

        self.characteristic = characteristic
        sendCurrentPayload()
    }

    /**
     * Starts sending the currently selected payload.
     */
    private func sendCurrentPayload() {
        guard payloadIndex < payloads.count else {
            if let peripheral {
                central.cancelPeripheralConnection(peripheral)
            }

            exit(0)
        }

        packet = payloads[payloadIndex].data
        packet.append(0x0A)
        offset = 0
        writeNextChunk()
    }

    /**
     * Sends the next BLE write chunk.
     */
    private func writeNextChunk() {
        guard let peripheral, let characteristic else {
            print("Peripheral disconnected before write completed")
            exit(1)
        }

        if offset >= packet.count {
            print("Sent packet \(payloadIndex + 1) of \(payloads.count).")
            payloadIndex += 1
            if payloadIndex >= payloads.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.central.cancelPeripheralConnection(peripheral)
                    exit(0)
                }
            } else {
                let delay = Double(self.payloads[self.payloadIndex].delayMs) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.sendCurrentPayload()
                }
            }
            return
        }

        let chunkSize = min(128, max(20, peripheral.maximumWriteValueLength(for: .withResponse)))
        let end = min(offset + chunkSize, packet.count)
        peripheral.writeValue(packet.subdata(in: offset..<end), for: characteristic, type: .withResponse)
        offset = end
    }

    /**
     * Continues chunked writes after each acknowledged write.
     */
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("Write failed: \(error.localizedDescription)")
            exit(1)
        }

        writeNextChunk()
    }
}

struct ReplayStep: Decodable {
    let delayMs: Int?
    let packet: String?
    let json: String?
}

struct ReplayFile: Decodable {
    let steps: [ReplayStep]
}

private func loadPayload(_ path: String, delayMs: Int = 1000) throws -> Payload {
    Payload(data: try Data(contentsOf: URL(fileURLWithPath: path)), delayMs: delayMs)
}

private func loadReplay(_ path: String) throws -> [Payload] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let replay = try JSONDecoder().decode(ReplayFile.self, from: data)
    var payloads: [Payload] = []

    for step in replay.steps {
        let delayMs = step.delayMs ?? 1000
        if let packet = step.packet {
            payloads.append(try loadPayload(packet, delayMs: delayMs))
        } else if let json = step.json {
            payloads.append(Payload(data: Data(json.utf8), delayMs: delayMs))
        }
    }

    return payloads
}

guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--replay") else {
    print("Usage: tools/steedpilot_send.swift fixtures/navigation-roundabout.json")
    print("       tools/steedpilot_send.swift --replay fixtures/route-demo.json")
    exit(1)
}

private let payloads = try CommandLine.arguments[1] == "--replay"
    ? loadReplay(CommandLine.arguments[2])
    : [loadPayload(CommandLine.arguments[1])]
private let sender = Sender(payloads: payloads)
_ = sender
RunLoop.main.run()
