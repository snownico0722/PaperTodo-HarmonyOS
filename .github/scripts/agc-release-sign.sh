#!/usr/bin/env bash

set -euo pipefail

SIGN_DIR="${RUNNER_TEMP}/papertodo-signing-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
RESOURCE_PREFIX_REGEX='^PaperTodo-Test-'
SIGNING_JWT=''
CREATED_CERT_ID=''
CREATED_PROFILE_ID=''
CREATED_RESOURCE_NAME=''
SIGNING_COMPLETE=0

require_signing_secrets() {
  if [[ -z "${AGC_SERVICE_ACCOUNT_JSON:-}" || -z "${AGC_APP_ID:-}" ]]; then
    echo 'A formal package requires AGC_SERVICE_ACCOUNT_JSON and AGC_APP_ID.' >&2
    exit 1
  fi
  node <<'NODE'
  const account = JSON.parse(process.env.AGC_SERVICE_ACCOUNT_JSON);
  for (const field of ['key_id', 'sub_account', 'private_key']) {
    if (!account[field]) {
      throw new Error(`AGC service account is missing ${field}`);
    }
  }
NODE
}

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

require_agc_success() {
  local action="$1"
  local status="$2"
  local response="$3"
  local code
  code="$(jq -r '.ret.code // -1' "$response" 2>/dev/null || echo -1)"
  if [[ "$status" != '200' || "$code" != '0' ]]; then
    echo "$action failed: HTTP=$status code=$code" >&2
    exit 1
  fi
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
  require_agc_success 'AGC profile-list query' "$status" "$output"
}

list_certificates() {
  local jwt="$1"
  local output="$2"
  local status=''
  local code=''
  local payload
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
  echo "AGC certificate-list query failed: HTTP=$status code=$code" >&2
  exit 1
}

delete_profile() {
  local jwt="$1"
  local id="$2"
  local response="$3"
  local status
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    "https://connect-api.cloud.huawei.com/api/publish/v2/provision?id=$id")"
  require_agc_success "AGC profile cleanup ($id)" "$status" "$response"
}

