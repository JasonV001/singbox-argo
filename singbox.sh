#!/bin/bash

# 鍩虹璺緞瀹氫箟
export SCRIPT_VERSION="15"
export DEFAULT_SNI="www.amd.com"
SELF_SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF_SCRIPT_PATH")"
SINGBOX_DIR="/usr/local/etc/sing-box"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/main"
SCRIPT_UPDATE_URL="${GITHUB_RAW_BASE}/singbox.sh"

# 娉ㄥ叆 sing-box 1.12+ 搴熷純閰嶇疆鍏煎鐜鍙橀噺 (鐢ㄤ簬鑴氭湰鍐呭祵鐨勫墠鍙板懡浠よ皟鐢紝濡?check/generate)
export ENABLE_DEPRECATED_LEGACY_DNS_SERVERS="true"
export ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM="true"
export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER="true"

# --- 鏍稿績宸ュ叿鍑芥暟 ---

# 棰滆壊瀹氫箟 - 缇庡寲鍚庣殑
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# 鎵撳嵃娑堟伅鍑芥暟 - 缇庡寲鍚庣殑
_info() { echo -e "${CYAN}${BOLD}[淇℃伅]${NC} $1" >&2; }
_success() { echo -e "${GREEN}${BOLD}[鎴愬姛]${NC} $1" >&2; }
_warn() { echo -e "${YELLOW}${BOLD}[娉ㄦ剰]${NC} $1" >&2; }
_warning() { _warn "$1"; } # 鍒悕鍏煎
_error() { echo -e "${RED}${BOLD}[閿欒]${NC} $1" >&2; }

# 鎵撳嵃婕備寒鐨勫垎闅旂嚎
_separator() { echo -e "${DIM}鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€${NC}"; }

# 鎵撳嵃 Logo
_print_logo() {
    echo -e "${CYAN}${BOLD}"
    echo "  鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽"
    echo "  鈺?    Sing-box 16 绠＄悊鑴氭湰 v${SCRIPT_VERSION}  鈺?
    echo "  鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆"
    echo -e "${NC}"
}

# 妫€鏌?root 鏉冮檺
_check_root() {
    if [[ $EUID -ne 0 ]]; then
        _error "姝よ剼鏈繀椤讳互 root 鏉冮檺杩愯銆?
        exit 1
    fi
}

# 缂栬В鐮佸櫒 (绾?Bash 绋冲仴瀹炵幇)
_url_decode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}
_url_encode() {
    # [淇] 浣跨敤 jq 鍐呭缓 @uri 杩囨护鍣紝瀹岀編澶勭悊 UTF-8 澶氬瓧鑺傚瓧绗?    # jq 鏄繀瑁呬緷璧栵紝@uri 浠ュ瓧鑺備负鍗曚綅鎵ц鏍囧噯 percent-encoding
    printf '%s' "$1" | jq -sRr @uri
}

_ss_base64_encode() {
    # Shadowsocks SIP002 瑙勮寖瑕佹眰 Base64 缂栫爜涓嶅甫濉厖 (No Padding)
    printf '%s' "$1" | base64 | tr -d '\n\r ' | sed 's/=//g'
}

# 鍏綉 IP 鑾峰彇 (甯﹀叏灞€缂撳瓨)
_get_public_ip() {
    [ -n "$server_ip" ] && [ "$server_ip" != "null" ] && { echo "$server_ip"; return; }
    local ip=$(timeout 5 curl -s4 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s4 --max-time 2 ipinfo.io/ip 2>/dev/null)
    [ -z "$ip" ] && ip=$(timeout 5 curl -s6 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s6 --max-time 2 ipinfo.io/ip 2>/dev/null)
    server_ip="$ip"
    echo "$ip"
}
_get_ip() { _get_public_ip; } # 鍒悕鍏煎

# 绯荤粺鐜妫€娴?_detect_init_system() {
    if [ -f /sbin/openrc-run ] || command -v rc-service &>/dev/null; then
        export INIT_SYSTEM="openrc"
        export SERVICE_FILE="/etc/init.d/sing-box"
    elif command -v systemctl &>/dev/null; then
        export INIT_SYSTEM="systemd"
        export SERVICE_FILE="/etc/systemd/system/sing-box.service"
    else
        export INIT_SYSTEM="unknown"
        export SERVICE_FILE=""
    fi
}

# 绔彛鍗犵敤妫€鏌?_check_port_occupied() {
    local port=$1
    local proto=${2:-tcp}
    if [[ "$proto" == "tcp" ]]; then
        if command -v ss &>/dev/null; then
            ss -lnpt | grep -q ":${port} " && return 0
        else
            netstat -lnpt | grep -q ":${port} " && return 0
        fi
    else
        if command -v ss &>/dev/null; then
            ss -lnpu | grep -q ":${port} " && return 0
        else
            netstat -lnpu | grep -q ":${port} " && return 0
        fi
    fi
    return 1
}

# 閰嶇疆鏂囦欢绔彛鎵弿 (棰勬鏄惁宸茶鏈▼搴忓崰鐢?
_check_port_in_config() {
    local port=$1
    [ ! -f "$CONFIG_FILE" ] && return 1
    jq -e ".inbounds[] | select(.listen_port == ($port|tonumber))" "$CONFIG_FILE" >/dev/null 2>&1
}

# 缁煎悎绔彛纰版挒妫€娴?_check_port_conflict() {
    local port=$1
    local proto=${2:-tcp}
    local silent=${3:-false}
    if _check_port_in_config "$port"; then
        [ "$silent" != "true" ] && _error "绔彛 ${port} 宸插湪 sing-box 閰嶇疆鏂囦欢涓鍗犵敤銆?
        return 0
    fi
    if _check_port_occupied "$port" "$proto"; then
        [ "$silent" != "true" ] && _error "绔彛 ${port} 宸茶绯荤粺鍏朵粬绋嬪簭鍗犵敤銆?
        return 0
    fi
    return 1
}

# IPTables 瑙勫垯鎸佷箙鍖?(璺?Debian/Alpine 鍙屽彂琛岀増鍏煎)
_save_iptables_rules() {
    if command -v netfilter-persistent &>/dev/null; then
        # Debian/Ubuntu: 浣跨敤 netfilter-persistent 缁熶竴鎸佷箙鍖?(鍚?v4+v6)
        netfilter-persistent save >/dev/null 2>&1
    else
        # Alpine / 閫氱敤鏂规: 鍒嗗埆淇濆瓨 v4 鍜?v6 瑙勫垯鍒版爣鍑嗚矾寰?        if command -v iptables-save &>/dev/null; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
        fi
        if command -v ip6tables-save &>/dev/null; then
            mkdir -p /etc/iptables
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        fi
    fi
    # Alpine OpenRC: 灏濊瘯浣跨敤 rc-service 淇濆瓨
    if command -v rc-service &>/dev/null; then
        rc-service iptables save 2>/dev/null
        rc-service ip6tables save 2>/dev/null
    fi
}

# 鍏綉 IP 鍒濆鍖?_init_server_ip() {
    _info "姝ｅ湪鑾峰彇鏈嶅姟鍣ㄥ叕缃?IP..."
    server_ip=$(_get_public_ip)
    if [ -z "$server_ip" ] || [ "$server_ip" == "null" ]; then
        _warn "鑷姩鑾峰彇 IP 澶辫触锛屽皢鍥為€€鍒?127.0.0.1"
        server_ip="127.0.0.1"
    else
        _success "褰撳墠鏈嶅姟鍣ㄥ叕缃?IP: ${server_ip}"
    fi
}

# 缁熶竴鏈嶅姟绠＄悊
_manage_service() {
    local action="$1"

    # [鍏抽敭鏍稿績淇] 鍔ㄦ€佹敞鍏ュ唴缃?NTP 鏃堕棿鍚屾妯″潡
    # 瑙ｅ喅閮ㄥ垎寤変环 LXC/Docker 瀹瑰櫒鏃犳硶淇敼姣嶆満绯荤粺鏃堕棿锛屽鑷?SS-2022 瑙﹀彂 30s 閲嶆斁淇濇姢鐩存帴鐖?bad timestamp 鎷掕繛鐨勬柇娴侀棶棰?    if [[ "$action" == "restart" || "$action" == "start" ]]; then
        if [ -s "$CONFIG_FILE" ] && ! jq -e '.ntp' "$CONFIG_FILE" >/dev/null 2>&1; then
            _info "妫€娴嬪埌鍐呮牳閰嶇疆缂哄け鍐呯疆鏃堕棿鍚屾(NTP)妯″潡锛屾鍦ㄨ嚜鍔ㄦ敞鍏ラ槻閲嶆斁淇濇姢琛ヤ竵..."
            _atomic_modify_json "$CONFIG_FILE" '.ntp = {"enabled": true, "server": "time.apple.com", "server_port": 123, "interval": "30m"}' 2>/dev/null
        fi
    fi

    [ -z "$INIT_SYSTEM" ] && _detect_init_system
    [ "$action" == "status" ] || _info "姝ｅ湪浣跨敤 ${INIT_SYSTEM} 鎵ц: $action..."
    case "$INIT_SYSTEM" in
        systemd)
            if [ "$action" == "status" ]; then systemctl status sing-box --no-pager -l; return; fi
            systemctl "$action" sing-box ;;
        openrc)
            if [ "$action" == "status" ]; then rc-service sing-box status; return; fi
            rc-service sing-box "$action" ;;
        *) _error "涓嶆敮鎸佺殑鏈嶅姟绠＄悊绯荤粺" ;;
    esac
}

# 鏅鸿兘鍖呯鐞?_pkg_install() {
    local pkgs="$*"
    [ -z "$pkgs" ] && return 0
    if command -v apk &>/dev/null; then
        apk add --no-cache $pkgs >/dev/null 2>&1
    elif command -v apt-get &>/dev/null; then
        # 鍏ㄦ柊 LXC/瀹瑰櫒涓?apt 缂撳瓨鍙兘涓虹┖锛屽繀椤诲厛 update
        if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls -A /var/lib/apt/lists/ 2>/dev/null | wc -l)" -le 1 ]; then
            apt-get update -qq >/dev/null 2>&1
        fi
        DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs >/dev/null 2>&1 || {
            # 鍏滃簳锛氬鏋滃畨瑁呭け璐ワ紝寮哄埗鍒锋柊绱㈠紩鍚庨噸璇?            apt-get update -qq >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs >/dev/null 2>&1
        }
    elif command -v yum &>/dev/null; then yum install -y $pkgs >/dev/null 2>&1
    elif command -v dnf &>/dev/null; then dnf install -y $pkgs >/dev/null 2>&1
    fi
}

# 鍘熷瓙淇敼 JSON/YAML 鏂囦欢
_atomic_modify_json() {
    local file="$1" filter="$2"
    [ ! -f "$file" ] && return 1
    local tmp="${file}.tmp"
    if jq "$filter" "$file" > "$tmp"; then mv "$tmp" "$file"
    else _error "淇敼JSON澶辫触: $file"; rm -f "$tmp"; return 1; fi
}
_atomic_modify_yaml() {
    local file="$1" filter="$2"
    [ ! -f "$file" ] && return 1
    cp "$file" "${file}.tmp"
    if ${YQ_BINARY} eval "$filter" -i "$file"; then rm "${file}.tmp"
    else _error "淇敼YAML澶辫触: $file"; mv "${file}.tmp" "$file"; return 1; fi
}

# --- 璧勬簮涓庣幆澧冪鐞?---

# 绯荤粺鏃堕棿鍚屾 (瑙ｅ喅 TLS 鎻℃墜 EOF 闂)
_sync_system_time() {
    _info "姝ｅ湪妫€鏌ュ苟鍚屾绯荤粺鏃堕棿..."
    local current_year=$(date +%Y)
    [ "$current_year" -lt 2024 ] && _warning "绯荤粺鏃堕棿婊炲悗锛屾鍦ㄥ己鍒跺悓姝?.."
    # 閲囩敤涓夌骇鍚屾绛栫暐鎻愬崌椴佹鎬?(NTP -> HTTP -> Package)
    if _pkg_install ntpdate >/dev/null 2>&1 && command -v ntpdate &>/dev/null; then
        ntpdate -u ntp.aliyun.com >/dev/null 2>&1 || ntpdate -u pool.ntp.org >/dev/null 2>&1
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        _pkg_install chrony >/dev/null 2>&1
        chronyd -q 'server ntp.aliyun.com iburst' >/dev/null 2>&1
    else
        # 鏈€鍚庣殑灞忛殰锛氶€氳繃 HTTP 澶撮儴淇鏃堕棿 (闃插尽 UDP 123 鎷︽埅)
        local http_time=$(curl -sI --max-time 3 https://www.google.com | grep -i '^date:' | cut -f2- -d' ')
        if [ -n "$http_time" ]; then
            # [淇] 鍏堝皾璇?GNU date 鐩存帴璁剧疆锛屽け璐ュ悗灏濊瘯 epoch 鏂瑰紡 (鍏煎 BusyBox)
            if ! date -s "$http_time" >/dev/null 2>&1; then
                local epoch=$(date -d "$http_time" +%s 2>/dev/null)
                [ -n "$epoch" ] && date -s "@$epoch" >/dev/null 2>&1
            fi
        fi
    fi
    _info "褰撳墠鏃堕棿锛?(date)"
}

# Clash YAML 鑺傜偣绠＄悊
_get_proxy_field() {
    local proxy_name="$1" field="$2"
    export PROXY_NAME="$proxy_name"
    ${YQ_BINARY} eval '.proxies[] | select(.name == env(PROXY_NAME)) | '"$field" "${CLASH_YAML_FILE}" 2>/dev/null | head -n 1
}
_add_node_to_yaml() {
    local proxy_json="$1"
    local proxy_name=$(echo "$proxy_json" | jq -r .name)
    _atomic_modify_yaml "$CLASH_YAML_FILE" ".proxies |= . + [${proxy_json}] | .proxies |= unique_by(.name)"
    export PROXY_NAME="$proxy_name"
    ${YQ_BINARY} eval '.proxy-groups[] |= (select(.name == "鑺傜偣閫夋嫨") | .proxies |= . + [env(PROXY_NAME)] | .proxies |= unique)' -i "$CLASH_YAML_FILE"
}
_remove_node_from_yaml() {
    local proxy_name="$1"
    export PROXY_NAME="$proxy_name"
    ${YQ_BINARY} eval 'del(.proxies[] | select(.name == env(PROXY_NAME)))' -i "$CLASH_YAML_FILE"
    ${YQ_BINARY} eval '.proxy-groups[] |= (select(.name == "鑺傜偣閫夋嫨") | .proxies |= del(.[] | select(. == env(PROXY_NAME))))' -i "$CLASH_YAML_FILE"
}
_find_proxy_name() {
    local port="$1" type="$2" proxy_name=""
    local proxy_obj=$(${YQ_BINARY} eval '.proxies[] | select(.port == '${port}')' ${CLASH_YAML_FILE} 2>/dev/null | head -n 1)
    [ -n "$proxy_obj" ] && proxy_name=$(echo "$proxy_obj" | ${YQ_BINARY} eval '.name' -)
    [ -z "$proxy_name" ] && proxy_name=$(${YQ_BINARY} eval '.proxies[] | select(.port == '${port}' or .port == 443) | .name' ${CLASH_YAML_FILE} 2>/dev/null | grep -i "${type:-.}" | head -n 1)
    echo "$proxy_name"
}

# 鍐呭瓨闄愰璁＄畻
_get_mem_limit() {
    local total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local cgroup_limit=""
    local limit

    [ -z "$total_mem_mb" ] && total_mem_mb=128

    if [ -r /sys/fs/cgroup/memory.max ]; then
        cgroup_limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
        if [ "$cgroup_limit" != "max" ] && [ -n "$cgroup_limit" ]; then
            total_mem_mb=$((cgroup_limit / 1024 / 1024))
        fi
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        cgroup_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
        if [ -n "$cgroup_limit" ] && [ "$cgroup_limit" -lt 9223372036854771712 ] 2>/dev/null; then
            total_mem_mb=$((cgroup_limit / 1024 / 1024))
        fi
    fi

    if [ "$total_mem_mb" -le 128 ]; then
        limit=48
    elif [ "$total_mem_mb" -le 256 ]; then
        limit=$((total_mem_mb * 50 / 100))
    elif [ "$total_mem_mb" -le 512 ]; then
        limit=$((total_mem_mb * 65 / 100))
    else
        limit=$((total_mem_mb * 80 / 100))
    fi

    [ "$limit" -lt 32 ] && limit=32
    echo "$limit"
}

# 瀹夎闃舵浼氫骇鐢熻緝澶氭枃浠剁紦瀛橈紝浣庡唴瀛樺鍣ㄤ腑灏藉姏閲婃斁锛涘け璐ヤ笉褰卞搷涓绘祦绋?_release_install_cache() {
    sync 2>/dev/null || true
    if [ -w /proc/sys/vm/drop_caches ]; then
        if { echo 1 > /proc/sys/vm/drop_caches; } 2>/dev/null; then
            _info "宸插皾璇曢噴鏀惧畨瑁呬骇鐢熺殑鏂囦欢缂撳瓨銆?
        fi
    fi
    return 0
}

# 瀹夎 yq
_install_yq() {
    if ! command -v yq &>/dev/null; then
        _info "瀹夎 yq..."
        local arch=$(uname -m)
        case $arch in x86_64|amd64) arch='amd64' ;; aarch64|arm64) arch='arm64' ;; *) arch='amd64' ;; esac
        wget -qO "$YQ_BINARY" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$arch"
        chmod +x "$YQ_BINARY"
    fi
}

# --- 鏍稿績鍙橀噺瀹氫箟 ---
export SINGBOX_DIR="/usr/local/etc/sing-box"
export SINGBOX_BIN="/usr/local/bin/sing-box"
export YQ_BINARY="/usr/local/bin/yq"
export CONFIG_FILE="${SINGBOX_DIR}/config.json"
export CLASH_YAML_FILE="${SINGBOX_DIR}/clash.yaml"
export METADATA_FILE="${SINGBOX_DIR}/metadata.json"
export LOG_FILE="/var/log/sing-box.log"
export PID_FILE="/tmp/sing-box.pid"
_detect_init_system
[ "$INIT_SYSTEM" == "openrc" ] && export SERVICE_FILE="/etc/init.d/sing-box" || export SERVICE_FILE="/etc/systemd/system/sing-box.service"

export -f _info _success _warn _warning _error _url_encode _url_decode _get_public_ip _detect_init_system _sync_system_time _release_install_cache _atomic_modify_json _atomic_modify_yaml _manage_service _pkg_install _get_proxy_field _add_node_to_yaml _remove_node_from_yaml _find_proxy_name

server_ip=""
BATCH_MODE=false
trap 'rm -f ${SINGBOX_DIR}/*.tmp /tmp/singbox_links.tmp' EXIT
# 渚濊禆瀹夎
_install_dependencies() {
    # 鏍稿績渚濊禆锛氳剼鏈繍琛岀殑缁濆鍓嶆彁锛屽繀椤诲叏閮ㄨ涓?    local core_pkgs="curl jq openssl wget tar"
    # 鍙€変緷璧栵細閮ㄥ垎鍔熻兘闇€瑕侊紝鍗充娇瑁呭け璐ヤ篃涓嶈嚧鍛?    local optional_pkgs="procps iptables socat iproute2 cron lsof"
    
    # 閽堝涓嶅悓鍙戣鐗堢殑 cron 鍖呭悕閫傞厤
    if command -v apk &>/dev/null; then
        optional_pkgs="${optional_pkgs/cron/dcron}"
    elif ! command -v apt-get &>/dev/null && ! command -v yum &>/dev/null && ! command -v dnf &>/dev/null; then
        optional_pkgs="${optional_pkgs/cron/cronie}"
    fi

    _info "姝ｅ湪瀹夎鏍稿績渚濊禆..."
    _pkg_install $core_pkgs
    
    _info "姝ｅ湪瀹夎鍙€変緷璧?.."
    _pkg_install $optional_pkgs 2>/dev/null || {
        # 鍙€変緷璧栨壒閲忓畨瑁呭け璐ユ椂锛堝 iptables 鍐茬獊锛夛紝閫愪釜灏濊瘯
        _warn "閮ㄥ垎鍙€変緷璧栨壒閲忓畨瑁呴亣鍒板啿绐侊紝姝ｅ湪閫愪釜閲嶈瘯..."
        for pkg in $optional_pkgs; do
            _pkg_install "$pkg" 2>/dev/null || true
        done
    }
    
    _install_yq

    # [淇] Alpine 涓?dcron 瀹夎鍚庨渶鎵嬪姩鍚姩 cron 瀹堟姢杩涚▼
    if command -v apk &>/dev/null; then
        if command -v crond &>/dev/null; then
            rc-service dcron start 2>/dev/null
            rc-update add dcron default 2>/dev/null
        fi
    fi

    # 鍏抽敭渚濊禆楠岃瘉锛氬鏋滄牳蹇冨伐鍏风己澶卞垯鏃犳硶缁х画
    local missing=""
    for cmd in jq curl wget openssl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        _error "浠ヤ笅鍏抽敭渚濊禆瀹夎澶辫触:${missing}"
        _error "璇蜂娇鐢ㄧ郴缁熷寘绠＄悊鍣ㄦ墜鍔ㄥ畨瑁呰繖浜涘伐鍏凤紙濡?apk add / apt-get install / yum install锛?
        exit 1
    fi
}

# 纭繚 iptables 鍙敤锛屽苟妫€娴嬪疄闄?netfilter 鍐欏叆鑳藉姏
_ensure_iptables() {
    # 绗竴姝ワ細妫€娴嬪懡浠ゆ槸鍚﹀瓨鍦紝涓嶅瓨鍦ㄥ垯灏濊瘯瀹夎
    if ! command -v iptables &>/dev/null; then
        _info "鏈娴嬪埌 iptables锛屽皾璇曞畨瑁?.."
        _pkg_install iptables
        if ! command -v iptables &>/dev/null; then
            _error "iptables 瀹夎澶辫触銆?
            return 1
        fi
        _success "iptables 瀹夎鎴愬姛銆?
    fi

    # 绗簩姝ワ細鎺㈡祴瀹為檯 netfilter 鑳藉姏锛堝懡浠ゅ瓨鍦ㄤ笉绛変簬鏈夊啓鏉冮檺锛?    # 鐢ㄤ竴鏉℃棤瀹崇殑涓存椂瑙勫垯娴嬭瘯 nat 琛ㄥ啓鏉冮檺锛屾祴璇曞悗绔嬪嵆鍒犻櫎
    local test_ok="false"
    if iptables -t nat -A PREROUTING -p tcp --dport 65530 -j DNAT --to-destination 127.0.0.1:65530 2>/dev/null; then
        iptables -t nat -D PREROUTING -p tcp --dport 65530 -j DNAT --to-destination 127.0.0.1:65530 2>/dev/null
        test_ok="true"
    fi

    if [ "$test_ok" != "true" ]; then
        _warn "iptables 鍛戒护瀛樺湪锛屼絾褰撳墠鐜鏃?nat 琛ㄥ啓鏉冮檺锛堝鍣?LXC 鏃犵壒鏉冩ā寮忥級銆?
        _warn "绔彛杞彂灏嗚嚜鍔ㄤ娇鐢?sing-box 寮曟搸浠ｆ浛銆?
        return 2  # 杩斿洖鍊?2 琛ㄧず锛氬懡浠ゅ瓨鍦ㄤ絾鑳藉姏鍙楅檺
    fi

    return 0
}

_install_sing_box() {
    _info "姝ｅ湪瀹夎鏈€鏂扮ǔ瀹氱増 sing-box..."
    local arch=$(uname -m)
    local arch_tag
    local temp_dir=""
    local archive_path=""
    local extracted_bin=""
    case $arch in
        x86_64|amd64) arch_tag='amd64' ;;
        aarch64|arm64) arch_tag='arm64' ;;
        armv7l) arch_tag='armv7' ;;
        *) _error "涓嶆敮鎸佺殑鏋舵瀯锛?arch"; return 1 ;;
    esac
    
    # 妫€娴?C 搴撶被鍨嬶細Alpine 绛夌郴缁熶娇鐢?musl锛岄渶瑕佷笅杞藉搴旂増鏈?    local libc_suffix=""
    if ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]; then
        _info "妫€娴嬪埌 musl libc (Alpine 绛夌郴缁?锛屽皢涓嬭浇 musl 鐗堟湰..."
        libc_suffix="-musl"
    fi
    
    local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local search_pattern="linux-${arch_tag}${libc_suffix}.tar.gz"
    local release_info=$(curl -s "$api_url")
    local download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"${search_pattern}\")) | .browser_download_url" | head -1)

    if [ -z "$download_url" ]; then _error "鏃犳硶鑾峰彇 sing-box 涓嬭浇閾炬帴 (鎼滅储: ${search_pattern})銆?; return 1; fi

    temp_dir=$(mktemp -d /root/.singbox-install.XXXXXX) || { _error "鍒涘缓涓存椂鐩綍澶辫触銆?; return 1; }
    archive_path="${temp_dir}/sing-box.tar.gz"

    _info "姝ｅ湪涓嬭浇 sing-box 瀹夎鍖?.."
    if ! wget -qO "$archive_path" "$download_url"; then
        _error "涓嬭浇澶辫触: $download_url"
        rm -rf "$temp_dir"
        return 1
    fi

    _info "姝ｅ湪瑙ｅ帇 sing-box 瀹夎鍖?.."
    if ! tar -xzf "$archive_path" -C "$temp_dir"; then
        _error "瑙ｅ帇 sing-box 瀹夎鍖呭け璐ワ紝涓存椂鐩綍淇濈暀: $temp_dir"
        return 1
    fi

    extracted_bin=$(find "$temp_dir" -name sing-box -type f 2>/dev/null | head -n 1)
    if [ -z "$extracted_bin" ]; then
        _error "瑙ｅ帇鍚庢湭鎵惧埌 sing-box 浜岃繘鍒舵枃浠讹紝涓存椂鐩綍淇濈暀: $temp_dir"
        return 1
    fi

    rm -f "$archive_path"

    _info "姝ｅ湪瀹夎 sing-box 浜岃繘鍒舵枃浠?.."
    mkdir -p "$(dirname "$SINGBOX_BIN")" || {
        _error "鍒涘缓瀹夎鐩綍澶辫触: $(dirname "$SINGBOX_BIN")"
        return 1
    }
    if ! mv -f "$extracted_bin" "$SINGBOX_BIN"; then
        _error "瀹夎 sing-box 浜岃繘鍒舵枃浠跺け璐? $SINGBOX_BIN"
        _error "涓存椂鐩綍淇濈暀: $temp_dir"
        return 1
    fi
    if ! chmod +x "$SINGBOX_BIN"; then
        _error "璁剧疆 sing-box 鍙墽琛屾潈闄愬け璐? $SINGBOX_BIN"
        _error "涓存椂鐩綍淇濈暀: $temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"
    _release_install_cache
    _success "sing-box 瀹夎鎴愬姛: ${SINGBOX_BIN}"
}

_install_cloudflared() {
    if [ -f "${CLOUDFLARED_BIN}" ]; then
        _info "cloudflared 宸插畨瑁? $(${CLOUDFLARED_BIN} --version 2>&1 | head -n1)"
        return 0
    fi
    
    _info "姝ｅ湪瀹夎渚濇嵁鐜鎵€闇€鐨勭粍浠?(ca-certificates)..."
    _pkg_install ca-certificates # 鍏抽敭淇锛欰lpine 绛夌簿绠€绯荤粺蹇呴』鏈夎瘉涔︽墠鑳借繘琛?TLS 鎻℃墜
    
    _info "姝ｅ湪瀹夎 cloudflared..."
    local arch=$(uname -m)
    local arch_tag
    case $arch in
        x86_64|amd64) arch_tag='amd64' ;;
command_args="run -c ${CONFIG_FILE} -c ${SINGBOX_DIR}/relay.json"
# 浣跨敤 supervise-daemon 瀹炵幇瀹堟姢鍜岄噸鍚?supervisor="supervise-daemon"
supervise_daemon_args="--env GOMEMLIMIT=${mem_limit_mb}MiB --env ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true --env ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true --env ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true"
respawn_delay=3
respawn_max=0

pidfile="${PID_FILE}"
# supervise-daemon 鑷姩灏?stdout/stderr 閲嶅畾鍚戝姛鑳介渶瑕?openrc 鐗堟湰鏀寔
# 濡傛灉涓嶆敮鎸侊紝鏃ュ織鍙兘涓嶄細杈撳嚭鍒版枃浠讹紝浣嗘湇鍔¤兘姝ｅ父杩愯
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"

depend() {
    need net
    after firewall
}
EOF
    chmod +x "$SERVICE_FILE"
}

_create_service_files() {
    
    _info "姝ｅ湪鍒涘缓 ${INIT_SYSTEM} 鏈嶅姟鏂囦欢..."
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        _create_systemd_service
        systemctl daemon-reload
        systemctl enable sing-box
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        touch "$LOG_FILE"
        _create_openrc_service
        rc-update add sing-box default
    fi
    _success "${INIT_SYSTEM} 鏈嶅姟鍒涘缓骞跺惎鐢ㄦ垚鍔熴€?
}


# 娉ㄦ剰: _manage_service 宸插湪涓婃柟瀹氫箟锛屾澶勪笉鍐嶉噸澶嶅畾涔?
_view_log() {
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        _info "鎸?Ctrl+C 閫€鍑烘棩蹇楁煡鐪嬨€?
        journalctl -u sing-box -f --no-pager
    else # 閫傜敤浜?openrc 鍜?direct 妯″紡
        if [ ! -f "$LOG_FILE" ]; then
            _warning "鏃ュ織鏂囦欢 ${LOG_FILE} 涓嶅瓨鍦ㄣ€?
            return
        fi
        _info "鎸?Ctrl+C 閫€鍑烘棩蹇楁煡鐪?(鏃ュ織鏂囦欢: ${LOG_FILE})銆?
        tail -f "$LOG_FILE"
    fi
}

