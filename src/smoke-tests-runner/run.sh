#!/bin/bash
set -euo pipefail

# ---- Logging ----------------------------------------------------------------

LOG_DIR="${SMOKE_TEST_LOG_DIR:-/var/vcap/sys/log/smoke-tests}"
LOG_FILE="${LOG_DIR}/smoke-tests.log"
mkdir -p "${LOG_DIR}"

# Save original terminal stdout so log() can write to it directly.
exec 4>&1

# Route all stdout+stderr through an indent filter, tee-ing to log + terminal.
# log() bypasses the filter and writes clean timestamped lines to both.
# Do not use set -x — it would expose credentials in the log.
exec > >(sed 's/^/  | /' | tee -a "${LOG_FILE}") 2>&1

log() {
  local msg="[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"
  echo "${msg}" >&4
  echo "${msg}" >> "${LOG_FILE}"
}

log "======================================== RUN START ========================================"

# ---- Config -----------------------------------------------------------------

export PATH="/var/vcap/packages/jq/bin:${PATH}"

source "${CONFIG_ENV_PATH:?CONFIG_ENV_PATH must be set by the calling job}"

CF_ORG="${CF_ORG:-system}"
CF_SPACE="${CF_SPACE:-rabbitmq-smoke-test}"
SMOKE_TEST_TIMEOUT_SECS="${SMOKE_TEST_TIMEOUT_SECS:-3600}"

log "--- Configuration"
log "    CF API:           ${CF_API}"
log "    Org / Space:      ${CF_ORG} / ${CF_SPACE}"
log "    Service offering: ${SERVICE_OFFERING}"
log "    Plans:            ${SMOKE_TEST_PLANS:-<none>}"
log "    TLS support:      ${TLS_SUPPORT}"
log "    OAuth enforced:   ${OAUTH_ENFORCED}"
log "    Global timeout:   ${SMOKE_TEST_TIMEOUT_SECS}s"

# Set per plan iteration; read by cleanup() trap
INSTANCE_NAME=""
KEY_NAME=""

# Management API connection — populated by extract_credentials()
MGMT_API_BASE=""
MGMT_USER=""
MGMT_PASS=""
MGMT_VHOST_ENCODED=""
DASHBOARD_URL=""

# ---- Global timeout ---------------------------------------------------------

# Compute the absolute deadline once at startup. Every CF command in the main
# flow runs under timeout(1) with the remaining budget as its limit, so the
# total wall-clock time is bounded by SMOKE_TEST_TIMEOUT_SECS regardless of
# how many plans are being tested. When the budget runs out, timeout(1) exits
# 124, set -e triggers the EXIT trap, and cleanup runs automatically.
DEADLINE=$(( SECONDS + SMOKE_TEST_TIMEOUT_SECS ))

# Returns the seconds remaining before the global deadline. Always returns at
# least 1 so the result can be passed directly to timeout(1) (which treats 0
# as "no timeout" in GNU coreutils).
remaining_seconds() {
  local rem=$(( DEADLINE - SECONDS ))
  if (( rem < 1 )); then rem=1; fi
  echo "${rem}"
}

# ---- CF authentication helpers ----------------------------------------------

# $SECONDS value recorded at the last successful cf auth call.
CF_AUTH_TIME=0
ensure_cf_auth() {
  local elapsed=$(( SECONDS - CF_AUTH_TIME ))
  if (( elapsed >= 3000 )); then
    log "--- CF token refresh (token age: ${elapsed}s)"
    cf auth "${CF_ADMIN_CLIENT}" "${CF_ADMIN_CLIENT_SECRET}" --client-credentials
    cf target -o "${CF_ORG}" -s "${CF_SPACE}"
    CF_AUTH_TIME=$SECONDS
  fi
}

cf_cmd() {
  ensure_cf_auth
  timeout "$(remaining_seconds)s" cf "$@"
}

cf_wait_for_service() {
  local instance_name="$1"
  local operation="$2"
  local max_secs="${3:-0}"
  local success_state="${operation} succeeded"
  local poll_deadline

  if (( max_secs > 0 )); then
    poll_deadline=$(( SECONDS + max_secs ))
  else
    poll_deadline=$DEADLINE
  fi

  while true; do
    if (( SECONDS >= poll_deadline )); then
      log "FAIL: timed out waiting for '${operation}' of ${instance_name}"
      return 124
    fi

    ensure_cf_auth
    local output exit_code
    output=$(timeout 60s cf service "${instance_name}" 2>&1) && exit_code=0 || exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
      # "not found" / "does not exist" = instance is gone — success for deletes.
      if [[ "${operation}" == "delete" ]] && echo "${output}" | grep -qiE "not found|does not exist"; then
        return 0
      fi
      log "    Polling '${instance_name}': cf service exited ${exit_code}, retrying in 15s"
      log "    Output: ${output}"
      sleep 15
      continue
    fi

    local status
    status=$(echo "${output}" | sed -n 's/^[[:space:]]*[Ss]tatus:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*$//')

    log "    Polling '${instance_name}': status=${status:-<unparsed>}"
    if [[ -z "${status}" ]]; then
      log "    Output: ${output}"
    fi

    if [[ "${status}" == "${success_state}" ]]; then
      return 0
    elif [[ "${status}" == *"failed"* ]]; then
      log "FAIL: service ${operation} failed for ${instance_name}: ${status}"
      log "    Output: ${output}"
      return 1
    fi

    sleep 15
  done
}

