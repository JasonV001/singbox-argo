#!/bin/bash

# 鏍稿績鐜瀹氫箟
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SINGBOX_DIR="/usr/local/etc/sing-box"

# [鏁村悎鏂规] 瑙ｆ瀽鍣ㄦ牳蹇冭В鐮佸嚱鏁?(鐙珛瀹炵幇锛屼笉渚濊禆澶栭儴)
_url_decode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

if ! command -v jq &>/dev/null; then
    echo '{"error": "缂哄皯 jq 渚濊禆"}'
    exit 1
fi

# 瑙ｆ瀽鍣ㄤ娇鐢ㄧ殑 URL 瑙ｇ爜缁熶竴鐢变富鑴氭湰鎴栫嫭绔嬪疄鐜版彁渚?_decode() { _url_decode "$1"; }

_get_param() {
    local params="$1"
    local key="$2"
    echo "$params" | sed -n "s/.*[\?&]${key}=\([^&]*\).*/\1/p"
}

_strip_ipv6_brackets() {
    local host="$1"
    if [[ "$host" =~ ^\[(.*)\]$ ]]; then
        host="${BASH_REMATCH[1]}"
    fi
    echo "$host"
}

_split_host_port() {
    local input="$1"
    local host=""
    local port=""

    input="${input%%\?*}"

    if [[ "$input" =~ ^(\[[^]]+\]):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$input" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    host=$(_strip_ipv6_brackets "$host")
    printf '%s\t%s\n' "$host" "$port"
}

# 瀹夊叏銆佹棤渚濊禆鍦拌В鐮?URL Safe Base64 骞朵笖鑷姩琛ラ綈 Padding
_decode_base64_urlsafe() {
    local input="$1"
    # 鍘婚櫎澶氫綑鐨勬崲琛岀鍜屾棤鏁堢┖鏍?    input=$(echo -n "$input" | tr -d ' \n\r')
    
    # 绾?Shell 鐜涓嬪皢 URL-Safe 瀛楃 (- 鍜?_) 杞负鏍囧噯 Base64 瀛楃 (+ 鍜?/)
    local safe_str=$(echo -n "$input" | tr -- '-_' '+/')
    
    # 鏅鸿兘鎺㈡祴鍜岃ˉ鍏ㄤ涪澶辩殑绛変簬鍙?(Padding)
    local pad=$(( 4 - (${#safe_str} % 4) ))
    if [ "$pad" -ne 4 ]; then
        local _i=0
        while [ $_i -lt $pad ]; do safe_str+="="; _i=$((_i+1)); done
    fi
    
    # 浜ょ粰鍘熺敓绯荤粺鍋氬畨鍏ㄧ殑鏍囧噯瑙ｇ爜
    echo -n "$safe_str" | base64 -d 2>/dev/null
}


# 瑙ｆ瀽 VLESS
_parse_vless() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    local regex="vless://([^@]+)@${host_regex}:([0-9]+)\??([^#]*)#?(.*)"
    if [[ $link =~ $regex ]]; then
        local uuid="${BASH_REMATCH[1]}"
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[2]}")
        local port="${BASH_REMATCH[3]}"
        local params="${BASH_REMATCH[4]}"
        local name=$(_decode "${BASH_REMATCH[5]}")

        local flow=$(_get_param "$params" "flow")
        local security=$(_get_param "$params" "security")
        local sni=$(_get_param "$params" "sni")
        [ -z "$sni" ] && sni=$(_get_param "$params" "servername")
        local pbk=$(_get_param "$params" "pbk")
        local sid=$(_get_param "$params" "sid")
        local fp=$(_get_param "$params" "fp")
        local type=$(_get_param "$params" "type")
        local path=$(_decode "$(_get_param "$params" "path")")
        local host=$(_get_param "$params" "host")

        local outbound=$(jq -n \
            --arg type "vless" \
            --arg tag "proxy" \
            --arg server "$server" \
            --argjson port "$port" \
            --arg uuid "$uuid" \
            --arg flow "${flow:-""}" \
            '{type:$type, tag:$tag, server:$server, server_port:$port, uuid:$uuid, flow:$flow}')

        [ "$type" == "ws" ] && outbound=$(echo "$outbound" | jq --arg path "${path:-"/"}" --arg host "$host" '.transport = {type:"ws", path:$path, headers:{Host:$host}}')
        
        local target_sni="${sni:-$host}"
        target_sni="${target_sni:-$server}"
        
        if [ "$security" == "reality" ]; then
            outbound=$(echo "$outbound" | jq --arg sni "$target_sni" --arg pbk "$pbk" --arg sid "$sid" --arg fp "${fp:-"chrome"}" \
                '.tls = {enabled:true, server_name:$sni, reality:{enabled:true, public_key:$pbk, short_id:$sid}, utls:{enabled:true, fingerprint:$fp}}')
        elif [ "$security" == "tls" ]; then
            outbound=$(echo "$outbound" | jq --arg sni "$target_sni" --arg fp "${fp:-"chrome"}" \
                '.tls = {enabled:true, server_name:$sni, utls:{enabled:true, fingerprint:$fp}}')
        fi
        echo "$outbound"
    fi
}

# 瑙ｆ瀽 VMess
_parse_vmess() {
    local link="${1#vmess://}"
    local decoded=$(_decode_base64_urlsafe "$link")
    [ -z "$decoded" ] && { echo '{"error": "Base64瑙ｇ爜澶辫触"}'; return; }
    
    local server=$(echo "$decoded" | jq -r '.add')
    server=$(_strip_ipv6_brackets "$server")
    local port=$(echo "$decoded" | jq -r '.port')
    local uuid=$(echo "$decoded" | jq -r '.id')
    local net=$(echo "$decoded" | jq -r '.net // "tcp"')
    local tls=$(echo "$decoded" | jq -r '.tls // ""')
    local path=$(echo "$decoded" | jq -r '.path // "/"')
    local host=$(echo "$decoded" | jq -r '.host // ""')
    local sni=$(echo "$decoded" | jq -r '.sni // ""')

    local outbound=$(jq -n --arg s "$server" --argjson p "$port" --arg u "$uuid" \
        '{type:"vmess", tag:"proxy", server:$s, server_port:$p, uuid:$u, security:"auto"}')

    local target_sni="${sni:-$host}"
    target_sni="${target_sni:-$server}"

    [ "$tls" == "tls" ] && outbound=$(echo "$outbound" | jq --arg sni "$target_sni" '.tls = {enabled:true, server_name:$sni}')
    [ "$net" == "ws" ] && outbound=$(echo "$outbound" | jq --arg path "$path" --arg host "$host" '.transport = {type:"ws", path:$path, headers:{Host:$host}}')
    
    echo "$outbound"
}

# 瑙ｆ瀽 Trojan
_parse_trojan() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    local regex="trojan://([^@]+)@${host_regex}:([0-9]+)\??([^#]*)#?(.*)"
    if [[ $link =~ $regex ]]; then
        local password="${BASH_REMATCH[1]}"
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[2]}")
        local port="${BASH_REMATCH[3]}"
        local params="${BASH_REMATCH[4]}"
        local name=$(_decode "${BASH_REMATCH[5]}")

        local sni=$(_get_param "$params" "sni")
        local type=$(_get_param "$params" "type")
        local path=$(_decode "$(_get_param "$params" "path")")
        local host=$(_get_param "$params" "host")

        local outbound=$(jq -n --arg s "$server" --argjson p "$port" --arg pw "$password" \
            '{type:"trojan", tag:"proxy", server:$s, server_port:$p, password:$pw}')

        [ "$type" == "ws" ] && outbound=$(echo "$outbound" | jq --arg path "${path:-"/"}" --arg host "$host" '.transport = {type:"ws", path:$path, headers:{Host:$host}}')
        
        local target_sni="${sni:-$host}"
        target_sni="${target_sni:-$server}"
        outbound=$(echo "$outbound" | jq --arg sni "$target_sni" '.tls = {enabled:true, server_name:$sni}')
        
        echo "$outbound"
    fi
}

# 瑙ｆ瀽 Shadowsocks
_parse_ss() {
    local link="$1"
    local body="${link#ss://}"
    [[ "$body" == *"#"* ]] && body="${body%#*}"
    
    local method_pass server_port
    if [[ "$body" == *"@"* ]]; then
        local userinfo="${body%@*}"
        server_port="${body#*@}"
        # 鍏?URL 瑙ｇ爜 userinfo锛堝鐞?%3A 绛夌紪鐮佸瓧绗︼級
        local decoded_userinfo=$(_url_decode "$userinfo")
        if [[ "$decoded_userinfo" == *":"* ]]; then
            # 宸茬粡鏄槑鏂?method:password 鏍煎紡锛堟垨 URL 缂栫爜鍚庣殑鏄庢枃锛?            method_pass="$decoded_userinfo"
        else
            # 娌℃湁鍐掑彿锛屽彲鑳芥槸 base64 缂栫爜
            method_pass=$(_decode_base64_urlsafe "$userinfo")
        fi
    else
        local decoded=$(_decode_base64_urlsafe "$body")
        method_pass="${decoded%@*}"
        server_port="${decoded#*@}"
    fi

    local split_result
    split_result=$(_split_host_port "$server_port") || { echo '{"error": "鏈嶅姟鍣ㄥ湴鍧€鎴栫鍙ｆ牸寮忛敊璇?}'; return; }
    local server port
    IFS=$'\t' read -r server port <<< "$split_result"

    jq -n --arg s "$server" --argjson p "$port" --arg m "${method_pass%%:*}" --arg pw "${method_pass#*:}" \
        '{type:"shadowsocks", tag:"proxy", server:$s, server_port:$p, method:$m, password:$pw}'
}

# 瑙ｆ瀽 Hysteria2
_parse_hy2() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    local regex="(hysteria2|hy2)://([^@]+)@${host_regex}:([0-9]+)\??([^#]*)#?(.*)"
    if [[ $link =~ $regex ]]; then
        local password=$(_decode "${BASH_REMATCH[2]}")
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[3]}")
        local port="${BASH_REMATCH[4]}"
        local params="${BASH_REMATCH[5]}"
        local sni=$(_get_param "$params" "sni")
        local obfs=$(_get_param "$params" "obfs")
        local opw=$(_get_param "$params" "obfs-password")

        local outbound=$(jq -n --arg s "$server" --argjson p "$port" --arg pw "$password" --arg sni "${sni:-$server}" \
            '{type:"hysteria2", tag:"proxy", server:$s, server_port:$p, password:$pw, tls:{enabled:true, server_name:$sni, insecure:true, alpn:["h3"]}}')
        [ -n "$obfs" ] && outbound=$(echo "$outbound" | jq --arg ot "$obfs" --arg op "$opw" '.obfs = {type:$ot, password:$op}')
        echo "$outbound"
    fi
}

