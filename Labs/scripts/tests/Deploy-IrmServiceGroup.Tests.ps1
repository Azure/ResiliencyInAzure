BeforeAll {
    . "$PSScriptRoot/../Deploy-IrmServiceGroup.ps1"
}

Describe 'Stage range selection' {
    It 'selects an inclusive range' {
        Get-StageRange -Start Membership -Stop Enrollment | Should -Be @('Membership', 'UsagePlan', 'Enrollment')
    }

    It 'rejects a reversed range' {
        { Get-StageRange -Start Drill -Stop UsagePlan } | Should -Throw '*occurs after*'
    }
}

Describe 'Stable relationship names' {
    It 'is deterministic and case insensitive' {
        $first = Get-StableRelationshipName '/providers/Microsoft.Management/serviceGroups/GroupA' '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/RG/providers/Microsoft.Compute/virtualMachines/VM1'
        $second = Get-StableRelationshipName '/PROVIDERS/microsoft.management/servicegroups/groupa' '/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/rg/providers/microsoft.compute/virtualmachines/vm1/'
        $first | Should -Be $second
        $first | Should -Match '^sg-[0-9a-f]{32}$'
    }
}

Describe 'ARM long-running operations' {
    BeforeEach {
        Mock Start-Sleep
        $script:poll = 0
    }

    It 'polls until succeeded and honors nonterminal states' {
        Mock Invoke-ArmRequest {
            $script:poll++
            [pscustomobject]@{ Body = [pscustomobject]@{ status = $(if ($script:poll -eq 1) { 'Running' } else { 'Succeeded' }) }; Headers = @{}; StatusCode = 200 }
        }
        $result = Wait-ArmOperation -Headers @{ 'Azure-AsyncOperation' = 'https://management.azure.com/operations/1?api-version=x' } -TimeoutSeconds 30 -InitialDelaySeconds 1
        $result.status | Should -Be 'Succeeded'
        Should -Invoke Invoke-ArmRequest -Times 2 -Exactly
    }

    It 'throws a detailed terminal failure' {
        Mock Invoke-ArmRequest { [pscustomobject]@{ Body = [pscustomobject]@{ status = 'Failed'; error = [pscustomobject]@{ code = 'BadThing'; message = 'Nope' } }; Headers = @{}; StatusCode = 200 } }
        { Wait-ArmOperation -Headers @{ Location = 'https://management.azure.com/operations/2' } -TimeoutSeconds 30 } | Should -Throw '*BadThing*Nope*'
    }

    It 'times out while retrying accepted operations' {
        Mock Invoke-ArmRequest { [pscustomobject]@{ Body = [pscustomobject]@{ status = 'Accepted' }; Headers = @{}; StatusCode = 202 } }
        Mock Start-Sleep { throw [System.TimeoutException]::new('test timeout') }
        { Wait-ArmOperation -Headers @{ 'Operation-Location' = 'https://management.azure.com/operations/3' } -TimeoutSeconds 1 } | Should -Throw '*test timeout*'
    }
}

Describe 'Existing and conflicting resources' {
    BeforeEach { $script:AzContext = [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000001' } } }

    It 'reuses a matching Service Group' {
        Mock Get-ArmResource { [pscustomobject]@{ NotFound = $false; Body = [pscustomobject]@{ properties = [pscustomobject]@{ displayName = 'Demo'; parent = [pscustomobject]@{ resourceId = '/providers/Microsoft.Management/serviceGroups/00000000-0000-0000-0000-000000000001' } } } } }
        Mock Invoke-VerifiedPut
        $config = [pscustomobject]@{ serviceGroup = [pscustomobject]@{ id = 'demo'; displayName = 'Demo'; parentResourceId = $null } }
        (Invoke-ServiceGroupStage $config).Outcome | Should -Be 'Reused'
        Should -Invoke Invoke-VerifiedPut -Times 0 -Exactly
    }

    It 'detects a conflicting enrollment target' {
        Mock Test-ArmResourceExists { $true }
        Mock Get-ArmResource { [pscustomobject]@{ NotFound = $false; Body = [pscustomobject]@{ properties = [pscustomobject]@{ serviceGroupId = '/providers/Microsoft.Management/serviceGroups/other' } } } }
        $config = [pscustomobject]@{ enrollment = [pscustomobject]@{ name = 'enroll' } }
        { Invoke-EnrollmentStage $config '/providers/Microsoft.Management/serviceGroups/wanted' '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.AzureResilienceManagement/usagePlans/plan' } | Should -Throw '*conflict*'
    }
}

Describe 'Drill resource classification' {
    It 'includes supported resources only when the native fault is verified' {
        $resource = [pscustomobject]@{ ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm'; ResourceType = 'Microsoft.Compute/virtualMachines' }
        $drill = [pscustomobject]@{ id = '/drillResources/1'; properties = [pscustomobject]@{ faultProperties = [pscustomobject]@{ defaultFault = [pscustomobject]@{ faultName = 'shutdown'; faultUrn = 'urn:official'; targetResourceId = $resource.ResourceId } } } }
        $result = Get-DrillResourceClassification $resource $drill
        $result.Status | Should -Be 'Included'
        $result.FaultUrn | Should -Be 'urn:official'
    }

    It 'marks a supported resource unresolved when no API fault exists' {
        $resource = [pscustomobject]@{ ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Web/sites/app'; ResourceType = 'Microsoft.Web/sites' }
        (Get-DrillResourceClassification $resource $null).Status | Should -Be 'Unresolved'
    }

    It 'excludes an unsupported canonical type' {
        $resource = [pscustomobject]@{ ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/store'; ResourceType = 'Microsoft.Storage/storageAccounts' }
        (Get-DrillResourceClassification $resource $null).Status | Should -Be 'Excluded'
    }
}

Describe 'REST error parsing' {
    It 'extracts Azure fields and request IDs' {
        $body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'AuthorizationFailed'; message = 'Denied'; target = 'scope'; details = @([pscustomobject]@{ code = 'Child' }) } }
        $result = Get-ArmErrorDetail $body @{ 'x-ms-request-id' = 'request-123' } 403
        $result.Code | Should -Be 'AuthorizationFailed'
        $result.Target | Should -Be 'scope'
        $result.CorrelationId | Should -Be 'request-123'
    }
}