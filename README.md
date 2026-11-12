# 打工养猫日记 · 原生 iOS 与 Mac

本仓库维护「打工养猫日记」的原生 iOS 与 Mac 版，采用 SwiftUI、SpriteKit 和共享的 `CatGameCore`，最低 iOS 17、macOS 14；支持简体中文、繁体中文和 English。两端共用玩法、状态协调和美术音频，分别在设备本地保存进度，支持备份导入与导出。

## 当前状态

**0.24.0（69）Mac 核心版已完成开发，待手动验收**。iOS 已上传 TestFlight 的版本仍为 **0.23.0（68）**；69 尚未上传。Steam 接入后续开发。[本版范围与验证记录](docs/releases/0.24.0-mac-core.md)。

## 获取资源与运行（唯一现行入口）

需要 macOS、支持 Swift 6 的 Xcode、Python 3 和 Git LFS。安装 Git LFS 后，从本仓库根目录执行：

```sh
git lfs install
git lfs pull --include="CatLife/**,CatLifeMac/**"
python3 -B scripts/check_runtime_assets.py
```

图片和音频使用 Git LFS。只拿到源码或 LFS 指针文件无法构建可运行的 App；以上命令仅拉取运行所需资源，不要求下载历史 QA 媒体和所有美术源文件。资源检查通过后，打开 **`CatLife.xcodeproj`**：iOS 选择 **`CatLife` scheme** 和 iPhone 模拟器；Mac 选择 **`CatLifeMac` scheme** 和 **My Mac**。模拟器及本机开发构建不要求发布账号；真机或发布签名使用自己的 Team，不要修改已有目标的 Bundle ID。

构建阶段也会执行同一资源检查。遇到缺文件、LFS 指针、无效文件头或清单问题时，按具体错误处理；构建不会自动联网或重写素材。此检查不替代图片解码、听感和真机验收。

## 构建与测试

以下命令均在仓库根目录运行。本机缓存统一放在外置硬盘 `/Volumes/AI作品素材/开发缓存/本机编译缓存/`，先确认硬盘确实已挂载；未挂载时停止，不回退到 `/tmp`、项目内 `.build` 或本机其他目录。使用 Xcode 界面构建时，Derived Data 也应设在此外盘目录。其他开发者可把示例路径换成自己已挂载的外部缓存目录。

```sh
if ! mount | grep -Fq ' on /Volumes/AI作品素材 ('; then
  echo '外置硬盘未挂载，请先连接后再构建。' >&2
  exit 1
fi
catlife_cache='/Volumes/AI作品素材/开发缓存/本机编译缓存/cat-life-game-ios/local'
mkdir -p "$catlife_cache"
```

iOS 模拟器构建：

```sh
xcodebuild build -project CatLife.xcodeproj -scheme CatLife \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$catlife_cache/DerivedData" -jobs 4 \
  CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  SWIFT_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  CODE_SIGNING_ALLOWED=NO
```

Mac 本机构建（产物位于外盘 DerivedData）：

```sh
xcodebuild build -project CatLife.xcodeproj -scheme CatLifeMac \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$catlife_cache/MacDerivedData" -jobs 4 \
  CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  SWIFT_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  CODE_SIGNING_ALLOWED=NO
```

核心逻辑测试不需要图片、音频或模拟器；本地包要求 Swift 6，macOS 测试目标最低 macOS 14：

```sh
CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
SWIFT_MODULECACHE_PATH="$catlife_cache/ModuleCache.noindex" \
SWIFTPM_MODULECACHE_OVERRIDE="$catlife_cache/ModuleCache.noindex" \
swift test --package-path CatGameCore \
  --scratch-path "$catlife_cache/Core" --jobs 4
```

App 测试需要已下载的运行素材和可用模拟器。先用 `xcrun simctl list devices available` 查设备 UDID，将下面的 `<UDID>` 替换为实际值：

```sh
xcodebuild test -project CatLife.xcodeproj -scheme CatLife \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath "$catlife_cache/DerivedData" -jobs 4 \
  -parallel-testing-enabled NO -only-testing:CatLifeTests \
  CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  SWIFT_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  CODE_SIGNING_ALLOWED=NO
```

Mac App 测试使用本机目标及同一套外盘缓存：

```sh
xcodebuild test -project CatLife.xcodeproj -scheme CatLifeMac \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$catlife_cache/MacDerivedData" -jobs 4 \
  -parallel-testing-enabled NO -only-testing:CatLifeMacTests \
  CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  SWIFT_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  CODE_SIGNING_ALLOWED=NO
```

Mac 界面测试需要本机 ad hoc 签名，使用下面的命令；将测试类和方法替换为本次需要验证的目标：

