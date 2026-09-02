#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${AGC_SERVICE_ACCOUNT_JSON:-}" || -z "${AGC_APP_ID:-}" ]]; then
  echo 'AGC_SERVICE_ACCOUNT_JSON and AGC_APP_ID are required.' >&2
  exit 1
fi

create_jwt() {
  node <<'NODE'
  const crypto = require('crypto');
  const account = JSON.parse(process.env.AGC_SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);
  const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${b64({ kid: account.key_id, typ: 'JWT', alg: 'PS256' })}.${b64({
    iss: account.sub_account,
    aud: 'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
    iat: now,
    exp: now + 3600
  })}`;
  const signature = crypto.sign('sha256', Buffer.from(input), {
    key: account.private_key,
    padding: crypto.constants.RSA_PKCS1_PSS_PADDING,
    saltLength: 32
  });
  process.stdout.write(`${input}.${signature.toString('base64url')}`);
NODE
}

jwt="$(create_jwt)"
echo "::add-mask::$jwt"
tmp="${RUNNER_TEMP}/papertodo-agc-inventory-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
mkdir -p "$tmp"

cert_file="$tmp/certificates.json"
status=''
code=''
for payload in \
  '{"certType":2,"fromRecCount":1,"maxReqCount":100}' \
  '{"fromRecCount":1,"maxReqCount":100}' \
  '{}'; do
  status="$(curl --silent --show-error --output "$cert_file" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/cert/list')"
  code="$(jq -r '.ret.code // -1' "$cert_file" 2>/dev/null || echo -1)"
  if [[ "$status" == '200' && "$code" == '0' ]]; then
    break
  fi
done
if [[ "$status" != '200' || "$code" != '0' ]]; then
  echo "AGC certificate-list query failed: HTTP=$status code=$code" >&2
  exit 1
fi

echo '=== AGC release certificate inventory ==='
jq -c '[
  .. | objects
  | select(.certName? != null)
  | {
      id: (.id? // .certId? // null),
      name: .certName,
      type: (.certType? // null),
      status: (.status? // .certStatus? // null),
      expireTime: (.expireTime? // .expirationTime? // .expireDate? // null)
    }
] | unique_by(.id, .name)' "$cert_file"

profile_file="$tmp/profiles.json"
status="$(curl --silent --show-error --output "$profile_file" --write-out '%{http_code}' \
  --header "Authorization: Bearer $jwt" \
  --header "appId: $AGC_APP_ID" \
  --header 'Content-Type: application/json' \
  'https://connect-api.cloud.huawei.com/api/publish/v3/provision/list?fromRecCount=1&maxReqCount=100')"
code="$(jq -r '.ret.code // -1' "$profile_file" 2>/dev/null || echo -1)"
if [[ "$status" != '200' || "$code" != '0' ]]; then
  echo "AGC profile-list query failed: HTTP=$status code=$code" >&2
  exit 1
fi

echo '=== AGC release profile inventory for PaperTodo app ==='
jq -c '[
  .provisionList[]?
  | {
      id: (.id? // .provisionId? // null),
      name: (.provisionName? // null),
      type: (.provisionType? // null),
      certId: (.certId? // null),
      status: (.status? // .provisionStatus? // null),
      expireTime: (.expireTime? // .expirationTime? // .expireDate? // null)
    }
]' "$profile_file"
