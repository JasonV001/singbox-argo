#!/bin/bash
# ============================================================
# xray_manager.sh 鈥?Xray-core 鑺傜偣绠＄悊瀛愯剼鏈?# 涓?singbox.sh 鍏卞瓨锛屽叡浜?clash.yaml
# ============================================================
XRAY_SCRIPT_VERSION="3.0.0"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# --- 璺緞瀹氫箟 ---
XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_DIR}/config.json"
XRAY_METADATA="${XRAY_DIR}/metadata.json"

# 鍏变韩璺緞 (缁ф壙鑷?singbox.sh 鎴栦娇鐢ㄩ粯璁ゅ€?
SINGBOX_DIR="${SINGBOX_DIR:-/usr/local/etc/sing-box}"
CLASH_YAML_FILE="${CLASH_YAML_FILE:-${SINGBOX_DIR}/clash.yaml}"
YQ_BINARY="${YQ_BINARY:-/usr/local/bin/yq}"

# --- 棰滆壊瀹氫箟 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 鎵撳嵃鍑芥暟 (濡傛湭浠庣埗杩涚▼缁ф壙鍒欏畾涔夋湰鍦扮増鏈? ---
if ! declare -f _info >/dev/null 2>&1; then
    _info()    { echo -e "${CYAN}[淇℃伅] $1${NC}" >&2; }
    _error()   { echo -e "${RED}[閿欒] $1${NC}" >&2; }
    _success() { echo -e "${GREEN}[鎴愬姛] $1${NC}" >&2; }
    _warn()    { echo -e "${YELLOW}[娉ㄦ剰] $1${NC}" >&2; }
    _warning() { _warn "$1"; }
fi

# --- URL 缂栫爜 ---
if ! declare -f _url_encode >/dev/null 2>&1; then
    _url_encode() {
        printf '%s' "$1" | jq -sRr @uri
    }
fi

if ! declare -f _release_install_cache >/dev/null 2>&1; then
    _release_install_cache() {
        sync 2>/dev/null || true
        if [ -w /proc/sys/vm/drop_caches ]; then
            if { echo 1 > /proc/sys/vm/drop_caches; } 2>/dev/null; then
                _info "宸插皾璇曢噴鏀惧畨瑁呬骇鐢熺殑鏂囦欢缂撳瓨銆?
            fi
        fi
        return 0
    }
fi

if ! declare -f _ss_base64_encode >/dev/null 2>&1; then
    _ss_base64_encode() {
        # SS 鏍囧噯 Base64 (鏃?Padding)
        printf '%s' "$1" | base64 | tr -d '\n\r ' | sed 's/=//g'
    }
fi
# --- 鐜妫€娴?---
if ! declare -f _detect_init_system >/dev/null 2>&1; then
    _detect_init_system() {
        if [ -f /sbin/openrc-run ] || command -v rc-service >/dev/null; then
            INIT_SYSTEM="openrc"
        elif command -v systemctl >/dev/null; then
            INIT_SYSTEM="systemd"
        else
            INIT_SYSTEM="unknown"
        fi
    }
fi
[ -z "$INIT_SYSTEM" ] && _detect_init_system

# --- 鍖呯鐞?---
if ! declare -f _pkg_install >/dev/null 2>&1; then
    _pkg_install() {
        local pkgs="$*"
        [ -z "$pkgs" ] && return 0
        if command -v apk >/dev/null; then
            apk add --no-cache $pkgs >/dev/null 2>&1
        elif command -v apt-get >/dev/null; then
            if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls -A /var/lib/apt/lists/ 2>/dev/null | wc -l)" -le 1 ]; then
                apt-get update -qq >/dev/null 2>&1
            fi
            DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs >/dev/null 2>&1 || {
                apt-get update -qq >/dev/null 2>&1
                DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs >/dev/null 2>&1
            }
        elif command -v yum >/dev/null; then yum install -y $pkgs >/dev/null 2>&1
        elif command -v dnf >/dev/null; then dnf install -y $pkgs >/dev/null 2>&1
        fi
    }
fi

# --- 鍘熷瓙 JSON 淇敼 ---
if ! declare -f _atomic_modify_json >/dev/null 2>&1; then
    _atomic_modify_json() {
        local file="$1" filter="$2"
        [ ! -f "$file" ] && return 1
        local tmp="${file}.tmp"
        if jq "$filter" "$file" > "$tmp"; then mv "$tmp" "$file"
        else _error "淇敼JSON澶辫触: $file"; rm -f "$tmp"; return 1; fi
    }
fi

# --- 鍘熷瓙 YAML 淇敼 ---
if ! declare -f _atomic_modify_yaml >/dev/null 2>&1; then
    _atomic_modify_yaml() {
        local file="$1" filter="$2"
        [ ! -f "$file" ] && return 1
        cp "$file" "${file}.tmp"
        if ${YQ_BINARY} eval "$filter" -i "$file" 2>/dev/null; then rm "${file}.tmp"
        else _error "淇敼YAML澶辫触: $file"; mv "${file}.tmp" "$file"; return 1; fi
    }
fi

# --- Clash YAML 鑺傜偣鎿嶄綔 ---
if ! declare -f _add_node_to_yaml >/dev/null 2>&1; then
    _add_node_to_yaml() {
        local proxy_json="$1"
        local name=$(echo "$proxy_json" | jq -r '.name')
        local yaml_entry=$(echo "$proxy_json" | ${YQ_BINARY} -P '.')
        echo "$yaml_entry" | ${YQ_BINARY} eval -i ".proxies += [load(\"/dev/stdin\")]" "$CLASH_YAML_FILE" 2>/dev/null || \
        ${YQ_BINARY} eval -i ".proxies += [$(echo "$proxy_json" | ${YQ_BINARY} -P '.')]" "$CLASH_YAML_FILE" 2>/dev/null
        export NODE_NAME="$name"
        _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxy-groups[] | select(.name == "鑺傜偣閫夋嫨") | .proxies) += [env(NODE_NAME)]'
    }
fi

if ! declare -f _remove_node_from_yaml >/dev/null 2>&1; then
    _remove_node_from_yaml() {
        local name="$1"
        export DEL_NAME="$name"
        _atomic_modify_yaml "$CLASH_YAML_FILE" 'del(.proxies[] | select(.name == env(DEL_NAME)))'
        _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxy-groups[].proxies) -= [env(DEL_NAME)]'
    }
fi

if ! declare -f _find_proxy_name >/dev/null 2>&1; then
    _find_proxy_name() {
        local port="$1" type="$2"
        ${YQ_BINARY} eval ".proxies[] | select(.port == ${port}) | .name" "$CLASH_YAML_FILE" 2>/dev/null | head -1
    }
