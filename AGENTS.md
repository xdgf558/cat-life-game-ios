# 原生 iOS 与 Mac 仓库约定

本文件适用于 `cat-life-game-ios` 全仓库，维护原生 iOS 与 Mac 两个目标。工程位于根目录 `CatLife.xcodeproj`；构建与资源获取统一以 [README.md](README.md) 为入口。

## 开发范围与实现

- 每次开发、修复、重构、代码审查或依赖调整都加载并应用 `$ponytail`，默认 `full` 模式；用户指定其他模式或停用时服从用户。技能位于 `$CODEX_HOME/skills/ponytail/SKILL.md`，未设置时使用 `~/.codex/skills/ponytail/SKILL.md`。
- 采用满足完整需求的最小改动，检查相关调用方、边界和必要验证，保留既有架构，不顺带做全仓重构。
- `CatGameCore` 管玩法、校验和存档；`CatLife/Store` 管状态与持久化协调；`Scene` 管 SpriteKit 展示和互动；`Views` 管共享及 iOS 界面，`CatLifeMac` 管 Mac 桌面界面、窗口和键鼠操作。两端共享 Core、Store 与运行素材；时间结算走现有同步流程，界面不另算奖励或扣费。
- 保持单机本地进度。iOS 与 Mac 使用独立 Bundle ID 和存档目录，不自动同步或覆盖对方进度。用户已明确本轮先做 Mac 核心版，Steam、云存档及冲突处理后续接入；界面如实显示未连接，不模拟云端成功。
- Mac 目标为 `CatLifeMac`，最低 macOS 14，Xcode 选择 `CatLifeMac` scheme 与 My Mac；Bundle ID 为 `com.stationcat.catlife.mac`，Release 存档目录为 `~/Library/Application Support/CatLifeMac/`，Debug 为 `CatLifeMac-Development/`，UI 测试为 `CatLifeMac-UITests/`；游戏加载前须取得目录锁。iOS Bundle ID 仍为 `com.stationcat.catlife.native`。
- 新字段必须兼容已有原生存档，按版本显式迁移并覆盖旧档、损坏数据与失败路径；不放宽校验、不悄悄清零、不编造历史。涉及持久化格式或旧版不认识的数据时检查 schema 并更新迁移保护测试。
- 金币、物品、任务和奖励以保存成功后的已提交状态为准，保存失败不得部分扣费或发布未落盘结果。导入、切猫、换楼层等异步回调继续核对存档代次和场景有效性。
- 用户文案使用现有本地化机制，新增或修改时同步简体中文、繁体中文和英语，检查 key 与格式参数一致。保留大字号、VoiceOver、减少动态效果、现有触控及 Mac 键鼠适配；文本输入和弹窗不得被全局快捷键抢占。
- UI 测试夹具、故障注入、采样计数器和测试启动参数用 `#if DEBUG` 隔离，不编进正式包；勿以隐藏测试按钮取代真实交互验证。

## 本机缓存与验证

- 新建 Xcode DerivedData、Swift build scratch、编译模块缓存和一次性构建目录，统一放在 `/Volumes/AI作品素材/开发缓存/本机编译缓存/`，按项目和用途分目录。源码、发布归档、截图和测试证据沿用项目原有存放策略，不属于此缓存规则。
- 构建前确认 `/Volumes/AI作品素材` 确实已挂载。未挂载时暂停依赖它的构建并说明，不自动回退到本机 `/tmp`、`/private/tmp` 或项目内缓存。保留已有指向外盘的符号链接，不删链接后重建真实本机目录。
- 图片和音频使用 Git LFS；先 `git lfs install`、`git lfs pull --include="CatLife/**,CatLifeMac/**"`，再运行 `python3 -B scripts/check_runtime_assets.py`。仅代码 Core 测试无需运行媒体。
- 按改动执行必要 Core、App、UI 或资源检查。只改文档不要求游戏回归。报告区分已完成、部分完成、故障及后续工作，准确说明所用源码、设备与未验证范围；不得将旧包或旧轮结果计作本轮通过。
- QA 与公开提交脱敏，不提交签名私钥、账号凭据、设备标识、真实玩家存档或本机个人路径；大型原始日志、录屏和归档不淹没源码审查。保留美术、音频来源说明，不因仓库公开而新增素材商用授权。

## 版本、PR 与 TestFlight

- 每次向玩家交付新的更新，必须同时提升发布目标 Info.plist（iOS：`CatLife/Info.plist`；Mac：`CatLifeMac/Info.plist`）的 `CFBundleShortVersionString` 和递增 `CFBundleVersion`，不能只提升构建号。修复或界面微调递增 patch，功能迭代递增 minor；同一次尚未发布更新的调试可保留对外版本号，构建号按需递增，不适用于已交付后的新更新。
- 同步 `CatLife/Views/AppRelease.swift` 的当前历史、`CatLife/Localization/GameStrings+*.swift` 的三语更新说明及版本测试。历史已发布版本、构建号和日期不得回写；第 13 版及更早实际为 `0.1.0`，保留原记录。
- 通常一个版本一个 PR；用户明确要求合并任务时按授权范围整理。开发和必要验证完成后开 PR 供用户审查，明确通过且授权后再合并、归档或上传，不把审查结论自行等同于上传许可。
- 当前开发版本为 **0.24.0（69）Mac 核心版**，尚未上传或发布。iOS 已上传 TestFlight 的版本仍为 **0.23.0（68）**（2026-11-11），沿用原有 App Store Connect 记录；上传、处理完成和测试开放分别确认。
- 用户于 2026-11-04 指定：内测/外测群组、测试者、邀请、Beta Review 与测试分发由用户手动处理，除非再次明确授权。上传成功、Apple 处理完成、审核通过和测试开放须分别记录；上传不得限制为 Internal Only，避免妨碍用户外测。
- 发布归档、上传和真机安装分别记录验证结果；未经授权不重置玩家存档。正式上架前仍需检查更新链接、内部观察入口及密集场景真机性能，不将模拟器通过当作这些事项已完成。
