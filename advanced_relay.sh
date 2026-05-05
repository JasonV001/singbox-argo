#!/bin/bash

# 核心环境定义
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SINGBOX_DIR="/usr/local/etc/sing-box"
SINGBOX_BIN="/usr/local/bin/sing-box"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/main"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
_info() { echo -e "${CYAN}[信息] $1${NC}" >&2; }
_error() { echo -e "${RED}[错误] $1${NC}" >&2; }
_success() { echo -e "${GREEN}[成功] $1${NC}" >&2; }
_warn() { echo -e "${YELLOW}[注意] $1${NC}" >&2; }

# URL编码
_url_encode() {
    printf '%s' "$1" | jq -sRr @uri
}

# 全局变量
YQ_BINARY="/usr/local/bin/yq"
RELAY_AUX_DIR="${SINGBOX_DIR}"
RELAY_CONFIG_FILE="${RELAY_AUX_DIR}/relay.json"
RELAY_CLASH_YAML="${RELAY_AUX_DIR}/clash.yaml"
RELAY_FILE="${RELAY_AUX_DIR}/relays.conf"

# 中转配置数组
RELAY_TAGS=()
RELAY_JSONS=()
RELAY_DESCS=()

# 节点数组
INBOUND_TAGS=()
INBOUND_PORTS=()
INBOUND_PROTOS=()
INBOUND_RELAY_TAGS=()

# 安装yq
_install_yq() {
    if ! command -v yq &>/dev/null; then
        _info "安装 yq..."
        local arch=$(uname -m)
        case $arch in x86_64|amd64) arch='amd64' ;; aarch64|arm64) arch='arm64' ;; *) arch='amd64' ;; esac
        wget -qO "$YQ_BINARY" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$arch"
        chmod +x "$YQ_BINARY"
    fi
}

# 环境检测
_detect_init_system() {
    if [ -f /sbin/openrc-run ] || command -v rc-service &>/dev/null; then
        INIT_SYSTEM="openrc"
    elif command -v systemctl &>/dev/null; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="unknown"
    fi
}
[ -z "$INIT_SYSTEM" ] && _detect_init_system

# 公网IP获取
_get_public_ip() {
    local ip=$(timeout 5 curl -s4 --max-time 2 icanhazip.com 2>/dev/null || timeout 5 curl -s4 --max-time 2 ipinfo.io/ip 2>/dev/null)
    [ -z "$ip" ] && ip=$(timeout 5 curl -s6 --max-time 2 icanhazip.com 2>/dev/null)
    echo "$ip"
}

# 端口冲突检测
_check_port_occupied() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -lnpt | grep -q ":${port} " && return 0
    else
        netstat -lnpt | grep -q ":${port} " && return 0
    fi
    return 1
}

# 原子修改JSON
_atomic_modify_json() {
    local file="$1" filter="$2"
    [ ! -f "$file" ] && return 1
    local tmp="${file}.tmp"
    if jq "$filter" "$file" > "$tmp"; then mv "$tmp" "$file"
    else _error "修改JSON失败: $file"; rm -f "$tmp"; return 1; fi
}

# 服务管理
_manage_service() {
    local action="$1"
    local service_pkg="sing-box"
    [ -f "/etc/systemd/system/sing-box-relay.service" ] && service_pkg="sing-box-relay"
    case "$INIT_SYSTEM" in
        systemd) systemctl "$action" "$service_pkg" ;;
        openrc) rc-service "$service_pkg" "$action" ;;
    esac
}

# ============================================================
# install.sh 中的中转链接解析函数
# ============================================================

save_relays_to_file() {
    mkdir -p "$(dirname "${RELAY_FILE}")"
    
    cat > "${RELAY_FILE}" << EOF
# Sing-box 中转配置文件
# 格式: TAG|DESCRIPTION|JSON_CONFIG
EOF
    
    for i in "${!RELAY_TAGS[@]}"; do
        local tag="${RELAY_TAGS[$i]}"
        local desc="${RELAY_DESCS[$i]}"
        local json="${RELAY_JSONS[$i]}"
        local json_base64=$(echo "$json" | base64 -w0)
        echo "${tag}|${desc}|${json_base64}" >> "${RELAY_FILE}"
    done
}