_uninstall() {
    _warning "锛侊紒锛佽鍛婏紒锛侊紒"
    _warning "鏈搷浣滃皢鍋滄骞剁鐢?[涓昏剼鏈琞 鏈嶅姟 (sing-box)锛?
    _warning "鍒犻櫎鎵€鏈夌浉鍏虫枃浠?(鍖呮嫭浜岃繘鍒躲€佺粍浠惰剼鏈€佸埆鍚嶅強閰嶇疆鏂囦欢)銆?
    
    echo ""
    echo "即将删除以下内容："
    echo -e "  ${RED}-${NC} 主配置与脚本目录: ${SINGBOX_DIR}"
    echo -e "  ${RED}-${NC} sing-box 二进制: ${SINGBOX_BIN}"
    echo -e "  ${RED}-${NC} yq 二进制: ${YQ_BINARY}"
    [ -f "/usr/local/bin/xray" ] && echo -e "  ${RED}-${NC} Xray 核心及配置: /usr/local/etc/xray/"
    echo -e "  ${RED}-${NC} 绯荤粺鍒悕: /usr/local/bin/sb"
    echo -e "  ${RED}-${NC} 绠＄悊鑴氭湰: ${SELF_SCRIPT_PATH}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"纭畾瑕佹墽琛屽嵏杞藉悧? (y/N): "${NC})" confirm_main
    [[ "$confirm_main" != "y" && "$confirm_main" != "Y" ]] && _info "鍗歌浇宸插彇娑堛€? && return

    # 1. 鍋滄鏈嶅姟
    _manage_service "stop"
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        systemctl disable sing-box >/dev/null 2>&1
        systemctl daemon-reload
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        rc-update del sing-box default >/dev/null 2>&1
    fi

    # 2. 娓呯悊閰嶇疆涓庢棩蹇?    _info "姝ｅ湪娓呯悊閰嶇疆鏂囦欢涓庢棩蹇?.."
    # 娓呯悊绔彛杞彂鐨?iptables 瑙勫垯 (鍐呰仈鎵ц锛岄伩鍏?source 鏁翠釜鑴氭湰瀵艰嚧 _menu 琚皟鐢?
    local pf_meta="${SINGBOX_DIR}/relay_pf.json"
    [ ! -f "$pf_meta" ] && pf_meta="${SINGBOX_DIR}/pf_metadata.json"
    if [ -f "$pf_meta" ] && command -v jq &>/dev/null; then
        _info "姝ｅ湪娓呯悊绔彛杞彂瑙勫垯 (iptables)..."
        local _pf_ports
        _pf_ports=$(jq -r 'keys[]' "$pf_meta" 2>/dev/null)
        for _pf_p in $_pf_ports; do
            local _pf_eng=$(jq -r --arg p "$_pf_p" '.[$p].engine // empty' "$pf_meta" 2>/dev/null)
            local _pf_net=$(jq -r --arg p "$_pf_p" '.[$p].network // empty' "$pf_meta" 2>/dev/null)
            local _pf_addr=$(jq -r --arg p "$_pf_p" '.[$p].target_addr // empty' "$pf_meta" 2>/dev/null)
            local _pf_tport=$(jq -r --arg p "$_pf_p" '.[$p].target_port // empty' "$pf_meta" 2>/dev/null)
            local _pf_resolved=$(jq -r --arg p "$_pf_p" '.[$p].resolved_ip // empty' "$pf_meta" 2>/dev/null)
            local _pf_del_dest="${_pf_resolved:-$_pf_addr}"
            
            if [ "$_pf_eng" == "iptables" ] && [ -n "$_pf_del_dest" ]; then
                if [[ "$_pf_net" == "tcp" || "$_pf_net" == "tcp+udp" ]]; then
                    iptables -t nat -D PREROUTING -p tcp --dport "$_pf_p" -j DNAT --to-destination "${_pf_del_dest}:${_pf_tport}" 2>/dev/null
                    iptables -t nat -D OUTPUT -p tcp --dport "$_pf_p" -j DNAT --to-destination "${_pf_del_dest}:${_pf_tport}" 2>/dev/null
                fi
                if [[ "$_pf_net" == "udp" || "$_pf_net" == "tcp+udp" ]]; then
                    iptables -t nat -D PREROUTING -p udp --dport "$_pf_p" -j DNAT --to-destination "${_pf_del_dest}:${_pf_tport}" 2>/dev/null
                    iptables -t nat -D OUTPUT -p udp --dport "$_pf_p" -j DNAT --to-destination "${_pf_del_dest}:${_pf_tport}" 2>/dev/null
                fi
                iptables -t nat -D POSTROUTING -d "$_pf_del_dest" -j MASQUERADE 2>/dev/null
            fi
        done
        
        # 娓呯悊 DNS 鍔ㄦ€佸埛鏂扮殑 cron 浠诲姟
        if crontab -l 2>/dev/null | grep -qF "# pf-dns-auto-refresh"; then
            crontab -l 2>/dev/null | grep -vF "# pf-dns-auto-refresh" | crontab -
        fi
        # 淇濆瓨 iptables 瑙勫垯
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules 2>/dev/null
        fi
        if command -v ip6tables-save &>/dev/null; then
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || ip6tables-save > /etc/ip6tables.rules 2>/dev/null
        fi
    fi
    rm -rf "${SINGBOX_DIR}" "${LOG_FILE}"
    
    # 3. 清理 Xray 核心 (如果已安装
    if [ -f "/usr/local/bin/xray" ]; then
        _info "姝ｅ湪娓呯悊 Xray 鏍稿績..."
        if [ "$INIT_SYSTEM" == "systemd" ]; then
            systemctl stop xray 2>/dev/null
            systemctl disable xray 2>/dev/null
            rm -f /etc/systemd/system/xray.service
            systemctl daemon-reload
        elif [ "$INIT_SYSTEM" == "openrc" ]; then
            rc-service xray stop 2>/dev/null
            rc-update del xray default 2>/dev/null
            rm -f /etc/init.d/xray
        fi
        rm -f "/usr/local/bin/xray"
        rm -rf "/usr/local/etc/xray"
    fi

    # 5. 娓呯悊缁勪欢鑴氭湰涓庡埆鍚?(鍙岄噸娓呯悊锛岄槻姝㈢洰褰曞悎骞跺悗鐨勭墿鐞嗘畫鐣?
    _info "姝ｅ湪娓呯悊鍛ㄨ竟鐜..."
    rm -f "${SINGBOX_DIR}/parser.sh" "${SINGBOX_DIR}/advanced_relay.sh" "${SINGBOX_DIR}/xray_manager.sh"
    rm -f "${SCRIPT_DIR}/parser.sh" "${SCRIPT_DIR}/advanced_relay.sh" "${SCRIPT_DIR}/xray_manager.sh"
    rm -f "/usr/local/bin/sb"
    
    # 5. 澶嶅師 MOTD
    if [ -f "/etc/motd" ]; then
        sed -i '/sing-box 鑺傜偣淇℃伅/d' /etc/motd 2>/dev/null
        sed -i '/====/d' /etc/motd 2>/dev/null
        sed -i '/Base64 璁㈤槄/d' /etc/motd 2>/dev/null
    fi

    # 6. 澶勭悊涓荤▼搴?(鑰冭檻涓庣嚎璺満鍏辩敤)
    local relay_script="/root/relay-install.sh"
    if [ -f "$relay_script" ]; then
        _warn "妫€娴嬪埌 [绾胯矾鏈篯 鑴氭湰瀛樺湪锛屼负淇濇寔鍏惰繍琛岋紝灏?[淇濈暀] sing-box 涓荤▼搴忋€?
    else
        _info "姝ｅ湪鍒犻櫎 sing-box 涓荤▼搴?.."
        rm -f "${SINGBOX_BIN}" "${YQ_BINARY}"
    fi

    _success "娓呯悊瀹屾垚銆傝剼鏈凡鑷瘉銆傚啀瑙侊紒"
    [ -f "${SELF_SCRIPT_PATH}" ] && rm -f "${SELF_SCRIPT_PATH}"
    exit 0
}

_initialize_config_files() {
    mkdir -p ${SINGBOX_DIR}
    if [ ! -s "$CONFIG_FILE" ]; then
        # 鍒濆鍖栧寘鍚畬鏁?dns 閰嶇疆鍜岃矾鐢辩瓥鐣ョ殑鍩虹鏂囦欢锛屼互鏀寔涓浆绗笁鏂瑰煙鍚嶈妭鐐癸紝闃叉薄鏌撳苟瑙勯伩 IPv6 鎻℃墜榛戞礊闂
        cat > "$CONFIG_FILE" << 'EOF'
{
  "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m"
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "direct"
      },
      {
        "tag": "dns-aliyun",
        "address": "https://223.5.5.5/dns-query",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "dns-cloudflare"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
EOF
    fi
    [ -s "$METADATA_FILE" ] || echo "{}" > "$METADATA_FILE"
    
    # [鍏抽敭淇] 鍒濆鍖?relay.json - 鏈嶅姟鍚姩鍛戒护浼氬姞杞借繖涓枃浠?    # 蹇呴』纭繚鍦ㄦ湇鍔¤繍琛屽墠姝ゆ枃浠剁墿鐞嗗瓨鍦紝鍚﹀垯 sing-box 浼?Fatal 閫€鍑?    local RELAY_JSON="${SINGBOX_DIR}/relay.json"
    if [ ! -s "$RELAY_JSON" ]; then
        echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "$RELAY_JSON"
        _info "宸插垵濮嬪寲涓浆閰嶇疆鏂囦欢: $RELAY_JSON"
    fi
    if [ ! -s "$CLASH_YAML_FILE" ]; then
        _info "姝ｅ湪鍒涘缓鍏ㄦ柊鐨?clash.yaml 閰嶇疆鏂囦欢..."
        cat > "$CLASH_YAML_FILE" << 'EOF'
port: 7890
socks-port: 7891
mixed-port: 7892
allow-lan: false
bind-address: '*'
mode: rule
log-level: info
ipv6: false
find-process-mode: strict
external-controller: '127.0.0.1:9090'
profile:
  store-selected: true
  store-fake-ip: true
unified-delay: true
tcp-concurrent: true
ntp:
  enable: true
  write-to-system: false
  server: ntp.aliyun.com
  port: 123
  interval: 30
dns:
  enable: true
  respect-rules: true
  use-system-hosts: true
  prefer-h3: false
  listen: '0.0.0.0:1053'
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  fake-ip-filter:
    - +.lan
    - +.local
    - localhost.ptlogin2.qq.com
    - +.msftconnecttest.com
    - +.msftncsi.com
  nameserver:
    - 1.1.1.1
    - 8.8.8.8
    - 'https://1.1.1.1/dns-query'
    - 'https://dns.quad9.net/dns-query'
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  proxy-server-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 'https://1.0.0.1/dns-query'
    - 'https://9.9.9.10/dns-query'
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  strict-route: false
  dns-hijack:
    - 'any:53'
  device: SakuraiTunnel
  endpoint-independent-nat: true
proxies: []
proxy-groups:
  - name: 鑺傜偣閫夋嫨
    type: select
    proxies: []
rules:
  - GEOIP,PRIVATE,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,鑺傜偣閫夋嫨
EOF
    fi
}

_init_relay_config() {
    # 纭繚涓浆閰嶇疆鏂囦欢瀛樺湪 (闅旂閰嶇疆)
    if [ ! -s "${SINGBOX_DIR}/relay.json" ]; then
        echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "${SINGBOX_DIR}/relay.json"
        _info "宸插垵濮嬪寲涓浆閰嶇疆鏂囦欢"
    fi
}

_cleanup_legacy_config() {
    # 妫€鏌ュ苟娓呯悊 config.json 涓畫鐣欑殑鏃х増涓浆閰嶇疆 (tag 浠?relay-out- 寮€澶寸殑 outbound)
    # 杩欎簺娈嬬暀浼氬鑷磋矾鐢卞啿绐侊紝浣夸富鑴氭湰鑺傜偣璇蛋涓浆绾胯矾
    local needs_restart=false
    
    if jq -e '.outbounds[] | select(.tag | startswith("relay-out-"))' "$CONFIG_FILE" >/dev/null 2>&1; then
        _warn "妫€娴嬪埌鏃х増涓浆娈嬬暀閰嶇疆锛屾鍦ㄦ竻鐞?.."
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_legacy"
        
        # 鍒犻櫎鎵€鏈?relay-out- 寮€澶寸殑 outbounds
        jq 'del(.outbounds[] | select(.tag | startswith("relay-out-")))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        
        # 鍒犻櫎鎵€鏈?relay-out- 寮€澶寸殑璺敱瑙勫垯 (濡傛灉鏈?
        if jq -e '.route.rules' "$CONFIG_FILE" >/dev/null 2>&1; then
            jq 'del(.route.rules[] | select(.outbound | startswith("relay-out-")))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
        
        # 纭繚瀛樺湪 direct 鍑虹珯涓斾綅浜庣涓€浣?(濡傛灉娌℃湁 direct锛屾坊鍔犱竴涓?
        if ! jq -e '.outbounds[] | select(.tag == "direct")' "$CONFIG_FILE" >/dev/null 2>&1; then
             jq '.outbounds = [{"type":"direct","tag":"direct"}] + .outbounds' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
        
        _success "閰嶇疆娓呯悊瀹屾垚銆傜浉鍏充腑杞凡琚縼绉昏嚦鐙珛閰嶇疆鏂囦欢 (relay.json)銆?
        needs_restart=true
    fi
    
    # [鍏抽敭淇] 纭繚 route.final 璁剧疆涓?"direct"
    # 杩欐槸鏍稿績淇锛氬綋 config.json 鍜?relay.json 鍚堝苟鏃讹紝relay-out-* outbound 浼氳鎻掑叆鍒?outbounds 鍒楄〃鍓嶉潰
    # 濡傛灉娌℃湁 route.final锛宻ing-box 浼氫娇鐢ㄥ垪琛ㄤ腑鐨勭涓€涓?outbound 浣滀负榛樿鍑哄彛锛屽鑷翠富鑺傜偣娴侀噺璧颁腑杞?    if ! jq -e '.route.final == "direct"' "$CONFIG_FILE" >/dev/null 2>&1; then
        _warn "妫€娴嬪埌 route.final 鏈缃垨涓嶆纭紝姝ｅ湪淇..."
        
        # 纭繚 route 瀵硅薄瀛樺湪
        if ! jq -e '.route' "$CONFIG_FILE" >/dev/null 2>&1; then
            jq '. + {"route":{"rules":[],"final":"direct"}}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        else
            # 璁剧疆 route.final = "direct"
            jq '.route.final = "direct"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
        
        _success "route.final 宸茶缃负 direct锛屼富鑺傜偣娴侀噺灏嗚蛋鏈満 IP銆?
        needs_restart=true
    fi
    
    if [ "$needs_restart" = true ]; then
        return 0
    fi
    return 1
}

_check_and_fix_dns() {
    # 鐑慨澶嶏細1.琛ュ厖缂哄け鐨?DNS 妯″潡锛?.灏嗗鏄撳紩璧峰嚭绔欒矾鐢辩粦瀹氭寰幆锛堣繛鎺ヨ绉掗噸缃級鐨?auto_detect_interface 娓呴櫎
    # 骞朵笖鍏ㄩ潰鍗囩骇涓?DoH (闃块噷 + CF) 涓?ipv4_only 绛栫暐闃叉琚薄鏌撶殑鍩熷悕瑙ｆ瀽鎵撳瓟澶辫触
    if [ ! -f "$CONFIG_FILE" ]; then return; fi
    
    local has_dns=$(jq 'has("dns")' "$CONFIG_FILE" 2>/dev/null)
    local has_auto_detect=$(jq 'try .route.auto_detect_interface catch false' "$CONFIG_FILE" 2>/dev/null)
    local needs_restart=false
    
    if [ "$has_dns" == "false" ] || [ "$has_auto_detect" == "true" ]; then
        _warn "妫€娴嬪埌鎮ㄧ殑閰嶇疆鏂囦欢瀛樺湪褰卞搷鑺傜偣杞彂鐨勫簳灞傞殣鎮?(缂轰箯闃叉薄鏌?DNS / 鍚敤浜嗕笉鑹矾鐢?锛屾鍦ㄨ嚜鍔ㄤ慨澶?.."
        
        local tmp_file="${CONFIG_FILE}.tmp"
        # 1. 娉ㄥ叆鐜颁唬闃叉薄鏌?DNS 2. 绉婚櫎鑷姩缃戝崱鎺㈡祴
        jq '. + {
            "dns": {
                "servers": [
                    {"tag": "dns-cloudflare", "address": "https://1.1.1.1/dns-query", "detour": "direct"},
                    {"tag": "dns-aliyun", "address": "https://223.5.5.5/dns-query", "detour": "direct"}
                ],
                "rules": [{"outbound": "any", "server": "dns-cloudflare"}],
                "strategy": "ipv4_only"
            }
        } | del(.route.auto_detect_interface)' "$CONFIG_FILE" > "$tmp_file"
        
        if [ $? -eq 0 ] && [ -s "$tmp_file" ]; then
            mv "$tmp_file" "$CONFIG_FILE"
            _success "楂樼骇 DNS 涓庤矾鐢卞弬鏁扮儹淇瀹屾垚锛?
            needs_restart=true
        else
            _error "楂樼骇淇搴旂敤澶辫触锛?
            rm -f "$tmp_file"
        fi
    fi
    
    if [ "$needs_restart" == "true" ]; then
        return 0
    fi
    return 1
}

_generate_self_signed_cert() {
    local domain="$1"
    local cert_path="$2"
    local key_path="$3"

    _info "姝ｅ湪涓?${domain} 鐢熸垚鏀寔 SAN 鐨勯珮绾ц嚜绛惧悕璇佷功..."
    
    # 鍒涘缓涓存椂閰嶇疆鏂囦欢鐢ㄤ簬鐢熸垚 SAN
    local openssl_config=$(mktemp)
    cat > "$openssl_config" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = ${domain}
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${domain}
DNS.2 = *.${domain}
EOF

    # 浣跨敤 RSA 2048 鐢熸垚璇佷功 (CF 鍥炴簮鍏煎鎬ф洿浣?
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -keyout "$key_path" -out "$cert_path" \
        -config "$openssl_config" >/dev/null 2>&1
    
    local status=$?
    rm -f "$openssl_config"

    if [ $status -ne 0 ]; then
        _error "涓?${domain} 鐢熸垚璇佷功澶辫触锛?
        rm -f "$cert_path" "$key_path"
        return 1
    fi
    _success "璇佷功 ${cert_path} (鍚?SAN) 宸叉垚鍔熺敓鎴愩€?
    return 0
}

# 娉ㄦ剰: _atomic_modify_json, _atomic_modify_yaml, _get_proxy_field, _add_node_to_yaml, _remove_node_from_yaml
# 鍧囧湪涓婃柟缁熶竴瀹氫箟锛屾澶勪笉鍐嶉噸澶嶅畾涔変互閬垮厤涓嶄竴鑷?
# 鏄剧ず鑺傜偣鍒嗕韩閾炬帴锛堝湪娣诲姞鑺傜偣鍚庤皟鐢級
# 鍙傛暟: $1=鍗忚绫诲瀷, $2=鑺傜偣鍚嶇О, $3=鏈嶅姟鍣↖P(鐢ㄤ簬閾炬帴), $4=绔彛, $5=鑺傜偣TAG, 鍏朵粬鍙傛暟鏍规嵁鍗忚涓嶅悓
_show_node_link() {
    local type="$1"
    local name="$2"
    local link_ip="$3"
    local port="$4"
    local tag="$5"
    # [鍏抽敭淇] 澶勭悊 IPv6 鎷彿鍖呰９閫昏緫
    if [[ "$link_ip" == *":"* ]] && [[ "$link_ip" != "["* ]]; then
        link_ip="[${link_ip}]"
    fi

    shift 5
    
    local url=""
    
    case "$type" in
        "vless-reality")
            # 鍙傛暟: uuid, sni, public_key, short_id, flow
            local uuid="$1" pk="$3" sid="$4" flow="${5:-xtls-rprx-vision}"
            # 瀵?SNI 鎵ц缁堟瀬淇濆簳涓庡噣鍖?            local sni=$(echo "$2" | xargs)
            [[ -z "$sni" ]] && sni="$DEFAULT_SNI"
            
            url="vless://${uuid}@${link_ip}:${port}?security=reality&encryption=none&pbk=$(_url_encode "${pk}")&fp=chrome&type=tcp&flow=${flow}&sni=${sni}&sid=${sid}#$(_url_encode "$name")"
            ;;
        "vless-ws-tls")
            # 鍙傛暟: uuid, sni, ws_path, skip_verify
            local uuid="$1" sni="${2:-$DEFAULT_SNI}" ws_path="$3" skip_verify="$4"
            local insecure_param=""
            [[ "$skip_verify" == "true" ]] && insecure_param="&insecure=1&allowInsecure=1"
            url="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&type=ws&host=${sni}&path=$(_url_encode "$ws_path")&sni=${sni}${insecure_param}#$(_url_encode "$name")"
            ;;
        "vless-tcp")
            # 鍙傛暟: uuid
            local uuid="$1"
            url="vless://${uuid}@${link_ip}:${port}?encryption=none&type=tcp#$(_url_encode "$name")"
            ;;
        "trojan-ws-tls")
            # 鍙傛暟: password, sni, ws_path, skip_verify
            local password="$1" sni="${2:-$DEFAULT_SNI}" ws_path="$3" skip_verify="$4"
            local insecure_param=""
            [[ "$skip_verify" == "true" ]] && insecure_param="&insecure=1&allowInsecure=1"
            url="trojan://${password}@${link_ip}:${port}?security=tls&type=ws&host=${sni}&path=$(_url_encode "$ws_path")&sni=${sni}${insecure_param}#$(_url_encode "$name")"
            ;;
        "hysteria2")
            # 鍙傛暟: password, sni, obfs_password(鍙€?, port_hopping(鍙€?
            local password="$1" sni="${2:-$DEFAULT_SNI}" obfs_password="$3" port_hopping="$4"
            local obfs_param=""; [[ -n "$obfs_password" ]] && obfs_param="&obfs=salamander&obfs-password=$(_url_encode "${obfs_password}")"
            local hop_param=""; [[ -n "$port_hopping" ]] && hop_param="&mport=${port_hopping}&ports=${port_hopping}"
            url="hysteria2://${password}@${link_ip}:${port}?sni=${sni}&insecure=1${obfs_param}${hop_param}#$(_url_encode "$name")"
            ;;
        "tuic")
            # 鍙傛暟: uuid, password, sni
            local uuid="$1" password="$2" sni="${3:-$DEFAULT_SNI}"
            url="tuic://${uuid}:${password}@${link_ip}:${port}?sni=${sni}&alpn=h3&congestion_control=bbr&udp_relay_mode=native&allow_insecure=1#$(_url_encode "$name")"
            ;;
        "anytls")
            # 鍙傛暟: password, sni, skip_verify
            local password="$1" sni="${2:-$DEFAULT_SNI}" skip_verify="$3"
            local insecure_param=""
            if [ "$skip_verify" == "true" ]; then
                insecure_param="&insecure=1&allowInsecure=1"
            fi
            url="anytls://${password}@${link_ip}:${port}?security=tls&sni=${sni}${insecure_param}#$(_url_encode "$name")"
            ;;
        "shadowsocks")
            # 鍙傛暟: method, password
            local method="$1" password="$2"
            local userinfo=$(echo -n "${method}:${password}" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
            url="ss://${userinfo}@${link_ip}:${port}#$(_url_encode "$name")"
            ;;
        "shadowsocks-shadowtls")
            # 鍙傛暟: method, pw, spw, sni
            local method="$1" pw="$2" spw="$3" sni="$4"
            url=""
            echo -e "${YELLOW}====== [瀹㈡埛绔厤缃弬鑰冪墖娈?(Clash Meta / Mihomo)] ======${NC}"
            echo -e "  - name: \"${name}\""
            echo -e "    type: ss"
            echo -e "    server: ${link_ip}"
            echo -e "    port: ${port}"
            echo -e "    cipher: ${method}"
            echo -e "    password: ${pw}"
            echo -e "    plugin: shadow-tls"
            echo -e "    plugin-opts:"
            echo -e "      host: ${sni}"
            echo -e "      password: ${spw}"
            echo -e "      version: 3"
            echo -e "${YELLOW}========================================================${NC}"
            echo -e "${CYAN}[鎻愮ず] ShadowTLS 闇€瑕佺壒瀹氱殑瀹㈡埛绔厤缃€?{NC}"
            echo -e "${CYAN}鎮ㄤ篃鍙互鐩存帴鎵撳紑鏈満浣嶄簬 ${YELLOW}/usr/local/etc/sing-box/clash.yaml${CYAN} 鐨勯厤缃枃浠讹紝${NC}"
            echo -e "${CYAN}鎵惧埌瀵瑰簲鑺傜偣鐨?YAML 浠ｇ爜鍧楋紝骞跺鍒跺埌鎮ㄧ殑瀹㈡埛绔腑浣跨敤锛?{NC}"
            ;;
        "vless-ws")
            # Argo 涓撶敤: uuid, path
            local uuid="$1" ws_path="$2"
            url="vless://${uuid}@${link_ip}:443?encryption=none&security=tls&type=ws&host=${link_ip}&path=$(_url_encode "$ws_path")&sni=${link_ip}#$(_url_encode "$name")"
            ;;
        "trojan-ws")
            # Argo 涓撶敤: password, path
            local password="$1" ws_path="$2"
            url="trojan://$(_url_encode "${password}")@${link_ip}:443?security=tls&type=ws&host=${link_ip}&path=$(_url_encode "$ws_path")&sni=${link_ip}#$(_url_encode "$name")"
            ;;
        "socks")
            # 鍙傛暟: username, password
            local username="$1" password="$2"
            echo ""
            _info "鑺傜偣淇℃伅: 鏈嶅姟鍣? ${link_ip}, 绔彛: ${port}, 鐢ㄦ埛鍚? ${username}, 瀵嗙爜: ${password}"
            return
            ;;
    esac
    
    if [ -n "$url" ]; then
        echo ""
        echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?鍒嗕韩閾炬帴 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{NC}"
        echo -e "${CYAN}${url}${NC}"
        echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{NC}"
        
        # [鎸佷箙鍖朷 灏嗙敓鎴愮殑閾炬帴瀛樺叆鍏冩暟鎹紝闃叉鏌ョ湅鏃剁敱浜庡姩鎬佹彁鍙栧鑷寸殑 SNI 涓㈠け
        if [ -n "$tag" ] && [ "$tag" != "null" ]; then
            if [[ "$tag" == argo-* ]]; then
                _atomic_modify_json "$ARGO_METADATA_FILE" ". + { \"$tag\": ((.[\"$tag\"] // {}) + { \"share_link\": \"$url\" }) }"
            else
                _atomic_modify_json "$METADATA_FILE" ". + { \"$tag\": ((.[\"$tag\"] // {}) + { \"share_link\": \"$url\" }) }"
            fi
        fi
    fi
}

_show_cdn_guidance() {
    local domain="$1"
    local port="$2"
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲 馃敡 濡備綍寮€鍚?Cloudflare CDN 浼橀€?鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    _info "濡傛灉鎮ㄥ笇鏈涘紑鍚?CDN 骞跺湪涔嬪悗浣跨敤浼橀€夊煙鍚?IP锛岃鎸夌収浠ヤ笅姝ラ閰嶇疆锛?
    _info "1. ${CYAN}銆怌F 鍚庡彴銆?{NC}灏嗚鍩熷悕鐨勮В鏋愯褰曞紑鍚皬榛勪簯 (${ORANGE}Proxied${NC})銆?
    _info "2. ${CYAN}銆怌F 鍚庡彴銆?{NC}鍦?[SSL/TLS] 鑿滃崟涓紝灏嗗姞瀵嗘ā寮忚涓? ${GREEN}Full (瀹屽叏)${NC}銆?
    if [ "$port" != "443" ]; then
        _warn "3. 鎮ㄧ殑鏈嶅姟鍣ㄧ洃鍚殑鏄?${port} 绔彛銆傝鍦?[Rules] -> [Origin Rules] 涓厤缃細"
        _warn "   - 涓绘満鍚?鍖呭惈 \"${domain}\" -> 閲嶅啓鍒扮鍙? ${port}"
    else
        _info "3. 鎮ㄧ殑鏈嶅姟鍣ㄥ凡鐩戝惉 443 绔彛锛屾棤闇€璁剧疆 Origin Rules銆?
    fi
    _info "4. ${CYAN}銆愬鎴风銆?{NC}淇敼閰嶇疆锛氬湴鍧€鏀逛负浼橀€夊煙鍚?IP锛岀鍙ｆ敼涓?${GREEN}443${NC}銆?
    _info "   (娉細Host/SNI 蹇呴』淇濇寔涓烘偍鐨勫煙鍚?${domain})"
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
}


