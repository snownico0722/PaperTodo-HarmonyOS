#!/usr/bin/env bash

set -euo pipefail

SIGN_DIR="${RUNNER_TEMP}/papertodo-signing-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
RESOURCE_PREFIX_REGEX='^PaperTodo-Test-'
STABLE_RESOURCE_NAME='PaperTodo-Release-Stable-v1'
STABLE_KEY_ALIAS='papertodo_release_stable_v1'
# One-time slot migration target. This is the superseded 3.3.1 release resource;
# 3.3.2 and 3.3.3 are intentionally never matched or deleted automatically.
LEGACY_RELEASE_SLOT_NAME='PaperTodo-Release-3.3.1-578f89a-33580158946-1'
CREATED_CERT_ID=''
CREATED_PROFILE_ID=''
BOOTSTRAP_COMPLETE=0

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

# Regenerate the same P-256 release private key on every trusted runner without
# storing signing material in git or artifacts. The protected AGC service-account
# private key is used only as HMAC key material with a versioned domain label.
# If that account key is ever rotated, the public-key check against the existing
# AGC stable certificate below fails closed and requires an explicit migration.
derive_persistent_release_key() {
  local output="$1"
  RELEASE_KEY_OUTPUT="$output" node <<'NODE'
  const crypto = require('crypto');
  const fs = require('fs');
  const account = JSON.parse(process.env.AGC_SERVICE_ACCOUNT_JSON);
  const order = BigInt('0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551');
  const seed = crypto.createHmac('sha256', account.private_key)
    .update('PaperTodo HarmonyOS persistent release signing key v1')
    .digest();
  const scalar = (BigInt(`0x${seed.toString('hex')}`) % (order - 1n)) + 1n;
  const d = Buffer.from(scalar.toString(16).padStart(64, '0'), 'hex');
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.setPrivateKey(d);
  const pub = ecdh.getPublicKey(undefined, 'uncompressed');
  const b64u = value => Buffer.from(value).toString('base64url');
  const jwk = {
    kty: 'EC',
    crv: 'P-256',
    d: b64u(d),
    x: b64u(pub.subarray(1, 33)),
    y: b64u(pub.subarray(33, 65))
  };
  const key = crypto.createPrivateKey({ key: jwk, format: 'jwk' });
  fs.writeFileSync(process.env.RELEASE_KEY_OUTPUT,
    key.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });
NODE
}