fi

# --- 绔彛鍐茬獊妫€娴?(璺ㄥ弻鏍稿績) ---
_check_port_occupied() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
        ss -ulnp 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    fi
    return 1
}

_check_xray_port_conflict() {
    local port="$1" protocol="${2:-tcp}"
    # 妫€鏌ョ郴缁熺鍙?    if _check_port_occupied "$port"; then
        _error "绔彛 $port 宸茶绯荤粺鍗犵敤锛?
        return 0
    fi
    # 妫€鏌?Xray 閰嶇疆
    if [ -f "$XRAY_CONFIG" ] && jq -e ".inbounds[] | select(.port == $port)" "$XRAY_CONFIG" >/dev/null 2>&1; then
        _error "绔彛 $port 宸茶 Xray 鑺傜偣浣跨敤锛?
        return 0
    fi
    # 妫€鏌?sing-box 閰嶇疆
    local sb_config="${SINGBOX_DIR}/config.json"
    if [ -f "$sb_config" ] && jq -e ".inbounds[] | select(.listen_port == $port)" "$sb_config" >/dev/null 2>&1; then
        _error "绔彛 $port 宸茶 sing-box 鑺傜偣浣跨敤锛?
        return 0
    fi
    return 1
}

# --- 鍏綉 IP 鑾峰彇 ---
if ! declare -f _get_public_ip >/dev/null 2>&1; then
    _get_public_ip() {
        [ -n "$server_ip" ] && [ "$server_ip" != "null" ] && { echo "$server_ip"; return; }
        local ip=$(timeout 5 curl -s4 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s4 --max-time 2 ipinfo.io/ip 2>/dev/null)
        [ -z "$ip" ] && ip=$(timeout 5 curl -s6 --max-time 2 icanhazip.com 2>/dev/null)
        server_ip="$ip"
        echo "$ip"
    }
fi

# --- 鑷璇佷功鐢熸垚 (Hysteria2 涓撶敤) ---
_generate_xray_cert() {
    local domain="$1" cert_path="$2" key_path="$3"
    _info "姝ｅ湪鐢熸垚鑷璇佷功 (${domain})..."
    openssl req -x509 -newkey rsa:2048 -keyout "$key_path" -out "$cert_path" \
        -days 3650 -nodes -subj "/CN=${domain}" \
        -addext "subjectAltName=DNS:${domain}" 2>/dev/null
    if [ $? -ne 0 ]; then
        _error "璇佷功鐢熸垚澶辫触锛?
        return 1
    fi
    chmod 644 "$cert_path" "$key_path"
    _success "璇佷功宸茬敓鎴愩€?
}

# ============================================================
#                   Xray 鏍稿績瀹夎涓庣鐞?# ============================================================

_install_xray() {
    _info "姝ｅ湪瀹夎/鏇存柊 Xray-core..."
    
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
    
    local zip_name="Xray-linux-${xray_arch}.zip"
    local download_url="https://github.com/XTLS/Xray-core/releases/latest/download/${zip_name}"
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
    
    # 瀹夎浜岃繘鍒?    mv "${tmp_dir}/xray" "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    
    # 瀹夎 geodata
    mkdir -p "$XRAY_DIR"
    [ -f "${tmp_dir}/geoip.dat" ] && mv "${tmp_dir}/geoip.dat" "$XRAY_DIR/"
    [ -f "${tmp_dir}/geosite.dat" ] && mv "${tmp_dir}/geosite.dat" "$XRAY_DIR/"
    
    rm -rf "$tmp_dir"
    _release_install_cache
    
    local version=$($XRAY_BIN version 2>/dev/null | head -1 | awk '{print $2}')
    _success "Xray-core v${version} 瀹夎鎴愬姛锛?
}

_create_xray_systemd_service() {
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -c ${XRAY_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null
}

_create_xray_openrc_service() {
    cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run
description="Xray Service"
command="${XRAY_BIN}"
command_args="run -c ${XRAY_CONFIG}"
pidfile="/run/xray.pid"
command_background=true
supervisor=supervise-daemon
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default 2>/dev/null
}

_create_xray_service() {
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        [ -f /etc/systemd/system/xray.service ] || _create_xray_systemd_service
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        [ -f /etc/init.d/xray ] || _create_xray_openrc_service
    fi
}

_manage_xray_service() {
    local action="$1"
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        systemctl "$action" xray 2>/dev/null
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        rc-service xray "$action" 2>/dev/null
    fi
    case "$action" in
        start)   _success "Xray 鏈嶅姟宸插惎鍔ㄣ€? ;;
        stop)    _success "Xray 鏈嶅姟宸插仠姝€? ;;
        restart) _success "Xray 鏈嶅姟宸查噸鍚€? ;;
        status)
            if [ "$INIT_SYSTEM" == "systemd" ]; then
                systemctl status xray --no-pager
            else
                rc-service xray status
            fi
            ;;
    esac
}

_init_xray_config() {
    mkdir -p "$XRAY_DIR"
    if [ ! -f "$XRAY_CONFIG" ]; then
        cat > "$XRAY_CONFIG" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": []
  }
}
EOF
        _success "Xray 閰嶇疆鏂囦欢宸插垵濮嬪寲銆?
    fi
    [ -f "$XRAY_METADATA" ] || echo '{}' > "$XRAY_METADATA"
}

_view_xray_log() {
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        journalctl -u xray -n 50 --no-pager -f
    else
        _warn "OpenRC 鐜涓嬭鏌ョ湅 /var/log/messages"
        tail -f /var/log/messages 2>/dev/null | grep -i xray
    fi
}

_uninstall_xray() {
    echo ""
    _warn "鍗冲皢鍗歌浇 Xray 鏍稿績鍙婂叾鎵€鏈夐厤缃紒"
    read -p "$(echo -e ${RED}"纭畾瑕佸嵏杞藉悧? (杈撳叆 yes 纭): "${NC})" confirm
    if [ "$confirm" != "yes" ]; then
        _info "鍗歌浇宸插彇娑堛€?
        return
    fi
    
    # 鍋滄鏈嶅姟
    _manage_xray_service "stop"
    
    # 浠?clash.yaml 涓竻鐞嗚妭鐐?    if [ -f "$XRAY_METADATA" ] && [ -f "$CLASH_YAML_FILE" ]; then
        local tags=$(jq -r 'keys[]' "$XRAY_METADATA" 2>/dev/null)
        for tag in $tags; do
            local node_name=$(jq -r ".\"$tag\".name // empty" "$XRAY_METADATA" 2>/dev/null)
            [ -n "$node_name" ] && [ "$node_name" != "null" ] && _remove_node_from_yaml "$node_name"
        done
    fi
    
    # 鍒犻櫎鏈嶅姟鏂囦欢
    if [ "$INIT_SYSTEM" == "systemd" ]; then
        systemctl disable xray 2>/dev/null
        rm -f /etc/systemd/system/xray.service
        systemctl daemon-reload
    elif [ "$INIT_SYSTEM" == "openrc" ]; then
        rc-update del xray default 2>/dev/null
        rm -f /etc/init.d/xray
    fi
    
    # 鍒犻櫎鏂囦欢
    rm -f "$XRAY_BIN"
    rm -rf "$XRAY_DIR"
    
    _success "Xray 鏍稿績宸插畬鍏ㄥ嵏杞斤紒"
}