# ---- Helpers ----------------------------------------------------------------

extract_credentials() {
  local key_json="$1"
  local raw_url vhost

  raw_url=$(echo "${key_json}" | jq -r '.http_api_uri')
  MGMT_USER=$(echo "${key_json}"     | jq -r '.username')
  MGMT_PASS=$(echo "${key_json}"     | jq -r '.password')
  DASHBOARD_URL=$(echo "${key_json}" | jq -r '.dashboard_url')
  vhost=$(echo "${key_json}"         | jq -r '.vhost')

  # Strip embedded credentials and trailing slash from URL
  MGMT_API_BASE=$(echo "${raw_url}" | sed 's|://[^@]*@|://|; s|/$||')
  # '/' is the default vhost — must be percent-encoded in URL paths
  MGMT_VHOST_ENCODED=$(printf '%s' "${vhost}" | sed 's|/|%2F|g')
}

# Wraps curl against the RabbitMQ management API.
# Logs the HTTP status and response body on non-2xx, then returns 1.
# Prints the response body to stdout on success.
mgmt_curl() {
  local description="$1"; shift
  local output http_code body
  output=$(curl -sk -u "${MGMT_USER}:${MGMT_PASS}" "$@" -w '\n%{http_code}')
  http_code=$(printf '%s' "${output}" | tail -1)
  body=$(printf '%s' "${output}" | head -n -1)
  if [[ "${http_code}" -lt 200 ]] || [[ "${http_code}" -ge 300 ]]; then
    log "FAIL: ${description} — HTTP ${http_code}"
    [[ -n "${body}" ]] && log "      Response: ${body}"
    return 1
  fi
  printf '%s' "${body}"
}

declare_queue() {
  log "    Declaring queue: $1"
  mgmt_curl "declare queue '$1'" \
    -X PUT -H "content-type: application/json" \
    "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1" \
    -d '{"durable": false, "auto_delete": true}' > /dev/null
  log "    Queue declared: $1"
}

publish() {
  log "    Publishing: '$2' -> $1"
  mgmt_curl "publish to '$1'" \
    -X POST -H "content-type: application/json" \
    "${MGMT_API_BASE}/exchanges/${MGMT_VHOST_ENCODED}/amq.default/publish" \
    -d "{\"properties\":{},\"routing_key\":\"$1\",\"payload\":\"$2\",\"payload_encoding\":\"string\"}" > /dev/null
  log "    Published: '$2' -> $1"
}

consume() {
  log "    Consuming from: $1"
  local response payload
  response=$(mgmt_curl "consume from '$1'" \
    -X POST -H "content-type: application/json" \
    "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1/get" \
    -d '{"count": 1, "ackmode": "ack_requeue_false", "encoding": "auto"}')
  payload=$(echo "${response}" | jq -r '.[0].payload')
  log "    Consumed: '${payload}' <- $1"
  echo "${payload}"
}

delete_queue() {
  log "    Deleting queue: $1"
  mgmt_curl "delete queue '$1'" \
    -X DELETE \
    "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1" > /dev/null
  log "    Queue deleted: $1"
}

# ---- Cleanup ----------------------------------------------------------------

# Cleans up the instance currently in progress. INSTANCE_NAME is cleared after
# each successful plan iteration so the trap is a no-op on normal exit.
cleanup() {
  local exit_code=$?

  if [[ -n "${INSTANCE_NAME}" ]]; then
    log "--- Cleanup (${INSTANCE_NAME})"

    # Reset CF_AUTH_TIME to force ensure_cf_auth to fetch a fresh token.
    # This protects against stale tokens if the script hit a global timeout.
    CF_AUTH_TIME=0
    ensure_cf_auth 2>/dev/null || true

    cf delete-service-key "${INSTANCE_NAME}" "${KEY_NAME}" -f 2>/dev/null || true

    local deadline=$(( SECONDS + 1800 ))
    while (( SECONDS < deadline )); do
      cf delete-service "${INSTANCE_NAME}" -f 2>/dev/null || true
      if cf_wait_for_service "${INSTANCE_NAME}" "delete" 60; then
        log "--- Cleanup: ${INSTANCE_NAME} deleted."
        break
      fi
    done
  fi

  cf logout 2>/dev/null || true

  if [[ ${exit_code} -eq 124 ]]; then
    log "SMOKE TESTS FAILED: global timeout of ${SMOKE_TEST_TIMEOUT_SECS}s exceeded"
    log "======================================== RUN END (FAILED — TIMEOUT) ========================================"
  elif [[ ${exit_code} -ne 0 ]]; then
    log "SMOKE TESTS FAILED (exit code: ${exit_code})"
    log "======================================== RUN END (FAILED) ========================================"
  else
    log "======================================== RUN END (PASSED) ========================================"
  fi
}