load_relays_from_file() {
    RELAY_TAGS=()
    RELAY_JSONS=()
    RELAY_DESCS=()
    
    if [[ ! -f "${RELAY_FILE}" ]]; then
        return 0
    fi
    
    while IFS='|' read -r tag desc json_base64; do
        [[ "$tag" =~ ^#.*$ || -z "$tag" ]] && continue
        
        local json=$(echo "$json_base64" | base64 -d 2>/dev/null)
        if [[ -n "$json" ]]; then
            RELAY_TAGS+=("$tag")
            RELAY_DESCS+=("$desc")
            RELAY_JSONS+=("$json")
        fi
    done < "${RELAY_FILE}"
}

parse_socks_link() {
    local link="$1"
    
    if [[ "$link" =~ ^socks://([A-Za-z0-9+/=]+) ]]; then
        _info "检测到 base64 编码的 SOCKS 链接，正在解码..."
        local base64_part="${BASH_REMATCH[1]}"
        local decoded=$(echo "$base64_part" | base64 -d 2>/dev/null)
        
        if [[ -z "$decoded" ]]; then
            _error "base64 解码失败"
            return 1
        fi
        
        link="socks5://${decoded}"
    fi
    
    local data=$(echo "$link" | sed 's|socks5\?://||')
    data=$(echo "$data" | cut -d'?' -f1 | cut -d'#' -f1)
    
    local relay_json=""
    local relay_desc=""
    
    if [[ "$data" =~ @ ]]; then
        local userpass=$(echo "$data" | cut -d'@' -f1)
        local username=$(echo "$userpass" | cut -d':' -f1)
        local password=$(echo "$userpass" | cut -d':' -f2-)
        local server_port=$(echo "$data" | cut -d'@' -f2)
        local server=$(echo "$server_port" | cut -d':' -f1)
        local port=$(echo "$server_port" | cut -d':' -f2)
        
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            _error "端口无效: ${port}"
            return 1
        fi
        
        local tag="relay-socks5-${#RELAY_TAGS[@]}"
        relay_json="{
  \"type\": \"socks\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"version\": \"5\",
  \"username\": \"${username}\",
  \"password\": \"${password}\"
}"
        relay_desc="SOCKS5 ${server}:${port} (认证)"
    else
        local server=$(echo "$data" | cut -d':' -f1)
        local port=$(echo "$data" | cut -d':' -f2)
        
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            _error "端口无效: ${port}"
            return 1
        fi
        
        local tag="relay-socks5-${#RELAY_TAGS[@]}"
        relay_json="{
  \"type\": \"socks\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"version\": \"5\"
}"
        relay_desc="SOCKS5 ${server}:${port}"
    fi
    
    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    
    save_relays_to_file
    _success "SOCKS5 中转已添加: ${relay_desc}"
}

parse_http_link() {
    local link="$1"
    local protocol=$(echo "$link" | cut -d':' -f1)
    local data=$(echo "$link" | sed 's|https\?://||')
    
    local tls="false"
    [[ "$protocol" == "https" ]] && tls="true"
    
    local relay_json=""
    local relay_desc=""
    local tag="relay-http-${#RELAY_TAGS[@]}"
    
    if [[ "$data" =~ @ ]]; then
        local userpass=$(echo "$data" | cut -d'@' -f1)
        local username=$(echo "$userpass" | cut -d':' -f1)
        local password=$(echo "$userpass" | cut -d':' -f2)
        local server_port=$(echo "$data" | cut -d'@' -f2)
        local server=$(echo "$server_port" | cut -d':' -f1)
        local port=$(echo "$server_port" | cut -d':' -f2 | cut -d'/' -f1 | cut -d'#' -f1 | cut -d'?' -f1)
        
        relay_json="{
  \"type\": \"http\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"username\": \"${username}\",
  \"password\": \"${password}\",
  \"tls\": {\"enabled\": ${tls}}
}"
        relay_desc="${protocol^^} ${server}:${port} (认证)"
    else
        local server=$(echo "$data" | cut -d':' -f1)
        local port=$(echo "$data" | cut -d':' -f2 | cut -d'/' -f1 | cut -d'#' -f1 | cut -d'?' -f1)
        
        relay_json="{
  \"type\": \"http\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"tls\": {\"enabled\": ${tls}}
}"
        relay_desc="${protocol^^} ${server}:${port}"
    fi
    
    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    
    save_relays_to_file
    _success "HTTP(S) 中转已添加: ${relay_desc}"
}

parse_ss_link() {
    local link="$1"
    local data=$(echo "$link" | sed 's|ss://||' | cut -d'#' -f1)
    
    if [[ "$data" =~ @ ]]; then
        local userinfo=$(echo "$data" | cut -d'@' -f1)
        local server_port=$(echo "$data" | cut -d'@' -f2 | cut -d'?' -f1)
        local server=$(echo "$server_port" | cut -d':' -f1)
        local port=$(echo "$server_port" | cut -d':' -f2)
        
        local decoded=$(echo "$userinfo" | base64 -d 2>/dev/null)
        if [[ -z "$decoded" ]]; then
            _error "Shadowsocks 链接解码失败"
            return 1
        fi
        
        local method=$(echo "$decoded" | cut -d':' -f1)
        local password=$(echo "$decoded" | cut -d':' -f2-)
        
        local tag="relay-ss-${#RELAY_TAGS[@]}"
        local relay_json="{
  \"type\": \"shadowsocks\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"method\": \"${method}\",
  \"password\": \"${password}\"
}"
        local relay_desc="Shadowsocks ${server}:${port}"
        
        RELAY_TAGS+=("$tag")
        RELAY_JSONS+=("$relay_json")
        RELAY_DESCS+=("$relay_desc")
        
        save_relays_to_file
        _success "Shadowsocks 中转已添加: ${relay_desc}"
    else
        _error "Shadowsocks 链接格式错误"
        return 1
    fi
}

parse_vmess_link() {
    local link="$1"
    local base64_data=$(echo "$link" | sed 's|vmess://||')
    local json=$(echo "$base64_data" | base64 -d 2>/dev/null)
    
    if [[ -z "$json" ]]; then
        _error "VMess 链接解码失败"
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        _error "需要 jq 工具来解析 VMess 链接"
        return 1
    fi
    
    local server=$(echo "$json" | jq -r '.add // .address')
    local port=$(echo "$json" | jq -r '.port')
    local uuid=$(echo "$json" | jq -r '.id')
    local alterId=$(echo "$json" | jq -r '.aid // 0')
    local security=$(echo "$json" | jq -r '.scy // "auto"')
    
    local tag="relay-vmess-${#RELAY_TAGS[@]}"
    local relay_json="{
  \"type\": \"vmess\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"uuid\": \"${uuid}\",
  \"alter_id\": ${alterId},
  \"security\": \"${security}\"
}"
    local relay_desc="VMess ${server}:${port}"
    
    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    
    save_relays_to_file
    _success "VMess 中转已添加: ${relay_desc}"
}

