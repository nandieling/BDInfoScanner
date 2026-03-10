
# Mac 原生 BDInfo 扫描器 (BDInfoScanner for Mac)

![Platform](https://img.shields.io/badge/Platform-macOS%2012.0%2B-blue.svg)
![Language](https://img.shields.io/badge/Language-Swift%20%7C%20SwiftUI-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

一款专为 macOS 打造的原生 DIY 蓝光原盘（BDMV）信息扫描与分析工具。基于 SwiftUI 开发，内嵌纯原生跨平台 BDInfo 引擎，一键扫盘，告别繁琐的命令行和虚拟机环境。

## ✨ 功能特点

* 🍏 **纯血原生体验**：采用 SwiftUI 构建，完美契合 macOS 设计语言，支持深色/浅色模式切换。
* ⚡️ **开箱即用**：App 内部已静态封装编译好的 `bdinfo-cli` 核心引擎，你的 Mac **无需**额外安装 `.NET` 或 `Mono` 运行环境。
* 🎯 **智能正片识别**：一键选择 BDMV 文件夹，软件会自动解析 `.mpls` 播放列表树，智能锁定时长最长的正片进行定向扫描，彻底绕过互动阻塞。
* 📊 **实时进度可见**：告别漫长物理扫描时的“软件假死”。提供平滑的实时进度条、已耗时显示及精准的预计剩余时间（ETA）。
* 📄 **PT 标准输出**：精确计算各章节码率，完美输出 PT 站发种高度认可的标准 BDinfo 文本报告，支持一键导出 `.txt`。

## 📸 应用截图
![](https://img2.pixhost.to/images/6333/703319670_.png)
![](https://img2.pixhost.to/images/6333/703319672_2.png)


## 📦 安装与使用

1. 前往本仓库的 [Releases](../../releases) 页面，下载最新的 `BDInfoScanner_vX.X.dmg` 安装包。
2. 双击打开 `.dmg` 文件，将 `BDInfoScanner` 拖入 `Applications`（应用程序）文件夹。
3. **⚠️ 首次运行注意（关于 macOS 权限拦截）：**
   因未参加苹果个人开发者签名，直接双击可能会提示“打不开，因为来自身份不明的开发者”。
   * **解决办法**：在启动台或应用程序文件夹中，对着软件图标**单击鼠标右键（或双指点按）**，选择**「打开」**。在弹出的安全警告框中再次点击「打开」即可。以后就可以正常双击运行了。

## 🛠 自行编译与开发指南

如果你希望参与开发或自行从源码编译本软件：

### 环境要求
* Xcode 14.0 或更高版本
* macOS 12.0 或更高版本

### 编译步骤
1. 克隆本项目到本地：
   ```bash
   git clone [https://github.com/你的用户名/BDInfoScanner.git](https://github.com/你的用户名/BDInfoScanner.git)

```

2. **下载核心引擎**：
前往（https://github.com/tetrahydroc/BDInfoCLI/releases) 下载对应 Mac 架构（`arm64` 或 `x64`）的独立执行文件。
3. 将下载的文件重命名为 `bdinfo-cli`。
4. **赋予执行权限**：
```bash
chmod +x /路径/到你的/bdinfo-cli

```


5. 将 `bdinfo-cli` 拖入 Xcode 项目的资源目录（确保勾选了 *Copy items if needed* 和对应 *Target*）。
6. `Cmd + R` 运行即可。

## 🙏 鸣谢 (Acknowledgments)

本软件的底层物理扫描与报告生成能力，完全归功于优秀的开源跨平台 BDInfo 核心项目：

* **[tetrahydroc/BDInfoCLI](https://github.com/tetrahydroc/BDInfoCLI)** - 跨平台、支持 UHD 的命令行版 BDInfo。

## 📄 开源协议

本项目采用 [MIT License](https://www.google.com/search?q=LICENSE) 协议进行开源。

```

