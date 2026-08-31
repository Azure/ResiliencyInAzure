# Data Resiliency and Cyber Recovery — Technical Workshop Lab Guide

Protect and recover Azure workloads with Azure Backup.

## Customer Scenario: Contoso Financial Services

Contoso is a financial-services firm running an insurance claims-processing application on Azure. Having assessed its infrastructure resiliency posture, the team now turns to protecting the data those workloads depend on.

| Component | Azure Service | Current State |
|-----------|--------------|---------------|
| Application logic & middleware | Azure VMs (claims application tier) | **Not backed up** ❌ |
| Scanned documents & media | Storage Account (blob containers) | **Not backed up** ❌ |
| VM recovery data | Recovery Services vault | Not yet created |
| Blob recovery data | Backup vault | Not yet created |
| Recovery point integrity | Microsoft Defender for Cloud | Not yet assessed |

**The challenge:** Contoso's workloads are running, but nothing is recoverable. A failed deployment, an accidental deletion, or a ransomware event would leave the claims business with no way back. Protection alone is not enough either — an attacker with valid credentials could delete recovery points or shorten retention, so the recovery data itself must be hardened and its integrity verified.

---

## Lab Environment Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure subscription | With Contributor access on the lab resource group |
| Resource providers | `Microsoft.RecoveryServices` and `Microsoft.DataProtection` registered |
| Sample VM | Claims application tier VM, with the VM agent present and running |
| Sample storage account | Containing at least one blob container with sample documents |
| Permissions | Ability to create vaults, backup policies, and role assignments |
| Defender for Servers | Plan 1 or Plan 2 enabled, required for recovery point threat assessment |
| Azure portal access | [https://portal.azure.com](https://portal.azure.com) |

> **Note:** `Microsoft.RecoveryServices` must be registered before you begin. Without it, zone-redundant and vault property options such as immutability settings are not accessible. VMs created from an Azure Marketplace image already have the VM agent installed; custom or migrated VMs may need it installed manually.

---

## Workload Journey

This guide is organized around the workloads themselves rather than by Azure artifact. Each exercise takes a workload — or both — from its current state to a verified outcome.

| Exercise | Workload in focus | What you achieve |
|----------|------------------|-------------------|
| Exercise 1 | VM workload — claims application tier | The VM goes from unprotected to protected, backed up, and verified recoverable |
| Exercise 2 | Blob workload — claim documents and logs | The storage account goes from unprotected to protected and verified |
| Exercise 3 | Both workloads | Recovery data is hardened against deletion and tampering, and restore paths are confirmed |
| Exercise 4 | Both workloads | Recovery points are assessed for compromise and threats are mapped to controls |

---

## Exercise 1 — Protect the Claims Application VM Workload

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 20 minutes |
| **Goal** | Take the claims application VM from unprotected to protected, and prove it is recoverable within Contoso's retention requirements. |

The claims application tier runs on Azure Virtual Machines and is the workload Contoso cannot afford to lose. In this exercise you follow the VM through its full protection journey: assess what it needs, stand up the protection container it will use, define how often and how long it is retained, enable protection, and confirm a usable recovery point exists.

| Attribute | Value for this lab |
|-----------|--------------------|
| Workload | Claims application tier on Azure Virtual Machines |
| Protection service | Azure Backup for Azure VMs |
| Protection container | Recovery Services vault |
| Recovery expectation | Daily recovery point, restorable within the agreed recovery window |

---

#### Task 1: Assess the VM workload's protection requirements

**Objective:** Translate Contoso's business requirements into the configuration values you will apply later in this exercise.

1. Identify the claims application VM, its resource group, and its region.

   > **Note:** The protection container must be created in the same region as the VM.

2. Confirm the VM is in a state supported for backup and that the VM agent is present.
3. Record how frequently the VM must be backed up — this determines the recovery point objective.
4. Record how long daily, monthly, and yearly recovery points must be retained to satisfy Contoso's compliance requirement.
5. Record whether Contoso needs fast local restores, which determines how long snapshots are retained for Instant Restore.

   > **Key talking point:** "Backup frequency and retention are business decisions, not technical defaults. We capture them before touching the portal so the configuration reflects what the business actually needs."

**Expected result:** You have a recorded set of values for schedule, retention, and instant restore that you reuse in Task 3, and again in Exercise 3 when hardening the workload.

#### Task 2: Stand up the protection container for the VM workload

**Objective:** Create the Recovery Services vault that will store the VM workload's recovery points.

1. Sign in to the Azure portal at [https://portal.azure.com](https://portal.azure.com).
2. In the top search bar, type **Resiliency** and go to the **Resiliency** dashboard.
3. On the **Vault** pane, select **+ Vault**.
4. Select **Recovery Services vault**, and then select **Continue**.
5. Select the lab **Subscription**, and select an existing **Resource group** or create a new one.
6. Enter a vault name that is unique to the subscription, using 2 to 50 characters, starting with a letter, and containing only letters, numbers, and hyphens.
7. Select the same **Region** as the claims application VM.
8. Select **Review + create**, and then select **Create**.
9. Once deployment completes, open the vault, and under **Settings** select **Properties**.
10. Under **Backup Configuration**, select **Update**, choose the storage replication type for the VM workload, and select **Save**.

    | Replication type | When to choose it |
    |------------------|-------------------|
    | Geo-redundant (GRS) | Default. Use when the vault is Contoso's primary backup mechanism |
    | Zone-redundant (ZRS) | Data residency requirements, resiliency within the same region |
    | Locally redundant (LRS) | Lower-cost option where offsite copies are not required |

> **Important:** Set the storage replication type **before** you protect the VM. It cannot be changed once the vault contains backup items, and changing it later means re-creating the vault and re-protecting the workload.

**Navigation path:** `Azure portal → Resiliency → Vault → + Vault → Recovery Services vault`

#### Task 3: Define how the VM workload is backed up and retained

**Objective:** Apply the values captured in Task 1 as a backup schedule and retention configuration.

1. Review the default protection behaviour first:
   - One backup per day
   - Daily recovery points retained for 30 days
   - Instant recovery snapshots retained for two days

2. If the default does not meet the requirements from Task 1, choose **Create New** during the configure backup flow to define a custom schedule.
3. Enter a policy name that identifies the workload it protects.
4. Set the backup schedule for the VM. Azure VMs support **daily** or **weekly** backups.
5. Set **Instant restore** retention to match Contoso's expectation for fast local restores.

   > **Note:** The valid range for instant restore retention is one to five days. The default is two days.

6. Set the retention range for daily or weekly recovery points.
7. Set monthly and yearly retention if long-term retention is required for the claims workload.
8. Save the configuration for use in the next task.

> **Note:** Azure Backup does not adjust automatically for daylight-saving time changes on Azure VM backups. If the claims workload requires more frequent recovery points than once a day, use the Enhanced backup policy.

**Expected result:** A backup configuration exists whose schedule and retention map directly to the requirements you recorded in Task 1.

#### Task 4: Enable protection on the VM workload

**Objective:** Apply the protection container and schedule to the actual claims application VM.

1. Go to **Resiliency**, and then select **+ Configure protection**.
2. Set **Resources managed by** to **Azure**.
3. Set **Datasource type** to **Azure Virtual machines**.
4. Set **Solution** to **Azure Backup**, and select **Continue**.
5. On the **Start: Configure Backup** pane, select **Azure Virtual machines**, select the vault created in Task 2, and select **Continue**.
6. Assign the schedule and retention configuration from Task 3.
7. Under **Virtual Machines**, select **Add**.
8. Select the claims application VM, and then select **OK**.
9. Select **Enable backup**.

> **Note:** Only VMs in the same region as the vault can be selected, and a VM is backed up by a single vault. A VM in a soft-deleted state does not appear in the selection list.

**Navigation path:** `Azure portal → Resiliency → + Configure protection → Azure Virtual machines → Azure Backup`

#### Task 5: Prove the VM workload is recoverable

**Objective:** Confirm the VM has a validated recovery point, rather than assuming configuration equals recoverability.

1. Go to **Resiliency**, then **Protected items**.
2. Set **Datasource type** to **Azure Virtual machines** and locate the claims application VM.
3. Right-click the row or select **More**, and then select **Backup Now**.
4. Use the calendar control to select the last day the recovery point should be retained, and select **OK**.
5. Go to **Resiliency**, then **Jobs**, and filter for jobs in progress.
6. Follow the job through its three phases:

   | Phase | What it does |
   |-------|-------------|
   | Snapshot | Captures a snapshot of the VM disks for Instant Restore |
   | Transfer data to vault | Copies data into the vault for long-term retention |
   | Validate backup | Verifies transferred data and confirms the recovery point is usable |

7. Confirm the VM now lists at least one recovery point.

> **Important:** Completion of **Transfer data to vault** does not by itself confirm a restorable recovery point. The VM workload is only proven recoverable once **Validate backup** succeeds.

**By the end of this exercise:**

- The claims application VM is a protected item in Azure Backup.
- Its schedule and retention match the requirements captured for the workload.
- A validated recovery point exists, so the VM workload is demonstrably recoverable.

---

## Exercise 2 — Protect the Claim Documents Blob Workload

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 20 minutes |
| **Goal** | Take the storage account holding scanned claim documents and logs from unprotected to protected, and confirm the protection model matches Contoso's recovery needs. |

Contoso's scanned claim documents, logs, and media live in Azure Blob Storage. This workload has a different protection model from the VM tier: it uses a different vault type, requires an explicit permission grant on the storage account, and offers two protection models with different recovery characteristics.

| Attribute | Value for this lab |
|-----------|--------------------|
| Workload | Scanned claim documents, logs, and media in Azure Blob Storage |
| Protection service | Azure Backup for Azure Blobs (Azure Storage) |
| Protection container | Backup vault |
| Protection models | Operational backup, vaulted backup, or both |

---

#### Task 1: Choose the protection model for the blob workload

**Objective:** Decide how the claim documents should be protected before configuring anything, because the two models have materially different recovery behaviour.

1. Compare the two available protection models:

   | | Operational backup | Vaulted backup |
   |---|-------------------|----------------|
   | Where data is held | Source storage account (local) | Backup vault (offsite) |
   | Maximum retention | 360 days | 10 years |
   | Restore target | Source storage account only | Different storage account only |
   | Schedule | Continuous, no schedule | Daily or weekly |
   | Best suited to | Fast recovery from accidental change | Long retention and ransomware resilience |

2. Decide whether the claim documents need fast local recovery, long offsite retention, or both.
3. Record the retention duration the workload requires for each model you select.
4. If you choose vaulted backup, identify now which target storage account would receive a restore.

   > **Key talking point:** "These models are complementary, not alternatives. Operational backup handles the everyday 'someone deleted a file' case. Vaulted backup is what survives a ransomware event, because the copy lives outside the storage account being attacked."

> **Important:** Deleting an entire container cannot be undone by operational backup. Delete individual blobs rather than whole containers, and enable container soft delete alongside operational backup.

**Expected result:** A documented decision on protection model and retention, with a target storage account identified if vaulted backup is in scope.

#### Task 2: Stand up the protection container for the blob workload

**Objective:** Create the Backup vault that manages protection for the blob workload.

1. Type **Backup vaults** in the portal search box.
2. Under **Services**, select **Backup vaults**.
3. On the **Backup vaults** page, select **Add**.
4. Under **Project details**, confirm the subscription and choose an existing resource group or create a new one.
5. Under **Instance details**, enter the vault name and choose the region for the blob workload.
6. Choose the **Storage redundancy**:
   - **Geo-redundant** when Azure is the primary backup storage endpoint
   - **Locally redundant** to reduce storage cost
7. Select **Review + create** and complete the deployment.

> **Note:** Storage redundancy cannot be changed after items are protected in the vault. The Backup vault is a **different resource type** from the Recovery Services vault used for the VM workload in Exercise 1.

**Navigation path:** `Azure portal → Backup vaults → Add`

#### Task 3: Grant the protection service access to the storage account

**Objective:** Give the Backup vault the permissions it needs on the storage account before configuring protection.

1. Go to the storage account holding the claim documents.
2. Open the **Access Control (IAM)** tab on the left navigation blade.
3. Select **Add role assignments**.
4. Under **Role**, choose **Storage Account Backup Contributor**.
5. Under **Assign access to**, choose **User, group or service principal**.
6. Search for the Backup vault created in Task 2 and select it from the results.
7. Select **Save**, and wait for the assignment to take effect before configuring protection.

> **Note:** The role assignment can take up to 30 minutes to take effect. You can also assign the role at the resource group or subscription level if multiple storage accounts must be protected.

> **Key talking point:** "Operational backup applies a Backup-owned Delete Lock that protects the storage account itself from accidental deletion. That is why the vault needs write-level permissions and not just read."

**Navigation path:** `Azure portal → Storage account → Access Control (IAM) → Add role assignments`

#### Task 4: Define how the blob workload is retained

**Objective:** Create the backup policy that implements the protection model chosen in Task 1.

1. Go to **Resiliency**, then **Protection policies**, and select **+ Create Policy**, then **Create Backup Policy**.
2. Select the **Datasource type** as **Azure Blobs (Azure Storage)**, and select **Continue**.
3. Enter a policy name, choose the Backup vault created in Task 2, review the vault details, and select **Next**.
4. On the **Schedule + retention** tab, select the checkboxes matching the protection model chosen in Task 1.
5. For **vaulted backups**, choose daily or weekly frequency, specify the schedule, and edit the default retention rule or add rules using grandparent-parent-child notation.
6. For **operational backups**, leave the schedule alone because they are continuous, and edit the default rule to set retention.
7. Select **Review + create**, and once the review succeeds, select **Create**.

**Expected result:** A backup policy exists whose datastore selections and retention match the decision recorded in Task 1.

#### Task 5: Enable protection on the blob workload

**Objective:** Apply the vault and policy to the storage account holding the claim documents.

1. Go to **Resiliency**, then **Overview**, and select **+ Configure protection**.
2. Under **Resources managed by**, select **Datasource type** as **Azure Blobs (Azure Storage)**, and select the solution as **Azure Backup**.
3. On the **Basics** tab, choose **Azure Blobs (Azure Storage)**, select the Backup vault, and select **Next**.
4. On the **Backup policy** tab, select the policy created in Task 4, review the details, and select **Next**.
5. On the **Datasources** tab, select the storage account holding the claim documents.
6. If you chose vaulted backup, select **Change** under **Selected containers**, then choose one of:
   - **Backup all present containers**
   - **Browse containers to backup**
   - **Backup all present and future containers**
7. Check the **Backup readiness** column to confirm the vault has sufficient permissions on the storage account.
8. If roles are still missing and you have permission, select the roles and select **Assign missing roles**, then wait for revalidation.
9. Once validation succeeds, open **Review + configure** and select **Next** to start protection.

> **Important:** **Backup all present and future containers** is a permanent choice and cannot be reversed. For vaulted backup the storage account must hold at least one container, and no more than 1000 containers can be protected.

> **Note:** You can also enable operational backup for this workload directly from the storage account, under **Data management** → **Data Protection**.

**Navigation path:** `Azure portal → Resiliency → Overview → + Configure protection → Azure Blobs (Azure Storage)`

#### Task 6: Confirm the blob workload is protected

**Objective:** Verify protection took effect and record what is actually covered.

1. Follow the portal notifications until the configure protection operation completes.
2. Confirm the storage account appears as a protected backup instance.
3. Record which containers are covered by protection.
4. Record the active protection model and retention applied to the workload.
5. Note any storage account that failed validation and the corrective action required.

**By the end of this exercise:**

- The claim documents storage account is protected by Azure Backup.
- The protection model chosen matches Contoso's recovery and retention needs.
- You can explain why the blob workload uses a different vault type and permission model from the VM workload.

---

## Exercise 3 — Harden Both Workloads Against Data Destruction

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 15 minutes |
| **Goal** | Protect the recovery data for both workloads so that a malicious or accidental operation cannot destroy Contoso's ability to recover. |

Both workloads are now protected, but protection alone does not stop an attacker with valid credentials from deleting recovery points or shortening retention. In this exercise you harden the recovery data for each workload and confirm which restore paths remain available in a disaster.

---

#### Task 1: Harden the VM workload's recovery data

**Objective:** Apply vault immutability so operations that would destroy VM recovery points are blocked.

1. Open the Recovery Services vault protecting the claims application VM.
2. Locate the immutability setting under the vault security or properties settings.
3. Review the three available states:

   | State | Behaviour |
   |-------|-----------|
   | **Disabled** | No operations are blocked |
   | **Enabled** | Operations that could result in loss of backups are blocked. Reversible |
   | **Enabled and locked** | WORM storage enabled, cannot be disabled. **Irreversible** |

4. Set the vault to **Enabled** so operations that would destroy VM recovery points are blocked.
5. Keep the vault unlocked for this lab unless the instructor confirms the environment is disposable.
6. Record the state you applied — you reference it during threat analysis in Exercise 4.

   Once hardened, the following operations behave differently per workload:

   | Workload | Operation blocked once hardened | What remains possible |
   |----------|--------------------------------|----------------------|
   | VM workload | Stopping protection and deleting its recovery points | Stopping protection while retaining data until expiry |
   | VM workload | Editing the schedule so retention is reduced | Increasing retention and changing the backup schedule |
   | VM workload | Swapping in a configuration with lower retention | Swapping in a configuration with higher retention |
   | Blob workload | Deleting recovery points before their expiry dates | Stopping protection while retaining data |

> **Note:** Hardening applies to every item protected in that vault. It does **not** apply to operational backup of blobs, so the blob workload is only fully covered when vaulted backup is in use.

**Navigation path:** `Azure portal → Recovery Services vault → Properties → Security settings`

#### Task 2: Decide whether to make hardening irreversible

**Objective:** Understand the consequence of locking immutability before recommending it to a customer.

1. Confirm that the **Enabled** state is reversible and can be turned off if recovery data must be deleted.
2. Confirm that **Enabled and locked** applies WORM storage, cannot be turned off, and is permanent.
3. Assess whether the lab environment is disposable enough to demonstrate the locked state.
4. Record the final state for each workload and the justification you would give Contoso.

> **Important:** Lock a vault only after the operational impact is understood, because the decision cannot be reversed.

**Expected result:** A documented position on whether Contoso should lock immutability in production, with reasoning.

#### Task 3: Confirm the restore path for each workload

**Objective:** Establish how each workload would actually be recovered in each disaster scenario.

1. Review the restore path available to each workload:

   | Scenario | VM workload restore path | Blob workload restore path |
   |----------|-------------------------|---------------------------|
   | Accidental change or deletion | Restore from a recovery point in the vault | Operational backup restore to the source storage account |
   | Regional disruption | Cross Region Restore into the secondary region | Vaulted backup restore to a storage account in another location |
   | Recovery into another subscription | Cross Subscription Restore | Restore to a storage account in the target subscription |

2. Confirm the storage replication type set in Exercise 1 supports the VM restore path Contoso expects.
3. Confirm a target storage account is identified for the blob workload, since vaulted backup restores only to a different account.
4. Record which restore path Contoso would use for a regional disruption, and which applies to accidental data loss.

   > **Key talking point:** "Cross Region Restore only works if the vault was configured for geo-redundancy up front. This is why the replication decision in Exercise 1 had to be made before any workload was protected."

**By the end of this exercise:**

- Recovery data for the VM workload is hardened against deletion and retention tampering.
- The limits of hardening for the blob workload are understood and documented.
- A restore path is identified for each workload for both accidental loss and regional disruption.

---

## Exercise 4 — Assess the Workloads for Cyber Threats

| Property | Value |
|----------|-------|
| **Level** | L300 |
| **Duration** | 15 minutes |
| **Goal** | Determine whether Contoso's recovery points are trustworthy, and map the threats each workload faces to the controls now in place. |

Recovering from ransomware only helps if the recovery point itself is clean. Azure Backup integrates with Microsoft Defender for Cloud to evaluate the health of Azure VM recovery points using signals such as disruption patterns, behavioural anomalies, and ransomware signatures.

---

#### Task 1: Turn on threat assessment for the VM workload

**Objective:** Enable Azure Backup threat detection so recovery points are evaluated as they are created.

1. Confirm the lab subscription has **Defender for Servers Plan 1 or Plan 2** enabled.

   > **Note:** The assessment depends on Defender for Servers signals. Without a plan enabled, recovery points cannot be evaluated.

2. Navigate to the Recovery Services vault protecting the claims application VM.
3. Under **Settings**, go to **Properties**.
4. Open the security settings section and locate the **Threat Detection** setting.
5. Enable threat detection and update the vault.
6. Confirm that enabling it at the vault level covers every VM protected in that vault.

> **Note:** Threat assessment for Azure VM backups is available in preview in all Azure public regions except UAE Central, Israel Central, Qatar Central, and Israel North West.

**Navigation path:** `Azure portal → Recovery Services vault → Properties → Security settings → Threat Detection`

#### Task 2: Confirm the assessment is configured for the workload

**Objective:** Verify the VM workload's recovery points are actually being assessed.

1. Open the vault and review the configuration status shown for the claims application VM.

   | Status | What it means for the workload |
   |--------|-------------------------------|
   | **Configured** | The VM workload's recovery points are being assessed |
   | **Not Configured** | Assessment is not yet switched on for items in this vault |
   | **Configuration Failed** | Assessment could not be set up because of configuration errors |
   | **Not Applicable** | Defender for Servers coverage was downgraded after setup |

2. Record the status, and resolve it if it shows anything other than **Configured**.

**Expected result:** The claims application VM shows a **Configured** source-scan status.

#### Task 3: Judge whether the VM workload's recovery points are clean

**Objective:** Use the assessment results to decide which recovery point you would actually restore from.

1. Take an on-demand backup so a new recovery point is created and assessed.
2. Go to **Backup items** in the Recovery Services vault and select **Azure Virtual Machine**.
3. Select the protected item for the claims application VM and select **View details**.
4. Open the **Recovery points** section and review the health reported for each recovery point.

   | Result | Recovery decision it drives |
   |--------|----------------------------|
   | **No Threats Reported** | Recent recovery points are clean and can be used with confidence |
   | **Suspicious RPs found** | At least one recent recovery point may be compromised; select an alternative |
   | **Not Applicable** | Defender for Servers coverage was downgraded for this VM |
   | **Unknown (-)** | Assessment is not configured or has failed, so cleanliness is unproven |

5. Record the result and state which recovery point you would restore from during an incident.

   > **Key talking point:** "This is the difference between having a backup and having a trustworthy backup. Without this signal, a customer recovering from ransomware may restore the malware along with the data."

> **Note:** If the VM has active ransomware alerts when assessment is switched on, the summary can take up to 48 hours to change to **Suspicious**.

#### Task 4: Map each workload's threats to the controls in place

**Objective:** Close the lab by connecting each configured control back to the threat it defends against.

1. Review how each threat maps to the controls configured across this guide:

   | Threat to the workload | Affected workload | Control configured in this lab |
   |------------------------|------------------|-------------------------------|
   | Compromised operator deletes recovery data | VM and Blob | Vault hardening blocks operations that destroy recovery points |
   | Attacker shortens retention so recovery points expire | VM | Hardening disallows any change that reduces retention |
   | Attacker deletes the storage account outright | Blob | Backup-owned Delete Lock applied by operational backup |
   | Ransomware encrypts data before the backup runs | VM | Threat assessment flags suspicious recovery points and surfaces clean ones |
   | Protection silently stops working | VM and Blob | Job phases and job monitoring in the Resiliency dashboard |

2. Confirm which of the controls above are active for each workload in your lab.
3. Record any control recommended for production but unavailable in the lab tenant.
4. Record the residual risk that remains for each workload after this lab.
5. Write one recommendation for Contoso that closes the most significant residual risk.

**By the end of this exercise:**

- Threat assessment is enabled and its results are understood for the VM workload.
- The cleanliness of the VM workload's recovery points has been judged.
- Threats are mapped per workload to the controls configured across this lab.

---

## Workshop Summary

| Exercise | Journey | What You Accomplished |
|----------|---------|----------------------|
| Exercise 1 | Protect compute | Created a Recovery Services vault, defined schedule and retention, enabled VM backup, validated a recovery point |
| Exercise 2 | Protect data | Created a Backup vault, granted storage permissions, chose a protection model, enabled blob protection |
| Exercise 3 | Harden | Applied vault immutability, decided on locking, confirmed restore paths per workload |
| Exercise 4 | Verify trust | Enabled threat assessment, judged recovery point cleanliness, mapped threats to controls |

---

## Three Recovery Pillars Recap

| Pillar | Customer Moment | Azure Backup Capability | Outcome |
|--------|----------------|------------------------|---------|
| **Data Resiliency** | "Can we get this workload back?" | Vault, backup policy, protected items, validated recovery points | Both compute and data layers are recoverable |
| **Cyber Resiliency** | "Can an attacker destroy our backups?" | Vault immutability, Delete Lock, retention enforcement | Recovery data survives credential compromise |
| **Recovery Confidence** | "Is this restore point safe to use?" | Threat detection with Microsoft Defender for Cloud | Clean recovery points identified before restore |

---

## Additional Resources

| Resource | Link |
|----------|------|
| Azure Backup documentation | [learn.microsoft.com/azure/backup](https://learn.microsoft.com/azure/backup/) |
| Back up Azure VMs in a Recovery Services vault | [learn.microsoft.com/azure/backup/backup-azure-arm-vms-prepare](https://learn.microsoft.com/azure/backup/backup-azure-arm-vms-prepare) |
| Create and manage Backup vaults | [learn.microsoft.com/azure/backup/create-manage-backup-vault](https://learn.microsoft.com/azure/backup/create-manage-backup-vault) |
| Configure backup for Azure Blobs | [learn.microsoft.com/azure/backup/blob-backup-configure-manage](https://learn.microsoft.com/azure/backup/blob-backup-configure-manage) |
| Immutable vault for Azure Backup | [learn.microsoft.com/azure/backup/backup-azure-immutable-vault-concept](https://learn.microsoft.com/azure/backup/backup-azure-immutable-vault-concept) |
| Threat detection in Azure Backup | [learn.microsoft.com/azure/backup/threat-detection-overview](https://learn.microsoft.com/azure/backup/threat-detection-overview) |

---

## Appendix

### Resources in the application

| Resource | Workload it serves | Example name |
|----------|-------------------|--------------|
| Azure Virtual Machine | Claims application tier | `ContosoClaimsApp-VM1` |
| Storage account with blob container | Scanned documents, logs, and media | `ContosoClaimsApp-SA1` |
| Recovery Services vault | VM workload protection container | `rsv-lab-<alias>-<region>` |
| Backup vault | Blob workload protection container | `bv-lab-<alias>-<region>` |
| Defender for Servers plan | Threat assessment for the VM workload | Plan 1 or Plan 2 |

### Naming conventions

| Artifact | Convention |
|----------|-----------|
| VM workload protection container | `rsv-lab-<alias>-<region>` |
| Blob workload protection container | `bv-lab-<alias>-<region>` |
| VM workload protection configuration | `bp-vm-claims-daily-<retention>` |
| Blob workload protection configuration | `bp-blob-claims-<model>-<retention>` |

<!-- TODO: Add the architecture diagram for the claims application -->
<!-- TODO: Add screenshots for the VM workload journey: vault, schedule and retention, enable protection, recovery point -->
<!-- TODO: Add screenshots for the blob workload journey: vault, IAM role, retention, configure protection -->
<!-- TODO: Add screenshots for vault hardening on both workloads -->
<!-- TODO: Add screenshots for threat assessment configuration and recovery point health -->
<!-- TODO: Confirm final tenant-specific portal labels after lab environment validation -->
