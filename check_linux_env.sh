#!/bin/bash
# =============================================================================
# Linux 环境检查工具
# 功能：检查脚本运行所需的所有依赖和环境
# =============================================================================

echo "========================================"
echo "  Linux 环境检查工具"
echo "========================================"
echo ""

# 状态变量
OK=0
WARN=0
ERROR=0

echo "📊 1. 系统信息"
echo "   -----------------------------------"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep -E '^NAME=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "Unknown")
    OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "Unknown")
    echo "   操作系统: $OS_NAME"
    echo "   系统版本: $OS_VER"
    OK=$((OK+1))
else
    echo "   ⚠️ 无法检测 /etc/os-release"
    WARN=$((WARN+1))
fi

echo "   内核版本: $(uname -r)"
echo "   系统架构: $(uname -m)"
echo ""

echo "🛠️ 2. 基础工具检查"
echo "   -----------------------------------"
check_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   ✅ $name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   ❌ $name: NOT FOUND ($desc)"
        ERROR=$((ERROR+1))
    fi
}

check_tool "bash" "脚本解释器"
check_tool "wget" "下载文件"
check_tool "curl" "HTTP请求"
check_tool "sed" "文本处理"
check_tool "grep" "文本搜索"
check_tool "awk" "文本处理"
check_tool "mktemp" "临时文件"
check_tool "chmod" "权限设置"
check_tool "cp" "文件复制"
check_tool "mv" "文件移动"
check_tool "rm" "文件删除"
check_tool "mkdir" "创建目录"
check_tool "dirname" "路径处理"
check_tool "readlink" "路径处理"
check_tool "chmod" "权限设置"
check_tool "cat" "查看文件"
echo ""

echo "📦 3. 压缩工具检查"
echo "   -----------------------------------"
check_archive_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   ✅ $name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   ⚠️ $name: NOT FOUND ($desc)"
        WARN=$((WARN+1))
    fi
}

check_archive_tool "unzip" "解压 ZIP"
check_archive_tool "tar" "解压 TAR/GZ"
check_archive_tool "gzip" "GZ压缩"
check_archive_tool "gunzip" "GZ解压"
echo ""

echo "🔧 4. 开发工具（可选）"
echo "   -----------------------------------"
check_optional_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   ✅ $name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   ⚠️ $name: NOT FOUND ($desc)"
        WARN=$((WARN+1))
    fi
}

check_optional_tool "git" "版本控制"
check_optional_tool "python3" "脚本辅助"
check_optional_tool "base64" "编码工具"
echo ""

echo "📁 5. 目录和权限检查"
echo "   -----------------------------------"
check_dir() {
    local path="$1"
    local desc="$2"
    if [ -d "$path" ]; then
        if [ -w "$path" ]; then
            echo "   ✅ $path: OK ($desc - 可写)"
            OK=$((OK+1))
        else
            echo "   ⚠️ $path: OK 但不可写 ($desc)"
            WARN=$((WARN+1))
        fi
    else
        echo "   ℹ️ $path: 将由脚本创建 ($desc)"
    fi
}

check_dir "/tmp" "临时文件"
check_dir "/usr/local/bin" "二进制文件"
check_dir "/usr/local/etc" "配置文件"
check_dir "/opt" "软件安装"
echo ""

echo "⚙️ 6. 系统管理检查"
echo "   -----------------------------------"
if command -v systemctl &>/dev/null; then
    echo "   ✅ systemctl: Systemd 系统管理"
    OK=$((OK+1))
elif [ -d /etc/init.d ]; then
    echo "   ✅ OpenRC/SysV init: 检测到"
    OK=$((OK+1))
else
    echo "   ⚠️ 未检测到标准 init 系统"
    WARN=$((WARN+1))
fi

if [ -f /etc/os-release ] && grep -qi alpine /etc/os-release; then
    echo "   ℹ️ Alpine 检测: 特殊处理已准备"
fi
echo ""

echo "🌐 7. 网络连接检查"
echo "   -----------------------------------"
check_connectivity() {
    local url="$1"
    local name="$2"
    if curl -I -s --connect-timeout 5 "$url" &>/dev/null; then
        echo "   ✅ $name: 可访问"
        OK=$((OK+1))
    else
        if wget --spider --timeout=5 "$url" 2>/dev/null; then
            echo "   ✅ $name: 可访问"
            OK=$((OK+1))
        else
            echo "   ❌ $name: 无法访问（可能需要代理）"
            ERROR=$((ERROR+1))
        fi
    fi
}

check_connectivity "https://github.com" "GitHub"
check_connectivity "https://api.github.com" "GitHub API"
echo ""

echo "🔐 8. 用户权限检查"
echo "   -----------------------------------"
if [ "$(id -u)" = "0" ]; then
    echo "   ✅ 用户: root (推荐)"
    OK=$((OK+1))
else
    echo "   ⚠️ 用户: $(whoami) (非 root，可能需要 sudo)"
    WARN=$((WARN+1))
    if command -v sudo &>/dev/null; then
        echo "   ✅ sudo: 可用"
        OK=$((OK+1))
    else
        echo "   ❌ sudo: 不可用"
        ERROR=$((ERROR+1))
    fi
fi
echo ""

echo "========================================"
echo "  检查结果摘要"
echo "========================================"
echo "   ✅ 通过: $OK"
echo "   ⚠️ 警告: $WARN"
echo "   ❌ 错误: $ERROR"
echo ""

if [ $ERROR -eq 0 ]; then
    echo "🎉 太棒了！所有关键检查通过！"
    echo "✅ 脚本可以正常运行"
else
    echo "⚠️ 有一些问题需要解决"
    echo ""
    echo "建议的修复命令："
    echo "----------------------------------------"
    
    if ! command -v bash &>/dev/null; then
        if [ -f /etc/alpine-release ]; then
            echo "apk add --no-cache bash"
        else
            echo "apt install -y bash"
        fi
    fi
    
    if ! command -v wget &>/dev/null || ! command -v curl &>/dev/null || ! command -v unzip &>/dev/null || ! command -v tar &>/dev/null; then
        if [ -f /etc/alpine-release ]; then
            echo "apk add --no-cache wget curl unzip tar sed grep gawk coreutils"
        else
            echo "apt update && apt install -y wget curl unzip tar sed gawk coreutils"
        fi
    fi
    echo ""
    echo "运行修复命令后，重新运行此检查脚本"
fi

echo ""
echo "========================================"
echo "  检查完成！"
echo "========================================"
echo ""

exit $ERROR
