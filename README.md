# Sing-box Manager Script

基于 sing-box 的多功能代理管理脚本。

## 快速开始

`ash
# 下载脚本
wget -O singbox.sh https://raw.githubusercontent.com/JasonV001/singbox-argo/main/singbox.sh

# 如果有编码问题，先转换
dos2unix singbox.sh

# 设置权限
chmod +x singbox.sh

# 运行脚本
./singbox.sh

# 之后直接用快捷指令
sb
`

## 功能特性

- Sing-box 核心管理
- Xray 核心支持
- Suoha 一键隧道（基于 Cloudflare Tunnel）
- 中转/落地节点管理
- 自动 TLS 证书处理
- Clash YAML 配置生成

## 系统要求

- Linux（Debian/Ubuntu/CentOS/Alpine）
- 支持架构：x86_64, arm64, armv7, i686
- 需要 root 权限