# AppMixer — macOS 메뉴바 앱별 볼륨 믹서 (설계 문서)

> 상태: **6단계까지 완료**. 마스터 볼륨·음소거가 실제 시스템과 동기화되고, 소리를 내는 앱이 목록에 나타나며, 앱별 볼륨·음소거가 실제 소리에 적용됩니다. 남은 것은 7단계(설정 저장, 로그인 시 자동 실행, 서명·공증)입니다.
> UI만 확인하려면 `AppMixer/AppMixerApp.swift`에서 `CoreAudioEngine()`을 `MockAudioEngine()`으로 바꾸세요(한 줄).
>
> 4단계 메모: 마스터 볼륨은 `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`을 `AudioObjectGet/SetPropertyData`로 읽고 씁니다. 같은 속성을 다루는 `AudioHardwareService…` 함수는 deprecated라 쓰지 않았습니다. 오디오 녹음 권한은 필요 없었습니다.
>
> 5단계 메모: 소리는 대부분 헬퍼 프로세스(Chrome Helper, Safari의 WebKit GPU 프로세스)가 냅니다. 그래서 비공개 함수 `responsibility_get_pid_responsible_for_pid`로 그 헬퍼를 띄운 앱을 찾아 하나로 묶습니다. 이 함수는 App Store 심사에서 거절될 수 있으므로, App Store로 배포하려면 다른 방법으로 바꿔야 합니다. 이 단계도 녹음 권한이 필요 없었습니다.
>
> 6단계 메모:
> - 볼륨이 100% 미만이거나 음소거된 앱에만 탭을 만듭니다(`AppTap`). 탭은 앱의 원래 출력을 음소거하고, aggregate 장치의 IO 콜백이 소리 × gain을 실제 스피커로 다시 내보냅니다.
> - 100%로 되돌리고 음소거도 풀면 탭을 없애므로 소리가 원래 경로로 돌아갑니다.
> - 탭 생성이 실패하면 소리는 원래대로 나옵니다. 실패 원인은 `/usr/bin/log show --predicate 'subsystem == "com.dgim9390.AppMixer"' --info --last 10m`로 확인할 수 있습니다. zsh에서는 `log`가 내장 명령과 이름이 겹치므로 반드시 전체 경로로 실행하세요.
> - 출력 장치가 바뀌면 탭을 전부 다시 만듭니다.
> - Swift만으로 충분해서 브릿징 헤더는 여전히 없습니다.
> - 탭의 드리프트 보정 리샘플러는 기본 품질이면 소리가 먹먹해집니다. 그래서 `kAudioSubTapDriftCompensationQualityKey`를 최고 품질로 지정했습니다(탭과 출력이 둘 다 48kHz일 때도 차이가 들렸습니다).
> - 시험한 환경: Chrome + 내장 스피커, AirPods. 아직 시험하지 않은 것: 모노 스피커처럼 채널 수가 다른 장치.
> - 알려진 한계: Chrome은 모든 탭과 웹앱(PWA, 예: YouTube Music)의 소리를 오디오 헬퍼 프로세스 하나에서 냅니다. 그래서 이것들은 "Google Chrome" 한 줄로 묶이고 따로 조절할 수 없습니다. 따로 조절하려면 그중 하나를 다른 브라우저(Safari 등)로 여세요.
>
> 7단계 메모 (일부 완료):
> - 앱별 볼륨·음소거는 bundle ID 기준으로 `UserDefaults`의 `appSettings` 키에 저장됩니다. 그래서 앱이나 AppMixer를 다시 켜도 유지됩니다.
>   - 저장 내용 확인: `defaults read com.dgim9390.AppMixer`
>   - 초기화: `defaults delete com.dgim9390.AppMixer`
> - 패널의 "로그인 시 실행" 체크박스로 로그인 항목에 등록합니다(`SMAppService.mainApp`). 등록하는 앱 위치가 그대로 기억되므로, `/Applications`로 옮긴 뒤에 켜는 것이 좋습니다.
> - 출력 장치 선택 메뉴는 넣지 않았습니다. macOS 제어 센터에서 바꿀 수 있고, AppMixer는 바뀐 장치를 알아서 따라갑니다.
> - 남은 것: 서명·공증.

메뉴바 아이콘을 클릭하면 패널이 열리고, 맨 위에 시스템 마스터 볼륨이, 그 아래에 지금 소리를 내는 앱 목록(아이콘 · 이름 · 볼륨 슬라이더 · 음소거 버튼)이 나옵니다. 윈도우의 볼륨 믹서와 같은 앱입니다.

