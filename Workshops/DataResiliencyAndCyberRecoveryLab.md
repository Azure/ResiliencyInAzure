# Lab 3: Data Resiliency and Cyber Recovery

**Backup and DR for Azure workloads with Azure Backup**

| Duration | Level | Format | Primary service |
| --- | --- | --- | --- |
| 70 minutes | L300 | Hands-on | Azure Backup |

## Objective

In this lab, you protect the two workloads that carry Contoso's claims processing application, and then validate that those workloads can be recovered from operational failure and from a cyber attack. The lab is organized around the workloads themselves — you take the VM workload from unprotected to recoverable, then do the same for the Blob workload, and finally harden and test both.

Contoso, a financial services firm, runs a claims processing application on Azure. The application tier runs on Azure Virtual Machines, and scanned claim documents, logs, and media are stored in Azure Blob Storage. Contoso needs both layers protected, retained to meet compliance requirements, and shielded so that ransomware or accidental operations cannot delete or tamper with recovery points.

### Workload journey

| Exercise | Workload in focus | What you achieve |
| --- | --- | --- |
| 1 | VM workload — claims application tier | The VM goes from unprotected to protected, backed up, and verified recoverable |
| 2 | Blob workload — claim documents and logs | The storage account goes from unprotected to protected and verified |
| 3 | Both workloads | Recovery data is hardened against deletion and tampering, and restore paths are confirmed |
| 4 | Both workloads | Recovery points are assessed for compromise and threats are mapped to controls |

## Before you start

- Review the Azure Backup architecture for built-in Azure VM backup, and the Azure VM backup extension model.
- Review the Azure VM backup support matrix before you configure backup.
- Ensure the `Microsoft.RecoveryServices` resource provider is registered in the subscription. Without it, zone-redundant and vault property options such as immutability settings are not accessible.
- Ensure the `Microsoft.DataProtection` provider is registered for the subscription used for blob backup.
- Confirm the VM agent is present on the VM. VMs created from an Azure Marketplace image already have the agent installed and running. Custom or migrated VMs may need manual installation.
- Confirm you have Contributor access on the lab resource group and permission to create vaults, policies, and role assignments.

---

## Exercise 1: Protect the claims application VM workload

> **Goal:** Take the claims application VM from unprotected to protected, and prove it is recoverable within Contoso's retention requirements.

The claims application tier runs on Azure Virtual Machines and is the workload Contoso cannot afford to lose. In this exercise you follow the VM through its full protection journey: assess what it needs, stand up the protection container it will use, define how often and how long it is retained, enable protection, and confirm a usable recovery point exists.

### VM workload profile

| Attribute | Value for this lab |
| --- | --- |
| Workload | Claims application tier on Azure Virtual Machines |
| Protection service | Azure Backup for Azure VMs |
| Protection container | Recovery Services vault |
| Recovery expectation | Daily recovery point, restorable within the agreed recovery window |

### Task 1: Assess the VM workload's protection requirements

1. Identify the claims application VM, its resource group, and its region. The protection container must be created in the same region as the VM.
2. Confirm the VM appears in a running or stopped state that is supported for backup, and that the VM agent is present.
3. Record how frequently the VM must be backed up, which determines the recovery point objective.
4. Record how long daily, monthly, and yearly recovery points must be retained to satisfy Contoso's compliance requirement.
5. Record whether Contoso needs fast local restores, which determines how long snapshots are retained for Instant Restore.

> [!TIP]
> Capture these values now. You reuse them in Task 3 when you define the protection schedule and retention, and again in Exercise 3 when you harden the workload.

### Task 2: Stand up the protection container for the VM workload

1. Sign in to the Azure portal.
2. Search for **Resiliency**, and then go to the **Resiliency** dashboard.
3. On the **Vault** pane, select **+ Vault**.
4. Select **Recovery Services vault**, and then select **Continue**.
5. Select the lab **Subscription**, and select an existing **Resource group** or create a new one.
6. Enter a vault name that is unique to the subscription, using 2 to 50 characters, starting with a letter, and containing only letters, numbers, and hyphens.
7. Select the same **Region** as the claims application VM.
8. Select **Review + create**, and then select **Create**.
9. Once deployment completes, open the vault, and under **Settings** select **Properties**.
10. Under **Backup Configuration**, select **Update**, choose the storage replication type for the VM workload, and select **Save**.