# ============================================================
#                   鍏变韩 Reality 閰嶇疆杈呭姪
# ============================================================

# 鐢熸垚 Reality 瀵嗛挜瀵瑰拰 shortId
_generate_reality_keys() {
    local keypair=$($XRAY_BIN x25519 2>&1)
    # 鎸夎鍙锋彁鍙栵細绗?琛?绉侀挜锛岀2琛?鍏挜 (涓嶄緷璧栧瓧娈靛悕)
    REALITY_PRIVATE_KEY=$(echo "$keypair" | awk 'NR==1 {print $NF}')
    REALITY_PUBLIC_KEY=$(echo "$keypair" | awk 'NR==2 {print $NF}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    # 楠岃瘉瀵嗛挜鏄惁涓虹┖
    if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
        _error "Reality 瀵嗛挜鐢熸垚澶辫触锛亁ray x25519 杈撳嚭:"
        echo "$keypair" >&2
        return 1
    fi
    _info "PrivateKey: ${REALITY_PRIVATE_KEY:0:8}... PublicKey: ${REALITY_PUBLIC_KEY:0:8}..."
}

# 閫氱敤鐨?Reality streamSettings JSON 鐢熸垚
_build_reality_stream() {
    local network="$1" sni="$2" private_key="$3" short_id="$4"
    local extra_settings="$5"
    jq -n --arg net "$network" --arg sni "$sni" --arg pk "$private_key" --arg sid "$short_id" \
        '{
            "network": $net,
            "security": "reality",
            "realitySettings": {
                "show": false,
                "dest": ($sni + ":443"),
                "xver": 0,
                "serverNames": [$sni],
                "privateKey": $pk,
                "shortIds": [$sid]
            }
        }'
}

# 閫氱敤绔彛杈撳叆寰幆
_input_port() {
    local port=""
    while true; do
        read -p "璇疯緭鍏ョ洃鍚鍙? " port
        [[ -z "$port" ]] && _error "绔彛涓嶈兘涓虹┖" && continue
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            _error "鏃犳晥绔彛鍙凤紒"
            continue
        fi
        _check_xray_port_conflict "$port" && continue
        break
    done
    echo "$port"
}

# 淇濆瓨鍒嗕韩閾炬帴鍒板厓鏁版嵁 (鍙傛暟: tag name link [key1=val1 key2=val2 ...])
_save_xray_meta() {
    local tag="$1" name="$2" link="$3"
    shift 3
    
    # 鍏堟瀯寤哄熀纭€ JSON
    local tmp="${XRAY_METADATA}.tmp.$$"
    jq --arg t "$tag" --arg n "$name" --arg l "$link" \
        '. + {($t): {name: $n, share_link: $l}}' "$XRAY_METADATA" > "$tmp" 2>/dev/null && \
        mv "$tmp" "$XRAY_METADATA" || { rm -f "$tmp"; return 1; }
    
    # 杩藉姞棰濆鐨勯敭鍊煎
    for pair in "$@"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        if [ -n "$key" ] && [ -n "$val" ]; then
            local tmp2="${XRAY_METADATA}.tmp.$$"
            jq --arg t "$tag" --arg k "$key" --arg v "$val" \
                '.[$t][$k] = $v' "$XRAY_METADATA" > "$tmp2" 2>/dev/null && \
                mv "$tmp2" "$XRAY_METADATA" || rm -f "$tmp2"
        fi
    done
}

# ============================================================
#              1. VLESS + TCP + Reality + Vision
# ============================================================

_add_vless_reality_vision() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?SNI (榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local default_name="X-Reality-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    # 鐢熸垚鍑瘉
    local uuid=$($XRAY_BIN uuid)
    local flow="xtls-rprx-vision"
    _generate_reality_keys || return 1
    local tag="xray-vless-reality-${port}"
    
    # IPv6 澶勭悊
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    # 鏋勫缓 inbound JSON
    local stream=$(_build_reality_stream "tcp" "$sni" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID")
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" --arg flow "$flow" --argjson stream "$stream" \
        '{
            "tag": $tag,
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": $uuid, "flow": $flow}],
                "decryption": "none"
            },
            "streamSettings": $stream
        }')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    # Clash YAML
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg u "$uuid" \
        --arg sn "$sni" --arg pk "$REALITY_PUBLIC_KEY" --arg sid "$REALITY_SHORT_ID" --arg f "$flow" \
        '{name:$n, type:"vless", server:$s, port:$p, uuid:$u, flow:$f, tls:true, servername:$sn,
          "reality-opts":{"public-key":$pk, "short-id":$sid}, "client-fingerprint":"chrome", network:"tcp"}')
    _add_node_to_yaml "$proxy_json"
    
    # 鍒嗕韩閾炬帴
    local link="vless://${uuid}@${link_ip}:${port}?security=reality&encryption=none&pbk=$(_url_encode "$REALITY_PUBLIC_KEY")&fp=chrome&type=tcp&flow=${flow}&sni=${sni}&sid=${REALITY_SHORT_ID}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link" "publicKey=$REALITY_PUBLIC_KEY" "shortId=$REALITY_SHORT_ID"
    
    _success "VLESS+Reality+Vision 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#              2. VLESS + gRPC + Reality
# ============================================================