_add_vless_ws_tls() {
    local camouflage_domain=""
    local port=""
    local client_server_addr="${server_ip}"

    if [ "$BATCH_MODE" = "true" ]; then
        [[ -n "$BATCH_IP" ]] && client_server_addr="$BATCH_IP"
        port="$BATCH_PORT"
        camouflage_domain="${BATCH_WS_TLS_DOMAIN:-$BATCH_SNI}"
    else
        _info "--- VLESS (WebSocket+TLS) 璁剧疆鍚戝 ---"
        _info "璇疯緭鍏ュ鎴风鐢ㄤ簬鈥滆繛鎺モ€濈殑鍦板潃:"
        _info "  - (鎺ㄨ崘) 鐩存帴鍥炶溅, 浣跨敤VPS鐨勫叕缃?IP: ${server_ip}"
        _info "  - (鍏朵粬) 鎮ㄤ篃鍙互鎵嬪姩杈撳叆涓€涓狪P鎴栧煙鍚?
        read -p "璇疯緭鍏ヨ繛鎺ュ湴鍧€ (榛樿: ${server_ip}): " connection_address
        client_server_addr=${connection_address:-$server_ip}
        
        # IPv6 澶勭悊
        if [[ "$client_server_addr" == *":"* ]] && [[ "$client_server_addr" != "["* ]]; then
             client_server_addr="[${client_server_addr}]"
        fi

        _info "璇疯緭鍏ユ偍鐨勨€滀吉瑁呭煙鍚嶁€濓紝杩欎釜鍩熷悕蹇呴』鏄偍璇佷功瀵瑰簲鐨勫煙鍚嶃€?
        _info " (渚嬪: xxx.741865.xyz)"
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚? " camouflage_domain
        [[ -z "$camouflage_domain" ]] && _error "浼鍩熷悕涓嶈兘涓虹┖" && return 1

        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙?(鐩磋繛妯″紡涓嬮鎺?443 绔彛): " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
    fi

    # 瀹㈡埛绔繛鎺ョ鍙ｉ粯璁や笌鐩戝惉绔彛涓€鑷?(鐩磋繛妯″紡)
    local client_port="$port"

    # --- 姝ラ 4: 璺緞 ---
    local ws_path=""
    if [ "$BATCH_MODE" = "true" ]; then
        ws_path="/"$(${SINGBOX_BIN} generate rand --hex 8)
    else
        read -p "璇疯緭鍏?WebSocket 璺緞 (鍥炶溅鍒欓殢鏈虹敓鎴?: " input_ws_path
        if [ -z "$input_ws_path" ]; then
            ws_path="/"$(${SINGBOX_BIN} generate rand --hex 8)
            _info "宸蹭负鎮ㄧ敓鎴愰殢鏈?WebSocket 璺緞: ${ws_path}"
        else
            ws_path="$input_ws_path"
            [[ ! "$ws_path" == /* ]] && ws_path="/${ws_path}"
        fi
    fi

    # 鎻愬墠瀹氫箟 tag锛岀敤浜庤瘉涔︽枃浠跺懡鍚?    local tag="vless-ws-in-${port}"
    local cert_path=""
    local key_path=""
    local skip_verify=false

    # --- 姝ラ 5: 璇佷功閫夋嫨 ---
    local cert_choice="1"
    if [ "$BATCH_MODE" = "true" ]; then
        cert_choice="1"
    else
        echo ""
        echo "璇烽€夋嫨璇佷功绫诲瀷:"
        echo "  1) 鑷姩鐢熸垚鑷鍚嶈瘉涔?(閫傚悎CF鍥炴簮/鐩磋繛璺宠繃楠岃瘉)"
        echo "  2) 鎵嬪姩涓婁紶璇佷功鏂囦欢 (acme.sh绛惧彂/Cloudflare婧愯瘉涔︾瓑)"
        read -p "璇烽€夋嫨 [1-2] (榛樿: 1): " cert_choice
        cert_choice=${cert_choice:-1}
    fi

    if [ "$cert_choice" == "1" ]; then
        # 鑷鍚嶈瘉涔?        cert_path="${SINGBOX_DIR}/${tag}.pem"
        key_path="${SINGBOX_DIR}/${tag}.key"
        _generate_self_signed_cert "$camouflage_domain" "$cert_path" "$key_path" || return 1
        skip_verify=true
        _info "宸茬敓鎴愯嚜绛惧悕璇佷功锛屽鎴风灏嗚烦杩囪瘉涔﹂獙璇併€?
    else
        # 鎵嬪姩涓婁紶璇佷功
        _info "璇疯緭鍏?${camouflage_domain} 瀵瑰簲鐨勮瘉涔︽枃浠惰矾寰勩€?
        _info "  - (鎺ㄨ崘) 浣跨敤 acme.sh 绛惧彂鐨?fullchain.pem"
        _info "  - (鎴?   浣跨敤 Cloudflare 婧愭湇鍔″櫒璇佷功"
        read -p "璇疯緭鍏ヨ瘉涔︽枃浠?.pem/.crt 鐨勫畬鏁磋矾寰? " cert_path
        [[ ! -f "$cert_path" ]] && _error "璇佷功鏂囦欢涓嶅瓨鍦? ${cert_path}" && return 1

        read -p "璇疯緭鍏ョ閽ユ枃浠?.key 鐨勫畬鏁磋矾寰? " key_path
        [[ ! -f "$key_path" ]] && _error "绉侀挜鏂囦欢涓嶅瓨鍦? ${key_path}" && return 1
        
        # 璇㈤棶鏄惁璺宠繃楠岃瘉
        read -p "$(echo -e ${YELLOW}"鎮ㄦ槸鍚︽鍦ㄤ娇鐢?Cloudflare 婧愭湇鍔″櫒璇佷功 (鎴栬嚜绛惧悕璇佷功)? (y/N): "${NC})" use_origin_cert
        if [[ "$use_origin_cert" == "y" || "$use_origin_cert" == "Y" ]]; then
            skip_verify=true
            _warning "宸插惎鐢?'skip-cert-verify: true'銆傝繖灏嗚烦杩囪瘉涔﹂獙璇併€?
        fi
    fi
    
    # [!] 鑷畾涔夊悕绉?    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-VLESS-WS-${port}"
    else
        local default_name="VLESS-WS-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi

    local uuid=$(${SINGBOX_BIN} generate uuid)
    
    # Inbound (鏈嶅姟鍣ㄧ) 閰嶇疆
    local inbound_json=$(jq -n \
        --arg t "$tag" \
        --arg p "$port" \
        --arg u "$uuid" \
        --arg cp "$cert_path" \
        --arg kp "$key_path" \
        --arg sn "$camouflage_domain" \
        --arg wsp "$ws_path" \
        '{
            "type": "vless",
            "tag": $t,
            "listen": "::",
            "listen_port": ($p|tonumber),
            "users": [{"uuid": $u, "flow": ""}],
            "tls": {
                "enabled": true,
                "server_name": $sn,
                "certificate_path": $cp,
                "key_path": $kp
            },
            "transport": {
                "type": "ws",
                "path": $wsp
            }
        }')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1

    # Proxy (瀹㈡埛绔? 閰嶇疆
    local proxy_json=$(jq -n \
            --arg n "$name" \
            --arg s "$client_server_addr" \
            --arg p "$client_port" \
            --arg u "$uuid" \
            --arg sn "$camouflage_domain" \
            --arg wsp "$ws_path" \
            --arg skip_verify_bool "$skip_verify" \
            --arg host_header "$camouflage_domain" \
            '{
                "name": $n,
                "type": "vless",
                "server": $s,
                "port": ($p|tonumber),
                "uuid": $u,
                "encryption": "none",
                "tls": true,
                "udp": true,
                "skip-cert-verify": ($skip_verify_bool == "true"),
                "network": "ws",
                "sni": $sn,
                "ws-opts": {
                    "path": $wsp,
                    "headers": {
                        "Host": $host_header
                    }
                }
            }')
            
    _add_node_to_yaml "$proxy_json"
    _success "VLESS (WebSocket+TLS) 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _success "瀹㈡埛绔繛鎺ュ湴鍧€ (server): ${client_server_addr}"
    _success "瀹㈡埛绔繛鎺ョ鍙?(port): ${client_port}"
    _success "瀹㈡埛绔吉瑁呭煙鍚?(sni/Host): ${camouflage_domain}"
    
    # CDN 鎸囧紩 (浠呭湪闈炴壒閲忔ā寮忎笅璇︾粏鏄剧ず)
    [ "$BATCH_MODE" != "true" ] && _show_cdn_guidance "${camouflage_domain}" "${port}"

    # IPv6 澶勭悊鐢ㄤ簬閾炬帴
    local link_ip="$client_server_addr"
    _show_node_link "vless-ws-tls" "$name" "$link_ip" "$client_port" "$tag" "$uuid" "$camouflage_domain" "$ws_path" "$skip_verify"
}

_add_trojan_ws_tls() {
    local camouflage_domain=""
    local port=""
    local client_server_addr="${server_ip}"

    if [ "$BATCH_MODE" = "true" ]; then
        [[ -n "$BATCH_IP" ]] && client_server_addr="$BATCH_IP"
        port="$BATCH_PORT"
        camouflage_domain="${BATCH_WS_TLS_DOMAIN:-$BATCH_SNI}"
    else
        _info "--- Trojan (WebSocket+TLS) 璁剧疆鍚戝 ---"
        _info "璇疯緭鍏ュ鎴风鐢ㄤ簬鈥滆繛鎺モ€濈殑鍦板潃:"
        _info "  - (鎺ㄨ崘) 鐩存帴鍥炶溅, 浣跨敤VPS鐨勫叕缃?IP: ${server_ip}"
        _info "  - (鍏朵粬) 鎮ㄤ篃鍙互鎵嬪姩杈撳叆涓€涓狪P鎴栧煙鍚?
        read -p "璇疯緭鍏ヨ繛鎺ュ湴鍧€ (榛樿: ${server_ip}): " connection_address
        client_server_addr=${connection_address:-$server_ip}
        
        # IPv6 澶勭悊
        if [[ "$client_server_addr" == *":"* ]] && [[ "$client_server_addr" != "["* ]]; then
             client_server_addr="[${client_server_addr}]"
        fi

        _info "璇疯緭鍏ユ偍鐨勨€滀吉瑁呭煙鍚嶁€濓紝杩欎釜鍩熷悕蹇呴』鏄偍璇佷功瀵瑰簲鐨勫煙鍚嶃€?
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚? " camouflage_domain
        [[ -z "$camouflage_domain" ]] && _error "浼鍩熷悕涓嶈兘涓虹┖" && return 1

        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙?(鐩磋繛妯″紡涓嬮鎺?443 绔彛): " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
    fi

    # 瀹㈡埛绔繛鎺ョ鍙ｉ粯璁や笌鐩戝惉绔彛涓€鑷?(鐩磋繛妯″紡)
    local client_port="$port"

    # --- 姝ラ 4: 璺緞 ---
    local ws_path=""
    if [ "$BATCH_MODE" = "true" ]; then
        ws_path="/"$(${SINGBOX_BIN} generate rand --hex 8)
    else
        read -p "璇疯緭鍏?WebSocket 璺緞 (鍥炶溅鍒欓殢鏈虹敓鎴?: " input_ws_path
        if [ -z "$input_ws_path" ]; then
            ws_path="/"$(${SINGBOX_BIN} generate rand --hex 8)
            _info "宸蹭负鎮ㄧ敓鎴愰殢鏈?WebSocket 璺緞: ${ws_path}"
        else
            ws_path="$input_ws_path"
            [[ ! "$ws_path" == /* ]] && ws_path="/${ws_path}"
        fi
    fi

    # 鎻愬墠瀹氫箟 tag锛岀敤浜庤瘉涔︽枃浠跺懡鍚?    local tag="trojan-ws-in-${port}"
    local cert_path=""
    local key_path=""
    local skip_verify=false

    # --- 姝ラ 5: 璇佷功閫夋嫨 ---
    if [ "$BATCH_MODE" = "true" ]; then
        cert_path="${SINGBOX_DIR}/${tag}.pem"
        key_path="${SINGBOX_DIR}/${tag}.key"
        _generate_self_signed_cert "$camouflage_domain" "$cert_path" "$key_path" || return 1
        skip_verify=true
    else
        echo ""
        echo "璇烽€夋嫨璇佷功绫诲瀷:"
        echo "  1) 鑷姩鐢熸垚鑷鍚嶈瘉涔?(閫傚悎CF鍥炴簮/鐩磋繛璺宠繃楠岃瘉)"
        echo "  2) 鎵嬪姩涓婁紶璇佷功鏂囦欢 (acme.sh绛惧彂/Cloudflare婧愯瘉涔︾瓑)"
        read -p "璇烽€夋嫨 [1-2] (榛樿: 1): " cert_choice
        cert_choice=${cert_choice:-1}
        if [ "$cert_choice" == "1" ]; then
            cert_path="${SINGBOX_DIR}/${tag}.pem"
            key_path="${SINGBOX_DIR}/${tag}.key"
            _generate_self_signed_cert "$camouflage_domain" "$cert_path" "$key_path" || return 1
            skip_verify=true
            _info "宸茬敓鎴愯嚜绛惧悕璇佷功锛屽鎴风灏嗚烦杩囪瘉涔﹂獙璇併€?
        else
            # 鎵嬪姩涓婁紶璇佷功
            _info "璇疯緭鍏?${camouflage_domain} 瀵瑰簲鐨勮瘉涔︽枃浠惰矾寰勩€?
            _info "  - (鎺ㄨ崘) 浣跨敤 acme.sh 绛惧彂鐨?fullchain.pem"
            _info "  - (鎴?   浣跨敤 Cloudflare 婧愭湇鍔″櫒璇佷功"
            read -p "璇疯緭鍏ヨ瘉涔︽枃浠?.pem/.crt 鐨勫畬鏁磋矾寰? " cert_path
            [[ ! -f "$cert_path" ]] && _error "璇佷功鏂囦欢涓嶅瓨鍦? ${cert_path}" && return 1

            read -p "璇疯緭鍏ョ閽ユ枃浠?.key 鐨勫畬鏁磋矾寰? " key_path
            [[ ! -f "$key_path" ]] && _error "绉侀挜鏂囦欢涓嶅瓨鍦? ${key_path}" && return 1
            
            # 璇㈤棶鏄惁璺宠繃楠岃瘉
            read -p "$(echo -e ${YELLOW}"鎮ㄦ槸鍚︽鍦ㄤ娇鐢?Cloudflare 婧愭湇鍔″櫒璇佷功 (鎴栬嚜绛惧悕璇佷功)? (y/N): "${NC})" use_origin_cert
            if [[ "$use_origin_cert" == "y" || "$use_origin_cert" == "Y" ]]; then
                skip_verify=true
                _warning "宸插惎鐢?'skip-cert-verify: true'銆傝繖灏嗚烦杩囪瘉涔﹂獙璇併€?
            fi
        fi
    fi

    # [!] Trojan: 浣跨敤瀵嗙爜
    local password=""
    if [ "$BATCH_MODE" = "true" ]; then
        password=$(${SINGBOX_BIN} generate rand --hex 16)
    else
        read -p "璇疯緭鍏?Trojan 瀵嗙爜 (鍥炶溅鍒欓殢鏈虹敓鎴?: " input_pw
        if [ -z "$input_pw" ]; then
            password=$(${SINGBOX_BIN} generate rand --hex 16)
            _info "宸蹭负鎮ㄧ敓鎴愰殢鏈哄瘑鐮? ${password}"
        else
            password="$input_pw"
        fi
    fi

    # [!] 鑷畾涔夊悕绉?    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-Trojan-WS-${port}"
    else
        local default_name="Trojan-WS-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi

    # Inbound (鏈嶅姟鍣ㄧ) 閰嶇疆
    local inbound_json=$(jq -n \
        --arg t "$tag" \
        --arg p "$port" \
        --arg pw "$password" \
        --arg cp "$cert_path" \
        --arg kp "$key_path" \
        --arg sn "$camouflage_domain" \
        --arg wsp "$ws_path" \
        '{
            "type": "trojan",
            "tag": $t,
            "listen": "::",
            "listen_port": ($p|tonumber),
            "users": [{"password": $pw}],
            "tls": {
                "enabled": true,
                "server_name": $sn,
                "certificate_path": $cp,
                "key_path": $kp
            },
            "transport": {
                "type": "ws",
                "path": $wsp
            }
        }')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1

    # Proxy (瀹㈡埛绔? 閰嶇疆
    local proxy_json=$(jq -n \
            --arg n "$name" \
            --arg s "$client_server_addr" \
            --arg p "$client_port" \
            --arg pw "$password" \
            --arg sn "$camouflage_domain" \
            --arg wsp "$ws_path" \
            --arg skip_verify_bool "$skip_verify" \
            --arg host_header "$camouflage_domain" \
            '{
                "name": $n,
                "type": "trojan",
                "server": $s,
                "port": ($p|tonumber),
                "password": $pw,
                "udp": true,
                "skip-cert-verify": ($skip_verify_bool == "true"),
                "network": "ws",
                "sni": $sn,
                "ws-opts": {
                    "path": $wsp,
                    "headers": {
                        "Host": $host_header
                    }
                }
            }')
            
    _add_node_to_yaml "$proxy_json"
    _success "Trojan (WebSocket+TLS) 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _success "瀹㈡埛绔繛鎺ュ湴鍧€ (server): ${client_server_addr}"
    _success "瀹㈡埛绔繛鎺ョ鍙?(port): ${client_port}"
    _success "瀹㈡埛绔吉瑁呭煙鍚?(sni/Host): ${camouflage_domain}"
    
    # CDN 鎸囧紩 (浠呭湪闈炴壒閲忔ā寮忎笅璇︾粏鏄剧ず)
    [ "$BATCH_MODE" != "true" ] && _show_cdn_guidance "${camouflage_domain}" "${port}"

    # IPv6 澶勭悊鐢ㄤ簬閾炬帴
    local link_ip="$client_server_addr"
    _show_node_link "trojan-ws-tls" "$name" "$link_ip" "$client_port" "$tag" "$password" "$camouflage_domain" "$ws_path" "$skip_verify"
}

_add_anytls() {
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    local server_name="www.amd.com"

    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        server_name="${BATCH_SNI:-www.amd.com}"
    else
        _info "--- 娣诲姞 AnyTLS 鑺傜偣 ---"
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?SNI (榛樿: www.amd.com): " camouflage_domain
        server_name=${camouflage_domain:-"www.amd.com"}
    fi
    
    # --- 姝ラ 4: 璇佷功閫夋嫨 ---
    local cert_choice="1"
    if [ "$BATCH_MODE" = "true" ]; then
        cert_choice="1"
    else
        echo ""
        echo "璇烽€夋嫨璇佷功绫诲瀷:"
        echo "  1) 鑷姩鐢熸垚鑷鍚嶈瘉涔?(鎺ㄨ崘)"
        echo "  2) 鎵嬪姩涓婁紶璇佷功鏂囦欢 (Cloudflare婧愯瘉涔︾瓑)"
        read -p "璇烽€夋嫨 [1-2] (榛樿: 1): " cert_choice
        cert_choice=${cert_choice:-1}
    fi
    
    local cert_path=""
    local key_path=""
    local skip_verify=true  # 榛樿璺宠繃楠岃瘉 (鑷璇佷功闇€瑕?
    local tag="anytls-in-${port}"
    
    if [ "$cert_choice" == "1" ]; then
        # 鑷鍚嶈瘉涔?        cert_path="${SINGBOX_DIR}/${tag}.pem"
        key_path="${SINGBOX_DIR}/${tag}.key"
        _generate_self_signed_cert "$server_name" "$cert_path" "$key_path" || return 1
        _info "宸茬敓鎴愯嚜绛惧悕璇佷功锛屽鎴风灏嗚烦杩囪瘉涔﹂獙璇併€?
    else
        # 鎵嬪姩涓婁紶璇佷功
        _info "璇疯緭鍏?${server_name} 瀵瑰簲鐨勮瘉涔︽枃浠惰矾寰勩€?
        read -p "璇疯緭鍏ヨ瘉涔︽枃浠?.pem/.crt 鐨勫畬鏁磋矾寰? " cert_path
        [[ ! -f "$cert_path" ]] && _error "璇佷功鏂囦欢涓嶅瓨鍦? ${cert_path}" && return 1
        
        read -p "璇疯緭鍏ョ閽ユ枃浠?.key 鐨勫畬鏁磋矾寰? " key_path
        [[ ! -f "$key_path" ]] && _error "绉侀挜鏂囦欢涓嶅瓨鍦? ${key_path}" && return 1
        
        # 璇㈤棶鏄惁璺宠繃楠岃瘉
        read -p "$(echo -e ${YELLOW}"鎮ㄦ槸鍚︽鍦ㄤ娇鐢ㄨ嚜绛惧悕璇佷功鎴朇loudflare婧愯瘉涔? (y/N): "${NC})" use_self_signed
        if [[ "$use_self_signed" == "y" || "$use_self_signed" == "Y" ]]; then
            skip_verify=true
            _warning "宸插惎鐢?'skip-cert-verify: true'锛屽鎴风灏嗚烦杩囪瘉涔﹂獙璇併€?
        else
            skip_verify=false
        fi
    fi
    
    # --- 姝ラ 5: 瀵嗙爜 (UUID 鏍煎紡) ---
    local password=""
    if [ "$BATCH_MODE" = "true" ]; then
        password=$(${SINGBOX_BIN} generate uuid)
    else
        read -p "璇疯緭鍏ュ瘑鐮?UUID (鍥炶溅鍒欓殢鏈虹敓鎴?: " input_pw
        password=${input_pw:-$(${SINGBOX_BIN} generate uuid)}
    fi
    
    # --- 姝ラ 6: 鑷畾涔夊悕绉?---
    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-AnyTLS-${port}"
    else
        local default_name="AnyTLS-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi
    
    # IPv6 澶勭悊
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"
    [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    # --- 鐢熸垚 Inbound 閰嶇疆 (鍖呭惈 padding_scheme) ---
    # padding_scheme 鏄?AnyTLS 鐨勬牳蹇冨姛鑳斤紝鐢ㄤ簬娴侀噺濉厖瀵规姉妫€娴?    local inbound_json=$(jq -n \
        --arg t "$tag" \
        --arg p "$port" \
        --arg pw "$password" \
        --arg sn "$server_name" \
        --arg cp "$cert_path" \
        --arg kp "$key_path" \
        '{
            "type": "anytls",
            "tag": $t,
            "listen": "::",
            "listen_port": ($p|tonumber),
            "users": [{"name": "default", "password": $pw}],
            "padding_scheme": [
                "stop=2",
                "0=100-200",
                "1=100-200"
            ],
            "tls": {
                "enabled": true,
                "alpn": ["http/1.1"],
                "certificate_path": $cp,
                "key_path": $kp
            }
        }')
    
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1
    
    # --- 鐢熸垚 Clash YAML 閰嶇疆 ---
    # 鏍规嵁鐢ㄦ埛鎻愪緵鐨勬牸寮忥細鍖呭惈 client-fingerprint, udp, alpn
    local proxy_json=$(jq -n \
        --arg n "$name" \
        --arg s "$yaml_ip" \
        --arg p "$port" \
        --arg pw "$password" \
        --arg sn "$server_name" \
        --arg skip_verify_bool "$skip_verify" \
        '{
            "name": $n,
            "type": "anytls",
            "server": $s,
            "port": ($p|tonumber),
            "password": $pw,
            "client-fingerprint": "chrome",
            "udp": true,
            "idle-session-check-interval": 30,
            "idle-session-timeout": 30,
            "min-idle-session": 0,
            "sni": $sn,
            "alpn": ["h2", "http/1.1"],
            "skip-cert-verify": ($skip_verify_bool == "true")
        }')
    
    _add_node_to_yaml "$proxy_json"
    
    # --- 淇濆瓨鍏冩暟鎹?---
    _atomic_modify_json "$METADATA_FILE" ". + {\"$tag\": {\"server_name\": \"$server_name\"}}" || return 1
    
    # --- 鐢熸垚鍒嗕韩閾炬帴 ---
    local insecure_param=""
    if [ "$skip_verify" == "true" ]; then
        insecure_param="&insecure=1&allowInsecure=1"
    fi
    local share_link="anytls://${password}@${link_ip}:${port}?security=tls&sni=${server_name}${insecure_param}&type=tcp#$(_url_encode "$name")"
    
    _success "AnyTLS 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _show_node_link "anytls" "$name" "$link_ip" "$port" "$tag" "$password" "$server_name" "$skip_verify"
}

_add_vless_reality() {
    [ -z "$server_ip" ] && server_ip=$(_get_ip)
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local server_name="www.amd.com"
    local port=""
    local name=""

    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        # 鎵归噺妯″紡鍙橀噺棰勫姞杞斤紝澧炲姞澶氬眰淇濆簳锛岄槻姝㈠彉閲忔硠闇?        server_name=$(echo "${BATCH_SNI}" | xargs)
        [[ -z "$server_name" ]] && server_name="$DEFAULT_SNI"
        name="Batch-Reality-${port}"
        # 鎵归噺妯″紡涓嬪鏋滀笉鏄惧紡鎸囧畾锛屽彲鑳戒涪澶?IP锛屾澶勮繘琛屽弻閲嶄繚闄?        [ -z "$node_ip" ] && node_ip="$server_ip"
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?(榛樿: www.amd.com): " camouflage_domain
        server_name=${camouflage_domain:-"www.amd.com"}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
        local default_name="VLESS-REALITY-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi

    local uuid=$(${SINGBOX_BIN} generate uuid)
    local keypair=$(${SINGBOX_BIN} generate reality-keypair)
    local private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}')
    local public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}')
    local short_id=$(${SINGBOX_BIN} generate rand --hex 8)
    local tag="vless-in-${port}"
    # IPv6澶勭悊锛歒AML鐢ㄥ師濮婭P锛岄摼鎺ョ敤甯]鐨処P
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    local inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg u "$uuid" --arg sn "$server_name" --arg pk "$private_key" --arg sid "$short_id" \
        '{"type":"vless","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"uuid":$u,"flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":$sn,"reality":{"enabled":true,"handshake":{"server":$sn,"server_port":443},"private_key":$pk,"short_id":[$sid]}}}')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1
    _atomic_modify_json "$METADATA_FILE" ". + {\"$tag\": {\"publicKey\": \"$public_key\", \"shortId\": \"$short_id\"}}" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg u "$uuid" --arg sn "$server_name" --arg pbk "$public_key" --arg sid "$short_id" \
        '{"name":$n,"type":"vless","server":$s,"port":($p|tonumber),"uuid":$u,"tls":true,"network":"tcp","flow":"xtls-rprx-vision","servername":$sn,"client-fingerprint":"chrome","reality-opts":{"public-key":$pbk,"short-id":$sid}}')
    _add_node_to_yaml "$proxy_json"
    _success "VLESS (REALITY) 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _show_node_link "vless-reality" "$name" "$link_ip" "$port" "$tag" "$uuid" "$server_name" "$public_key" "$short_id"
}

_add_vless_tcp() {
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        if [ -z "$port" ]; then
            _error "鎵归噺鍒涘缓閿欒: BATCH_PORT 涓虹┖锛岃烦杩?VLESS (TCP) 瀹夎銆?
            return 1
        fi
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
    fi
    # [!] 鑷畾涔夊悕绉?(鎵归噺妯″紡涓嬭嚜鍔ㄥ垎閰?
    local default_name="VLESS-TCP-${port}"
    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-TCP-${port}"
    else
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi

    local uuid=$(${SINGBOX_BIN} generate uuid)
    local tag="vless-tcp-in-${port}"
    # IPv6澶勭悊锛歒AML鐢ㄥ師濮婭P锛岄摼鎺ョ敤甯]鐨処P
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    local inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg u "$uuid" \
        '{"type":"vless","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"uuid":$u,"flow":""}],"tls":{"enabled":false}}')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg u "$uuid" \
        '{"name":$n,"type":"vless","server":$s,"port":($p|tonumber),"uuid":$u,"tls":false,"network":"tcp"}')
    _add_node_to_yaml "$proxy_json"
    _success "VLESS (TCP) 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _show_node_link "vless-tcp" "$name" "$link_ip" "$port" "$tag" "$uuid"
}

_add_hysteria2() {
    [ -z "$server_ip" ] && server_ip=$(_get_ip)
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    local server_name="www.amd.com"
    local obfs_password=""
    local port_hopping=""
    local use_multiport="false"

    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        if [ -z "$port" ]; then
            _error "鎵归噺鍒涘缓閿欒: BATCH_PORT 涓虹┖锛岃烦杩?Hysteria2 瀹夎銆?
            return 1
        fi
        server_name="$BATCH_SNI"
        # 鎵归噺妯″紡 double check
        [ -z "$node_ip" ] && node_ip="$server_ip"
        [ "$BATCH_HY2_OBFS" != "none" ] && obfs_password=$(${SINGBOX_BIN} generate rand --hex 16)
        port_hopping="$BATCH_HY2_HOP"
        if [ -n "$port_hopping" ]; then
            local port_range_start=$(echo $port_hopping | cut -d'-' -f1)
            local port_range_end=$(echo $port_hopping | cut -d'-' -f2)
            use_multiport="true"
        fi
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "udp" && continue
            break
        done
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?(榛樿: www.amd.com): " camouflage_domain
        server_name=${camouflage_domain:-"www.amd.com"}
    fi

    local tag="hy2-in-${port}"
    local cert_path="${SINGBOX_DIR}/${tag}.pem"
    local key_path="${SINGBOX_DIR}/${tag}.key"
    _generate_self_signed_cert "$server_name" "$cert_path" "$key_path" || return 1

    local password=""
    if [ "$BATCH_MODE" = "true" ]; then
        password=$(${SINGBOX_BIN} generate rand --hex 16)
    else
        read -p "璇疯緭鍏ュ瘑鐮?(榛樿闅忔満): " password; password=${password:-$(${SINGBOX_BIN} generate rand --hex 16)}
        read -p "鏄惁寮€鍚?QUIC 娴侀噺娣锋穯 (salamander)? (y/N): " h_choice
        if [[ "$h_choice" == "y" ]]; then
            obfs_password=$(${SINGBOX_BIN} generate rand --hex 16)
        fi
        read -p "鏄惁寮€鍚鍙ｈ烦璺? (y/N): " hop_choice
        if [[ "$hop_choice" == "y" ]]; then
            read -p "璇疯緭鍏ョ鍙ｈ寖鍥?(濡?20000-30000): " port_range
            if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                port_range_start="${BASH_REMATCH[1]}"
                port_range_end="${BASH_REMATCH[2]}"
                port_hopping="$port_range"
                use_multiport="true"
            fi
        fi
    fi
    
    # [!] 鑷畾涔夊悕绉?    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-Hysteria2-${port}"
    else
        local default_name="Hysteria2-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi
    
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"

    local up="${up_speed:-100}"
    local down="${down_speed:-100}"

    local inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg pw "$password" --arg op "$obfs_password" --arg cert "$cert_path" --arg key "$key_path" \
        '{"type":"hysteria2","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"password":$pw}],"tls":{"enabled":true,"alpn":["h3"],"certificate_path":$cert,"key_path":$key}} | if $op != "" then .obfs={"type":"salamander","password":$op} else . end')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1

    # [!] 閲嶆瀯澶氱鍙ｇ洃鍚ā寮忛€昏緫锛氫紭鍏堜娇鐢?iptables锛屽け璐ュ垯闄嶇骇鍒?JSON Inbound (甯︽暟閲忎繚鎶?
    local port_hopping_mode=""
    if [ "$use_multiport" == "true" ] && [ -n "$port_hopping" ]; then
        local iptables_available="false"
        local ip6tables_available="false"
        local test_dport=$((port_range_start + 1))
        [ "$test_dport" -eq "$port" ] && test_dport=$((port_range_start + 2))
        if [ "$test_dport" -gt "$port_range_end" ]; then
            test_dport="$port_range_start"
        fi

        local force_native_hop="false"
        if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --container 2>/dev/null | grep -qi '^lxc$'; then
            force_native_hop="true"
            _warn "妫€娴嬪埌 LXC 瀹瑰櫒鐜锛孒Y2 绔彛璺宠穬灏嗙洿鎺ヤ娇鐢?sing-box 鍘熺敓澶氱洃鍚ā寮忎互閬垮厤 iptables REDIRECT 鍋囩敓鏁堛€?
        elif [ -f /proc/1/environ ] && tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep -qi '^container=lxc$'; then
            force_native_hop="true"
            _warn "妫€娴嬪埌 LXC 瀹瑰櫒鐜锛孒Y2 绔彛璺宠穬灏嗙洿鎺ヤ娇鐢?sing-box 鍘熺敓澶氱洃鍚ā寮忎互閬垮厤 iptables REDIRECT 鍋囩敓鏁堛€?
        fi

        if [ "$force_native_hop" != "true" ]; then
            if command -v iptables &>/dev/null; then
                if iptables -t nat -A PREROUTING -p udp --dport "$test_dport" -j REDIRECT --to-ports "$port" 2>/dev/null; then
                    iptables -t nat -D PREROUTING -p udp --dport "$test_dport" -j REDIRECT --to-ports "$port" 2>/dev/null
                    iptables_available="true"
                fi
            fi
            if command -v ip6tables &>/dev/null; then
                if ip6tables -t nat -A PREROUTING -p udp --dport "$test_dport" -j REDIRECT --to-ports "$port" 2>/dev/null; then
                    ip6tables -t nat -D PREROUTING -p udp --dport "$test_dport" -j REDIRECT --to-ports "$port" 2>/dev/null
                    ip6tables_available="true"
                fi
            fi
        fi

        if [ "$iptables_available" == "true" ]; then
            iptables -t nat -A PREROUTING -p udp --dport ${port_range_start}:${port_range_end} -j REDIRECT --to-ports $port || iptables_available="false"
            if [ "$iptables_available" == "true" ]; then
                if [ "$ip6tables_available" == "true" ]; then
                    ip6tables -t nat -A PREROUTING -p udp --dport ${port_range_start}:${port_range_end} -j REDIRECT --to-ports $port 2>/dev/null || true
                fi
                _save_iptables_rules 2>/dev/null
                port_hopping_mode="iptables"
                _success "宸插惎鍔ㄥ簳绔?iptables 楂樿兘鏁?UDP 绔彛璺宠穬鑼冨洿鏄犲皠: ${port_hopping} -> ${port}"
            fi
        fi

        if [ "$port_hopping_mode" != "iptables" ]; then
            _warn "鍙戠幇闃茬伀澧欏彈闄?(鏃?iptables REDIRECT 鍐欐潈闄?锛屽噯澶囬檷绾ц嚦 Sing-box 鍘熺敓澶氬疄渚嬬洃鍚柟妗?.."
            local hop_count=$((port_range_end - port_range_start + 1))
            if [ "$hop_count" -le 1000 ]; then
                _info "姝ｅ湪鐢熸垚鍘熺敓澶ч噺鐩戝惉閰嶇疆鍧?(${port_range_start}-${port_range_end})..."
                local batch_array="[]"
                local skipped=0
                for ((p=port_range_start; p<=port_range_end; p++)); do
                    if [ "$p" -eq "$port" ]; then continue; fi
                    if _check_port_conflict "$p" "udp" "true"; then ((skipped++)); continue; fi
                    local hop_tag="${tag}-hop-${p}"
                    batch_array=$(echo "$batch_array" | jq --arg t "$hop_tag" --arg p "$p" --arg pw "$password" --arg cert "$cert_path" --arg key "$key_path" --arg op "$obfs_password" \
                        '. += [{"type":"hysteria2","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"password":$pw}],"tls":{"enabled":true,"alpn":["h3"],"certificate_path":$cert,"key_path":$key}} | if $op != "" then .obfs={"type":"salamander","password":$op} else . end]')
                done
                _atomic_modify_json "$CONFIG_FILE" ".inbounds += $batch_array | .inbounds |= unique_by(.tag)" || return 1
                local added_count=$(echo "$batch_array" | jq 'length')
                port_hopping_mode="native"
                _success "瀹夊叏闄嶇骇鎴愬姛锛氬凡纭紪鐮?${added_count} 涓師鐢熻緟鍔╃洃鍚妭鐐?(璺宠繃 ${skipped} 涓啿绐佺鍙?銆?
            else
                _error "闄嶇骇澶辫触锛氱洰鏍囪烦璺冪鍙ｆ暟閲?(${hop_count}) 瓒呭嚭浣庨厤鍘熺敓鐜鐨勫唴瀛樻壙杞藉畨鍏ㄩ槇鍊?(1000)锛?
                _warn "閴翠簬褰撳墠绯荤粺瀹瑰櫒涓嶆敮鎸佸唴鏍哥骇 iptables 鍔寔锛屼笖绔彛鏁伴噺瓒呴厤锛屽凡鑷姩鍙栨秷璇ヨ妭鐐圭殑璺宠穬璁惧畾銆?
                port_hopping=""
                port_hopping_mode=""
            fi
        fi
    fi
    
    # 淇濆瓨鍏冩暟鎹紙鍖呭惈绔彛璺宠穬淇℃伅锛?    local meta_json=$(jq -n --arg up "$up" --arg down "$down" --arg op "$obfs_password" --arg hop "$port_hopping" --arg hop_mode "$port_hopping_mode" \
        '{ "up": $up, "down": $down } | if $op != "" then .obfsPassword = $op else . end | if $hop != "" then .portHopping = $hop else . end | if $hop_mode != "" then .portHoppingMode = $hop_mode else . end')
    _atomic_modify_json "$METADATA_FILE" ". + {\"$tag\": $meta_json}" || return 1

    # Clash 閰嶇疆涓殑绔彛锛堝鏋滄湁绔彛璺宠穬锛屼娇鐢ㄨ寖鍥存牸寮忥級
    local clash_ports="$port"
    if [ -n "$port_hopping" ]; then
        clash_ports="$port_hopping"
    fi
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg ports "$clash_ports" --arg pw "$password" --arg sn "$server_name" --arg up "$up" --arg down "$down" --arg op "$obfs_password" --arg hop "$port_hopping" \
        '{
            "name": $n,
            "type": "hysteria2",
            "server": $s,
            "port": ($p|tonumber),
            "password": $pw,
            "sni": $sn,
            "skip-cert-verify": true,
            "alpn": ["h3"],
            "up": ($up|tonumber),
            "down": ($down|tonumber)
        } | if $op != "" then .obfs = "salamander" | .["obfs-password"] = $op else . end | if $hop != "" then .ports = $hop else . end')
    _add_node_to_yaml "$proxy_json"
    
    _success "Hysteria2 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    
    # 鏄剧ず绔彛璺宠穬淇℃伅
    if [ -n "$port_hopping" ]; then
        _info "绔彛璺宠穬鑼冨洿: ${port_hopping}"
    fi
    
    _show_node_link "hysteria2" "$name" "$link_ip" "$port" "$tag" "$password" "$server_name" "$obfs_password" "$port_hopping"
}

_add_tuic() {
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    local server_name="www.amd.com"

    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        server_name="${BATCH_SNI:-www.amd.com}"
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "udp" && continue
            break
        done
        read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?(榛樿: www.amd.com): " camouflage_domain
        server_name=${camouflage_domain:-"www.amd.com"}
    fi

    local tag="tuic-in-${port}"
    local cert_path="${SINGBOX_DIR}/${tag}.pem"
    local key_path="${SINGBOX_DIR}/${tag}.key"
    
    _generate_self_signed_cert "$server_name" "$cert_path" "$key_path" || return 1

    local uuid=$(${SINGBOX_BIN} generate uuid); local password=$(${SINGBOX_BIN} generate rand --hex 16)
    
    # [!] 鑷富鐢熸垚涓庡悕绉板垎閰?    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-TUICv5-${port}"
    else
        local default_name="TUICv5-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi

    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"

    local inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg u "$uuid" --arg pw "$password" --arg cert "$cert_path" --arg key "$key_path" \
        '{"type":"tuic","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"uuid":$u,"password":$pw}],"congestion_control":"bbr","tls":{"enabled":true,"alpn":["h3"],"certificate_path":$cert,"key_path":$key}}')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg u "$uuid" --arg pw "$password" --arg sn "$server_name" \
        '{"name":$n,"type":"tuic","server":$s,"port":($p|tonumber),"uuid":$u,"password":$pw,"sni":$sn,"skip-cert-verify":true,"alpn":["h3"],"udp-relay-mode":"native","congestion-controller":"bbr"}')
    _add_node_to_yaml "$proxy_json"
    _success "TUICv5 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    _show_node_link "tuic" "$name" "$link_ip" "$port" "$tag" "$uuid" "$password" "$server_name"
}

_add_shadowsocks_menu() {
    local choice=""
    if [ "$BATCH_MODE" = "true" ]; then
        choice="$BATCH_SS_VARIANT"
    else
        clear
        echo "========================================"
        _info "          娣诲姞 Shadowsocks 鑺傜偣"
        echo "========================================"
        echo " [缁忓吀 SS]"
        echo " 1) aes-256-gcm"
        echo " 2) chacha20-ietf-poly1305"
        echo " [SS-2022 (寮烘姉閲嶆斁淇濇姢)]"
        echo " 3) 2022-blake3-aes-256-gcm"
        echo " 4) 2022-blake3-aes-256-gcm (甯?Padding)"
        echo " [SS-2022 + ShadowTLS (瀹岀編浼缁勫悎)]"
        echo " 5) 2022-blake3-aes-256-gcm + ShadowTLS v3"
        echo " 0) 杩斿洖"
        echo "========================================"
        read -p "璇烽€夋嫨鍔犲瘑鏂瑰紡 [0-5]: " choice
    fi

    local method="" password="" name_prefix="" use_multiplex=false use_shadowtls=false
    case $choice in
        1) 
            method="aes-256-gcm"
            password=$(${SINGBOX_BIN} generate rand --hex 16)
            name_prefix="SS-aes256"
            ;;
        2) 
            method="chacha20-ietf-poly1305"
            password=$(${SINGBOX_BIN} generate rand --hex 16)
            name_prefix="SS-chacha20"
            ;;
        3)
            method="2022-blake3-aes-256-gcm"
            # SS-2022 鐨?aes-256 闇€瑕佷弗鏍肩殑 32 瀛楄妭 (256浣? base64 瀵嗛挜
            password=$(${SINGBOX_BIN} generate rand --base64 32)
            name_prefix="SS-2022"
            ;;
        4)
            method="2022-blake3-aes-256-gcm"
            password=$(${SINGBOX_BIN} generate rand --base64 32)
            name_prefix="SS-2022-Padding"
            use_multiplex=true
            _info "宸插惎鐢?Multiplex + Padding 妯″紡"
            _warning "娉ㄦ剰锛氬鎴风涔熷繀椤诲惎鐢?Multiplex + Padding 鎵嶈兘杩炴帴锛?
            ;;
        5)
            # SS-2022 256 浣嶇増鏈紙鎶楅噸鏀惧寮猴級
            method="2022-blake3-aes-256-gcm"
            password=$(${SINGBOX_BIN} generate rand --base64 32)
            name_prefix="SS-ShadowTLS"
            use_shadowtls=true
            ;;
        0) return 1 ;;
        *) _error "鏃犳晥杈撳叆"; return 1 ;;
    esac

    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        read -p "璇疯緭鍏ョ洃鍚鍙? " port; [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && return 1
    fi
    
    # [!] 鏂板锛氳嚜瀹氫箟鍚嶇О
    local name=""
    if [ "$BATCH_MODE" = "true" ]; then
        name="Batch-${name_prefix}-${port}"
    else
        local default_name="${name_prefix}-${port}"
        read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
        name=${custom_name:-$default_name}
    fi
    
    local shadowtls_password=""
    local shadowtls_sni="www.amd.com"
    if [ "$use_shadowtls" == "true" ]; then
        shadowtls_password=$(${SINGBOX_BIN} generate rand --hex 16)
        read -p "璇疯緭鍏?ShadowTLS 浼鐧藉悕鍗曞煙鍚?(榛樿: www.amd.com): " custom_sni
        shadowtls_sni=${custom_sni:-www.amd.com}
    fi

    local tag="${name_prefix}-in-${port}"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"

    # 鏍规嵁鏄惁鍚敤 Multiplex 鎴?ShadowTLS 鐢熸垚涓嶅悓閰嶇疆
    local inbound_json=""
    local jq_modify_expr=".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)"
    
    if [ "$use_shadowtls" == "true" ]; then
        local ss_tag="${tag}-ss"
        inbound_json=$(jq -n --arg t "$tag" --arg st "$ss_tag" --arg p "$port" --arg m "$method" --arg pw "$password" --arg spw "$shadowtls_password" --arg sni "$shadowtls_sni" \
            '[
                {
                    "type": "shadowtls",
                    "tag": $t,
                    "listen": "::",
                    "listen_port": ($p|tonumber),
                    "version": 3,
                    "users": [
                        {
                            "password": $spw
                        }
                    ],
                    "handshake": {
                        "server": $sni,
                        "server_port": 443
                    },
                    "detour": $st
                },
                {
                    "type": "shadowsocks",
                    "tag": $st,
                    "method": $m,
                    "password": $pw
                }
            ]')
        jq_modify_expr=".inbounds += $inbound_json | .inbounds |= unique_by(.tag)"
    elif [ "$use_multiplex" == "true" ]; then
        # 甯?Multiplex + Padding 鐨勯厤缃?        inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg m "$method" --arg pw "$password" \
            '{
                "type": "shadowsocks",
                "tag": $t,
                "listen": "::",
                "listen_port": ($p|tonumber),
                "method": $m,
                "password": $pw,
                "multiplex": {
                    "enabled": true,
                    "padding": true
                }
            }')
        jq_modify_expr=".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)"
    else
        # 鏍囧噯閰嶇疆
        inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg m "$method" --arg pw "$password" \
            '{
                "type": "shadowsocks",
                "tag": $t,
                "listen": "::",
                "listen_port": ($p|tonumber),
                "method": $m,
                "password": $pw
            }')
        jq_modify_expr=".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)"
    fi
    _atomic_modify_json "$CONFIG_FILE" "$jq_modify_expr" || return 1

    # YAML 閰嶇疆涔熼渶瑕佹牴鎹壒瀹氱姸鎬佺敓鎴?    local proxy_json=""
    if [ "$use_shadowtls" == "true" ]; then
        proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg m "$method" --arg pw "$password" --arg spw "$shadowtls_password" --arg sni "$shadowtls_sni" \
            '{
                "name": $n,
                "type": "ss",
                "server": $s,
                "port": ($p|tonumber),
                "cipher": $m,
                "password": $pw,
                "plugin": "shadow-tls",
                "plugin-opts": {
                    "host": $sni,
                    "password": $spw,
                    "version": 3
                }
            }')
    elif [ "$use_multiplex" == "true" ]; then
        proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg m "$method" --arg pw "$password" \
            '{
                "name": $n,
                "type": "ss",
                "server": $s,
                "port": ($p|tonumber),
                "cipher": $m,
                "password": $pw,
                "smux": {
                    "enabled": true,
                    "padding": true
                }
            }')
    else
        proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --arg p "$port" --arg m "$method" --arg pw "$password" \
            '{
                "name": $n,
                "type": "ss",
                "server": $s,
                "port": ($p|tonumber),
                "cipher": $m,
                "password": $pw
            }')
    fi
    _add_node_to_yaml "$proxy_json"

    _success "Shadowsocks (${method}) 鑺傜偣 [${name}] 娣诲姞鎴愬姛!"
    if [ "$use_multiplex" == "true" ]; then
        _info "Multiplex + Padding 宸插惎鐢紝瀹㈡埛绔渶閰嶇疆瀵瑰簲閫夐」"
    fi
    if [ "$use_shadowtls" == "true" ]; then
        _show_node_link "shadowsocks-shadowtls" "$name" "$link_ip" "$port" "$tag" "$method" "$password" "$shadowtls_password" "$shadowtls_sni"
    else
        _show_node_link "shadowsocks" "$name" "$link_ip" "$port" "$tag" "$method" "$password"
    fi
    return 0
}

_add_socks() {
    local node_ip="${server_ip}"
    [[ "$BATCH_MODE" == "true" && -n "$BATCH_IP" ]] && node_ip="$BATCH_IP"
    local port=""
    local username=""
    local password=""

    if [ "$BATCH_MODE" = "true" ]; then
        port="$BATCH_PORT"
        if [ -z "$port" ]; then
            _error "鎵归噺鍒涘缓閿欒: BATCH_PORT 涓虹┖锛岃烦杩?SOCKS5 瀹夎銆?
            return 1
        fi
        username=$(${SINGBOX_BIN} generate rand --hex 8)
        password=$(${SINGBOX_BIN} generate rand --hex 16)
    else
        read -p "璇疯緭鍏ユ湇鍔″櫒IP鍦板潃 (榛樿: ${server_ip}): " custom_ip
        node_ip=${custom_ip:-$server_ip}
        while true; do
            read -p "璇疯緭鍏ョ洃鍚鍙? " port
            [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
            _check_port_conflict "$port" "tcp" && continue
            break
        done
        read -p "璇疯緭鍏ョ敤鎴峰悕 (榛樿闅忔満): " username; username=${username:-$(${SINGBOX_BIN} generate rand --hex 8)}
        read -p "璇疯緭鍏ュ瘑鐮?(榛樿闅忔満): " password; password=${password:-$(${SINGBOX_BIN} generate rand --hex 16)}
    fi
    local tag="socks-in-${port}"
    local name="Batch-SOCKS5-${port}"
    [ "$BATCH_MODE" != "true" ] && name="SOCKS5-${port}"
    local display_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && display_ip="[$node_ip]"

    local inbound_json=$(jq -n --arg t "$tag" --arg p "$port" --arg u "$username" --arg pw "$password" \
        '{"type":"socks","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"username":$u,"password":$pw}]}')
    _atomic_modify_json "$CONFIG_FILE" ".inbounds += [$inbound_json] | .inbounds |= unique_by(.tag)" || return 1

    local proxy_json=$(jq -n --arg n "$name" --arg s "$display_ip" --arg p "$port" --arg u "$username" --arg pw "$password" \
        '{"name":$n,"type":"socks5","server":$s,"port":($p|tonumber),"username":$u,"password":$pw}')
    _add_node_to_yaml "$proxy_json"
    _success "SOCKS5 鑺傜偣娣诲姞鎴愬姛!"
    _show_node_link "socks" "$name" "$display_ip" "$port" "$tag" "$username" "$password"
}

_view_nodes() {
    if ! jq -e '.inbounds | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then _warning "褰撳墠娌℃湁浠讳綍鑺傜偣銆?; return; fi
    
    # 缁熻鏈夋晥鑺傜偣鏁伴噺锛堟帓闄よ緟鍔╄妭鐐癸級
    local node_count=$(jq '[.inbounds[] | select(.tag | contains("-hop-") | not)] | length' "$CONFIG_FILE")
    _info "--- 褰撳墠鑺傜偣淇℃伅 (鍏?${node_count} 涓? ---"
    
    # [鍏抽敭淇] 纭繚鍦ㄦ煡鐪嬪墠娓呯┖涔嬪墠鐨勪复鏃堕摼鎺ョ紦瀛?    rm -f /tmp/singbox_links.tmp
    
    # [璧勬簮浼樺寲] 浼犻€掔揣鍑?JSON锛屽惊鐜唴鐢ㄥ崟娆?jq 鎻愬彇 tag/type/port (3娆♀啋1娆?
    jq -c '.inbounds[]' "$CONFIG_FILE" | while IFS= read -r node; do
        # 鍚堝苟3娆″瓧娈垫彁鍙栦负1娆?        local _base_fields
        _base_fields=$(echo "$node" | jq -r '[.tag, .type, (.listen_port|tostring)] | @tsv')
        local tag type port
        IFS=$'\t' read -r tag type port <<< "$_base_fields"
        
        # 杩囨护鎺夊绔彛鐩戝惉鐢熸垚鐨勮緟鍔╄妭鐐癸紙璺宠繃 tag 涓寘鍚?-hop- 鐨勮妭鐐癸級
        if [[ "$tag" == *"-hop-"* ]]; then continue; fi
        
        # 浣跨敤缁熶竴鏌ユ壘鍑芥暟
        local proxy_name_to_find=$(_find_proxy_name "$port" "$type")

        # 鍒涘缓鏄剧ず鍚嶇О锛屼紭鍏堜娇鐢?clash.yaml 涓殑鍚嶇О锛屽け璐ュ垯鍥為€€鍒?tag
        local display_name=${proxy_name_to_find:-$tag}

        # 浼樺厛浣跨敤 metadata.json 涓殑 IP (鐢ㄤ簬 REALITY 鍜?TCP)
        local display_server=$(_get_proxy_field "$proxy_name_to_find" ".server")
        # 绉婚櫎鏂规嫭鍙?        local display_ip=$(echo "$display_server" | tr -d '[]')
        # IPv6閾炬帴鏍煎紡锛氭坊鍔燵]
        local link_ip="$display_ip"; [[ "$display_ip" == *":"* ]] && link_ip="[$display_ip]"
        
        echo "-------------------------------------"
        # [!] 宸蹭慨鏀癸細浣跨敤 display_name
        _info " 鑺傜偣: ${display_name}"
        local url=""
        
        # [鏂版灦鏋刔 浼樺厛浣跨敤鎸佷箙鍖栫敓鎴愮殑閾炬帴锛堜粠鏋佹簮瑙ｅ喅鍔ㄦ€佹彁鍙栧彲鑳藉瓨鍦ㄧ殑 SNI 涓㈠け姝昏锛?        url=$(jq -r --arg t "$tag" '.[$t].share_link // empty' "$METADATA_FILE")
        if { [ -z "$url" ] || [ "$url" == "null" ]; } && [[ "$tag" == argo-* ]] && [ -f "$ARGO_METADATA_FILE" ]; then
            url=$(jq -r --arg t "$tag" '.[$t].share_link // empty' "$ARGO_METADATA_FILE" 2>/dev/null)
        fi
        
        if [ -n "$url" ] && [ "$url" != "null" ]; then
            : # 鐩存帴浣跨敤鎸佷箙鍖栭摼鎺?        else
            case "$type" in
            "vless")
                # [璧勬簮浼樺寲] 鍚堝苟4娆q涓?娆?                local _vless_fields
                # [鍔犲浐] 鏅鸿兘鍥炴函 SNI: 浼樺厛 .tls.server_name, 澶囬€?.tls.reality.handshake.server, 淇濆簳 www.amd.com
                _vless_fields=$(echo "$node" | jq -r '[.users[0].uuid, (.users[0].flow // ""), (.tls.reality.enabled // false | tostring), (.transport.type // ""), (.tls.enabled // false | tostring), (.tls.server_name // .tls.reality.handshake.server // "www.amd.com"), (.transport.path // "")] | @tsv')
                IFS=$'\t' read -r uuid flow is_reality transport_type tls_enabled tls_sn ws_path <<< "$_vless_fields"
                
                # [鍔犲浐] 纭繚 Reality 妯″紡涓嬬殑娴侀噺鎺у埗瀛楁闈炵┖ (v2rayN 瑕佹眰)
                [ "$is_reality" == "true" ] && [ -z "$flow" ] && flow="xtls-rprx-vision"
                
                if [ "$is_reality" == "true" ]; then
                    # [淇] 鏀惧純瀵?Base64/Hex 瀵嗛挜浣跨敤 @tsv锛岄伩鍏嶆崯鍧?                    local pk=$(jq -r --arg t "$tag" '.[$t].publicKey // empty' "$METADATA_FILE")
                    local sid=$(jq -r --arg t "$tag" '.[$t].shortId // empty' "$METADATA_FILE")
                    local sn="$tls_sn"
                    local fp="chrome"
                    url="vless://${uuid}@${link_ip}:${port}?security=reality&encryption=none&pbk=$(_url_encode "${pk}")&fp=${fp}&type=tcp&flow=${flow}&sni=${sn}&sid=${sid}#$(_url_encode "$display_name")"
                elif [ "$transport_type" == "ws" ]; then
                    # ws_path 宸插湪涓婃柟鍚堝苟鎻愬彇
                    local sn="$tls_sn"
                    [ -z "$sn" ] || [ "$sn" == "null" ] && sn=$(_get_proxy_field "$proxy_name_to_find" ".servername")
                    url="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&type=ws&host=${sn}&path=$(_url_encode "$ws_path")&sni=${sn}#$(_url_encode "$display_name")"
                    
                    # Argo 鑺傜偣鍏冩暟鎹凡杩佺Щ鍒?argo_metadata.json
                    local argo_domain=""
                    if [[ "$tag" == argo-* ]] && [ -f "$ARGO_METADATA_FILE" ]; then
                        argo_domain=$(jq -r --arg t "$tag" '.[$t].domain // empty' "$ARGO_METADATA_FILE" 2>/dev/null)
                    fi
                    if [ -n "$argo_domain" ] && [ "$argo_domain" != "null" ]; then
                        url="vless://${uuid}@${argo_domain}:443?security=tls&encryption=none&type=ws&host=${argo_domain}&path=$(_url_encode "$ws_path")&sni=${argo_domain}#$(_url_encode "$display_name")"
                    fi
                elif [ "$tls_enabled" == "true" ]; then
                    local sn="$tls_sn"
                    url="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&type=tcp&sni=${sn}#$(_url_encode "$display_name")"
                else
                    url="vless://${uuid}@${link_ip}:${port}?encryption=none&type=tcp#$(_url_encode "$display_name")"
                fi
                ;;
            "trojan")
                # [璧勬簮浼樺寲] 鍚堝苟3娆q涓?娆?                local _trojan_fields
                _trojan_fields=$(echo "$node" | jq -r '[.users[0].password, (.transport.type // ""), (.transport.path // "")] | @tsv')
                local password transport_type ws_path
                IFS=$'\t' read -r password transport_type ws_path <<< "$_trojan_fields"
                
                if [ "$transport_type" == "ws" ]; then
                    local sn=$(_get_proxy_field "$proxy_name_to_find" ".sni")
                    url="trojan://${password}@${link_ip}:${port}?security=tls&type=ws&host=${sn}&path=$(_url_encode "$ws_path")&sni=${sn}#$(_url_encode "$display_name")"
                    
                    # Argo 鑺傜偣鍏冩暟鎹凡杩佺Щ鍒?argo_metadata.json
                    local argo_domain=""
                    if [[ "$tag" == argo-* ]] && [ -f "$ARGO_METADATA_FILE" ]; then
                        argo_domain=$(jq -r --arg t "$tag" '.[$t].domain // empty' "$ARGO_METADATA_FILE" 2>/dev/null)
                    fi
                    if [ -n "$argo_domain" ] && [ "$argo_domain" != "null" ]; then
                        url="trojan://${password}@${argo_domain}:443?security=tls&type=ws&host=${argo_domain}&path=$(_url_encode "$ws_path")&sni=${argo_domain}#$(_url_encode "$display_name")"
                    fi
                else
                    local sn=$(_get_proxy_field "$proxy_name_to_find" ".sni")
                    url="trojan://${password}@${link_ip}:${port}?security=tls&type=tcp&sni=${sn}#$(_url_encode "$display_name")"
                fi
                ;;
            "hysteria2")
                local pw=$(echo "$node" | jq -r '.users[0].password')
                local sn="$tls_sn"
                [ -z "$sn" ] || [ "$sn" == "null" ] && sn=$(_get_proxy_field "$proxy_name_to_find" ".sni")
                # [淇] 鏀惧純瀵规贩鍚堢被鍨嬪厓鏁版嵁浣跨敤 @tsv锛岄伩鍏嶆崯鍧?                local op=$(jq -r --arg t "$tag" '.[$t].obfsPassword // empty' "$METADATA_FILE")
                local hop=$(jq -r --arg t "$tag" '.[$t].portHopping // empty' "$METADATA_FILE")
                local obfs_param=""; [[ -n "$op" && "$op" != "null" ]] && obfs_param="&obfs=salamander&obfs-password=$(_url_encode "${op}")"
                # 绔彛璺宠穬鍙傛暟
                local hop_param=""; [[ -n "$hop" && "$hop" != "null" ]] && hop_param="&mport=${hop}&ports=${hop}"
                url="hysteria2://${pw}@${link_ip}:${port}?sni=${sn}&insecure=1${obfs_param}${hop_param}#$(_url_encode "$display_name")"
                ;;
            "tuic")
                # [璧勬簮浼樺寲] 鍚堝苟2娆q涓?娆?                local uuid pw
                IFS=$'\t' read -r uuid pw <<< "$(echo "$node" | jq -r '[.users[0].uuid, .users[0].password] | @tsv')"
                local sn=$(_get_proxy_field "$proxy_name_to_find" ".sni")
                url="tuic://${uuid}:${pw}@${link_ip}:${port}?sni=${sn}&alpn=h3&congestion_control=bbr&udp_relay_mode=native&allow_insecure=1#$(_url_encode "$display_name")"
                ;;
            "anytls")
                # [璧勬簮浼樺寲] 鍚堝苟2娆q涓?娆?                local pw sn
                # [鍔犲浐] 鍏佽 server_name 鍥炴函
                IFS=$'\t' read -r pw sn <<< "$(echo "$node" | jq -r '[.users[0].password, (.tls.server_name // "www.amd.com")] | @tsv')"
                local skip_verify=$(_get_proxy_field "$proxy_name_to_find" ".skip-cert-verify")
                local insecure_param=""
                if [ "$skip_verify" == "true" ]; then
                    insecure_param="&insecure=1&allowInsecure=1"
                fi
                url="anytls://${pw}@${link_ip}:${port}?security=tls&sni=${sn}${insecure_param}&type=tcp#$(_url_encode "$display_name")"
                ;;
            "shadowsocks")
                # [璧勬簮浼樺寲] 鍚堝苟2娆q涓?娆?                local method password
                IFS=$'\t' read -r method password <<< "$(echo "$node" | jq -r '[.method, .password] | @tsv')"
                url="ss://$(_url_encode "${method}:${password}")@${link_ip}:${port}#$(_url_encode "$display_name")"
                ;;
            "socks")
                # [璧勬簮浼樺寲] 鍚堝苟2娆q涓?娆?                local u p
                IFS=$'\t' read -r u p <<< "$(echo "$node" | jq -r '[.users[0].username, .users[0].password] | @tsv')"
                _info "  绫诲瀷: SOCKS5, 鍦板潃: $display_server, 绔彛: $port, 鐢ㄦ埛: $u, 瀵嗙爜: $p"
                ;;
        esac
        fi
        [ -n "$url" ] && echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${url}"
        # 鏀堕泦閾炬帴鍒颁复鏃舵枃浠?        [ -n "$url" ] && echo "$url" >> /tmp/singbox_links.tmp
    done
    echo "-------------------------------------"
    
    # 鐢熸垚鑱氬悎 Base64 閫夐」
    if [ -f /tmp/singbox_links.tmp ]; then
        echo ""
        read -p "鏄惁鐢熸垚鑱氬悎 Base64 璁㈤槄? (y/N): " gen_base64
        if [[ "$gen_base64" == "y" || "$gen_base64" == "Y" ]]; then
            echo ""
            _info "=== 鑱氬悎 Base64 璁㈤槄 ==="
            local base64_result=$(cat /tmp/singbox_links.tmp | base64 | tr -d '\n')
            echo -e "${CYAN}${base64_result}${NC}"
            echo ""
            _success "鍙洿鎺ュ鍒朵笂鏂瑰唴瀹瑰鍏?v2rayN 绛夊鎴风"
        fi
        rm -f /tmp/singbox_links.tmp
    fi
}

_delete_node() {
    if ! jq -e '.inbounds | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then _warning "褰撳墠娌℃湁浠讳綍鑺傜偣銆?; return; fi
    _info "--- 鑺傜偣鍒犻櫎 ---"
    
    # --- [!] 鏂扮殑鍒楄〃閫昏緫 ---
    # 鎴戜滑闇€瑕佸厛鏋勫缓涓€涓暟缁勶紝鏉ユ槧灏勭敤鎴疯緭鍏ュ拰鑺傜偣淇℃伅
    local inbound_tags=()
    local inbound_ports=()
    local inbound_types=()
    local display_names=() # 瀛樺偍鏄剧ず鍚嶇О
    local i=1
    # [璧勬簮浼樺寲] 涓€娆℃€ф彁鍙?tag/type/port锛岄伩鍏嶅惊鐜唴澶氭 fork jq
    while IFS=$'\t' read -r tag type port; do
        
        # [!] 杩囨护杈呭姪鑺傜偣
        if [[ "$tag" == *"-hop-"* ]]; then continue; fi
        
        # 瀛樺偍淇℃伅
        inbound_tags+=("$tag")
        inbound_ports+=("$port")
        inbound_types+=("$type")

        # 浣跨敤 utils.sh 涓殑缁熶竴鏌ユ壘鍑芥暟
        local proxy_name_to_find=$(_find_proxy_name "$port" "$type")
        
        local display_name=${proxy_name_to_find:-$tag} # 鍥為€€鍒?tag
        display_names+=("$display_name") # 瀛樺偍鏄剧ず鍚嶇О
        
        # [!] 宸蹭慨鏀癸細鏄剧ず鑷畾涔夊悕绉般€佺被鍨嬪拰绔彛
        echo -e "  ${CYAN}$i)${NC} ${display_name} (${YELLOW}${type}${NC}) @ ${port}"
        ((i++))
    done < <(jq -r '.inbounds[] | [.tag, .type, (.listen_port|tostring)] | @tsv' "$CONFIG_FILE")
    # --- 鍒楄〃閫昏緫缁撴潫 ---
    
    # 娣诲姞鍒犻櫎鎵€鏈夐€夐」
    local count=${#inbound_tags[@]}
    echo ""
    echo -e "  ${RED}99)${NC} 鍒犻櫎鎵€鏈夎妭鐐?

    read -p "璇疯緭鍏ヨ鍒犻櫎鐨勮妭鐐圭紪鍙?(杈撳叆 0 杩斿洖): " num
    
    [[ ! "$num" =~ ^[0-9]+$ ]] || [ "$num" -eq 0 ] && return
    
    # 澶勭悊鍒犻櫎鎵€鏈夎妭鐐?    if [ "$num" -eq 99 ]; then
        read -p "$(echo -e ${RED}"纭畾瑕佸垹闄ゆ墍鏈夎妭鐐瑰悧? 姝ゆ搷浣滀笉鍙仮澶? (杈撳叆 yes 纭): "${NC})" confirm_all
        if [ "$confirm_all" != "yes" ]; then
            _info "鍒犻櫎宸插彇娑堛€?
            return
        fi
        
        _info "姝ｅ湪鍒犻櫎鎵€鏈夎妭鐐?.."
        
        # [瀹夊叏鎬у姞鍥篯 绮惧噯鍒嗙骞堕攢姣佷粎鍏宠仈鏈剼鏈殑 iptables 璺宠穬绔彛瑙勫垯锛堝繀椤诲湪娓呯┖ metadata 涔嬪墠鎵ц锛侊級
        if [ -f "$METADATA_FILE" ]; then
            jq -r 'to_entries | .[] | select(.value.portHopping) | "\(.key)|\(.value.portHopping)|\(.value.portHoppingMode // \"\")"' "$METADATA_FILE" 2>/dev/null | while IFS="|" read -r ptag hop hop_mode; do
                local psuffix=$(echo "$ptag" | grep -oE "[0-9]+$")
                local hstart="${hop%-*}"
                local hend="${hop#*-}"
                if [ -z "$hop_mode" ]; then
                    if jq -e --arg prefix "${ptag}-hop-" '.inbounds[] | select(.tag | startswith($prefix))' "$CONFIG_FILE" >/dev/null 2>&1; then
                        hop_mode="native"
                    else
                        hop_mode="iptables"
                    fi
                fi
                if [ "$hop_mode" = "iptables" ]; then
                    if command -v iptables &>/dev/null; then iptables -t nat -D PREROUTING -p udp --dport ${hstart}:${hend} -j REDIRECT --to-ports $psuffix 2>/dev/null; fi
                    if command -v ip6tables &>/dev/null; then ip6tables -t nat -D PREROUTING -p udp --dport ${hstart}:${hend} -j REDIRECT --to-ports $psuffix 2>/dev/null; fi
                fi
            done
            _save_iptables_rules 2>/dev/null
        fi
        
        # 娓呯┖閰嶇疆
        _atomic_modify_json "$CONFIG_FILE" '.inbounds = []'
        _atomic_modify_json "$METADATA_FILE" '{}'
        
        # 娓呯┖ clash.yaml 涓殑浠ｇ悊
        ${YQ_BINARY} eval '.proxies = []' -i "$CLASH_YAML_FILE"
        ${YQ_BINARY} eval '.proxy-groups[] |= (select(.name == "鑺傜偣閫夋嫨") | .proxies = ["DIRECT"])' -i "$CLASH_YAML_FILE"
        
        # 鍒犻櫎鎵€鏈夎瘉涔︽枃浠?        rm -f ${SINGBOX_DIR}/*.pem ${SINGBOX_DIR}/*.key 2>/dev/null
        
        _success "鎵€鏈夎妭鐐瑰凡鍒犻櫎锛?
        _manage_service "restart"
        return
    fi
    
    # [!] 宸蹭慨鏀癸細鐜板湪 count 浼氬湪寰幆澶栬姝ｇ‘璁＄畻
    if [ "$num" -gt "$count" ]; then _error "缂栧彿瓒呭嚭鑼冨洿銆?; return; fi

    local index=$((num - 1))
    # [!] 宸蹭慨鏀癸細浠庢暟缁勪腑鑾峰彇姝ｇ‘鐨勪俊鎭?    local tag_to_del=${inbound_tags[$index]}
    local type_to_del=${inbound_types[$index]}
    local port_to_del=${inbound_ports[$index]}
    local display_name_to_del=${display_names[$index]}

    # --- [!] 鏂扮殑鍒犻櫎閫昏緫 ---
    # 浣跨敤缁熶竴鏌ユ壘鍑芥暟纭畾 clash.yaml 涓殑纭垏鍚嶇О
    local proxy_name_to_del=$(_find_proxy_name "$port_to_del" "$type_to_del")

    # [!] 宸蹭慨鏀癸細浣跨敤鏄剧ず鍚嶇О杩涜纭
    read -p "$(echo -e ${YELLOW}"纭畾瑕佸垹闄よ妭鐐?${display_name_to_del} 鍚? (y/N): "${NC})" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        _info "鍒犻櫎宸插彇娑堛€?
        return
    fi
    
    # === 鍏抽敭淇锛氬繀椤诲厛璇诲彇 metadata 鍒ゆ柇鑺傜偣绫诲瀷锛屽啀鍒犻櫎锛?==
    local node_metadata=$(jq -r --arg tag "$tag_to_del" '.[$tag] // empty' "$METADATA_FILE" 2>/dev/null)
    local node_type=""
    if [ -n "$node_metadata" ]; then
        node_type=$(echo "$node_metadata" | jq -r '.type // empty')
    fi
    
    # [!] 閲嶈淇锛氫笉浣跨敤绱㈠紩鍒犻櫎锛堝洜涓哄垪琛ㄥ凡杩囨护锛夛紝鏀逛负浣跨敤 Tag 绮剧‘鍖归厤鍒犻櫎
    _atomic_modify_json "$CONFIG_FILE" "del(.inbounds[] | select(.tag == \"$tag_to_del\"))" || return
    
    # [!] 鏂板锛氱簿鍑嗗墺绂昏鑺傜偣缁戝畾鐨勭郴缁熺骇闃茬伀澧欑鍙ｈ烦璺冪瓥鐣?    local port_hopping=$(echo "$node_metadata" | jq -r '.portHopping // empty' 2>/dev/null)
    local port_hopping_mode=$(echo "$node_metadata" | jq -r '.portHoppingMode // empty' 2>/dev/null)
    if [ -n "$port_hopping" ]; then
        if [ -z "$port_hopping_mode" ]; then
            if jq -e --arg prefix "${tag_to_del}-hop-" '.inbounds[] | select(.tag | startswith($prefix))' "$CONFIG_FILE" >/dev/null 2>&1; then
                port_hopping_mode="native"
            else
                port_hopping_mode="iptables"
            fi
        fi
        local hop_start="${port_hopping%-*}"
        local hop_end="${port_hopping#*-}"
        if [ "$port_hopping_mode" = "iptables" ]; then
            if command -v iptables &>/dev/null; then
                iptables -t nat -D PREROUTING -p udp --dport ${hop_start}:${hop_end} -j REDIRECT --to-ports $port_to_del 2>/dev/null
            fi
            if command -v ip6tables &>/dev/null; then
                ip6tables -t nat -D PREROUTING -p udp --dport ${hop_start}:${hop_end} -j REDIRECT --to-ports $port_to_del 2>/dev/null
            fi
            _save_iptables_rules 2>/dev/null
            _info "宸插嵏杞藉叧鑱旂殑搴曞眰 iptables UDP 绔彛鏄犲皠绛栫暐 (${port_hopping})"
        fi
    fi
    # [!] 绾ц仈娓呯悊锛氬悓鏃跺垹闄?JSON Fallback 妯″紡鍙兘鐢熸垚鐨勮緟鍔╄烦璺冨瓙 inbounds (鏍煎紡: tag-hop-xxx)
    _atomic_modify_json "$CONFIG_FILE" ".inbounds |= map(select(.tag | startswith(\"$tag_to_del-hop-\") | not))" 2>/dev/null
    
    _atomic_modify_json "$METADATA_FILE" "del(.\"$tag_to_del\")" || return
    
    # [!] 宸蹭慨鏀癸細浣跨敤鎵惧埌鐨?proxy_name_to_del 浠?clash.yaml 涓垹闄?    if [ -n "$proxy_name_to_del" ]; then
        _remove_node_from_yaml "$proxy_name_to_del"
    fi

    # 璇佷功娓呯悊閫昏緫 - 鍖呭惈 hysteria2, tuic, anytls (鍩轰簬 tag)
    if [ "$type_to_del" == "hysteria2" ] || [ "$type_to_del" == "tuic" ] || [ "$type_to_del" == "anytls" ]; then
        local cert_to_del="${SINGBOX_DIR}/${tag_to_del}.pem"
        local key_to_del="${SINGBOX_DIR}/${tag_to_del}.key"
        if [ -f "$cert_to_del" ] || [ -f "$key_to_del" ]; then
            _info "姝ｅ湪鍒犻櫎鑺傜偣鍏宠仈鐨勮瘉涔︽枃浠? ${cert_to_del}, ${key_to_del}"
            rm -f "$cert_to_del" "$key_to_del"
        fi
    fi
    
    # === 鏍规嵁涔嬪墠璇诲彇鐨勮妭鐐圭被鍨嬫竻鐞嗙浉鍏抽厤缃?===
    if [ "$node_type" == "third-party-adapter" ]; then
        # === 绗笁鏂归€傞厤灞傦細鍒犻櫎 outbound 鍜?route ===
        _info "妫€娴嬪埌绗笁鏂归€傞厤灞傦紝姝ｅ湪娓呯悊鍏宠仈閰嶇疆..."
        
        # 鍏堟煡鎵惧搴旂殑 outbound (蹇呴』鍦ㄥ垹闄?route 涔嬪墠)
        local outbound_tag=$(jq -r --arg inbound "$tag_to_del" '.route.rules[] | select(.inbound == $inbound) | .outbound' "$CONFIG_FILE" 2>/dev/null | head -n 1)
        
        # 鍒犻櫎 route 瑙勫垯
        _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.inbound == \"$tag_to_del\"))" || true
        
        # 鍒犻櫎瀵瑰簲鐨?outbound
        if [ -n "$outbound_tag" ] && [ "$outbound_tag" != "null" ]; then
            _atomic_modify_json "$CONFIG_FILE" "del(.outbounds[] | select(.tag == \"$outbound_tag\"))" || true
            _info "宸插垹闄ゅ叧鑱旂殑 outbound: $outbound_tag"
        fi
    else
        # === 鏅€氳妭鐐癸細鍙湁 inbound锛屾病鏈夐澶栫殑 outbound 鍜?route ===
        # 涓昏剼鏈垱寤虹殑鑺傜偣閫氬父鍙寘鍚?inbound锛宱utbound 鏄叏灞€鐨勶紙濡?direct锛?        # 濡傛灉鏈夌壒娈婄殑 outbound锛堝鏌愪簺鍗忚鐨勪笓鐢ㄩ厤缃級锛屼篃瑕佸垹闄?        
        # 妫€鏌ユ槸鍚︽湁鍩轰簬姝?inbound 鐨?route 瑙勫垯锛堥€氬父涓嶅簲璇ユ湁锛屼絾涓轰簡娓呯悊骞插噣锛?        local has_route=$(jq -e ".route.rules[]? | select(.inbound == \"$tag_to_del\")" "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$has_route" ]; then
            _info "妫€娴嬪埌鍏宠仈鐨勮矾鐢辫鍒欙紝姝ｅ湪娓呯悊..."
            _atomic_modify_json "$CONFIG_FILE" "del(.route.rules[] | select(.inbound == \"$tag_to_del\"))" || true
        fi
        
        # 娉ㄦ剰锛氫笉鍒犻櫎浠讳綍 outbound锛屽洜涓烘櫘閫氳妭鐐圭殑 outbound 閫氬父鏄叡浜殑鍏ㄥ眬 outbound
        # 锛堝 "direct"锛夛紝鍒犻櫎浼氬奖鍝嶅叾浠栬妭鐐?    fi
    # === 娓呯悊閫昏緫缁撴潫 ===
    
    _success "鑺傜偣 ${display_name_to_del} 宸插垹闄わ紒"
    _manage_service "restart"
}

_check_config() {
    _info "姝ｅ湪妫€鏌?sing-box 閰嶇疆鏂囦欢..."
    # 鎹曡幏鎵€鏈夎緭鍑猴紙鍖呮嫭 stderr 浜х敓鐨勫ぇ閲?WARN 鍜?TRACE 寮冪敤璀﹀憡锛?    local result
    result=$(${SINGBOX_BIN} check -c ${CONFIG_FILE} 2>&1)
    if [[ $? -eq 0 ]]; then
        _success "閰嶇疆鏂囦欢 (${CONFIG_FILE}) 鏍煎紡姝ｇ‘銆?
    else
        _error "閰嶇疆鏂囦欢妫€鏌ュけ璐?"
        echo "$result"
    fi
}

_modify_port() {
    if ! jq -e '.inbounds | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then
        _warning "褰撳墠娌℃湁浠讳綍鑺傜偣銆?
        return
    fi
    
    _info "--- 淇敼鑺傜偣绔彛 ---"
    
    # 鍒楀嚭鎵€鏈夎妭鐐?    local inbound_tags=()
    local inbound_ports=()
    local inbound_types=()
    local display_names=()
    
    local i=1
    # [璧勬簮浼樺寲] 鍚堝苟3娆q涓?娆?+ 浣跨敤鍏叡鍑芥暟 _find_proxy_name 鏇夸唬鍐呰仈鏌ユ壘
    while IFS=$'\t' read -r tag type port; do
        # [!] 杩囨护杈呭姪璺宠穬瀛愯妭鐐癸紙涓?_view_nodes / _delete_node 淇濇寔涓€鑷达級
        if [[ "$tag" == *"-hop-"* ]]; then continue; fi

        inbound_tags+=("$tag")
        inbound_ports+=("$port")
        inbound_types+=("$type")
        
        # [M1] 浣跨敤鍏叡鍑芥暟鏇夸唬鍐呰仈閲嶅鐨勪唬鐞嗗悕鏌ユ壘閫昏緫
        local proxy_name_to_find=$(_find_proxy_name "$port" "$type")
        
        local display_name=${proxy_name_to_find:-$tag}
        display_names+=("$display_name")
        
        echo -e "  ${CYAN}$i)${NC} ${display_name} (${YELLOW}${type}${NC}) @ ${GREEN}${port}${NC}"
        ((i++))
    done < <(jq -r '.inbounds[] | [.tag, .type, (.listen_port|tostring)] | @tsv' "$CONFIG_FILE")
    
    read -p "璇疯緭鍏ヨ淇敼绔彛鐨勮妭鐐圭紪鍙?(杈撳叆 0 杩斿洖): " num
    
    [[ ! "$num" =~ ^[0-9]+$ ]] || [ "$num" -eq 0 ] && return
    
    local count=${#inbound_tags[@]}
    if [ "$num" -gt "$count" ]; then
        _error "缂栧彿瓒呭嚭鑼冨洿銆?
        return
    fi
    
    local index=$((num - 1))
    local tag_to_modify=${inbound_tags[$index]}
    local type_to_modify=${inbound_types[$index]}
    local old_port=${inbound_ports[$index]}
    local display_name_to_modify=${display_names[$index]}
    local hop_info=""
    local hop_mode=""
    local hop_range_input=""
    local final_hop_info=""
    local final_hop_start=""
    local final_hop_end=""
    
    _info "褰撳墠鑺傜偣: ${display_name_to_modify} (${type_to_modify})"
    _info "褰撳墠绔彛: ${old_port}"
    
    if [ "$type_to_modify" = "hysteria2" ] && [ -f "$METADATA_FILE" ] && jq -e ".\"$tag_to_modify\"" "$METADATA_FILE" >/dev/null 2>&1; then
        hop_info=$(jq -r ".\"$tag_to_modify\".portHopping // \"\"" "$METADATA_FILE" 2>/dev/null)
        hop_mode=$(jq -r ".\"$tag_to_modify\".portHoppingMode // \"\"" "$METADATA_FILE" 2>/dev/null)
        if [ -n "$hop_info" ] && [ -z "$hop_mode" ]; then
            if jq -e --arg prefix "${tag_to_modify}-hop-" '.inbounds[] | select(.tag | startswith($prefix))' "$CONFIG_FILE" >/dev/null 2>&1; then
                hop_mode="native"
            else
                hop_mode="iptables"
            fi
        fi
    fi
    
    read -p "璇疯緭鍏ユ柊鐨勭鍙ｅ彿: " new_port
    
    # 楠岃瘉绔彛
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        _error "鏃犳晥鐨勭鍙ｅ彿锛?
        return
    fi
    
    if [ "$new_port" -eq "$old_port" ]; then
        _warning "鏂扮鍙ｄ笌褰撳墠绔彛鐩稿悓锛屾棤闇€淇敼銆?
        return
    fi
    
    # 妫€鏌ョ鍙ｆ槸鍚﹀凡琚崰鐢?    if jq -e --arg tag "$tag_to_modify" --argjson port "$new_port" '.inbounds[] | select(.listen_port == $port and .tag != $tag)' "$CONFIG_FILE" >/dev/null 2>&1; then
        _error "绔彛 $new_port 宸茶鍏朵粬鑺傜偣浣跨敤锛?
        return
    fi
    
    if [ -n "$hop_info" ]; then
        _info "妫€娴嬪埌褰撳墠 HY2 鑺傜偣鍚敤浜嗙鍙ｈ烦璺?(${hop_mode:-unknown}): ${hop_info}"
        read -p "璇疯緭鍏ユ柊鐨勭鍙ｈ烦璺冭寖鍥达紙鐩存帴鍥炶溅淇濈暀鍘熻寖鍥达紝杈撳叆 none 鍏抽棴锛? " hop_range_input
        if [ -z "$hop_range_input" ]; then
            final_hop_info="$hop_info"
        elif [ "$hop_range_input" = "none" ]; then
            final_hop_info=""
        else
            if [[ ! "$hop_range_input" =~ ^[0-9]+-[0-9]+$ ]]; then
                _error "绔彛璺宠穬鑼冨洿鏍煎紡鏃犳晥锛屽簲涓?start-end銆?
                return
            fi
            final_hop_start="${hop_range_input%-*}"
            final_hop_end="${hop_range_input#*-}"
            if [ "$final_hop_start" -lt 1 ] || [ "$final_hop_end" -gt 65535 ] || [ "$final_hop_start" -gt "$final_hop_end" ]; then
                _error "绔彛璺宠穬鑼冨洿鏃犳晥銆?
                return
            fi
            final_hop_info="$hop_range_input"
        fi
    fi
    
    if [ -n "$final_hop_info" ]; then
        final_hop_start="${final_hop_info%-*}"
        final_hop_end="${final_hop_info#*-}"
    fi
    
    _info "姝ｅ湪淇敼绔彛: ${old_port} -> ${new_port}"
    
    # 1. 淇敼 config.json 涓昏妭鐐圭鍙ｏ紙鎸?tag 绮剧‘鍖归厤锛岄伩鍏嶈繃婊?hop 瀛愯妭鐐瑰悗绱㈠紩閿欎綅锛?    _atomic_modify_json "$CONFIG_FILE" "(.inbounds[] | select(.tag == \"$tag_to_modify\") | .listen_port) = $new_port" || return
    
    # 2. 淇敼 clash.yaml (鍏ㄩ摼璺悓姝ユā寮?
    local old_proxy_name=$(_find_proxy_name "$old_port" "$type_to_modify")
    if [ -n "$old_proxy_name" ]; then
        # 鐢熸垚鏂板悕瀛楋細灏嗗悕瀛椾腑鐨勬棫绔彛鏇挎崲涓烘柊绔彛
        local new_proxy_name=$(echo "$old_proxy_name" | sed "s/${old_port}/${new_port}/g")
        
        export OLD_NAME="$old_proxy_name"
        export NEW_NAME="$new_proxy_name"
        export NEW_PORT_VAL="$new_port"
        
        # 鍘熷瓙鏀瑰悕涓庢敼绔彛
        _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxies[] | select(.name == env(OLD_NAME)) | .name) = env(NEW_NAME)'
        _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxies[] | select(.name == env(NEW_NAME)) | .port) = (env(NEW_PORT_VAL)|tonumber)'
        
        # 鍏ㄥ眬鍚屾鏇存柊鎵€鏈夊垎缁勪腑鐨勫紩鐢?        _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxy-groups[].proxies[] | select(. == env(OLD_NAME))) = env(NEW_NAME)'
        
        if [ -n "$final_hop_info" ]; then
            export NEW_PORTS_VAL="$final_hop_info"
            _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxies[] | select(.name == env(NEW_NAME)) | .ports) = env(NEW_PORTS_VAL)'
        elif [ -n "$hop_info" ]; then
            _atomic_modify_yaml "$CLASH_YAML_FILE" 'del(.proxies[] | select(.name == env(NEW_NAME)) | .ports)'
        fi
        
        _info "Clash 鑺傜偣鍚嶅悓姝? ${old_proxy_name} -> ${new_proxy_name}"
    fi
    
    # [淇] 3. 鍏ㄥ眬鍚屾鏇存柊 metadata.json 涓殑閾炬帴绔彛涓庡娉ㄥ悕
    if [ -f "$METADATA_FILE" ]; then
        if jq -e ".\"$tag_to_modify\"" "$METADATA_FILE" >/dev/null 2>&1; then
            # [鍏抽敭淇] _view_nodes 浼樺厛璇诲彇鐨勬槸 .share_link 瀛楁 (闈?.link)
            local current_link=$(jq -r ".\"$tag_to_modify\".share_link // \"\"" "$METADATA_FILE")
            if [ -n "$current_link" ]; then
                # 绮惧噯鏇挎崲锛氫粎鏇挎崲 URL 涓鍙ｄ綅缃殑鏁板瓧锛園IP:PORT? 鍜?#name-PORT 閮ㄥ垎锛夛紝閬垮厤璇激 UUID/瀵嗙爜
                local new_link=$(echo "$current_link" | sed -E "s/(:${old_port})([?&#\/]|$)/:${new_port}\2/g; s/(-${old_port})([?&#\/]|$)/-${new_port}\2/g")
                if [ -n "$hop_info" ]; then
                    if [ -n "$final_hop_info" ]; then
                        # 鏇存柊 mport 鍙傛暟
                        if [[ "$new_link" == *"&mport="* ]] || [[ "$new_link" == *"?mport="* ]]; then
                            new_link=$(echo "$new_link" | sed -E "s/([?&]mport=)[0-9]+-[0-9]+/\1${final_hop_info}/g")
                        else
                            new_link="${new_link}&mport=${final_hop_info}"
                        fi
                        # 鏇存柊 ports 鍙傛暟
                        if [[ "$new_link" == *"&ports="* ]] || [[ "$new_link" == *"?ports="* ]]; then
                            new_link=$(echo "$new_link" | sed -E "s/([?&]ports=)[0-9]+-[0-9]+/\1${final_hop_info}/g")
                        else
                            new_link="${new_link}&ports=${final_hop_info}"
                        fi
                    else
                        new_link=$(echo "$new_link" | sed -E 's/[?&]mport=[0-9]+-[0-9]+//g')
                        new_link=$(echo "$new_link" | sed -E 's/[?&]ports=[0-9]+-[0-9]+//g')
                        new_link=$(echo "$new_link" | sed -E 's/\?&/?/g; s/&$//g; s/\?$//g')
                    fi
                fi
                _atomic_modify_json "$METADATA_FILE" ".\"$tag_to_modify\".share_link = \"$new_link\""
                _info "鍒嗕韩閾炬帴宸插悓姝ユ洿鏂般€?
            fi
            if [ -n "$hop_info" ]; then
                if [ -n "$final_hop_info" ]; then
                    _atomic_modify_json "$METADATA_FILE" ".\"$tag_to_modify\".portHopping = \"$final_hop_info\"" || return
                    if [ -n "$hop_mode" ]; then
                        _atomic_modify_json "$METADATA_FILE" ".\"$tag_to_modify\".portHoppingMode = \"$hop_mode\"" || return
                    fi
                else
                    _atomic_modify_json "$METADATA_FILE" "del(.\"$tag_to_modify\".portHopping, .\"$tag_to_modify\".portHoppingMode)" || return
                fi
            fi
        fi
    fi

    # 4. 閫氱敤 tag 閲嶅懡鍚嶏紙鎵€鏈夊惈绔彛鐨?tag 閮藉彲鑳介渶瑕佹洿鏂帮級
    local new_tag=$(echo "$tag_to_modify" | sed "s/${old_port}/${new_port}/g")
    if [ "$new_tag" != "$tag_to_modify" ]; then
        # 4a. 澶勭悊璇佷功鏂囦欢閲嶅懡鍚嶏紙浠?Hysteria2, TUIC, AnyTLS 鏈夌嫭绔嬭瘉涔︼級
        if [ "$type_to_modify" == "hysteria2" ] || [ "$type_to_modify" == "tuic" ] || [ "$type_to_modify" == "anytls" ]; then
            local old_cert="${SINGBOX_DIR}/${tag_to_modify}.pem"
            local old_key="${SINGBOX_DIR}/${tag_to_modify}.key"
            local new_cert="${SINGBOX_DIR}/${new_tag}.pem"
            local new_key="${SINGBOX_DIR}/${new_tag}.key"
            
            if [ -f "$old_cert" ] && [ -f "$old_key" ]; then
                mv "$old_cert" "$new_cert"
                mv "$old_key" "$new_key"
                _atomic_modify_json "$CONFIG_FILE" "(.inbounds[] | select(.tag == \"$tag_to_modify\") | .tls.certificate_path) = \"$new_cert\"" || return
                _atomic_modify_json "$CONFIG_FILE" "(.inbounds[] | select(.tag == \"$tag_to_modify\") | .tls.key_path) = \"$new_key\"" || return
            fi
        fi
        
        # 4b. 鏇存柊 config.json 涓富鑺傜偣鐨?tag
        _atomic_modify_json "$CONFIG_FILE" "(.inbounds[] | select(.tag == \"$tag_to_modify\") | .tag) = \"$new_tag\"" || return
        
        # 4c. 杩佺Щ metadata.json 涓殑 key (鏃ag -> 鏂皌ag)
        if [ -f "$METADATA_FILE" ] && jq -e ".\"$tag_to_modify\"" "$METADATA_FILE" >/dev/null 2>&1; then
            local meta_content=$(jq ".\"$tag_to_modify\"" "$METADATA_FILE")
            _atomic_modify_json "$METADATA_FILE" "del(.\"$tag_to_modify\") | . + {\"$new_tag\": $meta_content}" || return
        fi
        
        _info "Tag 鍚屾: ${tag_to_modify} -> ${new_tag}"
    fi
    
    # 5. 鑱斿姩鏇存柊绔彛璺宠穬瑙勫垯
    local final_tag="${new_tag:-$tag_to_modify}"
    if [ -n "$hop_info" ]; then
        if [ "$hop_mode" = "iptables" ]; then
            # [淇] 浜嬪姟鎬?iptables 鏇存柊锛氬厛灏濊瘯鍐欏叆鏂拌鍒欙紝鎴愬姛鍚庡啀鍒犳棫瑙勫垯锛屽け璐ュ垯鍥炴粴
            local ipt_v4_ok="false"
            local ipt_v6_ok="false"
            local old_hop_start="${hop_info%-*}"
            local old_hop_end="${hop_info#*-}"

            if [ -n "$final_hop_info" ]; then
                # === 鏈夋柊璺宠穬鑼冨洿锛氬厛鍐欐柊瑙勫垯锛屾垚鍔熷悗鍐嶅垹鏃ц鍒?===
                # Step 1: 灏濊瘯鍐欏叆鏂?v4 瑙勫垯
                if command -v iptables &>/dev/null; then
                    if iptables -t nat -A PREROUTING -p udp --dport ${final_hop_start}:${final_hop_end} -j REDIRECT --to-ports $new_port 2>/dev/null; then
                        ipt_v4_ok="true"
                    else
                        _error "iptables 鏂拌烦璺冭鍒欏啓鍏ュけ璐?(v4)锛岀鍙ｈ烦璺冩槧灏勬湭鏇存柊銆?
                        _warn "灏濊瘯淇濈暀鏃ф槧灏勮鍒?(${old_hop_start}-${old_hop_end} -> ${old_port})..."
                        # 涓嶅垹鏃ц鍒欙紝鐩存帴涓锛坈onfig.json 绔彛宸叉敼锛屼絾 iptables 淇濇寔鏃ф槧灏勫厹搴曪級
                    fi
                fi
                # Step 2: 灏濊瘯鍐欏叆鏂?v6 瑙勫垯锛堝彲閫夛紝澶辫触涓嶉樆鏂?v4 娴佺▼锛?                if command -v ip6tables &>/dev/null; then
                    if ip6tables -t nat -A PREROUTING -p udp --dport ${final_hop_start}:${final_hop_end} -j REDIRECT --to-ports $new_port 2>/dev/null; then
                        ipt_v6_ok="true"
                    fi
                fi
                # Step 3: 鍙湁 v4 鎴愬姛鎵嶅垹鏃ц鍒欏苟鎸佷箙鍖?                if [ "$ipt_v4_ok" = "true" ]; then
                    if command -v iptables &>/dev/null; then
                        iptables -t nat -D PREROUTING -p udp --dport ${old_hop_start}:${old_hop_end} -j REDIRECT --to-ports $old_port 2>/dev/null
                    fi
                    if [ "$ipt_v6_ok" = "true" ] && command -v ip6tables &>/dev/null; then
                        ip6tables -t nat -D PREROUTING -p udp --dport ${old_hop_start}:${old_hop_end} -j REDIRECT --to-ports $old_port 2>/dev/null
                    fi
                    _save_iptables_rules 2>/dev/null
                    _info "宸插皢绔彛璺宠穬鏄犲皠浠?${old_port} 鑱斿姩鏇存柊鍒?${new_port}锛岃寖鍥? ${final_hop_info}"
                else
                    # v4 鍐欏叆澶辫触锛氬洖婊氬垰鎵嶅彲鑳芥畫鐣欑殑鏂拌鍒欙紙闃叉閲嶅瑙勫垯锛夛紝骞舵姤閿?                    iptables -t nat -D PREROUTING -p udp --dport ${final_hop_start}:${final_hop_end} -j REDIRECT --to-ports $new_port 2>/dev/null
                    ip6tables -t nat -D PREROUTING -p udp --dport ${final_hop_start}:${final_hop_end} -j REDIRECT --to-ports $new_port 2>/dev/null
                    _error "绔彛璺宠穬 iptables 瑙勫垯鏇存柊澶辫触锛屾棫鏄犲皠淇濇寔涓嶅彉銆傜鍙ｄ慨鏀逛粛浼氱户缁紝浣?HY2 璺宠穬鍙兘澶辨晥锛岃鎵嬪姩妫€鏌?iptables nat 瑙勫垯锛?
                fi
            else
                # === 鏃犳柊璺宠穬鑼冨洿锛氫粎鍒犻櫎鏃ц鍒?===
                if command -v iptables &>/dev/null; then
                    iptables -t nat -D PREROUTING -p udp --dport ${old_hop_start}:${old_hop_end} -j REDIRECT --to-ports $old_port 2>/dev/null
                fi
                if command -v ip6tables &>/dev/null; then
                    ip6tables -t nat -D PREROUTING -p udp --dport ${old_hop_start}:${old_hop_end} -j REDIRECT --to-ports $old_port 2>/dev/null
                fi
                _save_iptables_rules 2>/dev/null
                _info "宸茬Щ闄ょ鍙ｈ烦璺冩槧灏勩€?
            fi
        elif [ "$hop_mode" = "native" ]; then
            _atomic_modify_json "$CONFIG_FILE" ".inbounds |= map(select(.tag | startswith(\"${tag_to_modify}-hop-\") | not))" || return
            if [ -n "$new_tag" ] && [ "$new_tag" != "$tag_to_modify" ]; then
                _atomic_modify_json "$CONFIG_FILE" ".inbounds |= map(select(.tag | startswith(\"${new_tag}-hop-\") | not))" || return
            fi
            if [ -n "$final_hop_info" ]; then
                local cert_path="${SINGBOX_DIR}/${final_tag}.pem"
                local key_path="${SINGBOX_DIR}/${final_tag}.key"
                local hy2_password=$(jq -r --arg t "$final_tag" '.inbounds[] | select(.tag == $t) | .users[0].password // ""' "$CONFIG_FILE")
                local hy2_obfs_password=$(jq -r --arg t "$final_tag" '.inbounds[] | select(.tag == $t) | .obfs.password // ""' "$CONFIG_FILE")
                local batch_array="[]"
                local skipped=0
                local p
                for ((p=final_hop_start; p<=final_hop_end; p++)); do
                    if [ "$p" -eq "$new_port" ]; then continue; fi
                    # 浠呮鏌?config.json 涓槸鍚︽湁鍏朵粬鑺傜偣鍗犵敤锛堟帓闄よ嚜韬棫 hop 绔彛鍦ㄨ繘绋嬩腑浠嶅崰鐢ㄧ殑璇垽锛?                    if _check_port_in_config "$p"; then ((skipped++)); continue; fi
                    local hop_tag="${final_tag}-hop-${p}"
                    batch_array=$(echo "$batch_array" | jq --arg t "$hop_tag" --arg p "$p" --arg pw "$hy2_password" --arg cert "$cert_path" --arg key "$key_path" --arg op "$hy2_obfs_password" '. += [{"type":"hysteria2","tag":$t,"listen":"::","listen_port":($p|tonumber),"users":[{"password":$pw}],"tls":{"enabled":true,"alpn":["h3"],"certificate_path":$cert,"key_path":$key}} | if $op != "" then .obfs={"type":"salamander","password":$op} else . end]')
                done
                if [ "$(echo "$batch_array" | jq 'length')" -gt 0 ]; then
                    _atomic_modify_json "$CONFIG_FILE" ".inbounds += $batch_array" || return
                fi
                _info "宸查噸寤哄師鐢熺鍙ｈ烦璺冨瓙鑺傜偣锛岃寖鍥? ${final_hop_info}"
                if [ "$skipped" -gt 0 ]; then
                    _warning "鏈?${skipped} 涓烦璺冪鍙ｅ洜鍐茬獊琚烦杩囥€?
                fi
            else
                _info "宸茬Щ闄ゅ師鐢熺鍙ｈ烦璺冨瓙鑺傜偣銆?
            fi
        fi
    fi
    
    _success "绔彛淇敼鎴愬姛: ${old_port} -> ${new_port}"
    _manage_service "restart"
}

# --- 鏇存柊绠＄悊鑴氭湰 ---
_update_script() {
    _info "--- 鏇存柊鑴氭湰 ---"
    
    if [ "$SCRIPT_UPDATE_URL" == "YOUR_GITHUB_RAW_URL_HERE/singbox.sh" ]; then
        _error "閿欒锛氭偍灏氭湭鍦ㄨ剼鏈腑閰嶇疆 SCRIPT_UPDATE_URL 鍙橀噺銆?
        _warning "璇风紪杈戞鑴氭湰锛屾壘鍒?SCRIPT_UPDATE_URL 骞跺～鍏ユ偍姝ｇ‘鐨?GitHub raw 閾炬帴銆?
        return 1
    fi

    # 鏇存柊涓昏剼鏈?    _info "姝ｅ湪浠?GitHub 涓嬭浇鏈€鏂扮増鏈?.."
    local temp_script_path="${SELF_SCRIPT_PATH}.tmp"
    
    if wget -qO "$temp_script_path" "$SCRIPT_UPDATE_URL"; then
        if [ ! -s "$temp_script_path" ]; then
            _error "涓昏剼鏈笅杞藉け璐ユ垨鏂囦欢涓虹┖锛?
            rm -f "$temp_script_path"
            return 1
        fi
        
        chmod +x "$temp_script_path"
        mv "$temp_script_path" "$SELF_SCRIPT_PATH"
        _success "涓昏剼鏈?(singbox.sh) 鏇存柊鎴愬姛锛?
    else
        _error "涓昏剼鏈笅杞藉け璐ワ紒璇锋鏌ョ綉缁滄垨 GitHub 閾炬帴銆?
        rm -f "$temp_script_path"
        return 1
    fi
    
    # 闇€瑕佹洿鏂扮殑瀛愯剼鏈垪琛?    local sub_scripts=("advanced_relay.sh" "parser.sh" "xray_manager.sh")
    
    for script_name in "${sub_scripts[@]}"; do
        local updated=false
        # 澶氳矾寰勬娴嬶細1. 杈呭姪鐩綍 2. 褰撳墠鑴氭湰鍚岀骇鐩綍
        local paths_to_check=("${SINGBOX_DIR}/${script_name}" "${SCRIPT_DIR}/${script_name}")
        
        for script_path in "${paths_to_check[@]}"; do
            if [ -f "$script_path" ]; then
                local script_url="${GITHUB_RAW_BASE}/${script_name}"
                local temp_sub_path="${script_path}.tmp"
                
                _info "姝ｅ湪鏇存柊瀛愯剼鏈? ${script_name} -> ${script_path}..."
                if wget -qO "$temp_sub_path" "$script_url"; then
                    if [ -s "$temp_sub_path" ]; then
                        chmod +x "$temp_sub_path"
                        mv "$temp_sub_path" "$script_path"
                        updated=true
                        break
                    else
                        rm -f "$temp_sub_path"
                    fi
                else
                    rm -f "$temp_sub_path"
                fi
            fi
        done
        
        [ "$updated" = true ] && _success "瀛愯剼鏈?(${script_name}) 鏇存柊鎴愬姛銆? || _warning "瀛愯剼鏈?${script_name} 鏈彂鐜拌繍琛屼腑瀹炰緥鎴栦笅杞藉け璐ワ紝璺宠繃鏇存柊銆?
    done
    
    # 鏇存柊 yq 宸ュ叿锛堝鏋滅己澶辨垨鐗堟湰杩囨棫锛?    _install_yq
    
    _success "鎵€鏈夎剼鏈粍浠跺凡鏇存柊鑷虫渶鏂扮増 (v${SCRIPT_VERSION})锛?
    _info "璇烽噸鏂拌繍琛岃剼鏈互搴旂敤鎵€鏈夊彉鏇达細"
    echo -e "${YELLOW}bash ${SELF_SCRIPT_PATH}${NC}"
    exit 0
}

# 瀹堝崼鍑芥暟锛氭鏌?sing-box 鏍稿績鏄惁宸插畨瑁?_require_singbox() {
    if [ ! -f "${SINGBOX_BIN}" ]; then
        _error "姝ゅ姛鑳介渶瑕佸厛瀹夎 Sing-box 鏍稿績銆傝鍓嶅線涓昏彍鍗曘€愭牳蹇冪鐞嗐€?> [14] 杩涜瀹夎銆?
        return 1
    fi
    return 0
}

# [瀹夎/鏇存柊 Sing-box 鏍稿績] 鈥?鍙屾ā鎬侊細鏈灏辫銆佸凡瑁呭氨鏇存柊
_install_or_update_singbox() {
    if [ -f "${SINGBOX_BIN}" ]; then
        local current_ver=$(${SINGBOX_BIN} version 2>/dev/null | head -n1 | awk '{print $3}')
        _info "褰撳墠 Sing-box 鐗堟湰: v${current_ver}锛屾鍦ㄦ鏌ユ洿鏂?.."
    else
        _info "Sing-box 鏍稿績鏈畨瑁咃紝姝ｅ湪鎵ц棣栨瀹夎..."
    fi
    _do_update_singbox
}

# 鎵ц sing-box 鏍稿績鐨勫畨瑁?鏇存柊
_do_update_singbox() {
    _info "--- 瀹夎/鏇存柊 Sing-box 鏍稿績 ---"
    _install_sing_box
    
    if [ $? -eq 0 ]; then
        _success "sing-box 瀹夎/鏇存柊鎴愬姛锛?
        # 纭繚閰嶇疆鏂囦欢瀛樺湪
        if [ ! -f "${CONFIG_FILE}" ] || [ ! -f "${CLASH_YAML_FILE}" ]; then
            _info "妫€娴嬪埌涓婚厤缃枃浠剁己澶憋紝姝ｅ湪鍒濆鍖?.."
            _initialize_config_files
        fi
        _init_relay_config
        if [ ! -s "${SINGBOX_DIR}/relay.json" ]; then
            echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "${SINGBOX_DIR}/relay.json"
        fi
        _create_service_files
        _info "姝ｅ湪鍚姩/閲嶅惎 [涓籡 鏈嶅姟 (sing-box)..."
        _manage_service "restart"
        _success "[涓籡 鏈嶅姟宸插氨缁€?
    else
        _error "Sing-box 鏍稿績瀹夎/鏇存柊澶辫触銆?
    fi
}

# [瀹夎/鏇存柊 Xray 鏍稿績] 鈥?鍙屾ā鎬侊細鏈灏辫銆佸凡瑁呭氨鏇存柊
_install_or_update_xray() {
    local xray_bin="/usr/local/bin/xray"
    if [ -f "$xray_bin" ]; then
        local current_ver=$($xray_bin version 2>/dev/null | head -1 | awk '{print $2}')
        _info "褰撳墠 Xray 鐗堟湰: v${current_ver}锛屾鍦ㄦ鏌ユ洿鏂?.."
    else
        _info "Xray 鏍稿績鏈畨瑁咃紝姝ｅ湪鎵ц棣栨瀹夎..."
    fi
    _do_update_xray
}

# 鎵ц Xray 鏍稿績鐨勫畨瑁?鏇存柊 (鍐呰仈瀹炵幇锛岄伩鍏嶄緷璧?xray_manager.sh 鐨?source)
_do_update_xray() {
    _info "--- 瀹夎/鏇存柊 Xray 鏍稿績 ---"
    
    local xray_bin="/usr/local/bin/xray"
    local xray_dir="/usr/local/etc/xray"
    local is_first_install=false
    [ ! -f "$xray_bin" ] && is_first_install=true
    
    # 纭繚 unzip 鍙敤
    command -v unzip &>/dev/null || _pkg_install unzip
    
    local arch=$(uname -m)
    local xray_arch=""
    case "$arch" in
        x86_64|amd64)  xray_arch="64" ;;
        aarch64|arm64) xray_arch="arm64-v8a" ;;
        armv7l)        xray_arch="arm32-v7a" ;;
        *)             xray_arch="64" ;;
    esac
    
    local download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xray_arch}.zip"
    local tmp_dir=$(mktemp -d)
    local tmp_zip="${tmp_dir}/xray.zip"
    
    _info "涓嬭浇鍦板潃: ${download_url}"
    if ! wget -qO "$tmp_zip" "$download_url"; then
        _error "Xray 涓嬭浇澶辫触锛?
        rm -rf "$tmp_dir"
        return 1
    fi
    
    if ! unzip -qo "$tmp_zip" -d "$tmp_dir"; then
        _error "Xray 瑙ｅ帇澶辫触锛?
        rm -rf "$tmp_dir"
        return 1
    fi
    
    mv "${tmp_dir}/xray" "$xray_bin"
    chmod +x "$xray_bin"
    
    mkdir -p "$xray_dir"
    [ -f "${tmp_dir}/geoip.dat" ] && mv "${tmp_dir}/geoip.dat" "$xray_dir/"
    [ -f "${tmp_dir}/geosite.dat" ] && mv "${tmp_dir}/geosite.dat" "$xray_dir/"

    rm -rf "$tmp_dir"
    _release_install_cache
    
    local version=$($xray_bin version 2>/dev/null | head -1 | awk '{print $2}')
    _success "Xray-core v${version} 瀹夎/鏇存柊鎴愬姛锛?
    
    # 棣栨瀹夎鏃讹細鍒濆鍖栭厤缃笌鏈嶅姟
    if [ "$is_first_install" = true ]; then
        _info "棣栨瀹夎 Xray锛屾鍦ㄥ垵濮嬪寲閰嶇疆涓庢湇鍔?.."
        # 鍒濆鍖栭厤缃枃浠?        if [ ! -s "${xray_dir}/config.json" ]; then
            echo '{"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}],"routing":{"rules":[]}}' > "${xray_dir}/config.json"
        fi
        [ -s "${xray_dir}/metadata.json" ] || echo '{}' > "${xray_dir}/metadata.json"
        # 鍒涘缓 Xray 绯荤粺鏈嶅姟鏂囦欢
        _create_xray_service_from_main
        _info "姝ｅ湪鍚姩 Xray 鏈嶅姟..."
        if [ "$INIT_SYSTEM" == "systemd" ]; then
            systemctl start xray
        elif [ "$INIT_SYSTEM" == "openrc" ]; then
            rc-service xray start
        fi
        _success "Xray 棣栨瀹夎瀹屾垚骞跺凡鍚姩锛?
    else
        # 宸插畨瑁咃細閲嶅惎鏈嶅姟
        if command -v systemctl &>/dev/null && systemctl is-active xray &>/dev/null; then
            _info "姝ｅ湪閲嶅惎 Xray 鏈嶅姟..."
            systemctl restart xray
            _success "Xray 鏈嶅姟宸查噸鍚€?
        elif command -v rc-service &>/dev/null && rc-service xray status &>/dev/null 2>&1; then
            _info "姝ｅ湪閲嶅惎 Xray 鏈嶅姟..."
            rc-service xray restart
            _success "Xray 鏈嶅姟宸查噸鍚€?
        fi
    fi
}

# 浠庝富鑴氭湰鍒涘缓 Xray 鏈嶅姟鏂囦欢 (鍐呰仈瀹炵幇)
_create_xray_service_from_main() {
    local xray_bin="/usr/local/bin/xray"
    local xray_dir="/usr/local/etc/xray"
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        if [ ! -f "/etc/systemd/system/xray.service" ]; then
            cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=${xray_bin} run -c ${xray_dir}/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable xray
        fi
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        if [ ! -f "/etc/init.d/xray" ]; then
            cat > /etc/init.d/xray << 'EOF'
#!/sbin/openrc-run
name="xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -c /usr/local/etc/xray/config.json"
command_background=true
pidfile="/run/xray.pid"
EOF
            chmod +x /etc/init.d/xray
            rc-update add xray default 2>/dev/null
        fi
    fi
}

# --- 杩涢樁鍔熻兘 (瀛愯剼鏈? ---
_advanced_features() {
    local script_name="advanced_relay.sh"
    local script_path="${SINGBOX_DIR}/${script_name}"
    
    # 浼樺厛妫€娴嬪綋鍓嶇洰褰?(寮€鍙戣€?娴嬭瘯鐐逛紭鍏?
    if [ -f "$SCRIPT_DIR/$script_name" ]; then
        script_path="$SCRIPT_DIR/$script_name"
    fi

    # 濡傛灉閮戒笉瀛樺湪锛屽垯涓嬭浇
    if [ ! -f "$script_path" ]; then
        _info "鏈湴鏈娴嬪埌杩涢樁鑴氭湰锛屾鍦ㄥ皾璇曚笅杞?.."
        local download_url="${GITHUB_RAW_BASE}/${script_name}"
        
        if wget -qO "$script_path" "$download_url"; then
            chmod +x "$script_path"
            _success "涓嬭浇鎴愬姛锛?
        else
            _error "涓嬭浇澶辫触锛佽妫€鏌ョ綉缁滄垨纭 GitHub 浠撳簱鍦板潃銆?
            # 娓呯悊鍙兘鐨勭┖鏂囦欢
            rm -f "$script_path"
            return 1
        fi
    fi

    # 鎵ц鑴氭湰
    if [ -f "$script_path" ]; then
        # 璧嬩簣鏉冮檺骞舵墽琛?        chmod +x "$script_path"
        bash "$script_path"
    else
        _error "鎵句笉鍒拌繘闃惰剼鏈枃浠? ${script_path}"
    fi
}

# --- Xray 鑺傜偣绠＄悊 (瀛愯剼鏈? ---
_xray_features() {
    # 鍓嶇疆妫€鏌ワ細Xray 鏍稿績蹇呴』宸插畨瑁?    if [ ! -f "/usr/local/bin/xray" ]; then
        _error "Xray 鏍稿績鏈畨瑁咃紒璇峰厛閫氳繃涓昏彍鍗曘€愭牳蹇冪鐞嗐€?> [15] 杩涜瀹夎銆?
        return 1
    fi

    local script_name="xray_manager.sh"
    local script_path="${SINGBOX_DIR}/${script_name}"
    
    if [ -f "$SCRIPT_DIR/$script_name" ]; then
        script_path="$SCRIPT_DIR/$script_name"
    fi
    
    if [ ! -f "$script_path" ]; then
        _info "鏈湴鏈娴嬪埌 Xray 绠＄悊鑴氭湰锛屾鍦ㄥ皾璇曚笅杞?.."
        local download_url="${GITHUB_RAW_BASE}/${script_name}"
        if wget -qO "$script_path" "$download_url"; then
            chmod +x "$script_path"
            _success "涓嬭浇鎴愬姛锛?
        else
            _error "涓嬭浇澶辫触锛佽妫€鏌ョ綉缁滄垨纭 GitHub 浠撳簱鍦板潃銆?
            rm -f "$script_path"
            return 1
        fi
    fi
    
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        bash "$script_path"
    else
        _error "鎵句笉鍒?Xray 绠＄悊鑴氭湰: ${script_path}"
    fi
}

_main_menu() {
    while true; do
        clear
        # ASCII Logo
        echo -e "${CYAN}"
        echo '  ____  _             ____            '
        echo ' / ___|(_)_ __   __ _| __ )  _____  __'
        echo ' \___ \| | '\''_ \ / _` |  _ \ / _ \ \/ /'
        echo '  ___) | | | | | (_| | |_) | (_) >  < '
        echo ' |____/|_|_| |_|\__, |____/ \___/_/\_\'
        echo '                |___/    Lite Manager '
        echo -e "${NC}"
        
        # 鐗堟湰鏍囬
        echo -e "${CYAN}"
        echo "  鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
        echo "  鈺?        sing-box 绠＄悊鑴氭湰 v${SCRIPT_VERSION}         鈺?
        echo "  鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
        echo -e "${NC}"
        echo ""
        
        # 鑾峰彇绯荤粺淇℃伅
        local os_info="鏈煡"
        if [ -f /etc/os-release ]; then
            os_info=$(grep -E "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2 | head -1)
            [ -z "$os_info" ] && os_info=$(grep -E "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2 | head -1)
        fi
        [ -z "$os_info" ] && os_info=$(uname -s)
        
        # 鑾峰彇 Sing-box 鐗堟湰鍜岀姸鎬?        local sb_version=""
        local service_status="鈼?鏈煡"
        if [ -f "$SINGBOX_BIN" ]; then
            sb_version=" v$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')"
            if [ "$INIT_SYSTEM" == "systemd" ]; then
                if systemctl is-active --quiet sing-box 2>/dev/null; then
                    service_status="${GREEN}鈼?杩愯涓?{NC}"
                else
                    service_status="${RED}鈼?宸插仠姝?{NC}"
                fi
            elif [ "$INIT_SYSTEM" == "openrc" ]; then
                if rc-service sing-box status 2>/dev/null | grep -q "started"; then
                    service_status="${GREEN}鈼?杩愯涓?{NC}"
                else
                    service_status="${RED}鈼?宸插仠姝?{NC}"
                fi
            fi
        else
            service_status="${RED}鈼?鏈畨瑁?{NC}"
        fi
        
        # 鑾峰彇 Argo 鐘舵€?(淇 Alpine/BusyBox 鐨?ps 鎴柇闂锛氫紭鍏堜娇鐢?PID 鏂囦欢妫€娴?
        local argo_status="${RED}鈼?鏈畨瑁?{NC}"
        if [ -f "$CLOUDFLARED_BIN" ]; then
            local argo_running=false
            # 鏂瑰紡1 (绮惧噯): 閬嶅巻 PID 鏂囦欢锛屼笌瀹堟姢杩涚▼ _argo_keepalive 浣跨敤鐩稿悓鐨勬娴嬫柟寮?            for pid_file in /tmp/singbox_argo_*.pid; do
                [ -f "$pid_file" ] || continue
                local pid=$(cat "$pid_file" 2>/dev/null)
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    argo_running=true
                    break
                fi
            done
            # 鏂瑰紡2 (鍏滃簳): PID 鏂囦欢涓嶅瓨鍦ㄦ椂锛屽皾璇?pgrep 鎴?ps 鍖归厤杩涚▼鍚?            if [ "$argo_running" = false ]; then
                if command -v pgrep &>/dev/null; then
                    pgrep -x cloudflared &>/dev/null && argo_running=true
                elif ps w 2>/dev/null | grep -v "grep" | grep -q "cloudflared"; then
                    argo_running=true
                fi
            fi
            if [ "$argo_running" = true ]; then
                argo_status="${GREEN}鈼?杩愯涓?{NC}"
            else
                argo_status="${YELLOW}鈼?宸插畨瑁?(鏈繍琛?${NC}"
            fi
        fi
        
        # 鑾峰彇 Xray 鐗堟湰鍜岀姸鎬?        local xray_version=""
        local xray_status="${RED}鈼?鏈畨瑁?{NC}"
        if [ -f "/usr/local/bin/xray" ]; then
            xray_version=" v$(/usr/local/bin/xray version 2>/dev/null | head -1 | awk '{print $2}')"
            if [ "$INIT_SYSTEM" == "systemd" ]; then
                if systemctl is-active --quiet xray 2>/dev/null; then
                    xray_status="${GREEN}鈼?杩愯涓?{NC}"
                else
                    xray_status="${YELLOW}鈼?宸插仠姝?{NC}"
                fi
            elif [ "$INIT_SYSTEM" == "openrc" ]; then
                if rc-service xray status 2>/dev/null | grep -q "started"; then
                    xray_status="${GREEN}鈼?杩愯涓?{NC}"
                else
                    xray_status="${YELLOW}鈼?宸插仠姝?{NC}"
                fi
            fi
            local xray_nodes=$(jq '.inbounds | length' /usr/local/etc/xray/config.json 2>/dev/null || echo "0")
            xray_status="${xray_status} (${xray_nodes}鑺傜偣)"
        fi
        
        echo -e "  绯荤粺: ${CYAN}${os_info}${NC}  |  妯″紡: ${CYAN}${INIT_SYSTEM}${NC}"
        echo -e "  Sing-box${CYAN}${sb_version}${NC}: ${service_status}  |  Argo: ${argo_status}"
        echo -e "  Xray${CYAN}${xray_version}${NC}: ${xray_status}"
        echo ""
        
        # 鑺傜偣绠＄悊
        echo -e "  ${CYAN}銆愯妭鐐圭鐞嗐€?{NC}"
        echo -e "    ${GREEN}[1]${NC} 娣诲姞鑺傜偣          ${GREEN}[2]${NC} Suoha 涓閿洏閬"
        echo -e "    ${GREEN}[3]${NC} 鏌ョ湅鑺傜偣閾炬帴      ${GREEN}[4]${NC} 鍒犻櫎鑺傜偣"
        echo -e "    ${GREEN}[5]${NC} 淇敼鑺傜偣绔彛"
        echo ""
        
        # 鏈嶅姟鎺у埗
        echo -e "  ${CYAN}銆愭湇鍔℃帶鍒躲€?{NC}"
        echo -e "    ${GREEN}[6]${NC} 閲嶅惎鏈嶅姟          ${GREEN}[7]${NC} 鍋滄鏈嶅姟"
        echo -e "    ${GREEN}[8]${NC} 鏌ョ湅杩愯鐘舵€?     ${GREEN}[9]${NC} 鏌ョ湅瀹炴椂鏃ュ織"
        echo -e "    ${GREEN}[10]${NC} 瀹氭椂閲嶅惎璁剧疆"
        echo -e "    ${GREEN}[11]${NC} 鍚屾绯荤粺鏃堕棿"
        echo ""
        
        # 閰嶇疆涓庢洿鏂?        echo -e "  ${CYAN}銆愰厤缃笌鏇存柊銆?{NC}"
        echo -e "    ${GREEN}[12]${NC} 妫€鏌ラ厤缃枃浠?   ${GREEN}[13]${NC} 鏇存柊鑴氭湰"
        echo ""
        
        # 鏍稿績绠＄悊
        echo -e "  ${CYAN}銆愭牳蹇冪鐞嗐€?{NC}"
        echo -e "    ${GREEN}[14]${NC} 瀹夎/鏇存柊 Sing-box 鏍稿績"
        echo -e "    ${GREEN}[15]${NC} 瀹夎/鏇存柊 Xray 鏍稿績"
        echo -e "    ${RED}[16]${NC} 鍗歌浇鑴氭湰"
        echo ""
        
        # 杩涢樁鍔熻兘
        echo -e "  ${CYAN}銆愯繘闃跺姛鑳姐€?{NC}"
        echo -e "    ${GREEN}[17]${NC} 钀藉湴/涓浆/绗笁鏂硅妭鐐瑰鍏?
        echo -e "    ${GREEN}[18]${NC} Xray 鑺傜偣绠＄悊"
        echo ""
        
        echo -e "  鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
        echo -e "    ${YELLOW}[0]${NC} 閫€鍑鸿剼鏈?
        echo ""
        
        read -p "  璇疯緭鍏ラ€夐」 [0-18]: " choice
 
        case $choice in
            1) _require_singbox && _show_add_node_menu ;;
            2) _suoha_menu ;;
            3) _require_singbox && _view_nodes ;;
            4) _require_singbox && _delete_node ;;
            5) _require_singbox && _modify_port ;;
            6) _require_singbox && _manage_service "restart" ;;
            7) _require_singbox && _manage_service "stop" ;;
            8) _require_singbox && _manage_service "status" ;;
            9) _require_singbox && _view_log ;;
            10) _require_singbox && _scheduled_restart_menu ;;
            11) _sync_system_time ;;
            12) _require_singbox && _check_config ;;
            13) _update_script ;;
            14) _install_or_update_singbox ;;
            15) _install_or_update_xray ;;
            16) _uninstall ;; 
            17) _require_singbox && _advanced_features ;;
            18) _xray_features ;;
            0) exit 0 ;;
            *) _error "鏃犳晥杈撳叆锛岃閲嶈瘯銆? ;;
        esac
        echo
        read -n 1 -s -r -p "鎸変换鎰忛敭杩斿洖涓昏彍鍗?.."
    done
}

    # 瀹氭椂閲嶅惎鍔熻兘 - 闆朵緷璧栫増鏈?(Systemd Timer & OpenRC Logic)
    _scheduled_restart_menu() {
        clear
        echo -e "${CYAN}"
        echo '  鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
        echo '  鈺?        瀹氭椂閲嶅惎 sing-box             鈺?
        echo '  鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
        echo -e "${NC}"
        echo ""
        
        # [!] 闆朵緷璧栫瓥鐣ワ細涓嶅啀瀹夎 cron
        # 浠呯畝鍗曠殑鐜棰勫垽
        if [ "$INIT_SYSTEM" == "unknown" ]; then
            _error "鏈兘璇嗗埆绯荤粺鍒濆鍖栫幆澧?(systemd/openrc)锛屽畾鏃堕噸鍚姛鑳芥殏涓嶅彲鐢ㄣ€?
            read -n 1 -s -r -p "鎸変换鎰忛敭杩斿洖..."
            return
        fi

    
    # 鑾峰彇鏈嶅姟鍣ㄦ椂闂翠俊鎭?    local server_time=$(date '+%Y-%m-%d %H:%M:%S')
    local server_tz_offset=$(date +%z)  # 濡? +0800, +0000, -0500
    local server_tz_name=$(date +%Z 2>/dev/null || echo "Unknown")  # 濡? CST, UTC
    
    # 瑙ｆ瀽鏃跺尯鍋忕Щ (鏍煎紡: +0800 鎴?-0500)
    local offset_sign="${server_tz_offset:0:1}"
    local offset_hours="${server_tz_offset:1:2}"
    local offset_mins="${server_tz_offset:3:2}"
    
    # 鍘婚櫎鍓嶅闆?    offset_hours=$((10#$offset_hours))
    offset_mins=$((10#$offset_mins))
    
    # 璁＄畻鎬诲亸绉诲垎閽熸暟
    local server_offset_mins=$((offset_hours * 60 + offset_mins))
    if [ "$offset_sign" == "-" ]; then
        server_offset_mins=$((-server_offset_mins))
    fi
    
    # 鍖椾含鏃堕棿 = UTC+8 = +480 鍒嗛挓
    local beijing_offset_mins=480
    local diff_mins=$((beijing_offset_mins - server_offset_mins))
    local diff_hours=$((diff_mins / 60))
    local diff_remaining_mins=$((diff_mins % 60))
    
    # 鏍煎紡鍖栨樉绀?    local diff_display=""
    if [ $diff_mins -gt 0 ]; then
        diff_display="鍖椾含鏃堕棿姣旀湇鍔″櫒蹇?${diff_hours} 灏忔椂"
        if [ $diff_remaining_mins -ne 0 ]; then
            diff_display="${diff_display} ${diff_remaining_mins} 鍒嗛挓"
        fi
    elif [ $diff_mins -lt 0 ]; then
        diff_display="鍖椾含鏃堕棿姣旀湇鍔″櫒鎱?$((-diff_hours)) 灏忔椂"
        if [ $diff_remaining_mins -ne 0 ]; then
            diff_display="${diff_display} $((-diff_remaining_mins)) 鍒嗛挓"
        fi
    else
        diff_display="鏈嶅姟鍣ㄤ笌鍖椾含鏃堕棿鍚屾"
    fi
    
    # 妫€鏌ュ綋鍓嶅畾鏃朵换鍔＄姸鎬?    local cron_status="鏈缃?
    local cron_time=""
    
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        if [ -f "/etc/systemd/system/sing-box-restart.timer" ]; then
            cron_time=$(grep "OnCalendar" /etc/systemd/system/sing-box-restart.timer | cut -d' ' -f2 | cut -d: -f1,2)
            cron_status="宸插惎鐢?(姣忓ぉ ${cron_time} 閲嶅惎 - Systemd)"
        fi
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        if [ -f "/etc/init.d/sing-box-timer" ] && rc-service sing-box-timer status &>/dev/null; then
            cron_time=$(grep "RESTART_TIME=" /etc/init.d/sing-box-timer | cut -d'"' -f2)
            cron_status="宸插惎鐢?(姣忓ぉ ${cron_time} 閲嶅惎 - OpenRC)"
        fi
    fi
    
    echo -e "  ${CYAN}銆愭湇鍔″櫒鏃堕棿淇℃伅銆?{NC}"
    echo -e "    褰撳墠鏃堕棿: ${GREEN}${server_time}${NC}"
    echo -e "    鏃跺尯: ${GREEN}${server_tz_name} (UTC${server_tz_offset})${NC}"
    echo -e "    涓庡寳浜椂闂? ${YELLOW}${diff_display}${NC}"
    echo ""
    echo -e "  ${CYAN}銆愬畾鏃堕噸鍚姸鎬併€?{NC}"
    if [ "$cron_status" != "鏈缃? ]; then
        echo -e "    鐘舵€? ${GREEN}${cron_status}${NC}"
    else
        echo -e "    鐘舵€? ${YELLOW}${cron_status}${NC}"
    fi
    echo ""
    echo -e "  鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
    echo -e "    ${GREEN}[1]${NC} 璁剧疆瀹氭椂閲嶅惎"
    echo -e "    ${GREEN}[2]${NC} 鏌ョ湅褰撳墠璁剧疆"
    echo -e "    ${RED}[3]${NC} 鍙栨秷瀹氭椂閲嶅惎"
    echo ""
    echo -e "    ${YELLOW}[0]${NC} 杩斿洖涓昏彍鍗?
    echo ""
    
    read -p "  璇疯緭鍏ラ€夐」 [0-3]: " choice
    
    case $choice in
        1)
            echo ""
            echo -e "  ${CYAN}璁剧疆瀹氭椂閲嶅惎鏃堕棿${NC}"
            echo -e "  鎻愮ず: 杈撳叆鏈嶅姟鍣ㄦ椂鍖虹殑鏃堕棿 (24灏忔椂鍒?"
            echo ""
            read -p "  璇疯緭鍏ラ噸鍚椂闂?(鏍煎紡 HH:MM, 濡?04:30): " restart_time
            
            # 楠岃瘉鏃堕棿鏍煎紡
            if [[ ! "$restart_time" =~ ^([0-1]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
                _error "鏃堕棿鏍煎紡閿欒锛佽浣跨敤 HH:MM 鏍煎紡 (濡?04:30)"
                return
            fi
            
            local hour=$(echo "$restart_time" | cut -d: -f1)
            local min=$(echo "$restart_time" | cut -d: -f2)
            local time_str=$(printf "%02d:%02d" "$((10#$hour))" "$((10#$min))")

            if [ "$INIT_SYSTEM" == "systemd" ]; then
                # Systemd Timer 鏂规
                cat > /etc/systemd/system/sing-box-restart.service <<EOF
[Unit]
Description=Sing-box Scheduled Restart
[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart sing-box
EOF
                cat > /etc/systemd/system/sing-box-restart.timer <<EOF
[Unit]
Description=Sing-box Scheduled Restart Timer
[Timer]
OnCalendar=*-*-* ${time_str}:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
                systemctl daemon-reload
                systemctl enable --now sing-box-restart.timer
            elif [ "$INIT_SYSTEM" == "openrc" ]; then
                # OpenRC 璋冨害鏈嶅姟鏂规
                cat > /usr/local/bin/sb-timer.sh <<EOF
#!/bin/bash
TARGET_TIME="\$1"
while true; do
    [ "\$(date +%H:%M)" == "\$TARGET_TIME" ] && rc-service sing-box restart && sleep 61
    sleep 30
done
EOF
                chmod +x /usr/local/bin/sb-timer.sh
                cat > /etc/init.d/sing-box-timer <<EOF
#!/sbin/openrc-run
description="Sing-box Scheduled Restart Timer"
command="/usr/local/bin/sb-timer.sh"
command_args="${time_str}"
pidfile="/run/sing-box-timer.pid"
command_background=true
RESTART_TIME="${time_str}"
EOF
                chmod +x /etc/init.d/sing-box-timer
                rc-service sing-box-timer restart 2>/dev/null
                rc-update add sing-box-timer default 2>/dev/null
            fi
            
            _success "瀹氭椂閲嶅惎宸查€氳繃 ${INIT_SYSTEM} 鍘熺敓缁勪欢璁剧疆瀹屾垚锛?
            echo ""
            echo -e "  閲嶅惎鏃堕棿: ${GREEN}姣忓ぉ ${time_str}${NC} (鏈嶅姟鍣ㄦ椂鍖?"
                
                # 璁＄畻瀵瑰簲鐨勫寳浜椂闂?                local beijing_hour=$((hour + diff_hours))
                local beijing_min=$((min + diff_remaining_mins))
                
                # 澶勭悊鍒嗛挓婧㈠嚭
                if [ $beijing_min -ge 60 ]; then
                    beijing_min=$((beijing_min - 60))
                    beijing_hour=$((beijing_hour + 1))
                elif [ $beijing_min -lt 0 ]; then
                    beijing_min=$((beijing_min + 60))
                    beijing_hour=$((beijing_hour - 1))
                fi
                
                # 澶勭悊灏忔椂婧㈠嚭
                if [ $beijing_hour -ge 24 ]; then
                    beijing_hour=$((beijing_hour - 24))
                elif [ $beijing_hour -lt 0 ]; then
                    beijing_hour=$((beijing_hour + 24))
                fi
                
                echo -e "  瀵瑰簲鍖椾含鏃堕棿: ${YELLOW}$(printf "%02d:%02d" "$beijing_hour" "$beijing_min")${NC}"
            ;;
        2)
            echo ""
            echo -e "  ${CYAN}褰撳墠瀹氭椂浠诲姟璇︽儏:${NC}"
            if [ "$INIT_SYSTEM" == "systemd" ]; then
                systemctl list-timers sing-box-restart.timer --no-pager
            elif [ "$INIT_SYSTEM" == "openrc" ]; then
                rc-service sing-box-timer status
            fi
            ;;
        3)
            echo ""
            if [ "$cron_status" == "鏈缃? ]; then
                _warning "褰撳墠娌℃湁璁剧疆瀹氭椂閲嶅惎"
            else
                read -p "$(echo -e ${YELLOW}"  纭畾鍙栨秷瀹氭椂閲嶅惎? (y/N): "${NC})" confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    if [ "$INIT_SYSTEM" == "systemd" ]; then
                        systemctl disable --now sing-box-restart.timer 2>/dev/null
                        rm -f /etc/systemd/system/sing-box-restart.timer /etc/systemd/system/sing-box-restart.service
                        systemctl daemon-reload
                    elif [ "$INIT_SYSTEM" == "openrc" ]; then
                        rc-service sing-box-timer stop 2>/dev/null
                        rc-update del sing-box-timer default 2>/dev/null
                        rm -f /etc/init.d/sing-box-timer /usr/local/bin/sb-timer.sh
                    fi
                    _success "瀹氭椂閲嶅惎宸插彇娑堬紝鐩稿叧绯荤粺缁勪欢宸叉竻鐞嗐€?
                else
                    _info "宸插彇娑堟搷浣?
                fi
            fi
            ;;
        0)
            return
            ;;
        *)
            _error "鏃犳晥杈撳叆"
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "鎸変换鎰忛敭缁х画..."
}

# 鎵归噺鍒涘缓鑺傜偣 (v11.3 娣卞害鍚戝鐗?
_batch_create_nodes() {
    local input_str="$1"
    if [ -z "$input_str" ]; then
        _info "璇疯緭鍏ュ崗璁紪鍙?(绌烘牸鎴栭€楀彿鍒嗛殧锛屽: 1,5,8)"
        _warn "娉細鎵归噺閮ㄧ讲涓嶆敮鎸佸惈鏈?CDN 鐨勫崗璁?(2, 3)"
        read -p "鍗忚鍒楄〃: " input_str
    fi
    [ -z "$input_str" ] && return 1

    # 1. 瑙ｆ瀽鍗忚鍒楄〃
    local proto_ids=$(echo "$input_str" | tr ',' ' ' | xargs)
    local proto_count=0
    local has_complex=false 
    local has_sni_req=false 
    local has_hy2=false     
    local has_ss=false      
    local ss_occurences=0

    for pid in $proto_ids; do
        if [[ "$pid" =~ ^(2|3)$ ]]; then
            _error "鍗忚 ID $pid (WebSocket+TLS) 涓嶆敮鎸佹壒閲忓垱寤猴紝璇蜂娇鐢ㄥ崟鑺傜偣妯″紡鍗曠嫭鍒涘缓浠ュ紑鍚珮绾?CDN 浼樺寲銆?
            return 1
        fi
        ((proto_count++))
        if [[ "$pid" == "7" ]]; then
            has_ss=true
            ((ss_occurences++))
        fi
        [[ "$pid" =~ ^(5|7)$ ]] && has_complex=true
        [[ "$pid" =~ ^(1|4|5|6)$ ]] && has_sni_req=true
        [[ "$pid" == "5" ]] && has_hy2=true
    done

    [ $proto_count -eq 0 ] && { _error "鏈€夋嫨浠讳綍鍗忚"; return 1; }

    # 2. 寮曞鍚戝
    _info "--- 鎵归噺閮ㄧ讲寮曞鍚戝 ---"
    
    # [淇] 寮哄埗鍒濆鍖栨湇鍔″櫒 IP锛岄槻姝㈠悇鍗忚鍑芥暟鍥犲彉閲忔湭瀹氫箟鐢熸垚绌洪厤缃?    [ -z "$server_ip" ] && server_ip=$(_get_ip)
    local batch_ip="${server_ip}"
    read -p "璇疯緭鍏ユ壒閲忚妭鐐圭粦瀹氱殑IP鍦板潃 (鍥炶溅榛樿: ${server_ip}): " custom_batch_ip
    batch_ip=${custom_batch_ip:-$server_ip}
    export BATCH_IP="$batch_ip"
    
    # 2.1 SNI 鏀堕泦 (寮哄埗鍑€鍖栧鐞?
    export BATCH_SNI="$DEFAULT_SNI"
    if [ "$has_sni_req" = true ]; then
        read -p "璇疯緭鍏ョ粺涓€浼鍩熷悕 (SNI) [榛樿: $BATCH_SNI]: " input_sni
        input_sni=$(echo "$input_sni" | xargs)
        [ -n "$input_sni" ] && BATCH_SNI="$input_sni"
    fi

    # 2.2 Hy2 涓撻」
    local hy2_obfs="none"
    local hy2_hop="false"
    local hy2_hop_range=""
    if [ "$has_hy2" = true ]; then
        read -p "鏄惁寮€鍚?Hysteria2 QUIC 娣锋穯? (y/N): " hy2_q_choice
        [[ "$hy2_q_choice" == "y" ]] && hy2_obfs="salamander"
        read -p "鏄惁寮€鍚?Hysteria2 绔彛璺宠穬? (y/N): " hy2_h_choice
        if [[ "$hy2_h_choice" == "y" ]]; then
            hy2_hop="true"
            read -p "璇疯緭鍏ョ鍙ｈ烦璺冭寖鍥?(濡?20000-30000): " hy2_hop_range
        fi
    fi

    # 2.4 SS 涓撻」 (鏀寔澶氶€?
    local ss_variant="1"
    if [ "$has_ss" = true ]; then
        echo "閫夋嫨 Shadowsocks 鎵归噺鍔犲瘑鏂瑰紡 (鏀寔澶氶€夛紝濡?1,2,3,4):"
        echo " 1) aes-256-gcm"
        echo " 2) chacha20-ietf-poly1305"
        echo " 3) 2022-blake3-aes-256-gcm"
        echo " 4) 2022-blake3-aes-256-gcm (甯?Padding)"
        read -p "閫夋嫨 [1-4] (榛樿1): " ss_choice
        ss_variant=${ss_choice:-1}
        # 璁＄畻 SS 瀹為檯闇€瑕佺殑绔彛鏁?        local ss_needed=$(echo "$ss_variant" | tr ',' ' ' | wc -w)
        # 姣忎釜 Shadowsocks ID (7) 棰濆闇€瑕?(ss_needed - 1) 涓鍙?        proto_count=$((proto_count + (ss_needed - 1) * ss_occurences))
    fi

    # 3. 绔彛瑙勫垝
    local ports_list=()
    _info "鍏遍渶瑙勫垝 $proto_count 涓壒閲忕洃鍚鍙ｃ€?
    while true; do
        read -p "璇疯緭鍏ョ鍙ｅ彿 (鑼冨洿濡?10001-10010 鎴栫┖鏍煎垎闅?: " p_input
        local current_p_list=()
        if [[ "$p_input" == *"-"* ]]; then
            local start_p=$(echo $p_input | cut -d'-' -f1)
            local end_p=$(echo $p_input | cut -d'-' -f2)
            for ((p=start_p; p<=end_p; p++)); do current_p_list+=($p); done
        else
            current_p_list=($p_input)
        fi
        
        if [ ${#current_p_list[@]} -lt $proto_count ]; then
            _error "杈撳叆绔彛鏁伴噺涓嶈冻锛堜粎 ${#current_p_list[@]} 涓級锛岃閲嶆柊杈撳叆銆?
        else
            ports_list=("${current_p_list[@]}")
            break
        fi
    done

    # 4. 鎵ц瀹夎寰幆
    local bulk_idx=0
    local proto_array=($proto_ids)
    for i in "${!proto_array[@]}"; do
        local pid=${proto_array[$i]}
        
        if [ "$pid" == "7" ]; then
            local ss_variants=$(echo "$ss_variant" | tr ',' ' ')
            for v in $ss_variants; do
                local current_port=${ports_list[$bulk_idx]}
                _info "姝ｅ湪瀹夎 Shadowsocks (鍙樹綋 $v) 鍒扮鍙?$current_port..."
                export BATCH_MODE="true"
                export BATCH_PORT="$current_port"
                export BATCH_SS_VARIANT="$v"
                _add_shadowsocks_menu
                ((bulk_idx++))
            done
        else
            local current_port=${ports_list[$bulk_idx]}
            _info "姝ｅ湪瀹夎鍗忚 [$pid] 鍒扮鍙?$current_port..."
            
            export BATCH_MODE="true"
            export BATCH_PORT="$current_port"
            export BATCH_HY2_OBFS="$hy2_obfs"
            export BATCH_HY2_HOP="$hy2_hop_range"

            case $pid in
                1) _add_vless_reality ;;
                2) _add_vless_ws_tls ;;
                3) _add_trojan_ws_tls ;;
                4) _add_anytls ;;
                5) _add_hysteria2 ;;
                6) _add_tuic ;;
                8) _add_vless_tcp ;;
                9) _add_socks ;;
            esac
            ((bulk_idx++))
        fi
    done

    unset BATCH_MODE BATCH_PORT BATCH_SNI BATCH_HY2_OBFS BATCH_HY2_HOP BATCH_SS_VARIANT BATCH_IP
    
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲 鎵归噺鍒涘缓瀹屾垚鎻愮ず 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    _success "鎵€鏈夎妭鐐瑰凡鎸夌洿杩炴ā寮忛儴缃插畬姣曘€?
    _info "鎵€鏈夋壒閲忚妭鐐瑰凡灏辩华锛屾偍鍙互杩愯 sb 鏌ョ湅鍏蜂綋閰嶇疆銆?
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"

    _success "鎵归噺鍒涘缓浠诲姟宸插叏閮ㄥ畬鎴愩€?
    _manage_service restart
}

_show_add_node_menu() {
    local needs_restart=false
    local action_result
    clear
    echo -e "${CYAN}"
    echo '  鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    echo '  鈺?         sing-box 娣诲姞鑺傜偣            鈺?
    echo '  鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    echo -e "${NC}"
    echo ""
    
    echo -e "  ${CYAN}銆愬崗璁€夋嫨銆?{NC}"
    echo -e "    ${GREEN}[1]${NC} VLESS (Vision+REALITY)"
    echo -e "    ${GREEN}[2]${NC} VLESS (WebSocket+TLS)"
    echo -e "    ${GREEN}[3]${NC} Trojan (WebSocket+TLS)"
    echo -e "    ${GREEN}[4]${NC} AnyTLS"
    echo -e "    ${GREEN}[5]${NC} Hysteria2"
    echo -e "    ${GREEN}[6]${NC} TUICv5"
    echo -e "    ${GREEN}[7]${NC} Shadowsocks"
    echo -e "    ${GREEN}[8]${NC} VLESS (TCP)"
    echo -e "    ${GREEN}[9]${NC} SOCKS5"
    echo ""
    
    echo -e "  ${CYAN}銆愬揩鎹峰姛鑳姐€?{NC}"
    echo -e "   ${GREEN}[10]${NC} 鎵归噺鍒涘缓鑺傜偣"
    echo ""
    
    echo -e "  鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€"
    echo -e "    ${YELLOW}[0]${NC} 杩斿洖涓昏彍鍗?
    echo ""
    
    read -p "  璇疯緭鍏ラ€夐」 [0-10]: " choice

    # 濡傛灉杈撳叆鍖呭惈閫楀彿鎴栫┖鏍硷紝鑷姩杩涘叆鎵归噺澶勭悊妯″紡
    if [[ "$choice" == *","* ]] || [[ "$choice" == *" "* ]]; then
        _batch_create_nodes "$choice"
        return
    fi

    case $choice in
        1) _add_vless_reality; action_result=$? ;;
        2) _add_vless_ws_tls; action_result=$? ;;
        3) _add_trojan_ws_tls; action_result=$? ;;
        4) _add_anytls; action_result=$? ;;
        5) _add_hysteria2; action_result=$? ;;
        6) _add_tuic; action_result=$? ;;
        7) _add_shadowsocks_menu; action_result=$? ;;
        8) _add_vless_tcp; action_result=$? ;;
        9) _add_socks; action_result=$? ;;
        10) _batch_create_nodes; return ;;
        0) return ;;
        *) _error "鏃犳晥杈撳叆锛岃閲嶈瘯銆? ;;
    esac

    if [ "$action_result" -eq 0 ] 2>/dev/null; then
        needs_restart=true
    fi

    if [ "$needs_restart" = true ]; then
        _info "閰嶇疆宸叉洿鏂?
        _manage_service "restart"
    fi
}

# --- 鑴氭湰鍏ュ彛 ---

main() {
    _check_root
    _detect_init_system
    
    # 寮哄埗棰勫垱寤虹洰褰曪紝闃叉鍚庣画 cp/mv 鍥犺矾寰勪笉瀛樺湪鎶ラ敊 (淇濆簳鏈哄埗)
    mkdir -p "${SINGBOX_DIR}" 2>/dev/null
    
    # 1. 濮嬬粓妫€鏌ヤ緷璧?    _install_dependencies
    
    # 鑾峰彇褰掑彛鍚庣殑鍏綉 IP (鍦ㄤ緷璧栨鏌ュ悗鎵ц浠ョ‘淇?curl 鍙敤)
    _init_server_ip

    # 2. 鏍规嵁鏍稿績瀹夎鐘舵€佸喅瀹氬垵濮嬪寲璺緞
    if [ -f "${SINGBOX_BIN}" ]; then
        # --- sing-box 宸插畨瑁咃細鎵ц瀹屾暣鐨勫垵濮嬪寲涓庤嚜鎰堟娴?---
        
        # 3. 妫€鏌ラ厤缃枃浠?        if [ ! -f "${CONFIG_FILE}" ] || [ ! -f "${CLASH_YAML_FILE}" ]; then
             _info "妫€娴嬪埌涓婚厤缃枃浠剁己澶憋紝姝ｅ湪鍒濆鍖?.."
             _initialize_config_files
        fi

        # 3.1 鍒濆鍖栦腑杞厤缃?(閰嶇疆闅旂)
        _init_relay_config
        
        # 3.2 [鍏抽敭淇] 娓呯悊涓婚厤缃枃浠朵腑鐨勬棫鐗堟畫鐣?        local config_updated=false
        if _cleanup_legacy_config; then
            config_updated=true
        fi
        
        # 3.3 [鐑慨澶峕 妫€娴嬪苟琛ュ厖 DNS 妯″潡
        if _check_and_fix_dns; then
            config_updated=true
        fi
        
        if [ "$config_updated" = true ]; then
            _manage_service restart
        fi
        
        # [BUG FIX] 妫€鏌ュ苟淇鏃х増鏈嶅姟鏂囦欢
        if [ -f "$SERVICE_FILE" ]; then
            local need_update=false
            if grep -q "\-C " "$SERVICE_FILE"; then
                _warn "妫€娴嬪埌鏃х増鏈嶅姟閰嶇疆(鐩綍鍔犺浇妯″紡瀵艰嚧鍐茬獊)锛屾鍦ㄤ慨澶?.."
                need_update=true
            fi
            if [ "$INIT_SYSTEM" == "openrc" ] && ! grep -q "supervisor=" "$SERVICE_FILE"; then
                _warn "妫€娴嬪埌鏃х増 OpenRC 鏈嶅姟閰嶇疆锛屾鍦ㄤ慨澶嶄互鍏煎 Alpine..."
                need_update=true
            fi
            if [ "$need_update" = true ]; then
                if [ "$INIT_SYSTEM" == "systemd" ]; then
                     _create_systemd_service
                     systemctl daemon-reload
                elif [ "$INIT_SYSTEM" == "openrc" ]; then
                     _create_openrc_service
                fi
                if systemctl is-active sing-box >/dev/null 2>&1 || rc-service sing-box status >/dev/null 2>&1; then
                    _manage_service restart
                fi
                _success "鏈嶅姟閰嶇疆淇瀹屾垚銆?
            fi
        fi

        # [PATH FIX] 纭繚 relay.json 瀛樺湪
        if [ ! -s "${SINGBOX_DIR}/relay.json" ]; then
            echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "${SINGBOX_DIR}/relay.json"
        fi

        # 4. 纭繚鏈嶅姟鏂囦欢宸插垱寤?        _create_service_files
    else
        # --- sing-box 鏈畨瑁咃細浠呮樉绀烘彁绀猴紝涓嶈嚜鍔ㄥ畨瑁?---
        _warn "sing-box 鏍稿績鏈畨瑁呫€傝閫氳繃涓昏彍鍗曘€愭牳蹇冪鐞嗐€戣繘琛屽畨瑁呫€?
    fi
    
}

# ==================== Suoha 功能 ====================
_suoha_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo '  ╔═══════════════════════════════════════════════════════╗'
        echo '  ║  ____  _             ____                            ║'
        echo '  ║ / ___|(_)_ __   __ _| __ )  _____  __                ║'
        echo '  ║ \___ \| | '\''_ \ / _` |  _ \ / _ \ \/ /                ║'
        echo '  ║  ___) | | | | | (_| | |_) | (_) >  <                 ║'
        echo '  ║ |____/|_|_| |_|\__, |____/ \___/_/\_\                ║'
        echo '  ║                |___/   Suoha 一键隧道                ║'
        echo '  ╚═══════════════════════════════════════════════════════╝'
        echo -e "${NC}"
        echo ""
        echo -e "  ${CYAN}【说明】${NC}"
        echo "  基于 Cloudflare Tunnel 的超轻量级穿透工具"
        echo "  无需公网 IP，无需端口转发，极致隐藏，专为 NAT VPS 打造"
        echo ""
        
        # 检查系统类型
        local linux_os=""
        local is_alpine=false
        if [ -f /etc/os-release ]; then
            linux_os=$(grep -E "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2 | cut -d' ' -f1)
        fi
        [ -z "$linux_os" ] && linux_os=$(uname -s)
        
        if echo "$linux_os" | grep -qi "alpine"; then
            is_alpine=true
        fi
        
        echo -e "  ${CYAN}【主菜单】${NC}"
        echo -e "    ${GREEN}[1]${NC} 梭哈模式（无需 CF 域名，重启失效）"
        echo -e "    ${GREEN}[2]${NC} 安装服务（需要 CF 域名，永久使用）"
        echo -e "    ${GREEN}[3]${NC} 卸载服务"
        echo -e "    ${GREEN}[4]${NC} 清空缓存"
        echo -e "    ${GREEN}[5]${NC} 管理服务（如果已安装）"
        echo ""
        echo -e "    ${YELLOW}[0]${NC} 返回主菜单"
        echo ""
        
        read -p "  请选择模式 [0-5]: " mode
        [ -z "$mode" ] && mode=1
        
        case $mode in
            1) _suoha_quick_tunnel ;;
            2) _suoha_install_service ;;
            3) _suoha_uninstall_service ;;
            4) _suoha_clear_cache ;;
            5) _suoha_manage_service ;;
            0) break ;;
            *) _error "无效输入，请重试。" ;;
        esac
        
        if [ "$mode" != "0" ]; then
            echo ""
            read -n 1 -s -r -p "按任意键继续.."
        fi
    done
}

# 检测已安装的核心
_suoha_detect_core() {
    local detected_core=""
    
    # 检查 Xray
    if command -v xray &>/dev/null; then
        detected_core="xray"
    elif [ -f "/usr/local/bin/xray" ]; then
        detected_core="xray"
    elif [ -f "/usr/bin/xray" ]; then
        detected_core="xray"
    fi
    
    # 检查 sing-box
    if [ -z "$detected_core" ]; then
        if command -v sing-box &>/dev/null; then
            detected_core="sing-box"
        elif [ -f "/usr/local/bin/sing-box" ]; then
            detected_core="sing-box"
        elif [ -f "/usr/bin/sing-box" ]; then
            detected_core="sing-box"
        fi
    fi
    
    echo "$detected_core"
}

# 安装核心
_suoha_install_core() {
    local core_choice=$1
    
    if [ "$core_choice" = "1" ]; then
        _info "正在安装 Xray 核心..."
        local arch=$(uname -m)
        local xray_arch=""
        case $arch in
            x86_64|x64|amd64) xray_arch="linux-64" ;;
            i386|i686) xray_arch="linux-32" ;;
            armv8|arm64|aarch64) xray_arch="linux-arm64-v8a" ;;
            armv7l|armv7) xray_arch="linux-arm32-v7a" ;;
            *) _error "不支持的架构: $arch"; return 1 ;;
        esac
        
        if ! wget -q "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-$xray_arch.zip" -O /tmp/xray_install.zip; then
            _error "Xray 下载失败"
            return 1
        fi
        
        unzip -oq /tmp/xray_install.zip -d /tmp/xray_install
        if [ -f "/tmp/xray_install/xray" ]; then
            mv /tmp/xray_install/xray /usr/local/bin/xray
            chmod +x /usr/local/bin/xray
            rm -rf /tmp/xray_install /tmp/xray_install.zip
            _success "Xray 核心安装成功！"
            return 0
        else
            _error "Xray 安装失败"
            rm -rf /tmp/xray_install /tmp/xray_install.zip
            return 1
        fi
    else
        _info "正在安装 sing-box 核心..."
        local arch=$(uname -m)
        local core_arch=""
        case $arch in
            x86_64|x64|amd64) core_arch="amd64" ;;
            i386|i686) core_arch="386" ;;
            armv8|arm64|aarch64) core_arch="arm64" ;;
            armv7l|armv7) core_arch="armv7" ;;
            *) _error "不支持的架构: $arch"; return 1 ;;
        esac
        
        # 检测 libc 类型
        local libc_suffix=""
        if ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]; then
            libc_suffix="-musl"
        fi
        
        local singbox_filename="sing-box-$core_arch$libc_suffix"
        if ! wget -q "https://github.com/SagerNet/sing-box/releases/latest/download/$singbox_filename.tar.gz" -O /tmp/singbox_install.tar.gz; then
            _error "sing-box 下载失败"
            return 1
        fi
        
        tar -xzf /tmp/singbox_install.tar.gz -C /tmp
        local extracted_bin=$(find /tmp -name "sing-box" -type f 2>/dev/null | head -1)
        if [ -n "$extracted_bin" ]; then
            mv "$extracted_bin" /usr/local/bin/sing-box
            chmod +x /usr/local/bin/sing-box
            rm -rf /tmp/singbox_install.tar.gz
            _success "sing-box 核心安装成功！"
            return 0
        else
            _error "sing-box 安装失败"
            rm -f /tmp/singbox_install.tar.gz
            return 1
        fi
    fi
}

# 生成 sing-box 配置文件
_suoha_generate_singbox_config() {
    local protocol=$1
    local uuid=$2
    local urlpath=$3
    local port=$4
    
    if [ "$protocol" = "1" ]; then
        # VMess
        cat > config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "127.0.0.1",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "$urlpath"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound_tag": "vmess-in",
        "outbound_tag": "direct"
      }
    ]
  }
}
EOF
    else
        # VLESS
        cat > config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "$urlpath"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound_tag": "vless-in",
        "outbound_tag": "direct"
      }
    ]
  }
}
EOF
    fi
}

_suoha_quick_tunnel() {
    clear
    echo -e "${YELLOW}【梭哈模式】${NC}"
    echo ""
    
    # 自动检测已安装的核心
    local detected_core=$( _suoha_detect_core )
    
    if [ -n "$detected_core" ]; then
        echo -e "  检测到已安装的核心: ${GREEN}${detected_core}${NC}"
        echo ""
        read -p "  是否使用已安装的核心? [Y/n]: " use_detected
        [[ "$use_detected" != "n" && "$use_detected" != "N" ]] && core="$detected_core"
    fi
    
    # 如果没有使用检测到的核心，或者没有检测到核心，询问用户选择
    if [ "$core" != "xray" ] && [ "$core" != "sing-box" ]; then
        read -p "  请选择核心 [1] Xray / [2] sing-box（默认 1）: " core_choice
        [ -z "$core_choice" ] && core_choice=1
        [ "$core_choice" != "1" ] && [ "$core_choice" != "2" ] && { _error "请输入正确的核心"; return; }
        
        if [ "$core_choice" = "1" ]; then
            core="xray"
        else
            core="sing-box"
        fi
        
        # 检查选择的核心是否已安装
        local detected=$( _suoha_detect_core )
        if [ "$detected" != "$core" ]; then
            echo ""
            _warn "未检测到 $core，是否现在安装？"
            read -p "  [Y] 安装 / [N] 取消: " install_choice
            [[ "$install_choice" != "n" && "$install_choice" != "N" ]] || return
            _suoha_install_core "$core_choice" || return
        fi
    fi
    
    # 如果core变量是数字，转换为名称
    if [ "$core" = "1" ]; then
        core="xray"
    elif [ "$core" = "2" ]; then
        core="sing-box"
    fi
    
    read -p "  请选择协议 [1] VMess / [2] VLESS（默认 1）: " protocol
    [ -z "$protocol" ] && protocol=1
    [ "$protocol" != "1" ] && [ "$protocol" != "2" ] && { _error "请输入正确的协议"; return; }
    
    read -p "  请选择连接模式 [4] IPv4 / [6] IPv6（默认 4）: " ips
    [ -z "$ips" ] && ips=4
    [ "$ips" != "4" ] && [ "$ips" != "6" ] && { _error "请输入正确的连接模式"; return; }
    
    # 获取 ISP 信息
    local isp=""
    if command -v curl &>/dev/null; then
        isp=$(curl -s -$ips https://speed.cloudflare.com/meta | awk -F'"' '{print $26"-"$18"-"$30}' | sed 's/ /_/g')
    fi
    
    # 清理旧的进程
    _suoha_kill_processes
    
    # 创建临时目录
    local temp_dir=$(mktemp -d /tmp/suoha.XXXXXX)
    cd "$temp_dir" || { _error "无法创建临时目录"; return; }
    
    # 获取架构
    local arch=$(uname -m)
    local cf_arch="amd64"
    local core_arch="amd64"
    case $arch in
        x86_64|x64|amd64)
            cf_arch="amd64"
            core_arch="amd64"
            ;;
        i386|i686)
            cf_arch="386"
            core_arch="386"
            ;;
        armv8|arm64|aarch64)
            cf_arch="arm64"
            core_arch="arm64"
            ;;
        armv7l|armv7)
            cf_arch="arm"
            core_arch="armv7"
            ;;
        *)
            _error "不支持的架构: $arch"
            return
            ;;
    esac
    
    # 检测系统 libc 类型，用于 sing-box 下载
    local libc_suffix=""
    if ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]; then
        libc_suffix="-musl"
    fi
    
    _info "正在下载 Cloudflared..."
    if ! wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch" -O cloudflared; then
        _error "Cloudflared 下载失败"
        return
    fi
    chmod +x cloudflared
    
    # 检查是否使用已安装的核心
    if [ -f "/usr/local/bin/$core" ] || [ -f "/usr/bin/$core" ]; then
        _info "正在使用已安装的 $core..."
        if [ "$core" = "xray" ]; then
            cp /usr/local/bin/xray /usr/bin/xray 2>/dev/null || true
            cp "$(command -v xray 2>/dev/null || echo /usr/local/bin/xray)" ./
            chmod +x xray
        else
            cp /usr/local/bin/sing-box /usr/bin/sing-box 2>/dev/null || true
            cp "$(command -v sing-box 2>/dev/null || echo /usr/local/bin/sing-box)" ./
            chmod +x sing-box
        fi
    elif [ "$core" = "1" ] || [ "$core" = "xray" ]; then
        _info "正在下载 Xray..."
        local xray_arch=""
        case $arch in
            x86_64|x64|amd64) xray_arch="linux-64" ;;
            i386|i686) xray_arch="linux-32" ;;
            armv8|arm64|aarch64) xray_arch="linux-arm64-v8a" ;;
            armv7l|armv7) xray_arch="linux-arm32-v7a" ;;
        esac
        
        if ! wget -q "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-$xray_arch.zip" -O core.zip; then
            _error "Xray 下载失败"
            return
        fi
        unzip -q core.zip
        [ -f xray ] && chmod +x xray
    else
        _info "正在下载 sing-box..."
        local singbox_filename="sing-box-$core_arch$libc_suffix"
        if ! wget -q "https://github.com/SagerNet/sing-box/releases/latest/download/$singbox_filename.tar.gz" -O core.tar.gz; then
            _error "sing-box 下载失败"
            return
        fi
        tar -xzf core.tar.gz
        local extracted_bin=$(find . -name "sing-box" -type f 2>/dev/null | head -1)
        if [ -n "$extracted_bin" ]; then
            mv "$extracted_bin" sing-box
            chmod +x sing-box
        else
            _error "sing-box 提取失败"
            return
        fi
    fi
    
    # 生成配置
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    local urlpath=$(echo "$uuid" | cut -d'-' -f1)
    local port=$((RANDOM + 10000))
    
    if [ "$core" = "1" ]; then
        # Xray 配置
        cat > config.json <<EOF
{
  "inbounds": [
    {
      "port": $port,
      "listen": "127.0.0.1",
      "protocol": $( [ "$protocol" = "1" ] && echo '"vmess"' || echo '"vless"' ),
      "settings": {
        "clients": [
          {
            "id": "$uuid"
            $( [ "$protocol" = "1" ] && echo ',"alterId": 0' )
          }
        ]
        $( [ "$protocol" = "2" ] && echo ',"decryption": "none"' )
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$urlpath"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    else
        # sing-box 配置
        _suoha_generate_singbox_config "$protocol" "$uuid" "$urlpath" "$port"
    fi
    
    # 启动服务
    _info "正在启动服务..."
    if [ "$core" = "1" ]; then
        [ -f xray ] && ./xray run -config config.json >/dev/null 2>&1 &
    else
        [ -f sing-box ] && ./sing-box run -c config.json >/dev/null 2>&1 &
    fi
    sleep 1
    
    # 启动 Cloudflare Tunnel
    _info "正在连接 Cloudflare 隧道..."
    ./cloudflared tunnel --url "http://127.0.0.1:$port" --no-autoupdate --edge-ip-version "$ips" --protocol http2 > argo.log 2>&1 &
    sleep 2
    
    # 等待获取域名
    _info "正在获取隧道地址..."
    local argo=""
    local attempts=0
    while [ $attempts -lt 15 ] && [ -z "$argo" ]; do
        attempts=$((attempts + 1))
        argo=$(cat argo.log 2>/dev/null | grep 'trycloudflare.com' | awk 'NR==1{print}' | sed 's/.*http[s]*:\/\///' | awk '{print $1}')
        [ -z "$argo" ] && sleep 1
    done
    
    if [ -z "$argo" ]; then
        _error "获取隧道地址超时，请重试"
        return
    fi
    
    # 生成节点链接
    _success "隧道创建成功！"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}您的节点信息：${NC}"
    echo ""
    
    if [ "$protocol" = "1" ]; then
        # VMess 链接
        local vmess_tls=$(echo "{\"add\":\"www.visa.com.sg\",\"aid\":\"0\",\"host\":\"$argo\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$urlpath\",\"port\":\"443\",\"ps\":\"${isp}_tls\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)
        local vmess_plain=$(echo "{\"add\":\"www.visa.com.sg\",\"aid\":\"0\",\"host\":\"$argo\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$urlpath\",\"port\":\"80\",\"ps\":\"$isp\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)
        
        echo -e "  ${GREEN}VMess (TLS):${NC}"
        echo "  vmess://$vmess_tls"
        echo ""
        echo -e "  端口 443 可替换为: 2053, 2087, 2096, 8443"
        echo ""
        echo -e "  ${GREEN}VMess (无 TLS):${NC}"
        echo "  vmess://$vmess_plain"
        echo ""
        echo -e "  端口 80 可替换为: 8080, 8880, 2052, 2082, 2086, 2095"
    else
        # VLESS 链接
        local vless_tls="vless://$uuid@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host=$argo&path=$urlpath&sni=$argo#${isp}_tls"
        local vless_plain="vless://$uuid@www.visa.com.sg:80?encryption=none&security=none&type=ws&host=$argo&path=$urlpath#$isp"
        
        echo -e "  ${GREEN}VLESS (TLS):${NC}"
        echo "  $vless_tls"
        echo ""
        echo -e "  端口 443 可替换为: 2053, 2087, 2096, 8443"
        echo ""
        echo -e "  ${GREEN}VLESS (无 TLS):${NC}"
        echo "  $vless_plain"
        echo ""
        echo -e "  端口 80 可替换为: 8080, 8880, 2052, 2082, 2086, 2095"
    fi
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}【重要提示】${NC}"
    echo "  1. 将 'www.visa.com.sg' 替换为 Cloudflare 优选 IP"
    echo "  2. 确保客户端 Host (SNI) 设置为: $argo"
    echo "  3. 重启服务器或停止脚本后，此隧道会失效"
    echo ""
    
    # 保存信息到文件
    if [ "$protocol" = "1" ]; then
        cat > /root/v2ray.txt <<EOF
VMess 链接已经生成，www.visa.com.sg 可替换为 CF 优选 IP

vmess://$vmess_tls

端口 443 可改为 2053 2087 2096 8443

vmess://$vmess_plain

端口 80 可改为 8080 8880 2052 2082 2086 2095
EOF
    else
        cat > /root/v2ray.txt <<EOF
VLESS 链接已经生成，www.visa.com.sg 可替换为 CF 优选 IP

$vless_tls

端口 443 可改为 2053 2087 2096 8443

$vless_plain

端口 80 可改为 8080 8880 2052 2082 2086 2095
EOF
    fi
    
    _info "节点信息已保存到: /root/v2ray.txt"
    cd /
}

_suoha_kill_processes() {
    # 停止 Xray、sing-box 和 Cloudflared 进程
    if [ -f /etc/os-release ] && grep -qi "alpine" /etc/os-release; then
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "xray" | awk '{print $1}') >/dev/null 2>&1 || true
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "sing-box" | awk '{print $1}') >/dev/null 2>&1 || true
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "cloudflared" | awk '{print $1}') >/dev/null 2>&1 || true
    else
        if command -v systemctl &>/dev/null; then
            systemctl stop cloudflared >/dev/null 2>&1 || true
            systemctl stop xray >/dev/null 2>&1 || true
            systemctl stop singbox-suoha >/dev/null 2>&1 || true
        fi
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "xray" | awk '{print $2}') >/dev/null 2>&1 || true
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "sing-box" | awk '{print $2}') >/dev/null 2>&1 || true
        kill -9 $(ps w 2>/dev/null | grep -v "grep" | grep "cloudflared" | awk '{print $2}') >/dev/null 2>&1 || true
    fi
}

_suoha_install_service() {
    # 检查是否已安装
    if [ -f "/usr/bin/suoha" ] || [ -f "/opt/suoha/suoha.sh" ]; then
        _warn "服务可能已安装，正在跳转管理菜单..."
        sleep 1
        _suoha_manage_service
        return
    fi
    
    clear
    echo -e "${YELLOW}【安装服务模式】${NC}"
    echo ""
    
    # 自动检测已安装的核心
    local detected_core=$( _suoha_detect_core )
    local core=""
    
    if [ -n "$detected_core" ]; then
        echo -e "  检测到已安装的核心: ${GREEN}${detected_core}${NC}"
        echo ""
        read -p "  是否使用已安装的核心? [Y/n]: " use_detected
        [[ "$use_detected" != "n" && "$use_detected" != "N" ]] && core="$detected_core"
    fi
    
    # 如果没有使用检测到的核心，或者没有检测到核心，询问用户选择
    if [ -z "$core" ]; then
        read -p "  请选择核心 [1] Xray / [2] sing-box（默认 1）: " core_choice
        [ -z "$core_choice" ] && core_choice=1
        [ "$core_choice" != "1" ] && [ "$core_choice" != "2" ] && { _error "请输入正确的核心"; return; }
        
        if [ "$core_choice" = "1" ]; then
            core="xray"
        else
            core="sing-box"
        fi
        
        # 检查选择的核心是否已安装
        if ! _suoha_detect_core | grep -q "$core"; then
            echo ""
            _warn "未检测到 $core，是否现在安装？"
            read -p "  [Y] 安装 / [N] 取消: " install_choice
            [[ "$install_choice" != "n" && "$install_choice" != "N" ]] || return
            _suoha_install_core "$core_choice" || return
        fi
    fi
    
    # 如果core变量是数字，转换为名称
    if [ "$core" = "1" ]; then
        core="xray"
    elif [ "$core" = "2" ]; then
        core="sing-box"
    fi
    
    read -p "  请选择协议 [1] VMess / [2] VLESS（默认 1）: " protocol
    [ -z "$protocol" ] && protocol=1
    [ "$protocol" != "1" ] && [ "$protocol" != "2" ] && { _error "请输入正确的协议"; return; }
    
    read -p "  请选择连接模式 [4] IPv4 / [6] IPv6（默认 4）: " ips
    [ -z "$ips" ] && ips=4
    [ "$ips" != "4" ] && [ "$ips" != "6" ] && { _error "请输入正确的连接模式"; return; }
    
    # 获取 ISP 信息
    local isp=""
    if command -v curl &>/dev/null; then
        isp=$(curl -s -$ips https://speed.cloudflare.com/meta | awk -F'"' '{print $26"-"$18"-"$30}' | sed 's/ /_/g')
    fi
    
    # 停止旧进程和服务
    _suoha_kill_processes
    rm -rf /opt/suoha
    
    # 检查系统类型
    local is_alpine=false
    if [ -f /etc/os-release ] && grep -qi "alpine" /etc/os-release; then
        is_alpine=true
    fi
    
    # 创建目录
    mkdir -p /opt/suoha
    cd /opt/suoha || { _error "无法创建目录"; return; }
    
    # 获取架构
    local arch=$(uname -m)
    local cf_arch="amd64"
    local core_arch="amd64"
    case $arch in
        x86_64|x64|amd64)
            cf_arch="amd64"
            core_arch="amd64"
            ;;
        i386|i686)
            cf_arch="386"
            core_arch="386"
            ;;
        armv8|arm64|aarch64)
            cf_arch="arm64"
            core_arch="arm64"
            ;;
        armv7l|armv7)
            cf_arch="arm"
            core_arch="armv7"
            ;;
        *)
            _error "不支持的架构: $arch"
            return
            ;;
    esac
    
    # 检测系统 libc 类型，用于 sing-box 下载
    local libc_suffix=""
    if ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]; then
        libc_suffix="-musl"
    fi
    
    # 下载文件
    _info "正在下载 Cloudflared..."
    if ! wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch" -O cloudflared-linux; then
        _error "Cloudflared 下载失败"
        return
    fi
    chmod +x cloudflared-linux
    
    if [ "$core" = "1" ]; then
        _info "正在下载 Xray..."
        local xray_arch=""
        case $arch in
            x86_64|x64|amd64) xray_arch="linux-64" ;;
            i386|i686) xray_arch="linux-32" ;;
            armv8|arm64|aarch64) xray_arch="linux-arm64-v8a" ;;
            armv7l|armv7) xray_arch="linux-arm32-v7a" ;;
        esac
        
        if ! wget -q "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-$xray_arch.zip" -O core.zip; then
            _error "Xray 下载失败"
            return
        fi
        unzip -q core.zip
        [ -f xray ] && chmod +x xray
    else
        _info "正在下载 sing-box..."
        local singbox_filename="sing-box-$core_arch$libc_suffix"
        if ! wget -q "https://github.com/SagerNet/sing-box/releases/latest/download/$singbox_filename.tar.gz" -O core.tar.gz; then
            _error "sing-box 下载失败"
            return
        fi
        tar -xzf core.tar.gz
        local extracted_bin=$(find . -name "sing-box" -type f 2>/dev/null | head -1)
        if [ -n "$extracted_bin" ]; then
            mv "$extracted_bin" sing-box
            chmod +x sing-box
        else
            _error "sing-box 提取失败"
            return
        fi
    fi
    
    # 生成 UUID 和配置
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    local urlpath=$(echo "$uuid" | cut -d'-' -f1)
    local port=$((RANDOM + 10000))
    
    if [ "$core" = "1" ]; then
        # Xray 配置
        cat > config.json <<EOF
{
  "inbounds": [
    {
      "port": $port,
      "listen": "127.0.0.1",
      "protocol": $( [ "$protocol" = "1" ] && echo '"vmess"' || echo '"vless"' ),
      "settings": {
        "clients": [
          {
            "id": "$uuid"
            $( [ "$protocol" = "1" ] && echo ',"alterId": 0' )
          }
        ]
        $( [ "$protocol" = "2" ] && echo ',"decryption": "none"' )
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$urlpath"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    else
        # sing-box 配置
        _suoha_generate_singbox_config "$protocol" "$uuid" "$urlpath" "$port"
    fi
    
    # 启动 Cloudflare Tunnel 进行授权
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  请复制以下链接，用浏览器打开并授权需要绑定的域名"
    echo -e "  在网页中授权完成后按任意键继续"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel login
    echo ""
    read -n 1 -s -r -p "授权完成后按任意键继续..."
    
    # 获取当前已有的隧道
    ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel list > argo.log 2>&1
    echo ""
    echo -e "当前已绑定的隧道（如果有）:"
    sed 1,2d argo.log 2>/dev/null | awk '{print $2}' || echo "无"
    echo ""
    
    read -p "请输入要绑定的完整域名: " domain
    [ -z "$domain" ] && { _error "域名不能为空"; return; }
    [ -z "$(echo "$domain" | grep '\.')" ] && { _error "域名格式不正确"; return; }
    
    local name=$(echo "$domain" | cut -d'.' -f1)
    
    # 检查是否已存在
    local tunnel_exists=false
    if sed 1,2d argo.log 2>/dev/null | grep -q "^$name\$"; then
        tunnel_exists=true
    fi
    
    if [ "$tunnel_exists" = false ]; then
        _info "正在创建隧道: $name"
        ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel create "$name" > argo.log 2>&1
    else
        _info "隧道 $name 已存在，清理旧配置"
        ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel cleanup "$name" >/dev/null 2>&1
    fi
    
    # 绑定域名
    _info "正在绑定域名: $domain"
    ./cloudflared-linux --edge-ip-version "$ips" --protocol http2 tunnel route dns --overwrite-dns "$name" "$domain" > argo.log 2>&1
    
    local tunnel_uuid=$(grep -E 'Created tunnel|created tunnel' argo.log 2>/dev/null | sed 's/.*id //' | head -1 || grep -E '^[a-f0-9-]{36}$' argo.log 2>/dev/null | head -1)
    [ -z "$tunnel_uuid" ] && tunnel_uuid=$(cat ~/.cloudflared/*.json 2>/dev/null | grep -Eo '"ID":"[a-f0-9-]+"' | cut -d'"' -f4 | head -1)
    
    # 创建配置文件
    cat > config.yaml <<EOF
tunnel: $tunnel_uuid
credentials-file: /root/.cloudflared/$tunnel_uuid.json

ingress:
  - hostname: $domain
    service: http://127.0.0.1:$port
  - service: http_status:404
EOF
    
    # 生成节点信息
    echo ""
    _success "隧道创建成功！"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}您的节点信息：${NC}"
    echo ""
    
    if [ "$protocol" = "1" ]; then
        local vmess_tls=$(echo "{\"add\":\"www.visa.com.sg\",\"aid\":\"0\",\"host\":\"$domain\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$urlpath\",\"port\":\"443\",\"ps\":\"$isp\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)
        local vmess_plain=$(echo "{\"add\":\"www.visa.com.sg\",\"aid\":\"0\",\"host\":\"$domain\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$urlpath\",\"port\":\"80\",\"ps\":\"$isp\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)
        
        echo -e "  ${GREEN}VMess (TLS):${NC}"
        echo "  vmess://$vmess_tls"
        echo ""
        echo -e "  端口 443 可替换为: 2053, 2087, 2096, 8443"
        echo ""
        echo -e "  ${GREEN}VMess (无 TLS):${NC}"
        echo "  vmess://$vmess_plain"
        echo ""
        echo -e "  端口 80 可替换为: 8080, 8880, 2052, 2082, 2086, 2095"
        echo ""
        
        cat > /opt/suoha/v2ray.txt <<EOF
VMess 链接已经生成，www.visa.com.sg 可替换为 CF 优选 IP

vmess://$vmess_tls

端口 443 可改为 2053 2087 2096 8443

vmess://$vmess_plain

端口 80 可改为 8080 8880 2052 2082 2086 2095

注意：如果 80/8080/8880/2052/2082/2086/2095 端口无法正常使用
请前往 https://dash.cloudflare.com/
检查管理面板 SSL/TLS -> 边缘证书 -> 始终使用 HTTPS 是否处于关闭状态
EOF
    else
        local vless_tls="vless://$uuid@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host=$domain&path=$urlpath&sni=$domain#${isp}_tls"
        local vless_plain="vless://$uuid@www.visa.com.sg:80?encryption=none&security=none&type=ws&host=$domain&path=$urlpath&sni=$domain#$isp"
        
        echo -e "  ${GREEN}VLESS (TLS):${NC}"
        echo "  $vless_tls"
        echo ""
        echo -e "  端口 443 可替换为: 2053, 2087, 2096, 8443"
        echo ""
        echo -e "  ${GREEN}VLESS (无 TLS):${NC}"
        echo "  $vless_plain"
        echo ""
        echo -e "  端口 80 可替换为: 8080, 8880, 2052, 2082, 2086, 2095"
        echo ""
        
        cat > /opt/suoha/v2ray.txt <<EOF
VLESS 链接已经生成，www.visa.com.sg 可替换为 CF 优选 IP

$vless_tls

端口 443 可改为 2053 2087 2096 8443

$vless_plain

端口 80 可改为 8080 8880 2052 2082 2086 2095

注意：如果 80/8080/8880/2052/2082/2086/2095 端口无法正常使用
请前往 https://dash.cloudflare.com/
检查管理面板 SSL/TLS -> 边缘证书 -> 始终使用 HTTPS 是否处于关闭状态
EOF
    fi
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}【重要提示】${NC}"
    echo "  1. 将 'www.visa.com.sg' 替换为 Cloudflare 优选 IP"
    echo "  2. 确保客户端 Host (SNI) 设置为: $domain"
    echo "  3. 节点信息已保存到: /opt/suoha/v2ray.txt"
    echo ""
    
    # 保存核心类型到文件，供管理脚本使用
    echo "$core" > /opt/suoha/core_type
    
    # 创建服务
    if [ "$is_alpine" = true ]; then
        # Alpine OpenRC 服务
        cat > /etc/local.d/cloudflared.start <<EOF
#!/bin/sh
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/suoha/config.yaml run $name >/dev/null 2>&1 &
EOF
        chmod +x /etc/local.d/cloudflared.start
        
        if [ "$core" = "1" ]; then
            cat > /etc/local.d/xray.start <<EOF
#!/bin/sh
/opt/suoha/xray run -config /opt/suoha/config.json >/dev/null 2>&1 &
EOF
            chmod +x /etc/local.d/xray.start
        else
            cat > /etc/local.d/singbox.start <<EOF
#!/bin/sh
/opt/suoha/sing-box run -c /opt/suoha/config.json >/dev/null 2>&1 &
EOF
            chmod +x /etc/local.d/singbox.start
        fi
        
        rc-update add local default >/dev/null 2>&1
        /etc/local.d/cloudflared.start
        if [ "$core" = "1" ]; then
            /etc/local.d/xray.start
        else
            /etc/local.d/singbox.start
        fi
    else
        # Systemd 服务
        cat > /lib/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/suoha/config.yaml run $name
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        
        if [ "$core" = "1" ]; then
            cat > /lib/systemd/system/xray.service <<EOF
[Unit]
Description=Xray
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/suoha/xray run -config /opt/suoha/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        else
            cat > /lib/systemd/system/singbox-suoha.service <<EOF
[Unit]
Description=Sing-box (Suoha)
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/suoha/sing-box run -c /opt/suoha/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        fi
        
        systemctl enable cloudflared.service >/dev/null 2>&1
        if [ "$core" = "1" ]; then
            systemctl enable xray.service >/dev/null 2>&1
        else
            systemctl enable singbox-suoha.service >/dev/null 2>&1
        fi
        systemctl daemon-reload
        systemctl start cloudflared.service
        if [ "$core" = "1" ]; then
            systemctl start xray.service
        else
            systemctl start singbox-suoha.service
        fi
    fi
    
    # 创建管理脚本
    _suoha_create_manager_script "$is_alpine" "$ips" "$name" "$core"
    
    ln -sf /opt/suoha/suoha.sh /usr/bin/suoha
    _success "服务安装完成！管理命令: suoha"
}

_suoha_create_manager_script() {
    local is_alpine=$1
    local ips=$2
    local name=$3
    local core=$4
    
    if [ "$is_alpine" = true ]; then
        if [ "$core" = "1" ]; then
            cat > /opt/suoha/suoha.sh <<'EOF'
#!/bin/sh
while true; do
    clear
    if ps w | grep -v grep | grep -q cloudflared; then
        argo_status="${GREEN}● 运行中${NC}"
    else
        argo_status="${RED}● 已停止${NC}"
    fi
    
    if ps w | grep -v grep | grep -q /opt/suoha/xray; then
        xray_status="${GREEN}● 运行中${NC}"
    else
        xray_status="${RED}● 已停止${NC}"
    fi
    
    echo " Cloudflare: $argo_status"
    echo " Xray: $xray_status"
    echo ""
    echo "  [1] 管理隧道"
    echo "  [2] 启动服务"
    echo "  [3] 停止服务"
    echo "  [4] 重启服务"
    echo "  [5] 卸载服务"
    echo "  [6] 查看节点信息"
    echo "  [0] 退出"
    echo ""
    
    read -p "请选择菜单（默认 0）: " menu
    [ -z "$menu" ] && menu=0
    
    case $menu in
        1)
            clear
            while true; do
                echo "当前已绑定的隧道："
                /opt/suoha/cloudflared-linux tunnel list
                echo ""
                echo "  [1] 删除隧道"
                echo "  [0] 返回"
                read -p "请选择（默认 0）: " tunneladmin
                [ -z "$tunneladmin" ] && tunneladmin=0
                if [ "$tunneladmin" = "1" ]; then
                    read -p "请输入要删除的隧道名称: " tunnelname
                    [ -n "$tunnelname" ] && {
                        /opt/suoha/cloudflared-linux tunnel cleanup "$tunnelname"
                        /opt/suoha/cloudflared-linux tunnel delete "$tunnelname"
                    }
                else
                    break
                fi
            done
            ;;
        2)
            /etc/local.d/cloudflared.start
            /etc/local.d/xray.start
            clear
            sleep 1
            ;;
        3)
            kill -9 $(ps w | grep /opt/suoha/xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            clear
            sleep 2
            ;;
        4)
            kill -9 $(ps w | grep /opt/suoha/xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            /etc/local.d/cloudflared.start
            /etc/local.d/xray.start
            clear
            sleep 1
            ;;
        5)
            kill -9 $(ps w | grep /opt/suoha/xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            rm -rf /opt/suoha /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/suoha
            echo "所有服务都卸载完成"
            echo "彻底删除授权记录"
            echo "请访问 https://dash.cloudflare.com/profile/api-tokens"
            echo "删除授权的 Cloudflare Tunnel API Token 即可"
            exit 0
            ;;
        6)
            clear
            [ -f /opt/suoha/v2ray.txt ] && cat /opt/suoha/v2ray.txt
            ;;
        0)
            echo "退出成功"
            exit 0
            ;;
    esac
done
EOF
        else
            cat > /opt/suoha/suoha.sh <<'EOF'
#!/bin/sh
while true; do
    clear
    if ps w | grep -v grep | grep -q cloudflared; then
        argo_status="${GREEN}● 运行中${NC}"
    else
        argo_status="${RED}● 已停止${NC}"
    fi
    
    if ps w | grep -v grep | grep -q /opt/suoha/sing-box; then
        singbox_status="${GREEN}● 运行中${NC}"
    else
        singbox_status="${RED}● 已停止${NC}"
    fi
    
    echo " Cloudflare: $argo_status"
    echo " Sing-box: $singbox_status"
    echo ""
    echo "  [1] 管理隧道"
    echo "  [2] 启动服务"
    echo "  [3] 停止服务"
    echo "  [4] 重启服务"
    echo "  [5] 卸载服务"
    echo "  [6] 查看节点信息"
    echo "  [0] 退出"
    echo ""
    
    read -p "请选择菜单（默认 0）: " menu
    [ -z "$menu" ] && menu=0
    
    case $menu in
        1)
            clear
            while true; do
                echo "当前已绑定的隧道："
                /opt/suoha/cloudflared-linux tunnel list
                echo ""
                echo "  [1] 删除隧道"
                echo "  [0] 返回"
                read -p "请选择（默认 0）: " tunneladmin
                [ -z "$tunneladmin" ] && tunneladmin=0
                if [ "$tunneladmin" = "1" ]; then
                    read -p "请输入要删除的隧道名称: " tunnelname
                    [ -n "$tunnelname" ] && {
                        /opt/suoha/cloudflared-linux tunnel cleanup "$tunnelname"
                        /opt/suoha/cloudflared-linux tunnel delete "$tunnelname"
                    }
                else
                    break
                fi
            done
            ;;
        2)
            /etc/local.d/cloudflared.start
            /etc/local.d/singbox.start
            clear
            sleep 1
            ;;
        3)
            kill -9 $(ps w | grep /opt/suoha/sing-box | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            clear
            sleep 2
            ;;
        4)
            kill -9 $(ps w | grep /opt/suoha/sing-box | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            /etc/local.d/cloudflared.start
            /etc/local.d/singbox.start
            clear
            sleep 1
            ;;
        5)
            kill -9 $(ps w | grep /opt/suoha/sing-box | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
            rm -rf /opt/suoha /etc/local.d/cloudflared.start /etc/local.d/singbox.start /usr/bin/suoha
            echo "所有服务都卸载完成"
            echo "彻底删除授权记录"
            echo "请访问 https://dash.cloudflare.com/profile/api-tokens"
            echo "删除授权的 Cloudflare Tunnel API Token 即可"
            exit 0
            ;;
        6)
            clear
            [ -f /opt/suoha/v2ray.txt ] && cat /opt/suoha/v2ray.txt
            ;;
        0)
            echo "退出成功"
            exit 0
            ;;
    esac
done
EOF
        fi
    else
        if [ "$core" = "1" ]; then
            cat > /opt/suoha/suoha.sh <<'EOF'
#!/bin/bash
while true; do
    clear
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        argo_status="${GREEN}● 运行中${NC}"
    else
        argo_status="${RED}● 已停止${NC}"
    fi
    
    if systemctl is-active --quiet xray 2>/dev/null; then
        xray_status="${GREEN}● 运行中${NC}"
    else
        xray_status="${RED}● 已停止${NC}"
    fi
    
    echo " Cloudflare: $argo_status"
    echo " Xray: $xray_status"
    echo ""
    echo "  [1] 管理隧道"
    echo "  [2] 启动服务"
    echo "  [3] 停止服务"
    echo "  [4] 重启服务"
    echo "  [5] 卸载服务"
    echo "  [6] 查看节点信息"
    echo "  [0] 退出"
    echo ""
    
    read -p "请选择菜单（默认 0）: " menu
    [ -z "$menu" ] && menu=0
    
    case $menu in
        1)
            clear
            while true; do
                echo "当前已绑定的隧道："
                /opt/suoha/cloudflared-linux tunnel list
                echo ""
                echo "  [1] 删除隧道"
                echo "  [0] 返回"
                read -p "请选择（默认 0）: " tunneladmin
                [ -z "$tunneladmin" ] && tunneladmin=0
                if [ "$tunneladmin" = "1" ]; then
                    read -p "请输入要删除的隧道名称: " tunnelname
                    [ -n "$tunnelname" ] && {
                        /opt/suoha/cloudflared-linux tunnel cleanup "$tunnelname"
                        /opt/suoha/cloudflared-linux tunnel delete "$tunnelname"
                    }
                else
                    break
                fi
            done
            ;;
        2)
            systemctl start cloudflared
            systemctl start xray
            clear
            ;;
        3)
            systemctl stop cloudflared
            systemctl stop xray
            clear
            ;;
        4)
            systemctl restart cloudflared
            systemctl restart xray
            clear
            ;;
        5)
            systemctl stop cloudflared
            systemctl stop xray
            systemctl disable cloudflared >/dev/null 2>&1
            systemctl disable xray >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            kill -9 $(ps w | grep /opt/suoha/xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
            systemctl daemon-reload
            echo "所有服务都卸载完成"
            echo "彻底删除授权记录"
            echo "请访问 https://dash.cloudflare.com/profile/api-tokens"
            echo "删除授权的 Cloudflare Tunnel API Token 即可"
            exit 0
            ;;
        6)
            clear
            [ -f /opt/suoha/v2ray.txt ] && cat /opt/suoha/v2ray.txt
            ;;
        0)
            echo "退出成功"
            exit 0
            ;;
    esac
done
EOF
        else
            cat > /opt/suoha/suoha.sh <<'EOF'
#!/bin/bash
while true; do
    clear
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        argo_status="${GREEN}● 运行中${NC}"
    else
        argo_status="${RED}● 已停止${NC}"
    fi
    
    if systemctl is-active --quiet singbox-suoha 2>/dev/null; then
        singbox_status="${GREEN}● 运行中${NC}"
    else
        singbox_status="${RED}● 已停止${NC}"
    fi
    
    echo " Cloudflare: $argo_status"
    echo " Sing-box: $singbox_status"
    echo ""
    echo "  [1] 管理隧道"
    echo "  [2] 启动服务"
    echo "  [3] 停止服务"
    echo "  [4] 重启服务"
    echo "  [5] 卸载服务"
    echo "  [6] 查看节点信息"
    echo "  [0] 退出"
    echo ""
    
    read -p "请选择菜单（默认 0）: " menu
    [ -z "$menu" ] && menu=0
    
    case $menu in
        1)
            clear
            while true; do
                echo "当前已绑定的隧道："
                /opt/suoha/cloudflared-linux tunnel list
                echo ""
                echo "  [1] 删除隧道"
                echo "  [0] 返回"
                read -p "请选择（默认 0）: " tunneladmin
                [ -z "$tunneladmin" ] && tunneladmin=0
                if [ "$tunneladmin" = "1" ]; then
                    read -p "请输入要删除的隧道名称: " tunnelname
                    [ -n "$tunnelname" ] && {
                        /opt/suoha/cloudflared-linux tunnel cleanup "$tunnelname"
                        /opt/suoha/cloudflared-linux tunnel delete "$tunnelname"
                    }
                else
                    break
                fi
            done
            ;;
        2)
            systemctl start cloudflared
            systemctl start singbox-suoha
            clear
            ;;
        3)
            systemctl stop cloudflared
            systemctl stop singbox-suoha
            clear
            ;;
        4)
            systemctl restart cloudflared
            systemctl restart singbox-suoha
            clear
            ;;
        5)
            systemctl stop cloudflared
            systemctl stop singbox-suoha
            systemctl disable cloudflared >/dev/null 2>&1
            systemctl disable singbox-suoha >/dev/null 2>&1
            kill -9 $(ps w | grep cloudflared | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            kill -9 $(ps w | grep /opt/suoha/sing-box | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/singbox-suoha.service /usr/bin/suoha
            systemctl daemon-reload
            echo "所有服务都卸载完成"
            echo "彻底删除授权记录"
            echo "请访问 https://dash.cloudflare.com/profile/api-tokens"
            echo "删除授权的 Cloudflare Tunnel API Token 即可"
            exit 0
            ;;
        6)
            clear
            [ -f /opt/suoha/v2ray.txt ] && cat /opt/suoha/v2ray.txt
            ;;
        0)
            echo "退出成功"
            exit 0
            ;;
    esac
done
EOF
        fi
    fi
    
    chmod +x /opt/suoha/suoha.sh
}

_suoha_manage_service() {
    if [ -f "/usr/bin/suoha" ] && [ -x "/usr/bin/suoha" ]; then
        /usr/bin/suoha
    elif [ -f "/opt/suoha/suoha.sh" ] && [ -x "/opt/suoha/suoha.sh" ]; then
        /opt/suoha/suoha.sh
    else
        _warn "服务未安装，请先安装服务（选择模式 2）"
    fi
}

_suoha_uninstall_service() {
    clear
    echo -e "${RED}【卸载服务】${NC}"
    echo ""
    read -p "确定要卸载 Suoha 服务吗？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    _suoha_kill_processes
    
    if command -v systemctl &>/dev/null; then
        systemctl stop cloudflared >/dev/null 2>&1 || true
        systemctl stop xray >/dev/null 2>&1 || true
        systemctl stop singbox-suoha >/dev/null 2>&1 || true
        systemctl disable cloudflared >/dev/null 2>&1 || true
        systemctl disable xray >/dev/null 2>&1 || true
        systemctl disable singbox-suoha >/dev/null 2>&1 || true
        rm -f /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /lib/systemd/system/singbox-suoha.service >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
    fi
    
    rm -f /etc/local.d/cloudflared.start /etc/local.d/xray.start /etc/local.d/singbox.start >/dev/null 2>&1
    rm -f /usr/bin/suoha >/dev/null 2>&1
    rm -rf /opt/suoha >/dev/null 2>&1
    rm -f /root/v2ray.txt >/dev/null 2>&1
    
    _success "服务卸载完成！"
    echo ""
    echo "如需彻底删除授权记录，请访问："
    echo "https://dash.cloudflare.com/profile/api-tokens"
    echo "删除授权的 Cloudflare Tunnel API Token"
}

_suoha_clear_cache() {
    clear
    echo -e "${YELLOW}【清空缓存】${NC}"
    echo ""
    read -p "确定要清空临时文件和缓存吗？(y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    _info "正在清理临时文件..."
    rm -f /root/v2ray.txt >/dev/null 2>&1
    rm -rf /tmp/suoha.* >/dev/null 2>&1
    rm -rf xray cloudflared xray.zip argo.log 2>/dev/null
    
    _success "缓存已清空！"
}

# ==================== 主程序 ====================

    _main_menu
}

main
