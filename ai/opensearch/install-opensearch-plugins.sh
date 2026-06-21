#!/usr/bin/env bash
set -euo pipefail

PLUGIN_BIN="/usr/share/opensearch/bin/opensearch-plugin"
MODULE_DIR="/usr/share/opensearch/modules"
STRICT_MODE="${PLUGIN_INSTALL_STRICT:-true}"

# Format: logical_name|plugin_candidates_csv|module_candidates_csv
# Source lists are based on OpenSearch official plugin docs (bundled + additional).
declare -a REQUIRED_PLUGIN_GROUPS=(
  "alerting|opensearch-alerting|"
  "anomaly-detection|opensearch-anomaly-detection|"
  "asynchronous-search|opensearch-asynchronous-search|"
  "cross-cluster-replication|opensearch-cross-cluster-replication|"
  "custom-codecs|opensearch-custom-codecs|"
  "flow-framework|opensearch-flow-framework|"
  "geospatial|opensearch-geospatial|"
  "index-management|opensearch-index-management|"
  "job-scheduler|opensearch-job-scheduler|"
  "knn|opensearch-knn,knn|"
  "ml|opensearch-ml|"
  "neural-search|opensearch-neural-search,neural-search|"
  "notifications|opensearch-notifications,notifications|"
  "notifications-core|opensearch-notifications-core|"
  "observability|opensearch-observability|"
  "performance-analyzer|opensearch-performance-analyzer|"
  "reports-scheduler|opensearch-reports-scheduler|"
  "security|opensearch-security|"
  "security-analytics|opensearch-security-analytics|"
  "sql|opensearch-sql|"
  "learning-to-rank|opensearch-ltr|"
  "system-templates|opensearch-system-templates|"
  "user-behavior-insights|opensearch-ubi|"
  "search-relevance|opensearch-search-relevance|"
  "analysis-icu|analysis-icu|"
  "analysis-kuromoji|analysis-kuromoji|"
  "analysis-nori|analysis-nori|"
  "analysis-phonetic|analysis-phonetic|"
  "analysis-smartcn|analysis-smartcn|"
  "analysis-stempel|analysis-stempel|"
  "analysis-ukrainian|analysis-ukrainian|"
  "ingest-attachment|ingest-attachment|"
  "mapper-annotated-text|mapper-annotated-text|"
  "mapper-murmur3|mapper-murmur3|"
  "mapper-size|mapper-size|"
  "query-insights|query-insights|query-insights"
  "repository-azure|repository-azure|"
  "repository-gcs|repository-gcs|"
  "repository-hdfs|repository-hdfs|"
  "repository-s3|repository-s3|"
  "store-smb|store-smb|"
  "transport-grpc|transport-grpc|transport-grpc"
  "workload-management|workload-management|workload-management"
)

is_installed() {
  local candidate="$1"
  [[ -z "${candidate}" ]] && return 1
  "${PLUGIN_BIN}" list | grep -Fxq "${candidate}"
}

is_module_present() {
  local candidate="$1"
  [[ -z "${candidate}" ]] && return 1
  [[ -d "${MODULE_DIR}/${candidate}" ]]
}

install_candidate() {
  local candidate="$1"
  echo "Installing plugin candidate: ${candidate}"
  "${PLUGIN_BIN}" install --batch "${candidate}"
}

ensure_group() {
  local logical_name="$1"
  local plugin_csv="$2"
  local module_csv="$3"

  IFS=',' read -r -a plugin_candidates <<< "${plugin_csv}"
  IFS=',' read -r -a module_candidates <<< "${module_csv}"

  for c in "${plugin_candidates[@]}"; do
    if is_installed "${c}"; then
      echo "OK ${logical_name}: already installed as ${c}"
      return 0
    fi
  done

  for c in "${module_candidates[@]}"; do
    if is_module_present "${c}"; then
      echo "OK ${logical_name}: provided as module ${c}"
      return 0
    fi
  done

  for c in "${plugin_candidates[@]}"; do
    [[ -z "${c}" ]] && continue
    if install_candidate "${c}"; then
      echo "OK ${logical_name}: installed ${c}"
      return 0
    fi
    echo "WARN ${logical_name}: candidate ${c} not installable"
  done

  echo "ERROR ${logical_name}: no candidate installed"
  return 1
}

missing_count=0
for group in "${REQUIRED_PLUGIN_GROUPS[@]}"; do
  IFS='|' read -r logical_name plugin_csv module_csv <<< "${group}"
  if ! ensure_group "${logical_name}" "${plugin_csv}" "${module_csv}"; then
    missing_count=$((missing_count + 1))
  fi
  echo "------------------------------------------------------------"
done

echo "Final installed plugins:"
"${PLUGIN_BIN}" list | sort || true

if [[ "${missing_count}" -gt 0 ]]; then
  if [[ "${STRICT_MODE}" == "true" ]]; then
    echo "Plugin bootstrap failed: ${missing_count} required plugin groups missing"
    exit 1
  fi
  echo "Plugin bootstrap completed with warnings: ${missing_count} missing groups"
fi
