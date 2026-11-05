import AppKit
import CoreAudio
import AudioToolbox
import os

private let log = Logger(subsystem: "com.dgim9390.AppMixer", category: "engine")

/// 실제 엔진 (Process Tap 방식).
/// 4단계: 마스터 볼륨 연동. 5단계: 소리 내는 앱 감지. 6단계: 앱별 볼륨(Process Tap + gain).
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
    /// 사용자가 정한 앱별 값. bundle ID로 저장해서 앱이나 AppMixer를 다시 켜도 유지된다.
    private var appSettings: [String: AppSetting] = CoreAudioEngine.loadSettings()
    /// 앱(소유 PID)별 Core Audio 프로세스 객체. Chrome처럼 헬퍼가 여러 개면 여러 개.
    private var processesByOwner: [pid_t: [AudioObjectID]] = [:]
    private var taps: [pid_t: AppTap] = [:]

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

        // 탭은 출력 장치에 묶여 있으므로 장치가 바뀌면 전부 새로 만든다
        taps.removeAll()
        syncTaps()
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
        var owners: [pid_t: [AudioObjectID]] = [:]

        for process in processes {
            if watchedProcesses.insert(process).inserted, let block = processListener {
                var addr = Self.address(kAudioProcessPropertyIsRunningOutput)
                AudioObjectAddPropertyListenerBlock(process, &addr, .main, block)
            }
            guard let pid = Self.get(process, kAudioProcessPropertyPID, as: pid_t.self) else { continue }

            // 소리는 보통 헬퍼 프로세스(Safari → WebKit GPU, Chrome Helper)가 내므로 그 프로세스를 띄운 앱 기준으로 묶는다
            let owner = responsiblePID(for: pid)
            guard owner != getpid() else { continue }
            owners[owner, default: []].append(process)

            // 탭이 걸린 앱은 잠깐 출력이 멈춰도 목록에 남긴다 (사라졌다 나타났다 반복 방지)
            let running = Self.get(process, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            guard running || taps[owner] != nil, byOwner[owner] == nil else { continue }
            let app = NSRunningApplication(processIdentifier: owner)
            let setting = appSettings[Self.settingKey(bundleID: app?.bundleIdentifier, pid: owner)] ?? AppSetting()
            byOwner[owner] = AudioApp(
                id: owner,
                name: app?.localizedName ?? "PID \(owner)",
                bundleID: app?.bundleIdentifier,
                volume: setting.volume,
                isMuted: setting.muted
            )
        }

        watchedProcesses.formIntersection(processes) // 사라진 프로세스 객체의 리스너는 객체와 함께 없어진다
        processesByOwner = owners
        apps = byOwner.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        syncTaps()
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

    // MARK: 앱별 볼륨 (6단계)

    /// 볼륨 100%이고 음소거가 아닌 앱은 탭 없이 원래 경로로 재생한다 (지연·위험 0).
    private func syncTaps() {
        // apps에는 readApps가 이미 저장된 설정을 채워 두었다
        var wanted: [pid_t: Float] = [:]
        // 슬라이더 값의 제곱을 gain으로: 귀는 소리 크기를 로그로 느껴서 직선이면 50%에서도 거의 안 줄어든 것처럼 들린다
        for app in apps where app.volume < 1 || app.isMuted { wanted[app.id] = app.isMuted ? 0 : app.volume * app.volume }

        // 더 필요 없거나, 앱의 프로세스 구성이 바뀐(새 헬퍼가 생긴) 탭은 없앤다
        for (owner, tap) in taps where wanted[owner] == nil || tap.processes != Set(processesByOwner[owner] ?? []) {
            taps[owner] = nil
            log.info("tap 제거: pid \(owner)")
        }

        for (owner, gain) in wanted {
            if let tap = taps[owner] {
                tap.gain.pointee = gain
            } else if let processes = processesByOwner[owner], !processes.isEmpty,
                      let uid = Self.get(device, kAudioDevicePropertyDeviceUID, as: Unmanaged<CFString>.self)?.takeRetainedValue() {
                taps[owner] = AppTap(processes: processes, outputUID: uid as String, gain: gain)
                log.info("tap 생성 \(self.taps[owner] == nil ? "실패" : "성공"): pid \(owner)")
            }
        }
    }

    func setVolume(_ volume: Float, for app: AudioApp.ID) {
        updateSetting(for: app) { $0.volume = volume }
    }

    func setMuted(_ muted: Bool, for app: AudioApp.ID) {
        updateSetting(for: app) { $0.muted = muted }
    }

    // MARK: 설정 저장

    private func updateSetting(for pid: pid_t, _ change: (inout AppSetting) -> Void) {
        guard let app = apps.first(where: { $0.id == pid }) else { return }
        change(&appSettings[Self.settingKey(bundleID: app.bundleID, pid: pid), default: AppSetting()])
        // bundle ID가 없는 프로세스는 PID가 매번 바뀌므로 저장하지 않는다
        let persistent = appSettings.filter { !$0.key.hasPrefix("pid:") && $0.value != AppSetting() }
        UserDefaults.standard.set(try? JSONEncoder().encode(persistent), forKey: Self.settingsKey)
        readApps()
    }

    private static let settingsKey = "appSettings"

    private static func settingKey(bundleID: String?, pid: pid_t) -> String { bundleID ?? "pid:\(pid)" }

    private static func loadSettings() -> [String: AppSetting] {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: AppSetting].self, from: data)) ?? [:]
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

