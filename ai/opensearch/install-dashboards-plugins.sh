#!/usr/bin/env bash
set -euo pipefail

PLUGIN_BIN="/usr/share/opensearch-dashboards/bin/opensearch-dashboards-plugin"
STRICT_MODE="${DASHBOARDS_PLUGIN_INSTALL_STRICT:-false}"

# Common official OpenSearch Dashboards plugins
PLUGINS=(
  alertingDashboards
  anomalyDetectionDashboards
  assistantDashboards
  ganttChartDashboards
  indexManagementDashboards
  mlCommonsDashboards
  notificationsDashboards
  observabilityDashboards
  queryWorkbenchDashboards
  reportsDashboards
  searchRelevanceDashboards
  securityAnalyticsDashboards
)

is_installed() {
  local candidate="$1"
  "${PLUGIN_BIN}" list | grep -Fxq "${candidate}"
}

missing_count=0
for plugin in "${PLUGINS[@]}"; do
  if is_installed "${plugin}"; then
    echo "OK dashboards plugin already installed: ${plugin}"
    continue
  fi
  if "${PLUGIN_BIN}" install "${plugin}"; then
    echo "OK dashboards plugin installed: ${plugin}"
  else
    echo "WARN dashboards plugin not installable: ${plugin}"
    missing_count=$((missing_count + 1))
  fi
  echo "------------------------------------------------------------"
done

echo "Final installed dashboards plugins:"
"${PLUGIN_BIN}" list | sort || true

if [[ "${missing_count}" -gt 0 && "${STRICT_MODE}" == "true" ]]; then
  echo "Dashboards plugin bootstrap failed: ${missing_count} plugins missing"
  exit 1
fi