> [!IMPORTANT]
> Set the storage replication type before you protect the VM. It cannot be changed once the vault contains backup items, and changing it later means re-creating the vault and re-protecting the workload.

### Task 3: Define how the VM workload is backed up and retained

1. Review the default protection behaviour first: one backup per day, daily recovery points retained for 30 days, and instant recovery snapshots retained for two days.
2. If the default does not meet the requirements you captured in Task 1, choose **Create New** during the configure backup flow to define a custom schedule.
3. Enter a policy name that identifies the workload it protects.
4. Set the backup schedule for the VM. Azure VMs support daily or weekly backups.
5. Set **Instant restore** retention to match Contoso's expectation for fast local restores. The valid range is one to five days and the default is two days.
6. Set the retention range for daily or weekly recovery points.
7. Set monthly and yearly retention if long-term retention is required for the claims workload.
8. Save the configuration for use in the next task.

> [!NOTE]
> Azure Backup does not adjust automatically for daylight-saving time changes on Azure VM backups. If the claims workload requires more frequent recovery points than once a day, use the Enhanced backup policy.

### Task 4: Enable protection on the VM workload

1. Go to **Resiliency**, and then select **+ Configure protection**.
2. Set **Resources managed by** to **Azure**.
3. Set **Datasource type** to **Azure Virtual machines**.
4. Set **Solution** to **Azure Backup**, and select **Continue**.
5. On the **Start: Configure Backup** pane, select **Azure Virtual machines**, select the vault you created in Task 2, and select **Continue**.
6. Assign the schedule and retention configuration from Task 3.
7. Under **Virtual Machines**, select **Add**.
8. Select the claims application VM, and then select **OK**.
9. Select **Enable backup**.

> [!NOTE]
> Only VMs in the same region as the vault can be selected, and a VM is backed up by a single vault. A VM in a soft-deleted state does not appear in the selection list.

### Task 5: Prove the VM workload is recoverable

1. Go to **Resiliency**, then **Protected items**.
2. Set **Datasource type** to **Azure Virtual machines** and locate the claims application VM.
3. Right-click the row or select **More**, and then select **Backup Now**.
4. Use the calendar control to select the last day the recovery point should be retained, and select **OK**.
5. Go to **Resiliency**, then **Jobs**, and filter for jobs in progress.
6. Follow the job through its three phases: **Snapshot**, **Transfer data to vault**, and **Validate backup**.
7. Confirm the VM now lists at least one recovery point.

> [!IMPORTANT]
> Completion of **Transfer data to vault** does not by itself confirm a restorable recovery point. The VM workload is only proven recoverable once **Validate backup** succeeds.

**By the end of this exercise:**

- The claims application VM is a protected item in Azure Backup.
- Its schedule and retention match the requirements captured for the workload.
- A validated recovery point exists, so the VM workload is demonstrably recoverable.

---

## Exercise 2: Protect the claim documents Blob workload

> **Goal:** Take the storage account holding scanned claim documents and logs from unprotected to protected, and confirm the protection model matches Contoso's recovery needs.

Contoso's scanned claim documents, logs, and media live in Azure Blob Storage. This workload has a different protection model from the VM tier: it uses a different vault type, requires an explicit permission grant on the storage account, and offers two protection models with different recovery characteristics. In this exercise you take the blob workload through its own end-to-end journey.

### Blob workload profile

| Attribute | Value for this lab |
| --- | --- |
| Workload | Scanned claim documents, logs, and media in Azure Blob Storage |
| Protection service | Azure Backup for Azure Blobs (Azure Storage) |
| Protection container | Backup vault |
| Protection models | Operational backup, vaulted backup, or both |

### Task 1: Choose the protection model for the blob workload

|  | Operational backup | Vaulted backup |
| --- | --- | --- |
| Where data is held | Source storage account (local) | Backup vault (offsite) |
| Maximum retention | 360 days | 10 years |
| Restore target | Source storage account only | Different storage account only |
| Schedule | Continuous, no schedule | Daily or weekly |
| Best suited to | Fast recovery from accidental change | Long retention and ransomware resilience |

1. Decide whether the claim documents need fast local recovery, long offsite retention, or both.
2. Record the retention duration the workload requires for each model you select.
3. Note that operational backup restores only to the source storage account, and vaulted backup restores only to a different storage account.
4. If you choose vaulted backup, identify now which target storage account would receive a restore.

> [!IMPORTANT]
> Deleting an entire container cannot be undone by operational backup. Delete individual blobs rather than whole containers, and enable container soft delete alongside operational backup.

