# Infrastructure Resiliency Manager Service Group onboarding

`Deploy-IrmServiceGroup.ps1` is a PowerShell 7 workflow for idempotent onboarding of an Azure Service Group to Infrastructure Resiliency Manager (IRM). It supports complete and stage-bounded runs, ARM long-running operations, `-WhatIf`, deterministic memberships, and JSON summaries.

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

The caller needs the read/write/action permissions represented by the operations in the table below at their respective scopes. It also needs read access to all members and permission to create `Microsoft.Relationships/serviceGroupMember` relationships on them. Drill identity RBAC is intentionally not assigned by this script: the drill uses `rbacSetupMode = Manual`. Grant the generated system-assigned principal the roles required by the current IRM drill documentation before execution. `-RegisterMissingProviders` explicitly permits provider registration; there is no implicit registration or role assignment.

## Configuration

Copy and edit `parameters.sample.json`. Names are URI-escaped and validated; subscription IDs must be GUIDs and resource IDs must be complete ARM IDs.

| Object | Required values |
|---|---|
| `serviceGroup` | Immutable `id`, mutable `displayName`, optional Service Group `parentResourceId`. A null parent uses the tenant-root Service Group. |
| `resources` | Array of full ARM resource IDs. |
| `usagePlan` | `subscriptionId`, existing `resourceGroupName`, `name`, and `location`. The official example uses `global`, which is why the sample differs from the original illustrative `eastus`. |
| `enrollment` | Nested enrollment `name`. |
| `goalAssignment` | Tenant-scoped assignment `name`. API `2026-09-30-preview` removed the goal-template dependency; the request sets zonal intent directly. |
| `drill` | Asset `subscriptionId`, existing `resourceGroupName`, drill `name`, and asset `location`. The drill itself is tenant-scoped below the Service Group. |

## Run

Complete workflow:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -Verbose
```

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
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -StartAtStage GoalAssignment -StopAfterStage DrillResources
```

Preview changes and write no resources:

```powershell
./Deploy-IrmServiceGroup.ps1 -ParameterFile ./parameters.json -WhatIf -Verbose
```

Use `-CreateMissingPrerequisites` to permit creation of a missing skipped Service Group, `-Force` for the documented mutable-property updates, `-ContinueOnResourceError` for independent member/classification errors, `-MaxConcurrency 4` for bounded membership PUT submission, and `-OutputPath ./irm-summary.json` for a machine-readable result.

## Operation mapping

| Stage | REST operation | Method | API version | Idempotency check | Verification |
|---|---|---:|---|---|---|
| ServiceGroup | `/providers/Microsoft.Management/serviceGroups/{name}` | PUT | `2024-02-01-preview` | GET and compare display name/parent | LRO then GET |
| Membership | `{resourceId}/providers/Microsoft.Relationships/serviceGroupMember/{hash}` | PUT | `2023-09-01-preview` | Deterministic name; GET and compare `targetId` | LRO then GET |
| UsagePlan | `/subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.AzureResilienceManagement/usagePlans/{name}` | PUT | `2026-08-31-preview` | GET; require Standard and matching location | LRO then GET |
| Enrollment | `{usagePlanId}/enrollments/{name}` | PUT | `2026-08-31-preview` | GET and compare `serviceGroupId` | LRO then GET |
| GoalAssignment | `{serviceGroupId}/providers/Microsoft.AzureResilienceManagement/goalAssignments/{name}` | PUT | `2026-09-30-preview` | GET and compare zonal-only intent | LRO then GET |
| Drill | `{serviceGroupId}/providers/Microsoft.AzureResilienceManagement/drills/{name}` | PUT | `2026-06-01-preview` | GET; require Zonal and SystemAssigned | LRO then GET |
| DrillResources | `{drillId}/addOrUpdateResources` | POST | `2026-06-01-preview` | List Drill Resources and classify desired state | LRO then list/compare |

## Native fault selection

The support map uses canonical types for VMs, VMSS, AKS, PostgreSQL/MySQL flexible servers, SQL databases, Load Balancer, Azure Cache for Redis, and App Service. IRM's API marks `defaultFault` read-only and Add/Update Resources accepts a Drill Resource ID. The script therefore reads each generated Drill Resource, requires an official system-provided `defaultFault.faultUrn`, and submits only the Drill Resource ID to select that default. A supported type without a returned native fault is `Unresolved`; no display-name-to-URN inference or custom runbook is used.

## Troubleshooting

- `Prerequisite failed`: create or grant access to the named object, or use `-CreateMissingPrerequisites` where supported.
- `AuthorizationFailed`/`Forbidden`: use the request ID in the error and verify access at tenant, Service Group, member, subscription, and resource-group scopes.
- Provider warning: register it explicitly or rerun with `-RegisterMissingProviders` after approval.
- LRO timeout: increase `-OperationTimeoutSeconds`; the script honors `Retry-After` and bounded exponential backoff.
- Membership conflict: inspect the deterministic relationship and remove or reconcile the conflicting target manually.
- `Unresolved` drill resource: wait for IRM discovery, verify the support matrix and returned `defaultFault`, then rerun.

## Assumptions and preview details

- The cited `2026-09-30-preview` specification and example are available. Goal templates are removed in that version; `requireZonalResiliency = true` is the required direct intent.
- The drill OpenAPI allows `SystemAssigned`, but its maximum-set example demonstrates user-assigned identities. This script uses the common ARM managed-identity schema and fails verification if the service does not retain `SystemAssigned`.
- `defaultFault` is read-only. Fault URNs are discovered from the API response and intentionally not hard-coded.
- The Add/Update Resources API operates on generated Drill Resource IDs, not member ARM IDs. IRM must finish discovering these resources before Stage 7.
- Preview behavior may require additional RBAC documented by the service. This script reports prerequisites and does not create role assignments.

References: [Service Group quickstart](https://learn.microsoft.com/azure/governance/service-groups/create-service-group-rest-api), [Azure REST API specifications](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/azureresiliencemanagement/resource-manager/Microsoft.AzureResilienceManagement/AzureResilienceManagement).