_add_vless_grpc_reality() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?SNI (榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local service_name="grpc"
    read -p "璇疯緭鍏?gRPC serviceName (榛樿: grpc): " custom_svc
    service_name=${custom_svc:-grpc}
    
    local default_name="X-gRPC-Reality-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local uuid=$($XRAY_BIN uuid)
    _generate_reality_keys || return 1
    local tag="xray-vless-grpc-${port}"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    # 鏋勫缓 streamSettings (gRPC + Reality)
    local stream=$(_build_reality_stream "grpc" "$sni" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID")
    stream=$(echo "$stream" | jq --arg svc "$service_name" '. + {grpcSettings: {serviceName: $svc}}')
    
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" --argjson stream "$stream" \
        '{tag:$tag, listen:"0.0.0.0", port:$port, protocol:"vless",
          settings:{clients:[{id:$uuid, flow:""}], decryption:"none"},
          streamSettings:$stream}')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg u "$uuid" \
        --arg sn "$sni" --arg pk "$REALITY_PUBLIC_KEY" --arg sid "$REALITY_SHORT_ID" --arg svc "$service_name" \
        '{name:$n, type:"vless", server:$s, port:$p, uuid:$u, tls:true, servername:$sn,
          "reality-opts":{"public-key":$pk, "short-id":$sid}, "client-fingerprint":"chrome",
          network:"grpc", "grpc-opts":{"grpc-service-name":$svc}}')
    _add_node_to_yaml "$proxy_json"
    
    local link="vless://${uuid}@${link_ip}:${port}?security=reality&encryption=none&pbk=$(_url_encode "$REALITY_PUBLIC_KEY")&fp=chrome&type=grpc&serviceName=${service_name}&sni=${sni}&sid=${REALITY_SHORT_ID}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link" "publicKey=$REALITY_PUBLIC_KEY" "shortId=$REALITY_SHORT_ID"
    
    _success "VLESS+gRPC+Reality 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#          3. Trojan + XHTTP + Reality
# ============================================================

_add_trojan_xhttp_reality() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?SNI (榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local path="/$(openssl rand -hex 6)"
    read -p "璇疯緭鍏?XHTTP 璺緞 (榛樿: ${path}): " custom_path
    path=${custom_path:-$path}
    
    local default_name="X-Trojan-XHTTP-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local password=$(openssl rand -hex 16)
    _generate_reality_keys || return 1
    local tag="xray-trojan-xhttp-${port}"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    local stream=$(_build_reality_stream "xhttp" "$sni" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID")
    stream=$(echo "$stream" | jq --arg p "$path" '. + {xhttpSettings: {path: $p}}')
    
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg pw "$password" --argjson stream "$stream" \
        '{tag:$tag, listen:"0.0.0.0", port:$port, protocol:"trojan",
          settings:{clients:[{password:$pw}]},
          streamSettings:$stream}')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    # Clash YAML - mihomo 涓嶆敮鎸?xhttp 浼犺緭灞傦紝璺宠繃鍐欏叆
    _warn "mihomo/Clash 涓嶆敮鎸?XHTTP 浼犺緭灞傦紝姝よ妭鐐逛粎鏀寔 V2rayN/Xray 瀹㈡埛绔?
    
    local link="trojan://${password}@${link_ip}:${port}?security=reality&type=xhttp&path=$(_url_encode "$path")&sni=${sni}&pbk=$(_url_encode "$REALITY_PUBLIC_KEY")&fp=chrome&sid=${REALITY_SHORT_ID}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link" "publicKey=$REALITY_PUBLIC_KEY" "shortId=$REALITY_SHORT_ID"
    
    _success "Trojan+XHTTP+Reality 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#            4. Trojan + gRPC + Reality
# ============================================================

_add_trojan_grpc_reality() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?SNI (榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local service_name="trojan-grpc"
    read -p "璇疯緭鍏?gRPC serviceName (榛樿: trojan-grpc): " custom_svc
    service_name=${custom_svc:-trojan-grpc}
    
    local default_name="X-Trojan-gRPC-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local password=$(openssl rand -hex 16)
    _generate_reality_keys || return 1
    local tag="xray-trojan-grpc-${port}"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    local stream=$(_build_reality_stream "grpc" "$sni" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID")
    stream=$(echo "$stream" | jq --arg svc "$service_name" '. + {grpcSettings: {serviceName: $svc}}')
    
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg pw "$password" --argjson stream "$stream" \
        '{tag:$tag, listen:"0.0.0.0", port:$port, protocol:"trojan",
          settings:{clients:[{password:$pw}]},
          streamSettings:$stream}')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg pw "$password" \
        --arg sn "$sni" --arg pk "$REALITY_PUBLIC_KEY" --arg sid "$REALITY_SHORT_ID" --arg svc "$service_name" \
        '{name:$n, type:"trojan", server:$s, port:$p, password:$pw, udp:true,
          sni:$sn, "skip-cert-verify":false,
          "reality-opts":{"public-key":$pk, "short-id":$sid}, "client-fingerprint":"chrome",
          network:"grpc", "grpc-opts":{"grpc-service-name":$svc}}')
    _add_node_to_yaml "$proxy_json"
    
    local link="trojan://${password}@${link_ip}:${port}?security=reality&type=grpc&serviceName=${service_name}&sni=${sni}&pbk=$(_url_encode "$REALITY_PUBLIC_KEY")&fp=chrome&sid=${REALITY_SHORT_ID}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link" "publicKey=$REALITY_PUBLIC_KEY" "shortId=$REALITY_SHORT_ID"
    
    _success "Trojan+gRPC+Reality 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#                   5. Shadowsocks
# ============================================================

_add_shadowsocks_xray() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    clear
    echo "========================================"
    _info "      Xray Shadowsocks 鍔犲瘑鏂瑰紡"
    echo "========================================"
    echo " [缁忓吀 SS]"
    echo " 1) aes-256-gcm"
    echo " 2) chacha20-ietf-poly1305"
    echo " [SS-2022 (寮烘姉閲嶆斁淇濇姢)]"
    echo " 3) 2022-blake3-aes-256-gcm"
    echo " 4) 2022-blake3-aes-256-gcm (甯?Padding)"
    echo " 0) 杩斿洖"
    echo "========================================"
    read -p "璇烽€夋嫨 [0-4]: " choice
    
    local method="" password="" name_prefix="" use_multiplex="false"
    case $choice in
        1) 
            method="aes-256-gcm"
            password=$(openssl rand -hex 16)
            name_prefix="X-SS-aes256"
            ;;
        2) 
            method="chacha20-ietf-poly1305"
            password=$(openssl rand -hex 16)
            name_prefix="X-SS-chacha20"
            ;;
        3) 
            method="2022-blake3-aes-256-gcm"
            password=$(openssl rand -base64 32)
            name_prefix="X-SS-2022"
            ;;
        4) 
            method="2022-blake3-aes-256-gcm"
            password=$(openssl rand -base64 32)
            name_prefix="X-SS-2022-Padding"
            use_multiplex="true"
            _info "宸查厤缃?Multiplex + Padding 閫夐」"
            ;;
        0) return 1 ;;
        *) _error "鏃犳晥杈撳叆"; return 1 ;;
    esac
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    
    local default_name="${name_prefix}-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local tag="xray-ss-${port}"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    # 淇锛歭isten 鐩戝惉鍦板潃鏀逛负 "::" 鏀寔 IPv4+IPv6 鍙屾爤
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg m "$method" --arg pw "$password" \
        '{
            tag: $tag,
            listen: "::",
            port: $port,
            protocol: "shadowsocks",
            settings: {
                method: $m,
                password: $pw,
                network: "tcp,udp"
            }
        }')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    local proxy_json=""
    if [ "$use_multiplex" == "true" ]; then
        proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg m "$method" --arg pw "$password" \
            '{name:$n, type:"ss", server:$s, port:$p, cipher:$m, password:$pw, smux: {enabled: true, padding: true}}')
    else
        proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg m "$method" --arg pw "$password" \
            '{name:$n, type:"ss", server:$s, port:$p, cipher:$m, password:$pw}')
    fi
    _add_node_to_yaml "$proxy_json"
    
    local ss_user_info=$(_ss_base64_encode "${method}:${password}")
    local link="ss://${ss_user_info}@${link_ip}:${port}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link"
    
    _success "Shadowsocks (${method}) 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#                 鑷璇佷功鐢熸垚 (CF鍥炴簮鐢?
