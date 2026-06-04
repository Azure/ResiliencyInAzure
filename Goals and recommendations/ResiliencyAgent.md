# Resiliency Agent — Private Preview Documentation

---

## Prerequisites

The Resiliency Agent is currently available as a private preview. To get started, you will need to complete the following steps:

1. **Request access:** Request access to the preview by reaching out to [azureresiliency@microsoft.com](mailto:azureresiliency@microsoft.com). Please include your tenant ID and a brief description of your use case.
2. **Tenant enrollment:** Your tenant must be enrolled in the private preview. The team will configure your tenant for access after reviewing your request.
3. **Access the preview:** Once you receive confirmation that your tenant has been enrolled, use the following preview URL to access the Resiliency Agent capabilities:

**[https://aka.ms/resiliencyAgent/Preview](https://aka.ms/resiliencyAgent/Preview)**

> **Note:** The Resiliency Agent is integrated into the Azure Copilot experience within the Azure Portal. You will need a supported browser (Microsoft Edge or Google Chrome recommended).

---

## Overview

The Resiliency Agent is an AI-powered assistant integrated into Azure Copilot that helps you design, assess, and improve the resiliency of your Azure workloads through natural language. Instead of navigating multiple tools and interpreting raw signals, you can interact with the agent conversationally to understand your resiliency posture, get actionable recommendations, and execute remediation — all from within the Azure Portal.

The agent supports two primary capability areas:

### Start Resilient — Design with resiliency from day one

Start Resilient helps you build resiliency into your applications before they are deployed. Describe your application architecture in natural language, and the agent will:

- Analyze your application topology and identify resiliency best practices relevant to your resources.
- Generate a detailed resiliency report with recommendations tailored to your architecture.
- Produce deployment-ready Bicep templates with the recommended resiliency configurations already enabled.

This capability is designed for teams that are building new applications or modernizing existing ones and want to ensure resiliency is a deployment default — not a remediation afterthought.

### Get Resilient — Assess and improve your existing workloads

Get Resilient helps you understand and improve the resiliency posture of workloads that are already running in Azure. The agent can:

- Check whether individual resources or entire application groups (Service Groups) are zonally resilient.
- Identify prerequisites and blockers for enabling resiliency on your resources.
- Provide guided remediation — including direct conversions where supported, or step-by-step migration guidance for more complex scenarios.
- Generate enablement scripts in your preferred format (PowerShell, Azure CLI, Bicep, Terraform, or ARM templates).
- Help you organize resources into Service Groups, set resiliency goals, and track compliance over time.
- Surface indicative cost impact so you can make informed decisions about remediation.

This capability is designed for teams managing existing workloads who want to systematically close resiliency gaps and maintain compliance with their organization's resiliency objectives.

---

## How to Access the Resiliency Agent

There are two ways to launch the Resiliency Agent:

### Option 1: Via Azure Copilot

1. Open the Azure Portal using the preview URL provided to you after enrollment.
2. Navigate to the Resiliency overview page (this should load automatically from the preview URL).
3. Click the **Copilot icon** in the top-right corner of the Azure Portal header bar. This opens the Copilot side panel.
4. In the Copilot panel, locate the **agent selector dropdown** near the top of the panel.
5. Click the dropdown and select **"Resiliency"** from the list of available agents (other options include Copilot, Troubleshooting, Deployment, and Optimization).
6. The panel header will update to show **"Resiliency agent"** and you will see suggested starter prompts to begin your interaction.

### Option 2: Via Top Actions on the Resiliency Screen

When you are on the Resiliency overview page, you will see top action buttons that provide quick entry points into common resiliency workflows. Clicking any of these actions will automatically open the Copilot panel with the Resiliency Agent selected and pre-populated with a relevant prompt.

> **Tip:** Once the agent is loaded, you can interact with it using the suggested prompts or by typing your own questions in natural language. The agent maintains context across multiple turns, so you can have a continuous conversation that progresses from assessment to remediation.

---

## Start Resilient — Scenarios and Sample Prompts

The Start Resilient capability helps you design resilient architectures from scratch. Below are the key scenarios you can explore, along with sample prompts to get started.

### Describe your application and get a resiliency plan

Tell the agent about your application's resources in natural language. The agent will analyze your topology, ask clarifying questions if needed (e.g., region, configuration preferences), and generate a resiliency summary with a detailed recommendation report.

**Sample prompts:**

> *"My app has a VM, a PostgreSQL database, and a load balancer. Help me start my resilient journey."*

> *"I'm building an application with AKS, Redis, Storage, and Cosmos DB. What should I do to make it resilient?"*

> *"I have a web app with an App Service, SQL Database, and a Front Door. Can you assess the resiliency?"*

### Generate resilient Bicep templates

Ask the agent to generate deployment-ready Bicep templates for your resources with the recommended resiliency configurations already enabled. The agent produces modular templates including `main.bicep`, `parameters.json`, and per-resource files.

**Sample prompts:**

> *"Generate a Bicep template for a zonally resilient VM setup."*

> *"Create Bicep templates for a resilient architecture with VMs, AKS, and Storage."*

> *"Generate deployment templates for my application with resiliency best practices included."*

### Larger application architectures

The agent can handle more complex application descriptions with multiple resource types. It will produce a consolidated resiliency summary and detailed recommendations across all resources.

**Sample prompts:**

> *"My app includes VMs, AKS, Redis, Storage, and Cosmos DB. Help me design a resilient setup."*

> *"Generate Bicep templates for a zonally resilient architecture with VMs, AKS, and Storage."*

---

## Get Resilient — Scenarios and Sample Prompts

The Get Resilient capability helps you assess and improve the resiliency of your existing Azure workloads. Below are the key scenarios you can explore.

### Check resource resiliency

Ask the agent to check whether a specific resource or your entire Service Group is zonally resilient. The agent will return the current resiliency status along with supporting configuration details.

**Sample prompts:**

> *"Is my VM zonally resilient?"*

> *"Check the resiliency of my storage account."*

> *"Get the zonal resiliency posture of my service group."*

### Check prerequisites for resiliency

Before enabling resiliency, you may need to address certain prerequisites. The agent can identify blocking conditions such as region limitations, permission requirements, or configuration dependencies.

**Sample prompts:**

> *"What are the prerequisites to make my VM zonally resilient?"*

> *"What do I need to do before enabling zone redundancy on my database?"*

### Enable resiliency on your resources

For resources that support in-place conversion (mutable resources), the agent can directly enable zonal resiliency. For resources that require redeployment (such as VMs), the agent will provide step-by-step guidance and scripts.

**Sample prompts:**

> *"Enable zonal resiliency for my PostgreSQL server."*

> *"Enable zonal resiliency for my VM."*

> *"How do I make my storage account zone-redundant?"*

> **Important:** For some resource types, the agent will execute the change directly. For others (like VMs), it will provide guidance and scripts rather than making changes, since these resources require redeployment.

### Generate enablement scripts

The agent can generate scripts to enable or create zonally resilient resources in multiple formats including PowerShell, Azure CLI, Bicep, Terraform, and ARM templates.

**Sample prompts:**

> *"Give me scripts to enable zonal resiliency for my resources."*

> *"Generate scripts to create a zonally resilient storage account."*

> *"Generate scripts for all resources in my service group."*

### Organize resources into Service Groups

Service Groups let you logically group the Azure resources that make up an application. The agent can help you create Service Groups, add resources to them, and view their membership.

**Sample prompts:**

> *"Create a service group for my application."*

> *"Add my VM and database to the service group."*

> *"Show the resources in my service group."*

### Set resiliency goals and track compliance

Once you have a Service Group, you can set resiliency goals and track how your resources comply over time. The agent supports creating goals, checking compliance status, excluding specific resources, and refreshing compliance after changes.

**Sample prompts:**

> *"Set a zonal resiliency goal for my service group."*

> *"What is my goal compliance status?"*

> *"Exclude this VM from my resiliency goal."*

> *"Refresh my goal compliance after recent changes."*

### End-to-end guided workflow

The agent supports multi-turn conversations that progress naturally from assessment to remediation. You can start by checking your posture, then ask for scripts to fix issues, and continue through the full resiliency lifecycle in a single conversation.

**Example conversation flow:**

1. Start with: *"Create a service group for my app"*
2. Then: *"Set resiliency goals"*
3. Then: *"Check posture"*
4. Then: *"Fix the issues"* or *"Give me scripts to fix it"*

> **Tip:** The agent maintains context across turns, so each step builds on the previous one. You don't need to repeat resource names or configuration details.

---

## Known Limitations

As this is a private preview, please be aware of the following:

- The agent is optimized for zonal resiliency scenarios. Regional resiliency and other resiliency dimensions will be added in future releases.
- Template generation currently supports Bicep format. Support for additional IaC formats in the Start Resilient flow is planned.
- Some operations may take a few moments to complete, especially for larger Service Groups.
- If the agent encounters an error or unexpected behavior, please share feedback with the team at [azureresiliency@microsoft.com](mailto:azureresiliency@microsoft.com).

---

## Providing Feedback

Your feedback is critical to shaping this experience. We encourage you to try the scenarios above and share your observations:

- What worked well and what didn't?
- Were the recommendations and scripts accurate and actionable?
- Were there scenarios you expected to work but didn't?
- Any suggestions for additional capabilities?

Please send feedback to [azureresiliency@microsoft.com](mailto:azureresiliency@microsoft.com) with the subject line **"Resiliency Agent Preview Feedback"**.