parse_vless_link() {
    local link="$1"
    local data=$(echo "$link" | sed 's|vless://||')
    local uuid=$(echo "$data" | cut -d'@' -f1)
    local server_port_params=$(echo "$data" | cut -d'@' -f2)
    local server=$(echo "$server_port_params" | cut -d':' -f1)
    local port_params=$(echo "$server_port_params" | cut -d':' -f2)
    local port=$(echo "$port_params" | cut -d'?' -f1)
    
    local params=$(echo "$port_params" | grep -o '?.*' | sed 's|?||' | cut -d'#' -f1)
    
    local security="none"
    local sni=""
    local flow=""
    
    if [[ -n "$params" ]]; then
        [[ "$params" =~ security=([^&]+) ]] && security="${BASH_REMATCH[1]}"
        [[ "$params" =~ sni=([^&]+) ]] && sni="${BASH_REMATCH[1]}"
        [[ "$params" =~ flow=([^&]+) ]] && flow="${BASH_REMATCH[1]}"
    fi
    
    local tls_config=""
    if [[ "$security" == "tls" || "$security" == "reality" ]]; then
        tls_config=",
  \"tls\": {
    \"enabled\": true,
    \"server_name\": \"${sni}\"
  }"
    fi
    
    local flow_config=""
    [[ -n "$flow" ]] && flow_config=",
  \"flow\": \"${flow}\""
    
    local tag="relay-vless-${#RELAY_TAGS[@]}"
    local relay_json="{
  \"type\": \"vless\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"uuid\": \"${uuid}\"${flow_config}${tls_config}
}"
    local relay_desc="VLESS ${server}:${port}"
    
    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    
    save_relays_to_file
    _success "VLESS 中转已添加: ${relay_desc}"
}

parse_trojan_link() {
    local link="$1"
    local data=$(echo "$link" | sed 's|trojan://||')
    local password=$(echo "$data" | cut -d'@' -f1)
    local server_port_params=$(echo "$data" | cut -d'@' -f2)
    local server=$(echo "$server_port_params" | cut -d':' -f1)
    local port_params=$(echo "$server_port_params" | cut -d':' -f2)
    local port=$(echo "$port_params" | cut -d'?' -f1)
    
    local params=$(echo "$port_params" | grep -o '?.*' | sed 's|?||' | cut -d'#' -f1)
    
    local sni=""
    [[ "$params" =~ sni=([^&]+) ]] && sni="${BASH_REMATCH[1]}"
    
    local tag="relay-trojan-${#RELAY_TAGS[@]}"
    local relay_json="{
  \"type\": \"trojan\",
  \"tag\": \"${tag}\",
  \"server\": \"${server}\",
  \"server_port\": ${port},
  \"password\": \"${password}\",
  \"tls\": {
    \"enabled\": true,
    \"server_name\": \"${sni}\"
  }
}"
    local relay_desc="Trojan ${server}:${port}"
    
    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    
    save_relays_to_file
    _success "Trojan 中转已添加: ${relay_desc}"
}

# ============================================================
# 中转配置菜单 (来自 install.sh)
# ============================================================