delete_certificates() {
  local jwt="$1"
  local response="$2"
  shift 2
  local ids=("$@")
  local request
  local status
  [[ ${#ids[@]} -gt 0 ]] || return 0
  request="$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s '{certIds: .}')"
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    'https://connect-api.cloud.huawei.com/api/publish/v2/cert/delete')"
  require_agc_success 'AGC certificate cleanup' "$status" "$response"
}

cleanup_failed_signing() {
  local original_status=$?
  trap - EXIT
  if [[ "$original_status" == '0' || "$SIGNING_COMPLETE" == '1' || -z "$SIGNING_JWT" ]]; then
    return "$original_status"
  fi

  set +e
  echo 'Signing failed; removing only resources created by this failed run.' >&2
  local profile_id="$CREATED_PROFILE_ID"
  if [[ -z "$profile_id" && -n "$CREATED_RESOURCE_NAME" ]]; then
    local profile_list="$SIGN_DIR/failed-run-profiles.json"
    local list_status
    list_status="$(curl --silent --show-error --output "$profile_list" --write-out '%{http_code}' \
      --header "Authorization: Bearer $SIGNING_JWT" \
      --header "appId: $AGC_APP_ID" \
      --header 'Content-Type: application/json' \
      'https://connect-api.cloud.huawei.com/api/publish/v3/provision/list?fromRecCount=1&maxReqCount=100')"
    if [[ "$list_status" == '200' && "$(jq -r '.ret.code // -1' "$profile_list" 2>/dev/null)" == '0' ]]; then
      profile_id="$(jq -r --arg name "$CREATED_RESOURCE_NAME" \
        '.provisionList[]? | select(.provisionName == $name) | .id' \
        "$profile_list" | head -n 1)"
    fi
  fi

  if [[ -n "$profile_id" ]]; then
    delete_profile "$SIGNING_JWT" "$profile_id" "$SIGN_DIR/delete-failed-profile.json"
  fi
  if [[ -n "$CREATED_CERT_ID" ]]; then
    delete_certificates "$SIGNING_JWT" "$SIGN_DIR/delete-failed-certificate.json" "$CREATED_CERT_ID"
  fi
  return "$original_status"
}

cleanup_stale() {
  require_signing_secrets
  mkdir -p "$SIGN_DIR"
  local jwt
  jwt="$(create_jwt)"
  echo "::add-mask::$jwt"

  local profile_list="$SIGN_DIR/stale-profiles.json"
  list_profiles "$jwt" "$profile_list"
  mapfile -t profile_ids < <(
    jq -r --arg regex "$RESOURCE_PREFIX_REGEX" \
      '.provisionList[]? | select((.provisionName // "") | test($regex)) | .id' \
      "$profile_list" | sort -u
  )
  echo "Stale PaperTodo CI profiles found: ${#profile_ids[@]}"
  local id
  for id in "${profile_ids[@]}"; do
    delete_profile "$jwt" "$id" "$SIGN_DIR/delete-stale-profile-$id.json"
  done

  local cert_list="$SIGN_DIR/stale-certificates.json"
  list_certificates "$jwt" "$cert_list"
  mapfile -t cert_ids < <(
    jq -r --arg regex "$RESOURCE_PREFIX_REGEX" \
      '.. | objects
       | select(((.certName? // "") | test($regex)))
       | (.id? // .certId? // empty)' \
      "$cert_list" | sort -u
  )
  echo "Stale PaperTodo CI certificates found: ${#cert_ids[@]}"
  delete_certificates "$jwt" "$SIGN_DIR/delete-stale-certificates.json" "${cert_ids[@]}"
}

sign_release() {
  require_signing_secrets
  : "${HOS_SDK_HOME:?HOS_SDK_HOME is required}"
  : "${SOURCE_SHA:?SOURCE_SHA is required}"
  : "${APP_VERSION:?APP_VERSION is required}"
  : "${PACKAGE_BASENAME:?PACKAGE_BASENAME is required}"

  umask 077
  mkdir -p "$SIGN_DIR" package/payload
  local key_alias='papertodo_ci_release'
  local keystore_password="Pt-$(openssl rand -hex 16)-9A"
  local keystore="$SIGN_DIR/release.p12"
  local csr="$SIGN_DIR/release.csr"
  local certificate="$SIGN_DIR/release.cer"
  local profile="$SIGN_DIR/release.p7b"
  echo "::add-mask::$keystore_password"

  keytool -genkeypair \
    -alias "$key_alias" \
    -keyalg EC \
    -groupname secp256r1 \
    -sigalg SHA256withECDSA \
    -dname "C=CN,O=PaperTodo,OU=GitHub CI,CN=$key_alias" \
    -keystore "$keystore" \
    -storetype pkcs12 \
    -validity 9125 \
    -storepass "$keystore_password" \
    -keypass "$keystore_password" \
    -noprompt
  keytool -certreq \
    -alias "$key_alias" \
    -sigalg SHA256withECDSA \
    -keystore "$keystore" \
    -storetype pkcs12 \
    -storepass "$keystore_password" \
    -file "$csr"

  local jwt
  jwt="$(create_jwt)"
  echo "::add-mask::$jwt"
  local resource_name="PaperTodo-Release-${APP_VERSION}-${SOURCE_SHA:0:7}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  printf '%s' "$resource_name" > "$SIGN_DIR/resource-name"
  SIGNING_JWT="$jwt"
  CREATED_RESOURCE_NAME="$resource_name"
  trap cleanup_failed_signing EXIT

  local cert_response="$SIGN_DIR/cert-response.json"
  local cert_request
  local status
  cert_request="$(jq -n --rawfile csr "$csr" --arg certName "$resource_name" \
    '{csr: $csr, certName: $certName, certType: 2}')"
  status="$(curl --silent --show-error --output "$cert_response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$cert_request" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/cert')"
  require_agc_success 'AGC release certificate creation' "$status" "$cert_response"
  local cert_id
  local cert_url
  cert_id="$(jq -r '.certInfo.id // empty' "$cert_response")"
  cert_url="$(jq -r '.certInfo.certDownloadUrl // empty' "$cert_response")"
  [[ -n "$cert_id" && -n "$cert_url" ]]
  CREATED_CERT_ID="$cert_id"
  printf '%s' "$cert_id" > "$SIGN_DIR/cert-id"
  curl --fail --location --silent --show-error "$cert_url" --output "$certificate"

  local profile_response="$SIGN_DIR/profile-response.json"
  local profile_request
  profile_request="$(jq -n \
    --arg provisionName "$resource_name" \
    --arg certId "$cert_id" \
    --arg appId "$AGC_APP_ID" \
    '{provisionName: $provisionName, provisionType: 2, certId: $certId, appId: $appId}')"
  status="$(curl --silent --show-error --output "$profile_response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$profile_request" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/provision')"
  require_agc_success 'AGC release profile creation' "$status" "$profile_response"
  local profile_id
  local profile_url
  profile_id="$(jq -r '.provisionInfo.id // .provisionInfo.provisionId // empty' "$profile_response")"
  profile_url="$(jq -r '.provisionInfo.provisionDownloadUrl // empty' "$profile_response")"
  [[ -n "$profile_url" ]]
  if [[ -n "$profile_id" ]]; then
    CREATED_PROFILE_ID="$profile_id"
    printf '%s' "$profile_id" > "$SIGN_DIR/profile-id"
  fi
  curl --fail --location --silent --show-error "$profile_url" --output "$profile"

  mapfile -t sign_tools < <(
    find "$HOS_SDK_HOME" -type f \
      \( -name 'hap-sign-tool.jar' -o -name 'hap_sign_tool.jar' \) -print | sort
  )
  mapfile -t unsigned_apps < <(
    find . -type f -name '*-unsigned.app' -path '*/build/*' -print | sort
  )
  if [[ ${#sign_tools[@]} -eq 0 || ${#unsigned_apps[@]} -ne 1 ]]; then
    echo "Expected a signing tool and exactly one unsigned APP; tools=${#sign_tools[@]} apps=${#unsigned_apps[@]}." >&2
    exit 1
  fi

  local sign_tool="${sign_tools[0]}"
  local signed_app="package/payload/${PACKAGE_BASENAME}.app"
  java -jar "$sign_tool" sign-app \
    -keyAlias "$key_alias" \
    -signAlg SHA256withECDSA \
    -mode localSign \
    -appCertFile "$certificate" \
    -profileFile "$profile" \
    -inFile "${unsigned_apps[0]}" \
    -keystoreFile "$keystore" \
    -outFile "$signed_app" \
    -keyPwd "$keystore_password" \
    -keystorePwd "$keystore_password" \
    -signCode 1

  java -jar "$sign_tool" verify-app \
    -inFile "$signed_app" \
    -outCertChain "$SIGN_DIR/verified-cert-chain.cer" \
    -outProfile "$SIGN_DIR/verified-profile.p7b"
  [[ -s "$signed_app" ]]
  [[ -s "$SIGN_DIR/verified-cert-chain.cer" ]]
  [[ -s "$SIGN_DIR/verified-profile.p7b" ]]

  (
    cd package/payload
    sha256sum "${PACKAGE_BASENAME}.app" > SHA256SUMS
    sha256sum --check SHA256SUMS
    printf 'version=%s\ncommit=%s\nbuild_mode=release\nsigning=AGC release\nverification=hap-sign-tool verify-app\n' \
      "$APP_VERSION" "$SOURCE_SHA" > BUILD_INFO.txt
    zip -9 "../${PACKAGE_BASENAME}.zip" \
      "${PACKAGE_BASENAME}.app" SHA256SUMS BUILD_INFO.txt
  )
  SIGNING_COMPLETE=1
  echo "Signed and verified formal APP: $signed_app"
}

case "${1:-}" in
  check)
    require_signing_secrets
    ;;
  cleanup-stale)
    cleanup_stale
    ;;
  sign)
    sign_release
    ;;
  *)
    echo 'Usage: agc-release-sign.sh {check|cleanup-stale|sign}' >&2
    exit 2
    ;;
esac
