# Pre-requisites to use Regional Resiliency Preview in Azure Infrastructure Resiliency Manager 

1. Ensure you have **signed up** for the preview using [this form](https://forms.cloud.microsoft/r/9jpNsT75PY). You will receive an email notification from the product group once you are enrolled, along with instructions on how to access the preview.

2. Ensure that you have **test resources** in your Azure environment that fall under one or more of the [supported resource types](./Goals%20and%20recommendations/ViewResiliencePosture.md#Supported-Solutions).

3. Ensure that you have registered **Microsoft.AzureResilienceManagement** resource provider on your tenant. You can run the following commands in PowerShell to register the resource provider on your tenant.

    ```powershell
    Connect-AzAccount #Login once prompted. If prompted for a subscription id, you can use any subscription within your tenant
    Invoke-AzRestMethod -Path /providers/Microsoft.AzureResilienceManagement/register?api-version=2021-04-01 -Method POST #Check for successful registration (status code 200)
    ```

> [!IMPORTANT]
> Wait 15-20 minutes after registering the resource provider before trying any of the tutorials in this documentation.

4. There are certain **RBAC** (role based access control) requirements for each scenario. These have been detailed in the [access requirements](rbac.md) section. Depending on the scenario you wish to try out, the access requirements vary. You can either choose to setup all the required permissions before trying out the product, or set them up in phases as and when you try out a particular capability. Each tutorial article provides a list of permissions needed for using that specific capability.

5. Once the test resources have been identified, ensure that these have been organized into a **service group** that represents your test application. The link below guides you through the steps to create a service group.

6. To create Recovery Plans and conduct Drills using Resiliency Manager, you must setup a [Usage Plan](https://github.com/Azure/ResiliencyInAzure/blob/main/Create%20Usage%20Plan%20for%20Service%20Group) for the Service Group. During the preview, there will not be any billing or charges even if you associate a Usage Plan. This is however a required step for you to be able to proceed with using Recovery Plans and Drills for Regional resiliency scenarios.

## Next step

[Create a service group](CreateServiceGroup.md)
[Create a Usage Plan](https://github.com/Azure/ResiliencyInAzure/blob/main/Create%20Usage%20Plan%20for%20Service%20Group)
