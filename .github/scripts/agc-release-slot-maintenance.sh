#!/usr/bin/env bash
set -euo pipefail

MAX_RELEASE_CERTIFICATES=3
PAPERTODO_RELEASE_REGEX='^PaperTodo-Release-[0-9]+\.[0-9]+\.[0-9]+-'

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
  local code message
  code="$(jq -r '.ret.code // -1' "$response" 2>/dev/null || echo -1)"
  message="$(jq -r '.ret.msg // empty' "$response" 2>/dev/null || true)"
  if [[ "$status" != '200' || "$code" != '0' ]]; then
    echo "$action failed: HTTP=$status code=$code${message:+ message=$message}" >&2
    exit 1
  fi
}

list_release_certificates() {
  local jwt="$1"
  local output="$2"
  local status code payload
  status=''
  code=''
  for payload in \
    '{"certType":2,"fromRecCount":1,"maxReqCount":100}' \
    '{"fromRecCount":1,"maxReqCount":100}' \
    '{}'; do
    status="$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
      --request POST \
      --header "Authorization: Bearer $jwt" \
      --header 'Content-Type: application/json' \
      --data "$payload" \
      'https://connect-api.cloud.huawei.com/api/publish/v3/cert/list')"
    code="$(jq -r '.ret.code // -1' "$output" 2>/dev/null || echo -1)"
    if [[ "$status" == '200' && "$code" == '0' ]]; then
      return 0
    fi
  done
  echo "AGC release certificate list failed: HTTP=$status code=$code" >&2
  exit 1
}

list_profiles() {
  local jwt="$1"
  local output="$2"
  local status
  status="$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
    --header "Authorization: Bearer $jwt" \
    --header "appId: $AGC_APP_ID" \
    --header 'Content-Type: application/json' \
    'https://connect-api.cloud.huawei.com/api/publish/v3/provision/list?fromRecCount=1&maxReqCount=100')"
  require_success 'AGC profile-list query' "$status" "$output"
}

delete_profile() {
  local jwt="$1"
  local id="$2"
  local output="$3"
  local status
  status="$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    "https://connect-api.cloud.huawei.com/api/publish/v2/provision?id=$id")"
  require_success "AGC rolling profile cleanup ($id)" "$status" "$output"
}

delete_certificate() {
  local jwt="$1"
  local id="$2"
  local output="$3"
  local request status
  request="$(jq -n --arg id "$id" '{certIds: [$id]}')"
  status="$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    'https://connect-api.cloud.huawei.com/api/publish/v2/cert/delete')"
  require_success "AGC rolling certificate cleanup ($id)" "$status" "$output"
}

canonical_release_records() {
  local file="$1"
  jq -c '[
    .. | objects
    | select(.certName? != null)
    | select((.certType? // 2) == 2)
    | {
        id: (.id? // .certId? // null),
        name: .certName,
        createTime: (.createTime? // 0)
      }
    | select(.id != null)
  ] | unique_by(.id)' "$file"
}

jwt="$(create_jwt)"
echo "::add-mask::$jwt"
tmp="${RUNNER_TEMP}/papertodo-agc-release-slot-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
mkdir -p "$tmp"

cert_file="$tmp/release-certificates.json"
list_release_certificates "$jwt" "$cert_file"
records="$(canonical_release_records "$cert_file")"
total="$(jq 'length' <<<"$records")"
echo "AGC release certificate slots in use before this build: $total/$MAX_RELEASE_CERTIFICATES"

while (( total >= MAX_RELEASE_CERTIFICATES )); do
  candidates="$(jq -c --arg regex "$PAPERTODO_RELEASE_REGEX" \
    '[.[] | select((.name // "") | test($regex))] | sort_by(.createTime, .id)' <<<"$records")"
  candidate_count="$(jq 'length' <<<"$candidates")"

  # Never erase the only known PaperTodo release identity just to make room.
  # With the rolling policy, at least the newest previous release is preserved.
  if (( candidate_count <= 1 )); then
    echo "AGC release certificate limit is full, but only $candidate_count managed PaperTodo release certificate is safely reclaimable." >&2
    echo 'Refusing to delete unrelated or the sole remaining PaperTodo release certificate.' >&2
    exit 1
  fi

  oldest="$(jq -c '.[0]' <<<"$candidates")"
  old_id="$(jq -r '.id' <<<"$oldest")"
  old_name="$(jq -r '.name' <<<"$oldest")"
  echo "Reclaiming oldest superseded PaperTodo release slot: $old_name"

  profile_file="$tmp/profiles-$old_id.json"
  list_profiles "$jwt" "$profile_file"
  mapfile -t profile_ids < <(jq -r --arg name "$old_name" \
    '.provisionList[]? | select((.provisionName // "") == $name) | (.id? // .provisionId? // empty)' \
    "$profile_file" | sort -u)
  for profile_id in "${profile_ids[@]}"; do
    delete_profile "$jwt" "$profile_id" "$tmp/delete-profile-$profile_id.json"
  done

  delete_certificate "$jwt" "$old_id" "$tmp/delete-certificate-$old_id.json"

  list_release_certificates "$jwt" "$cert_file"
  records="$(canonical_release_records "$cert_file")"
  total="$(jq 'length' <<<"$records")"
  echo "AGC release certificate slots after rolling cleanup: $total/$MAX_RELEASE_CERTIFICATES"
done

echo 'At least one AGC traditional release certificate slot is available for this formal build.'
