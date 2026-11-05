import AppKit
import CoreAudio
import AudioToolbox

/// 실제 엔진 (Process Tap 방식).
/// 4단계: 마스터 볼륨 연동. 5단계: 소리 내는 앱 감지. 6단계(앱별 볼륨 적용)는 아직 없음.
/// Core Audio C API는 Swift에서 바로 호출하므로 브릿징 헤더는 없다 (README §6).
@MainActor
final class CoreAudioEngine: AudioEngine {
    private(set) var masterVolume: Float = 0
    private(set) var isMasterMuted = false
    private(set) var apps: [AudioApp] = []
    var onChange: (() -> Void)?

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var watchedProcesses: Set<AudioObjectID> = []
    /// 사용자가 정한 앱별 값. 앱이 소리를 멈췄다 다시 내도 유지된다.
    private var appSettings: [pid_t: (volume: Float, muted: Bool)] = [:]

    init() {
        // 이어폰 연결 등으로 기본 출력 장치가 바뀌면 새 장치에 다시 붙는다
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(system, &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachDefaultDevice() }
        }
        deviceListener = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readMaster() }
        }
        attachDefaultDevice()

        // 프로세스가 생기거나 사라질 때, 각 프로세스가 소리를 내기 시작하거나 멈출 때 목록 갱신
        let processListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readApps() }
        }
        self.processListener = processListener
        addr = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(system, &addr, .main, processListener)
        readApps()
    }

    // MARK: 마스터 볼륨 (4단계)

    func setMasterVolume(_ volume: Float) {
        var v = Float32(volume)
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        readMaster()
    }

    func setMasterMuted(_ muted: Bool) {
        var m: UInt32 = muted ? 1 : 0
        var addr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        readMaster()
    }

    private func attachDefaultDevice() {
        for selector in Self.masterSelectors { listen(selector, on: device, add: false) }
        device = Self.get(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self) ?? AudioObjectID(kAudioObjectUnknown)
        for selector in Self.masterSelectors { listen(selector, on: device, add: true) }
        readMaster()
    }

    /// 볼륨 조절이 없는 장치(HDMI 등)는 읽기가 실패하므로 값을 그대로 둔다.
    private func readMaster() {
        let out = kAudioDevicePropertyScopeOutput
        masterVolume = Self.get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: out, as: Float32.self) ?? masterVolume
        if let m = Self.get(device, kAudioDevicePropertyMute, scope: out, as: UInt32.self) { isMasterMuted = m != 0 }
        onChange?()
    }

    private func listen(_ selector: AudioObjectPropertySelector, on id: AudioObjectID, add: Bool) {
        guard id != kAudioObjectUnknown, let block = deviceListener else { return }
        var addr = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
        if add {
            AudioObjectAddPropertyListenerBlock(id, &addr, .main, block)
        } else {
            AudioObjectRemovePropertyListenerBlock(id, &addr, .main, block)
        }
    }

    private static let masterSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    // MARK: 앱 목록 (5단계)

    private func readApps() {
        let processes = Self.processObjects()
        var byOwner: [pid_t: AudioApp] = [:]

        for process in processes {
            if watchedProcesses.insert(process).inserted, let block = processListener {
                var addr = Self.address(kAudioProcessPropertyIsRunningOutput)
                AudioObjectAddPropertyListenerBlock(process, &addr, .main, block)
            }
            guard Self.get(process, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1,
                  let pid = Self.get(process, kAudioProcessPropertyPID, as: pid_t.self) else { continue }

            // 소리는 보통 헬퍼 프로세스(Safari → WebKit GPU, Chrome Helper)가 내므로 그 프로세스를 띄운 앱 기준으로 묶는다
            let owner = responsiblePID(for: pid)
            guard owner != getpid(), byOwner[owner] == nil else { continue }
            let app = NSRunningApplication(processIdentifier: owner)
            let setting = appSettings[owner] ?? (1, false)
            byOwner[owner] = AudioApp(
                id: owner,
                name: app?.localizedName ?? "PID \(owner)",
                bundleID: app?.bundleIdentifier,
                volume: setting.volume,
                isMuted: setting.muted
            )
        }

        watchedProcesses.formIntersection(processes) // 사라진 프로세스 객체의 리스너는 객체와 함께 없어진다
        apps = byOwner.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        onChange?()
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    // MARK: 앱별 볼륨 (6단계: 아직 소리는 바뀌지 않고 값만 기억)

    // 6단계: 앱별 CATapDescription(.mutedWhenTapped) → AudioHardwareCreateProcessTap
    // → aggregate 장치 → IOProc에서 gain 곱하기. 볼륨 100%이고 음소거가 아니면 탭을 없앤다.
    func setVolume(_ volume: Float, for app: AudioApp.ID) {
        appSettings[app, default: (1, false)].volume = volume
        readApps()
    }

    func setMuted(_ muted: Bool, for app: AudioApp.ID) {
        appSettings[app, default: (1, false)].muted = muted
        readApps()
    }

    // MARK: Core Audio 헬퍼

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// 고정 크기 속성 하나를 읽는다. 실패하면 nil.
    private static func get<T>(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        as _: T.Type
    ) -> T? {
        guard id != kAudioObjectUnknown else { return nil }
        var addr = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.move()
    }
}

// shortcut: 비공개 libSystem 함수. App Store 심사에서는 거절될 수 있음 — App Store 배포 시 부모 PID/번들 ID 매칭으로 교체
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibilityGetPID(_ pid: pid_t) -> pid_t

private func responsiblePID(for pid: pid_t) -> pid_t {
    let owner = responsibilityGetPID(pid)
    return owner > 0 ? owner : pid
}
