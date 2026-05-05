#!/bin/bash
# shellcheck disable=SC2034,SC2155,SC2086

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

if [[ ! -x "$0" ]]; then
    echo "警告: 脚本缺少执行权限，尝试自动修复..."
    chmod +x "$0" 2>/dev/null
    if [[ ! -x "$0" ]]; then
        echo "错误: 无法自动添加执行权限"
        echo "请手动运行: chmod +x $0"
        exit 1
    fi
    echo "执行权限已修复"
fi

DEFAULT_CONFIG_FILE="/etc/sing-box/config.json"
DEFAULT_RELAY_FILE="/etc/sing-box/relays.conf"
CONFIG_DIR="/etc/sing-box"
INSTALL_FLAG="${CONFIG_DIR}/.relay_installed"
PATH_CONFIG_FILE="${CONFIG_DIR}/relay_path.conf"
LOG_FILE="/var/log/sing-box-relay.log"
AUTO_DETECT_FILE="${CONFIG_DIR}/.auto_detect.conf"
LAST_SUCCESS_FILE="${CONFIG_DIR}/.last_success.conf"
RECOVERY_HISTORY_FILE="${CONFIG_DIR}/.recovery_history.log"

CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
RELAY_FILE="${DEFAULT_RELAY_FILE}"

INSTALL_DIR="/usr/local/bin"
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

RELAY_TAGS=()
RELAY_JSONS=()
RELAY_DESCS=()

INBOUND_TAGS=()
INBOUND_PORTS=()
INBOUND_PROTOS=()
INBOUND_SNIS=()
INBOUND_RELAY_TAGS=()

ALPINE=0
OS_NAME=""
ARCH=""
AUTO_DETECT_ENABLED=1
CONFIG_VALID=false
INITIALIZED=false

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

log_msg() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local max_size=$((10 * 1024 * 1024))
    if [[ -f "$LOG_FILE" ]]; then
        local file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ "$file_size" -gt "$max_size" ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
        fi
    fi
    
    echo "[$timestamp] [${level}] $message" >> "$LOG_FILE" 2>/dev/null || true
    echo "[$timestamp] [${level}] $message" >> /var/log/sing-box-relay-last.log 2>/dev/null || true
}

log_debug() { log_msg "DEBUG" "$1"; }
log_info() { log_msg "INFO" "$1"; print_info "$1"; }
log_success() { log_msg "SUCCESS" "$1"; print_success "$1"; }
log_warning() { log_msg "WARNING" "$1"; print_warning "$1"; }
log_error() { log_msg "ERROR" "$1"; print_error "$1"; }
log_critical() { log_msg "CRITICAL" "$1"; print_error "$1"; }

detect_system() {
    log_info "开始系统检测..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$NAME"
        [[ "$ID" == "alpine" ]] && ALPINE=1 || ALPINE=0
        log_info "操作系统: ${OS_NAME}"
    else
        OS_NAME="Unknown"
        ALPINE=0
        log_warning "无法检测操作系统"
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) log_warning "不支持的架构: $ARCH" ;;
    esac
    log_success "系统检测完成: ${OS_NAME} (${ARCH})"
}

