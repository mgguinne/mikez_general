#!/usr/bin/env bash
# Unwrap one .shortcut / .wflow file into an XML plist.
#
# For AEA1 signed shortcuts: pull SigningPublicKey out of the auth_data,
# wrap it as ASN.1 SubjectPublicKeyInfo PEM, run `aea decrypt -sign-pub`
# to verify the signature and extract the inner Apple Archive, then
# `aa extract` to get Shortcut.wflow. Finally normalize to XML with plutil.
#
# For raw binary plists, just plutil-convert.
#
# Usage: unwrap-shortcut.sh <input> <output-xml-plist>
# Exits non-zero on any failure.

set -euo pipefail

INPUT="${1:?input path required}"
OUTPUT="${2:?output path required}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "macOS only (needs aea, aa, plutil)" >&2
  exit 1
fi

magic="$(head -c 4 "$INPUT" 2>/dev/null || true)"

if [[ "$magic" != "AEA1" ]]; then
  cp "$INPUT" "$OUTPUT"
  plutil -convert xml1 "$OUTPUT"
  exit 0
fi

tmp_pem="$(mktemp)"
tmp_bin="$(mktemp)"
tmp_dir="$(mktemp -d)"
trap 'rm -f "$tmp_pem" "$tmp_bin"; rm -rf "$tmp_dir"' EXIT

# Build a PEM public key from auth_data.SigningPublicKey (raw uncompressed P-256 point).
python3 - "$INPUT" > "$tmp_pem" <<'PY'
import struct, sys, plistlib, base64
with open(sys.argv[1], "rb") as f:
    data = f.read()
auth_size = struct.unpack("<I", data[8:12])[0]
auth = plistlib.loads(data[12:12+auth_size])
raw = auth["SigningPublicKey"]
if len(raw) != 65 or raw[0] != 4:
    sys.exit("SigningPublicKey is not an uncompressed P-256 point")
prefix = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
der = prefix + raw
b64 = base64.b64encode(der).decode()
sys.stdout.write(
    "-----BEGIN PUBLIC KEY-----\n"
    + "\n".join(b64[i:i+64] for i in range(0, len(b64), 64))
    + "\n-----END PUBLIC KEY-----\n"
)
PY

aea decrypt -i "$INPUT" -o "$tmp_bin" -sign-pub "$tmp_pem" >/dev/null 2>&1
aa extract -i "$tmp_bin" -d "$tmp_dir" >/dev/null 2>&1

inner="$tmp_dir/Shortcut.wflow"
if [[ ! -f "$inner" ]]; then
  inner="$(find "$tmp_dir" -type f | head -n1)"
fi
if [[ -z "$inner" || ! -f "$inner" ]]; then
  echo "no extracted plist found in archive" >&2
  exit 1
fi

cp "$inner" "$OUTPUT"
plutil -convert xml1 "$OUTPUT"