```sh
xcodebuild test -project CatLife.xcodeproj -scheme CatLifeMac \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$catlife_cache/MacDerivedData" -jobs 4 \
  -parallel-testing-enabled NO \
  '-only-testing:CatLifeMacUITests/<测试类>/<方法>' \
  CLANG_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  SWIFT_MODULE_CACHE_PATH="$catlife_cache/ModuleCache.noindex" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Mac UI 测试使用 DEBUG 专用存档、偏好与窗口恢复记录；运行前保存工作，测试会操作前台窗口。上述命令是执行入口，不代表本轮已通过，实际结果以对应 QA 记录为准。

定向 UI 回归使用同一命令，将 `-only-testing:CatLifeTests` 改为 `-only-testing:CatLifeUITests/<测试类>/<方法>`。UI 测试使用专用模拟器与测试存档，勿对玩家真机执行重置夹具。验证记录要区分执行的设备、方法、源码和未覆盖范围，不把历史结果记成本轮重新通过。

## Mac 核心版

桌面界面包含标题、小家、布置、打工、商店、猫咪、猫町和设置八个页面；任务、背包、邻居、医院及备份恢复复用原生面板。支持鼠标与触控板操作、可修改快捷键和窗口设置。

Mac 目标为 `CatLifeMac`，Bundle ID 为 `com.stationcat.catlife.mac`，Release 进度位于 `~/Library/Application Support/CatLifeMac/`；Debug 使用独立的 `CatLifeMac-Development/`，UI 测试使用 `CatLifeMac-UITests/`。与 iOS 的 `com.stationcat.catlife.native` 及其存档目录独立。两端不会自动同步进度，可由玩家使用原生备份转移。

启动会检查已有游戏实例并锁定实际存档目录，避免本版本的多份 App 同时写入。手动验收前请先退出旧试玩包。

Tab、空格和 Return 保留系统焦点操作；游戏确认默认用 ⌘Return，Option+Tab 切换猫咪，Option+空格切换近看，Option+↑/↓ 选择列表。普通方向键只在房间画布聚焦时微调家具；只有微调与列表移动接受长按重复。

本版尚未接入 Steam，界面显示“未连接 Steam”。Steam 云存档、账号和冲突处理待后续配置，不把本地保存显示成云端同步成功。

## 工程与资源维护

通常直接使用已提交的 Xcode 工程。添加 Swift 文件后如需重新生成，安装 Ruby `xcodeproj` gem，再执行 `ruby scripts/generate_project.rb`；生成前也会检查运行素材，重复生成应保持稳定。有意增删运行素材时执行 `python3 -B scripts/check_runtime_assets.py --update-manifest`，将 `scripts/runtime_assets.json`、`scripts/runtime_assets.xcfilelist` 和资源一并提交；普通构建不应改写清单。

| 路径 | 职责 |
| --- | --- |
| `CatLife.xcodeproj` | 双平台工程：iOS scheme 为 `CatLife`，Mac scheme 为 `CatLifeMac` |
| `CatLife/` | iOS 界面及两端共享的 `Store` 状态协调、`Scene` 房间互动、`Localization` 三语和 `Platform` 适配；共享资源位于 `Assets.xcassets`、`Audio` |
| `CatLifeMac/` | Mac App 入口、桌面页面、窗口和键鼠设置；不另写玩法结算 |
| `CatGameCore/` | 独立 Swift 包：玩法、数据校验、存档编解码与迁移，以及核心测试 |
| `CatLifeTests/`、`CatLifeUITests/` | iOS App 逻辑与真实交互回归，测试夹具不得进入 Release |
| `CatLifeMacTests/`、`CatLifeMacUITests/` | Mac 输入、设置、持久化与桌面交互回归 |
| `scripts/` | 工程生成、运行资源检查和维护脚本 |
| `ArtSource/`、`AudioSource/` | 美术及音频制作来源、提示词、清单和处理说明；不参与普通运行资源下载 |
| `Distribution/TestFlight/`、`QA/` | 发布交接、测试内容和历史验证说明；大型原始产物按既有策略保存在仓库外或 LFS |
| `docs/ios-room-home/`、`docs/history/` | 早期房间设计资料和历史文档 |

素材来源以 `ArtSource/`、`AudioSource/` 中各批次记录为准，例如 [build 58 音乐来源](AudioSource/build58/README.md)。公开源码不等于全部美术、参考图和音乐获准自由商用；本次迁移未新增许可证，也不改变原有权利归属。

后续开发与发布遵守 [AGENTS.md](AGENTS.md)：保持原生旧档兼容、三语和可访问性；完成验证后开 PR 供用户审查，用户明确批准后再合并或上传 TestFlight。
