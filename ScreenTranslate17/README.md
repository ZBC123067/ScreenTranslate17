# ScreenTranslate17 0.4.1

这是面向 **iPhone 15 Pro（arm64e）/ iOS 17.0 / RootHide Bootstrap** 的应用内翻译插件候选工程。它不是系统级翻译器：只能在 Bootstrap“应用列表”中由用户明确开启注入的 App 内工作，不能覆盖主屏幕、锁屏、通知中心、控制中心或系统权限提示。

## 已实现

- 悬浮翻译球：单击优先扫描原生文字；双击隐藏或显示译文；长按打开控制面板。
- 原生 UIKit 文本扫描，识别不到时可使用 Apple Vision 本机 OCR。
- OCR 当前屏幕、框选区域翻译，以及指定区域的连续字幕模式。
- 连续字幕用 24×24 图像指纹跳过完全相同的画面；画面一变化即可 OCR，不再因动画、光标或滚动而无限等待。
- 手动开启的聊天增量翻译；优先读取原生文本，复杂聊天界面取不到文字时自动用本机 OCR 补充，每次只处理靠近底部的新内容。
- 输入框中文译英文；必须在预览中点“替换输入框文字”，绝不发送消息。
- 覆盖、双语、原文下方三种显示方式；少量译文贴近原文并进行碰撞检测，密集页面或无法避让时自动切换为底部可滚动的玻璃译文面板，彻底避免几十个气泡互相重叠。
- 顶部“灵动岛风格”状态胶囊显示框选、OCR、联网翻译、连续字幕与聊天监听状态；点击胶囊可直接打开控制菜单。它只使用公开 UIKit 材质，不修改系统灵动岛或 SpringBoard。
- 译文采用 iOS 17 可用的模糊材质、连续圆角、细高光边缘和轻阴影，模拟 Apple Liquid Glass 的层次感；这不是 iOS 27 的私有系统材质，因此不会调用不稳定的私有 API。
- 缓存最多 750 条，默认 7 天。
- 敏感输入框不读取；默认屏蔽钱包、银行、支付、验证器等 bundle；号码、卡号、集装箱号和带标签的账号/提单号在联网前替换为占位符，且含敏感占位符的翻译不会缓存。
- 支持 DeepL、Microsoft Translator 和 OpenAI 兼容的 Chat Completions 服务。只接受 HTTPS；不再使用不稳定且无官方保证的 Google Web 接口。
- 航运术语：离线仅对完整术语短语直译；OpenAI 兼容服务会收到不强制的术语指引，避免把普通语境中的 `space` 误译为“舱位”。

## RootHide 与注入

`THEOS_PACKAGE_SCHEME = roothide`、`jbroot()` 路径和 RootHide 所需的基础 entitlement 已包含。RootHide 的 jbroot 每次越狱可能变化，因此任何越狱文件路径都必须通过 `jbroot()` 取得，不能写死 `/var/jb`。

注入过滤使用 UIKit 框架，目的是让 Bootstrap 为用户已在 App List 中允许的 UIKit App 加载插件；构造函数还会拒绝 SpringBoard、WebKit 子进程、App Extension 和 AuthKit UI。不要在 Bootstrap 中勾选银行、支付或不信任 App。

## 构建

1. 将工程放入 GitHub 仓库。
2. 打开 Actions，运行 **Build RootHide package**。
3. 下载 `ScreenTranslate17-roothide-deb` artifact。
4. 用 Sileo 安装 `.deb`，然后到 Bootstrap → App List，只开启要翻译的普通 App，并完全退出后重新打开它。
5. 在 iOS“设置”→ ScreenTranslate17 中配置服务。联网翻译默认关闭，必须先选择服务、填写 HTTPS 地址/Key，再手动打开开关。

## API Key 与隐私边界

`PSEditTextCell` 的安全显示只是不在设置页明文显示。由于这是一个注入式 RootHide tweak，而非拥有独立 Keychain access group 的 App，现版本的 Key 仍保存在 RootHide 偏好文件中；它不是硬件级密钥库。请使用独立、可撤销、额度受限的 Key，或部署不需要把上游 Key 下发到手机的 HTTPS 自建代理。

OCR 与截图都只在内存中处理，工程不会把截图写入磁盘。启用联网服务时，**未被规则识别为敏感的文本仍会发送到你选择的翻译服务**。自动聊天翻译只在用户明确开启后工作。

## 验证范围与剩余风险

`scripts/static_audit.py` 会在 GitHub Actions 中检查 UTF-8、XML plist、版本一致性、RootHide scheme、权限、被移除的 Google Web 路径和旧 OCR API。GitHub Actions 会用 RootHide Theos 对 arm64e 编译并打包。

本机 Windows 环境不能运行 iOS SDK、RootHide 注入器或 iPhone 15 Pro 实机，因此不能替代下面的实际验证：不同 App 的私有/SwiftUI 视图树、受保护视频与 Metal 画面是否能截图、Vision 的语言可用性、RootHide 当前版本的注入稳定性、目标 App 的反注入检测、翻译服务凭据和网络。首次安装只应在一个普通、非敏感 App（例如 Safari）中手动测试；确认稳定后再逐个启用其他 App。