### Task 2: Stand up the protection container for the blob workload

1. Type **Backup vaults** in the portal search box.
2. Under **Services**, select **Backup vaults**.
3. On the **Backup vaults** page, select **Add**.
4. Under **Project details**, confirm the subscription and choose an existing resource group or create a new one.
5. Under **Instance details**, enter the vault name and choose the region for the blob workload.
6. Choose the **Storage redundancy**. Use **Geo-redundant** when Azure is the primary backup storage endpoint, or **Locally redundant** to reduce storage cost.
7. Select **Review + create** and complete the deployment.

> [!NOTE]
> Storage redundancy cannot be changed after items are protected in the vault. The Backup vault is a different resource type from the Recovery Services vault used for the VM workload.

### Task 3: Grant the protection service access to the storage account

1. Go to the storage account holding the claim documents.
2. Open the **Access Control (IAM)** tab on the left navigation blade.
3. Select **Add role assignments**.
4. Under **Role**, choose **Storage Account Backup Contributor**.
5. Under **Assign access to**, choose **User, group or service principal**.
6. Search for the Backup vault created in Task 2 and select it from the results.
7. Select **Save**, and wait for the assignment to take effect before configuring protection.

> [!NOTE]
> The role assignment can take up to 30 minutes to take effect. You can also assign the role at the resource group or subscription level if multiple storage accounts must be protected.

> [!TIP]
> Operational backup applies a Backup-owned Delete Lock that protects the storage account itself from accidental deletion, which is why this permission is required.

### Task 4: Define how the blob workload is retained

1. Go to **Resiliency**, then **Protection policies**, and select **+ Create Policy**, then **Create Backup Policy**.
2. Select the **Datasource type** as **Azure Blobs (Azure Storage)**, and select **Continue**.
3. Enter a policy name, choose the Backup vault created in Task 2, review the vault details, and select **Next**.
4. On the **Schedule + retention** tab, select the checkboxes matching the protection model you chose in Task 1.
5. For vaulted backups, choose daily or weekly frequency, specify the schedule, and edit the default retention rule or add rules using grandparent-parent-child notation.
6. For operational backups, leave the schedule alone because they are continuous, and edit the default rule to set retention.
7. Select **Review + create**, and once the review succeeds, select **Create**.

### Task 5: Enable protection on the blob workload

1. Go to **Resiliency**, then **Overview**, and select **+ Configure protection**.
2. Under **Resources managed by**, select **Datasource type** as **Azure Blobs (Azure Storage)**, and select the solution as **Azure Backup**.
3. On the **Basics** tab, choose **Azure Blobs (Azure Storage)** and select the Backup vault, then select **Next**.
4. On the **Backup policy** tab, select the policy created in Task 4, review the details, and select **Next**.
5. On the **Datasources** tab, select the storage account holding the claim documents.
6. If you chose vaulted backup, select **Change** under **Selected containers**, then choose **Backup all present containers**, **Browse containers to backup**, or **Backup all present and future containers**.
7. Check the **Backup readiness** column to confirm the vault has sufficient permissions on the storage account.
8. If roles are still missing and you have permission, select the roles and select **Assign missing roles**, then wait for revalidation.
9. Once validation succeeds, open **Review + configure** and select **Next** to start protection.

> [!IMPORTANT]
> **Backup all present and future containers** is a permanent choice and cannot be reversed. For vaulted backup the storage account must hold at least one container, and no more than 1000 containers can be protected.

> [!TIP]
> You can also enable operational backup for this workload directly from the storage account, under **Data management**, then **Data Protection**.

### Task 6: Confirm the blob workload is protected

1. Follow the portal notifications until the configure protection operation completes.
2. Confirm the storage account appears as a protected backup instance.
3. Record which containers are covered by protection.
4. Record the active protection model and retention applied to the workload.
5. Note any storage account that failed validation and the corrective action required.

**By the end of this exercise:**

- The claim documents storage account is protected by Azure Backup.
- The protection model chosen matches Contoso's recovery and retention needs.
- The learner can explain why the blob workload uses a different vault type and permission model from the VM workload.

---

## Exercise 3: Harden both workloads against data destruction

> **Goal:** Protect the recovery data for both workloads so that a malicious or accidental operation cannot destroy Contoso's ability to recover.

