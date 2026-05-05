#!/bin/bash
# onekey suoha
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0
for i in `echo ${linux_os[@]}`
do
	if [ $i == $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') ]
	then
		break
	else
		n=$[$n+1]
	fi
done
if [ $n == 5 ]
then
	echo 褰撳墠绯荤粺$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2)娌℃湁閫傞厤
	echo 榛樿浣跨敤APT鍖呯鐞嗗櫒
	n=0
fi
if [ -z $(type -P unzip) ]
then
	${linux_update[$n]}
	${linux_install[$n]} unzip
fi
if [ -z $(type -P curl) ]
then
	${linux_update[$n]}
	${linux_install[$n]} curl
fi
if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') != "Alpine" ]
then
	if [ -z $(type -P systemctl) ]
	then
		${linux_update[$n]}
		${linux_install[$n]} systemctl
	fi
fi


function quicktunnel(){
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
	x86_64 | x64 | amd64 )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
	;;
	i386 | i686 )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
	;;
	armv8 | arm64 | aarch64 )
	echo arm64
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
	;;
	armv7l )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
	;;
	* )
	echo 褰撳墠鏋舵瀯$(uname -m)娌℃湁閫傞厤
	exit
	;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
rm -rf xray.zip
uuid=$(cat /proc/sys/kernel/random/uuid)
urlpath=$(echo $uuid | awk -F- '{print $1}')
port=$[$RANDOM+10000]
if [ $protocol == 1 ]
then
cat>xray/config.json<<EOF
{
	"inbounds": [
		{
			"port": $port,
			"listen": "localhost",
			"protocol": "vmess",
			"settings": {
				"clients": [
					{
						"id": "$uuid",
						"alterId": 0
					}
				]
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
fi
if [ $protocol == 2 ]
then
cat>xray/config.json<<EOF
{
	"inbounds": [
		{
			"port": $port,
			"listen": "localhost",
			"protocol": "vless",
			"settings": {
				"decryption": "none",
				"clients": [
					{
						"id": "$uuid"
					}
				]
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
fi
./xray/xray run>/dev/null 2>&1 &
./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
sleep 1
n=0
while true
do
n=$[$n+1]
clear
echo 绛夊緟cloudflare argo鐢熸垚鍦板潃 宸茬瓑寰?$n 绉?argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [ $n == 15 ]
then
	n=0
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
	else
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
	fi
	rm -rf argo.log
	clear
	echo argo鑾峰彇瓒呮椂,閲嶈瘯涓?	./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
	sleep 1
elif [ -z "$argo" ]
then
	sleep 1
else
	rm -rf argo.log
	break
fi
done
clear
if [ $protocol == 1 ]
then
	echo -e vmess閾炬帴宸茬粡鐢熸垚, www.visa.com.sg 鍙浛鎹负CF浼橀€塈P'\n' > v2ray.txt
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'_tls","tls":"tls","type":"none","v":"2"}' | base64 | awk '{ORS=(NR%76==0?RS:"");}1') >> v2ray.txt
	else
		echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'_tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0) >> v2ray.txt
	fi
	echo -e '\n'绔彛 443 鍙敼涓?2053 2083 2087 2096 8443'\n' >> v2ray.txt
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"80","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"","type":"none","v":"2"}' | base64 | awk '{ORS=(NR%76==0?RS:"");}1') >> v2ray.txt
	else
		echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"80","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"","type":"none","v":"2"}' | base64 -w 0) >> v2ray.txt
	fi
	echo -e '\n'绔彛 80 鍙敼涓?8080 8880 2052 2082 2086 2095 >> v2ray.txt
fi
if [ $protocol == 2 ]
then
	echo -e vless閾炬帴宸茬粡鐢熸垚, www.visa.com.sg 鍙浛鎹负CF浼橀€塈P'\n' > v2ray.txt
	echo 'vless://'$uuid'@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host='$argo'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'_tls' >> v2ray.txt
	echo -e '\n'绔彛 443 鍙敼涓?2053 2083 2087 2096 8443'\n' >> v2ray.txt
	echo 'vless://'$uuid'@www.visa.com.sg:80?encryption=none&security=none&type=ws&host='$argo'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'' >> v2ray.txt
	echo -e '\n'绔彛 80 鍙敼涓?8080 8880 2052 2082 2086 2095 >> v2ray.txt
fi
rm -rf argo.log
cat v2ray.txt
echo -e '\n'淇℃伅宸茬粡淇濆瓨鍦?/root/v2ray.txt,鍐嶆鏌ョ湅璇疯繍琛?cat /root/v2ray.txt
echo -e 娉ㄦ剰锛氭鍝堟ā寮忛噸鍚湇鍔″櫒鍚庡け鏁堬紒锛侊紒
}

function installtunnel(){
#鍒涘缓涓荤洰褰?mkdir -p /opt/suoha/ >/dev/null 2>&1
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
	x86_64 | x64 | amd64 )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
	;;
	i386 | i686 )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
	;;
	armv8 | arm64 | aarch64 )
	echo arm64
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
	;;
	armv71 )
	curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
	curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
	;;
	* )
	echo 褰撳墠鏋舵瀯$(uname -m)娌℃湁閫傞厤
	exit
	;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
mv cloudflared-linux /opt/suoha/
mv xray/xray /opt/suoha/
rm -rf xray xray.zip
uuid=$(cat /proc/sys/kernel/random/uuid)
urlpath=$(echo $uuid | awk -F- '{print $1}')
port=$[$RANDOM+10000]
if [ $protocol == 1 ]
then
cat>/opt/suoha/config.json<<EOF
{
	"inbounds": [
		{
			"port": $port,
			"listen": "localhost",
			"protocol": "vmess",
			"settings": {
				"clients": [
					{
						"id": "$uuid",
						"alterId": 0
					}
				]
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
fi
if [ $protocol == 2 ]
then
cat>/opt/suoha/config.json<<EOF
{
	"inbounds": [
		{
			"port": $port,
			"listen": "localhost",
			"protocol": "vless",
			"settings": {
				"decryption": "none",
				"clients": [
					{
						"id": "$uuid"
					}
				]
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
fi
clear
echo 澶嶅埗涓嬮潰鐨勯摼鎺?鐢ㄦ祻瑙堝櫒鎵撳紑骞舵巿鏉冮渶瑕佺粦瀹氱殑鍩熷悕
echo 鍦ㄧ綉椤典腑鎺堟潈瀹屾瘯鍚庝細缁х画杩涜涓嬩竴姝ヨ缃?/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel login
clear
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel list >argo.log 2>&1
echo -e ARGO TUNNEL褰撳墠宸茬粡缁戝畾鐨勬湇鍔″涓?\n'
sed 1,2d argo.log | awk '{print $2}'
echo -e '\n'鑷畾涔変竴涓畬鏁翠簩绾у煙鍚?渚嬪 xxx.example.com
echo 蹇呴』鏄綉椤甸噷闈㈢粦瀹氭巿鏉冪殑鍩熷悕鎵嶇敓鏁?涓嶈兘涔辫緭鍏?read -p "杈撳叆缁戝畾鍩熷悕鐨勫畬鏁翠簩绾у煙鍚? " domain
if [ -z "$domain" ]
then
	echo 娌℃湁璁剧疆鍩熷悕
	exit
elif [ $(echo $domain | grep "\." | wc -l) == 0 ]
then
	echo 鍩熷悕鏍煎紡涓嶆纭?	exit
fi
name=$(echo $domain | awk -F\. '{print $1}')
if [ $(sed 1,2d argo.log | awk '{print $2}' | grep -w $name | wc -l) == 0 ]
then
	echo 鍒涘缓TUNNEL $name
	/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >argo.log 2>&1
	echo TUNNEL $name 鍒涘缓鎴愬姛
else
	echo TUNNEL $name 宸茬粡瀛樺湪
	if [ ! -f "/root/.cloudflared/$(sed 1,2d argo.log | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json" ]
	then
		echo /root/.cloudflared/$(sed 1,2d argo.log | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json 鏂囦欢涓嶅瓨鍦?		echo 娓呯悊TUNNEL $name
		/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >argo.log 2>&1
		echo 鍒犻櫎TUNNEL $name
		/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel delete $name >argo.log 2>&1
		echo 閲嶅缓TUNNEL $name
		/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >argo.log 2>&1
	else
		echo 娓呯悊TUNNEL $name
		/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >argo.log 2>&1
	fi
fi
echo 缁戝畾 TUNNEL $name 鍒板煙鍚?$domain
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel route dns --overwrite-dns $name $domain >argo.log 2>&1
echo $domain 缁戝畾鎴愬姛
tunneluuid=$(cut -d= -f2 argo.log)
if [ $protocol == 1 ]
then
	echo -e vmess閾炬帴宸茬粡鐢熸垚, www.visa.com.sg 鍙浛鎹负CF浼橀€塈P'\n' >/opt/suoha/v2ray.txt
	echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$domain'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"tls","type":"none","v":"2"}' | base64 -w 0) >>/opt/suoha/v2ray.txt
	echo -e '\n'绔彛 443 鍙敼涓?2053 2083 2087 2096 8443'\n' >>/opt/suoha/v2ray.txt
	echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$domain'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"80","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"","type":"none","v":"2"}' | base64 -w 0) >>/opt/suoha/v2ray.txt
	echo -e '\n'绔彛 80 鍙敼涓?8080 8880 2052 2082 2086 2095'\n' >>/opt/suoha/v2ray.txt
	echo 娉ㄦ剰:濡傛灉 80 8080 8880 2052 2082 2086 2095 绔彛鏃犳硶姝ｅ父浣跨敤 >>/opt/suoha/v2ray.txt
	echo 璇峰墠寰€ https://dash.cloudflare.com/ >>/opt/suoha/v2ray.txt
	echo 妫€鏌ョ鐞嗛潰鏉?SSL/TLS - 杈圭紭璇佷功 - 濮嬬粓浣跨敤HTTPS 鏄惁澶勪簬鍏抽棴鐘舵€?>>/opt/suoha/v2ray.txt
fi
if [ $protocol == 2 ]
then
	echo -e vless閾炬帴宸茬粡鐢熸垚, www.visa.com.sg 鍙浛鎹负CF浼橀€塈P'\n' >/opt/suoha/v2ray.txt
	echo 'vless://'$uuid'@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host='$domain'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'_tls' >>/opt/suoha/v2ray.txt
	echo -e '\n'绔彛 443 鍙敼涓?2053 2083 2087 2096 8443'\n' >>/opt/suoha/v2ray.txt
	echo 'vless://'$uuid'@www.visa.com.sg:80?encryption=none&security=none&type=ws&host='$domain'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'' >>/opt/suoha/v2ray.txt
	echo -e '\n'绔彛 80 鍙敼涓?8080 8880 2052 2082 2086 2095'\n' >>/opt/suoha/v2ray.txt
	echo 娉ㄦ剰:濡傛灉 80 8080 8880 2052 2082 2086 2095 绔彛鏃犳硶姝ｅ父浣跨敤 >>/opt/suoha/v2ray.txt
	echo 璇峰墠寰€ https://dash.cloudflare.com/ >>/opt/suoha/v2ray.txt
	echo 妫€鏌ョ鐞嗛潰鏉?SSL/TLS - 杈圭紭璇佷功 - 濮嬬粓浣跨敤HTTPS 鏄惁澶勪簬鍏抽棴鐘舵€?>>/opt/suoha/v2ray.txt
fi
rm -rf argo.log
cat>/opt/suoha/config.yaml<<EOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json

ingress:
  - hostname:
    service: http://localhost:$port
EOF
if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
cat>/etc/local.d/cloudflared.start<<EOF
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/suoha/config.yaml run $name &
EOF
cat>/etc/local.d/xray.start<<EOF
/opt/suoha/xray run -config /opt/suoha/config.json &
EOF
chmod +x /etc/local.d/cloudflared.start /etc/local.d/xray.start
rc-update add local
/etc/local.d/cloudflared.start >/dev/null 2>&1
/etc/local.d/xray.start >/dev/null 2>&1
else
#鍒涘缓鏈嶅姟
cat>/lib/systemd/system/cloudflared.service<<EOF
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
cat>/lib/systemd/system/xray.service<<EOF
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
systemctl enable cloudflared.service >/dev/null 2>&1
systemctl enable xray.service >/dev/null 2>&1
systemctl --system daemon-reload
systemctl start cloudflared.service
systemctl start xray.service
fi
if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
#鍒涘缓鍛戒护閾炬帴
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
while true
do
if [ \$(ps -ef | grep cloudflared-linux | grep -v grep | wc -l) == 0 ]
then
	argostatus=stop
else
	argostatus=running
fi
if [ \$(ps -ef | grep xray | grep -v grep | wc -l) == 0 ]
then
	xraystatus=stop
else
	xraystatus=running
fi
echo argo \$argostatus
echo xray \$xraystatus
echo 1.绠＄悊TUNNEL
echo 2.鍚姩鏈嶅姟
echo 3.鍋滄鏈嶅姟
echo 4.閲嶅惎鏈嶅姟
echo 5.鍗歌浇鏈嶅姟
echo 6.鏌ョ湅褰撳墠v2ray閾炬帴
echo 0.閫€鍑?read -p "璇烽€夋嫨鑿滃崟(榛樿0): " menu
if [ -z "\$menu" ]
then
	menu=0
fi
if [ \$menu == 1 ]
then
	clear
	while true
	do
		echo ARGO TUNNEL褰撳墠宸茬粡缁戝畾鐨勬湇鍔″涓?		/opt/suoha/cloudflared-linux tunnel list
		echo 1.鍒犻櫎TUNNEL
		echo 0.閫€鍑?		read -p "璇烽€夋嫨鑿滃崟(榛樿0): " tunneladmin
		if [ -z "\$tunneladmin" ]
		then
			tunneladmin=0
		fi
		if [ \$tunneladmin == 1 ]
		then
			read -p "璇疯緭鍏ヨ鍒犻櫎鐨凾UNNEL NAME: " tunnelname
			echo 鏂紑TUNNEL \$tunnelname
			/opt/suoha/cloudflared-linux tunnel cleanup \$tunnelname
			echo 鍒犻櫎TUNNEL \$tunnelname
			/opt/suoha/cloudflared-linux tunnel delete \$tunnelname
		else
			break
		fi
	done
elif [ \$menu == 2 ]
then
	kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	/etc/local.d/cloudflared.start >/dev/null 2>&1
	/etc/local.d/xray.start >/dev/null 2>&1
	clear
	sleep 1
elif [ \$menu == 3 ]
then
	kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	clear
	sleep 2
elif [ \$menu == 4 ]
then
	kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	/etc/local.d/cloudflared.start >/dev/null 2>&1
	/etc/local.d/xray.start >/dev/null 2>&1
	clear
	sleep 1
elif [ \$menu == 5 ]
then
	kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
	rm -rf /opt/suoha /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/suoha ~/.cloudflared
	echo 鎵€鏈夋湇鍔￠兘鍗歌浇瀹屾垚
	echo 褰诲簳鍒犻櫎鎺堟潈璁板綍
	echo 璇疯闂?https://dash.cloudflare.com/profile/api-tokens
	echo 鍒犻櫎鎺堟潈鐨?Argo Tunnel API Token 鍗冲彲
	exit
elif [ \$menu == 6 ]
then
	clear
	cat /opt/suoha/v2ray.txt
elif [ \$menu == 0 ]
then
	echo 閫€鍑烘垚鍔?	exit
fi
done
EOF
else
#鍒涘缓鍛戒护閾炬帴
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
clear
while true
do
echo argo \$(systemctl status cloudflared.service | sed -n '3p')
echo xray \$(systemctl status xray.service | sed -n '3p')
echo 1.绠＄悊TUNNEL
echo 2.鍚姩鏈嶅姟
echo 3.鍋滄鏈嶅姟
echo 4.閲嶅惎鏈嶅姟
echo 5.鍗歌浇鏈嶅姟
echo 6.鏌ョ湅褰撳墠v2ray閾炬帴
echo 0.閫€鍑?read -p "璇烽€夋嫨鑿滃崟(榛樿0): " menu
if [ -z "\$menu" ]
then
	menu=0
fi
if [ \$menu == 1 ]
then
	clear
	while true
	do
		echo ARGO TUNNEL褰撳墠宸茬粡缁戝畾鐨勬湇鍔″涓?		/opt/suoha/cloudflared-linux tunnel list
		echo 1.鍒犻櫎TUNNEL
		echo 0.閫€鍑?		read -p "璇烽€夋嫨鑿滃崟(榛樿0): " tunneladmin
		if [ -z "\$tunneladmin" ]
		then
			tunneladmin=0
		fi
		if [ \$tunneladmin == 1 ]
		then
			read -p "璇疯緭鍏ヨ鍒犻櫎鐨凾UNNEL NAME: " tunnelname
			echo 鏂紑TUNNEL \$tunnelname
			/opt/suoha/cloudflared-linux tunnel cleanup \$tunnelname
			echo 鍒犻櫎TUNNEL \$tunnelname
			/opt/suoha/cloudflared-linux tunnel delete \$tunnelname
		else
			break
		fi
	done
elif [ \$menu == 2 ]
then
	systemctl start cloudflared.service
	systemctl start xray.service
	clear
elif [ \$menu == 3 ]
then
	systemctl stop cloudflared.service
	systemctl stop xray.service
	clear
elif [ \$menu == 4 ]
then
	systemctl restart cloudflared.service
	systemctl restart xray.service
	clear
elif [ \$menu == 5 ]
then
	systemctl stop cloudflared.service
	systemctl stop xray.service
	systemctl disable cloudflared.service
	systemctl disable xray.service
	kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$2}') >/dev/null 2>&1
	kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$2}') >/dev/null 2>&1
	rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha ~/.cloudflared
	systemctl --system daemon-reload
	echo 鎵€鏈夋湇鍔￠兘鍗歌浇瀹屾垚
	echo 褰诲簳鍒犻櫎鎺堟潈璁板綍
	echo 璇疯闂?https://dash.cloudflare.com/profile/api-tokens
	echo 鍒犻櫎鎺堟潈鐨?Argo Tunnel API Token 鍗冲彲
	exit
elif [ \$menu == 6 ]
then
	clear
	cat /opt/suoha/v2ray.txt
elif [ \$menu == 0 ]
then
	echo 閫€鍑烘垚鍔?	exit
fi
done
EOF
fi
chmod +x /opt/suoha/suoha.sh
ln -sf /opt/suoha/suoha.sh /usr/bin/suoha
}

clear
#!/bin/sh

# 鎵撳嵃 ASCII 鑹烘湳
echo "       _       _                              _                "
echo "      | |     | |       ___   _   _    ___   | |__     ____       "
echo "    __| |_____| |_     / __| | | | |  / _ \  | |_ \   / _  |   "
echo "   |__   ______  _|    \__ \ | |_| | | (_) | | | | | | (_| | "
echo "      | |_    | |_     |___/  \___/   \___/  |_| |_|  \____|"
echo "       \__|    \__|"
echo "                                 "
echo -e '\n'娆㈣繋浣跨敤 TT Agro-suoha 涓€閿鍝堣剼鏈?..'\n'
# 鍏朵粬鑴氭湰鍐呭
echo 姊搱妯″紡涓嶉渶瑕佽嚜宸辨彁渚涘煙鍚?浣跨敤CF ARGO QUICK TUNNEL鍒涘缓蹇€熼摼鎺?echo 姊搱妯″紡鍦ㄩ噸鍚垨鑰呰剼鏈啀娆¤繍琛屽悗澶辨晥,濡傛灉闇€瑕佷娇鐢ㄩ渶瑕佸啀娆¤繍琛屽垱寤?echo 瀹夎鏈嶅姟妯″紡,闇€瑕佹湁CF鎵樼鍩熷悕,骞朵笖闇€瑕佹寜鐓ф彁绀烘墜鍔ㄧ粦瀹欰RGO鏈嶅姟
echo 棣栨缁戝畾ARGO鏈嶅姟鍚庡鏋滀笉鎯冲啀娆¤烦杞綉椤电粦瀹?echo 灏嗗凡缁忕粦瀹氱殑绯荤粺鐩綍涓嬬殑 /root/.cloudflared 鏂囦欢澶逛互鍙婂唴瀹?echo 鎷疯礉鑷虫柊绯荤粺涓嬪悓鏍风殑鐩綍,浼氳嚜鍔ㄨ烦杩囩櫥褰曢獙璇?
echo -e 鍩轰簬 Cloudflare Tunnel 鐨勬柊涓€浠ｈ秴杞婚噺绾х┛閫忓伐鍏?echo -e 鏃犻渶鍏綉 IP  鏃犻渶绔彛杞彂  鏋佽嚧闅愯棌  涓撲负 NAT VPS 鎵撻€?
echo -e 娉ㄦ剰锛氭鍝堟ā寮忛噸鍚湇鍔″櫒鍚庡け鏁堬紒锛侊紒

echo -e '\n'TT Cloudflare Tunnel 涓€閿畇uoha鑴氭湰  鏃犻渶鍏綉 IP  鏃犻渶绔彛杞彂 Agro闅ч亾'\n'
echo 1.姊搱妯″紡 鏃犻渶cloudflare鍩熷悕閲嶅惎浼氬け鏁堬紒
echo 2.瀹夎鏈嶅姟 闇€瑕乧loudflare鍩熷悕閲嶅惎涓嶄細澶辨晥锛?echo 3.鍗歌浇鏈嶅姟
echo 4.娓呯┖缂撳瓨
echo 5.绠＄悊鏈嶅姟
echo -e 0.閫€鍑鸿剼鏈?\n'
read -p "璇烽€夋嫨妯″紡(榛樿1):" mode
if [ -z "$mode" ]
then
	mode=1
fi
# 鍦ㄩ€夋嫨瀹夎鏈嶅姟鏃跺啀娆℃鏌?if [ $mode == 2 ]; then
    if [ -f "/usr/bin/suoha" ]; then
        echo "鏈嶅姟宸茬粡瀹夎锛屾鍦ㄨ烦杞埌绠＄悊鑿滃崟..."
        suoha
        exit 0
    fi
    # 缁х画瀹夎娴佺▼...
fi
if [ $mode == 1 ]
then
	read -p "璇烽€夋嫨xray鍗忚(榛樿1.vmess,2.vless):" protocol
	if [ -z "$protocol" ]
	then
		protocol=1
	fi
	if [ $protocol != 1 ] && [ $protocol != 2 ]
	then
		echo 璇疯緭鍏ユ纭殑xray鍗忚
		exit
	fi
	read -p "璇烽€夋嫨argo杩炴帴妯″紡IPV4鎴栬€匢PV6(杈撳叆4鎴?,榛樿4):" ips
	if [ -z "$ips" ]
	then
		ips=4
	fi
	if [ $ips != 4 ] && [ $ips != 6 ]
	then
		echo 璇疯緭鍏ユ纭殑argo杩炴帴妯″紡
		exit
	fi
	isp=$(curl -$ips -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
	else
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
	fi
	rm -rf xray cloudflared-linux v2ray.txt
	quicktunnel
elif [ $mode == 2 ]
then
	read -p "璇烽€夋嫨xray鍗忚(榛樿1.vmess,2.vless):" protocol
	if [ -z "$protocol" ]
	then
		protocol=1
	fi
	if [ $protocol != 1 ] && [ $protocol != 2 ]
	then
		echo 璇疯緭鍏ユ纭殑xray鍗忚
		exit
	fi
	read -p "璇烽€夋嫨argo杩炴帴妯″紡IPV4鎴栬€匢PV6(杈撳叆4鎴?,榛樿4):" ips
	if [ -z "$ips" ]
	then
		ips=4
	fi
	if [ $ips != 4 ] && [ $ips != 6 ]
	then
		echo 璇疯緭鍏ユ纭殑argo杩炴帴妯″紡
		exit
	fi
	isp=$(curl -$ips -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
	else
		systemctl stop cloudflared.service
		systemctl stop xray.service
		systemctl disable cloudflared.service
		systemctl disable xray.service
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
		systemctl --system daemon-reload
	fi
	installtunnel
	cat /opt/suoha/v2ray.txt
	echo 鏈嶅姟瀹夎瀹屾垚,绠＄悊鏈嶅姟璇疯繍琛屽懡浠?suoha
elif [ $mode == 3 ]
then
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
	else
		systemctl stop cloudflared.service
		systemctl stop xray.service
		systemctl disable cloudflared.service
		systemctl disable xray.service
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha ~/.cloudflared
		systemctl --system daemon-reload
	fi
	clear
	echo 鎵€鏈夋湇鍔￠兘鍗歌浇瀹屾垚
	echo 褰诲簳鍒犻櫎鎺堟潈璁板綍
	echo 璇疯闂?https://dash.cloudflare.com/profile/api-tokens
	echo 鍒犻櫎鎺堟潈鐨?Argo Tunnel API Token 鍗冲彲
elif [ $mode == 5 ]
then
    if [ -f "/usr/bin/suoha" ]; then
        suoha
    else
        echo "绠＄悊鏈嶅姟鏈畨瑁咃紝璇峰厛瀹夎鏈嶅姟锛堥€夋嫨妯″紡2锛?
    
    fi

elif [ $mode == 4 ]
then
	if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
	then
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
	else
		kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
		kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
	fi
	rm -rf xray cloudflared-linux v2ray.txt
else
	echo 閫€鍑烘垚鍔?	exit
fi

