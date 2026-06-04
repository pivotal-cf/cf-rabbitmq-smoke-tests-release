#!/bin/bash
set -euo pipefail

# ---- Logging ----------------------------------------------------------------

LOG_DIR="/var/vcap/sys/log/on-demand-broker-smoke-tests"
LOG_FILE="${LOG_DIR}/smoke-tests.log"
mkdir -p "${LOG_DIR}"

exec 4>&1
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

# ---- Timeout & Auth Helpers -------------------------------------------------

DEADLINE=$(( SECONDS + SMOKE_TEST_TIMEOUT_SECS ))
CF_AUTH_TIME=0

remaining_seconds() {
  local r=$(( DEADLINE - SECONDS ))
  echo $(( r < 1 ? 1 : r ))
}

ensure_cf_auth() {
  local elapsed=$(( SECONDS - CF_AUTH_TIME ))
  (( elapsed < 3000 )) && return 0

  log "--- CF token refresh"
  cf auth "${CF_ADMIN_CLIENT}" "${CF_ADMIN_CLIENT_SECRET}" --client-credentials &>/dev/null || true
  cf target -o "${CF_ORG}" -s "${CF_SPACE}" &>/dev/null || true
  CF_AUTH_TIME=$SECONDS
}

cf_cmd() {
  ensure_cf_auth
  timeout "$(remaining_seconds)s" cf "$@"
}

get_service_status() {
  ensure_cf_auth
  if ! out=$(cf service "$1" 2>&1); then
    [[ "${out}" =~ "not found"|"does not exist" ]] && echo "not found" || echo "error"
    return
  fi
  # Extracts the value after "Status:" or "status:", ignoring leading/trailing whitespace
  echo "${out}" | awk -F ':[ \t]*' '/^[Ss]tatus/ {print $2; exit}'
}

cf_wait_for_service() {
  local instance="$1" op="$2" max_secs="${3:-0}" status
  local limit=$(( max_secs > 0 ? SECONDS + max_secs : DEADLINE ))

  while (( SECONDS < limit )); do
    status=$(get_service_status "${instance}")

    case "${status}" in
      "error") sleep 15 ; continue ;;
      "not found") [[ "${op}" == "delete" ]] && return 0 || return 1 ;;
      "${op} succeeded") return 0 ;;
      *"failed"*) log "FAIL: ${op} failed for ${instance} (${status})"; return 1 ;;
    esac

    sleep 15
  done

  log "FAIL: timed out waiting for '${op}' of ${instance}"
  return 124
}

# ---- RabbitMQ Helpers -------------------------------------------------------

extract_credentials() {
  # Safely parse JSON into bash variables in a single subshell execution
  eval "$(echo "$1" | jq -r '"MGMT_USER=\(.username | @sh) MGMT_PASS=\(.password | @sh) DASHBOARD_URL=\(.dashboard_url | @sh) raw_url=\(.http_api_uri | @sh) vhost=\(.vhost | @sh)"')"

  MGMT_API_BASE=$(echo "${raw_url}" | sed 's|://[^@]*@|://|; s|/$||')
  MGMT_VHOST_ENCODED="${vhost//\//%2F}" # Native bash URL-encoding of '/'
}

mgmt_curl() {
  local desc="$1" out code body; shift
  out=$(curl -sk -u "${MGMT_USER}:${MGMT_PASS}" "$@" -w '\n%{http_code}')
  code=$(printf '%s' "${out}" | tail -1)
  body=$(printf '%s' "${out}" | head -n -1)

  if (( code < 200 || code >= 300 )); then
    log "FAIL: ${desc} — HTTP ${code}"
    return 1
  fi
  printf '%s' "${body}"
}

