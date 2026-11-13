# Tutorial: Define and Execute a Regional Resiliency Drill to Assess Service Group Resiliency

## Introduction

Azure Infrastructure Resiliency manager enables you to assess the resiliency of Service Group resources by simulating [zonal outages](https://learn.microsoft.com/en-us/azure/resiliency/availability-zone-down-drills-about) on individual resources.

For Regional resiliency drills, you can bring your own custom script to bring down your application on the Primary region or simulate region-down faults using your own scripts. Support for native region-down faults is planned for future releases.

Integration with [Azure Health Models](https://learn.microsoft.com/en-us/azure/azure-monitor/health-models/overview) and [Service Level Indicator (SLI)](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/service-level-indicators-create) metrics in Azure Monitor helps you monitor the health of your application and its resources over the course of Drill operations in real-time.

## Pre-requisites

1. Ensure that all the pre-requisites in [this article](../Prerequisites.md) are met.

2. In addition, you will need to have a recovery plan setup for your service group. Refer to the [recovery plan tutorial](../Recovery%20plan/CreateAndExecuteRecoveryPlan.md) for instructions to create a recovery plan.

3. Ensure that the **Chaos Studio Resource Provider** is registered in the subscription where the Chaos Experiment will be created. If it is not already registered, follow these steps:
   - Navigate to the **Subscription** view in the Azure portal.
   - Search for **Microsoft.Chaos** in the Resource Providers section.
   - Select and register the provider.
   - Allow 15–20 minutes for the registration to complete before proceeding with drill creation.

![Chaos Registration Step](../img/42-Chaos-Reg.png)

4. Similarly, ensure that either Azure Health Model or an SLI is setup and associated with the Drill.

## Drill Setup

To define a regional resiliency drill, follow the steps below:

1. Visit the Service Group for which you want to define a Drill and navigate to Resiliency > Drills.

    ![Screenshot of SG Drill Page on Day 0](../img/26-Drill-SG-Empty.png)

2. Click on **Create drill** and input a suitable name for the Drill instance. Post this, select the Subscription and Region that needs to be associated with the Chaos Experiment and Log Analytics Workspace that will be created to perform fault injection and monitoring measurement respectively over the course of the drill. This Subscription and Region need not be related to the Subscriptions and Regions associated with Service Group members.

    ![Screenshot of SG Create Drill Flow](../img/Drill-create-basics.png)

3. Then choose between System-assigned and User-assigned identity that will be used to fetch resources of the Service Group and the associated Azure Health Model details securely. The same identity can be used for fault injection by default or alternately, a different identity can be selected. The role assignment type will use Azure built-in roles by default.
    
    ![Screenshot of Drill MSI selection](../img/Drill-create-permissions.png)

4. Ensure that users responsible for drill creation and execution have the required permissions. These permissions are listed below for quick reference:
    - Minimum role required at Service Group level for successful drill execution: 
        - **Azure Resilience Management Drill Contributor**, to Create/Update/Execute Drills (tenant-level resources).  
        - **Azure Resilience Management Recovery Plan Contributor**, to Create/Execute Recovery Plan
    - Minimum role required at Subscription level (the subscription associated with Automation Account and Chaos experiment) for successful drill execution: **Azure Resilience Management Drill Assets Contributor**, to manage the Subscription associated with Automation Account and Chaos experiment.
    - Minimum roles required in individual resources to perform fault injection: **Azure Resilience Management Drills Target Resource Contributor**, to manage the target resources.
        - **User Access Administrator** → for assigning roles on each of the drill resources’ subscriptions.
            - For role assignments (instead of User Access Administrator required on each subscription of drill resource):
                - Microsoft.Authorization/roleAssignments/read — Check if role already exists
                - Microsoft.Authorization/roleAssignments/write — Create role assignment

5.Select a Azure Health Model or an SLI and associate with the drill for monitoring the health of the resources and application.

![Screenshot of Drill details](../img/Drill-create-monitoring.png)

6. Upon confirmation, the Drill instance gets created. Note that every Service Group can be associated with a single Regional Drill instance.

7. Upon creation, review the summary widgets on the Overview page that explain the Drill parameters that need fixing in order to proceed with execution of the Drill.

![Screenshot of Drill details](../img/Drills-overview.png)

Similarly, double-click details and edits on **Identity and Permissions** can be done using the dedicated blade on the left navigation.

7. Next, proceed to review the resources that are included in the Drill. Key points on the resources included in a drill: 
    
    ![Screenshot of Drill resource exclude page](../img/Drill-Resiliency-solutions.png)
    
    4. Any resource that is excluded by default from the drill can be included back by clicking on “View details and include resources” as shown below. Ensure that you click on “Refresh” upon including resources back to the drill to see the updated list:

    ![Screenshot of Drill Resource Review](../img/30-Drill-Resources.png)

8. Upon confirming the list of resources to be included in the drill, proceed to the Fault Designer tab to add custom faults that need to be applied to the resources. Select any resource and click on "Edit Fault" for the same. 

    ![Screenshot of Drill Fault Designer](../img/Drill-fault-designer.png)      
    
    > [!TIP]
        > Use custom scripts powered by Azure Runbooks to define fault logic.

Note that faults can be applied in bulk for a given resource type by selecting the resource type and clicking on "Edit fault".

Note that all resources are in "Needs Attention" state by default. Once the fault logic has been defined, select each of these resources and click on "Include and prepare for fault injection". This step proceeds to complete role assignment and target onboarding, which are mandatory steps to perform fault injection. Leverage the hyperlink on "Needs attention" to debug the reason for lack of resource readiness for fault injection.

![Screenshot of resource exclusion](../img/33-Drill-Include-Exclue.png.jpg)

Alternately, resources can be excluded from fault injection by selecting the resource and clicking on "Exclude from fault injection".

Any resource that undergoes changes in the Fault Designer will be in "Under edit" state till the changes are not saved.

Leverage the "Fault duration" input to inject faults for a set duration. The default value is 10 minutes.

9. Once fault design is complete for all resources, review readiness across all summary widgets. "Resync and check readiness" on Overview screen can be leveraged to fix any config drifts and to attempt changing "Drill execution readiness" from Not Ready to Ready.

    > [!NOTE]
    > Refresh the drill instance after every edit operation.

![Screenshot of Drill MSI selection](../img/Drill-check-readiness.png)

## Drill Execution

1. Once the “Drill execution readiness” is “Ready”, click on “Execute Drill” on the Overview page.

2. Select the Drill execution type. Once fault injection is completed, the Recovery Plan associated with the Service Group gets executed. Ideally, every Service Group should undergo the entire cycle of Fault Injection > Failover > Reprotect > Failover (in reverse direction) > Reprotect (in reverse direction). Depending on which stage your last drill was stopped, you can choose between Failover and Reprotection. 

3. Upon selecting the right operation, review the subset of resources that will undergo the same. For example, if Failover is selected, select the source zone from which the failover should be triggered. This will filter the resources that belong to the selected zone.

4. Finally, review the final set of resources that will undergo fault injection and confirm execution. 

5. Drill execution progress can be tracked through a job as shown below.

![Screenshot of Drill Run Job](../img/35-Drill-Run-Job.png)
  
Every drill execution job follows the sequence of Fault Injection > Failover > Reprotect > Failover (in reverse direction) > Reprotect (in reverse direction). For a given step, "Retry" operation can be leveraged to re-execute any given operation for a failed resource. "Start" begins the step and "Mark step as complete" ends the step. Once a step, for example, Reprotect is ended, it cannot be retried. 

> [!NOTE]
> For Failover (Reverse) to select the right resources for failover back from target to source zone, edit the source recovery plan’s resources before failover.

6. Every drill execution also supports addition of notes during the execution which will get stored as a part of run history of the drill. 

> [!NOTE]
> Upon adding notes and saving the notes, refresh the job to update the notes. 

7. Additionally, every execution run should be explicitly ended using “End execution”, which is followed by review of the notes and an attestation of the final status of the Drill as shown below.

![Screenshot of Drill Execution End](../img/36-Drill-End-Execution.png)

8. You can download the drill report using the **Download report** action on the Drill run details page.
