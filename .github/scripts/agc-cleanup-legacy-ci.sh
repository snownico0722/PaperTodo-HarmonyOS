#!/usr/bin/env bash
set -euo pipefail

LEGACY_NAME='PaperTodo-CI-5eab785-33577497009-1'

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

require_success() {
  local action="$1"
  local status="$2"
  local response="$3"
  local code
  code="$(jq -r '.ret.code // -1' "$response" 2>/dev/null || echo -1)"
  if [[ "$status" != '200' || "$code" != '0' ]]; then
    echo "$action failed: HTTP=$status code=$code" >&2
    jq '{ret: .ret}' "$response" >&2 || true
    exit 1
  fi
}

jwt="$(create_jwt)"
echo "::add-mask::$jwt"
tmp="${RUNNER_TEMP}/papertodo-agc-legacy-cleanup-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
mkdir -p "$tmp"

# Profiles must be removed before their certificate.
profiles="$tmp/profiles.json"
status="$(curl --silent --show-error --output "$profiles" --write-out '%{http_code}' \
  --header "Authorization: Bearer $jwt" \
  --header "appId: $AGC_APP_ID" \
  --header 'Content-Type: application/json' \
  'https://connect-api.cloud.huawei.com/api/publish/v3/provision/list?fromRecCount=1&maxReqCount=100')"
require_success 'AGC profile-list query' "$status" "$profiles"
mapfile -t profile_ids < <(jq -r --arg name "$LEGACY_NAME" '.provisionList[]? | select(.provisionName == $name) | (.id // .provisionId // empty)' "$profiles" | sort -u)
echo "Legacy CI profiles to delete: ${#profile_ids[@]}"
for id in "${profile_ids[@]}"; do
  response="$tmp/delete-profile-$id.json"
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    "https://connect-api.cloud.huawei.com/api/publish/v2/provision?id=$id")"
  require_success "AGC legacy profile cleanup ($id)" "$status" "$response"
done

certs="$tmp/certificates.json"
status=''
code=''
for payload in \
  '{"certType":2,"fromRecCount":1,"maxReqCount":100}' \
  '{"fromRecCount":1,"maxReqCount":100}' \
  '{}'; do
  status="$(curl --silent --show-error --output "$certs" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/cert/list')"
  code="$(jq -r '.ret.code // -1' "$certs" 2>/dev/null || echo -1)"
  if [[ "$status" == '200' && "$code" == '0' ]]; then
    break
  fi
done
if [[ "$status" != '200' || "$code" != '0' ]]; then
  echo "AGC certificate-list query failed: HTTP=$status code=$code" >&2
  exit 1
fi
mapfile -t cert_ids < <(jq -r --arg name "$LEGACY_NAME" '.. | objects | select(.certName? == $name) | (.id? // .certId? // empty)' "$certs" | sort -u)
echo "Legacy CI certificates to delete: ${#cert_ids[@]}"
if [[ ${#cert_ids[@]} -gt 0 ]]; then
  request="$(printf '%s\n' "${cert_ids[@]}" | jq -R . | jq -s '{certIds: .}')"
  response="$tmp/delete-certificates.json"
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    'https://connect-api.cloud.huawei.com/api/publish/v2/cert/delete')"
  require_success 'AGC legacy certificate cleanup' "$status" "$response"
fi

echo "Legacy pre-main signing resource cleanup complete: $LEGACY_NAME"
