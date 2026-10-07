# Infrastructure Resiliency Manager Service Group onboarding

`Deploy-IrmServiceGroup.ps1` is a PowerShell 7 workflow for idempotent onboarding of an Azure Service Group to Infrastructure Resiliency Manager (IRM) through Drill creation. It supports stage-bounded runs, ARM long-running operations, `-WhatIf`, deterministic memberships, and JSON summaries.

> All APIs used by this workflow are preview APIs. Validate contracts in a non-production tenant before adoption.

## Prerequisites

- PowerShell 7 or later.
- Current `Az.Accounts` and `Az.Resources` modules.
- An authenticated context: `Connect-AzAccount -Tenant <tenant-id>`.
- Existing Usage Plan and drill resource groups.
- Access to every subscription containing a member resource, the Usage Plan, and drill assets.
- Resource providers registered in relevant subscriptions: `Microsoft.AzureResilienceManagement`, `Microsoft.Chaos`, `Microsoft.Insights`, `Microsoft.OperationalInsights`, and `Microsoft.Automation`.

Install modules:

```powershell
Install-Module Az.Accounts, Az.Resources -Scope CurrentUser
Connect-AzAccount -Tenant '<tenant-guid>'
```

The caller needs the read/write/action permissions represented by the operations in the table below at their respective scopes. It also needs read access to all members and permission to create `Microsoft.Relationships/serviceGroupMember` relationships on them. `-RegisterMissingProviders` explicitly permits provider registration; there is no implicit role assignment.

## Configuration

Copy and edit `parameters.sample.json`. Names are URI-escaped and validated; subscription IDs must be GUIDs and resource IDs must be complete ARM IDs.

| Object | Required values |
|---|---|
| `serviceGroup` | Immutable `id`, mutable `displayName`, optional Service Group `parentResourceId`. A null parent uses the tenant-root Service Group. |
| `resources` | Array of full ARM resource IDs. |
| `usagePlan` | `subscriptionId`, existing `resourceGroupName`, `name`, and `location`. The official example uses `global`, which is why the sample differs from the original illustrative `eastus`. |
| `enrollment` | Nested enrollment `name`. |
| `goalAssignment` | Tenant-scoped assignment `name`. API `2026-08-31-preview` sets `requireZonalResiliency` directly on the assignment. `requireRegionalResiliency` isn't supported by this API version. |
| `drill` | Asset `subscriptionId`, existing `resourceGroupName`, drill `name`, and asset `location`. The drill itself is tenant-scoped below the Service Group. |

## Run

Supported scripted workflow through Drill creation:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StopAfterStage Drill -Verbose
```

> [!IMPORTANT]
> Use the script only through the `Drill` stage. After the drill is created, open it in the Azure portal and add the relevant resources there. The portal workflow automatically creates the role assignments required for the selected resources. Do not use the script's `DrillResources` stage for user onboarding.

Service Group only:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StartAtStage ServiceGroup -StopAfterStage ServiceGroup
```

Through Usage Plan:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StartAtStage ServiceGroup -StopAfterStage UsagePlan
```

Resume at goal assignment:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StartAtStage GoalAssignment -StopAfterStage Drill
```

