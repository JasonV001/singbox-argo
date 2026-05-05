#!/bin/bash
# =============================================================================
# Linux 鐜妫€鏌ュ伐鍏?# 鍔熻兘锛氭鏌ヨ剼鏈繍琛屾墍闇€鐨勬墍鏈変緷璧栧拰鐜
# =============================================================================

echo "========================================"
echo "  Linux 鐜妫€鏌ュ伐鍏?
echo "========================================"
echo ""

# 鐘舵€佸彉閲?OK=0
WARN=0
ERROR=0

echo "馃搳 1. 绯荤粺淇℃伅"
echo "   -----------------------------------"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep -E '^NAME=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "Unknown")
    OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "Unknown")
    echo "   鎿嶄綔绯荤粺: $OS_NAME"
    echo "   绯荤粺鐗堟湰: $OS_VER"
    OK=$((OK+1))
else
    echo "   鈿狅笍 鏃犳硶妫€娴?/etc/os-release"
    WARN=$((WARN+1))
fi

echo "   鍐呮牳鐗堟湰: $(uname -r)"
echo "   绯荤粺鏋舵瀯: $(uname -m)"
echo ""

echo "馃洜锔?2. 鍩虹宸ュ叿妫€鏌?
echo "   -----------------------------------"
check_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   鉁?$name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   鉂?$name: NOT FOUND ($desc)"
        ERROR=$((ERROR+1))
    fi
}

check_tool "bash" "鑴氭湰瑙ｉ噴鍣?
check_tool "wget" "涓嬭浇鏂囦欢"
check_tool "curl" "HTTP璇锋眰"
check_tool "sed" "鏂囨湰澶勭悊"
check_tool "grep" "鏂囨湰鎼滅储"
check_tool "awk" "鏂囨湰澶勭悊"
check_tool "mktemp" "涓存椂鏂囦欢"
check_tool "chmod" "鏉冮檺璁剧疆"
check_tool "cp" "鏂囦欢澶嶅埗"
check_tool "mv" "鏂囦欢绉诲姩"
check_tool "rm" "鏂囦欢鍒犻櫎"
check_tool "mkdir" "鍒涘缓鐩綍"
check_tool "dirname" "璺緞澶勭悊"
check_tool "readlink" "璺緞澶勭悊"
check_tool "chmod" "鏉冮檺璁剧疆"
check_tool "cat" "鏌ョ湅鏂囦欢"
echo ""

echo "馃摝 3. 鍘嬬缉宸ュ叿妫€鏌?
echo "   -----------------------------------"
check_archive_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   鉁?$name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   鈿狅笍 $name: NOT FOUND ($desc)"
        WARN=$((WARN+1))
    fi
}

check_archive_tool "unzip" "瑙ｅ帇 ZIP"
check_archive_tool "tar" "瑙ｅ帇 TAR/GZ"
check_archive_tool "gzip" "GZ鍘嬬缉"
check_archive_tool "gunzip" "GZ瑙ｅ帇"
echo ""

echo "馃敡 4. 寮€鍙戝伐鍏凤紙鍙€夛級"
echo "   -----------------------------------"
check_optional_tool() {
    local name="$1"
    local desc="$2"
    if command -v "$name" &>/dev/null; then
        echo "   鉁?$name: OK ($desc)"
        OK=$((OK+1))
    else
        echo "   鈿狅笍 $name: NOT FOUND ($desc)"
        WARN=$((WARN+1))
    fi
}

check_optional_tool "git" "鐗堟湰鎺у埗"
check_optional_tool "python3" "鑴氭湰杈呭姪"
check_optional_tool "base64" "缂栫爜宸ュ叿"
echo ""

echo "馃搧 5. 鐩綍鍜屾潈闄愭鏌?
echo "   -----------------------------------"
check_dir() {
    local path="$1"
    local desc="$2"
    if [ -d "$path" ]; then
        if [ -w "$path" ]; then
            echo "   鉁?$path: OK ($desc - 鍙啓)"
            OK=$((OK+1))
        else
            echo "   鈿狅笍 $path: OK 浣嗕笉鍙啓 ($desc)"
            WARN=$((WARN+1))
        fi
    else
        echo "   鈩癸笍 $path: 灏嗙敱鑴氭湰鍒涘缓 ($desc)"
    fi
}

