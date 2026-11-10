#!/usr/bin/env bash
set -euo pipefail
umask 077

config=/etc/nginx/sites-available/sk1bid.ru.conf
if [[ $EUID != 0 ]]; then
  echo 'Run this script with sudo on the nginx host.' >&2
  exit 1
fi
if [[ ! -f $config || -L $config ]]; then
  echo "Expected a regular file at $config" >&2
  exit 1
fi
exec 9>/run/lock/paloma-relay-nginx.lock
flock -n 9

work=$(mktemp -d "${config%/*}/.paloma-relay.XXXXXX")
installed=0
cleanup() {
  local status=$?
  trap - EXIT
  if (( installed )); then
    if cmp -s "$config" "$work/candidate"; then
      if mv -f "$work/original" "$config" && nginx -t && systemctl reload nginx; then
        echo 'Restored and reloaded the previous nginx configuration.' >&2
      else
        echo "Automatic rollback failed. Backup: $backup" >&2
        status=1
      fi
    else
      echo "Configuration changed during deployment. Review the live file and backup: $backup" >&2
      status=1
    fi
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -p -- "$config" "$work/original"

python3 - "$work/original" "$work/candidate" <<'PY'
import re
import sys
from pathlib import Path

source, candidate = map(Path, sys.argv[1:])
config = source.read_bytes().decode("utf-8")
# Keep the insertion tied to the direct directives of one server. Quoted
# strings and comments may contain braces that do not delimit nginx blocks.
tokens = list(re.finditer(r'''#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s{};#"' ]+|[{};]''', config))
stack = []
directive = []
matches = []
for token in tokens:
    value = token.group()
    if value.startswith("#"):
        continue
    if value == "{":
        stack.append((directive, []))
        directive = []
    elif value == ";":
        if stack:
            stack[-1][1].append(directive)
        directive = []
    elif value == "}":
        if not stack:
            sys.exit("Unexpected closing brace in nginx configuration.")
        block, directives = stack.pop()
        if [part.group() for part in block] == ["server"]:
            words = [[part.group() for part in line] for line in directives]
            if any(line[:1] == ["server_name"] and "sk1bid.ru" in line[1:] for line in words) and any(
                line[:2] == ["listen", "443"] and "ssl" in line[2:]
                for line in words
            ):
                matches.append((block[0].start(), token.end(), directives))
        directive = []
    else:
        directive.append(token)
if stack or len(matches) != 1:
    sys.exit("Expected exactly one SSL server listening on 443 for sk1bid.ru.")

start, end, directives = matches[0]
block = config[start:end]
snippet = """
    # BEGIN Paloma Morse HTTPS relay
    location ^~ /api/auth/ {
        proxy_pass http://127.0.0.1:3001;
    }

    location = /api/lobbies {
        proxy_pass http://127.0.0.1:3001;
    }

    location ^~ /socket.io/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 90s;
        proxy_send_timeout 90s;
        proxy_buffering off;
    }
    # END Paloma Morse HTTPS relay
"""
if "Paloma Morse HTTPS relay" in config:
    if config.count("Paloma Morse HTTPS relay") == 2 and snippet in block:
        candidate.write_bytes(config.encode("utf-8"))
        sys.exit(0)
    sys.exit("Unexpected existing Paloma marker. Review the configuration.")
if re.search(r"(?m)^\s*location\s+[^\n{]*(?:/api|/socket\.io)", block):
    sys.exit("Existing API or Socket.IO location found. Review the configuration.")
anchors = [
    line[0].start() for line in directives
    if [part.group() for part in line] == ["ssl_prefer_server_ciphers", "off"]
]
if len(anchors) != 1:
    sys.exit("Expected exactly one ssl_prefer_server_ciphers off anchor.")
anchor = re.match(r"ssl_prefer_server_ciphers[ \t]+off;[ \t]*\n", config[anchors[0]:])
if anchor is None:
    sys.exit("The SSL anchor does not have the expected layout.")
insertion = anchors[0] + anchor.end()
candidate.write_bytes((config[:insertion] + snippet + config[insertion:]).encode("utf-8"))
PY

if cmp -s "$work/original" "$work/candidate"; then
  nginx -t
  echo 'Relay HTTPS configuration is already present.'
  exit 0
fi

cmp -s "$config" "$work/original" || { echo 'Configuration changed during preparation.' >&2; exit 1; }
backup=$(mktemp /var/backups/sk1bid.ru.conf.paloma.XXXXXX)
install -m 600 "$work/original" "$backup"
cp -p -- "$work/original" "$work/replacement"
cat "$work/candidate" > "$work/replacement"
installed=1
mv -f "$work/replacement" "$config"
nginx -t
systemctl reload nginx
installed=0
echo "HTTPS relay configured. Backup: $backup"