# 瑙ｆ瀽 TUIC
_parse_tuic() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    local regex="tuic://([^:]+):([^@]+)@${host_regex}:([0-9]+)\??([^#]*)#?(.*)"
    if [[ $link =~ $regex ]]; then
        local uuid="${BASH_REMATCH[1]}"
        local password=$(_decode "${BASH_REMATCH[2]}")
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[3]}")
        local port="${BASH_REMATCH[4]}"
        local params="${BASH_REMATCH[5]}"
        local sni=$(_get_param "$params" "sni")
        local cc=$(_get_param "$params" "congestion_control")
        [ -z "$cc" ] && cc="bbr"

        jq -n --arg s "$server" --argjson p "$port" --arg u "$uuid" --arg pw "$password" --arg sni "${sni:-$server}" --arg cc "$cc" \
            '{type:"tuic", tag:"proxy", server:$s, server_port:$p, uuid:$u, password:$pw, congestion_control:$cc, tls:{enabled:true, server_name:$sni, insecure:true, alpn:["h3"]}}'
    fi
}

# 瑙ｆ瀽 AnyTLS
_parse_anytls() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    local regex="anytls://([^@]+)@${host_regex}:([0-9]+)\??([^#]*)#?(.*)"
    if [[ $link =~ $regex ]]; then
        local password=$(_decode "${BASH_REMATCH[1]}")
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[2]}")
        local port="${BASH_REMATCH[3]}"
        local params="${BASH_REMATCH[4]}"
        local sni=$(_get_param "$params" "sni")

        jq -n --arg s "$server" --argjson p "$port" --arg pw "$password" --arg sni "${sni:-$server}" \
            '{type:"anytls", tag:"proxy", server:$s, server_port:$p, password:$pw, tls:{enabled:true, server_name:$sni, insecure:true}}'
    fi
}