trap cleanup EXIT

# ---- Setup ------------------------------------------------------------------

log "--- CF login"
cf api --skip-ssl-validation "${CF_API}"
cf auth "${CF_ADMIN_CLIENT}" "${CF_ADMIN_CLIENT_SECRET}" --client-credentials
CF_AUTH_TIME=$SECONDS  # anchor for token age tracking

log "--- Setup org and space"
cf_cmd create-org   "${CF_ORG}"                  || true
cf_cmd create-space "${CF_SPACE}" -o "${CF_ORG}" || true
cf_cmd target -o "${CF_ORG}" -s "${CF_SPACE}"

# ---- Per-plan smoke tests ---------------------------------------------------

if [[ -z "${SMOKE_TEST_PLANS}" ]]; then
  log "No smoke test plans configured. Exiting with success."
  exit 0
fi

tls_params=""
if [[ "${TLS_SUPPORT}" == "enforced" ]] || [[ "${TLS_SUPPORT}" == "optional" ]]; then
  tls_params='{"tls": true}'
fi

for plan in ${SMOKE_TEST_PLANS}; do
  INSTANCE_NAME="rmq-smoke-test-$(( RANDOM % 10000 ))"
  KEY_NAME="${INSTANCE_NAME}-key"
  plan_start=$SECONDS

  log "=== Plan: ${plan} ==="

  log "--- Creating service instance: ${INSTANCE_NAME}"
  if [[ -n "${tls_params}" ]]; then
    cf_cmd create-service "${SERVICE_OFFERING}" "${plan}" "${INSTANCE_NAME}" -c "${tls_params}"
  else
    cf_cmd create-service "${SERVICE_OFFERING}" "${plan}" "${INSTANCE_NAME}"
  fi
  cf_wait_for_service "${INSTANCE_NAME}" "create"

  log "--- Creating service key: ${KEY_NAME}"
  cf_cmd create-service-key "${INSTANCE_NAME}" "${KEY_NAME}"

  # `cf service-key` prefixes output with a header line — awk skips to the first '{'.
  # jq normalises CF CLI v7 (bare JSON) and v8 (wrapped in {"credentials":{}}) formats.
  KEY_JSON=$(cf_cmd service-key "${INSTANCE_NAME}" "${KEY_NAME}" \
    | awk 'found || /^\{/{found=1; print}' \
    | jq -r 'if .credentials then .credentials else . end')

  extract_credentials "${KEY_JSON}"
  log "--- Credentials extracted (management API: ${MGMT_API_BASE}, vhost: ${MGMT_VHOST_ENCODED})"

  # Pub/sub skipped when OAuth is enforced — broker issues no AMQP credentials
  if [[ "${OAUTH_ENFORCED}" != "true" ]]; then
    log "--- Messaging test"
    QUEUE="rmq-smoke-test-queue"
    declare_queue "${QUEUE}"
    publish  "${QUEUE}" "smoke-msg-1"
    publish  "${QUEUE}" "smoke-msg-2"
    msg1=$(consume "${QUEUE}")
    msg2=$(consume "${QUEUE}")
    delete_queue "${QUEUE}" || true

    if [[ "${msg1}" != "smoke-msg-1" ]]; then
      log "FAIL: messaging test — expected 'smoke-msg-1', got '${msg1}'"
      exit 1
    fi
    if [[ "${msg2}" != "smoke-msg-2" ]]; then
      log "FAIL: messaging test — expected 'smoke-msg-2', got '${msg2}'"
      exit 1
    fi
    log "--- Messaging test passed (FIFO order verified)"
  fi

  log "--- Dashboard reachability test (${DASHBOARD_URL})"
  dashboard_status=$(curl -sk -o /dev/null -w "%{http_code}" "${DASHBOARD_URL}")
  if [[ "${dashboard_status}" != "200" ]]; then
    log "FAIL: dashboard returned HTTP ${dashboard_status}, expected 200"
    exit 1
  fi
  log "--- Dashboard is reachable (HTTP 200)"

  log "--- Cleanup: ${INSTANCE_NAME}"
  cf_cmd delete-service-key "${INSTANCE_NAME}" "${KEY_NAME}" -f
  cf_cmd delete-service "${INSTANCE_NAME}" -f
  cf_wait_for_service "${INSTANCE_NAME}" "delete"
  INSTANCE_NAME=""  # signal to trap that this plan's instance is already gone
  KEY_NAME=""

  log "=== Plan ${plan}: PASSED ($(( SECONDS - plan_start ))s) ==="
done

log "--- All smoke tests passed."
# cleanup trap fires here and prints RUN END banner
