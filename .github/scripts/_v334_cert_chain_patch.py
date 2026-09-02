from pathlib import Path

path = Path('.github/scripts/agc-release-sign.sh')
text = path.read_text()

start = text.index('normalize_certificate_pem() {')
end = text.index('\ncreate_stable_certificate() {', start)
replacement = r'''extract_matching_certificate_from_bundle() {
  local key_file="$1"
  local input="$2"
  local output="$3"
  local candidate_dir="$SIGN_DIR/certificate-candidates"
  local scratch="$SIGN_DIR/certificate-scratch"
  rm -rf "$candidate_dir" "$scratch"
  mkdir -p "$candidate_dir" "$scratch"

  extract_pem_blocks() {
    local source="$1"
    local prefix="$2"
    CERT_SOURCE="$source" CERT_DIR="$candidate_dir" CERT_PREFIX="$prefix" python3 <<'PY'
import os
import re
from pathlib import Path

source = Path(os.environ['CERT_SOURCE'])
out_dir = Path(os.environ['CERT_DIR'])
prefix = os.environ['CERT_PREFIX']
data = source.read_bytes()
blocks = re.findall(br'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', data, re.S)
for index, block in enumerate(blocks, start=1):
    (out_dir / f'{prefix}-{index:03d}.pem').write_bytes(block + b'\n')
PY
  }

  # AGC download URLs may return a PEM bundle, a single DER certificate, or a
  # PKCS#7-style chain. Collect every parseable X.509 certificate rather than
  # assuming the first certificate in the file is the application leaf.
  extract_pem_blocks "$input" raw

  if openssl x509 -inform DER -in "$input" -out "$scratch/single-der.pem" >/dev/null 2>&1; then
    extract_pem_blocks "$scratch/single-der.pem" der
  fi

  if openssl pkcs7 -in "$input" -print_certs -out "$scratch/pkcs7-pem.pem" >/dev/null 2>&1; then
    extract_pem_blocks "$scratch/pkcs7-pem.pem" pkcs7-pem
  fi
  if openssl pkcs7 -inform DER -in "$input" -print_certs -out "$scratch/pkcs7-der.pem" >/dev/null 2>&1; then
    extract_pem_blocks "$scratch/pkcs7-der.pem" pkcs7-der
  fi

  if keytool -printcert -rfc -file "$input" > "$scratch/keytool.pem" 2>/dev/null; then
    extract_pem_blocks "$scratch/keytool.pem" keytool
  fi

  local candidate_count
  candidate_count="$(find "$candidate_dir" -type f -name '*.pem' | wc -l | tr -d ' ')"
  if [[ "$candidate_count" == '0' ]]; then
    echo 'AGC certificate download contained no parseable X.509 certificates.' >&2
    exit 1
  fi

  RELEASE_KEY_FILE="$key_file" RELEASE_CERT_DIR="$candidate_dir" RELEASE_CERT_OUTPUT="$output" node <<'NODE'
  const crypto = require('crypto');
  const fs = require('fs');
  const path = require('path');

  const privateKey = crypto.createPrivateKey(fs.readFileSync(process.env.RELEASE_KEY_FILE));
  const targetJwk = crypto.createPublicKey(privateKey).export({ format: 'jwk' });
  const canonical = jwk => [
    jwk.kty || '',
    jwk.crv || '',
    jwk.x || '',
    jwk.y || '',
    jwk.n || '',
    jwk.e || ''
  ].join(':');
  const targetCanonical = canonical(targetJwk);
  const fingerprint = value => crypto.createHash('sha256').update(value).digest('hex');

  const files = fs.readdirSync(process.env.RELEASE_CERT_DIR)
    .filter(name => name.endsWith('.pem'))
    .sort();
  const unique = new Map();
  for (const name of files) {
    try {
      const cert = new crypto.X509Certificate(fs.readFileSync(path.join(process.env.RELEASE_CERT_DIR, name)));
      const rawHash = crypto.createHash('sha256').update(cert.raw).digest('hex');
      if (!unique.has(rawHash)) {
        unique.set(rawHash, { name, cert, canonical: canonical(cert.publicKey.export({ format: 'jwk' })) });
      }
    } catch (_) {
      // Ignore duplicate extraction artifacts that are not standalone X.509 certs.
    }
  }

  const certificates = [...unique.values()];
  const matches = certificates.filter(item => item.canonical === targetCanonical);
  console.log(`AGC certificate candidates: extracted=${files.length} unique=${certificates.length} matching=${matches.length}`);
  if (matches.length !== 1) {
    console.error('Could not identify exactly one AGC leaf certificate matching the persistent release key.');
    console.error(`persistent_public_fingerprint=${fingerprint(targetCanonical)}`);
    for (let i = 0; i < certificates.length; i++) {
      console.error(`candidate_${i + 1}_public_fingerprint=${fingerprint(certificates[i].canonical)}`);
    }
    process.exit(1);
  }
  fs.writeFileSync(process.env.RELEASE_CERT_OUTPUT, matches[0].cert.toString(), { mode: 0o600 });
  console.log(`Selected matching AGC application certificate from candidate: ${matches[0].name}`);
NODE
}
'''
text = text[:start] + replacement + text[end:]

old = '    normalize_certificate_pem "$certificate_raw" "$certificate_pem"\n    verify_persistent_key_matches_certificate "$key_file" "$certificate_pem"'
new = '    extract_matching_certificate_from_bundle "$key_file" "$certificate_raw" "$certificate_pem"'
if text.count(old) != 2:
    raise SystemExit(f'expected 2 certificate normalization call sites, found {text.count(old)}')
text = text.replace(old, new)

old_export = '''\n  openssl pkcs12 -export \\
    -name "$STABLE_KEY_ALIAS" \\
    -inkey "$key_file" \\
    -in "$certificate_pem" \\
    -out "$keystore" \\
    -passout "pass:$keystore_password"\n'''
if text.count(old_export) != 1:
    raise SystemExit(f'expected one post-AGC PKCS12 rebuild, found {text.count(old_export)}')
text = text.replace(old_export, '\n', 1)

old_app_cert = '    -appCertFile "$certificate_pem" \\\'
new_app_cert = '    -appCertFile "$certificate_raw" \\\'
if text.count(old_app_cert) != 1:
    raise SystemExit(f'expected one appCertFile line, found {text.count(old_app_cert)}')
text = text.replace(old_app_cert, new_app_cert, 1)

path.write_text(text)
