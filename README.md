# 打工养猫日记 · 原生 iOS

本仓库独立维护「打工养猫日记」的原生 iOS App，采用 SwiftUI、SpriteKit 和本地 Foundation 核心包，最低 iOS 17；支持简体中文、繁体中文和 English。游戏进度保存在设备本地，提供原生备份导入与导出。

## 当前状态

当前版本 **0.23.0（68）**，包含陪伴界面与四向家具布置改版，已上传 TestFlight，Apple 已开始处理。

## 获取资源与运行（唯一现行入口）

需要 macOS、支持 Swift 6 的 Xcode、Python 3 和 Git LFS。安装 Git LFS 后，从本仓库根目录执行：

```sh
git lfs install
git lfs pull --include="CatLife/**"
python3 -B scripts/check_runtime_assets.py
```

图片和音频使用 Git LFS。只拿到源码或 LFS 指针文件无法构建可运行的 App；以上命令仅拉取运行所需资源，不要求下载历史 QA 媒体和所有美术源文件。资源检查通过后，打开 **`CatLife.xcodeproj`**，选择 **`CatLife` scheme** 和 iPhone 模拟器运行。模拟器不需要开发者账号；真机签名使用自己的 Team，不要修改应用的 Bundle ID。

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

模拟器构建：

```sh
xcodebuild build -project CatLife.xcodeproj -scheme CatLife \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$catlife_cache/DerivedData" -jobs 4 \
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

定向 UI 回归使用同一命令，将 `-only-testing:CatLifeTests` 改为 `-only-testing:CatLifeUITests/<测试类>/<方法>`。UI 测试使用专用模拟器与测试存档，勿对玩家真机执行重置夹具。验证记录要区分执行的设备、方法、源码和未覆盖范围，不把历史结果记成本轮重新通过。

## 工程与资源维护

通常直接使用已提交的 Xcode 工程。添加 Swift 文件后如需重新生成，安装 Ruby `xcodeproj` gem，再执行 `ruby scripts/generate_project.rb`；生成前也会检查运行素材，重复生成应保持稳定。有意增删运行素材时执行 `python3 -B scripts/check_runtime_assets.py --update-manifest`，将 `scripts/runtime_assets.json`、`scripts/runtime_assets.xcfilelist` 和资源一并提交；普通构建不应改写清单。

| 路径 | 职责 |
| --- | --- |
| `CatLife.xcodeproj` | 已生成的 App、App 测试与 UI 测试工程，`CatLife` 为运行 scheme |
| `CatLife/` | 原生 App：`Views` 界面、`Store` 状态与存盘协调、`Scene` 房间与互动、`Localization` 三语；资源位于 `Assets.xcassets`、`Audio` |
| `CatGameCore/` | 独立 Swift 包：玩法、数据校验、存档编解码与迁移，以及核心测试 |
| `CatLifeTests/`、`CatLifeUITests/` | App 逻辑与真实交互回归，测试夹具不得进入 Release |
| `scripts/` | 工程生成、运行资源检查和维护脚本 |
| `ArtSource/`、`AudioSource/` | 美术及音频制作来源、提示词、清单和处理说明；不参与普通运行资源下载 |
| `Distribution/TestFlight/`、`QA/` | 发布交接、测试内容和历史验证说明；大型原始产物按既有策略保存在仓库外或 LFS |
| `docs/ios-room-home/`、`docs/history/` | 早期房间设计资料和历史文档 |

素材来源以 `ArtSource/`、`AudioSource/` 中各批次记录为准，例如 [build 58 音乐来源](AudioSource/build58/README.md)。公开源码不等于全部美术、参考图和音乐获准自由商用；本次迁移未新增许可证，也不改变原有权利归属。

后续开发与发布遵守 [AGENTS.md](AGENTS.md)：保持原生旧档兼容、三语和可访问性；完成验证后开 PR 供用户审查，用户明确批准后再合并或上传 TestFlight。