private struct AppSetting: Codable, Equatable {
    var volume: Float = 1
    var muted = false
}

/// 한 앱의 Process Tap + aggregate 장치 + IO 콜백. 객체가 해제되면(deinit) 전부 정리되고 앱 소리는 원래대로 돌아온다.
private final class AppTap {
    let processes: Set<AudioObjectID>
    // shortcut: 메인 스레드 쓰기 / 오디오 스레드 읽기를 정렬된 Float 하나로 공유 (arm64에서 찢어지지 않음).
    // 최소 지원을 macOS 15로 올리면 Synchronization.Atomic으로 교체
    let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(processes: [AudioObjectID], outputUID: String, gain initial: Float) {
        self.processes = Set(processes)
        gain.initialize(to: initial)

        // 앱 소리를 가로채면서 원래 출력은 음소거
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { log.error("AudioHardwareCreateProcessTap 실패: \(status)"); return nil }

        // 탭(입력) + 실제 스피커(출력)를 묶은 비공개 장치
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppMixer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            // 기본 품질 리샘플러는 고음이 깎여 먹먹하게 들린다 → 최고 품질
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID)
        guard status == noErr else { log.error("AudioHardwareCreateAggregateDevice 실패: \(status)"); return nil }

        // 탭과 출력의 샘플레이트가 다르면 리샘플링이 일어난다 (음질 문제 진단용)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format)
        var deviceRate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        addr.mSelector = kAudioDevicePropertyNominalSampleRate
        AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, &deviceRate)
        log.notice("tap \(format.mSampleRate, privacy: .public)Hz \(format.mChannelsPerFrame, privacy: .public)ch → 출력 \(deviceRate, privacy: .public)Hz")

        // 큐 nil = HAL의 실시간 오디오 스레드에서 바로 호출
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, Self.ioBlock(gain: gain))
        guard status == noErr else { log.error("AudioDeviceCreateIOProcIDWithBlock 실패: \(status)"); return nil }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { log.error("AudioDeviceStart 실패: \(status)"); return nil }
    }

    deinit {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        gain.deallocate()
    }

    /// 실시간 스레드에서 돈다: 할당·락·로그 금지. 입력(탭) 샘플 × gain → 출력.
    /// HAL IOProc 데이터는 항상 Float32. 채널 수가 다르면 입력 채널을 돌려 쓴다 (스테레오 → 모노는 왼쪽만).
    private static func ioBlock(gain: UnsafeMutablePointer<Float>) -> AudioDeviceIOBlock {
        { _, inputList, _, outputList, _ in
            let g = gain.pointee
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputList))
            let outputs = UnsafeMutableAudioBufferListPointer(outputList)

            var inChannels = 0
            for b in inputs { inChannels += Int(b.mNumberChannels) }

            var outChannel = 0
            for out in outputs {
                guard let dst = out.mData?.assumingMemoryBound(to: Float.self), out.mNumberChannels > 0 else { continue }
                let dstStride = Int(out.mNumberChannels)
                let dstFrames = Int(out.mDataByteSize) / (MemoryLayout<Float>.size * dstStride)

                for c in 0..<dstStride {
                    // 이 출력 채널에 대응하는 입력 버퍼와 그 안의 채널 위치 찾기
                    var src: UnsafeMutablePointer<Float>?
                    var srcStride = 1, srcOffset = 0, srcFrames = 0
                    if inChannels > 0 {
                        var want = (outChannel + c) % inChannels
                        for b in inputs {
                            let n = Int(b.mNumberChannels)
                            if want < n {
                                src = b.mData?.assumingMemoryBound(to: Float.self)
                                srcStride = n
                                srcOffset = want
                                srcFrames = Int(b.mDataByteSize) / (MemoryLayout<Float>.size * n)
                                break
                            }
                            want -= n
                        }
                    }
                    let frames = src == nil ? 0 : min(dstFrames, srcFrames)
                    if let src {
                        for f in 0..<frames { dst[f * dstStride + c] = src[f * srcStride + srcOffset] * g }
                    }
                    for f in frames..<dstFrames { dst[f * dstStride + c] = 0 }
                }
                outChannel += dstStride
            }
        }
    }
}

// shortcut: 비공개 libSystem 함수. App Store 심사에서는 거절될 수 있음 — App Store 배포 시 부모 PID/번들 ID 매칭으로 교체
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibilityGetPID(_ pid: pid_t) -> pid_t

private func responsiblePID(for pid: pid_t) -> pid_t {
    let owner = responsibilityGetPID(pid)
    return owner > 0 ? owner : pid
}