Both workloads are now protected, but protection alone does not stop an attacker with valid credentials from deleting recovery points or shortening retention. In this exercise you harden the recovery data for each workload and confirm which restore paths remain available in a disaster.

### Task 1: Harden the VM workload's recovery data

1. Open the Recovery Services vault protecting the claims application VM.
2. Locate the immutability setting under the vault security or properties settings.
3. Review the three available states: **Disabled**, **Enabled**, and **Enabled and locked**.
4. Set the vault to **Enabled** so operations that would destroy VM recovery points are blocked.
5. Keep the vault unlocked for this lab unless the instructor confirms the environment is disposable.
6. Record the state you applied, because you reference it during threat analysis in Exercise 4.

#### What hardening blocks for each workload

| Workload | Operation blocked once hardened | What remains possible |
| --- | --- | --- |
| VM workload | Stopping protection and deleting its recovery points | Stopping protection while retaining data until expiry |
| VM workload | Editing the schedule so retention is reduced | Increasing retention and changing the backup schedule |
| VM workload | Swapping in a configuration with lower retention | Swapping in a configuration with higher retention |
| Blob workload | Deleting recovery points before their expiry dates | Stopping protection while retaining data |

> [!NOTE]
> Hardening applies to every item protected in that vault. It does not apply to operational backup of blobs, so the blob workload is only fully covered when vaulted backup is in use.

### Task 2: Decide whether to make hardening irreversible

1. Confirm that the **Enabled** state is reversible and can be turned off if recovery data must be deleted.
2. Confirm that **Enabled and locked** applies WORM storage, cannot be turned off, and is permanent.
3. Assess whether the lab environment is disposable enough to demonstrate the locked state.
4. Record the final state for each workload and the justification you would give Contoso.

> [!IMPORTANT]
> Lock a vault only after the operational impact is understood, because the decision cannot be reversed.

### Task 3: Confirm the restore path for each workload

| Scenario | VM workload restore path | Blob workload restore path |
| --- | --- | --- |
| Accidental change or deletion | Restore from a recovery point in the vault | Operational backup restore to the source storage account |
| Regional disruption | Cross Region Restore into the secondary region | Vaulted backup restore to a storage account in another location |
| Recovery into another subscription | Cross Subscription Restore | Restore to a storage account in the target subscription |

1. Confirm the storage replication type set in Exercise 1 supports the VM restore path Contoso expects.
2. Confirm a target storage account is identified for the blob workload, since vaulted backup restores only to a different account.
3. Record which restore path Contoso would use for a regional disruption, and which applies to accidental data loss.

**By the end of this exercise:**

- Recovery data for the VM workload is hardened against deletion and retention tampering.
- The limits of hardening for the blob workload are understood and documented.
- A restore path is identified for each workload for both accidental loss and regional disruption.

---

## Exercise 4: Assess the workloads for cyber threats

> **Goal:** Determine whether Contoso's recovery points are trustworthy, and map the threats each workload faces to the controls now in place.

Recovering from ransomware only helps if the recovery point itself is clean. Azure Backup integrates with Microsoft Defender for Cloud to evaluate the health of Azure VM recovery points using signals such as disruption patterns, behavioural anomalies, and ransomware signatures. In this exercise you turn that assessment on for the VM workload and then evaluate both workloads against realistic attack scenarios.

### Task 1: Turn on threat assessment for the VM workload

1. Confirm the lab subscription has Defender for Servers Plan 1 or Plan 2 enabled, because the assessment depends on those signals.
2. Navigate to the Recovery Services vault protecting the claims application VM.
3. Under **Settings**, go to **Properties**.
4. Open the security settings section and locate the **Threat Detection** setting.
5. Enable threat detection and update the vault.
6. Confirm that enabling it at the vault level covers every VM protected in that vault.

> [!NOTE]
> Threat assessment for Azure VM backups is available in preview in all Azure public regions except UAE Central, Israel Central, Qatar Central, and Israel North West.

### Task 2: Confirm the assessment is configured for the workload

| Status | What it means for the workload |
| --- | --- |
| Configured | The VM workload's recovery points are being assessed |
| Not Configured | Assessment is not yet switched on for items in this vault |
| Configuration Failed | Assessment could not be set up because of configuration errors |
| Not Applicable | Defender for Servers coverage was downgraded after setup |

1. Open the vault and review the configuration status shown for the claims application VM.
2. Record the status, and resolve it if it shows anything other than **Configured**.

### Task 3: Judge whether the VM workload's recovery points are clean

