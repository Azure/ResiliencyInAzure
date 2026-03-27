# Role Based Access Control (RBAC) Requirements for Resiliency preview scenarios

The following table lists the RBAC roles that can be leveraged by users to achieve specific resiliency management requirements.

## Service Group Management

| Scenario | Roles |
|----------|--------------------------|
| Create service group and add/remove member resources in the service group | 1. Microsoft.Relationship/ServiceGroupMember/write access on the resources that are being added to the service group <br> 2. Service Group contributor |

## Goals and Recommendations

| Scenario | Roles |
|----------|--------------------------|
| Assign goals to service group | 1.  Service Group contributor <br>2.  Microsoft.Relationship/ServiceGroupMember/read access to the resources under the service group |
| View counts of resilient, non-resilient, not evaluated resources under the service group (after goal assignment) | 1.  Service Group reader |
| View list of resources under the service group and their zone resiliency configuration status (after goal assignment) | 1.  Service Group reader <br>2.  Reader access to the resources within the service group |
| Include/Exclude/Attest resources in the service group (after goal assignment) | 1.  Service Group contributor |
| Rediscover resources in the service group | 1.  Service Group contributor <br>2.  Microsoft.Relationship/ServiceGroupMember/read access to the required resources under the service group |
| View Service Group level recommendations | 1.  Service Group reader |
| View resource level recommendations for resources under the Service Group (after goal assignment) | 1.  Service Group reader <br>2.  Reader access to the resources for which recommendations need to be viewed |
| Postpone/Dismiss recommendations | 1.  Contributor access to the resources for which recommendations need to be dismissed/postponed |

## Recovery Plan

| Scenario | Roles |
|----------|--------------------------|
| Create and Execute Recovery Plan | 1. **Recovery Contributor**: Required on the Service Group. <br> 2. **Reader Access**: Required on the subscription or resource group that is a member of the Service Group. This ensures that underlying resources can be discovered. <br><br> **For Recovery Plans containing VMs using Azure Site Recovery, the following additional permissions are required:** <br><br> 1. **Service Group Contributor**: Required on the Service Group. <br> 2. **Microsoft.Relationship/ServiceGroupMember/write**: Required on the linked recovery resource (e.g., VM created during failover) to add the new VM to the Service Group. <br> 3. **Site Recovery Operator**: Required on the Recovery Services vault used by the VM. This permission must be assigned to the managed identity of the Recovery Plan. <br><br> **For users utilizing custom runbooks in the Recovery Plan, the following additional permissions are required:** <br><br> 1. **Automation Job Operator**: Required on the associated Automation Account. <br><br> **For enabling zone redundancy on resources, the following additional permissions are required:** <br><br> 1. **Contributor Access**: Required on resources to enable zone redundancy before creating and executing the Recovery Plan.|

## Drills

| Scenario | Roles |
|----------|--------------------------|
| Create/Update/Execute Drills |  1. **SG Drill Contributor** on the **Service Group** <br> 2. **Drill Assets Contributor** on the **subscription** associated with Automation Account and Chaos experiment <br> 3. **Drill Resource Fault Contributor** on the **resources** on which fault injection should be performed.|
| Monitor Service Group metrics health during drill execution |  1. **Log Analytics Contributor + Monitoring Contributor** in the chosen subscription → for creating the monitoring infrastructure (Log analytics workspace, tables, Data Collection Endpoints (DCE), Data Collection Rules (DCR))  <br> 2. **User Access Administrator** → for assigning roles on the Log Analytics subscription and on each of the drill resources’ subscriptions. |