detect_config_paths() {
    # 自动检测配置文件路径
    # 搜索优先级路径和常见位置，设置全局 CONFIG_FILE 和 RELAY_FILE
    # 返回值:
    #   0 - 检测成功
    #   1 - 未找到配置文件
    # 全局变量:
    #   CONFIG_FILE - 检测到的配置文件路径
    #   RELAY_FILE - 对应的中转配置文件路径
    
    log_info "开始自动检测配置文件路径..."
    local detected_paths=()
    local priority_paths=(
        "${DEFAULT_CONFIG_FILE}"
        "/usr/local/etc/sing-box/config.json"
        "$HOME/.sing-box/config.json"
        "/opt/sing-box/config.json"
        "/var/lib/sing-box/config.json"
        "/etc/sing-box/config.json.bak"
        "/root/.sing-box/config.json"
    )

    for path in "${priority_paths[@]}"; do
        if [[ -f "$path" ]]; then
            detected_paths+=("$path")
            log_info "发现配置文件: $path"
        fi
    done

    local find_results=$(find /etc /usr/local /opt /var/lib /home -maxdepth 5 -name "config.json" -path "*/sing-box/*" 2>/dev/null | head -20)
    if [[ -n "$find_results" ]]; then
        while IFS= read -r path; do
            [[ -n "$path" && ! " ${detected_paths[*]} " =~ " $path " ]] && detected_paths+=("$path") && log_debug "发现配置文件: $path"
        done <<< "$find_results"
    fi

    if [[ ${#detected_paths[@]} -eq 0 ]]; then
        log_warning "未检测到任何配置文件"
        return 1
    elif [[ ${#detected_paths[@]} -eq 1 ]]; then
        CONFIG_FILE="${detected_paths[0]}"
        RELAY_FILE="${CONFIG_FILE%/*}/relays.conf"
        log_success "自动选择配置文件: ${CONFIG_FILE}"
        save_detection_result "${CONFIG_FILE}" "${RELAY_FILE}" "auto_single"
        return 0
    else
        log_info "发现 ${#detected_paths[@]} 个配置文件，选择优先级最高的"
        CONFIG_FILE="${detected_paths[0]}"
        RELAY_FILE="${CONFIG_FILE%/*}/relays.conf"
        save_detection_result "${CONFIG_FILE}" "${RELAY_FILE}" "auto_multi"
        for i in "${!detected_paths[@]}"; do
            [[ $i -gt 0 ]] && log_debug "候选配置文件: ${detected_paths[$i]}"
        done
        return 0
    fi
}

save_detection_result() {
    mkdir -p "${CONFIG_DIR}"
    cat > "${AUTO_DETECT_FILE}" << EOF
# 自动检测配置 - 请勿手动修改
# 最后检测时间: $(date)
# 检测方式: $3
AUTO_DETECTED_CONFIG="$1"
AUTO_DETECTED_RELAY="$2"
DETECTION_TIMESTAMP=$(date +%s)
DETECTION_COUNT=1
EOF
    log_info "自动检测配置已保存"
}

save_last_success() {
    mkdir -p "${CONFIG_DIR}"
    cat > "${LAST_SUCCESS_FILE}" << EOF
# 最后成功配置记录
LAST_CONFIG_FILE="${CONFIG_FILE}"
LAST_RELAY_FILE="${RELAY_FILE}"
LAST_SUCCESS_TIME=$(date +%s)
EOF
}

load_auto_detect_config() {
    if [[ -f "${AUTO_DETECT_FILE}" ]]; then
        source "${AUTO_DETECT_FILE}"
        if [[ -n "$AUTO_DETECTED_CONFIG" && -f "$AUTO_DETECTED_CONFIG" ]]; then
            CONFIG_FILE="$AUTO_DETECTED_CONFIG"
            RELAY_FILE="${AUTO_DETECTED_RELAY:-${CONFIG_FILE%/*}/relays.conf}"
            log_info "加载自动检测配置: ${CONFIG_FILE}"
            return 0
        else
            log_warning "自动检测配置文件存在但内容无效"
            rm -f "${AUTO_DETECT_FILE}"
        fi
    fi
    return 1
}

load_last_success_config() {
    if [[ -f "${LAST_SUCCESS_FILE}" ]]; then
        source "${LAST_SUCCESS_FILE}"
        if [[ -n "$LAST_CONFIG_FILE" && -f "$LAST_CONFIG_FILE" ]]; then
            CONFIG_FILE="$LAST_CONFIG_FILE"
            RELAY_FILE="${LAST_RELAY_FILE:-${CONFIG_FILE%/*}/relays.conf}"
            log_info "恢复上次成功配置: ${CONFIG_FILE}"
            return 0
        fi
    fi
    return 1
}

validate_config_file() {
    # 验证配置文件的完整性和有效性
    # 参数:
    #   $1 - 配置文件路径
    # 返回值:
    #   0 - 验证通过
    #   1 - 验证失败
    # 全局变量:
    #   CONFIG_VALID - 设置为 true 或 false
    
    local file="$1"
    log_info "验证配置文件: ${file}"
    CONFIG_VALID=false

    if [[ ! -f "$file" ]]; then
        log_error "配置文件不存在: ${file}"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        log_error "配置文件无法读取: ${file}"
        return 1
    fi

    local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if [[ "$file_size" -lt 10 ]]; then
        log_error "配置文件为空或过小: ${file} (${file_size} bytes)"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        log_warning "jq 未安装，跳过 JSON 验证"
        CONFIG_VALID=true
        return 0
    fi

    if jq . "$file" >/dev/null 2>&1; then
        local inbounds_count=$(jq '.inbounds | length' "$file" 2>/dev/null || echo "0")
        log_debug "配置文件包含 ${inbounds_count} 个 inbound"
        CONFIG_VALID=true
        log_success "配置文件验证通过"
        return 0
    else
        log_error "配置文件格式错误: ${file}"
        return 1
    fi
}

validate_and_repair_config() {
    local file="$1"
    log_info "开始验证并修复配置文件..."

    if ! validate_config_file "$file"; then
        log_warning "配置文件无效，尝试修复..."
        
        if [[ -f "${file}.bak" ]]; then
            log_info "找到备份文件 ${file}.bak，尝试恢复..."
            if cp "${file}.bak" "$file"; then
                log_success "从备份恢复配置文件成功"
                if validate_config_file "$file"; then
                    return 0
                else
                    log_error "恢复后的文件仍然无效"
                fi
            else
                log_error "从备份恢复失败"
            fi
        fi

        if load_last_success_config; then
            log_info "使用上次成功的配置"
            return validate_config_file "${CONFIG_FILE}"
        fi

        log_error "无法修复配置文件"
        return 1
    fi

    return 0
}

load_path_config() {
    log_info "加载路径配置..."
    
    if [[ -f "${PATH_CONFIG_FILE}" ]]; then
        source "${PATH_CONFIG_FILE}"
        if [[ -n "$CUSTOM_CONFIG_FILE" && -f "$CUSTOM_CONFIG_FILE" ]]; then
            CONFIG_FILE="$CUSTOM_CONFIG_FILE"
            RELAY_FILE="${CUSTOM_RELAY_FILE:-${CONFIG_FILE%/*}/relays.conf}"
            AUTO_DETECT_ENABLED=0
            log_info "加载自定义路径配置: ${CONFIG_FILE}"
            
            if ! validate_and_repair_config "${CONFIG_FILE}"; then
                log_warning "自定义路径配置无效，回退到自动检测"
                AUTO_DETECT_ENABLED=1
                load_auto_detect_config || detect_config_paths
                validate_and_repair_config "${CONFIG_FILE}"
            fi
        else
            log_warning "自定义路径配置无效，回退到自动检测"
            AUTO_DETECT_ENABLED=1
            load_auto_detect_config || detect_config_paths
            validate_and_repair_config "${CONFIG_FILE}"
        fi
    else
        load_auto_detect_config || detect_config_paths
        validate_and_repair_config "${CONFIG_FILE}"
    fi
}

save_path_config() {
    mkdir -p "${CONFIG_DIR}"
    cat > "${PATH_CONFIG_FILE}" << EOF
CUSTOM_CONFIG_FILE="${CONFIG_FILE}"
CUSTOM_RELAY_FILE="${RELAY_FILE}"
CONFIG_SAVED_TIME=$(date +%s)
EOF
    rm -f "${AUTO_DETECT_FILE}"
    AUTO_DETECT_ENABLED=0
    log_success "路径配置已保存到 ${PATH_CONFIG_FILE}"
}

record_recovery_action() {
    local action="$1"
    local result="$2"
    local details="$3"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERY] $action - $result - $details" >> "${RECOVERY_HISTORY_FILE}" 2>/dev/null || true
}

auto_recovery() {
    # 自动恢复机制 - 检测并修复系统问题
    # 处理场景:
    #   - 配置目录不存在
    #   - 配置文件无效或损坏
    #   - 依赖缺失 (jq, curl, openssl)
    #   - 中转配置文件缺失
    # 返回值:
    #   0 - 恢复成功或无需恢复
    #   1 - 无法恢复关键问题
    
    log_info "启动自动恢复机制..."
    local recovery_steps=0
    local recovery_actions=""

    if [[ ! -d "${CONFIG_DIR}" ]]; then
        log_warning "配置目录不存在，创建目录"
        mkdir -p "${CONFIG_DIR}"
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 创建配置目录;"
        record_recovery_action "CREATE_DIR" "SUCCESS" "${CONFIG_DIR}"
    fi

    if ! validate_config_file "${CONFIG_FILE}"; then
        log_warning "当前配置文件无效，尝试重新检测..."
        
        if load_last_success_config && validate_config_file "${CONFIG_FILE}"; then
            recovery_steps=$((recovery_steps+1))
            recovery_actions="${recovery_actions} 恢复上次成功配置;"
            record_recovery_action "RESTORE_LAST_SUCCESS" "SUCCESS" "${CONFIG_FILE}"
        elif detect_config_paths && validate_config_file "${CONFIG_FILE}"; then
            recovery_steps=$((recovery_steps+1))
            recovery_actions="${recovery_actions} 重新检测配置文件;"
            record_recovery_action "REDETECT_CONFIG" "SUCCESS" "${CONFIG_FILE}"
        else
            log_error "无法找到有效配置文件"
            record_recovery_action "FIND_CONFIG" "FAILED" "所有检测方法均失败"
            return 1
        fi
    fi

    log_info "检查依赖..."
    check_dependencies

    if ! command -v jq &>/dev/null; then
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 安装 jq;"
        record_recovery_action "INSTALL_JQ" "FAILED" "jq 安装失败"
        log_error "jq 安装失败"
    else
        if [[ ! -f "${AUTO_DETECT_FILE}" ]]; then
            recovery_steps=$((recovery_steps+1))
            recovery_actions="${recovery_actions} 确认 jq 已安装;"
            record_recovery_action "CHECK_JQ" "SUCCESS" "jq 已安装"
        fi
    fi

    if ! command -v curl &>/dev/null; then
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 安装 curl;"
        record_recovery_action "INSTALL_CURL" "FAILED" "curl 安装失败"
    fi

    if ! command -v openssl &>/dev/null; then
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 安装 openssl;"
        record_recovery_action "INSTALL_OPENSSL" "FAILED" "openssl 安装失败"
    fi

    if [[ ! -d "$(dirname "${RELAY_FILE}")" ]]; then
        log_warning "中转配置目录不存在，创建目录"
        mkdir -p "$(dirname "${RELAY_FILE}")"
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 创建中转目录;"
        record_recovery_action "CREATE_RELAY_DIR" "SUCCESS" "$(dirname "${RELAY_FILE}")"
    fi

    if [[ ! -f "${RELAY_FILE}" ]]; then
        log_info "中转配置文件不存在，创建空文件"
        mkdir -p "$(dirname "${RELAY_FILE}")"
        echo "# Sing-box 中转配置文件" > "${RELAY_FILE}"
        recovery_steps=$((recovery_steps+1))
        recovery_actions="${recovery_actions} 创建中转配置文件;"
        record_recovery_action "CREATE_RELAY_FILE" "SUCCESS" "${RELAY_FILE}"
    fi

    if [[ $recovery_steps -gt 0 ]]; then
        log_success "自动恢复完成，修复了 ${recovery_steps} 个问题: ${recovery_actions}"
        save_last_success
    else
        log_info "系统状态正常，无需恢复"
    fi

    return 0
}

check_dependencies() {
    log_info "检查依赖..."
    local missing=()
    local install_success=0

    for cmd in jq curl openssl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
            log_warning "缺失依赖: $cmd"
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "所有依赖已安装"
        return 0
    fi

    log_info "尝试安装缺失依赖: ${missing[*]}"

    if [[ $ALPINE -eq 1 ]]; then
        if command -v apk &>/dev/null; then
            log_info "使用 apk 安装依赖..."
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
            install_success=$?
        fi
    elif command -v apt-get &>/dev/null; then
        log_info "使用 apt-get 安装依赖..."
        if [[ ! -f /var/lib/apt/lists/lock ]]; then
            apt-get update -qq >/dev/null 2>&1
        fi
        apt-get install -y "${missing[@]}" >/dev/null 2>&1
        install_success=$?
    elif command -v dnf &>/dev/null; then
        log_info "使用 dnf 安装依赖..."
        dnf install -y "${missing[@]}" >/dev/null 2>&1
        install_success=$?
    elif command -v yum &>/dev/null; then
        log_info "使用 yum 安装依赖..."
        yum install -y "${missing[@]}" >/dev/null 2>&1
        install_success=$?
    elif command -v zypper &>/dev/null; then
        log_info "使用 zypper 安装依赖..."
        zypper install -y "${missing[@]}" >/dev/null 2>&1
        install_success=$?
    else
        log_error "未找到支持的包管理器"
        return 1
    fi

    if [[ $install_success -eq 0 ]]; then
        log_success "依赖安装完成"
        return 0
    else
        log_error "依赖安装失败，请手动安装: ${missing[*]}"
        return 1
    fi
}

svc_start() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-service sing-box start 2>/dev/null
    else
        systemctl start sing-box
    fi
}

svc_stop() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-service sing-box stop 2>/dev/null
    else
        systemctl stop sing-box
    fi
}

svc_restart() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-service sing-box restart 2>/dev/null
    else
        systemctl restart sing-box
    fi
}

svc_enable() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-update add sing-box default >/dev/null 2>&1
    else
        systemctl enable sing-box >/dev/null 2>&1
    fi
}

svc_disable() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-update del sing-box default >/dev/null 2>&1
    else
        systemctl disable sing-box >/dev/null 2>&1
    fi
}

