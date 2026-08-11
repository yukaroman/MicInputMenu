import CoreAudio
import Foundation

enum AudioInputDeviceKind: String {
    case builtIn
    case bluetooth
    case usb
    case phone
    case wireless
    case aggregate
    case virtual
    case other

    var symbolName: String {
        switch self {
        case .builtIn: return "macbook"
        case .bluetooth: return "airpodspro"
        case .usb: return "cable.connector"
        case .phone: return "iphone"
        case .wireless: return "wifi"
        case .aggregate: return "square.stack.3d.up"
        case .virtual: return "app.connected.to.app.below.fill"
        case .other: return "mic"
        }
    }

    func statusSymbolName(isMuted: Bool) -> String {
        if isMuted {
            return "mic.slash.fill"
        }

        switch self {
        case .builtIn, .other:
            return "mic.fill"
        case .bluetooth:
            return "airpodspro"
        case .usb:
            return "cable.connector"
        case .phone:
            return "iphone"
        case .wireless:
            return "wifi"
        case .aggregate:
            return "square.stack.3d.up"
        case .virtual:
            return "app.connected.to.app.below.fill"
        }
    }

    static func classify(transportType: UInt32) -> AudioInputDeviceKind {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            return .usb
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return .phone
        case kAudioDeviceTransportTypeAirPlay:
            return .wireless
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .other
        }
    }
}

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let kind: AudioInputDeviceKind
}

struct AudioInputControlState {
    let volume: Float?
    let canSetVolume: Bool
    let isMuted: Bool?
    let canSetMute: Bool
}

enum CoreAudioInputError: LocalizedError {
    case operationFailed(operation: String, status: OSStatus)
    case deviceUnavailable(AudioDeviceID)
    case controlUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .operationFailed(operation, status):
            return "\(operation) (Core Audio error \(status))"
        case let .deviceUnavailable(deviceID):
            return "Input device \(deviceID) is no longer available."
        case let .controlUnavailable(control):
            return "This input device does not provide a writable \(control) control."
        }
    }
}

final class CoreAudioInputService {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var observedSystemAddresses: [AudioObjectPropertyAddress] = []
    private var observedDeviceID: AudioDeviceID?
    private var observedDeviceAddresses: [AudioObjectPropertyAddress] = []

    deinit {
        stopObserving()
    }

    func inputDevices() throws -> [AudioInputDevice] {
        var address = Self.devicesAddress
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw CoreAudioInputError.operationFailed(
                operation: "Read audio device list size",
                status: status
            )
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = deviceIDs.withUnsafeMutableBytes { buffer in
            var mutableSize = dataSize
            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &mutableSize,
                buffer.baseAddress!
            )
        }
        guard status == noErr else {
            throw CoreAudioInputError.operationFailed(
                operation: "Read audio device list",
                status: status
            )
        }

        return deviceIDs
            .filter { inputChannelCount(deviceID: $0) > 0 }
            .compactMap { deviceID in
                guard let name = stringProperty(
                    deviceID: deviceID,
                    selector: kAudioObjectPropertyName
                ) else {
                    return nil
                }

                let uid = stringProperty(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                ) ?? String(deviceID)
                let transportType = uint32Property(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyTransportType,
                    scope: kAudioObjectPropertyScopeGlobal,
                    element: kAudioObjectPropertyElementMain
                ) ?? kAudioDeviceTransportTypeUnknown

                return AudioInputDevice(
                    id: deviceID,
                    uid: uid,
                    name: name,
                    transportType: transportType,
                    kind: .classify(transportType: transportType)
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func defaultInputDeviceID() throws -> AudioDeviceID? {
        var address = Self.defaultInputAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw CoreAudioInputError.operationFailed(
                operation: "Read default input device",
                status: status
            )
        }

        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        let availableIDs = Set(try inputDevices().map(\.id))
        guard availableIDs.contains(deviceID) else {
            throw CoreAudioInputError.deviceUnavailable(deviceID)
        }

        var address = Self.defaultInputAddress
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard status == noErr else {
            throw CoreAudioInputError.operationFailed(
                operation: "Set default input device",
                status: status
            )
        }
    }

    func inputControlState(deviceID: AudioDeviceID) -> AudioInputControlState {
        let readableVolumeElements = readableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar
        )
        let volumes = readableVolumeElements.compactMap {
            float32Property(
                deviceID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: $0
            )
        }
        let volume = volumes.isEmpty
            ? nil
            : volumes.reduce(0, +) / Float(volumes.count)

        let readableMuteElements = readableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyMute
        )
        let muteValues = readableMuteElements.compactMap {
            uint32Property(
                deviceID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeInput,
                element: $0
            )
        }
        let isMuted = muteValues.isEmpty ? nil : muteValues.allSatisfy { $0 != 0 }

