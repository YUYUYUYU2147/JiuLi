# 星愿档案 iPad 原生版

SwiftUI 工程面向 iPadOS 16.0 及以上，可运行于 iPad（第 5 代，iPadOS 16.7.16）。

## 当前版本

- 六款游戏板块与原 APK 图标：原神、星穹铁道、绝区零、鸣潮、异环、崩坏3。
- 读取和合并星愿档案 / UIGF JSON 的抽卡明细；记录保存在应用沙盒，来源总览与逐抽数据分开保存。
- 按物品名、UID、卡池筛选，按时间排序，查看稀有度分布与基础汇总。
- 导出完整兼容档案 JSON，可通过 iPad 文件 App 导入导出。
- iPad 横屏使用分栏导航。

米游社账号登录、官方同步、绝区零官方小程序全历史、鸣潮账号云同步、崩坏3在线读取、多账号凭据管理、恢复点和原 APK 的高级统计尚未移植。需要逐项移植接口与安全凭据处理，不能从 Android APK 自动转换成 iOS 实现。

## 打开工程

在 macOS 上用 Xcode 14 或更新版本打开 `StarWishArchive.xcodeproj`。设置 Apple Development Team 后，选择 iPad 设备编译。最低系统为 iPadOS 16.0。

本仓库执行环境为 Linux，没有 Xcode、iOS SDK 或 Apple 签名证书，因而不能在此生成或签署 IPA。部署到设备需要 Apple 开发者签名与 provisioning profile。
