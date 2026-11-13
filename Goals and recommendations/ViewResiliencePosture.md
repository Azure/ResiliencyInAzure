# How to view the Resiliency Posture of your Service Group

This article explains how to interpret the **regional resiliency insights view** of your service group in Resiliency experiences. It covers key concepts, supported scenarios, and how to **exclude or manually attest resources** to improve the accuracy of your resilience posture and receive more targeted recommendations.

---

## Key Concepts

Once goals are assigned to your service group, the resilience summary displays three key metrics:

1. **Regionally resilient resources**  
   Resources configured with an Azure-recommended solution for regional resiliency. You may also manually attest resources using custom solutions not currently detectable by Resiliency service.

2. **Resources not regionally resilient**  
   Resources for which no regional resiliency solution has been detected.

3. **Resources not evaluated**  
   Resources excluded from evaluation by the user, or unsupported by Resiliency service.

The resource count reflects all the resources under the service group, which the user assigning the goal (or triggering rediscovery) has access to. This includes **resources under any child service groups**, **subscriptions** or **resource groups** that belong to this service group, with each resource counted only once.

> [!NOTE]
>
> - You need **Service Group Reader** permissions to view the regional resilience summary. You also need Reader access to the **resources** for which regional resiliency status needs to be viewed.
> - Newly added resources are **not automatically refreshed** post goal assignment. [Re-discovery](#rediscovering-resources) is required to include them. This limitation will be addressed in future updates.

---

## Viewing resiliency posture

To view the resiliency posture for your service group:

1. Navigate to your service group in the portal and select **Goals and Recommendations** from the menu under the Resiliency section.
2. If goals have been assigned, a summary view appears showing the distribution of resources based on their regional resiliency configuration status.
    ![Screenshot of SG resiliency summary tile view](../img/Posture-SG-View.png)
3. Select the Regional resiliency insights tile to view a detailed list of resources in the service group. This includes:
    - The regional resiliency solution configured for each resource.
    - Whether each resource is included or excluded from goal evaluation.
    ![Screenshot of SG resource resiliency list view](../img/Posture-SG-RR-Details-page.png)

> [!NOTE]
>
> - By default, all supported resource types are included in the goal evaluation.
> - There might be a temporary discrepancy between the number of recommendations shown and the number of non-regionally resilient resources. This is because the recommendations take a few hours to get updated. Use the summary tile to get the latest resilience posture of the service group.

## Override Resiliency Assessment in Specific Scenarios

In some cases, you may need to override the default resiliency assessment provided by Resiliency service. This can help ensure that recommendations align with your architectural decisions and operational context.

### Scenario 1: Exclude Non-Critical Resources

You can choose to exclude resources that are not critical to your workload’s availability.
**Example:**
Storage accounts used solely for telemetry logging may not require regional resiliency and can be excluded from evaluation.

To exclude a non-critical resource, follow the below steps:

1. Navigate to the Regional resiliency insights tile and open the resource list view.
2. Choose the resource you want to exclude and click on **Include/Exclude Resources**.
    ![Screenshot of exclude button selection](../img/RR-details-include-exclude-action.png)
3. Set the Target State to **Excluded**. In the Reason field, choose "Regional resiliency not required for this resource".
    ![Screenshot of resource being excluded](../img/RR-Details-Include-exclude-resources.png)
4. Once saved, the exemption status for the resource shows up as 'Excluded' and is counted under the 'Not Evaluated' category.

> [!NOTE]
> Resource types that are not supported by Resiliency service are automatically excluded from goal evaluation and cannot be included. However, if you are already ensuring resiliency for these resources, you can manually attest them to reflect their resiliency status in the summary view.

### Scenario 2: Manually Attest Resources

Some resources may be resilient by design, even if Azure cannot automatically detect their configuration. In such cases, you can manually mark these VMs as compliant to prevent them from being flagged in recommendations.

**Example:**
Single-instance virtual machines (VMs) deployed across multiple regions, where resiliency is managed at the application level. 

To manually attest a resource, follow the below steps:

1. Navigate to the Resiliency Summary tile in the service group and open the resource list view.
2. Choose the resource you want to exclude and click on **Include/Exclude Resources**.
3. Set the Target State to **Excluded**. In the Reason field, choose "I am ensuring regional resiliency via custom solution".
    ![Screenshot of resource being manually attested](../img/RR-Details-Include-exclude-resources.png)
4. Once saved, the exemption status for the resource shows up as 'Manually attested' and is counted under the 'Regionally resilient' category.

## Rediscovering resources

Over time, there might be changes to your service group, such as resources being added or deleted. To ensure that your resiliency posture view reflects the latest state of the service group, you can trigger the 'Re-discover resources' action to ensure that new resources are also evaluated for their regional resiliency status.

   ![Screenshot of resource rediscovery](../img/goals-rediscover-resources.png)

> [!IMPORTANT]
>
> - To rediscover resources, you must have Service Group Contributor permissions., as well as Service Group membership read access to the resources that get rediscovered.
> - Rediscovery evaluates only the resources accessible to the user who starts the action. Different users with different access can produce different rediscovery results.
>
> Example:
>
> - If User 1 has service group membership read access to resources A, B, and C and runs rediscovery, Resiliency service will consider A, B, and C as part of the service group for evaluation.
> - If User 2 later runs rediscovery and has access only to resources B and C, Resiliency service will evaluate only B and C as part of the service group for evaluation.
>
> Recommendation:
>
> - Limit who can run rediscovery and ensure those users have access to the full set of service group resources. This helps keep rediscovery results consistent and complete.

## Supported Solutions

The following table lists the Azure-supported solutions recognized by Resiliency service for each resource type. For those resources not in the list, you can still include them in the Service Group and the associated Recovery Plans and Drills and bring your own custom scripts to orchestrate recovery and bring your own fault injection scripts. 

| **Resource Type**       | **Detected Solution**                                  | ** Resource Category ** |
|-------------------------|--------------------------------------------------------| ----------------------- |
| Azure VM                | Azure Site Recovery with regional disaster recovery (or) Manual attestation     | Stateful |
| Azure Cosmos DB         | Azure Cosmos DB Multi-region Replication | Stateful |
| Azure Storage Account   | Geo-redundant storage / Geo-zone-redundant storage / Read-access geo-zone-redundant storage / Read-access geo-redundant storage | Stateful |
| Azure NetApp Files (ANF) | Cross-region replication | Stateful |
| Azure Service Bus       | Azure Service Bus Geo-Replication | Stateful |
| Azure Container Registry         | Azure Container Registry Geo-Replication | Stateful |
| Azure Key Vault | Microsoft-managed replication | Stateful | 
| Azure Front Door | Regionally resilient by default | Global |
| Azure Traffic Manager | Regionally resilient by default | Global |
| Azure Kubernetes Services         | Solution not evaluated | Stateless | 
| Azure Load Balancer         | Solution not evaluated | Stateless |
| Azure Application Gateway         | Solution not evaluated | Stateless |
| Azure Firewall         | Solution not evaluated | Stateless |
| Azure Public IP Address         | Solution not evaluated | Stateless |
| Azure App Service                | Solution not evaluated | Stateless |

## Next steps

[Review recommendations for your service group](./Recommendations.md)
