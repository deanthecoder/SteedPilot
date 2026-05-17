// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "FirmwareBle.h"

#include "SteedPilot/NavJson.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEService.h>
#include <BLECharacteristic.h>

namespace {

constexpr const char* DeviceName = "SteedPilot";
constexpr const char* ServiceUuid = "c6372234-79d6-4a5e-8a57-08a3b7a8a7d1";
constexpr const char* StateCharacteristicUuid = "f6c8d747-fc2c-4ef4-906a-7c8cbf552814";

FirmwareBle* owner = nullptr;

class SteedPilotBleServerCallbacks final : public BLEServerCallbacks {
public:
    /**
     * Handles BLE client connection events.
     *
     * @param server BLE server that accepted the connection.
     */
    void onConnect(BLEServer* server) override {
        (void)server;
        if (owner) {
            owner->setLinkState(SteedPilot::LinkState::Connected);
        }
    }

    /**
     * Handles BLE client disconnection events.
     *
     * @param server BLE server that lost the connection.
     */
    void onDisconnect(BLEServer* server) override {
        if (owner) {
            owner->setLinkState(SteedPilot::LinkState::Disconnected);
        }

        server->startAdvertising();
    }
};

class SteedPilotBleCharacteristicCallbacks final : public BLECharacteristicCallbacks {
public:
    /**
     * Handles writes to the navigation-state characteristic.
     *
     * @param characteristic Characteristic containing the written JSON packet.
     */
    void onWrite(BLECharacteristic* characteristic) override {
#if !defined(CONFIG_BLUEDROID_ENABLED)
        const String value = characteristic->getValue();
        if (owner && value.length() > 0) {
            owner->handleWrite(value.c_str(), (size_t)value.length());
        }
#else
        (void)characteristic;
#endif
    }

#if defined(CONFIG_BLUEDROID_ENABLED)
    /**
     * Handles Bluedroid writes using the raw write payload.
     *
     * @param characteristic Characteristic receiving the write.
     * @param param Bluedroid write event parameters.
     */
    void onWrite(BLECharacteristic* characteristic, esp_ble_gatts_cb_param_t* param) override {
        (void)characteristic;
        if (owner && param && param->write.len > 0) {
            owner->handleWrite((const char*)param->write.value, (size_t)param->write.len);
        }
    }
#endif
};

SteedPilotBleServerCallbacks serverCallbacks;
SteedPilotBleCharacteristicCallbacks characteristicCallbacks;

} // namespace

void FirmwareBle::begin(StateCallback callback) {
    _callback = callback;
    owner = this;

    BLEDevice::init(DeviceName);
    BLEServer* server = BLEDevice::createServer();
    server->setCallbacks(&serverCallbacks);

    BLEService* service = server->createService(ServiceUuid);
    BLECharacteristic* stateCharacteristic = service->createCharacteristic(
        StateCharacteristicUuid,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
    stateCharacteristic->setCallbacks(&characteristicCallbacks);
    stateCharacteristic->setValue("{\"v\":1,\"device\":\"SteedPilot\"}");

    service->start();
    server->getAdvertising()->addServiceUUID(ServiceUuid);
    server->startAdvertising();
    setLinkState(SteedPilot::LinkState::Pairing);

    Serial.println("SteedPilot BLE advertising");
}

SteedPilot::LinkState FirmwareBle::linkState() const {
    return _linkState;
}

void FirmwareBle::handleWrite(const char* data, size_t length) {
    Serial.printf("BLE write chunk: %u bytes\n", (unsigned)length);
    for (size_t i = 0; i < length; ++i) {
        const char ch = data[i];

        if (!_packetStarted && ch != '{') {
            continue;
        }

        if (_packetLength + 1 >= MaxPacketBytes) {
            Serial.println("BLE JSON packet too large");
            _packetLength = 0;
            _jsonDepth = 0;
            _packetStarted = false;
            return;
        }

        _packetStarted = true;
        _packet[_packetLength++] = ch;

        if (ch == '{') {
            ++_jsonDepth;
        } else if (ch == '}') {
            --_jsonDepth;
            if (_jsonDepth <= 0) {
                parseBufferedPacket();
                _packetLength = 0;
                _jsonDepth = 0;
                _packetStarted = false;
            }
        }
    }

}

void FirmwareBle::parseBufferedPacket() {
    _packet[_packetLength] = '\0';
    Serial.printf("BLE JSON packet: %u bytes, prefix: %.24s\n", (unsigned)_packetLength, _packet);

    SteedPilot::NavState state;
    if (!SteedPilot::parseNavStateJson(_packet, _packetLength, state)) {
        Serial.println("BLE JSON parse failed");
        return;
    }

    state.linkState = _linkState;
    state.connected = _linkState == SteedPilot::LinkState::Connected;

    if (_callback) {
        _callback(state);
    }
}

void FirmwareBle::setLinkState(SteedPilot::LinkState state) {
    _linkState = state;
}