# 瑙ｆ瀽 SOCKS5 (鏀寔鏈夎璇佸拰鏃犺璇佷袱绉嶆牸寮?
_parse_socks() {
    local link="$1"
    local host_regex='(\[[^]]+\]|[^:/?#]+)'
    # 鏈夎璇佹牸寮? socks5://user:pass@host:port#name
    local regex_auth="socks5://([^:]+):([^@]+)@${host_regex}:([0-9]+)#?(.*)"
    # 鏃犺璇佹牸寮? socks5://host:port#name
    local regex_noauth="socks5://${host_regex}:([0-9]+)#?(.*)"
    
    if [[ $link =~ $regex_auth ]]; then
        local user="${BASH_REMATCH[1]}"
        local pass="${BASH_REMATCH[2]}"
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[3]}")
        local port="${BASH_REMATCH[4]}"
        
        jq -n --arg s "$server" --argjson p "$port" --arg u "$user" --arg pw "$pass" \
            '{type:"socks", tag:"proxy", server:$s, server_port:$p, version:"5", users:[{username:$u, password:$pw}]}'
    elif [[ $link =~ $regex_noauth ]]; then
        local server=$(_strip_ipv6_brackets "${BASH_REMATCH[1]}")
        local port="${BASH_REMATCH[2]}"
        
        jq -n --arg s "$server" --argjson p "$port" \
            '{type:"socks", tag:"proxy", server:$s, server_port:$p, version:"5"}'
    fi
}

case "$1" in
    vless://*) _parse_vless "$1" ;;
    vmess://*) _parse_vmess "$1" ;;
    trojan://*) _parse_trojan "$1" ;;
    ss://*) _parse_ss "$1" ;;
    hysteria2://*|hy2://*) _parse_hy2 "$1" ;;
    tuic://*) _parse_tuic "$1" ;;
    anytls://*) _parse_anytls "$1" ;;
    socks5://*) _parse_socks "$1" ;;
    *) echo "{\"error\": \"涓嶆敮鎸佺殑鍗忚\"}"; exit 1 ;;
esac
