# ddns-go Installer

Interactive one-click installer for [ddns-go](https://github.com/jeessy2/ddns-go), with version selection, platform detection, service installation, and listen port configuration.

## English

### Features

- Automatically detects OS and CPU architecture.
- Supports official ddns-go release assets.
- Shows the latest 5 ddns-go releases in an interactive version menu.
- Supports manual version input.
- Supports manual OS, architecture, and MIPS float ABI selection.
- Supports interactive listen mode selection:
  - Public IPv4
  - Localhost only
  - Custom public port
  - Custom local port
  - Custom full listen address
- Installs ddns-go as a system service.
- Supports install, update, uninstall, status, and asset list modes.
- Verifies downloads with official `checksums.txt`.

### Quick Start

Recommended:

```bash
curl -fLO https://raw.githubusercontent.com/Astro-y/ddns-go-installer/main/install-ddns-go.sh
chmod +x install-ddns-go.sh
sudo ./install-ddns-go.sh
```

Do not use `curl | bash` for the interactive installer, because the script needs terminal input for arrow-key menus.

### Linux Usage

```bash
sudo ./install-ddns-go.sh
sudo ./install-ddns-go.sh install
sudo ./install-ddns-go.sh update
sudo ./install-ddns-go.sh uninstall
sudo ./install-ddns-go.sh status
sudo ./install-ddns-go.sh list
```

### Linux Options

```bash
--version <vX.Y.Z>       Install a specific ddns-go version
--port <port>            Web listen port, default: 9876
--ip <ip>                Web listen IP
--listen <ip:port>       Full listen address
--config <path>          Config file path
--asset <asset-name>     Use an exact release asset
--install-dir <path>     Install directory, default: /opt/ddns-go
```

Examples:

```bash
sudo ./install-ddns-go.sh install --version v6.17.1
sudo ./install-ddns-go.sh install --listen 0.0.0.0:9876
sudo ./install-ddns-go.sh install --ip 127.0.0.1 --port 9876
```

### Windows Usage

Download the PowerShell script:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Astro-y/ddns-go-installer/main/install-ddns-go.ps1" -OutFile "install-ddns-go.ps1"
```

Run PowerShell as Administrator:

```powershell
.\install-ddns-go.ps1
```

Examples:

```powershell
.\install-ddns-go.ps1 -Command install
.\install-ddns-go.ps1 -Command install -Listen 0.0.0.0:9876
.\install-ddns-go.ps1 -Command install -Version v6.17.1
```

If script execution is blocked by Windows execution policy, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-ddns-go.ps1
```

### After Installation

Open:

```text
http://SERVER_IP:9876
```

Then configure ddns-go in the web UI.

The config file may be empty before you save settings in the web UI. This is normal.

Default Linux config path:

```text
/opt/ddns-go/.ddns_go_config.yaml
```

### Notes

- `Public IPv4` listens on `0.0.0.0:<port>`.
- `Localhost only` listens on `127.0.0.1:<port>`.
- `Custom public port` listens on `0.0.0.0:<custom-port>`.
- `Custom local port` listens on `127.0.0.1:<custom-port>`.
- `Custom full listen address` is for advanced cases such as `[::]:9876`.

---

## 中文

### 功能特�?
这是一�?[ddns-go](https://github.com/jeessy2/ddns-go) 交互式一键安装脚本�?
支持�?
- 自动识别系统�?CPU 架构�?- 覆盖官方 ddns-go Release 资产�?- 上下键选择版本，默认显示最�?5 个版本�?- 支持手动输入版本号�?- 支持手动选择系统、架构和 MIPS 浮点类型�?- 支持交互式选择监听方式�?  - 公网 IPv4
  - 仅本�?  - 自定义公网端�?  - 自定义本地端�?  - 自定义完整监听地址
- 自动安装 ddns-go 系统服务�?- 支持安装、更新、卸载、状态查看和资产列表�?- 使用官方 `checksums.txt` 校验下载文件�?
### 快速开�?
推荐方式�?
```bash
curl -fLO https://raw.githubusercontent.com/Astro-y/ddns-go-installer/main/install-ddns-go.sh
chmod +x install-ddns-go.sh
sudo ./install-ddns-go.sh
```

不推荐使用：

```bash
curl -fsSL https://raw.githubusercontent.com/Astro-y/ddns-go-installer/main/install-ddns-go.sh | sudo bash
```

因为脚本包含上下键交互菜单，管道运行可能影响终端输入�?
### Linux 用法

```bash
sudo ./install-ddns-go.sh
sudo ./install-ddns-go.sh install
sudo ./install-ddns-go.sh update
sudo ./install-ddns-go.sh uninstall
sudo ./install-ddns-go.sh status
sudo ./install-ddns-go.sh list
```

### Linux 参数

```bash
--version <vX.Y.Z>       指定 ddns-go 版本
--port <port>            Web 监听端口，默�?9876
--ip <ip>                Web 监听 IP
--listen <ip:port>       完整监听地址
--config <path>          配置文件路径
--asset <asset-name>     指定官方 Release 资产
--install-dir <path>     安装目录，默�?/opt/ddns-go
```

示例�?
```bash
sudo ./install-ddns-go.sh install --version v6.17.1
sudo ./install-ddns-go.sh install --listen 0.0.0.0:9876
sudo ./install-ddns-go.sh install --ip 127.0.0.1 --port 9876
```

### Windows 用法

下载 PowerShell 脚本�?
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Astro-y/ddns-go-installer/main/install-ddns-go.ps1" -OutFile "install-ddns-go.ps1"
```

请用管理员身份运�?PowerShell�?
```powershell
.\install-ddns-go.ps1
```

示例�?
```powershell
.\install-ddns-go.ps1 -Command install
.\install-ddns-go.ps1 -Command install -Listen 0.0.0.0:9876
.\install-ddns-go.ps1 -Command install -Version v6.17.1
```

如果 Windows 执行策略阻止脚本运行，可以使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-ddns-go.ps1
```

### 安装�?
安装完成后打开�?
```text
http://服务器IP:9876
```

进入 Web 页面后填写并保存 ddns-go 配置�?
首次安装后配置文件为空是正常的，保存配置后才会写入内容�?
默认 Linux 配置文件路径�?
```text
/opt/ddns-go/.ddns_go_config.yaml
```

### 监听模式说明

- `Public IPv4` 监听 `0.0.0.0:<端口>`�?- `Localhost only` 监听 `127.0.0.1:<端口>`�?- `Custom public port` 监听 `0.0.0.0:<自定义端�?`�?- `Custom local port` 监听 `127.0.0.1:<自定义端�?`�?- `Custom full listen address` 适合高级场景，例�?`[::]:9876`�?
## License

MIT
