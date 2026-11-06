#!/bin/sh

umask 077
PORTAL_HOST=192.168.253.3
USERNAME=学号
PASSWORD=密码
TMP=/tmp/campus-login.$$
LOCK=/var/run/campus-login.lock

log() {
	logger -t campus-login "$*"
}

if ! mkdir "$LOCK" 2>/dev/null; then
	exit 0
fi
cleanup() {
	status=$?
	trap - EXIT
	rm -f "$TMP.probe" "$TMP.response"
	rmdir "$LOCK" 2>/dev/null
	exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

portal_url=
if [ "$#" -gt 1 ]; then
	log "Usage: login.sh [portal-url]"
	exit 2
fi
if [ "$#" -eq 1 ]; then
	portal_url=$1
else
	if wget -q -T 8 -O "$TMP.probe" http://neverssl.com; then
		portal_url=$(sed -n "s/.*location.href='\([^']*\)'.*/\1/p" "$TMP.probe" | head -n 1)
	fi
	if [ -z "$portal_url" ]; then
		if wget --no-check-certificate -q -T 8 -O "$TMP.probe" https://www.baidu.com && ! grep -q 'eportal/index.jsp' "$TMP.probe"; then
			exit 0
		fi
		log "No portal redirect and external HTTPS probe failed; will retry later"
		exit 1
	fi
fi

case "$portal_url" in
	http://192.168.253.3/eportal/index.jsp\?*) ;;
	*) log "Unexpected portal URL; refusing to submit credentials"; exit 1 ;;
esac
query=${portal_url#*\?}
if ! printf '%s' "$query" | grep -Eq '^[A-Za-z0-9_&=.%+:/?~-]+$'; then
	log "Portal query contains unsupported characters"
	exit 1
fi

encoded_query=$(printf '%s' "$query" | lua -e '
local value = io.read("*a")
local function encode(text)
	return (text:gsub("([^A-Za-z0-9_.!~*()%-])", function(char)
		return string.format("%%%02X", string.byte(char))
	end))
end
io.write(encode(encode(value)))
') || { log "Failed to encode portal parameters"; exit 1; }

cookie=$(printf 'GET /eportal/index.jsp?%s HTTP/1.0\r\nHost: %s\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n' "$query" "$PORTAL_HOST" |
	nc "$PORTAL_HOST" 80 |
	sed -n 's/^[Ss]et-[Cc]ookie:[[:space:]]*\([^;]*\).*/\1/p' |
	tr -d '\r' | head -n 1)
if [ -z "$cookie" ]; then
	log "Portal did not provide a login session cookie"
	exit 1
fi

body="userId=$USERNAME&password=$PASSWORD&service=&queryString=$encoded_query&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false"
body_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
if ! {
	printf 'POST /eportal/InterFace.do?method=login HTTP/1.1\r\nHost: %s\r\nUser-Agent: Mozilla/5.0\r\nReferer: %s\r\nOrigin: http://%s\r\nCookie: %s\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
		"$PORTAL_HOST" "$portal_url" "$PORTAL_HOST" "$cookie" "$body_length" "$body"
} | nc "$PORTAL_HOST" 80 > "$TMP.response"; then
	log "Portal login request failed; will retry later"
	exit 1
fi

if ! grep -q '"result"[[:space:]]*:[[:space:]]*"success"' "$TMP.response"; then
	log "Portal rejected login; will retry later"
	exit 1
fi

if wget --no-check-certificate -q -T 10 -O "$TMP.probe" https://www.baidu.com && ! grep -q 'eportal/index.jsp' "$TMP.probe"; then
	log "Portal login succeeded; Internet access verified"
	exit 0
fi

log "Portal accepted login but external HTTPS probe failed; will retry later"
exit 1