require_agc_success() {
  local action="$1"
  local status="$2"
  local response="$3"
  local code
  code="$(jq -r '.ret.code // -1' "$response" 2>/dev/null || echo -1)"
  if [[ "$status" != '200' || "$code" != '0' ]]; then
    local message
    message="$(jq -r '.ret.msg // empty' "$response" 2>/dev/null || true)"
    echo "$action failed: HTTP=$status code=$code${message:+ message=$message}" >&2
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

cleanup_failed_bootstrap() {
  local original_status=$?
  trap - EXIT
  if [[ "$original_status" == '0' || "$BOOTSTRAP_COMPLETE" == '1' ]]; then
    return "$original_status"
  fi
  set +e
  if [[ -n "$CREATED_PROFILE_ID" ]]; then
    echo 'Persistent signing bootstrap failed; removing newly created profile.' >&2
    delete_profile "$SIGNING_JWT" "$CREATED_PROFILE_ID" "$SIGN_DIR/delete-new-profile.json"
  fi
  if [[ -n "$CREATED_CERT_ID" ]]; then
    echo 'Persistent signing bootstrap failed; removing newly created certificate.' >&2
    delete_certificates "$SIGNING_JWT" "$SIGN_DIR/delete-new-certificate.json" "$CREATED_CERT_ID"
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
  echo "Stale PaperTodo test profiles found: ${#profile_ids[@]}"
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
  echo "Stale PaperTodo test certificates found: ${#cert_ids[@]}"
  delete_certificates "$jwt" "$SIGN_DIR/delete-stale-certificates.json" "${cert_ids[@]}"
}

find_certificate_record() {
  local list_file="$1"
  local name="$2"
  jq -c --arg name "$name" \
    '[.. | objects | select(.certName? == $name)] | unique_by(.id // .certId) | .[0] // empty' \
    "$list_file"
}

find_certificate_count() {
  local list_file="$1"
  local name="$2"
  jq -r --arg name "$name" \
    '[.. | objects | select(.certName? == $name)] | unique_by(.id // .certId) | length' \
    "$list_file"
}

find_profile_record() {
  local list_file="$1"
  local name="$2"
  jq -c --arg name "$name" \
    '[.provisionList[]? | select(.provisionName? == $name)] | unique_by(.id // .provisionId) | .[0] // empty' \
    "$list_file"
}

find_profile_count() {
  local list_file="$1"
  local name="$2"
  jq -r --arg name "$name" \
    '[.provisionList[]? | select(.provisionName? == $name)] | unique_by(.id // .provisionId) | length' \
    "$list_file"
}

reclaim_legacy_slot_if_needed() {
  local jwt="$1"
  local cert_list="$2"
  local profile_list="$3"

  local legacy_cert_count legacy_profile_count
  legacy_cert_count="$(find_certificate_count "$cert_list" "$LEGACY_RELEASE_SLOT_NAME")"
  legacy_profile_count="$(find_profile_count "$profile_list" "$LEGACY_RELEASE_SLOT_NAME")"
  if [[ "$legacy_cert_count" == '0' && "$legacy_profile_count" == '0' ]]; then
    return 0
  fi
  if [[ "$legacy_cert_count" -gt 1 || "$legacy_profile_count" -gt 1 ]]; then
    echo "Refusing ambiguous legacy release cleanup: certs=$legacy_cert_count profiles=$legacy_profile_count" >&2
    exit 1
  fi

  echo "Reclaiming superseded release signing slot: $LEGACY_RELEASE_SLOT_NAME"
  if [[ "$legacy_profile_count" == '1' ]]; then
    local profile_record profile_id
    profile_record="$(find_profile_record "$profile_list" "$LEGACY_RELEASE_SLOT_NAME")"
    profile_id="$(jq -r '.id // .provisionId // empty' <<<"$profile_record")"
    [[ -n "$profile_id" ]] || { echo 'Legacy profile id missing.' >&2; exit 1; }
    delete_profile "$jwt" "$profile_id" "$SIGN_DIR/delete-legacy-profile.json"
  fi
  if [[ "$legacy_cert_count" == '1' ]]; then
    local cert_record cert_id
    cert_record="$(find_certificate_record "$cert_list" "$LEGACY_RELEASE_SLOT_NAME")"
    cert_id="$(jq -r '.id // .certId // empty' <<<"$cert_record")"
    [[ -n "$cert_id" ]] || { echo 'Legacy certificate id missing.' >&2; exit 1; }
    delete_certificates "$jwt" "$SIGN_DIR/delete-legacy-certificate.json" "$cert_id"
  fi
}

download_certificate() {
  local record="$1"
  local output="$2"
  local url
  url="$(jq -r '.certDownloadUrl // .downloadUrl // empty' <<<"$record")"
  [[ -n "$url" ]] || {
    echo "AGC certificate list did not provide a download URL for $STABLE_RESOURCE_NAME." >&2
    exit 1
  }
  curl --fail --location --silent --show-error "$url" --output "$output"
}

download_profile() {
  local record="$1"
  local output="$2"
  local url
  url="$(jq -r '.provisionDownloadUrl // .downloadUrl // empty' <<<"$record")"
  [[ -n "$url" ]] || {
    echo "AGC profile list did not provide a download URL for $STABLE_RESOURCE_NAME." >&2
    exit 1
  }
  curl --fail --location --silent --show-error "$url" --output "$output"
}

normalize_certificate_pem() {
  local input="$1"
  local output="$2"
  if openssl x509 -in "$input" -noout >/dev/null 2>&1; then
    openssl x509 -in "$input" -out "$output"
  else
    openssl x509 -inform DER -in "$input" -out "$output"
  fi
}

verify_persistent_key_matches_certificate() {
  local key_file="$1"
  local cert_pem="$2"
  local key_hash cert_hash
  key_hash="$(openssl pkey -in "$key_file" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  cert_hash="$(openssl x509 -in "$cert_pem" -pubkey -noout | \
    openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  if [[ -z "$key_hash" || -z "$cert_hash" || "$key_hash" != "$cert_hash" ]]; then
    echo 'Persistent release key no longer matches the AGC stable release certificate.' >&2
    echo 'The protected AGC service-account key may have rotated; perform an explicit signing-identity migration.' >&2
    exit 1
  fi
}

create_stable_certificate() {
  local jwt="$1"
  local csr="$2"
  local response="$3"
  local request status
  request="$(jq -n --rawfile csr "$csr" --arg certName "$STABLE_RESOURCE_NAME" \
    '{csr: $csr, certName: $certName, certType: 2}')"
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/cert')"
  require_agc_success 'AGC persistent release certificate creation' "$status" "$response"
}

create_stable_profile() {
  local jwt="$1"
  local cert_id="$2"
  local response="$3"
  local request status
  request="$(jq -n \
    --arg provisionName "$STABLE_RESOURCE_NAME" \
    --arg certId "$cert_id" \
    --arg appId "$AGC_APP_ID" \
    '{provisionName: $provisionName, provisionType: 2, certId: $certId, appId: $appId}')"
  status="$(curl --silent --show-error --output "$response" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $jwt" \
    --header 'Content-Type: application/json' \
    --data "$request" \
    'https://connect-api.cloud.huawei.com/api/publish/v3/provision')"
  require_agc_success 'AGC persistent release profile creation' "$status" "$response"
}

resolve_persistent_identity() {
  local jwt="$1"
  local key_file="$2"
  local csr="$3"
  local certificate_raw="$4"
  local certificate_pem="$5"
  local profile="$6"

  local cert_list="$SIGN_DIR/release-certificates.json"
  local profile_list="$SIGN_DIR/release-profiles.json"
  list_certificates "$jwt" "$cert_list"
  list_profiles "$jwt" "$profile_list"

  local stable_cert_count stable_profile_count
  stable_cert_count="$(find_certificate_count "$cert_list" "$STABLE_RESOURCE_NAME")"
  stable_profile_count="$(find_profile_count "$profile_list" "$STABLE_RESOURCE_NAME")"
  if [[ "$stable_cert_count" -gt 1 || "$stable_profile_count" -gt 1 ]]; then
    echo "Refusing ambiguous persistent release identity: certs=$stable_cert_count profiles=$stable_profile_count" >&2
    exit 1
  fi
  if [[ "$stable_profile_count" == '1' && "$stable_cert_count" == '0' ]]; then
    echo 'Persistent AGC profile exists without its certificate; refusing automatic destructive repair.' >&2
    exit 1
  fi

  local cert_record='' cert_id='' profile_record=''
  if [[ "$stable_cert_count" == '0' ]]; then
    # The account historically filled all traditional release-certificate slots.
    # Reclaim only the explicitly superseded 3.3.1 pair when bootstrapping v1.
    reclaim_legacy_slot_if_needed "$jwt" "$cert_list" "$profile_list"
    list_certificates "$jwt" "$cert_list"
    list_profiles "$jwt" "$profile_list"

    local cert_response="$SIGN_DIR/stable-cert-response.json"
    create_stable_certificate "$jwt" "$csr" "$cert_response"
    cert_id="$(jq -r '.certInfo.id // .certInfo.certId // empty' "$cert_response")"
    local cert_url
    cert_url="$(jq -r '.certInfo.certDownloadUrl // empty' "$cert_response")"
    [[ -n "$cert_id" && -n "$cert_url" ]] || {
      echo 'AGC persistent certificate response is missing id or download URL.' >&2
      exit 1
    }
    CREATED_CERT_ID="$cert_id"
    curl --fail --location --silent --show-error "$cert_url" --output "$certificate_raw"
    normalize_certificate_pem "$certificate_raw" "$certificate_pem"
    verify_persistent_key_matches_certificate "$key_file" "$certificate_pem"
    stable_cert_count=1
    echo "Created persistent AGC release certificate: $STABLE_RESOURCE_NAME"
  else
    cert_record="$(find_certificate_record "$cert_list" "$STABLE_RESOURCE_NAME")"
    cert_id="$(jq -r '.id // .certId // empty' <<<"$cert_record")"
    [[ -n "$cert_id" ]] || { echo 'Persistent certificate id missing.' >&2; exit 1; }
    download_certificate "$cert_record" "$certificate_raw"
    normalize_certificate_pem "$certificate_raw" "$certificate_pem"
    verify_persistent_key_matches_certificate "$key_file" "$certificate_pem"
    echo "Reusing persistent AGC release certificate: $STABLE_RESOURCE_NAME"
  fi

  if [[ "$stable_profile_count" == '0' ]]; then
    local profile_response="$SIGN_DIR/stable-profile-response.json"
    create_stable_profile "$jwt" "$cert_id" "$profile_response"
    local profile_id profile_url
    profile_id="$(jq -r '.provisionInfo.id // .provisionInfo.provisionId // empty' "$profile_response")"
    profile_url="$(jq -r '.provisionInfo.provisionDownloadUrl // empty' "$profile_response")"
    [[ -n "$profile_url" ]] || { echo 'AGC persistent profile response is missing download URL.' >&2; exit 1; }
    CREATED_PROFILE_ID="$profile_id"
    curl --fail --location --silent --show-error "$profile_url" --output "$profile"
    echo "Created persistent AGC release profile: $STABLE_RESOURCE_NAME"
  else
    profile_record="$(find_profile_record "$profile_list" "$STABLE_RESOURCE_NAME")"
    download_profile "$profile_record" "$profile"
    echo "Reusing persistent AGC release profile: $STABLE_RESOURCE_NAME"
  fi

  [[ -s "$certificate_pem" && -s "$profile" ]] || {
    echo 'Persistent release identity files are incomplete.' >&2
    exit 1
  }
  # From this point the stable pair is intentional account state. Never remove it
  # because a later local packaging/sign-tool step fails.
  BOOTSTRAP_COMPLETE=1
  trap - EXIT
}

sign_release() {
  require_signing_secrets
  : "${HOS_SDK_HOME:?HOS_SDK_HOME is required}"
  : "${SOURCE_SHA:?SOURCE_SHA is required}"
  : "${APP_VERSION:?APP_VERSION is required}"
  : "${PACKAGE_BASENAME:?PACKAGE_BASENAME is required}"

  umask 077
  mkdir -p "$SIGN_DIR" package/payload
  local key_file="$SIGN_DIR/release-key.pem"
  local csr="$SIGN_DIR/release.csr"
  local certificate_raw="$SIGN_DIR/release.cer"
  local certificate_pem="$SIGN_DIR/release-cert.pem"
  local profile="$SIGN_DIR/release.p7b"
  local keystore="$SIGN_DIR/release.p12"
  local keystore_password="Pt-$(openssl rand -hex 16)-9A"
  echo "::add-mask::$keystore_password"

  derive_persistent_release_key "$key_file"

  # AGC certificate requests have been proven with keytool PKCS#10 output.
  # Keep the persistent private key, but let keytool generate the CSR.
  local bootstrap_certificate="$SIGN_DIR/release-bootstrap-cert.pem"
  openssl req -new -x509 -sha256 -days 3650 \
    -key "$key_file" \
    -subj "/C=CN/O=PaperTodo/OU=Release/CN=$STABLE_KEY_ALIAS" \
    -out "$bootstrap_certificate"
  openssl pkcs12 -export \
    -name "$STABLE_KEY_ALIAS" \
    -inkey "$key_file" \
    -in "$bootstrap_certificate" \
    -out "$keystore" \
    -passout "pass:$keystore_password"
  keytool -certreq \
    -alias "$STABLE_KEY_ALIAS" \
    -sigalg SHA256withECDSA \
    -keystore "$keystore" \
    -storetype pkcs12 \
    -storepass "$keystore_password" \
    -keypass "$keystore_password" \
    -file "$csr"

  local jwt
  jwt="$(create_jwt)"
  echo "::add-mask::$jwt"
  SIGNING_JWT="$jwt"
  trap cleanup_failed_bootstrap EXIT
  resolve_persistent_identity "$jwt" "$key_file" "$csr" "$certificate_raw" "$certificate_pem" "$profile"

  openssl pkcs12 -export \
    -name "$STABLE_KEY_ALIAS" \
    -inkey "$key_file" \
    -in "$certificate_pem" \
    -out "$keystore" \
    -passout "pass:$keystore_password"

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
    -keyAlias "$STABLE_KEY_ALIAS" \
    -signAlg SHA256withECDSA \
    -mode localSign \
    -appCertFile "$certificate_pem" \
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
    printf 'version=%s\ncommit=%s\nbuild_mode=release\nsigning=AGC persistent release v1\nverification=hap-sign-tool verify-app\n' \
      "$APP_VERSION" "$SOURCE_SHA" > BUILD_INFO.txt
    zip -9 "../${PACKAGE_BASENAME}.zip" \
      "${PACKAGE_BASENAME}.app" SHA256SUMS BUILD_INFO.txt
  )
  echo "Signed and verified formal APP with persistent identity: $signed_app"
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