---

## 1. 오디오 백엔드 비교: Process Tap vs 가상 드라이버

먼저 용어 정리입니다.

- **Core Audio**: macOS 오디오의 가장 낮은 C API 계층입니다. 오디오 장치, 스트림, 볼륨 같은 것을 정수 ID(`AudioObjectID`)와 "속성(property)" 조회·설정으로 다룹니다. 파일 디스크립터와 `ioctl`의 관계와 비슷합니다.
- **HAL(Hardware Abstraction Layer) 플러그인**: `coreaudiod` 데몬이 불러오는 오디오 드라이버 번들입니다. 실제 하드웨어가 없는 "가상 스피커"도 이 방식으로 만듭니다.
- **Process Tap**: macOS 14.2에 추가된 API입니다. 특정 프로세스의 출력 오디오를 가로채서(tap) 우리 앱이 입력처럼 읽을 수 있게 해 줍니다.

| 기준 | A. Core Audio Process Tap | B. 가상 오디오 드라이버 (Background Music 방식) |
|---|---|---|
| 최소 macOS | **14.2 이상** | 10.10 이상 (사실상 제한 없음) |
| 설치 난이도 | 앱만 복사하면 끝. 처음 실행할 때 **"시스템 오디오 녹음" 권한 팝업**에 한 번 동의 | `/Library/Audio/Plug-Ins/HAL`에 드라이버를 설치해야 함 → **관리자 암호가 필요**하고 `coreaudiod`를 재시작해야 함. 지울 때도 같은 절차 |
| 동작 방식 | 앱 소리를 탭으로 가져오면서 원래 출력은 음소거(`.mutedWhenTapped`) → 우리 IO 콜백에서 gain을 곱해 실제 출력 장치로 다시 내보냄 | 시스템 기본 출력을 가상 장치로 바꿔 모든 앱 소리를 받은 뒤, 드라이버 안에서 앱별 gain을 적용하고 실제 장치로 다시 내보냄 |
| 지연 / 안정성 | IO 버퍼 한 단계가 늘어남 (보통 수 ms 수준, 블루투스는 원래 지연이 더 큼). 출력 장치가 바뀌면 탭과 aggregate 장치를 다시 만들어야 함. 비교적 새 API라 사례가 적음 | 지연은 비슷함. 기본 출력 장치를 바꿔치기하므로 앱이 죽으면 소리가 안 나거나, OS 업데이트 후 드라이버가 깨지는 문제가 과거에 자주 보고됨 |
| 라이선스 | Apple 공개 API라 제약 없음 | Background Music은 **GPLv2**. 그 코드를 복사하거나 링크해서 배포하면 **AppMixer 전체를 GPLv2로 공개해야 함**. 피하려면 드라이버를 처음부터 직접 작성해야 함 |
| Swift에서 직접 호출 | **가능**. 전부 C 함수라 Swift에서 바로 부를 수 있고 `CATapDescription`은 Obj-C 클래스라 그대로 쓸 수 있음. 브릿징 헤더가 필요 없음 | 드라이버 자체는 C/C++로 써야 함(별도 번들). 앱 쪽 통신은 Swift로 가능하지만 C++ 코드베이스가 하나 더 생김 |
| 앱 목록 감지 | `kAudioHardwarePropertyProcessObjectList` + 프로세스별 `kAudioProcessPropertyIsRunningOutput`(14.0+)으로 "지금 소리 내는 앱"을 OS가 직접 알려 줌 | 드라이버가 클라이언트 PID를 보고 직접 추적해야 함 |

### 추천: **A. Process Tap**

1. **설치가 쉬움**: 드라이버도 관리자 암호도 없이 앱만 실행하면 됩니다. 메뉴바 유틸리티에는 이 점이 가장 중요합니다.
2. **라이선스 문제가 없음**: GPL 코드에 의존하지 않으므로 배포 방식을 자유롭게 정할 수 있습니다.
3. **Swift만으로 충분함**: 브릿징 헤더도 Obj-C/C++ 스텁도 필요 없습니다(3단계에서 따로 만들지 않습니다. 이유는 §6 참고).
4. **14.2 제약은 문제가 안 됨**: 개발 환경이 macOS 27이고, 메뉴바 UI(`MenuBarExtra`, `@Observable`)도 어차피 macOS 13~14 이상이 필요합니다.

