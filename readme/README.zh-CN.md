# Notchify

<p align="center">
  <img src="./ic_launcher.png" alt="Notchify" width="160" />
</p>

<p align="center">
  <strong>紧凑、流畅的 MacBook 刘海抽屉：文件暂存、快捷动作、音乐控制与实时镜像。</strong>
</p>

<p align="center">
  <strong>Notchify by Christian Saguirre</strong><br />
  <em>Inspired to make by Nadiane</em>
</p>

<p align="center">
  <a href="https://github.com/chrischancode/notchify/releases/latest">下载最新版本</a> ·
  <a href="https://github.com/chrischancode/notchify/actions">构建与 Artifacts</a>
</p>

---

## ⚡ 功能特性

- 📁 **文件架与暂存 (Shelf)**：拖放文件至刘海抽屉暂存，支持高清缩略图与预览，随时拖出至访达、微信、Discord、Slack 等应用。
- 📡 **即时 AirDrop**：将文件拖入 AirDrop 区域，立即唤起 macOS 原生隔空投送。
- 🪞 **实时相机镜像 (Live Mirror)**：水平翻转真实镜像预览，抽屉内随时一键开关。
- 🎵 **迷你音乐控制**：支持 Apple Music、Spotify 等，常驻显示封面与一键播放/暂停。
- 📸 **一键快捷动作**：一键**截图 (Capture)** 与一键**息屏锁定 (Lock)**。
- 🖱️ **拖拽自动展开**：将文件拖至屏幕顶部刘海处，刘海平滑自动展开为抽屉。

---

## 📥 快速下载与安装

### 步骤 1：下载
- 从 **[Releases](https://github.com/chrischancode/notchify/releases/latest)** 下载 `Notchify.zip`，或从 **[GitHub Actions](https://github.com/chrischancode/notchify/actions)** 获取最新构建产物。

### 步骤 2：安装
1. 解压下载的压缩包得到 `Notchify.app`。
2. 将 `Notchify.app` 拖入**应用程序**文件夹 (`/Applications`)。

---

## 💻 终端修复命令（重要）

由于从 GitHub 下载的应用未经 Mac App Store 签名，macOS Gatekeeper 可能会提示：  
> *“Notchify 已损坏，打不开”* 或 *“无法验证开发者”*。

打开 Mac **终端** (按 `Cmd + 空格` 搜索 `终端` 并回车)，运行此命令即可立即解决：

```bash
xattr -cr /Applications/Notchify.app
```

> **原理说明**：该命令会清除 macOS 的安全隔离属性 (`com.apple.quarantine`)，使 Notchify 可以正常秒开。

---

## ⚙️ 权限设置

首次启动 Notchify 时，请根据需要授予以下权限：
1. **摄像头**：用于实时相机镜像功能 (`系统设置 > 隐私与安全性 > 摄像头`)。
2. **辅助功能**：用于刘海窗口精确定位与全局快捷键 (`系统设置 > 隐私与安全性 > 辅助功能`)。

---

## 👤 Credits

- **Notchify by**: Christian Saguirre
- **Inspired to make by**: Nadiane
- Inspired by modern macOS Dynamic Island experiences.
