# Infrastructure Resiliency Manager & Resiliency Agent — Technical Workshop Lab Guide

## Customer Scenario: Contoso Financial Services

Contoso is a financial-services firm running an insurance claims-processing application on Azure. Their estate includes:

| Component | Azure Service | Current State |
|-----------|--------------|---------------|
| Application logic & middleware | Azure VMs (3-tier) | Deployed across zones |
| Microservices frontend | AKS cluster (3 nodes, zones 1/2/3) | Zone-redundant compute |
| Order/claims database | Azure SQL Database (GP_Gen5_2) | **Not zone-redundant** ❌ |
| Scanned documents & media | Storage Account (Standard_LRS) | **Not zone-redundant** ❌ |
| Container images | Azure Container Registry | Zone-redundant ✅ |
| Traffic routing | Standard Load Balancer | Zone-redundant ✅ |

**The challenge:** Contoso's compute layer looks resilient on the surface — AKS nodes are spread across zones. But backend dependencies (SQL, Storage) are not zone-redundant. A zone failure could keep compute alive while data services become unreachable.

---

## Lab Environment Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure subscription | With Contributor or Owner access |
| Resource groups | Pre-provisioned with sample resources (AKS + SQL + Storage) |
| Azure portal access | [https://portal.azure.com](https://portal.azure.com) |
| Resiliency Agent access | Azure Copilot with Resiliency Agent enabled |
| Pre-created Service Groups | `IRMDemoSGDayZero` (blank), `IRMDemoSG1` (AKS app with goals + drill) |
| Sample AKS App | E-commerce storefront with status bar and infrastructure panel |

> **Note:** Your lab environment has been pre-provisioned. Verify access by navigating to **Azure portal → Resiliency** and confirming you can see the Infrastructure Resiliency Manager dashboard.

---

## Lab 1 — Introduction to Resilient Cloud Design

| Property | Value |
|----------|-------|
| **Level** | L100 |
| **Duration** | 20 minutes |
| **Goal** | Build foundational awareness of Azure resiliency concepts before beginning hands-on configuration |

---

### Exercise 1.1: Explore Availability Zones in Azure

**Objective:** Understand how Availability Zones provide physical isolation within an Azure region.

#### Task 1: Review Availability Zone architecture

1. Open the Azure portal at [https://portal.azure.com](https://portal.azure.com).
2. In the top search bar, type **Resiliency** and select **Resiliency** from the results.
3. In the left navigation menu, expand **Infrastructure Resiliency**.
4. Select **Overview** to see the centralized resiliency dashboard.

   > **Expected result:** You see the Infrastructure Resiliency Manager overview with tiles showing zone-resilient vs. non-resilient resource counts.

5. Note the categorization of resources:
   - **Zone resilient** — Resources configured with a zone resiliency solution
   - **Non-zone resilient** — Resources without zone redundancy configured
   - **Not evaluated** — Resources not yet supported by the resiliency service

#### Task 2: Understand the shared responsibility model for reliability

1. From the **Resiliency** dashboard, select **Resource Resiliency** in the left menu.
2. Review the resource list and observe the **Resiliency Status** column.
3. For any resource marked **Zone Resilient**, click on it to view the detected resiliency solution.

   > **Key concept:** Azure provides the platform capabilities (Availability Zones, zone-redundant SKUs), but customers are responsible for configuring their resources to use these capabilities. IRM helps bridge this gap.

4. Click on any resource marked **Non-zone resilient** and select **View Recommendation**.

   > **Expected result:** You see an Azure Advisor recommendation explaining what configuration change is needed to make this resource zone-resilient.

#### Task 3: Explore Azure region pairs and zone-redundancy options

1. Navigate to **Azure portal → Create a resource → Storage account**.
2. On the **Basics** tab, observe the **Redundancy** dropdown options:
   - **LRS** (Locally Redundant Storage) — single datacenter
   - **ZRS** (Zone-Redundant Storage) — spread across 3 availability zones
   - **GRS/GZRS** — cross-region replication
3. **Do not create the resource** — this is observation only.
4. Navigate back to the **Resiliency** dashboard.

> **Summary:** You now understand that Availability Zones are physically separate datacenters within a region, and that configuring zone redundancy is a customer responsibility that IRM helps you manage at scale.

---

### Exercise 1.2: Navigate Infrastructure Resiliency Manager

**Objective:** Familiarize yourself with the IRM portal experience and its core navigation structure.

#### Task 1: Explore the IRM menu structure

1. In the Azure portal, navigate to **Resiliency → Infrastructure Resiliency**.
2. Observe the left menu items:
   - **Overview** — At-scale summary dashboard
   - **Resource Resiliency** — Individual resource posture
   - **Service Group Resiliency** — Application-level groupings
   - **Recommendations** — Remediation guidance
   - **Recovery Plans** — Orchestrated recovery sequences
   - **Drills** — Zone-down simulation experiments
   - **Usage Plans** — Enable customers to specify billing subscription details

3. Select **Service Group Resiliency**.
4. Observe the service groups listed and their status indicators.

   > **Expected result:** You see service groups categorized as Zone Resilient, Non-Zone Resilient, Goals Not Assigned, or Not Evaluated.

5. Identify `IRMDemoSGDayZero` — this is an empty service group you will configure in Lab 3.
6. Identify `IRMDemoSG1` — this is the pre-configured AKS app service group you will use in Labs 2–4.

**Navigation path:** `Azure portal → Resiliency → Infrastructure Resiliency → Service Group Resiliency`

---

## Lab 2 — Resiliency Posture Review

| Property | Value |
|----------|-------|
| **Level** | L200 |
| **Duration** | 25 minutes |
| **Goal** | Understand how to inspect and interpret an application's resiliency posture using IRM. This is an inspection-only lab — participants do not make changes. |

---

### Exercise 2.1: Inspect the IRM Service Group Posture View

**Objective:** Review the resiliency posture of an existing application modeled as a Service Group.

#### Task 1: Open the Service Group at-scale view

1. Navigate to **Azure portal → Resiliency → Infrastructure Resiliency → Overview**.
2. Observe the at-scale summary:
   - Total zone-resilient service groups
   - Total non-resilient service groups
   - Total resource count by posture

   > **Key talking point:** "This is what a platform team sees when managing dozens of applications — which apps meet zone resilience goals and which don't."

3. Select the **Service Group Resiliency** tile to see the detailed list.

#### Task 2: Drill into IRMDemoSG1 (AKS e-commerce app)

1. From the Service Group list, select **IRMDemoSG1**.
2. Review the **Resiliency Goal** — it should show **Zone Resilient** as the target.
3. Examine the resource-by-resource posture for `IRMDemoSG1`:

   | Resource | Resiliency Status | Zone Resilient? |
   |----------|------------------|-----------------|
   | AKS Cluster (3 nodes, zones 1/2/3) | Zone-redundant | ✅ |
   | Azure Load Balancer (Standard SKU) | Zone-redundant | ✅ |
   | Azure Container Registry | Zone-redundant by default | ✅ |
   | Azure SQL Database (GP_Gen5_2) | Not zone-redundant | ❌ |
   | Storage Account (Standard_LRS) | Not zone-redundant | ❌ |

4. Note the **overall service group status** — it shows **Non-Zone Resilient** because not all members meet the goal.

   > **Expected result:** You can see exactly which resources are dragging the overall posture down and why.

#### Task 3: Understand resiliency states

1. While viewing `IRMDemoSG1`, identify resources in each state:
   - **Zone-resilient** — The resource is configured with an Azure-recommended zonal resiliency solution (e.g., AKS with zone-redundant node pools).
   - **Non-resilient** — The resource lacks zone redundancy configuration (e.g., SQL Database without zone redundancy enabled).
   - **Not-evaluated** — The resource type is not yet supported by the resiliency service for evaluation.

2. For each **non-resilient** resource, click **View Recommendation** to preview what remediation would involve.

   > **Do not act on recommendations yet** — that is covered in Lab 3.

**Navigation path:** `Azure portal → Resiliency → Infrastructure Resiliency → Service Group Resiliency → IRMDemoSG1`

---

### Exercise 2.2: Review Azure Advisor Reliability Recommendations

**Objective:** Understand how Azure Advisor Reliability pillar recommendations surface within IRM.

#### Task 1: Navigate to recommendations within IRM

1. From the `IRMDemoSG1` service group view, select the **Recommendations** tab.
2. Review the list of recommendations — each is scoped to resources within this service group.
3. For each recommendation, note:
   - **Impacted resource** — Which specific resource needs action
   - **Recommendation** — The specific configuration change suggested
   - **Cost indicator** — High / Medium / Low / No cost impact

   | Resource | Recommendation | Cost Impact |
   |----------|---------------|-------------|
   | Azure SQL Database | Enable zone redundancy | Medium |
   | Storage Account | Convert LRS → ZRS | Low |

4. Click on any recommendation to expand the details:
   - Step-by-step remediation instructions
   - Link to relevant documentation
   - Estimated impact and effort

#### Task 2: Compare resource-level vs. service-group-level views

1. Navigate back to **Resiliency → Infrastructure Resiliency → Resource Resiliency**.
2. Filter by the resource group containing your lab resources.
3. Compare: The resource-level view shows individual resources regardless of application grouping.
3. Navigate back to **Service Group Resiliency → IRMDemoSG1**.
5. Compare: The service group view shows the same resources in the context of an application, with a shared resiliency goal.

   > **Key insight:** Service groups provide an application-centric view. A single resource can belong to multiple service groups if it serves multiple applications.

---

## Lab 3 — Start and Get Resilient with IRM and Advisor

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 60 minutes |
| **Goal** | Move from identifying resiliency gaps to configuring and remediating the posture of a migrated application |

---

### Exercise 3.1: Create a Service Group for a Migrated Application

**Objective:** Model your application in IRM by creating a Service Group and setting a zonal resiliency goal.

#### Task 1: Create a new Service Group

1. Navigate to **Azure portal → Resiliency → Infrastructure Resiliency → Service Group Resiliency**.
2. Select **+ Create Service Group**.
3. On the **Basics** tab:
   - **Service Group Name:** `ContosoClaimsApp-Lab`
   - **Subscription:** Select your lab subscription
   - **Parent Service Group:** Leave empty (top-level group)
4. Select **Next: Members**.

#### Task 2: Add resources to the Service Group

1. On the **Members** tab, select **+ Add resources**.
2. Use the resource picker to add the following resources from your lab environment:
   - AKS Cluster
   - Azure SQL Database
   - Storage Account
   - Load Balancer
   - Container Registry
3. Review the selected resources and confirm.
4. Select **Next: Review + Create**.
5. Select **Create**.

   > **Expected result:** Your service group `ContosoClaimsApp-Lab` is created and appears in the Service Group Resiliency list with status "Goals Not Assigned."

**Navigation path:** `Azure portal → Resiliency → Infrastructure Resiliency → Service Group Resiliency → + Create Service Group`

#### Task 3: Set a zonal resiliency goal

1. Open your newly created service group `ContosoClaimsApp-Lab`.
2. Select **Assign Goal**.
3. Set the resiliency goal to **Zone Resilient**.
4. Select **Save**.

   > **Expected result:** The system evaluates all member resources against the zone-resilient goal. You now see a posture summary showing which resources meet the goal and which do not.

5. Review the posture breakdown:
   - Resources meeting the goal (zone-resilient)
   - Resources with gaps (non-zone-resilient)
   - Resources not yet evaluated

---

### Exercise 3.2: Review Contextual Azure Advisor Reliability Recommendations

**Objective:** Review and understand recommendations surfaced by IRM for your service group.

#### Task 1: Review recommendations with cost indicators

1. From your service group `ContosoClaimsApp-Lab`, navigate to the **Recommendations** tab.
2. Review each recommendation and its **cost impact indicator**:
   - **High** — Significant cost increase (e.g., adding replicas)
   - **Medium** — Moderate cost increase (e.g., upgrading SKU tier)
   - **Low** — Minimal or no cost impact (e.g., configuration toggle)
   - **No cost** — Free configuration change

3. Note how recommendations are prioritized: Start with low-cost, high-impact changes.

#### Task 2: Export a prioritized action plan

1. From the **Recommendations** tab, select **Export**.
2. Choose the export format (CSV or PDF).
3. Review the exported action plan — it contains:
   - Resource name and type
   - Current configuration
   - Recommended change
   - Cost indicator
   - Priority

   > **Expected result:** You have a prioritized, exportable action plan that can be shared with your team for planning and execution.

---

### Exercise 3.3: Apply Copilot-Powered Remediation with the Resiliency Agent

**Objective:** Use the Resiliency Agent in Azure Copilot to generate remediation guidance and zone-resilient IaC templates for non-resilient resources.

#### Task 1: Open the Resiliency Agent

1. In the Azure portal, select the **Copilot** icon (✨) in the top toolbar.
2. The Azure Copilot pane opens on the right side.
3. The Resiliency Agent is available — type your first prompt.

#### Task 2: Generate remediation guidance for non-resilient resources

1. In the Copilot pane, type:

   ```
   Enable zone resiliency for all non-resilient resources in my service group ContosoClaimsApp-Lab
   ```

2. The Resiliency Agent responds with:
   - **What can be fixed in place** — Portal toggle to enable zone redundancy (brief disconnect expected)
   - **What needs script/automation** — If migration between tiers is required
   - **What requires manual effort** — Support requests or architecture changes

3. Review the categorized remediation guidance.

   > **Expected result:** The agent provides a structured breakdown of remediation effort by complexity level.

#### Task 3: Generate zone-resilient Bicep templates

1. In the Copilot pane, type:

   ```
   Generate zone-resilient Bicep templates for my SQL Database and Storage Account in ContosoClaimsApp-Lab
   ```

2. The Resiliency Agent responds with:
   - A **guidance report** — which services need zone redundancy and what configurations to set
   - **Modular Bicep templates** with zone-redundancy baked in:
     - Azure SQL Database with `zoneRedundant: true`
     - Storage Account configured as ZRS (Zone-Redundant Storage)
   - **Cost implications** and trade-offs for each resilience choice

3. Review the generated Bicep code. Example expected output:

   ```bicep
   resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
     name: '${sqlServerName}/${databaseName}'
     location: location
     properties: {
       zoneRedundant: true
     }
     sku: {
       name: 'GP_Gen5'
       tier: 'GeneralPurpose'
       capacity: 2
     }
   }

   resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
     name: storageAccountName
     location: location
     sku: {
       name: 'Standard_ZRS'
     }
     kind: 'StorageV2'
   }
   ```

4. Copy the generated templates for use in your deployment pipeline.

   > **Key talking point:** "IRM doesn't just tell you what's wrong — the agent categorizes each fix by effort and generates deployment-ready IaC templates with zone-redundancy baked in."

#### Task 4: Validate generated templates

1. In the Copilot pane, type:

   ```
   Validate the zone-resilient Bicep templates you generated — confirm they meet zone redundancy requirements
   ```

2. The agent confirms:
   - Template syntax is valid
   - Zone-redundancy configurations are correctly applied
   - Cost estimate for the changes

#### Task 5: Start Resilient — Generate templates for a new deployment (optional)

1. In the Copilot pane, type:

   ```
   I need to deploy an e-commerce application on AKS in West US 2 with a SQL database for order processing and a storage account for product images. Generate zone-resilient Bicep templates.
   ```

2. The Resiliency Agent responds with:
   - A comprehensive guidance report
   - Modular Bicep templates with zone-redundancy baked in:
     - AKS cluster with zone-redundant node pools across zones 1, 2, 3
     - Azure SQL Database with zone redundancy enabled
     - Storage Account configured as ZRS
     - Standard Load Balancer with zone-redundant frontend
   - Cost implications and trade-offs

   > **Key talking point:** "The proof point is that you leave this conversation with deployable, resilient-by-default infrastructure-as-code in the tooling you already use — Bicep, Terraform, or ARM templates. Not a list of recommendations to figure out later."

---

## Lab 4 — Stay Resilient and Ensure Continuity

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 45 minutes |
| **Goal** | Explore drills and validate operational recovery readiness |

---

### Exercise 4.2: Explore Zone-Down Drills (Chaos Studio Integration)

**Objective:** Understand how to create and review Zone-Down Drills to validate application resilience.

#### Task 1: Explore the entry point for creating a new drill

1. Navigate to **Azure portal → Resiliency → Infrastructure Resiliency → Drills**.
2. Select **+ Create Drill** to see the interface.
3. Note the fields for:
   - **Drill name**
   - **Service Group** selection
   - **Target Zone** specification
4. **Do not complete the creation** — this is exploration only. Select **Cancel**.

   > **Key insight:** The drill creation flow allows you to select which service group to test and which zone to simulate failing.

#### Task 2: Review the pre-created drill for IRMDemoSG1

1. Navigate back to **Drills** and select an existing drill associated with **IRMDemoSG1**.
2. Review the **Fault Designer**:

   | Resource | Included in Drill? | Fault Type |
   |----------|--------------------|------------|
   | AKS Cluster | ✅ Yes | Node pool shutdown in target zone |
   | Load Balancer | ✅ Yes | Zone-redundant — continues routing |
   | SQL Database | ⛔ Excluded | Non-ZR — would cause expected failures |
   | Storage Account | ⛔ Excluded | Non-ZR — would cause expected failures |

   > **Key insight:** We exclude non-resilient resources deliberately. The drill validates what *should* survive a zone failure. Non-resilient resources are excluded to avoid expected (but uninformative) failures.

#### Task 3: Review drill configuration and permissions

1. Select **Settings → Identity and permissions** on the drill pane.
2. Under **Role assignment status**, review:
   - ✅ Chaos Studio identity has required permissions
   - ✅ The drill identity has permissions on target resources

   > **Expected result:** All role assignments are in place. The drill is ready to execute if needed.

#### Task 4: View the drill execution entry point

1. Navigate back to the drill overview pane.
2. Locate the **Start Drill** button at the top of the pane.
3. Note the options for:
   - **Target Zone** — Select which zone to simulate failing
   - **Execution controls** — Start, monitor, and stop the drill
4. **Do not execute the drill** — this is observation only.

   > **Key insight:** Executing a full drill would take 10–15 minutes. In a real scenario, you would select your target zone and confirm execution to simulate the zone outage and validate application resilience.



---

## Workshop Summary

| Lab | Journey | What You Accomplished |
|-----|---------|----------------------|
| Lab 1 | Foundations | Explored Availability Zones, IRM navigation, shared responsibility model |
| Lab 2 | Assess | Inspected service group posture, understood zone-resilient/non-resilient/not-evaluated states |
| Lab 3 | Start & Get Resilient | Created service group, set goals, used Resiliency Agent for remediation + IaC generation |
| Lab 4 | Stay Resilient | Explored drills and validated recovery readiness |

---

## Three Customer Journeys Recap

| Journey | Customer Moment | IRM Capability | Outcome |
|---------|----------------|----------------|---------|
| **Start Resilient** | Greenfield — deploying something new | Resiliency Agent generates guidance + resilient IaC | Deploys resilient from day zero |
| **Get Resilient** | Brownfield — hardening existing estate | At-scale assessment → per-app drill-down → Copilot remediation | Knows posture, closes gaps with deployment-ready code |
| **Stay Resilient** | Steady-state — preventing drift | Config drift detection + compliance drills + recovery orchestration | Catches regression, proves readiness for audits |

---

## Additional Resources

| Resource | Link |
|----------|------|
| IRM Overview | [learn.microsoft.com/azure/resiliency/infrastructure-resiliency-manager-overview](https://learn.microsoft.com/azure/resiliency/infrastructure-resiliency-manager-overview) |
| Goals & Recommendations | [learn.microsoft.com/azure/resiliency/goals-recommendations-about](https://learn.microsoft.com/azure/resiliency/goals-recommendations-about) |
| Zone-Down Drills | [learn.microsoft.com/azure/resiliency/availability-zone-down-drills-about](https://learn.microsoft.com/azure/resiliency/availability-zone-down-drills-about) |
| Recovery Plans | [learn.microsoft.com/azure/resiliency/recovery-orchestration-plan-about](https://learn.microsoft.com/azure/resiliency/recovery-orchestration-plan-about) |
| What's New in Resiliency | [learn.microsoft.com/azure/resiliency/resiliency-whats-new](https://learn.microsoft.com/azure/resiliency/resiliency-whats-new) |