Preview changes and write no resources:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StopAfterStage Drill -WhatIf -Verbose
```

Use `-CreateMissingPrerequisites` to permit creation of a missing skipped Service Group, `-Force` for the documented mutable-property updates, `-ContinueOnResourceError` for independent membership errors, `-MaxConcurrency 4` for bounded membership PUT submission, and `-OutputPath ./irm-summary.json` for a machine-readable result. Individual authenticated HTTP calls are bounded by `-ArmRequestTimeoutSeconds` (default `120`), while asynchronous ARM operations are bounded separately by `-OperationTimeoutSeconds` (default `1800`). ARM `403 AuthorizationFailed` and `LinkedAuthorizationFailed` responses are retried with bounded exponential backoff for RBAC and linked-scope propagation; tune this with `-AuthorizationRetryCount` (default `6`, `0` disables retries) and `-AuthorizationRetryDelaySeconds` (default `10`, capped at 60 seconds per delay). Service Group prerequisite checks also retry transient `404` responses while the tenant-scoped resource propagates; tune this independently with `-ResourcePropagationRetryCount` and `-ResourcePropagationRetryDelaySeconds`.

## Operation mapping

| Stage | REST operation | Method | API version | Idempotency check | Verification |
|---|---|---:|---|---|---|
| ServiceGroup | `/providers/Microsoft.Management/serviceGroups/{name}` | PUT | `2024-02-01-preview` | GET and compare display name/parent | LRO then GET |
| Membership | `{resourceId}/providers/Microsoft.Relationships/serviceGroupMember/{hash}` | PUT | `2023-09-01-preview` | Deterministic name; GET and compare `targetId` | LRO then GET |
| UsagePlan | `/subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.AzureResilienceManagement/usagePlans/{name}` | PUT | `2026-08-31-preview` | GET; require Standard and matching location | LRO then GET |
| Enrollment | `{usagePlanId}/enrollments/{name}` | PUT | `2026-08-31-preview` | GET and compare `serviceGroupId` | LRO then GET |
| GoalAssignment | `{serviceGroupId}/providers/Microsoft.AzureResilienceManagement/goalAssignments/{name}` | PUT | `2026-08-31-preview` | GET and compare zonal-only intent | LRO then GET |
| Drill | `{serviceGroupId}/providers/Microsoft.AzureResilienceManagement/drills/{name}` | PUT | `2026-06-01-preview` | GET; require Zonal and SystemAssigned | LRO then GET |

## Add resources to the drill

After the script creates the drill:

1. Open the drill in the Azure portal.
2. Use the portal workflow to add the relevant Service Group resources to the drill.
3. Review and apply the role assignments presented by the portal.

The portal automatically handles the role assignments needed for the selected drill resources. Resource inclusion is intentionally outside the supported scripted workflow.

## Troubleshooting

- `Prerequisite failed`: create or grant access to the named object, or use `-CreateMissingPrerequisites` where supported.
- `AuthorizationFailed` or `LinkedAuthorizationFailed`: the script waits up to six retries (250 seconds by default) for authorization propagation. If it still fails, use the request ID to verify access at both the requested scope and the linked Service Group scope, then refresh the context with `Disconnect-AzAccount` and `Connect-AzAccount`.
- Service Group `does not exist or did not become visible`: the script waits up to six retries (250 seconds by default) for tenant-scoped resource visibility. Increase `-ResourcePropagationRetryCount` only when Service Group GET requests eventually succeed in the same tenant.
- `Forbidden`: this is not treated as a propagation error; verify access at tenant, Service Group, member, subscription, and resource-group scopes.
- `MissingSubscription` while polling a Service Group operation: update to the current script. Absolute ARM operation URLs must be sent through `Invoke-AzRestMethod -Uri`, not `-Path`.
- Provider warning: register it explicitly or rerun with `-RegisterMissingProviders` after approval.
- Request timeout: increase `-ArmRequestTimeoutSeconds` if an individual ARM HTTP call consistently needs more than 120 seconds.
- Membership conflict: inspect the deterministic relationship and remove or reconcile the conflicting target manually.

## Assumptions and preview details

- Goal assignments use API `2026-08-31-preview`; `requireZonalResiliency = true` expresses the required direct intent.
- The drill and its internal Chaos, recovery-plan, and monitoring resources use system-assigned identities. The script fails verification if the service does not retain `SystemAssigned` on the drill.
- Drill Resource inclusion and its required role assignments are completed through the Azure portal after the scripted `Drill` stage.

References: [Service Group quickstart](https://learn.microsoft.com/azure/governance/service-groups/create-service-group-rest-api), [Azure REST API specifications](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/azureresiliencemanagement/resource-manager/Microsoft.AzureResilienceManagement/AzureResilienceManagement).