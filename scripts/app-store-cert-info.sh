#!/usr/bin/env bash
# 从证书里取出 App 备案要填的三样东西：公钥 / 签名 MD5 / 签名 SHA-1。
#
# 用法：
#   ./scripts/app-store-cert-info.sh                      # 自动找 Apple Distribution / 3rd Party Mac Developer
#   ./scripts/app-store-cert-info.sh "Apple Development"  # 按名字从钥匙串取
#   ./scripts/app-store-cert-info.sh ~/Downloads/dist.cer # 直接读 .cer / PEM 文件
#
# 备案系统里的「公钥」一般要 Base64 的公钥串；「签名MD5值」是证书的 MD5 指纹。
# 不同接入商对大小写、冒号要求不同，这里把几种写法都打印出来。

set -euo pipefail

TARGET="${1:-}"

pick_from_keychain() {
  local name="$1"
  security find-certificate -a -c "$name" -p 2>/dev/null | head -n 100
}

pem=""
if [[ -z "$TARGET" ]]; then
  for name in "Apple Distribution" "3rd Party Mac Developer Application" "Apple Development"; do
    out="$(pick_from_keychain "$name" || true)"
    if [[ -n "${out// }" ]] && grep -q "BEGIN CERTIFICATE" <<<"$out"; then
      pem="$out"
      echo "# 使用钥匙串里的证书：$name"
      break
    fi
  done
elif [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
  # Xcode 26+ 的分发证书可能是「云端托管」，私钥不在本机钥匙串里，
  # 只能从已签名的 app 里把证书抠出来。
  TMPDIR_CERTS="$(mktemp -d)"
  codesign -d --extract-certificates="$TMPDIR_CERTS/" "$TARGET" >/dev/null 2>&1
  if [[ -s "$TMPDIR_CERTS/0" ]]; then
    pem="$(openssl x509 -inform DER -in "$TMPDIR_CERTS/0" 2>/dev/null)"
    echo "# 从已签名 app 中提取证书：$TARGET"
  fi
  rm -rf "$TMPDIR_CERTS"
elif [[ -f "$TARGET" ]]; then
  if openssl x509 -in "$TARGET" -noout >/dev/null 2>&1; then
    pem="$(cat "$TARGET")"
  else
    pem="$(openssl x509 -inform DER -in "$TARGET" 2>/dev/null)"
  fi
  echo "# 使用文件：$TARGET"
else
  pem="$(pick_from_keychain "$TARGET")"
  echo "# 使用钥匙串里的证书：$TARGET"
fi

if [[ -z "${pem// }" ]]; then
  echo "没找到证书。先在 developer.apple.com 创建 Apple Distribution 证书并双击导入钥匙串。" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "$pem" > "$TMP/cert.pem"

echo
echo "## 证书信息"
openssl x509 -in "$TMP/cert.pem" -noout -subject -issuer -dates -serial \
  | sed 's/^/   /'
team="$(openssl x509 -in "$TMP/cert.pem" -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
echo "   Team ID: ${team:-（未找到）}"

echo
echo "## 公钥（Base64，一行）"
openssl x509 -in "$TMP/cert.pem" -pubkey -noout \
  | openssl pkey -pubin -outform DER 2>/dev/null \
  | openssl base64 -A
echo

echo "## 签名 MD5（证书 MD5 指纹）"
md5="$(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -md5 | sed 's/.*=//')"
echo "   带冒号大写：$md5"
echo "   大写无冒号：$(tr -d ':' <<<"$md5")"
echo "   小写无冒号：$(tr -d ':' <<<"$md5" | tr 'A-Z' 'a-z')"

echo
echo "## 签名 SHA-1（有些接入商要这个而不是 MD5）"
sha1="$(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//')"
echo "   带冒号大写：$sha1"
echo "   大写无冒号：$(tr -d ':' <<<"$sha1")"
echo "   小写无冒号：$(tr -d ':' <<<"$sha1" | tr 'A-Z' 'a-z')"

echo
echo "## 有效期检查"
if openssl x509 -in "$TMP/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
  echo "   证书仍在有效期内 ✅"
else
  echo "   证书已过期 ❌ 备案会因为这个被退回，先换新证书" >&2
fi
