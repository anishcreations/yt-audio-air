//  YT Audio Air
//  Copyright (C) 2026 Anish Aryal
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Foundation
import CoreBluetooth

/// Dedicated BLE GATT Peripheral manager handling two-way remote control
/// and live metadata broadcasts for companion clients (Android / Wear OS).
final class BLEMediaServer: NSObject, CBPeripheralManagerDelegate {
    static let shared = BLEMediaServer()
    
    // MARK: - UUID Definitions
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let controlCharUUID = CBUUID(string: "87654321-4321-4321-4321-cba987654321")
    static let metadataCharUUID = CBUUID(string: "98765432-4321-4321-4321-abcdef123456")
    
    // MARK: - Command Protocol Bytes
    enum Command: UInt8 {
        case togglePlayPause = 0x01
        case nextTrack       = 0x02
        case previousTrack   = 0x03
        case volumeUp        = 0x04
        case volumeDown      = 0x05
    }
    
    // MARK: - Properties
    private var peripheralManager: CBPeripheralManager?
    private var controlCharacteristic: CBMutableCharacteristic?
    private var metadataCharacteristic: CBMutableCharacteristic?
    
    private let queue = DispatchQueue.main
    private var currentMetadataJSON: String = "{\"title\":\"YT Audio Air\",\"artist\":\"YouTube\",\"isPlaying\":false}"
    private var subscribedCentrals: [CBCentral] = []
    
    private override init() {
        super.init()
    }
    
    private func logBLE(_ message: String) {
        print("[BLEMediaServer] \(message)")
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/yt-audio-air-ble.log")
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }

    /// Starts advertising the BLE Peripheral service.
    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.peripheralManager == nil else { return }
            self.logBLE("Initializing CBPeripheralManager on Main Queue...")
            self.peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
            )
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        logBLE("State updated: \(peripheral.state.rawValue) (poweredOn = \(peripheral.state == .poweredOn))")
        guard peripheral.state == .poweredOn else {
            logBLE("Bluetooth state not poweredOn. Current raw value: \(peripheral.state.rawValue)")
            return
        }
        
        setupServices()
    }
    
    private func setupServices() {
        guard let peripheralManager = peripheralManager else { return }
        
        // 1. Control Characteristic (Write / WriteWithoutResponse)
        let controlChar = CBMutableCharacteristic(
            type: BLEMediaServer.controlCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        
        // 2. Metadata Characteristic (Notify / Read)
        let metadataChar = CBMutableCharacteristic(
            type: BLEMediaServer.metadataCharUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        // 3. Primary BLE Service
        let service = CBMutableService(type: BLEMediaServer.serviceUUID, primary: true)
        service.characteristics = [controlChar, metadataChar]
        
        self.controlCharacteristic = controlChar
        self.metadataCharacteristic = metadataChar
        
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logBLE("Failed to add BLE service: \(error.localizedDescription)")
            return
        }
        
        // Start Advertising Service UUID
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BLEMediaServer.serviceUUID],
            CBAdvertisementDataLocalNameKey: "YT Audio Air"
        ]
        peripheralManager?.startAdvertising(advertisementData)
        logBLE("Successfully added service and started advertising Service UUID 12345678-1234-1234-1234-123456789abc")
    }
    
    // MARK: - Incoming Writes (Remote Control Commands)
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEMediaServer.controlCharUUID,
                  let data = request.value,
                  let commandByte = data.first else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
                continue
            }
            
            print(String(format: "[BLEMediaServer] Received command byte: 0x%02X", commandByte))
            
            // Dispatch command execution to main thread
            DispatchQueue.main.async {
                AppDelegate.shared?.handleRemoteCommand(commandByte)
            }
            
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    // MARK: - Incoming Reads & Subscriptions
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLEMediaServer.metadataCharUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        
        let data = currentMetadataJSON.data(using: .utf8) ?? Data()
        if request.offset > data.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == BLEMediaServer.metadataCharUUID {
            if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                subscribedCentrals.append(central)
            }
            logBLE("Central subscribed to metadata updates: \(central.identifier)")
            
            // Send current metadata immediately upon subscription
            if let data = currentMetadataJSON.data(using: .utf8),
               let metadataChar = metadataCharacteristic {
                peripheral.updateValue(data, for: metadataChar, onSubscribedCentrals: [central])
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == BLEMediaServer.metadataCharUUID {
            subscribedCentrals.removeAll(where: { $0.identifier == central.identifier })
            logBLE("Central unsubscribed from metadata updates: \(central.identifier)")
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        logBLE("Peripheral manager buffer ready for subscriber updates.")
        if let data = currentMetadataJSON.data(using: .utf8),
           let metadataChar = metadataCharacteristic {
            peripheral.updateValue(data, for: metadataChar, onSubscribedCentrals: nil)
        }
    }
    
    // MARK: - Outgoing Metadata Broadcasts
    
    /// Broadcasts updated track title, artist, and playback state to connected BLE centrals.
    func broadcastMetadata(title: String, artist: String, isPlaying: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let metadataDict: [String: Any] = [
                "title": cleanTitle.isEmpty ? "YT Audio Air" : cleanTitle,
                "artist": cleanArtist.isEmpty ? "YouTube" : cleanArtist,
                "isPlaying": isPlaying
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: metadataDict, options: []),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            
            // Avoid duplicate broadcasts
            guard jsonString != self.currentMetadataJSON else { return }
            self.currentMetadataJSON = jsonString
            
            guard let peripheralManager = self.peripheralManager,
                  let metadataChar = self.metadataCharacteristic else {
                return
            }
            
            let success = peripheralManager.updateValue(jsonData, for: metadataChar, onSubscribedCentrals: nil)
            if success {
                print("[BLEMediaServer] Broadcasted metadata: \(jsonString)")
            } else {
                print("[BLEMediaServer] Update value queued (buffer full).")
            }
        }
    }
}