# ============================================================
# 娉ㄦ剰: CF鍥炴簮鍗忚澶嶇敤涓婃柟绗?60琛屽畾涔夌殑 _generate_xray_cert锛屼笉鍐嶉噸澶嶅畾涔?
# ============================================================
#         6. VLESS + HTTP/2 + TLS (鏀寔CF鍥炴簮)
# ============================================================

_add_vless_h2_tls() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ュ煙鍚?(CF鍥炴簮濉粦瀹氬煙鍚? 鐩磋繛鍥炶溅榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local path="/$(openssl rand -hex 6)"
    read -p "璇疯緭鍏?H2 璺緞 (榛樿: ${path}): " custom_path
    path=${custom_path:-$path}
    
    local default_name="X-VLESS-H2-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local uuid=$($XRAY_BIN uuid)
    local tag="xray-vless-h2-${port}"
    local cert_path="${XRAY_DIR}/${tag}.pem"
    local key_path="${XRAY_DIR}/${tag}.key"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    # 鐢熸垚鑷璇佷功
    _generate_xray_cert "$sni" "$cert_path" "$key_path" || return 1
    
    # 鏋勫缓 inbound (Xray v26+ 鏃2宸茶縼绉昏嚦 XHTTP stream-one)
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg cert "$cert_path" --arg key "$key_path" --arg sn "$sni" --arg pa "$path" \
        '{
            tag: $tag,
            listen: "0.0.0.0",
            port: $port,
            protocol: "vless",
            settings: {
                clients: [{id: $uuid, flow: ""}],
                decryption: "none"
            },
            streamSettings: {
                network: "xhttp",
                security: "tls",
                tlsSettings: {
                    certificates: [{certificateFile: $cert, keyFile: $key}],
                    alpn: ["h2"]
                },
                xhttpSettings: {
                    mode: "stream-one",
                    host: $sn,
                    path: $pa
                }
            }
        }')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    # Clash YAML - mihomo 涓嶆敮鎸?XHTTP锛岃烦杩囧啓鍏?    _warn "mihomo/Clash 涓嶆敮鎸?XHTTP 浼犺緭灞傦紝姝よ妭鐐逛粎鏀寔 V2rayN/Xray 瀹㈡埛绔?
    
    local link="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&sni=${sni}&alpn=h2&type=xhttp&mode=stream-one&path=$(_url_encode "$path")&host=${sni}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link"
    
    _info "姝よ妭鐐规敮鎸?CF CDN 鍥炴簮 (SSL妯″紡璁句负 Full)"
    _success "VLESS+H2+TLS 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#         7. VLESS + gRPC + TLS (鏀寔CF鍥炴簮)
# ============================================================

_add_vless_grpc_tls() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ュ煙鍚?(CF鍥炴簮濉粦瀹氬煙鍚? 鐩磋繛鍥炶溅榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local service_name="grpc-$(openssl rand -hex 4)"
    read -p "璇疯緭鍏?gRPC serviceName (榛樿: ${service_name}): " custom_svc
    service_name=${custom_svc:-$service_name}
    
    local default_name="X-VLESS-gRPC-TLS-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local uuid=$($XRAY_BIN uuid)
    local tag="xray-vless-grpc-tls-${port}"
    local cert_path="${XRAY_DIR}/${tag}.pem"
    local key_path="${XRAY_DIR}/${tag}.key"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    _generate_xray_cert "$sni" "$cert_path" "$key_path" || return 1
    
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg cert "$cert_path" --arg key "$key_path" --arg sn "$sni" --arg svc "$service_name" \
        '{
            tag: $tag,
            listen: "0.0.0.0",
            port: $port,
            protocol: "vless",
            settings: {
                clients: [{id: $uuid, flow: ""}],
                decryption: "none"
            },
            streamSettings: {
                network: "grpc",
                security: "tls",
                tlsSettings: {
                    certificates: [{certificateFile: $cert, keyFile: $key}],
                    alpn: ["h2"]
                },
                grpcSettings: {
                    serviceName: $svc
                }
            }
        }')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg u "$uuid" \
        --arg sn "$sni" --arg svc "$service_name" \
        '{name:$n, type:"vless", server:$s, port:$p, uuid:$u, tls:true, servername:$sn,
          "skip-cert-verify":true, network:"grpc",
          "grpc-opts":{"grpc-service-name":$svc}}')
    _add_node_to_yaml "$proxy_json"
    
    local link="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&sni=${sni}&type=grpc&serviceName=${service_name}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link"
    
    _info "姝よ妭鐐规敮鎸?CF CDN 鍥炴簮 (闇€鍦–F寮€鍚痝RPC鏀寔, SSL妯″紡璁句负 Full)"
    _success "VLESS+gRPC+TLS 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#         8. Trojan + gRPC + TLS (鏀寔CF鍥炴簮)
# ============================================================

