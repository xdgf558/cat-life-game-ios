# 0.23.0（68）TestFlight 上传记录

2026-11-11 19:43:00（GMT+8），Xcode 返回 `Upload succeeded`、`EXPORT SUCCEEDED` 和 `Uploaded package is processing`。上传成功，Apple 已开始处理；尚未确认处理完成、审核通过或测试开放。未添加内外测群组、测试者或邀请，未提交 Beta Review，由用户手动完成。

[PR #1](https://github.com/xdgf558/cat-life-game-ios/pull/1) 已合并。发布 main 提交为 `cf7e2bfb52cf713d420a775edf58de679ea24613`，完整源码树与审查通过的 `5a276f278686e80d9afe0aae3c4bc30990fc03fd` 完全一致。归档直接从独立 iOS 仓库 main 新建，包含旧镜像家具保留原占地的复审修复。

目标 App ID 为 `6830428076`，Bundle ID 为 `com.stationcat.catlife.native`，版本 `0.23.0（68）`，最低 iOS 17。未新建 App，不自动更改版本或构建号，也未限制为 Internal Only。实际上传包经过 App Store 分发重签，严格签名校验通过，`get-task-allow=false`，无设备列表或企业分发权限，Team 与应用标识一致。

归档有效描述文件、匹配 dSYM、隐私清单、45 份音频、63 个测试启动参数隔离均通过，未链接 XCTest。上传前后 742 项生产源码、配置和资源指纹无变化。实际分发二进制 SHA256 为 `aeb69c299099b61fd9499a45d22d7decbc1970cf3f2955d7f7e1912ce33205aa`。原始归档、上传回执、签名和分发验证均保存在仓库外，公开仓库仅保留脱敏摘要。

沿用同源码在合并前通过的 456 项 Core、419 项 App 与大小屏定向 UI 验证，本次不计作重新执行。完整范围、过程失败及保留限制见 [设计 QA 摘要](design-build68-summary.md)。本版可粘贴的测试重点见 [测试说明](../Distribution/TestFlight/companion-design-0.23.0-68.txt)。

本轮未安装真机、读取或修改玩家存档。密集家具、五猫和三个视角的真机帧率、电量、VoiceOver 与触感仍待实际验证；正式上架前仍需调整 App Store 更新链接与内部观察入口。