svc_is_active() {
    if [[ $ALPINE -eq 1 ]]; then
        rc-service sing-box status 2>/dev/null | grep -q 'started'
    else
        systemctl is-active --quiet sing-box
    fi
}

save_relays_to_file() {
    mkdir -p "$(dirname "${RELAY_FILE}")"
    cp "${RELAY_FILE}" "${RELAY_FILE}.bak" 2>/dev/null || true
    
    cat > "${RELAY_FILE}" << 'EOF'
# Sing-box 中转配置文件
# 格式: TAG|DESCRIPTION|JSON_CONFIG
# 警告: 手动修改此文件可能导致配置损坏
EOF
    for i in "${!RELAY_TAGS[@]}"; do
        local tag="${RELAY_TAGS[$i]}"
        local desc="${RELAY_DESCS[$i]}"
        local json="${RELAY_JSONS[$i]}"
        local json_base64=$(echo "$json" | base64 -w0)
        echo "${tag}|${desc}|${json_base64}" >> "${RELAY_FILE}"
    done
    log_success "中转配置已保存"
}

load_relays_from_file() {
    RELAY_TAGS=()
    RELAY_JSONS=()
    RELAY_DESCS=()
    
    if [[ ! -f "${RELAY_FILE}" ]]; then
        log_info "中转配置文件不存在，创建空配置"
        mkdir -p "$(dirname "${RELAY_FILE}")"
        echo "# Sing-box 中转配置文件" > "${RELAY_FILE}"
        return 0
    fi

    local line_num=0
    while IFS='|' read -r tag desc json_base64; do
        line_num=$((line_num+1))
        [[ "$tag" =~ ^#.*$ || -z "$tag" ]] && continue
        
        local json=$(echo "$json_base64" | base64 -d 2>/dev/null)
        if [[ -n "$json" ]]; then
            RELAY_TAGS+=("$tag")
            RELAY_DESCS+=("$desc")
            RELAY_JSONS+=("$json")
        else
            log_warning "第 ${line_num} 行解码失败，跳过"
        fi
    done < "${RELAY_FILE}"
    log_info "加载了 ${#RELAY_TAGS[@]} 个中转配置"
}

load_inbounds_from_config() {
    if ! validate_config_file "${CONFIG_FILE}"; then
        log_error "无法加载配置文件"
        return 1
    fi

    INBOUND_TAGS=()
    INBOUND_PORTS=()
    INBOUND_PROTOS=()
    INBOUND_SNIS=()
    INBOUND_RELAY_TAGS=()

    local inbounds_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null || echo "0")
    [[ "$inbounds_count" -eq 0 ]] && { log_warning "配置文件中没有 inbound"; return 1; }

    for ((i=0; i<inbounds_count; i++)); do
        local inbound=$(jq -c ".inbounds[${i}]" "${CONFIG_FILE}" 2>/dev/null)
        [[ -z "$inbound" ]] && continue

        local tag=$(echo "$inbound" | jq -r '.tag' 2>/dev/null || echo "unknown")
        local port=$(echo "$inbound" | jq -r '.listen_port' 2>/dev/null || echo "0")
        local type=$(echo "$inbound" | jq -r '.type' 2>/dev/null || echo "unknown")

        [[ "$tag" == "shadowsocks-in-"* ]] && continue

        local proto="unknown"
        local sni=""
        if [[ "$tag" == *"vless-in-"* ]]; then
            proto="Reality"
            sni=$(echo "$inbound" | jq -r '.tls.server_name // ""' 2>/dev/null)
        elif [[ "$tag" == *"hy2-in-"* ]]; then
            proto="Hysteria2"
            sni=$(echo "$inbound" | jq -r '.tls.server_name // ""' 2>/dev/null)
        elif [[ "$tag" == *"shadowtls-in-"* ]]; then
            proto="ShadowTLS v3"
            sni=$(echo "$inbound" | jq -r '.handshake.server // ""' 2>/dev/null)
        elif [[ "$tag" == *"socks-in"* ]]; then
            proto="SOCKS5"
        elif [[ "$tag" == *"vless-tls-in-"* ]]; then
            proto="HTTPS"
            sni=$(echo "$inbound" | jq -r '.tls.server_name // ""' 2>/dev/null)
        elif [[ "$tag" == *"anytls-in-"* ]]; then
            proto="AnyTLS"
            sni=$(echo "$inbound" | jq -r '.tls.server_name // ""' 2>/dev/null)
        fi

        [[ -z "$sni" ]] && sni="-"

        INBOUND_TAGS+=("$tag")
        INBOUND_PORTS+=("$port")
        INBOUND_PROTOS+=("$proto")
        INBOUND_SNIS+=("$sni")
        INBOUND_RELAY_TAGS+=("direct")
    done

    local route_rules=$(jq -c '.route.rules[]? // empty' "${CONFIG_FILE}" 2>/dev/null)
    [[ -n "$route_rules" ]] && while IFS= read -r rule; do
        local inbound_array=$(echo "$rule" | jq -r '.inbound[]? // empty' 2>/dev/null)
        local outbound=$(echo "$rule" | jq -r '.outbound // ""' 2>/dev/null)
        [[ -n "$outbound" && "$outbound" != "direct" ]] && while IFS= read -r inbound_tag; do
            for i in "${!INBOUND_TAGS[@]}"; do
                [[ "${INBOUND_TAGS[$i]}" == "$inbound_tag" ]] && INBOUND_RELAY_TAGS[$i]="$outbound" && break
            done
        done <<< "$inbound_array"
    done <<< "$route_rules"

    log_info "加载了 ${#INBOUND_TAGS[@]} 个 inbound 配置"
    return 0
}

generate_config() {
    if ! validate_config_file "${CONFIG_FILE}"; then
        log_error "无法生成配置"
        return 1
    fi

    local outbounds_array=()
    for relay_json in "${RELAY_JSONS[@]}"; do
        outbounds_array+=("$relay_json")
    done
    outbounds_array+=('{"type": "direct", "tag": "direct"}')

    local outbounds="["
    for i in "${!outbounds_array[@]}"; do
        [[ $i -gt 0 ]] && outbounds+=", "
        outbounds+="${outbounds_array[$i]}"
    done
    outbounds+="]"

    local route_rules=()
    local has_relay=0
    for i in "${!INBOUND_TAGS[@]}"; do
        local relay_tag="${INBOUND_RELAY_TAGS[$i]}"
        if [[ "$relay_tag" != "direct" ]]; then
            route_rules+=("{\"inbound\":[\"${INBOUND_TAGS[$i]}\"],\"outbound\":\"${relay_tag}\"}")
            has_relay=1
        fi
    done

    local route_json
    if [[ $has_relay -eq 1 ]]; then
        route_json="{\"rules\":["
        for i in "${!route_rules[@]}"; do
            [[ $i -gt 0 ]] && route_json+=","
            route_json+="${route_rules[$i]}"
        done
        route_json+="],\"final\":\"direct\",\"default_domain_resolver\":\"local\"}"
    else
        route_json="{\"final\":\"direct\",\"default_domain_resolver\":\"local\"}"
    fi

    local temp_config=$(mktemp -t sing-box-relay.XXXXXX)
    if jq --argjson outbounds "$outbounds" --argjson route "$route_json" \
        '.outbounds = $outbounds | .route = $route' "${CONFIG_FILE}" > "$temp_config" 2>/dev/null; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak" 2>/dev/null
        mv "$temp_config" "${CONFIG_FILE}"
        save_last_success
        log_success "配置文件更新完成"
        return 0
    else
        rm -f "$temp_config"
        log_error "配置更新失败"
        return 1
    fi
}

add_relay_link() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ${GREEN}支持的中转协议格式${CYAN}              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} SOCKS5   - ${CYAN}socks5://[user:pass@]host:port${NC}"
    echo -e "${GREEN}2.${NC} HTTP(S)  - ${CYAN}http(s)://[user:pass@]host:port${NC}"
    echo -e "${GREEN}3.${NC} Shadowsocks - ${CYAN}ss://base64(method:pass)@host:port${NC}"
    echo -e "${GREEN}4.${NC} VMess    - ${CYAN}vmess://base64(json)${NC}"
    echo -e "${GREEN}5.${NC} VLESS    - ${CYAN}vless://uuid@host:port?params${NC}"
    echo -e "${GREEN}6.${NC} Trojan   - ${CYAN}trojan://pass@host:port?params${NC}"
    echo -e "${GREEN}7.${NC} Hysteria2 - ${CYAN}hysteria2://pass@host:port?params${NC}"
    echo ""
    echo -e "${YELLOW}提示: 直接粘贴节点分享链接即可自动识别${NC}"
    echo ""
    read -p "粘贴中转链接 (直接回车返回): " RELAY_LINK

    [[ -z "$RELAY_LINK" ]] && { print_info "取消操作"; return 0; }

    local result=1
    if [[ "$RELAY_LINK" =~ ^socks ]]; then
        parse_socks_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^https? ]]; then
        parse_http_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^ss:// ]]; then
        parse_ss_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^vmess:// ]]; then
        parse_vmess_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^vless:// ]]; then
        parse_vless_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^trojan:// ]]; then
        parse_trojan_link "$RELAY_LINK" && result=0
    elif [[ "$RELAY_LINK" =~ ^hysteria2:// ]]; then
        parse_hysteria2_link "$RELAY_LINK" && result=0
    else
        log_error "不支持的链接格式"
    fi

    return $result
}

parse_socks_link() {
    local link="$1"
    [[ "$link" =~ ^socks://([A-Za-z0-9+/=]+) ]] && {
        local decoded=$(echo "${BASH_REMATCH[1]}" | base64 -d 2>/dev/null)
        [[ -z "$decoded" ]] && { log_error "base64 解码失败"; return 1; }
        link="socks5://${decoded}"
    }

    local data=$(echo "$link" | sed 's|socks5\?://||')
    data=$(echo "$data" | cut -d'?' -f1 | cut -d'#' -f1)

    local tag="relay-socks5-${#RELAY_TAGS[@]}"
    local relay_json=""
    local relay_desc=""

    if [[ "$data" =~ @ ]]; then
        local userpass=$(echo "$data" | cut -d'@' -f1)
        local username=$(echo "$userpass" | cut -d':' -f1)
        local password=$(echo "$userpass" | cut -d':' -f2-)
        local server_port=$(echo "$data" | cut -d'@' -f2)
        local server=$(echo "$server_port" | cut -d':' -f1)
        local port=$(echo "$server_port" | cut -d':' -f2)

        [[ ! "$port" =~ ^[0-9]+$ ]] && { log_error "端口无效: ${port}"; return 1; }

        relay_json="{\"type\": \"socks\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"version\": \"5\", \"username\": \"${username}\", \"password\": \"${password}\"}"
        relay_desc="SOCKS5 ${server}:${port} (认证)"
    else
        local server=$(echo "$data" | cut -d':' -f1)
        local port=$(echo "$data" | cut -':' -f2)

        [[ ! "$port" =~ ^[0-9]+$ ]] && { log_error "端口无效: ${port}"; return 1; }

        relay_json="{\"type\": \"socks\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"version\": \"5\"}"
        relay_desc="SOCKS5 ${server}:${port}"
    fi

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "SOCKS5 中转已添加: ${relay_desc}"
    return 0
}

parse_http_link() {
    local link="$1"
    local protocol=$(echo "$link" | cut -d':' -f1)
    local data=$(echo "$link" | sed 's|https\?://||')
    local tls="false"
    [[ "$protocol" == "https" ]] && tls="true"

    local tag="relay-http-${#RELAY_TAGS[@]}"
    local relay_json=""
    local relay_desc=""
    local server=""
    local port=""

    if [[ "$data" =~ @ ]]; then
        local userpass=$(echo "$data" | cut -d'@' -f1)
        local username=$(echo "$userpass" | cut -d':' -f1)
        local password=$(echo "$userpass" | cut -d':' -f2)
        local server_port=$(echo "$data" | cut -d'@' -f2)
        server=$(echo "$server_port" | cut -d':' -f1)
        port=$(echo "$server_port" | cut -d':' -f2 | cut -d'/' -f1 | cut -d'#' -f1 | cut -d'?' -f1)

        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            log_error "端口无效: ${port}，必须是 1-65535 之间的数字"
            return 1
        fi

        relay_json="{\"type\": \"http\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"username\": \"${username}\", \"password\": \"${password}\", \"tls\": {\"enabled\": ${tls}}}"
        relay_desc="${protocol^^} ${server}:${port} (认证)"
    else
        server=$(echo "$data" | cut -d':' -f1)
        port=$(echo "$data" | cut -d':' -f2 | cut -d'/' -f1 | cut -d'#' -f1 | cut -d'?' -f1)

        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            log_error "端口无效: ${port}，必须是 1-65535 之间的数字"
            return 1
        fi

        relay_json="{\"type\": \"http\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"tls\": {\"enabled\": ${tls}}}"
        relay_desc="${protocol^^} ${server}:${port}"
    fi

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "HTTP(S) 中转已添加: ${relay_desc}"
    return 0
}

parse_ss_link() {
    local link="$1"
    local data=$(echo "$link" | sed 's|ss://||' | cut -d'#' -f1)

    [[ ! "$data" =~ @ ]] && { log_error "Shadowsocks 链接格式错误"; return 1; }

    local userinfo=$(echo "$data" | cut -d'@' -f1)
    local server_port=$(echo "$data" | cut -d'@' -f2 | cut -d'?' -f1)
    local server=$(echo "$server_port" | cut -d':' -f1)
    local port=$(echo "$server_port" | cut -d':' -f2)

    local decoded=$(echo "$userinfo" | base64 -d 2>/dev/null)
    [[ -z "$decoded" ]] && { log_error "Shadowsocks 链接解码失败"; return 1; }

    local method=$(echo "$decoded" | cut -d':' -f1)
    local password=$(echo "$decoded" | cut -d':' -f2-)

    local tag="relay-ss-${#RELAY_TAGS[@]}"
    local relay_json="{\"type\": \"shadowsocks\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"method\": \"${method}\", \"password\": \"${password}\"}"
    local relay_desc="Shadowsocks ${server}:${port}"

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "Shadowsocks 中转已添加: ${relay_desc}"
    return 0
}

parse_vmess_link() {
    local link="$1"
    local base64_data=$(echo "$link" | sed 's|vmess://||')
    local json=$(echo "$base64_data" | base64 -d 2>/dev/null)

    [[ -z "$json" ]] && { log_error "VMess 链接解码失败"; return 1; }
    command -v jq &>/dev/null || { log_error "需要 jq 工具"; return 1; }

    local server=$(echo "$json" | jq -r '.add // .address')
    local port=$(echo "$json" | jq -r '.port')
    local uuid=$(echo "$json" | jq -r '.id')
    local alterId=$(echo "$json" | jq -r '.aid // 0')
    local security=$(echo "$json" | jq -r '.scy // "auto"')

    local tag="relay-vmess-${#RELAY_TAGS[@]}"
    local relay_json="{\"type\": \"vmess\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"uuid\": \"${uuid}\", \"alter_id\": ${alterId}, \"security\": \"${security}\"}"
    local relay_desc="VMess ${server}:${port}"

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "VMess 中转已添加: ${relay_desc}"
    return 0
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

    [[ -n "$params" ]] && {
        [[ "$params" =~ security=([^&]+) ]] && security="${BASH_REMATCH[1]}"
        [[ "$params" =~ sni=([^&]+) ]] && sni="${BASH_REMATCH[1]}"
        [[ "$params" =~ flow=([^&]+) ]] && flow="${BASH_REMATCH[1]}"
    }

    local tls_config=""
    [[ "$security" == "tls" || "$security" == "reality" ]] && tls_config=",\n  \"tls\": {\n    \"enabled\": true,\n    \"server_name\": \"${sni}\"\n  }"

    local flow_config=""
    [[ -n "$flow" ]] && flow_config=",\n  \"flow\": \"${flow}\""

    local tag="relay-vless-${#RELAY_TAGS[@]}"
    local relay_json="{\n  \"type\": \"vless\",\n  \"tag\": \"${tag}\",\n  \"server\": \"${server}\",\n  \"server_port\": ${port},\n  \"uuid\": \"${uuid}\"${flow_config}${tls_config}\n}"
    local relay_desc="VLESS ${server}:${port}"

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "VLESS 中转已添加: ${relay_desc}"
    return 0
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
    local relay_json="{\"type\": \"trojan\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"password\": \"${password}\", \"tls\": {\"enabled\": true, \"server_name\": \"${sni}\"}}"
    local relay_desc="Trojan ${server}:${port}"

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "Trojan 中转已添加: ${relay_desc}"
    return 0
}

parse_hysteria2_link() {
    local link="$1"
    local data=$(echo "$link" | sed 's|hysteria2://||' | cut -d'?' -f1)
    local password=$(echo "$data" | cut -d'@' -f1)
    local server_port=$(echo "$data" | cut -d'@' -f2)
    local server=$(echo "$server_port" | cut -d':' -f1)
    local port=$(echo "$server_port" | cut -d':' -f2)

    [[ -z "$password" || -z "$server" || -z "$port" ]] && { log_error "Hysteria2 链接格式错误"; return 1; }

    local params=$(echo "$link" | grep -o '?.*' | sed 's|?||')
    local sni=""
    [[ "$params" =~ sni=([^&]+) ]] && sni="${BASH_REMATCH[1]}"

    local tag="relay-hysteria2-${#RELAY_TAGS[@]}"
    local relay_json="{\"type\": \"hysteria2\", \"tag\": \"${tag}\", \"server\": \"${server}\", \"server_port\": ${port}, \"password\": \"${password}\", \"tls\": {\"enabled\": true, \"server_name\": \"${sni}\", \"insecure\": true}}"
    local relay_desc="Hysteria2 ${server}:${port}"

    RELAY_TAGS+=("$tag")
    RELAY_JSONS+=("$relay_json")
    RELAY_DESCS+=("$relay_desc")
    save_relays_to_file
    log_success "Hysteria2 中转已添加: ${relay_desc}"
    return 0
}

manual_add_node() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${GREEN}手动添加节点${CYAN}                   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}支持的协议类型:${NC}"
    echo -e "  ${GREEN}[1]${NC} Reality"
    echo -e "  ${GREEN}[2]${NC} Hysteria2"
    echo -e "  ${GREEN}[3]${NC} SOCKS5"
    echo -e "  ${GREEN}[4]${NC} ShadowTLS v3"
    echo -e "  ${GREEN}[5]${NC} HTTPS"
    echo -e "  ${GREEN}[6]${NC} AnyTLS"
    echo ""
    read -p "选择协议类型 [1-6]: " proto_choice

    [[ ! "$proto_choice" =~ ^[1-6]$ ]] && { log_error "无效选择"; return 1; }

    local proto=""
    case $proto_choice in
        1) proto="Reality" ;;
        2) proto="Hysteria2" ;;
        3) proto="SOCKS5" ;;
        4) proto="ShadowTLS v3" ;;
        5) proto="HTTPS" ;;
        6) proto="AnyTLS" ;;
    esac

    echo ""
    read -p "监听端口: " port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_error "端口无效，必须是 1-65535 之间的数字"
        return 1
    fi

    read -p "SNI域名 (留空使用 time.is): " sni
    [[ -z "$sni" ]] && sni="time.is"

    local tag="${proto,,}-in-${port}"

    local inbound_json=""
    case $proto in
        "Reality")
            read -p "UUID (留空自动生成): " uuid
            [[ -z "$uuid" ]] && uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(openssl rand -hex 16)")
            read -p "Public Key: " pbk
            [[ -z "$pbk" ]] && { log_error "Public Key 不能为空"; return 1; }
            read -p "Short ID (留空自动生成): " sid
            [[ -z "$sid" ]] && sid=$(openssl rand -hex 8 2>/dev/null)

            inbound_json="{\"type\": \"vless\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"users\": [{\"uuid\": \"${uuid}\", \"flow\": \"xtls-rprx-vision\"}], \"tls\": {\"enabled\": true, \"server_name\": \"${sni}\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"${sni}\", \"server_port\": 443}, \"private_key\": \"${pbk}\", \"short_id\": [\"${sid}\"]}}}"
            ;;
        "Hysteria2")
            read -p "密码 (留空自动生成): " hy2_pass
            [[ -z "$hy2_pass" ]] && hy2_pass=$(openssl rand -hex 16 2>/dev/null)

            inbound_json="{\"type\": \"hysteria2\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"users\": [{\"password\": \"${hy2_pass}\"}], \"tls\": {\"enabled\": true, \"alpn\": [\"h3\"], \"server_name\": \"${sni}\"}}"
            ;;
        "SOCKS5")
            read -p "用户名 (留空无认证): " socks_user
            read -p "密码: " socks_pass

            if [[ -n "$socks_user" && -n "$socks_pass" ]]; then
                inbound_json="{\"type\": \"socks\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"users\": [{\"username\": \"${socks_user}\", \"password\": \"${socks_pass}\"}]}"
            else
                inbound_json="{\"type\": \"socks\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}}"
            fi
            ;;
        "ShadowTLS v3")
            read -p "Shadowsocks 密码 (留空自动生成): " ss_pass
            [[ -z "$ss_pass" ]] && ss_pass=$(openssl rand -hex 16 2>/dev/null)
            read -p "ShadowTLS 密码 (留空自动生成): " stls_pass
            [[ -z "$stls_pass" ]] && stls_pass=$(openssl rand -hex 16 2>/dev/null)

            inbound_json="{\"type\": \"shadowtls\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"version\": 3, \"users\": [{\"password\": \"${stls_pass}\"}], \"handshake\": {\"server\": \"${sni}\", \"server_port\": 443}, \"strict_mode\": true, \"detour\": \"shadowsocks-in-${port}\"},{\"type\": \"shadowsocks\", \"tag\": \"shadowsocks-in-${port}\", \"listen\": \"127.0.0.1\", \"network\": \"tcp\", \"method\": \"2022-blake3-aes-128-gcm\", \"password\": \"${ss_pass}\"}"
            ;;
        "HTTPS")
            read -p "UUID (留空自动生成): " https_uuid
            [[ -z "$https_uuid" ]] && https_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(openssl rand -hex 16)")

            inbound_json="{\"type\": \"vless\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"users\": [{\"uuid\": \"${https_uuid}\"}], \"tls\": {\"enabled\": true, \"server_name\": \"${sni}\"}}"
            ;;
        "AnyTLS")
            read -p "密码 (留空自动生成): " anytls_pass
            [[ -z "$anytls_pass" ]] && anytls_pass=$(openssl rand -hex 16 2>/dev/null)

            inbound_json="{\"type\": \"anytls\", \"tag\": \"${tag}\", \"listen\": \"::\", \"listen_port\": ${port}, \"users\": [{\"password\": \"${anytls_pass}\"}], \"tls\": {\"enabled\": true, \"server_name\": \"${sni}\"}}"
            ;;
    esac

    if [[ -n "$inbound_json" ]] && [[ -f "${CONFIG_FILE}" ]] && command -v jq &>/dev/null; then
        local temp_config=$(mktemp -t sing-box-relay.XXXXXX)
        if jq --argjson new_inbound "$inbound_json" '.inbounds += [$new_inbound]' "${CONFIG_FILE}" > "$temp_config" 2>/dev/null; then
            cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak" 2>/dev/null
            mv "$temp_config" "${CONFIG_FILE}"
            save_last_success
            log_success "节点已添加: ${proto} :${port}"
            load_inbounds_from_config
        else
            rm -f "$temp_config"
            log_error "添加节点失败"
            return 1
        fi
    else
        log_error "配置文件不存在或 jq 未安装"
        return 1
    fi

    return 0
}