check_dir "/tmp" "涓存椂鏂囦欢"
check_dir "/usr/local/bin" "浜岃繘鍒舵枃浠?
check_dir "/usr/local/etc" "閰嶇疆鏂囦欢"
check_dir "/opt" "杞欢瀹夎"
echo ""

echo "鈿欙笍 6. 绯荤粺绠＄悊妫€鏌?
echo "   -----------------------------------"
if command -v systemctl &>/dev/null; then
    echo "   鉁?systemctl: Systemd 绯荤粺绠＄悊"
    OK=$((OK+1))
elif [ -d /etc/init.d ]; then
    echo "   鉁?OpenRC/SysV init: 妫€娴嬪埌"
    OK=$((OK+1))
else
    echo "   鈿狅笍 鏈娴嬪埌鏍囧噯 init 绯荤粺"
    WARN=$((WARN+1))
fi

if [ -f /etc/os-release ] && grep -qi alpine /etc/os-release; then
    echo "   鈩癸笍 Alpine 妫€娴? 鐗规畩澶勭悊宸插噯澶?
fi
echo ""

echo "馃寪 7. 缃戠粶杩炴帴妫€鏌?
echo "   -----------------------------------"
check_connectivity() {
    local url="$1"
    local name="$2"
    if curl -I -s --connect-timeout 5 "$url" &>/dev/null; then
        echo "   鉁?$name: 鍙闂?
        OK=$((OK+1))
    else
        if wget --spider --timeout=5 "$url" 2>/dev/null; then
            echo "   鉁?$name: 鍙闂?
            OK=$((OK+1))
        else
            echo "   鉂?$name: 鏃犳硶璁块棶锛堝彲鑳介渶瑕佷唬鐞嗭級"
            ERROR=$((ERROR+1))
        fi
    fi
}

check_connectivity "https://github.com" "GitHub"
check_connectivity "https://api.github.com" "GitHub API"
echo ""

echo "馃攼 8. 鐢ㄦ埛鏉冮檺妫€鏌?
echo "   -----------------------------------"
if [ "$(id -u)" = "0" ]; then
    echo "   鉁?鐢ㄦ埛: root (鎺ㄨ崘)"
    OK=$((OK+1))
else
    echo "   鈿狅笍 鐢ㄦ埛: $(whoami) (闈?root锛屽彲鑳介渶瑕?sudo)"
    WARN=$((WARN+1))
    if command -v sudo &>/dev/null; then
        echo "   鉁?sudo: 鍙敤"
        OK=$((OK+1))
    else
        echo "   鉂?sudo: 涓嶅彲鐢?
        ERROR=$((ERROR+1))
    fi
fi
echo ""

echo "========================================"
echo "  妫€鏌ョ粨鏋滄憳瑕?
echo "========================================"
echo "   鉁?閫氳繃: $OK"
echo "   鈿狅笍 璀﹀憡: $WARN"
echo "   鉂?閿欒: $ERROR"
echo ""

if [ $ERROR -eq 0 ]; then
    echo "馃帀 澶浜嗭紒鎵€鏈夊叧閿鏌ラ€氳繃锛?
    echo "鉁?鑴氭湰鍙互姝ｅ父杩愯"
else
    echo "鈿狅笍 鏈変竴浜涢棶棰橀渶瑕佽В鍐?
    echo ""
    echo "寤鸿鐨勪慨澶嶅懡浠わ細"
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
    echo "杩愯淇鍛戒护鍚庯紝閲嶆柊杩愯姝ゆ鏌ヨ剼鏈?
fi

echo ""
echo "========================================"
echo "  妫€鏌ュ畬鎴愶紒"
echo "========================================"
echo ""

exit $ERROR