setup_relay() {
    load_relays_from_file
    
    while true; do
        echo ""
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║              ${GREEN}中转配置菜单${CYAN}                  ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        if [[ ${#RELAY_TAGS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}当前中转列表:${NC}"
            for i in "${!RELAY_TAGS[@]}"; do
                idx=$((i+1))
                echo -e "  ${GREEN}[${idx}]${NC} ${RELAY_DESCS[$i]}"
            done
            echo ""
        else
            echo -e "${YELLOW}当前没有配置中转${NC}"
            echo ""
        fi
        
        echo -e "  ${GREEN}[1]${NC} 添加新的中转链接"
        echo -e "  ${GREEN}[2]${NC} 为节点配置中转"
        echo -e "  ${GREEN}[3]${NC} 删除中转链接"
        echo -e "  ${GREEN}[4]${NC} 清空所有中转"
        echo -e "  ${GREEN}[0]${NC} 返回主菜单"
        echo ""
        read -p "请选择 [0-4]: " r_choice
        
        case $r_choice in
            1)
                echo ""
                echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║          ${GREEN}支持的中转协议格式${CYAN}              ║${NC}"
                echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${GREEN}1. SOCKS5 代理${NC}"
                echo -e "   ${YELLOW}格式:${NC} socks5://[用户名:密码@]服务器:端口"
                echo -e "   ${CYAN}示例:${NC}"
                echo -e "     socks5://user:pass@1.2.3.4:1080"
                echo -e "     socks5://1.2.3.4:1080 ${YELLOW}(无认证)${NC}"
                echo ""
                echo -e "${GREEN}2. HTTP/HTTPS 代理${NC}"
                echo -e "   ${YELLOW}格式:${NC} http(s)://[用户名:密码@]服务器:端口"
                echo -e "   ${CYAN}示例:${NC}"
                echo -e "     http://user:pass@1.2.3.4:8080"
                echo -e "     https://1.2.3.4:443 ${YELLOW}(无认证)${NC}"
                echo ""
                echo -e "${GREEN}3. Shadowsocks${NC}"
                echo -e "   ${YELLOW}格式:${NC} ss://base64(加密方式:密码)@服务器:端口"
                echo -e "   ${CYAN}示例:${NC}"
                echo -e "     ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@1.2.3.4:8388"
                echo ""
                echo -e "${GREEN}4. VMess${NC}"
                echo -e "   ${YELLOW}格式:${NC} vmess://base64(JSON配置)"
                echo -e "   ${CYAN}说明:${NC} 标准 V2Ray 分享链接"
                echo ""
                echo -e "${GREEN}5. VLESS${NC}"
                echo -e "   ${YELLOW}格式:${NC} vless://UUID@服务器:端口?参数#备注"
                echo -e "   ${CYAN}示例:${NC}"
                echo -e "     vless://uuid@1.2.3.4:443?security=tls&sni=example.com"
                echo ""
                echo -e "${GREEN}6. Trojan${NC}"
                echo -e "   ${YELLOW}格式:${NC} trojan://密码@服务器:端口?参数#备注"
                echo -e "   ${CYAN}示例:${NC}"
                echo -e "     trojan://password@1.2.3.4:443?sni=example.com"
                echo ""
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${YELLOW}提示:${NC} 直接粘贴完整的节点分享链接即可，脚本会自动识别协议类型"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                read -p "粘贴中转链接: " RELAY_LINK
                
                if [[ -z "$RELAY_LINK" ]]; then
                    _warn "未提供链接，中转配置保持不变"
                else
                    if [[ "$RELAY_LINK" =~ ^socks ]]; then
                        parse_socks_link "$RELAY_LINK"
                    elif [[ "$RELAY_LINK" =~ ^https? ]]; then
                        parse_http_link "$RELAY_LINK"
                    elif [[ "$RELAY_LINK" =~ ^ss:// ]]; then
                        parse_ss_link "$RELAY_LINK"
                    elif [[ "$RELAY_LINK" =~ ^vmess:// ]]; then
                        parse_vmess_link "$RELAY_LINK"
                    elif [[ "$RELAY_LINK" =~ ^vless:// ]]; then
                        parse_vless_link "$RELAY_LINK"
                    elif [[ "$RELAY_LINK" =~ ^trojan:// ]]; then
                        parse_trojan_link "$RELAY_LINK"
                    else
                        _error "不支持的链接格式"
                    fi
                fi
                ;;
            2)
                if [[ ${#INBOUND_TAGS[@]} -eq 0 ]]; then
                    _warn "当前尚未添加任何节点，请先添加节点"
                    continue
                fi
                
                if [[ ${#RELAY_TAGS[@]} -eq 0 ]]; then
                    _warn "尚未添加任何中转链接，请先选择选项 [1] 添加中转"
                    continue
                fi
                
                echo ""
                echo -e "${CYAN}选择要配置中转的节点:${NC}"
                for i in "${!INBOUND_TAGS[@]}"; do
                    idx=$((i+1))
                    local relay_status="${INBOUND_RELAY_TAGS[$i]}"
                    local relay_desc="直连"
                    
                    if [[ "$relay_status" != "direct" ]]; then
                        for j in "${!RELAY_TAGS[@]}"; do
                            if [[ "${RELAY_TAGS[$j]}" == "$relay_status" ]]; then
                                relay_desc="中转: ${RELAY_DESCS[$j]}"
                                break
                            fi
                        done
                    fi
                    
                    echo -e "  ${GREEN}[${idx}]${NC} ${INBOUND_PROTOS[$i]}:${INBOUND_PORTS[$i]} → ${YELLOW}${relay_desc}${NC}"
                done
                echo ""
                read -p "请输入节点序号 (输入 0 返回): " node_idx
                
                if [[ "$node_idx" == "0" ]]; then
                    continue
                fi
                
                if ! [[ "$node_idx" =~ ^[0-9]+$ ]] || (( node_idx < 1 || node_idx > ${#INBOUND_TAGS[@]} )); then
                    _error "无效的节点序号"
                    continue
                fi
                
                local n=$((node_idx-1))
                
                echo ""
                echo -e "${CYAN}选择中转方式:${NC}"
                echo -e "  ${GREEN}[0]${NC} 直连 (不使用中转)"
                for i in "${!RELAY_TAGS[@]}"; do
                    idx=$((i+1))
                    echo -e "  ${GREEN}[${idx}]${NC} ${RELAY_DESCS[$i]}"
                done
                echo ""
                read -p "请选择: " relay_idx
                
                if [[ "$relay_idx" == "0" ]]; then
                    INBOUND_RELAY_TAGS[$n]="direct"
                    _success "节点已设置为直连"
                elif [[ "$relay_idx" =~ ^[0-9]+$ ]] && (( relay_idx >= 1 && relay_idx <= ${#RELAY_TAGS[@]} )); then
                    local r=$((relay_idx-1))
                    INBOUND_RELAY_TAGS[$n]="${RELAY_TAGS[$r]}"
                    _success "节点已设置为: ${RELAY_DESCS[$r]}"
                else
                    _error "无效选择"
                    continue
                fi
                ;;
            3)
                if [[ ${#RELAY_TAGS[@]} -eq 0 ]]; then
                    _warn "当前没有中转链接"
                    continue
                fi
                
                echo ""
                echo -e "${CYAN}删除中转链接:${NC}"
                echo -e "  ${GREEN}[0]${NC} 删除全部中转"
                for i in "${!RELAY_TAGS[@]}"; do
                    idx=$((i+1))
                    echo -e "  ${GREEN}[${idx}]${NC} ${RELAY_DESCS[$i]}"
                done
                echo ""
                read -p "请选择要删除的中转 (输入 0 删除全部, 输入 -1 取消): " del_idx
                
                if [[ "$del_idx" == "-1" ]]; then
                    continue
                elif [[ "$del_idx" == "0" ]]; then
                    echo ""
                    read -p "确认删除全部中转? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        RELAY_TAGS=()
                        RELAY_JSONS=()
                        RELAY_DESCS=()
                        rm -f "${RELAY_FILE}"
                        
                        for i in "${!INBOUND_RELAY_TAGS[@]}"; do
                            INBOUND_RELAY_TAGS[$i]="direct"
                        done
                        
                        _success "已删除全部中转配置"
                    fi
                elif [[ "$del_idx" =~ ^[0-9]+$ ]] && (( del_idx >= 1 && del_idx <= ${#RELAY_TAGS[@]} )); then
                    local d=$((del_idx-1))
                    local del_tag="${RELAY_TAGS[$d]}"
                    local del_desc="${RELAY_DESCS[$d]}"
                    
                    echo ""
                    read -p "确认删除中转: ${del_desc}? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        unset RELAY_TAGS[$d]
                        unset RELAY_JSONS[$d]
                        unset RELAY_DESCS[$d]
                        
                        RELAY_TAGS=("${RELAY_TAGS[@]}")
                        RELAY_JSONS=("${RELAY_JSONS[@]}")
                        RELAY_DESCS=("${RELAY_DESCS[@]}")
                        
                        for i in "${!INBOUND_RELAY_TAGS[@]}"; do
                            if [[ "${INBOUND_RELAY_TAGS[$i]}" == "$del_tag" ]]; then
                                INBOUND_RELAY_TAGS[$i]="direct"
                            fi
                        done
                        
                        save_relays_to_file
                        _success "已删除中转: ${del_desc}"
                    fi
                else
                    _error "无效选择"
                fi
                ;;
            4)
                clear_relay
                ;;
            0)
                break
                ;;
            *)
                _error "无效选项"
                ;;
        esac
    done
}

clear_relay() {
    echo ""
    read -p "确认删除全部中转配置并恢复直连? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        _info "取消操作"
        return 0
    fi
    
    RELAY_TAGS=()
    RELAY_JSONS=()
    RELAY_DESCS=()
    rm -f "${RELAY_FILE}"
    
    if [[ ${#INBOUND_RELAY_TAGS[@]} -gt 0 ]]; then
        for i in "${!INBOUND_RELAY_TAGS[@]}"; do
            INBOUND_RELAY_TAGS[$i]="direct"
        done
    fi
    
    _success "已删除全部中转配置，当前为直连模式"
}

# ============================================================
# 端口转发管理模块 (保留原有功能)
# ============================================================

PF_METADATA_FILE="${RELAY_AUX_DIR}/relay_pf.json"

_pf_normalize_target_addr() {
    local addr="$1"
    if [[ "$addr" =~ ^\[(.*)\]$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$addr"
    fi
}

_pf_is_ipv4_literal() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

_pf_is_ipv6_literal() {
    local addr="$(_pf_normalize_target_addr "$1")"
    [[ "$addr" == *:* ]]
}

_pf_format_to_destination() {
    local family="$1"
    local ip="$2"
    local port="$3"
    if [ "$family" == "ipv6" ]; then
        echo "[${ip}]:${port}"
    else
        echo "${ip}:${port}"
    fi
}

_pf_can_write_iptables_rule() {
    local bin="$1"
    shift
    command -v "$bin" &>/dev/null || return 1
    "$bin" "$@" &>/dev/null || return 1
    local delete_args=("$@")
    local i
    for ((i=0; i<${#delete_args[@]}; i++)); do
        if [ "${delete_args[$i]}" == "-A" ]; then
            delete_args[$i]="-D"
            break
        fi
    done
    "$bin" "${delete_args[@]}" &>/dev/null
}

_pf_has_ip6tables_nat() {
    command -v ip6tables &>/dev/null && ip6tables -t nat -L PREROUTING -n &>/dev/null 2>&1
}

_pf_ensure_metadata() {
    [ -f "$PF_METADATA_FILE" ] || echo '{}' > "$PF_METADATA_FILE"
}

_pf_count() {
    _pf_ensure_metadata
    jq 'length' "$PF_METADATA_FILE" 2>/dev/null || echo 0
}

_pf_enable_forwarding() {
    if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
        echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
        if ! grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        else
            sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
        fi
        _info "已启用 IPv4 转发 (ip_forward=1)"
    fi
}

_save_iptables_rules() {
    _info "正在保存 IPTables 规则..."
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    else
        if command -v iptables-save &>/dev/null; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
        fi
        if command -v ip6tables-save &>/dev/null; then
            mkdir -p /etc/iptables
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        fi
    fi
    if command -v rc-service &>/dev/null; then
        rc-service iptables save 2>/dev/null
        rc-service ip6tables save 2>/dev/null
    fi
}

_pf_view() {
    echo ""
    _info "=== 当前端口转发规则 ==="
    echo ""
    _pf_ensure_metadata
    
    local count=$(_pf_count)
    if [ "$count" -eq 0 ]; then
        _warn "暂无转发规则"; read -p "  按回车继续..."; return
    fi
    
    local i=1
    while IFS=$'\t' read -r port name engine addr tport net_display; do
        [ -z "$port" ] && continue
        local engine_label=""
        if [ "$engine" == "iptables" ]; then
            engine_label="${GREEN}iptables${NC}"
        else
            engine_label="${YELLOW}sing-box${NC}"
        fi
        echo -e "  ${GREEN}[$i]${NC} 【${name}】 本机 :${CYAN}${port}${NC} → ${CYAN}${addr}:${tport}${NC}  [${YELLOW}${net_display}${NC}]  引擎: ${engine_label}"
        i=$((i+1))
    done < <(jq -r 'to_entries[] | [.key, .value.name, .value.engine, .value.target_addr, (.value.target_port|tostring), .value.network_display] | @tsv' "$PF_METADATA_FILE" 2>/dev/null)
    
    echo ""
    echo -e "  共 ${GREEN}${count}${NC} 条转发规则"
    echo ""
    read -p "  按回车继续..."
}

_pf_build_inbound_json() {
    local tag="$1"
    local listen_port="$2"
    local network="$3"

    if [ "$network" == "tcp+udp" ]; then
        jq -n --arg t "$tag" --argjson p "$listen_port" \
            '{"type":"direct","tag":$t,"listen":"::","listen_port":$p}'
    else
        jq -n --arg t "$tag" --argjson p "$listen_port" --arg net "$network" \
            '{"type":"direct","tag":$t,"listen":"::","listen_port":$p,"network":$net}'
    fi
}

_pf_build_rule_json() {
    local inbound_tag="$1"
    local outbound_tag="$2"
    local target_addr="$3"
    local target_port="$4"
    local network="$5"

    jq -n --arg it "$inbound_tag" --arg ot "$outbound_tag" --arg addr "$target_addr" --argjson port "$target_port" --arg net "$network" '
        {
            inbound: $it,
            outbound: $ot,
            action: "route",
            override_address: $addr,
            override_port: $port
        }
        | if ($net == "udp" or $net == "tcp+udp") then .udp_connect = true | .udp_timeout = "5m" else . end
    '
}

_pf_apply_singbox_rules() {
    local action="$1"
    local listen_port="$2"
    local target_addr="$3"
    local target_port="$4"
    local network="$5"
    local in_tag="pf-in-${listen_port}"
    local out_tag="pf-out-${listen_port}"

    [ ! -f "$RELAY_CONFIG_FILE" ] && echo '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}' > "$RELAY_CONFIG_FILE"

    if [ "$action" == "delete" ]; then
        local del_filter="del(.inbounds[] | select(.tag == \"$in_tag\"))"
        del_filter="${del_filter} | del(.outbounds[] | select(.tag == \"$out_tag\"))"
        del_filter="${del_filter} | .route.rules = [.route.rules[] | select(.inbound != \"$in_tag\")]"
        _atomic_modify_json "$RELAY_CONFIG_FILE" "$del_filter"
        return $?
    fi

    local inbound_json
    inbound_json=$(_pf_build_inbound_json "$in_tag" "$listen_port" "$network")
    local outbound_json
    outbound_json=$(jq -n --arg t "$out_tag" '{"type":"direct","tag":$t}')
    local rule_json
    rule_json=$(_pf_build_rule_json "$in_tag" "$out_tag" "$target_addr" "$target_port" "$network")

    local combined_filter=".inbounds += [$inbound_json] | .outbounds += [$outbound_json]"
    if ! jq -e '.route' "$RELAY_CONFIG_FILE" >/dev/null 2>&1; then
        combined_filter="${combined_filter} | . + {\"route\":{\"rules\":[]}}"
    fi
    combined_filter="${combined_filter} | .route.rules += [$rule_json]"
    _atomic_modify_json "$RELAY_CONFIG_FILE" "$combined_filter"
}

_pf_store_metadata() {
    local listen_port="$1"
    local engine="$2"
    local custom_name="$3"
    local target_addr="$4"
    local target_port="$5"
    local network="$6"
    local network_display="$7"

    local meta
    meta=$(jq -n \
        --arg engine "$engine" \
        --arg name "$custom_name" \
        --arg addr "$target_addr" \
        --argjson tport "$target_port" \
        --arg net "$network" \
        --arg net_display "$network_display" \
        --arg created "$(date '+%Y-%m-%d %H:%M:%S')" \
        '{
            engine: $engine,
            name: $name,
            target_addr: $addr,
            target_port: $tport,
            network: $net,
            network_display: $net_display,
            created_at: $created
        }')

    jq --arg port "$listen_port" --argjson meta "$meta" '.[$port] = $meta' "$PF_METADATA_FILE" > "${PF_METADATA_FILE}.tmp" \
        && mv "${PF_METADATA_FILE}.tmp" "$PF_METADATA_FILE"
}

_pf_prepare_iptables_target() {
    local raw_addr="$1"
    local addr="$(_pf_normalize_target_addr "$raw_addr")"

    if _pf_is_ipv4_literal "$addr"; then
        printf 'ipv4\t%s\tfalse\n' "$addr"
        return 0
    fi
    if _pf_is_ipv6_literal "$addr"; then
        _pf_has_ip6tables_nat || return 1
        printf 'ipv6\t%s\tfalse\n' "$addr"
        return 0
    fi

    local resolved=""
    if command -v getent &>/dev/null; then
        resolved=$(getent ahostsv4 "$addr" 2>/dev/null | awk '{print $1}' | head -1)
    fi
    if [ -z "$resolved" ] && command -v dig &>/dev/null; then
        resolved=$(dig +short A "$addr" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
    fi

    [ -z "$resolved" ] && return 1
    printf 'ipv4\t%s\ttrue\n' "$resolved"
}

_pf_ensure_masquerade() {
    local target_ip="$1"
    local family="${2:-ipv4}"
    local bin="iptables"

    if [ "$family" == "ipv6" ]; then
        bin="ip6tables"
        _pf_has_ip6tables_nat || return 0
    fi

    "$bin" -t nat -A POSTROUTING -d "$target_ip" -j MASQUERADE 2>/dev/null
}

_pf_apply_forward_filter_rules() {
    local op="$1"
    local family="$2"
    local proto="$3"
    local target_ip="$4"
    local target_port="$5"
    local bin="iptables"

    if [ "$family" == "ipv6" ]; then
        bin="ip6tables"
        command -v "$bin" &>/dev/null || return 0
        "$bin" -L FORWARD -n &>/dev/null 2>&1 || return 0
    else
        command -v "$bin" &>/dev/null || return 0
    fi

    "$bin" "$op" FORWARD -p "$proto" -d "$target_ip" --dport "$target_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    "$bin" "$op" FORWARD -p "$proto" -s "$target_ip" --sport "$target_port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
}

_pf_apply_iptables_rules() {
    local action="$1"
    local listen_port="$2"
    local target_ip="$3"
    local target_port="$4"
    local network="$5"
    local family="$6"
    local bin="iptables"
    local rc=0

    if [ "$family" == "ipv6" ]; then
        bin="ip6tables"
        _pf_has_ip6tables_nat || return 1
    fi

    local chain_flag="-A"
    [ "$action" == "delete" ] && chain_flag="-D"
    local to_dest
    to_dest=$(_pf_format_to_destination "$family" "$target_ip" "$target_port")
    local proto
    for proto in tcp udp; do
        if [[ "$network" != "$proto" && "$network" != "tcp+udp" ]]; then
            continue
        fi
        if ! "$bin" -t nat "$chain_flag" PREROUTING -p "$proto" --dport "$listen_port" -j DNAT --to-destination "$to_dest" 2>/dev/null; then
            [ "$action" == "add" ] && rc=1
        fi
        if ! "$bin" -t nat "$chain_flag" OUTPUT -p "$proto" --dport "$listen_port" -j DNAT --to-destination "$to_dest" 2>/dev/null; then
            [ "$action" == "add" ] && rc=1
        fi
        _pf_apply_forward_filter_rules "$chain_flag" "$family" "$proto" "$target_ip" "$target_port"
    done

    if [ "$action" == "add" ]; then
        _pf_ensure_masquerade "$target_ip" "$family"
    fi
    return "$rc"
}

_pf_add() {
    echo ""
    _pf_ensure_metadata

    local PF_ENGINE="singbox"
    if command -v iptables &>/dev/null; then
        if iptables -t nat -A PREROUTING -p tcp --dport 65535 -j DNAT --to-destination 127.0.0.1:65535 2>/dev/null; then
            iptables -t nat -D PREROUTING -p tcp --dport 65535 -j DNAT --to-destination 127.0.0.1:65535 2>/dev/null
            PF_ENGINE="iptables"
        fi
    fi

    if [ "$PF_ENGINE" == "iptables" ]; then
        _info "=== 添加端口转发规则 (引擎: iptables DNAT) ==="
    else
        _warn "=== 添加端口转发规则 (引擎: sing-box 用户态转发) ==="
    fi
    echo ""

    local listen_port
    while true; do
        read -p "  请输入本机监听端口: " listen_port
        if [[ ! "$listen_port" =~ ^[0-9]+$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            _error "无效端口，请输入 1-65535 之间的数字"
            continue
        fi
        if _check_port_occupied "$listen_port"; then
            _error "端口 $listen_port 已被系统占用，请换一个"
            continue
        fi
        if jq -e ".\"$listen_port\"" "$PF_METADATA_FILE" >/dev/null 2>&1; then
            _error "端口 $listen_port 已存在转发规则，请换一个"
            continue
        fi
        break
    done

    local target_addr
    read -p "  请输入目标地址 (IP 或域名): " target_addr
    if [ -z "$target_addr" ]; then
        _error "目标地址不能为空"; read -p "  按回车继续..."; return
    fi

    local target_port
    read -p "  请输入目标端口: " target_port
    if [[ ! "$target_port" =~ ^[0-9]+$ ]] || [ "$target_port" -lt 1 ] || [ "$target_port" -gt 65535 ]; then
        _error "无效端口"; read -p "  按回车继续..."; return
    fi

    echo ""
    local proto_choice
    local network="tcp"
    local network_display="TCP"
    echo -e "  ${CYAN}请选择转发协议：${NC}"
    echo -e "    ${GREEN}[1]${NC} 仅 TCP"
    echo -e "    ${GREEN}[2]${NC} 仅 UDP"
    echo -e "    ${GREEN}[3]${NC} TCP+UDP"
    echo ""
    read -p "  请选择 [1-3] (默认 1): " proto_choice
    case "$proto_choice" in
        2) network="udp"; network_display="UDP" ;;
        3) network="tcp+udp"; network_display="TCP+UDP" ;;
        *) ;;
    esac

    local custom_name
    read -p "  请输入备注名称 (直接回车默认: 转发规则-${listen_port}): " custom_name
    [ -z "$custom_name" ] && custom_name="转发规则-${listen_port}"
    custom_name="${custom_name//\"/}"
    custom_name="${custom_name//\\/}"
    custom_name="${custom_name//#/}"

    if [ "$PF_ENGINE" == "iptables" ]; then
        local resolved_payload=""
        resolved_payload=$(_pf_prepare_iptables_target "$target_addr")
        if [ $? -ne 0 ] || [ -z "$resolved_payload" ]; then
            _error "目标地址无法解析为可用的 IPv4/IPv6，无法创建 iptables 转发规则"
            read -p "  按回车继续..."; return
        fi
        local target_family resolved_ip target_is_domain
        IFS=$'\t' read -r target_family resolved_ip target_is_domain <<< "$resolved_payload"
        [ "$target_is_domain" == "true" ] && _success "域名已解析: $target_addr -> $resolved_ip (${target_family})"
        _pf_enable_forwarding
        if ! _pf_apply_iptables_rules "add" "$listen_port" "$resolved_ip" "$target_port" "$network" "$target_family"; then
            _error "iptables 规则写入失败"
            read -p "  按回车继续..."; return
        fi
        _save_iptables_rules
    else
        if ! _pf_apply_singbox_rules "add" "$listen_port" "$target_addr" "$target_port" "$network"; then
            _error "配置写入失败"
            read -p "  按回车继续..."; return
        fi
        _manage_service restart
    fi

    _pf_store_metadata "$listen_port" "$PF_ENGINE" "$custom_name" "$target_addr" "$target_port" "$network" "$network_display"

    echo ""
    _success "端口转发规则已添加并生效！"
    echo -e "  引擎: ${CYAN}${PF_ENGINE}${NC}"
    echo -e "  转发模式: ${CYAN}${network_display}${NC}"
    echo -e "  本机端口: ${GREEN}${listen_port}${NC} -> 目标: ${GREEN}${target_addr}:${target_port}${NC}"
    echo ""
    read -p "  按回车继续..."
}

_pf_delete() {
    echo ""
    _info "=== 删除端口转发规则 ==="
    echo ""
    _pf_ensure_metadata

    local count=$(_pf_count)
    if [ "$count" -eq 0 ]; then
        _warn "暂无转发规则"; read -p "  按回车继续..."; return
    fi

    local ports=()
    local i=1
    while IFS=$'\t' read -r port name engine addr tport net_display; do
        [ -z "$port" ] && continue
        ports+=("$port")
        echo -e "  ${GREEN}[$i]${NC} 【${name}】:${CYAN}${port}${NC} -> ${CYAN}${addr}:${tport}${NC}  [${YELLOW}${net_display}${NC}]"
        i=$((i+1))
    done < <(jq -r 'to_entries[] | [.key, .value.name, .value.engine, .value.target_addr, (.value.target_port|tostring), .value.network_display] | @tsv' "$PF_METADATA_FILE" 2>/dev/null)

    echo ""
    read -p "  请输入要删除的序号 (0 取消): " sel
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#ports[@]}" ]; then
        [ "$sel" != "0" ] && _error "无效选择"
        return
    fi

    local selected_port="${ports[$((sel-1))]}"
    local sel_engine=$(jq -r ".\"$selected_port\".engine" "$PF_METADATA_FILE")
    local sel_addr=$(jq -r ".\"$selected_port\".target_addr" "$PF_METADATA_FILE")
    local sel_tport=$(jq -r ".\"$selected_port\".target_port" "$PF_METADATA_FILE")
    local sel_net=$(jq -r ".\"$selected_port\".network" "$PF_METADATA_FILE")

    if [ "$sel_engine" == "iptables" ]; then
        _pf_apply_iptables_rules "delete" "$selected_port" "$sel_addr" "$sel_tport" "$sel_net" "ipv4"
        _save_iptables_rules
    else
        _pf_apply_singbox_rules "delete" "$selected_port"
        _manage_service restart
    fi

    jq "del(.\"$selected_port\")" "$PF_METADATA_FILE" > "${PF_METADATA_FILE}.tmp" \
        && mv "${PF_METADATA_FILE}.tmp" "$PF_METADATA_FILE"

    _success "已删除端口 ${selected_port} 的转发规则"
    read -p "  按回车继续..."
}

_pf_clear() {
    local count=$(_pf_count)
    if [ "$count" -eq 0 ]; then
        _warn "暂无转发规则"; read -p "  按回车继续..."; return
    fi

    echo ""
    _warn "确认清空全部 ${count} 条端口转发规则？"
    read -p "  (y/N): " confirm
    if [ "$confirm" != "y" ]; then return; fi

    local need_singbox_restart=false
    while IFS=$'\t' read -r port engine addr tport net; do
        [ -z "$port" ] && continue
        if [ "$engine" == "iptables" ]; then
            _pf_apply_iptables_rules "delete" "$port" "$addr" "$tport" "$net" "ipv4"
        else
            _pf_apply_singbox_rules "delete" "$port"
            need_singbox_restart=true
        fi
    done < <(jq -r 'to_entries[] | [.key, .value.engine, .value.target_addr, (.value.target_port|tostring), .value.network] | @tsv' "$PF_METADATA_FILE" 2>/dev/null)

    echo '{}' > "$PF_METADATA_FILE"
    _save_iptables_rules
    if [ "$need_singbox_restart" = true ]; then
        _manage_service restart
    fi

    _success "所有端口转发规则已清空"
    read -p "  按回车继续..."
}

_port_forward_menu() {
    while true; do
        clear
        local count=$(_pf_count)
        echo -e "${CYAN}"
        echo "  ╔═══════════════════════════════════════╗"
        echo -e "  ║    端口转发管理 (当前规则: ${GREEN}${count}${CYAN} 条)      ║"
        echo "  ╠═══════════════════════════════════════╣"
        echo -e "  ║  ${GREEN}[1]${CYAN} 添加转发规则                     ║"
        echo -e "  ║  ${GREEN}[2]${CYAN} 查看当前转发规则                 ║"
        echo -e "  ║  ${GREEN}[3]${NC} 删除转发规则                     ║"
        echo -e "  ║  ${RED}[4]${NC} 清空所有转发规则                 ║"
        echo -e "  ║  ${YELLOW}[0]${CYAN} 返回上级菜单                     ║"
        echo "  ╚═══════════════════════════════════════╝"
        echo -e "${NC}"
        
        read -p "  请输入选项 [0-4]: " pf_choice
        case "$pf_choice" in
            1) _pf_add ;;
            2) _pf_view ;;
            3) _pf_delete ;;
            4) _pf_clear ;;
            0) return ;;
            *) _error "无效输入"; sleep 1 ;;
        esac
    done
}

# ============================================================
# 主菜单
# ============================================================

_menu() {
    _install_yq

    while true; do
        clear
        echo -e "${CYAN}"
        echo '  ____  _             ____            '
        echo ' / ___|(_)_ __   __ _| __ )  _____  __'
        echo ' \___ \| | '\''_ \ / _` |  _ \ / _ \ \/ /'
        echo '  ___) | | | | | (_| | |_) | (_) >  < '
        echo ' |____/|_|_| |_|\__, |____/ \___/_/\_\'
        echo '                |___/    Lite Manager '
        echo -e "${NC}"

        echo -e "${CYAN}"
        echo "  ╔═══════════════════════════════════════╗"
        echo "  ║       singbox-lite 进阶转发管理       ║"
        echo "  ║           (新版中转系统)              ║"
        echo "  ╚═══════════════════════════════════════╝"
        echo -e "${NC}"

        local os_info="Linux"
        [ -f /etc/os-release ] && os_info=$(grep -E "^NAME=" /etc/os-release | cut -d'"' -f2 | head -1)
        
        local service_status="${RED}○ 已停止${NC}"
        local service_name="sing-box"
        [ -f "/etc/systemd/system/sing-box-relay.service" ] && service_name="sing-box-relay"
        
        if [ "$INIT_SYSTEM" == "systemd" ]; then
            systemctl is-active --quiet "$service_name" && service_status="${GREEN}● 运行中${NC}"
        else
            rc-service "$service_name" status 2>/dev/null | grep -q "started" && service_status="${GREEN}● 运行中${NC}"
        fi

        echo -e "  系统版本: ${CYAN}${os_info}${NC}"
        echo -e "  服务状态: ${service_status}"
        echo ""
        echo -e "  ${CYAN}【中转管理】${NC}"
        echo -e "    ${GREEN}[1]${NC} 中转配置管理"
        echo ""
        echo -e "  ${CYAN}【端口转发】${NC}"
        echo -e "    ${GREEN}[2]${NC} 端口转发管理"
        echo ""
        echo -e "  ─────────────────────────────────────────"
        echo -e "    ${YELLOW}[0]${NC} 退出"
        echo ""
        read -p "  请输入选项 [0-2]: " choice
        case $choice in
            1) setup_relay ;;
            2) _port_forward_menu ;;
            0) break ;;
            *) _error "无效输入"; sleep 1 ;;
        esac
    done
}

_menu