남는 위험(4단계에서 확인할 것):
- 실시간 오디오 스레드에서 실행되는 IO 콜백은 메모리 할당이나 락을 쓰면 안 됩니다. Swift 클로저 안에서는 ARC(참조 카운팅)와 할당이 몰래 일어나지 않도록 `UnsafeMutablePointer`만 다루는 짧은 루프로 작성해야 합니다. Swift로 해결이 안 될 정도로 끊김이 생기면 **그때만** 콜백 하나를 C로 옮기는 것을 검토합니다.
- 출력 장치가 바뀔 때(이어폰 연결 등) 탭을 다시 만드는 처리가 필요합니다.
- 볼륨이 100%이고 음소거도 아닌 앱은 **탭을 만들지 않고** 원래 경로로 그대로 재생해서 지연과 위험을 0으로 둡니다.

---

## 2. 계층 구조

```
┌──────────────────────────────────────────────────────────┐
│ SwiftUI View   MixerView / MasterVolumeRow / AppVolumeRow │  ← AppKit/SwiftUI만 import
└───────────────▲──────────────────────────┬───────────────┘
        상태 관찰 (@Observable)           사용자 조작 (메서드 호출)
┌───────────────┴──────────────────────────▼───────────────┐
│ MixerViewModel  (@MainActor @Observable)                  │  ← 구현체를 모르고 프로토콜만 앎
└───────────────▲──────────────────────────┬───────────────┘
          onAppsChanged 콜백              setVolume / setMuted ...
┌───────────────┴──────────────────────────▼───────────────┐
│ protocol AudioEngine                                      │
├──────────────────────────┬───────────────────────────────┤
│ MockAudioEngine          │ CoreAudioEngine (Swift)        │  ← CoreAudio import는 여기만
│ (가상 앱 3개, 메모리 상태) │   ├ 마스터 볼륨: 기본 출력 장치 속성 │
│                          │   ├ 앱 감지: Process Object 목록  │
│                          │   └ 앱별 볼륨: Process Tap +      │
│                          │     Aggregate Device + IOProc    │
└──────────────────────────┴───────────────▲───────────────┘
                                           │ C API (직접 호출, 브릿징 없음)
                               ┌───────────┴───────────┐
                               │ Core Audio (coreaudiod) │
                               └────────────────────────┘
```

- **ViewModel**: 화면에 보여 줄 상태를 들고 있고, 사용자의 조작을 엔진 호출로 바꾸는 중간 계층입니다. 뷰는 이 상태를 읽기만 하면 자동으로 다시 그려집니다.
- **`@Observable`**: macOS 14+ Swift 매크로입니다. 클래스의 프로퍼티가 바뀌면 그 값을 읽는 SwiftUI 뷰만 다시 그립니다. 예전 방식인 `ObservableObject` + `@Published`보다 코드가 짧습니다.
- **Aggregate Device**: 여러 오디오 장치(여기서는 "탭 입력 + 실제 스피커 출력")를 하나의 가상 장치로 묶은 것입니다. 탭을 읽으려면 탭을 aggregate 장치에 넣고 그 장치에 IO 콜백을 등록해야 합니다.

### 프로토콜 초안

```swift
struct AudioApp: Identifiable, Equatable {
    let id: pid_t            // 프로세스 ID
    let name: String
    let bundleID: String?    // 아이콘은 뷰가 NSWorkspace로 가져옴 (Core Audio와 무관)
    var volume: Float        // 0.0 ... 1.0
    var isMuted: Bool
}

protocol AudioEngine: AnyObject {
    var masterVolume: Float { get }
    var isMasterMuted: Bool { get }
    var apps: [AudioApp] { get }
    var onChange: (() -> Void)? { get set }   // 앱 목록이나 외부 볼륨 변경을 알림

    func setMasterVolume(_ v: Float)
    func setMasterMuted(_ m: Bool)
    func setVolume(_ v: Float, for app: AudioApp.ID)
    func setMuted(_ m: Bool, for app: AudioApp.ID)
}
```

**음소거 해제 시 볼륨 복원**은 `isMuted`를 `volume`과 별도 플래그로 두는 것으로 해결합니다. 음소거해도 `volume`은 그대로 남아 있으므로, 해제하면 이전 값으로 자동 복원됩니다. "이전 볼륨"을 따로 저장할 필요가 없습니다.

---

## 3. 데이터 흐름

