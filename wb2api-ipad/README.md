# wb2api iPad 本机版

这个工程把 wb2api 1.16.0 的 Python 后端、SQLite 数据库和管理网页放进 iPad 应用。应用启动后在 iPad 本机启动 API，并在内嵌 WebView 打开管理台。API 只监听 iPad 本机回环地址。部署目标是 iPadOS 16.0，支持 iPad 第 5 代的 iPadOS 16.7.16。

## 工程内容

- `src/wb2api/app.py` 提供 Toga iPad 界面、WebView 和本机服务启动。
- `src/wb2api/ios_runtime.py` 在 App Support 目录保存配置、数据库和日志，并启动 Uvicorn。
- `src/wb2api/backend/` 包含从上游 1.16.0 源码暂存的 FastAPI 后端与网页资源。
- `pyproject.toml` 设定 iPadOS 最低版本和后端 Python 依赖。

Python 后端和管理网页从 wb2api 官方仓库 `1.16.0` 暂存脚本生成。APK 内的 Android ARM64 Python/OpenSSL/SQLite 二进制没有放入工程。

## 后台运行

iPadOS 可能在应用切到后台或设备锁屏后暂停普通应用。本机 API 的可用时间按应用前台运行期间设计。重新打开应用后，服务会恢复检查并启动。

## 用 Windows 电脑安装

不需要自己买 Mac。仓库内的 `.github/workflows/build-ios.yml` 会让 GitHub 的 macOS 云端电脑编译未签名 IPA。

1. 在 GitHub 新建一个公开仓库，把本工程目录里的**全部内容**上传到仓库根目录，确认 `.github/workflows/build-ios.yml` 位于根目录下。公开仓库的 macOS GitHub Actions 标准运行时间免费。
2. 打开仓库的 **Actions**，运行 **Build unsigned iPad IPA**。成功后下载 `wb2api-1.16.0-unsigned-ipa` artifact 并解压，得到 `.ipa`。
3. 在 Windows 电脑按 AltStore 官方指南安装 AltServer、Apple 官网的 iTunes 与 iCloud 桌面版，将 iPad 用 USB 连接电脑并信任设备。
4. 用 AltServer 在 iPad 上安装 AltStore。在 iPad 设置里开启“开发者模式”。
5. 把 `.ipa` 放入 iPad 的“文件”App，在 AltStore 的 **My Apps** 页面点 `+`，选择 IPA 安装。

免费 Apple 账号签名的侧载应用需要大约每 7 天用 AltServer 刷新一次。该工程目录中的自动构建文件只负责编译和打包，AltStore 在安装时用你的 Apple 账号签名。

AltStore 官方 Windows 指南：https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

如果没有可用的 Windows 电脑，云端 macOS 仍可构建 IPA，但安装和免费签名刷新需要 AltServer 所在的 Windows 或 Mac 电脑。

## iOS 原生依赖

FastAPI、Pydantic、Uvicorn、HTTPX 和 SQLAlchemy 的 Python 源码已暂存。SQLAlchemy 按同步 ORM 路径运行，工程使用纯 Python 代码并移除它的 `greenlet` 运行时依赖。wb2api 的 AES-GCM 凭证导入导出需要 `cryptography`，Android 锁定的 42.0.8 没有公开 iOS wheel，完整 iOS 构建前需在 macOS/Xcode 上构建并验证 arm64 iOS wheel。文件选择器还需额外的 WKWebView 与 iOS 文档选择器桥接，当前管理页支持粘贴明文 JSON 凭证。

## 验证状态

已用 Python 3.12 和 Android 后端固定的纯 Python依赖在 Linux 上启动本机服务，同时禁用 greenlet 导入。SQLite 初始化成功，`/api/app/version`、带本机令牌的 `/api/accounts` 和 `/admin` 都返回成功。APK 解包显示的 Chaquopy ELF 运行库是 Android AArch64，未放入 iOS 工程。

当前执行环境是 Linux，没有 Xcode 或 iOS SDK，因此尚未生成 IPA，也未验证 iOS 原生 wheel 和真机生命周期。