| Result | Recovery decision it drives |
| --- | --- |
| No Threats Reported | Recent recovery points are clean and can be used with confidence |
| Suspicious RPs found | At least one recent recovery point may be compromised; select an alternative |
| Not Applicable | Defender for Servers coverage was downgraded for this VM |
| Unknown (-) | Assessment is not configured or has failed, so cleanliness is unproven |

1. Take an on-demand backup so a new recovery point is created and assessed.
2. Go to **Backup items** in the Recovery Services vault and select **Azure Virtual Machine**.
3. Select the protected item for the claims application VM and select **View details**.
4. Open the **Recovery points** section and review the health reported for each recovery point.
5. Record the result and state which recovery point you would restore from during an incident.

> [!NOTE]
> If the VM has active ransomware alerts when assessment is switched on, the summary can take up to 48 hours to change to **Suspicious**.

### Task 4: Map each workload's threats to the controls in place

| Threat to the workload | Affected workload | Control configured in this lab |
| --- | --- | --- |
| Compromised operator deletes recovery data | VM and Blob | Vault hardening blocks operations that destroy recovery points |
| Attacker shortens retention so recovery points expire | VM | Hardening disallows any change that reduces retention |
| Attacker deletes the storage account outright | Blob | Backup-owned Delete Lock applied by operational backup |
| Ransomware encrypts data before the backup runs | VM | Threat assessment flags suspicious recovery points and surfaces clean ones |
| Protection silently stops working | VM and Blob | Job phases and job monitoring in the Resiliency dashboard |

1. Confirm which of the controls above are active for each workload in your lab.
2. Record any control recommended for production but unavailable in the lab tenant.
3. Record the residual risk that remains for each workload after this lab.
4. Write one recommendation for Contoso that closes the most significant residual risk.

**By the end of this exercise:**

- Threat assessment is enabled and its results are understood for the VM workload.
- The cleanliness of the VM workload's recovery points has been judged.
- Threats are mapped per workload to the controls configured across this lab.

---

## Appendix

### Architecture

The lab protects two workloads from Contoso's claims processing application. The application tier on Azure Virtual Machines is protected by Azure Backup through a Recovery Services vault. The scanned claim documents in Azure Blob Storage are protected through a Backup vault, using operational backup, vaulted backup, or both. Recovery data for both workloads is hardened through vault immutability, and the VM workload's recovery points are assessed for compromise using Azure Backup threat detection with Microsoft Defender for Cloud.

<!-- TODO: Add the architecture diagram for the claims application -->

### Resources in the application

| Resource | Workload it serves | Example name |
| --- | --- | --- |
| Azure Virtual Machine | Claims application tier | `ContosoClaimsApp-VM1` |
| Storage account with blob container | Scanned documents, logs, and media | `ContosoClaimsApp-SA1` |
| Recovery Services vault | VM workload protection container | `rsv-lab3-<alias>-<region>` |
| Backup vault | Blob workload protection container | `bv-lab3-<alias>-<region>` |
| Defender for Servers plan | Threat assessment for the VM workload | Plan 1 or Plan 2 |

### Naming conventions

- VM workload protection container: `rsv-lab3-<alias>-<region>`
- Blob workload protection container: `bv-lab3-<alias>-<region>`
- VM workload protection configuration: `bp-vm-claims-daily-<retention>`
- Blob workload protection configuration: `bp-blob-claims-<model>-<retention>`

### Authoring placeholders

- `<Add the architecture diagram for the claims application>`
- `<Add screenshots for the VM workload journey: vault, schedule and retention, enable protection, recovery point>`
- `<Add screenshots for the blob workload journey: vault, IAM role, retention, configure protection>`
- `<Add screenshots for vault hardening on both workloads>`
- `<Add screenshots for threat assessment configuration and recovery point health>`
- `<Confirm final tenant-specific portal labels after Skillable validation>`

### Instructor notes and open decisions

| Decision | Owner | Status |
| --- | --- | --- |
| Confirm the customer/application name: Caldova or Zava | Design team | Open |
| Pre-created VM and storage account, or learner-deployed | Instructor | Open |
| Vault hardening remains Enabled, or is locked in the lab | Instructor | Open |
| Defender for Servers enabled in the lab subscription | Lab environment | Open |
| Target regions confirmed, vault region matches each workload | Lab environment | Open |
| Blob workload uses operational, vaulted, or both models | Design team | Open |