_add_trojan_grpc_tls() {
    [ -z "$server_ip" ] && server_ip=$(_get_public_ip)
    local node_ip="$server_ip"
    
    read -p "璇疯緭鍏ユ湇鍔″櫒IP (榛樿: ${server_ip}): " custom_ip
    node_ip=${custom_ip:-$server_ip}
    
    local port=$(_input_port)
    local sni="www.amd.com"
    read -p "璇疯緭鍏ュ煙鍚?(CF鍥炴簮濉粦瀹氬煙鍚? 鐩磋繛鍥炶溅榛樿: www.amd.com): " custom_sni
    sni=${custom_sni:-www.amd.com}
    
    local service_name="grpc-$(openssl rand -hex 4)"
    read -p "璇疯緭鍏?gRPC serviceName (榛樿: ${service_name}): " custom_svc
    service_name=${custom_svc:-$service_name}
    
    local default_name="X-Trojan-gRPC-TLS-${port}"
    read -p "璇疯緭鍏ヨ妭鐐瑰悕绉?(榛樿: ${default_name}): " custom_name
    local name=${custom_name:-$default_name}
    
    local password=$(openssl rand -hex 16)
    local tag="xray-trojan-grpc-tls-${port}"
    local cert_path="${XRAY_DIR}/${tag}.pem"
    local key_path="${XRAY_DIR}/${tag}.key"
    local yaml_ip="$node_ip"
    local link_ip="$node_ip"; [[ "$node_ip" == *":"* ]] && link_ip="[$node_ip]"
    
    _generate_xray_cert "$sni" "$cert_path" "$key_path" || return 1
    
    local inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg pw "$password" \
        --arg cert "$cert_path" --arg key "$key_path" --arg sn "$sni" --arg svc "$service_name" \
        '{
            tag: $tag,
            listen: "0.0.0.0",
            port: $port,
            protocol: "trojan",
            settings: {
                clients: [{password: $pw}]
            },
            streamSettings: {
                network: "grpc",
                security: "tls",
                tlsSettings: {
                    certificates: [{certificateFile: $cert, keyFile: $key}],
                    alpn: ["h2"]
                },
                grpcSettings: {
                    serviceName: $svc
                }
            }
        }')
    
    _atomic_modify_json "$XRAY_CONFIG" ".inbounds += [$inbound]" || return 1
    
    local proxy_json=$(jq -n --arg n "$name" --arg s "$yaml_ip" --argjson p "$port" --arg pw "$password" \
        --arg sn "$sni" --arg svc "$service_name" \
        '{name:$n, type:"trojan", server:$s, port:$p, password:$pw, udp:true,
          sni:$sn, "skip-cert-verify":true, network:"grpc",
          "grpc-opts":{"grpc-service-name":$svc}}')
    _add_node_to_yaml "$proxy_json"
    
    local link="trojan://${password}@${link_ip}:${port}?security=tls&type=grpc&serviceName=${service_name}&sni=${sni}#$(_url_encode "$name")"
    
    _save_xray_meta "$tag" "$name" "$link"
    
    _info "姝よ妭鐐规敮鎸?CF CDN 鍥炴簮 (闇€鍦–F寮€鍚痝RPC鏀寔, SSL妯″紡璁句负 Full)"
    _success "Trojan+gRPC+TLS 鑺傜偣 [${name}] 娣诲姞鎴愬姛锛?
    echo -e "  ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
}

# ============================================================
#                     鑺傜偣绠＄悊
# ============================================================

_view_xray_nodes() {
    if [ ! -f "$XRAY_CONFIG" ] || ! jq -e '.inbounds | length > 0' "$XRAY_CONFIG" >/dev/null 2>&1; then
        _warn "褰撳墠娌℃湁 Xray 鑺傜偣銆?
        return
    fi
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲 Xray 鑺傜偣鍒楄〃 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    local count=0
    local tags=$(jq -r '.inbounds[].tag' "$XRAY_CONFIG" 2>/dev/null)
    for tag in $tags; do
        count=$((count + 1))
        local protocol=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .protocol" "$XRAY_CONFIG")
        local port=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .port" "$XRAY_CONFIG")
        local network=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .streamSettings.network // \"tcp\"" "$XRAY_CONFIG")
        local security=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .streamSettings.security // \"none\"" "$XRAY_CONFIG")
        local name=$(jq -r ".\"$tag\".name // \"$tag\"" "$XRAY_METADATA" 2>/dev/null)
        local link=$(jq -r ".\"$tag\".share_link // empty" "$XRAY_METADATA" 2>/dev/null)
        local desc="${protocol}"
        [ "$network" != "null" ] && [ "$network" != "tcp" ] && desc="${desc}+${network}"
        [ "$security" != "null" ] && [ "$security" != "none" ] && desc="${desc}+${security}"
        echo ""
        echo -e "  ${GREEN}[${count}]${NC} ${CYAN}${name}${NC}"
        echo -e "      鍗忚: ${YELLOW}${desc}${NC}  |  绔彛: ${GREEN}${port}${NC}  |  鏍囩: ${CYAN}${tag}${NC}"
        [ -n "$link" ] && echo -e "      ${YELLOW}鍒嗕韩閾炬帴:${NC} ${link}"
    done
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    echo -e "  鍏?${GREEN}${count}${NC} 涓?Xray 鑺傜偣"
}

