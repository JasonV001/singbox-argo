# Sing-box Manager Script

基于 sing-box 的多功能代理管理脚本，支持多种协议和功能。

## 🚀 快速开始

```bash
# 下载脚本
wget -O singbox.sh https://github.com/YOUR_USER/YOUR_REPO/raw/main/singbox.sh

# 设置权限
chmod +x singbox.sh

# 运行脚本
./singbox.sh
```

## ✨ 功能特性

- ✅ Sing-box 核心管理
- ✅ Xray 核心支持
- ✅ 多协议支持（VMess, VLESS, Trojan, Shadowsocks, SOCKS, TUIC, Hysteria）
- ✅ Suoha 一键隧道（基于 Cloudflare Tunnel）
- ✅ 中转/落地节点管理
- ✅ 自动 TLS 证书处理
- ✅ Clash YAML 配置生成

## 📋 系统要求

- Linux 系统（Debian/Ubuntu/CentOS/Alpine）
- 支持架构：x86_64, arm64, armv7, i686
- 需要 root 权限

## 🛠️ 依赖工具

```bash
# Debian/Ubuntu
apt install -y wget curl unzip tar sed grep awk

# Alpine
apk add --no-cache wget curl unzip tar bash sed grep gawk
```

## 📁 文件结构

```
.
├── singbox.sh          # 主管理脚本
├── suoha.sh            # Suoha 一键隧道功能
├── advanced_relay.sh   # 高级中转功能
├── parser.sh           # 链接解析工具
├── xray_manager.sh     # Xray 管理功能
├── check_linux_env.sh  # Linux 环境检查工具
└── .gitattributes      # Git 配置文件
```

## 📝 命令行参数

```bash
# 显示帮助
./singbox.sh --help

# 安装 sing-box
./singbox.sh --install

# 查看状态
./singbox.sh --status

# 启动服务
./singbox.sh --start

# 停止服务
./singbox.sh --stop

# 重启服务
./singbox.sh --restart

# 卸载脚本
./singbox.sh --uninstall
```

## 🌐 协议支持

| 协议 | 状态 | 说明 |
|------|------|------|
| VMess | ✅ | 支持 |
| VLESS | ✅ | 支持 |
| Trojan | ✅ | 支持 |
| Shadowsocks | ✅ | 支持 |
| SOCKS5 | ✅ | 支持 |
| TUIC | ✅ | 支持 |
| Hysteria2 | ✅ | 支持 |

## 🧪 环境检查

```bash
# 在部署前检查环境
./check_linux_env.sh
```

## 📄 许可证

MIT License

## 📞 支持

如有问题，请提交 Issue。