        return AudioInputControlState(
            volume: volume,
            canSetVolume: !writableElements(
                deviceID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar
            ).isEmpty,
            isMuted: isMuted,
            canSetMute: !writableElements(
                deviceID: deviceID,
                selector: kAudioDevicePropertyMute
            ).isEmpty
        )
    }

    func setInputVolume(_ volume: Float, deviceID: AudioDeviceID) throws {
        let elements = writableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar
        )
        guard !elements.isEmpty else {
            throw CoreAudioInputError.controlUnavailable("volume")
        }

        let clampedVolume = min(max(volume, 0), 1)
        try setFloat32Property(
            clampedVolume,
            deviceID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            elements: elements,
            operation: "Set input volume"
        )
    }

    func setInputMuted(_ isMuted: Bool, deviceID: AudioDeviceID) throws {
        let elements = writableElements(
            deviceID: deviceID,
            selector: kAudioDevicePropertyMute
        )
        guard !elements.isEmpty else {
            throw CoreAudioInputError.controlUnavailable("mute")
        }

        var lastError: OSStatus = noErr
        var didSetValue = false
        for element in elements {
            var address = inputAddress(
                selector: kAudioDevicePropertyMute,
                element: element
            )
            var value: UInt32 = isMuted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            )
            if status == noErr {
                didSetValue = true
            } else {
                lastError = status
            }
        }

        guard didSetValue else {
            throw CoreAudioInputError.operationFailed(
                operation: "Set input mute",
                status: lastError
            )
        }
    }

    func startObservingChanges(_ handler: @escaping () -> Void) {
        guard listenerBlock == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshObservedInputDevice()
            handler()
        }
        listenerBlock = block

        addListener(
            objectID: systemObject,
            address: Self.defaultInputAddress,
            storingIn: &observedSystemAddresses
        )
        addListener(
            objectID: systemObject,
            address: Self.devicesAddress,
            storingIn: &observedSystemAddresses
        )
        refreshObservedInputDevice()
    }

    func stopObserving() {
        guard let block = listenerBlock else { return }

        removeObservedDeviceListeners(block: block)
        for storedAddress in observedSystemAddresses {
            var address = storedAddress
            AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &address,
                DispatchQueue.main,
                block
            )
        }

        observedSystemAddresses.removeAll()
        listenerBlock = nil
    }

    private func refreshObservedInputDevice() {
        guard let block = listenerBlock else { return }
        let defaultDeviceID = (try? defaultInputDeviceID()) ?? nil
        let alreadyObserving = observedDeviceID == defaultDeviceID
            && (defaultDeviceID == nil || !observedDeviceAddresses.isEmpty)
        guard !alreadyObserving else { return }

        removeObservedDeviceListeners(block: block)
        guard let defaultDeviceID else { return }

        observedDeviceID = defaultDeviceID
        for address in observationAddresses(deviceID: defaultDeviceID) {
            addListener(
                objectID: defaultDeviceID,
                address: address,
                storingIn: &observedDeviceAddresses
            )
        }
    }

    private func observationAddresses(deviceID: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            inputAddress(
                selector: kAudioDevicePropertyStreamConfiguration,
                element: kAudioObjectPropertyElementMain
            ),
            inputAddress(
                selector: kAudioDevicePropertyDataSource,
                element: kAudioObjectPropertyElementMain
            )
        ]

        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in observableElements(deviceID: deviceID, selector: selector) {
                addresses.append(inputAddress(selector: selector, element: element))
            }
        }

        var uniqueAddresses: [AudioObjectPropertyAddress] = []
        for address in addresses {
            var mutableAddress = address
            guard AudioObjectHasProperty(deviceID, &mutableAddress) else { continue }
            if !uniqueAddresses.contains(where: { Self.sameAddress($0, address) }) {
                uniqueAddresses.append(address)
            }
        }
        return uniqueAddresses
    }

    private func observableElements(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        var elements: [AudioObjectPropertyElement] = []
        if hasProperty(deviceID: deviceID, selector: selector, element: 0) {
            elements.append(0)
        }

        let channelCount = inputChannelCount(deviceID: deviceID)
        if channelCount > 0 {
            for channel in 1...channelCount {
                let element = AudioObjectPropertyElement(channel)
                if hasProperty(deviceID: deviceID, selector: selector, element: element) {
                    elements.append(element)
                }
            }
        }
        return elements
    }

    private func addListener(
        objectID: AudioObjectID,
        address storedAddress: AudioObjectPropertyAddress,
        storingIn addresses: inout [AudioObjectPropertyAddress]
    ) {
        guard let block = listenerBlock else { return }
        var address = storedAddress
        let status = AudioObjectAddPropertyListenerBlock(
            objectID,
            &address,
            DispatchQueue.main,
            block
        )
        if status == noErr {
            addresses.append(storedAddress)
        }
    }

    private func removeObservedDeviceListeners(
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        if let observedDeviceID {
            for storedAddress in observedDeviceAddresses {
                var address = storedAddress
                AudioObjectRemovePropertyListenerBlock(
                    observedDeviceID,
                    &address,
                    DispatchQueue.main,
                    block
                )
            }
        }
        observedDeviceAddresses.removeAll()
        observedDeviceID = nil
    }

    private static func sameAddress(
        _ first: AudioObjectPropertyAddress,
        _ second: AudioObjectPropertyAddress
    ) -> Bool {
        first.mSelector == second.mSelector
            && first.mScope == second.mScope
            && first.mElement == second.mElement
    }

    private func inputChannelCount(deviceID: AudioDeviceID) -> Int {
        var address = inputAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            element: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return 0
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        var mutableSize = dataSize
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &mutableSize,
            rawBuffer
        ) == noErr else {
            return 0
        }

        let audioBufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func readableElements(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        if hasProperty(deviceID: deviceID, selector: selector, element: 0) {
            return [0]
        }

        let channelCount = inputChannelCount(deviceID: deviceID)
        guard channelCount > 0 else { return [] }
        return (1...channelCount).compactMap { channel in
            let element = AudioObjectPropertyElement(channel)
            return hasProperty(deviceID: deviceID, selector: selector, element: element)
                ? element
                : nil
        }
    }

    private func writableElements(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        if isPropertySettable(deviceID: deviceID, selector: selector, element: 0) {
            return [0]
        }

        let channelCount = inputChannelCount(deviceID: deviceID)
        guard channelCount > 0 else { return [] }
        return (1...channelCount).compactMap { channel in
            let element = AudioObjectPropertyElement(channel)
            return isPropertySettable(
                deviceID: deviceID,
                selector: selector,
                element: element
            ) ? element : nil
        }
    }

    private func hasProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = inputAddress(selector: selector, element: element)
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func isPropertySettable(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = inputAddress(selector: selector, element: element)
        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }

    private func float32Property(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var address = inputAddress(selector: selector, element: element)
        var value: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func setFloat32Property(
        _ value: Float,
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        elements: [AudioObjectPropertyElement],
        operation: String
    ) throws {
        var lastError: OSStatus = noErr
        var didSetValue = false

        for element in elements {
            var address = inputAddress(selector: selector, element: element)
            var mutableValue = Float32(value)
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &mutableValue
            )
            if status == noErr {
                didSetValue = true
            } else {
                lastError = status
            }
        }

        guard didSetValue else {
            throw CoreAudioInputError.operationFailed(
                operation: operation,
                status: lastError
            )
        }
    }

    private func uint32Property(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let valuePointer = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        valuePointer.initialize(to: nil)
        defer {
            valuePointer.deinitialize(count: 1)
            valuePointer.deallocate()
        }

        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            UnsafeMutableRawPointer(valuePointer)
        )

        guard status == noErr, let value = valuePointer.pointee else { return nil }
        return value.takeUnretainedValue() as String
    }

    private func inputAddress(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
