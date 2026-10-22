#!/usr/bin/env bash
# 薄安装编排：固定官方工件，使用官方 CLI 注册服务；不修改防火墙。
set -euo pipefail
umask 077
[[ ${EUID} -eq 0 ]] || { echo '请通过管理页命令以 sudo 执行。' >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo '当前已验证安装入口仅支持 Linux x86_64。' >&2; exit 1; }
command -v python3 >/dev/null && command -v curl >/dev/null && command -v systemctl >/dev/null || { echo '需要 python3、curl 和 systemd。' >&2; exit 1; }
config_url=${1:?需要管理页生成的完整接入地址}
base=/opt/homelab/easytier-client
state=/var/lib/homelab-easytier-client
version=2.7.0-318a0b06
service=homelab-easytier-client
# 解析 URL 和版本来源，不把凭据输出到日志。
origin=$(python3 - "$config_url" <<'PY'
import sys,urllib.parse
u=urllib.parse.urlsplit(sys.argv[1])
assert u.scheme=='wss' and u.hostname and not u.username and not u.password and not u.query and not u.fragment
assert u.path.startswith('/config/') and len(u.path.split('/'))==3 and u.path.split('/')[-1]
print('https://'+u.netloc)
PY
)
if [[ -e "$state/installation.json" ]]; then
  echo '该安装入口已执行；为避免覆盖身份，请使用已有服务，升级按维护手册执行。' >&2
  exit 1
fi
[[ ! -e "$base" && ! -L "$base" && ! -e "$state" && ! -L "$state" ]] || { echo '发现既有目录，拒绝覆盖；请先核对原安装。' >&2; exit 1; }
[[ $(systemctl show "$service.service" -p LoadState --value) == not-found ]] || { echo '发现同名服务，拒绝覆盖。' >&2; exit 1; }
python3 - <<'PY'
import socket
with socket.socket() as probe:
 try: probe.bind(('127.0.0.1',15989))
 except OSError: raise SystemExit('本机 RPC 端口已占用，拒绝覆盖现有实例。')
PY
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl --fail --silent --show-error --proto '=https' --tlsv1.2 "$origin/install/artifacts/easytier-linux-x86_64-318a0b06.zip" -o "$tmp/core.zip"
echo 'c4cc1e81c2f65c16b8834fe3b1f1eabd7335dc2cf11568217c85842423121bf2  core.zip' | (cd "$tmp" && sha256sum --check --status)
python3 - "$tmp/core.zip" "$tmp/bin" <<'PY'
import pathlib,sys,zipfile
target=pathlib.Path(sys.argv[2]);target.mkdir()
with zipfile.ZipFile(sys.argv[1]) as z:
 for name in ('easytier-core','easytier-cli'):
  entries=[n for n in z.namelist() if pathlib.PurePosixPath(n).name==name]
  assert len(entries)==1
  (target/name).write_bytes(z.read(entries[0]));(target/name).chmod(0o755)
PY
[[ $("$tmp/bin/easytier-core" --version) == *"$version"* ]]
mkdir -p "$base/releases/$version" "$state/config"
chmod 700 "$state" "$state/config"
cp "$tmp/bin/easytier-core" "$tmp/bin/easytier-cli" "$base/releases/$version/"
ln -s "releases/$version" "$base/current"
machine_id=$(cat /proc/sys/kernel/random/uuid)
python3 - "$state/installation.json" "$machine_id" "$version" <<'PY'
import json,pathlib,sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({'machine_id':sys.argv[2],'version':sys.argv[3],'service':'homelab-easytier-client'})+'\n')
PY
# 官方 CLI 会输出包含 Token 的参数，必须捕获；只报告退出状态。
if ! "$base/current/easytier-cli" service --name "$service" install --core-path "$base/current/easytier-core" --service-work-dir "$state" --core-args --config-server "$config_url" --config-dir "$state/config" --machine-id "$machine_id" --disable-env-parsing --rpc-portal 127.0.0.1:15989 >"$tmp/install.log" 2>&1; then
  echo '官方服务注册失败；保留目录供受限排障，未自动覆盖其他安装。' >&2; exit 1
fi
chmod 600 "/etc/systemd/system/$service.service"
systemctl daemon-reload
if ! "$base/current/easytier-cli" service --name "$service" start >"$tmp/start.log" 2>&1; then
  echo '服务启动失败；保留身份和配置供排障。' >&2; exit 1
fi
systemctl is-active --quiet "$service"
printf '安装完成。设备 UUID：%s；请在管理页核对并批准加入网络。\n' "$machine_id"