assign_relay_to_node() {
    [[ ${#INBOUND_TAGS[@]} -eq 0 ]] && { log_warning "当前没有可用的节点"; return 1; }
    [[ ${#RELAY_TAGS[@]} -eq 0 ]] && { log_warning "当前没有中转链接"; return 1; }

    echo ""
    echo -e "${CYAN}选择要配置中转的节点:${NC}"
    for i in "${!INBOUND_TAGS[@]}"; do
        idx=$((i+1))
        local relay_status="${INBOUND_RELAY_TAGS[$i]}"
        local relay_desc="${GREEN}直连${NC}"
        if [[ "$relay_status" != "direct" ]]; then
            for j in "${!RELAY_TAGS[@]}"; do
                [[ "${RELAY_TAGS[$j]}" == "$relay_status" ]] && relay_desc="${YELLOW}${RELAY_DESCS[$j]}${NC}" && break
            done
        fi
        echo -e "  ${GREEN}[${idx}]${NC} ${INBOUND_PROTOS[$i]}:${INBOUND_PORTS[$i]} → ${relay_desc}"
    done
    echo ""
    read -p "请输入节点序号 (输入 0 返回): " node_idx

    [[ "$node_idx" == "0" ]] && return 0
    [[ ! "$node_idx" =~ ^[0-9]+$ ]] || (( node_idx < 1 || node_idx > ${#INBOUND_TAGS[@]} )) && { log_error "无效的节点序号"; return 1; }

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
        log_success "节点已设置为直连"
    elif [[ "$relay_idx" =~ ^[0-9]+$ ]] && (( relay_idx >= 1 && relay_idx <= ${#RELAY_TAGS[@]} )); then
        local r=$((relay_idx-1))
        INBOUND_RELAY_TAGS[$n]="${RELAY_TAGS[$r]}"
        log_success "节点已设置为: ${RELAY_DESCS[$r]}"
    else
        log_error "无效选择"
        return 1
    fi

    if generate_config; then
        svc_restart
        sleep 2
        svc_is_active && log_success "配置已应用，服务已重启" || log_warning "服务启动可能失败"
    fi
}

configure_node_relay() {
    assign_relay_to_node
}

delete_relay() {
    [[ ${#RELAY_TAGS[@]} -eq 0 ]] && { log_warning "当前没有中转链接"; return 0; }

    echo ""
    echo -e "${CYAN}删除中转链接:${NC}"
    echo -e "  ${GREEN}[0]${NC} 删除全部中转"
    for i in "${!RELAY_TAGS[@]}"; do
        idx=$((i+1))
        echo -e "  ${GREEN}[${idx}]${NC} ${RELAY_DESCS[$i]}"
    done
    echo ""
    read -p "请选择 (输入 0 删除全部, -1 取消): " del_idx

    [[ "$del_idx" == "-1" ]] && return 0

    if [[ "$del_idx" == "0" ]]; then
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
            log_success "已删除全部中转配置"
            generate_config && svc_restart && sleep 2
            svc_is_active && log_success "配置已更新" || log_warning "服务启动可能失败"
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
                [[ "${INBOUND_RELAY_TAGS[$i]}" == "$del_tag" ]] && INBOUND_RELAY_TAGS[$i]="direct"
            done

            save_relays_to_file
            log_success "已删除中转: ${del_desc}"
            generate_config && svc_restart && sleep 2
            svc_is_active && log_success "配置已更新" || log_warning "服务启动可能失败"
        fi
    else
        log_error "无效选择"
    fi
}

show_relay_config() {
    echo ""
    echo -e "${CYAN}当前中转配置:${NC}"
    if [[ ${#RELAY_TAGS[@]} -gt 0 ]]; then
        for i in "${!RELAY_TAGS[@]}"; do
            echo -e "\n${PURPLE}[$((i+1))] ${RELAY_DESCS[$i]}${NC}"
            echo "${RELAY_JSONS[$i]}" | jq '.' 2>/dev/null || echo "${RELAY_JSONS[$i]}"
        done
    else
        echo "暂无中转配置"
    fi
    echo ""
}

show_main_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${GREEN}           Sing-Box 中转管理脚本${CYAN}                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}配置文件: ${CONFIG_FILE}${NC}"
    echo -e "${YELLOW}自动检测: ${AUTO_DETECT_ENABLED}${NC}"

    if [[ -f "${CONFIG_FILE}" ]]; then
        if load_inbounds_from_config 2>/dev/null; then
            echo -e "${GREEN}已检测到节点: ${#INBOUND_TAGS[@]} 个${NC}"
        else
            echo -e "${YELLOW}配置文件存在但无法解析节点${NC}"
        fi
    else
        echo -e "${RED}未检测到 sing-box 配置${NC}"
    fi

    echo ""
    echo -e "${YELLOW}中转状态:${NC}"
    if [[ ${#RELAY_TAGS[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}中转链接: ${#RELAY_TAGS[@]} 个${NC}"
        local relay_used=0
        for status in "${INBOUND_RELAY_TAGS[@]}"; do
            [[ "$status" != "direct" ]] && ((relay_used++))
        done
        echo -e "  ${CYAN}使用中转: ${relay_used} 个节点${NC}"
    else
        echo -e "  ${YELLOW}暂无中转配置${NC}"
    fi

    echo ""
    echo -e "  ${GREEN}[1]${NC} 添加中转链接"
    echo -e "  ${GREEN}[2]${NC} 手动添加节点"
    echo -e "  ${GREEN}[3]${NC} 为节点配置中转"
    echo -e "  ${GREEN}[4]${NC} 删除中转链接"
    echo -e "  ${GREEN}[5]${NC} 查看中转配置"
    echo ""
    echo -e "  ${GREEN}[6]${NC} 查看节点列表"
    echo -e "  ${GREEN}[7]${NC} 重新加载配置"
    echo -e "  ${GREEN}[8]${NC} 配置文件路径设置"
    echo ""
    echo -e "  ${GREEN}[0]${NC} 退出"
    echo ""
}

show_nodes() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${GREEN}节点列表${CYAN}                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ ${#INBOUND_TAGS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}暂无节点${NC}"
        echo -e "${CYAN}提示: 请先运行 install.sh 创建节点或使用手动添加${NC}"
    else
        for i in "${!INBOUND_TAGS[@]}"; do
            idx=$((i+1))
            local relay_status="${INBOUND_RELAY_TAGS[$i]}"
            local relay_desc="${GREEN}直连${NC}"
            if [[ "$relay_status" != "direct" ]]; then
                for j in "${!RELAY_TAGS[@]}"; do
                    [[ "${RELAY_TAGS[$j]}" == "$relay_status" ]] && relay_desc="${YELLOW}${RELAY_DESCS[$j]}${NC}" && break
                done
            fi
            echo -e "  ${GREEN}[${idx}]${NC} ${INBOUND_PROTOS[$i]} | 端口: ${INBOUND_PORTS[$i]} | SNI: ${INBOUND_SNIS[$i]}"
            echo -e "       ${CYAN}出站: ${relay_desc}${NC}"
            echo ""
        done
    fi
}

set_custom_path() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${GREEN}配置文件路径设置${CYAN}                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}当前配置:${NC}"
    echo -e "  配置文件: ${CONFIG_FILE}"
    echo -e "  中转文件: ${RELAY_FILE}"
    echo -e "  自动检测: ${AUTO_DETECT_ENABLED}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 使用自动检测模式"
    echo -e "  ${GREEN}[2]${NC} 手动输入自定义路径"
    echo -e "  ${GREEN}[3]${NC} 重置为默认路径"
    echo -e "  ${GREEN}[0]${NC} 返回"
    echo ""
    read -p "请选择 [0-3]: " path_choice

    case $path_choice in
        1)
            log_info "切换到自动检测模式"
            rm -f "${PATH_CONFIG_FILE}"
            AUTO_DETECT_ENABLED=1
            detect_config_paths
            validate_config_file "${CONFIG_FILE}"
            print_success "已切换到自动检测模式"
            ;;
        2)
            echo ""
            read -p "输入配置文件路径: " new_config_path
            [[ -z "$new_config_path" ]] && { print_info "取消操作"; return; }

            if validate_config_file "$new_config_path"; then
                CONFIG_FILE="$new_config_path"
                RELAY_FILE="${new_config_path%/*}/relays.conf"
                save_path_config
                print_success "配置文件路径已更新"
            else
                print_error "无效的配置文件"
            fi
            ;;
        3)
            log_info "重置为默认路径"
            rm -f "${PATH_CONFIG_FILE}"
            rm -f "${AUTO_DETECT_FILE}"
            CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
            RELAY_FILE="${DEFAULT_RELAY_FILE}"
            AUTO_DETECT_ENABLED=1
            print_success "已恢复默认路径"
            ;;
        0) return ;;
        *) print_error "无效选择" ;;
    esac
}

install_relay_script() {
    clear
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${GREEN}安装中转管理功能${CYAN}                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    detect_system
    check_dependencies
    auto_recovery

    mkdir -p "${CONFIG_DIR}"
    mkdir -p /usr/local/bin

    print_info "创建快捷命令 zz..."
    cat > /usr/local/bin/zz << 'EOZZ'
#!/bin/bash
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
RELAY_FILE="${CONFIG_DIR}/relays.conf"
PATH_CONFIG_FILE="${CONFIG_DIR}/relay_path.conf"
AUTO_DETECT_FILE="${CONFIG_DIR}/.auto_detect.conf"

if [[ -f "${PATH_CONFIG_FILE}" ]]; then
    source "${PATH_CONFIG_FILE}"
    [[ -n "$CUSTOM_CONFIG_FILE" ]] && CONFIG_FILE="$CUSTOM_CONFIG_FILE"
    [[ -n "$CUSTOM_RELAY_FILE" ]] && RELAY_FILE="$CUSTOM_RELAY_FILE"
elif [[ -f "${AUTO_DETECT_FILE}" ]]; then
    source "${AUTO_DETECT_FILE}"
    [[ -n "$AUTO_DETECTED_CONFIG" ]] && CONFIG_FILE="$AUTO_DETECTED_CONFIG"
    [[ -n "$AUTO_DETECTED_RELAY" ]] && RELAY_FILE="$AUTO_DETECTED_RELAY"
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")"

if [[ -f "${CONFIG_DIR}/relay.sh" ]]; then
    bash "${CONFIG_DIR}/relay.sh" "$@"
elif [[ -f "${SCRIPT_DIR}/relay.sh" ]]; then
    bash "${SCRIPT_DIR}/relay.sh" "$@"
else
    echo "错误: 找不到 relay.sh"
    exit 1
fi
EOZZ
    chmod +x /usr/local/bin/zz 2>/dev/null

    cp "$SCRIPT_PATH" "${CONFIG_DIR}/relay.sh" 2>/dev/null
    chmod +x "${CONFIG_DIR}/relay.sh" 2>/dev/null

    touch "${INSTALL_FLAG}"

    log_success "安装完成!"
    echo ""
    echo -e "${GREEN}快捷命令: zz${NC}"
    echo -e "${YELLOW}使用方法:${NC}"
    echo -e "  zz        - 运行中转管理"
    echo -e "  zz install - 重新安装"
    echo -e "  zz uninstall - 卸载"
    echo ""
    read -p "按回车继续..."
}

uninstall_relay_script() {
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║              ${RED}卸载中转管理功能${YELLOW}                ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${RED}警告: 此操作将执行以下操作:${NC}"
    echo -e "  1. 停止 sing-box 服务"
    echo -e "  2. 删除所有中转配置"
    echo -e "  3. 清除中转相关文件"
    echo -e "  4. 移除快捷命令 zz"
    echo ""
    echo -e "${YELLOW}注意: 不会删除节点配置和 sing-box 主程序${NC}"
    echo ""

    read -p "确认卸载? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "取消卸载"; return; }

    print_info "开始卸载..."

    svc_stop 2>/dev/null

    rm -f /usr/local/bin/zz 2>/dev/null
    rm -f "${CONFIG_DIR}/relay.sh" 2>/dev/null
    rm -f "${INSTALL_FLAG}" 2>/dev/null
    rm -f "${PATH_CONFIG_FILE}" 2>/dev/null
    rm -f "${LAST_SUCCESS_FILE}" 2>/dev/null
    rm -f "${RECOVERY_HISTORY_FILE}" 2>/dev/null

    print_success "卸载完成!"
}

parse_link() {
    local link="$1"
    [[ -z "$link" ]] && { log_error "链接为空"; return 1; }

    local result=1

    if [[ "$link" =~ ^socks5?:// ]]; then
        parse_socks_link "$link" && result=0
    elif [[ "$link" =~ ^https?:// ]]; then
        parse_http_link "$link" && result=0
    elif [[ "$link" =~ ^ss:// ]]; then
        parse_ss_link "$link" && result=0
    elif [[ "$link" =~ ^vmess:// ]]; then
        parse_vmess_link "$link" && result=0
    elif [[ "$link" =~ ^vless:// ]]; then
        parse_vless_link "$link" && result=0
    elif [[ "$link" =~ ^trojan:// ]]; then
        parse_trojan_link "$link" && result=0
    elif [[ "$link" =~ ^hysteria2:// ]]; then
        parse_hysteria2_link "$link" && result=0
    else
        log_error "不支持的链接格式"
    fi

    return $result
}

main_menu() {
    local choice
    while true; do
        show_main_menu
        read -p "请选择 [0-8]: " choice
        case $choice in
            1) add_relay_link ;;
            2) manual_add_node ;;
            3) configure_node_relay ;;
            4) delete_relay ;;
            5) show_relay_config ;;
            6) show_nodes ;;
            7) reload_config ;;
            8) set_custom_path ;;
            0) echo "再见!"; exit 0 ;;
            *) print_error "无效选择" ;;
        esac
        echo ""
        read -p "按回车继续..."
    done
}

initialize_and_run() {
    detect_system

    if [[ $# -gt 0 ]]; then
        case "$1" in
            install) install_relay_script; exit 0 ;;
            uninstall) uninstall_relay_script; exit 0 ;;
            detect) detect_config_paths; validate_config_file "${CONFIG_FILE}"; exit $? ;;
            list) load_inbounds_from_config; show_nodes; exit 0 ;;
            repair) auto_recovery; exit $? ;;
            add) shift; add_relay_link "$@"; exit $? ;;
            *) echo "未知参数: $1"; echo "使用 -h 查看帮助"; exit 1 ;;
        esac
    fi

    auto_recovery || true
    load_relays_from_file
    load_inbounds_from_config 2>/dev/null || true
    main_menu
}

initialize_and_run "$@"