_delete_xray_node() {
    if [ ! -f "$XRAY_CONFIG" ] || ! jq -e '.inbounds | length > 0' "$XRAY_CONFIG" >/dev/null 2>&1; then
        _warn "褰撳墠娌℃湁 Xray 鑺傜偣鍙垹闄ゃ€?; return
    fi
    local tags=($(jq -r '.inbounds[].tag' "$XRAY_CONFIG" 2>/dev/null))
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲 閫夋嫨瑕佸垹闄ょ殑鑺傜偣 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    for i in "${!tags[@]}"; do
        local tag="${tags[$i]}"
        local port=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .port" "$XRAY_CONFIG")
        local name=$(jq -r ".\"$tag\".name // \"$tag\"" "$XRAY_METADATA" 2>/dev/null)
        echo -e "  ${GREEN}[$((i+1))]${NC} ${name} (绔彛: ${port})"
    done
    echo -e "  ${RED}[99]${NC} 鍒犻櫎鍏ㄩ儴鑺傜偣"
    echo -e "  ${RED}[0]${NC} 杩斿洖"
    echo ""
    read -p "璇烽€夋嫨: " choice
    [ "$choice" == "0" ] && return
    if [ "$choice" == "99" ]; then _delete_all_xray_nodes; return; fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#tags[@]}" ]; then
        _error "鏃犳晥閫夋嫨锛?; return
    fi
    local target_tag="${tags[$((choice-1))]}"
    local target_name=$(jq -r ".\"$target_tag\".name // \"$target_tag\"" "$XRAY_METADATA" 2>/dev/null)
    read -p "$(echo -e ${RED}"纭畾鍒犻櫎 [$target_name]? (y/N): "${NC})" confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { _info "宸插彇娑堛€?; return; }
    [ -n "$target_name" ] && [ "$target_name" != "null" ] && _remove_node_from_yaml "$target_name"
    rm -f "${XRAY_DIR}/${target_tag}.pem" "${XRAY_DIR}/${target_tag}.key" 2>/dev/null
    _atomic_modify_json "$XRAY_CONFIG" "del(.inbounds[] | select(.tag == \"$target_tag\"))"
    _atomic_modify_json "$XRAY_METADATA" "del(.\"$target_tag\")" 2>/dev/null
    _manage_xray_service "restart"
    _success "鑺傜偣 [$target_name] 宸插垹闄わ紒"
}

_delete_all_xray_nodes() {
    if [ ! -f "$XRAY_CONFIG" ] || ! jq -e '.inbounds | length > 0' "$XRAY_CONFIG" >/dev/null 2>&1; then
        _warn "褰撳墠娌℃湁 Xray 鑺傜偣銆?; return
    fi
    local count=$(jq '.inbounds | length' "$XRAY_CONFIG")
    read -p "$(echo -e ${RED}"纭畾鍒犻櫎鍏ㄩ儴 ${count} 涓妭鐐? (y/N): "${NC})" confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { _info "宸插彇娑堛€?; return; }
    # 浠?clash.yaml 涓Щ闄ゆ墍鏈夎妭鐐?    local tags=$(jq -r '.inbounds[].tag' "$XRAY_CONFIG" 2>/dev/null)
    for tag in $tags; do
        local name=$(jq -r ".\"$tag\".name // empty" "$XRAY_METADATA" 2>/dev/null)
        [ -n "$name" ] && _remove_node_from_yaml "$name"
        rm -f "${XRAY_DIR}/${tag}.pem" "${XRAY_DIR}/${tag}.key" 2>/dev/null
    done
    _atomic_modify_json "$XRAY_CONFIG" '.inbounds = []'
    echo '{}' > "$XRAY_METADATA"
    _manage_xray_service "restart"
    _success "鍏ㄩ儴 ${count} 涓妭鐐瑰凡鍒犻櫎锛?
}

_modify_xray_port() {
    if [ ! -f "$XRAY_CONFIG" ] || ! jq -e '.inbounds | length > 0' "$XRAY_CONFIG" >/dev/null 2>&1; then
        _warn "褰撳墠娌℃湁 Xray 鑺傜偣銆?; return
    fi
    local tags=($(jq -r '.inbounds[].tag' "$XRAY_CONFIG" 2>/dev/null))
    echo ""
    echo -e "${YELLOW}鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲 閫夋嫨瑕佷慨鏀圭鍙ｇ殑鑺傜偣 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲${NC}"
    for i in "${!tags[@]}"; do
        local tag="${tags[$i]}"
        local port=$(jq -r ".inbounds[] | select(.tag == \"$tag\") | .port" "$XRAY_CONFIG")
        local name=$(jq -r ".\"$tag\".name // \"$tag\"" "$XRAY_METADATA" 2>/dev/null)
        echo -e "  ${GREEN}[$((i+1))]${NC} ${name} (绔彛: ${port})"
    done
    echo -e "  ${RED}[0]${NC} 杩斿洖"
    echo ""
    read -p "璇烽€夋嫨 [0-${#tags[@]}]: " choice
    [ "$choice" == "0" ] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#tags[@]}" ]; then
        _error "鏃犳晥閫夋嫨锛?; return
    fi
    local target_tag="${tags[$((choice-1))]}"
    local old_port=$(jq -r ".inbounds[] | select(.tag == \"$target_tag\") | .port" "$XRAY_CONFIG")
    local target_name=$(jq -r ".\"$target_tag\".name // \"$target_tag\"" "$XRAY_METADATA" 2>/dev/null)
    _info "褰撳墠绔彛: ${old_port}"
    local new_port=$(_input_port)
    
    # 璁＄畻鏂扮殑 tag 鍜屽悕绉?    local new_tag=$(echo "$target_tag" | sed "s/${old_port}/${new_port}/g")
    local new_name=$(echo "$target_name" | sed "s/${old_port}/${new_port}/g")
    
    # 1. 鏇存柊 config.json: 绔彛 + tag
    _atomic_modify_json "$XRAY_CONFIG" "(.inbounds[] | select(.tag == \"$target_tag\") | .port) = $new_port"
    _atomic_modify_json "$XRAY_CONFIG" "(.inbounds[] | select(.tag == \"$target_tag\") | .tag) = \"$new_tag\""
    
    # 2. 鏇存柊 clash.yaml: 绔彛 + 鍚嶇О
    if [ -n "$target_name" ] && [ "$target_name" != "null" ]; then
        export MOD_NAME="$target_name"
        _atomic_modify_yaml "$CLASH_YAML_FILE" "(.proxies[] | select(.name == env(MOD_NAME)) | .port) = $new_port"
        if [ "$new_name" != "$target_name" ]; then
            export NEW_NAME="$new_name"
            _atomic_modify_yaml "$CLASH_YAML_FILE" '(.proxies[] | select(.name == env(MOD_NAME)) | .name) = env(NEW_NAME)'
        fi
    fi
    
    # 3. 鏇存柊 metadata: tag閿悕 + 鍚嶇О + 鍒嗕韩閾炬帴
    local old_link=$(jq -r ".\"$target_tag\".share_link // empty" "$XRAY_METADATA" 2>/dev/null)
    local new_link=""
    if [ -n "$old_link" ]; then
        new_link=$(echo "$old_link" | sed "s/:${old_port}/:${new_port}/g; s/-${old_port}/-${new_port}/g; s/#[^#]*$/#$(_url_encode "$new_name")/g")
    fi
    # 鐢ㄦ柊 tag 浣滀负 key锛屽垹闄ゆ棫 key
    local tmp="${XRAY_METADATA}.tmp.$$"
    if [ -n "$new_link" ]; then
        jq --arg ot "$target_tag" --arg nt "$new_tag" --arg n "$new_name" --arg l "$new_link" \
            '. + {($nt): (.[$ot] + {name: $n, share_link: $l})} | del(.[$ot])' "$XRAY_METADATA" > "$tmp" 2>/dev/null && \
            mv "$tmp" "$XRAY_METADATA" || rm -f "$tmp"
    else
        jq --arg ot "$target_tag" --arg nt "$new_tag" --arg n "$new_name" \
            '. + {($nt): (.[$ot] + {name: $n})} | del(.[$ot])' "$XRAY_METADATA" > "$tmp" 2>/dev/null && \
            mv "$tmp" "$XRAY_METADATA" || rm -f "$tmp"
    fi
    
    _manage_xray_service "restart"
    _success "鑺傜偣 [$new_name] 绔彛宸叉敼涓?${new_port}锛?
}

# ============================================================
#                       鑿滃崟绯荤粺
# ============================================================

_xray_add_node_menu() {
    while true; do
        clear
        echo ""
        echo -e "  ${GREEN}Xray 娣诲姞鑺傜偣${NC}"
        echo "  ==============================="
        echo -e "  ${CYAN}  鈹€鈹€ Reality 鍗忚 鈹€鈹€${NC}"
        echo -e "  ${YELLOW}[1]${NC} VLESS+TCP+Reality+Vision"
        echo -e "  ${YELLOW}[2]${NC} VLESS+gRPC+Reality"
        echo -e "  ${YELLOW}[3]${NC} Trojan+XHTTP+Reality"
        echo -e "  ${YELLOW}[4]${NC} Trojan+gRPC+Reality"
        echo -e "  ${CYAN}  鈹€鈹€ TLS 鍗忚 (鏀寔CF鍥炴簮) 鈹€鈹€${NC}"
        echo -e "  ${YELLOW}[5]${NC} VLESS+XHTTP+TLS (H2鍥炴簮)"
        echo -e "  ${YELLOW}[6]${NC} VLESS+gRPC+TLS"
        echo -e "  ${YELLOW}[7]${NC} Trojan+gRPC+TLS"
        echo -e "  ${CYAN}  鈹€鈹€ 鍏朵粬 鈹€鈹€${NC}"
        echo -e "  ${YELLOW}[8]${NC} Shadowsocks"
        echo -e "  ${RED}[0]${NC} 杩斿洖"
        echo "  ==============================="
        read -p "璇烽€夋嫨 [0-8]: " choice
        if [ "$choice" != "0" ] && [ ! -f "$XRAY_BIN" ]; then
            _error "Xray 灏氭湭瀹夎锛佽鍏堝畨瑁?Xray 鏍稿績銆?
            read -p "鎸夊洖杞﹂敭杩斿洖..."; continue
        fi
        case $choice in
            1) _add_vless_reality_vision && _manage_xray_service "restart" ;;
            2) _add_vless_grpc_reality && _manage_xray_service "restart" ;;
            3) _add_trojan_xhttp_reality && _manage_xray_service "restart" ;;
            4) _add_trojan_grpc_reality && _manage_xray_service "restart" ;;
            5) _add_vless_h2_tls && _manage_xray_service "restart" ;;
            6) _add_vless_grpc_tls && _manage_xray_service "restart" ;;
            7) _add_trojan_grpc_tls && _manage_xray_service "restart" ;;
            8) _add_shadowsocks_xray && _manage_xray_service "restart" ;;
            0) return ;;
            *) _error "鏃犳晥杈撳叆" ;;
        esac
        echo ""; read -p "鎸夊洖杞﹂敭缁х画..."
    done
}