**앱 목록 감지 → UI 갱신**
```
coreaudiod ─(속성 변경 리스너: ProcessObjectList / IsRunningOutput)─▶ CoreAudioEngine
   → PID·bundleID 조회, NSRunningApplication으로 이름 확인 → apps 갱신
   → onChange() ─▶ MixerViewModel (메인 스레드로 이동) → @Observable 상태 변경 → 뷰 재렌더
```

**슬라이더 조작 → 볼륨 적용**
```
AppVolumeRow 슬라이더 ─▶ viewModel.setVolume(0.4, for: pid)
   → 상태를 즉시 반영 (UI가 끊김 없이 따라오도록)
   → engine.setVolume(0.4, for: pid)
       → 해당 앱 탭이 없으면 생성 (CATapDescription → AudioHardwareCreateProcessTap
         → aggregate 장치 생성 → IOProc 등록 → 시작)
       → gain 값을 원자적 변수에 저장 → 다음 오디오 버퍼부터 샘플 × 0.4
```

**마스터 볼륨**은 탭 없이 기본 출력 장치의 볼륨 속성(`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`)을 읽고 쓰기만 합니다. 키보드 볼륨 키로 바뀐 값도 리스너로 받아서 슬라이더에 반영합니다.

---

## 4. 디렉토리 구조 (2·3단계에서 생성)

```
AppMixer/
├── README.md                 이 문서 + 빌드 방법
├── project.yml               XcodeGen 설정. .xcodeproj는 여기서 생성 (git에 넣지 않음)
├── AppMixer/
│   ├── AppMixerApp.swift     @main 진입점. MenuBarExtra 선언, 엔진 주입 (교체 지점 한 줄)
│   ├── Views/
│   │   ├── MixerView.swift   패널 전체: 마스터 행 + 구분선 + 앱 행 리스트
│   │   └── VolumeRow.swift   아이콘·이름·슬라이더·음소거 버튼 한 줄 (마스터/앱 공용)
│   ├── MixerViewModel.swift  @Observable 상태 + 사용자 조작 → 엔진 호출
│   ├── Audio/
│   │   ├── AudioEngine.swift       프로토콜 + AudioApp 모델
│   │   ├── MockAudioEngine.swift   Spotify / Safari / Discord 가상 앱
│   │   └── CoreAudioEngine.swift   실제 구현 (3단계: 빈 껍데기, 4단계 이후 구현)
│   ├── Info.plist            XcodeGen이 생성 (LSUIElement, 권한 문구 포함)
│   └── AppMixer.entitlements
└── AppMixerTests/
    └── MixerViewModelTests.swift   Mock 엔진으로 음소거/복원 로직 검증
```

뷰와 ViewModel은 `import SwiftUI`/`AppKit`만 하고, `CoreAudio`/`AudioToolbox` import는 `CoreAudioEngine.swift`에만 둡니다(완료 기준 4번).

---

## 5. UI 방식: `MenuBarExtra(.window)`

- `MenuBarExtra`는 SwiftUI로 메뉴바 아이콘을 만드는 Scene입니다(macOS 13+). 기본 `.menu` 스타일은 일반 메뉴라 슬라이더가 제대로 동작하지 않지만, **`.menuBarExtraStyle(.window)`**를 쓰면 팝오버 같은 패널 안에 임의의 SwiftUI 뷰를 넣을 수 있습니다. 슬라이더와 버튼에는 이것으로 충분하므로 **이 방식을 채택합니다.**
- 대안인 `NSStatusItem + NSPopover`(AppKit)는 패널 크기·위치를 세밀하게 조절하거나 우클릭 메뉴를 따로 두고 싶을 때만 필요합니다. 지금은 쓰지 않고, 부족한 점이 생기면 그때 바꿉니다(뷰는 그대로 재사용 가능).
- **Dock 아이콘 숨기기**: Info.plist에 `LSUIElement = YES`를 넣으면 Dock과 앱 전환기(⌘Tab)에 나타나지 않는 "에이전트 앱"이 됩니다.

---

## 6. 권한 · 엔타이틀먼트

- **앱 번들(.app)**: 실행 파일, Info.plist(앱 메타데이터), 리소스를 담은 폴더입니다. Finder에서는 파일 하나처럼 보입니다.
- **엔타이틀먼트**: 코드 서명에 포함되는 "이 앱이 이런 기능을 쓴다"는 선언입니다. 샌드박스, 카메라 같은 기능을 켤 때 씁니다.
- **TCC**: macOS의 개인정보 권한 시스템입니다(시스템 설정 → 개인정보 보호 및 보안).

