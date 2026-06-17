// ════════════════════════════════════════════════════════════════════════
// SLO Prometheus Rule Group para app-cicd
//
// Traducción 1:1 de las 3 alertas + 4 recording rules que estaban en
// k8s/observability/prometheus-rule.yaml, ahora como recurso Azure que
// Azure Monitor managed Prometheus evalúa nativamente.
//
// Apply:
//   az deployment group create \
//     -g rg-appcicd-dev-eastus \
//     -f bicep/prometheus-rules.bicep \
//     -p azureMonitorWorkspaceName=<TU_AMW_NAME> \
//        aksClusterName=aks-appcicd-dev
// ════════════════════════════════════════════════════════════════════════

@description('Nombre del Azure Monitor Workspace (descúbrelo con: az monitor account list -o table)')
param azureMonitorWorkspaceName string

@description('Nombre del cluster AKS')
param aksClusterName string = 'aks-appcicd-dev'

@description('Región donde se crea el rule group (debe ser la misma del workspace)')
param location string = 'eastus'

var monitorWorkspaceId = resourceId(
  'Microsoft.Monitor/accounts',
  azureMonitorWorkspaceName
)
var aksClusterId = resourceId(
  'Microsoft.ContainerService/managedClusters',
  aksClusterName
)

// ════════════════════════════════════════════════════════════════════════
// GRUPO 1 — Recording rules (precalculan los SLIs)
// Equivalente al grupo "app-cicd.sli.recording" del YAML original
// ════════════════════════════════════════════════════════════════════════
resource sliRecordingRules 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'app-cicd-sli-recording'
  location: location
  properties: {
    description: 'Recording rules de SLIs para app-cicd (disponibilidad, errores, latencia p95)'
    scopes: [
      monitorWorkspaceId
      aksClusterId
    ]
    clusterName: aksClusterName
    interval: 'PT1M'
    enabled: true
    rules: [
      {
        record: 'app_cicd:http_requests:rate1m'
        expression: 'sum(rate(http_requests_received_total{job="app-cicd"}[1m]))'
        enabled: true
      }
      {
        record: 'app_cicd:success_ratio:rate1m'
        expression: 'sum(rate(http_requests_received_total{job="app-cicd", code=~"2.."}[1m])) / sum(rate(http_requests_received_total{job="app-cicd"}[1m]))'
        enabled: true
      }
      {
        record: 'app_cicd:error_ratio:rate1m'
        expression: 'sum(rate(http_requests_received_total{job="app-cicd", code=~"5.."}[1m])) / sum(rate(http_requests_received_total{job="app-cicd"}[1m]))'
        enabled: true
      }
      {
        record: 'app_cicd:http_request_duration:p95'
        expression: 'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="app-cicd"}[1m])) by (le))'
        enabled: true
      }
    ]
  }
}

// ════════════════════════════════════════════════════════════════════════
// GRUPO 2 — Alertas SLO
// Las 3 alertas originales de Cloud Monitoring
// Severity: 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose
// ════════════════════════════════════════════════════════════════════════
resource sloAlerts 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = {
  name: 'app-cicd-slo-alerts'
  location: location
  properties: {
    description: 'Alertas SLO para app-cicd (disponibilidad ≥99.5%, error rate ≤0.5%, latencia p95 ≤500ms)'
    scopes: [
      monitorWorkspaceId
      aksClusterId
    ]
    clusterName: aksClusterName
    interval: 'PT1M'
    enabled: true
    rules: [
      // ALERTA 1 — Disponibilidad < 99.5%
      {
        alert: 'AppCicdAvailabilityBelow995'
        expression: 'app_cicd:success_ratio:rate1m < 0.995'
        for: 'PT1M'
        severity: 2
        enabled: true
        labels: {
          severity: 'critical'
          slo: 'availability'
          service: 'app-cicd'
        }
        annotations: {
          summary: 'Disponibilidad de app-cicd por debajo del 99.5%'
          description: 'Tasa de éxito (2xx) cayó al {{ $value | humanizePercentage }} (objetivo: ≥ 99.5%).'
          slo_target: '99.5%'
        }
      }

      // ALERTA 2 — Tasa de errores > 0.5%
      {
        alert: 'AppCicdErrorRateAbove05'
        expression: 'app_cicd:error_ratio:rate1m > 0.005'
        for: 'PT1M'
        severity: 2
        enabled: true
        labels: {
          severity: 'critical'
          slo: 'error-rate'
          service: 'app-cicd'
        }
        annotations: {
          summary: 'Tasa de errores 5xx de app-cicd por encima del 0.5%'
          description: 'Tasa de 5xx: {{ $value | humanizePercentage }} (objetivo: ≤ 0.5%).'
          slo_target: '0.5%'
        }
      }

      // ALERTA 3 — Latencia p95 > 500ms
      {
        alert: 'AppCicdLatencyP95Above500ms'
        expression: 'app_cicd:http_request_duration:p95 > 0.5'
        for: 'PT1M'
        severity: 2
        enabled: true
        labels: {
          severity: 'critical'
          slo: 'latency'
          service: 'app-cicd'
        }
        annotations: {
          summary: 'Latencia p95 de app-cicd por encima de 500ms'
          description: 'p95: {{ $value | humanizeDuration }} (objetivo: ≤ 500ms).'
          slo_target: '500ms'
        }
      }
    ]
  }
  dependsOn: [
    sliRecordingRules  // las alertas usan las recording rules, deben crearse después
  ]
}

output recordingRulesId string = sliRecordingRules.id
output alertsRulesId string = sloAlerts.id