_xray_menu() {
    # 鍏ㄥ眬鍓嶇疆妫€鏌ワ細Xray 鏍稿績蹇呴』宸插畨瑁?    if [ ! -f "$XRAY_BIN" ]; then
        _error "Xray 鏍稿績鏈畨瑁咃紒璇疯繑鍥炰富鑿滃崟锛岄€氳繃銆愭牳蹇冪鐞嗐€?> [14] 杩涜瀹夎銆?
        read -p "鎸夊洖杞﹂敭杩斿洖..."
        return
    fi

    while true; do
        clear
        echo ""
        echo -e "  ${GREEN}Xray-core 鑺傜偣绠＄悊 v${XRAY_SCRIPT_VERSION}${NC}"
        echo "  =============================="
        local xray_status="${RED}鏈畨瑁?{NC}"
        if [ -f "$XRAY_BIN" ]; then
            local xray_ver=$($XRAY_BIN version 2>/dev/null | head -1 | awk '{print $2}')
            if [ "$INIT_SYSTEM" == "systemd" ]; then
                systemctl is-active xray >/dev/null 2>&1 && xray_status="${GREEN}杩愯涓?{NC} (v${xray_ver})" || xray_status="${YELLOW}宸插仠姝?{NC} (v${xray_ver})"
            else
                rc-service xray status >/dev/null 2>&1 && xray_status="${GREEN}杩愯涓?{NC} (v${xray_ver})" || xray_status="${YELLOW}宸插仠姝?{NC} (v${xray_ver})"
            fi
        fi
        local node_count=$(jq '.inbounds | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")
        echo -e "  鐘舵€? ${xray_status}  鑺傜偣: ${GREEN}${node_count}${NC} 涓?
        echo ""
        echo -e "  ${CYAN}銆愭湇鍔℃帶鍒躲€?{NC}"
        echo -e "    ${YELLOW}[1]${NC} 鍚姩 Xray"
        echo -e "    ${YELLOW}[2]${NC} 鍋滄 Xray"
        echo -e "    ${YELLOW}[3]${NC} 閲嶅惎 Xray"
        echo -e "    ${YELLOW}[4]${NC} 鏌ョ湅 Xray 鐘舵€?
        echo -e "    ${YELLOW}[5]${NC} 鏌ョ湅 Xray 鏃ュ織"
        echo ""
        echo -e "  ${CYAN}銆愯妭鐐圭鐞嗐€?{NC}"
        echo -e "    ${YELLOW}[6]${NC} 娣诲姞鑺傜偣"
        echo -e "    ${YELLOW}[7]${NC} 鏌ョ湅鎵€鏈夎妭鐐?
        echo -e "    ${YELLOW}[8]${NC} 鍒犻櫎鑺傜偣"
        echo -e "    ${YELLOW}[9]${NC} 淇敼绔彛"
        echo ""
        echo -e "    ${RED}[99]${NC} 鍗歌浇 Xray"
        echo -e "    ${RED}[0]${NC}  杩斿洖涓昏彍鍗?
        echo "  =============================="
        read -p "璇烽€夋嫨 [0-99]: " choice
        case $choice in
            1) _manage_xray_service "start"; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            2) _manage_xray_service "stop"; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            3) _manage_xray_service "restart"; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            4) _manage_xray_service "status"; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            5) _view_xray_log ;;
            6) _xray_add_node_menu ;;
            7) _view_xray_nodes; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            8) _delete_xray_node; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            9) _modify_xray_port; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            99) _uninstall_xray; read -p "鎸夊洖杞﹂敭缁х画..." ;;
            0) return ;;
            *) _error "鏃犳晥杈撳叆"; read -p "鎸夊洖杞﹂敭缁х画..." ;;
        esac
    done
}

# ============================================================
#                       鍏ュ彛
# ============================================================
_xray_menu