| 항목 | 값 | 이유 |
|---|---|---|
| `LSUIElement` (Info.plist) | `YES` | Dock 아이콘 없는 메뉴바 전용 앱 |
| `NSAudioCaptureUsageDescription` (Info.plist) | "앱별 볼륨을 조절하려면 각 앱의 오디오를 가져와야 합니다." | Process Tap은 다른 앱의 소리를 "녹음"하는 것으로 취급되어 TCC 동의가 필요합니다. 이 문구가 없으면 권한 요청 없이 탭이 실패합니다 |
| App Sandbox | **끔** | 탭 + aggregate 장치를 만드는 앱은 샌드박스 밖에서 실행하는 사례가 대부분이고, 샌드박스 안에서 동작이 보장되는지는 문서가 불분명합니다. App Store가 아닌 Developer ID 서명 + 공증(notarization)으로 배포한다고 가정합니다. 4단계에서 샌드박스 켠 상태도 한 번 시험해 보고 결과를 여기에 기록합니다 |
| Hardened Runtime | 켬 | 공증을 받으려면 필수입니다. 오디오 *입력* 장치(마이크)를 쓰지 않으므로 `com.apple.security.device.audio-input`은 필요 없을 것으로 예상하고, 4단계에서 확인합니다 |
| 브릿징 헤더 | **만들지 않음** | 사용하는 API(`AudioObjectGetPropertyData`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice`, `AudioDeviceCreateIOProcIDWithBlock`, `CATapDescription`)가 모두 SDK 모듈로 Swift에 노출되어 있습니다. C 코드를 따로 둘 이유가 없습니다 |

개발 중에는 "Sign to Run Locally"(로컬 임시 서명)로 충분합니다. 다만 TCC 권한은 서명 단위로 기억되므로, 임시 서명이 바뀌면 권한 팝업이 다시 뜰 수 있습니다. 4단계부터는 Xcode에서 개인 Apple ID 팀으로 서명하는 것을 권장합니다.

---

## 7. 로드맵

| 단계 | 내용 | 완료 기준 |
|---|---|---|
| 1 | 이 설계 문서 | 사용자 확인 |
| 2 | XcodeGen 프로젝트, `AudioEngine` 프로토콜, `MockAudioEngine`, `MixerViewModel`, SwiftUI 패널 | `xcodebuild` 성공, Dock 아이콘 없음, Mock 앱 3개 조작이 상태에 반영됨 |
| 3 | `CoreAudioEngine` 빈 껍데기, `AppMixerApp`에서 한 줄로 Mock/실제 교체 | 빌드 성공, 교체해도 컴파일됨 |
| 4 | 마스터 볼륨 실제 연동 (기본 출력 장치 볼륨/음소거 + 변경 리스너) | 볼륨 키와 슬라이더가 서로 동기화됨 |
| 5 | 앱 목록 감지 (Process Object 목록 + IsRunningOutput, 앱 이름·아이콘) | 소리를 내는 앱만 목록에 나타나고 사라짐 |
| 6 | 앱별 볼륨 (Process Tap + aggregate + IOProc gain, 출력 장치 변경 시 재구성) | 실제 앱 소리가 슬라이더에 따라 바뀜, 끊김 없음 |
| 7 | 마무리: 볼륨 설정 저장, 로그인 시 자동 실행(`SMAppService`), 서명·공증 | 다른 Mac에서 설치해 실행 가능 |

---

## 빌드 방법

`.xcodeproj`, `Info.plist`, `.entitlements`는 모두 `project.yml`에서 생성됩니다. 직접 고치지 말고 `project.yml`을 수정한 뒤 다시 생성하세요.

```bash
brew install xcodegen                       # 처음 한 번
xcodegen generate                           # project.yml → AppMixer.xcodeproj
xcodebuild -project AppMixer.xcodeproj -scheme AppMixer -configuration Debug -derivedDataPath build build
xcodebuild -project AppMixer.xcodeproj -scheme AppMixer -derivedDataPath build test
open build/Build/Products/Debug/AppMixer.app
```

실행하면 메뉴바에 슬라이더 아이콘(☰ 모양)만 나타납니다. 종료하려면 패널 아래쪽의 "AppMixer 종료"를 누르세요.

Mock 단계의 아이콘: Mock 앱에도 실제 bundle ID를 넣어 두었습니다. 그 앱이 설치되어 있으면 진짜 아이콘이, 없으면 SF Symbol(`app.fill`)이 표시됩니다. 실제 엔진에서도 같은 코드를 그대로 씁니다.