declare_queue() { mgmt_curl "declare queue" -X PUT -H "content-type: application/json" "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1" -d '{"durable": false, "auto_delete": true}' >/dev/null; }
publish()       { mgmt_curl "publish" -X POST -H "content-type: application/json" "${MGMT_API_BASE}/exchanges/${MGMT_VHOST_ENCODED}/amq.default/publish" -d "{\"properties\":{},\"routing_key\":\"$1\",\"payload\":\"$2\",\"payload_encoding\":\"string\"}" >/dev/null; }
consume()       { mgmt_curl "consume" -X POST -H "content-type: application/json" "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1/get" -d '{"count": 1, "ackmode": "ack_requeue_false", "encoding": "auto"}' | jq -r '.[0].payload'; }
delete_queue()  { mgmt_curl "delete queue" -X DELETE "${MGMT_API_BASE}/queues/${MGMT_VHOST_ENCODED}/$1" >/dev/null; }

# ---- Cleanup ----------------------------------------------------------------

cleanup() {
  local exit_code=$?
  if [[ -n "${INSTANCE_NAME}" ]]; then
    log "--- Cleanup on exit: (${INSTANCE_NAME})"

    cf_cmd delete-service-key "${INSTANCE_NAME}" "${KEY_NAME}" -f &>/dev/null || true
    cf_wait_for_service "${INSTANCE_NAME}" "delete" 1800
  fi

  cf logout &>/dev/null || true

  message="RUN END (PASSED)"
  if (( exit_code == 124 )); then message="RUN END (TIMEOUT: ${SMOKE_TEST_TIMEOUT_SECS}s)"
  elif (( exit_code != 0 )); then message="RUN END (FAILED: ${exit_code})"; fi

  log "======================================== ${message} ========================================"
}

trap cleanup EXIT

# ---- Setup & Execution ------------------------------------------------------

log "--- CF login & Setup"
cf api --skip-ssl-validation "${CF_API}"
cf auth "${CF_ADMIN_CLIENT}" "${CF_ADMIN_CLIENT_SECRET}" --client-credentials

cf_cmd create-org "${CF_ORG}" || true
cf_cmd create-space "${CF_SPACE}" -o "${CF_ORG}" || true
cf_cmd target -o "${CF_ORG}" -s "${CF_SPACE}"

[[ -z "${SMOKE_TEST_PLANS}" ]] && log "No smoke test plans configured. Exiting." && exit 0

tls_params=""
[[ "${TLS_SUPPORT}" =~ ^(enforced|optional)$ ]] && tls_params='{"tls": true}'

for plan in ${SMOKE_TEST_PLANS}; do
  INSTANCE_NAME="rmq-smoke-test-$(( RANDOM % 10000 ))"
  KEY_NAME="${INSTANCE_NAME}-key"
  plan_start=$SECONDS

  log "=== Plan: ${plan} ==="
  cf_cmd create-service "${SERVICE_OFFERING}" "${plan}" "${INSTANCE_NAME}" ${tls_params:+-c "${tls_params}"}
  cf_wait_for_service "${INSTANCE_NAME}" "create"

  cf_cmd create-service-key "${INSTANCE_NAME}" "${KEY_NAME}"
  KEY_JSON=$(cf_cmd service-key "${INSTANCE_NAME}" "${KEY_NAME}" | awk 'found || /^\{/{found=1; print}' | jq -r '.credentials // .')
  extract_credentials "${KEY_JSON}"

  if [[ "${OAUTH_ENFORCED}" != "true" ]]; then
    log "--- Messaging test"
    declare_queue "smoke-queue"
    publish "smoke-queue" "smoke-msg-1"
    publish "smoke-queue" "smoke-msg-2"

    [[ $(consume "smoke-queue") != "smoke-msg-1" ]] && exit 1
    [[ $(consume "smoke-queue") != "smoke-msg-2" ]] && exit 1
    delete_queue "smoke-queue" || true
  fi

  log "--- Dashboard reachability test"
  [[ $(curl -sk -o /dev/null -w "%{http_code}" "${DASHBOARD_URL}") != "200" ]] && log "FAIL: Dashboard unreachable" && exit 1

  log "--- Teardown: ${INSTANCE_NAME}"
  cf_cmd delete-service-key "${INSTANCE_NAME}" "${KEY_NAME}" -f
  cf_cmd delete-service "${INSTANCE_NAME}" -f
  cf_wait_for_service "${INSTANCE_NAME}" "delete"

  INSTANCE_NAME=""
  log "=== Plan ${plan}: PASSED ($(( SECONDS - plan_start ))s) ==="
done
