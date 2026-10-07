#requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)]
    [string]$ParameterFile,

    [ValidateSet('ServiceGroup', 'Membership', 'UsagePlan', 'Enrollment', 'GoalAssignment', 'Drill', 'DrillResources')]
    [string]$StartAtStage = 'ServiceGroup',

    [ValidateSet('ServiceGroup', 'Membership', 'UsagePlan', 'Enrollment', 'GoalAssignment', 'Drill', 'DrillResources')]
    [string]$StopAfterStage = 'DrillResources',

    [string]$TenantId,
    [switch]$CreateMissingPrerequisites,
    [switch]$Force,
    [switch]$ContinueOnResourceError,
    [switch]$RegisterMissingProviders,

    [ValidateRange(1, 32)]
    [int]$MaxConcurrency = 1,

    [ValidateRange(30, 86400)]
    [int]$OperationTimeoutSeconds = 1800,

    [ValidateRange(1, 60)]
    [int]$InitialPollDelaySeconds = 2,

    [ValidateRange(1, 300)]
    [int]$MaximumPollDelaySeconds = 30,

    [ValidateRange(10, 600)]
    [int]$ArmRequestTimeoutSeconds = 120,

    [ValidateRange(0, 10)]
    [int]$AuthorizationRetryCount = 6,

    [ValidateRange(1, 300)]
    [int]$AuthorizationRetryDelaySeconds = 10,

    [ValidateRange(0, 10)]
    [int]$ResourcePropagationRetryCount = 6,

    [ValidateRange(1, 300)]
    [int]$ResourcePropagationRetryDelaySeconds = 10,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ApiVersions = @{
    ServiceGroup  = '2024-02-01-preview'
    Membership    = '2023-09-01-preview'
    UsagePlan     = '2026-08-31-preview'
    Enrollment    = '2026-08-31-preview'
    GoalAssignment = '2026-08-31-preview'
    Drill         = '2026-06-01-preview'
    ResourceGroup = '2021-04-01'
    Subscription  = '2020-01-01'
    Provider      = '2021-04-01'
}
$script:StageOrder = @('ServiceGroup', 'Membership', 'UsagePlan', 'Enrollment', 'GoalAssignment', 'Drill', 'DrillResources')
$script:StageResults = [System.Collections.Generic.List[object]]::new()
$script:MembershipSummary = $null
$script:ClassificationSummary = $null
$script:AzContext = $null

# This map reflects the published Availability Zone Down support categories.
# Native fault identifiers are deliberately discovered from DrillResource.defaultFault.
$script:ZoneDownSupportedTypes = [ordered]@{
    'microsoft.compute/virtualmachines'                 = 'Virtual Machines'
    'microsoft.compute/virtualmachinescalesets'        = 'Virtual Machine Scale Sets'
    'microsoft.containerservice/managedclusters'       = 'Azure Kubernetes Service'
    'microsoft.dbforpostgresql/flexibleservers'        = 'Azure Database for PostgreSQL flexible servers'
    'microsoft.dbformysql/flexibleservers'             = 'Azure Database for MySQL flexible servers'
    'microsoft.sql/servers/databases'                   = 'Azure SQL Database'
    'microsoft.network/loadbalancers'                  = 'Azure Load Balancer'
    'microsoft.cache/redis'                             = 'Azure Cache for Redis'
    'microsoft.web/sites'                              = 'App Service'
}

function ConvertFrom-ArmContent {
    [CmdletBinding()]
    param([AllowNull()][string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    try { return $Content | ConvertFrom-Json -Depth 100 }
    catch { return $Content }
}

function Get-ResponseHeader {
    [CmdletBinding()]
    param([AllowNull()]$Headers, [Parameter(Mandatory)][string[]]$Name)
    if ($null -eq $Headers) { return $null }
    foreach ($candidate in $Name) {
        foreach ($entry in $Headers.GetEnumerator()) {
            if ([string]$entry.Key -ieq $candidate) {
                if ($entry.Value -is [System.Collections.IEnumerable] -and $entry.Value -isnot [string]) {
                    return [string](@($entry.Value)[0])
                }
                return [string]$entry.Value
            }
        }
    }
    return $null
}

function Get-ArmErrorDetail {
    [CmdletBinding()]
    param([AllowNull()]$Body, [AllowNull()]$Headers, [int]$StatusCode)
    $errorProperty = if ($Body) { $Body.PSObject.Properties['error'] } else { $null }
    $errorObject = if ($errorProperty) { $errorProperty.Value } else { $Body }
    $codeProperty = if ($errorObject) { $errorObject.PSObject.Properties['code'] } else { $null }
    $messageProperty = if ($errorObject) { $errorObject.PSObject.Properties['message'] } else { $null }
    $targetProperty = if ($errorObject) { $errorObject.PSObject.Properties['target'] } else { $null }
    $detailsProperty = if ($errorObject) { $errorObject.PSObject.Properties['details'] } else { $null }
    [pscustomobject]@{
        StatusCode    = $StatusCode
        Code          = if ($codeProperty) { [string]$codeProperty.Value } else { $null }
        Message       = if ($messageProperty) { [string]$messageProperty.Value } else { [string]$errorObject }
        Target        = if ($targetProperty) { [string]$targetProperty.Value } else { $null }
        Details       = if ($detailsProperty) { @($detailsProperty.Value) } else { @() }
        CorrelationId = Get-ResponseHeader -Headers $Headers -Name @('x-ms-correlation-request-id', 'x-ms-request-id', 'request-id')
    }
}

function ConvertTo-ArmErrorDetailsJson {
    [CmdletBinding()]
    param([AllowNull()]$Details)
    if ($null -eq $Details) { return '[]' }
    $items = @($Details)
    if ($items.Count -eq 0) { return '[]' }
    return ($items | ConvertTo-Json -Depth 20 -Compress)
}

function Add-ApiVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowNull()][string]$ApiVersion)
    if ([string]::IsNullOrWhiteSpace($ApiVersion) -or $Path -match '(?i)[?&]api-version=') { return $Path }
    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    return "$Path${separator}api-version=$([uri]::EscapeDataString($ApiVersion))"
}

function Get-ArmRequestTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RequestPath)
    if ($RequestPath -notmatch '^https://') { return @{ Path = $RequestPath } }
    $requestUri = [uri]$RequestPath
    $resourceManagerUri = [uri]$script:AzContext.Environment.ResourceManagerUrl
    if ($requestUri.Authority -ine $resourceManagerUri.Authority) {
        throw "ARM operation URL host '$($requestUri.Authority)' does not match the active environment host '$($resourceManagerUri.Authority)'."
    }
    return @{ Uri = $requestUri.AbsoluteUri }
}

function Invoke-ArmWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$RequestPath,
        [AllowNull()][string]$Payload,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers
    )
    $target = Get-ArmRequestTarget -RequestPath $RequestPath
    $uri = if ($target.ContainsKey('Uri')) {
        [uri]$target.Uri
    }
    else {
        [uri]"$([string]$script:AzContext.Environment.ResourceManagerUrl.TrimEnd('/'))/$($target.Path.TrimStart('/'))"
    }
    $accessToken = Get-AzAccessToken -ResourceUrl $script:AzContext.Environment.ResourceManagerUrl -DefaultProfile $script:AzContext -AsSecureString
    if ($null -eq $accessToken -or $null -eq $accessToken.Token) { throw 'Unable to acquire an Azure Resource Manager access token.' }
    $arguments = @{
        Uri = $uri
        Method = $Method
        Headers = $Headers
        Authentication = 'Bearer'
        Token = $accessToken.Token
        SkipHttpErrorCheck = $true
        ConnectionTimeoutSeconds = [math]::Min(30, $ArmRequestTimeoutSeconds)
        OperationTimeoutSeconds = $ArmRequestTimeoutSeconds
        ErrorAction = 'Stop'
    }
    if ($null -ne $Payload) {
        $arguments.Body = $Payload
        $arguments.ContentType = 'application/json'
    }
    Invoke-WebRequest @arguments
}

function Invoke-ArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PUT', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$ApiVersion,
        [AllowNull()]$Body,
        [switch]$AllowNotFound,
        [ValidateRange(0, 10)][int]$RetryCount = 3,
        [AllowNull()][System.Collections.IDictionary]$RequestHeaders
    )
    $requestPath = Add-ApiVersion -Path $Path -ApiVersion $ApiVersion
    Write-Verbose "ARM $Method $($requestPath -replace '(?i)(sig|token|code)=[^&]+', '$1=REDACTED')"
    $payload = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 100 -Compress } else { $null }
    $maximumAttempt = [math]::Max($RetryCount, $AuthorizationRetryCount)
    for ($attempt = 0; $attempt -le $maximumAttempt; $attempt++) {
        try {
            $arguments = @{ Method = $Method; DefaultProfile = $script:AzContext }
            $target = Get-ArmRequestTarget -RequestPath $requestPath
            foreach ($entry in $target.GetEnumerator()) { $arguments[$entry.Key] = $entry.Value }
            if ($null -ne $payload) { $arguments.Payload = $payload }
            $raw = if ($RequestHeaders -and $RequestHeaders.Count) {
                Invoke-ArmWebRequest -Method $Method -RequestPath $requestPath -Payload $payload -Headers $RequestHeaders
            }
            else {
                Invoke-AzRestMethod @arguments
            }
            $statusCode = [int]$raw.StatusCode
            $responseBody = ConvertFrom-ArmContent -Content $raw.Content
            if ($statusCode -eq 404 -and $AllowNotFound) {
                return [pscustomobject]@{ StatusCode = $statusCode; Body = $responseBody; Headers = $raw.Headers; NotFound = $true; Path = $requestPath }
            }
            if ($statusCode -in 200, 201, 202, 204) {
                return [pscustomobject]@{ StatusCode = $statusCode; Body = $responseBody; Headers = $raw.Headers; NotFound = $false; Path = $requestPath }
            }
            $detail = Get-ArmErrorDetail -Body $responseBody -Headers $raw.Headers -StatusCode $statusCode
            $isAuthorizationPropagationError = $statusCode -eq 403 -and $detail.Code -iin @('AuthorizationFailed', 'LinkedAuthorizationFailed')
            if ($isAuthorizationPropagationError -and $attempt -lt $AuthorizationRetryCount) {
                $delay = [math]::Min(60, $AuthorizationRetryDelaySeconds * [math]::Pow(2, $attempt))
                Write-Warning "ARM authorization for this scope or a linked scope has not propagated or access is insufficient; retrying in $delay second(s) (attempt $($attempt + 1) of $AuthorizationRetryCount)."
                Start-Sleep -Seconds $delay
                continue
            }
            if ($statusCode -in 408, 429, 500, 502, 503, 504 -and $attempt -lt $RetryCount) {
                $retryAfter = Get-ResponseHeader -Headers $raw.Headers -Name @('Retry-After')
                $delay = if ($retryAfter -match '^\d+$') { [int]$retryAfter } else { [math]::Min(30, [math]::Pow(2, $attempt + 1)) }
                Write-Warning "Transient ARM response $statusCode ($($detail.Code)); retrying in $delay second(s)."
                Start-Sleep -Seconds $delay
                continue
            }
            $details = ConvertTo-ArmErrorDetailsJson -Details $detail.Details
            if ($isAuthorizationPropagationError) {
                throw "ARM $Method failed after $($attempt + 1) authorization attempt(s): HTTP $statusCode; code=$($detail.Code); message=$($detail.Message); target=$($detail.Target); details=$details; requestId=$($detail.CorrelationId). Authorization propagation may still be pending; verify access at both the requested and linked scopes, then refresh the Azure context before retrying."
            }
            throw "ARM $Method failed: HTTP $statusCode; code=$($detail.Code); message=$($detail.Message); target=$($detail.Target); details=$details; requestId=$($detail.CorrelationId)"
        }
        catch {
            if ($attempt -lt $RetryCount -and $_.Exception.Message -match '(?i)timeout|temporar|connection|429|50[0234]') {
                $delay = [math]::Min(30, [math]::Pow(2, $attempt + 1))
                Write-Warning "Transient ARM request failure; retrying in $delay second(s): $($_.Exception.Message)"
                Start-Sleep -Seconds $delay
                continue
            }
            throw
        }
    }
}

function Wait-ArmOperation {
    [CmdletBinding()]
    param(
        [AllowNull()]$Headers,
        [int]$TimeoutSeconds = $OperationTimeoutSeconds,
        [int]$InitialDelaySeconds = $InitialPollDelaySeconds,
        [int]$MaximumDelaySeconds = $MaximumPollDelaySeconds
    )
    $operationUri = Get-ResponseHeader -Headers $Headers -Name @('Azure-AsyncOperation', 'Operation-Location', 'Location')
    if ([string]::IsNullOrWhiteSpace($operationUri)) {
        Write-Information 'ARM request completed without an asynchronous operation URL.' -InformationAction Continue
        return $null
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $delay = $InitialDelaySeconds
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $response = Invoke-ArmRequest -Method GET -Path $operationUri -ApiVersion $null -RetryCount 3
        $state = if ($response.Body.status) { [string]$response.Body.status } elseif ($response.Body.properties.provisioningState) { [string]$response.Body.properties.provisioningState } else { 'Succeeded' }
        Write-Verbose "ARM operation state: $state"
        Write-Information "ARM operation state: $state (elapsed $([math]::Round($stopwatch.Elapsed.TotalSeconds))s; timeout ${TimeoutSeconds}s)." -InformationAction Continue
        if ($state -ieq 'Succeeded') { return $response.Body }
        if ($state -in @('Failed', 'Canceled', 'Cancelled')) {
            $detail = Get-ArmErrorDetail -Body $response.Body -Headers $response.Headers -StatusCode $response.StatusCode
            throw "ARM operation ${state}: code=$($detail.Code); message=$($detail.Message); target=$($detail.Target); requestId=$($detail.CorrelationId)"
        }
        if ($state -notin @('InProgress', 'Running', 'Accepted', 'Creating', 'Updating', 'Provisioning')) { throw "ARM operation returned unknown state '$state'." }
        $retryAfter = Get-ResponseHeader -Headers $response.Headers -Name @('Retry-After')
        $sleepSeconds = if ($retryAfter -match '^\d+$') { [math]::Min($MaximumDelaySeconds, [int]$retryAfter) } else { $delay }
        Start-Sleep -Seconds $sleepSeconds
        $delay = [math]::Min($MaximumDelaySeconds, [math]::Max($delay + 1, $delay * 2))
    }
    throw [System.TimeoutException]::new("ARM operation exceeded the configured timeout of $TimeoutSeconds seconds.")
}

function Get-ArmResource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ResourceId, [Parameter(Mandatory)][string]$ApiVersion, [switch]$AllowNotFound)
    Invoke-ArmRequest -Method GET -Path $ResourceId -ApiVersion $ApiVersion -AllowNotFound:$AllowNotFound
}

function Test-ArmResourceExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$ApiVersion,
        [ValidateRange(0, 10)][int]$RetryNotFoundCount = 0,
        [ValidateRange(1, 300)][int]$RetryDelaySeconds = 10
    )
    for ($attempt = 0; $attempt -le $RetryNotFoundCount; $attempt++) {
        $response = Get-ArmResource -ResourceId $ResourceId -ApiVersion $ApiVersion -AllowNotFound
        if (-not $response.NotFound) { return $true }
        if ($attempt -lt $RetryNotFoundCount) {
            $delay = [math]::Min(60, $RetryDelaySeconds * [math]::Pow(2, $attempt))
            Write-Warning "ARM resource '$ResourceId' is not visible yet; retrying in $delay second(s) (attempt $($attempt + 1) of $RetryNotFoundCount)."
            Start-Sleep -Seconds $delay
        }
    }
    return $false
}

function Test-ServiceGroupExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ResourceId)
    Test-ArmResourceExists `
        -ResourceId $ResourceId `
        -ApiVersion $script:ApiVersions.ServiceGroup `
        -RetryNotFoundCount $ResourcePropagationRetryCount `
        -RetryDelaySeconds $ResourcePropagationRetryDelaySeconds
}

function Assert-Prerequisite {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Prerequisite failed: $Message" }
}

function Assert-ArmName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Label)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._()\-]{0,89}$') { throw "$Label '$Value' contains invalid characters or has an invalid length." }
}

function Assert-Guid {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Label)
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed)) { throw "$Label must be a GUID." }
}

function Get-StableRelationshipName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServiceGroupId, [Parameter(Mandatory)][string]$ResourceId)
    $bytes = [Text.Encoding]::UTF8.GetBytes("$($ServiceGroupId.ToLowerInvariant())|$($ResourceId.TrimEnd('/').ToLowerInvariant())")
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return 'sg-' + ([Convert]::ToHexString($hash).ToLowerInvariant().Substring(0, 32))
}

function Get-CanonicalResourceType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ResourceId, [AllowNull()][string]$ReturnedType)
    if (-not [string]::IsNullOrWhiteSpace($ReturnedType)) { return $ReturnedType.ToLowerInvariant() }
    $providerIndex = $ResourceId.IndexOf('/providers/', [StringComparison]::OrdinalIgnoreCase)
    if ($providerIndex -lt 0) { return $null }
    $segments = $ResourceId.Substring($providerIndex + 11).Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    if ($segments.Count -lt 2) { return $null }
    $types = [Collections.Generic.List[string]]::new()
    $types.Add($segments[0])
    for ($index = 1; $index -lt $segments.Count; $index += 2) { $types.Add($segments[$index]) }
    return ($types -join '/').ToLowerInvariant()
}

function Get-DrillResourceClassification {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Resource, [AllowNull()]$DrillResource)
    $resourceId = [string]$Resource.ResourceId
    $type = Get-CanonicalResourceType -ResourceId $resourceId -ReturnedType ([string]$Resource.ResourceType)
    if (-not $script:ZoneDownSupportedTypes.Contains($type)) {
        return [pscustomobject]@{ ResourceId = $resourceId; ResourceType = $type; Status = 'Excluded'; FaultName = $null; FaultUrn = $null; Reason = 'Resource type is not listed as supporting a system-native Zone Down fault.'; DrillResourceId = if ($DrillResource) { $DrillResource.id } else { $null } }
    }
    if (-not $DrillResource) {
        return [pscustomobject]@{ ResourceId = $resourceId; ResourceType = $type; Status = 'Unresolved'; FaultName = $null; FaultUrn = $null; Reason = 'The API did not return a Drill Resource for this Service Group member.'; DrillResourceId = $null }
    }
    $fault = $DrillResource.properties.faultProperties.defaultFault
    if (-not $fault -or [string]::IsNullOrWhiteSpace([string]$fault.faultUrn) -or [string]::IsNullOrWhiteSpace([string]$fault.faultName)) {
        return [pscustomobject]@{ ResourceId = $resourceId; ResourceType = $type; Status = 'Unresolved'; FaultName = $null; FaultUrn = $null; Reason = 'The supported resource has no verifiable system-native defaultFault in the Drill Resource response.'; DrillResourceId = $DrillResource.id }
    }
    [pscustomobject]@{ ResourceId = $resourceId; ResourceType = $type; Status = 'Included'; FaultName = [string]$fault.faultName; FaultUrn = [string]$fault.faultUrn; Reason = $null; DrillResourceId = $DrillResource.id }
}

function New-StageResult {
    param([string]$Stage, [string]$Status, [string]$ResourceId, [string]$Outcome, [datetime]$Started, [AllowNull()]$ErrorDetail)
    [pscustomobject]@{ Stage = $Stage; Status = $Status; ResourceId = $ResourceId; Outcome = $Outcome; Error = $ErrorDetail; DurationSeconds = [math]::Round(((Get-Date) - $Started).TotalSeconds, 3) }
}

function Invoke-VerifiedPut {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ResourceId, [string]$ApiVersion, $Body, [string]$Action)
    if (-not $PSCmdlet.ShouldProcess($ResourceId, $Action)) { return 'Skipped' }
    $response = Invoke-ArmRequest -Method PUT -Path $ResourceId -ApiVersion $ApiVersion -Body $Body
    Wait-ArmOperation -Headers $response.Headers | Out-Null
    $verified = Get-ArmResource -ResourceId $ResourceId -ApiVersion $ApiVersion
    if ($verified.Body.properties.provisioningState -in @('Failed', 'Canceled', 'Cancelled')) { throw "Verification GET returned provisioningState '$($verified.Body.properties.provisioningState)'." }
    if ($response.StatusCode -eq 201) { return 'Created' }
    return 'Updated'
}

function Invoke-ServiceGroupStage {
    [CmdletBinding(SupportsShouldProcess)]
    param($Config)
    $started = Get-Date
    $name = [string]$Config.serviceGroup.id
    Assert-ArmName -Value $name -Label 'Service Group ID'
    $resourceId = "/providers/Microsoft.Management/serviceGroups/$([uri]::EscapeDataString($name))"
    $existing = Get-ArmResource -ResourceId $resourceId -ApiVersion $script:ApiVersions.ServiceGroup -AllowNotFound
    $parent = if ($Config.serviceGroup.parentResourceId) { [string]$Config.serviceGroup.parentResourceId } else { "/providers/Microsoft.Management/serviceGroups/$($script:AzContext.Tenant.Id)" }
    if ($parent -notmatch '^/providers/Microsoft\.Management/serviceGroups/[A-Za-z0-9._()\-]+$') { throw 'serviceGroup.parentResourceId is not a valid Service Group resource ID.' }
    $desired = @{ properties = @{ displayName = [string]$Config.serviceGroup.displayName; parent = @{ resourceId = $parent } } }
    if (-not $existing.NotFound) {
        $matches = ([string]$existing.Body.properties.displayName -ceq [string]$Config.serviceGroup.displayName) -and ([string]$existing.Body.properties.parent.resourceId -ieq $parent)
        if ($matches -or -not $Force) {
            if (-not $matches) { Write-Warning 'The existing Service Group differs in mutable properties. Use -Force to update it.' }
            return New-StageResult ServiceGroup Succeeded $resourceId Reused $started $null
        }
    }
    $outcome = Invoke-VerifiedPut -ResourceId $resourceId -ApiVersion $script:ApiVersions.ServiceGroup -Body $desired -Action 'Create or update Service Group' -WhatIf:$WhatIfPreference
    New-StageResult ServiceGroup Succeeded $resourceId $outcome $started $null
}

function Get-ValidatedResources {
    [CmdletBinding()]
    param($Config)
    $valid = [System.Collections.Generic.List[object]]::new()
    $invalid = [System.Collections.Generic.List[object]]::new()
    $duplicates = [System.Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($idValue in @($Config.resources)) {
        $id = ([string]$idValue).TrimEnd('/')
        if (-not $seen.Add($id)) { $duplicates.Add($id); continue }
        if ($id -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+(?:/[^/]+/[^/]+)*$') {
            $invalid.Add([pscustomobject]@{ ResourceId = $id; Reason = 'Invalid Azure resource ID syntax.' }); continue
        }
        try {
            $resource = Get-AzResource -ResourceId $id -DefaultProfile $script:AzContext -ErrorAction Stop
            if (-not $resource) { throw 'Resource was not returned.' }
            $valid.Add([pscustomobject]@{ ResourceId = $id; ResourceType = [string]$resource.ResourceType })
        }
        catch { $invalid.Add([pscustomobject]@{ ResourceId = $id; Reason = "Resource is missing or inaccessible: $($_.Exception.Message)" }) }
    }
    [pscustomobject]@{ Valid = @($valid); Invalid = @($invalid); Duplicates = @($duplicates) }
}

function Invoke-MembershipStage {
    [CmdletBinding(SupportsShouldProcess)]
    param($Config, [string]$ServiceGroupResourceId)
    $started = Get-Date
    Assert-Prerequisite (Test-ServiceGroupExists $ServiceGroupResourceId) "Service Group '$ServiceGroupResourceId' does not exist or did not become visible after $ResourcePropagationRetryCount propagation retries."
    $resources = Get-ValidatedResources -Config $Config
    $added = [Collections.Generic.List[string]]::new(); $existingIds = [Collections.Generic.List[string]]::new(); $failed = [Collections.Generic.List[object]]::new(); $pending = [Collections.Generic.List[object]]::new()
    foreach ($resource in $resources.Valid) {
        $relationshipName = Get-StableRelationshipName -ServiceGroupId $ServiceGroupResourceId -ResourceId $resource.ResourceId
        $relationshipId = "$($resource.ResourceId)/providers/Microsoft.Relationships/serviceGroupMember/$relationshipName"
        try {
            $current = Get-ArmResource -ResourceId $relationshipId -ApiVersion $script:ApiVersions.Membership -AllowNotFound
            if (-not $current.NotFound) {
                if ([string]$current.Body.properties.targetId -ine $ServiceGroupResourceId) { throw "Membership conflict: existing targetId is '$($current.Body.properties.targetId)'." }
                $existingIds.Add($resource.ResourceId); continue
            }
            if ($PSCmdlet.ShouldProcess($relationshipId, 'Create Service Group member relationship')) { $pending.Add([pscustomobject]@{ Resource = $resource; RelationshipId = $relationshipId }) }
        }
        catch {
            $failed.Add([pscustomobject]@{ ResourceId = $resource.ResourceId; Error = $_.Exception.Message })
            if (-not $ContinueOnResourceError) { throw }
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
        }
    }
    $submitted = if ($MaxConcurrency -eq 1) {
        foreach ($item in $pending) {
            try { [pscustomobject]@{ Item = $item; Response = (Invoke-ArmRequest PUT $item.RelationshipId $script:ApiVersions.Membership @{ properties = @{ targetId = $ServiceGroupResourceId } }); Error = $null } }
            catch { [pscustomobject]@{ Item = $item; Response = $null; Error = $_.Exception.Message } }
        }
    }
    else {
        $profile = $script:AzContext; $apiVersion = $script:ApiVersions.Membership; $target = $ServiceGroupResourceId
        $pending | ForEach-Object -Parallel {
            try {
                $path = "$($_.RelationshipId)?api-version=$using:apiVersion"
                $payload = @{ properties = @{ targetId = $using:target } } | ConvertTo-Json -Depth 10 -Compress
                $raw = Invoke-AzRestMethod -Method PUT -Path $path -Payload $payload -DefaultProfile $using:profile -ErrorAction Stop
                $body = if ($raw.Content) { $raw.Content | ConvertFrom-Json -Depth 100 } else { $null }
                if ([int]$raw.StatusCode -notin 200, 201, 202, 204) { throw "HTTP $($raw.StatusCode): $($raw.Content)" }
                [pscustomobject]@{ Item = $_; Response = [pscustomobject]@{ StatusCode = [int]$raw.StatusCode; Body = $body; Headers = $raw.Headers }; Error = $null }
            }
            catch { [pscustomobject]@{ Item = $_; Response = $null; Error = $_.Exception.Message } }
        } -ThrottleLimit $MaxConcurrency
    }
    foreach ($submission in @($submitted)) {
        try {
            if ($submission.Error) { throw $submission.Error }
            Wait-ArmOperation -Headers $submission.Response.Headers | Out-Null
            $verified = Get-ArmResource -ResourceId $submission.Item.RelationshipId -ApiVersion $script:ApiVersions.Membership
            if ([string]$verified.Body.properties.targetId -ine $ServiceGroupResourceId) { throw 'Membership verification returned an unexpected targetId.' }
            $added.Add($submission.Item.Resource.ResourceId)
        }
        catch {
            $failed.Add([pscustomobject]@{ ResourceId = $submission.Item.Resource.ResourceId; Error = $_.Exception.Message })
            if (-not $ContinueOnResourceError) { throw }
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
        }
    }
    $script:MembershipSummary = [pscustomobject]@{ Added = @($added); Existing = @($existingIds); SkippedDuplicates = $resources.Duplicates; InvalidOrInaccessible = $resources.Invalid; Failed = @($failed); ValidResources = $resources.Valid }
    New-StageResult Membership $(if ($failed.Count -or $resources.Invalid.Count) { 'Partial' } else { 'Succeeded' }) $ServiceGroupResourceId $(if ($added.Count) { 'Created' } else { 'Reused' }) $started $null
}

function Assert-SubscriptionAndResourceGroup {
    param([string]$SubscriptionId, [string]$ResourceGroupName)
    Assert-Guid $SubscriptionId 'Subscription ID'; Assert-ArmName $ResourceGroupName 'Resource group name'
    Assert-Prerequisite (Test-ArmResourceExists "/subscriptions/$SubscriptionId" $script:ApiVersions.Subscription) "Subscription '$SubscriptionId' is missing or inaccessible."
    Assert-Prerequisite (Test-ArmResourceExists "/subscriptions/$SubscriptionId/resourceGroups/$([uri]::EscapeDataString($ResourceGroupName))" $script:ApiVersions.ResourceGroup) "Resource group '$ResourceGroupName' is missing or inaccessible."
}

function Invoke-UsagePlanStage {
    [CmdletBinding(SupportsShouldProcess)] param($Config)
    $started = Get-Date; $plan = $Config.usagePlan
    Assert-SubscriptionAndResourceGroup $plan.subscriptionId $plan.resourceGroupName; Assert-ArmName $plan.name 'Usage Plan name'
    $id = "/subscriptions/$($plan.subscriptionId)/resourceGroups/$([uri]::EscapeDataString($plan.resourceGroupName))/providers/Microsoft.AzureResilienceManagement/usagePlans/$([uri]::EscapeDataString($plan.name))"
    $existing = Get-ArmResource $id $script:ApiVersions.UsagePlan -AllowNotFound
    if (-not $existing.NotFound) {
        if ([string]$existing.Body.properties.planType -ine 'Standard') { if (-not $Force) { throw "Existing Usage Plan is '$($existing.Body.properties.planType)', not Standard." } }
        elseif ([string]$existing.Body.location -ieq [string]$plan.location) { return New-StageResult UsagePlan Succeeded $id Reused $started $null }
        elseif (-not $Force) { throw "Existing Usage Plan location '$($existing.Body.location)' differs from '$($plan.location)'." }
    }
    $outcome = Invoke-VerifiedPut $id $script:ApiVersions.UsagePlan @{ location = [string]$plan.location; properties = @{ planType = 'Standard' } } 'Create or update Standard Usage Plan' -WhatIf:$WhatIfPreference
    New-StageResult UsagePlan Succeeded $id $outcome $started $null
}

function Invoke-EnrollmentStage {
    [CmdletBinding(SupportsShouldProcess)] param($Config, [string]$ServiceGroupResourceId, [string]$UsagePlanResourceId)
    $started = Get-Date; Assert-ArmName $Config.enrollment.name 'Enrollment name'
    Assert-Prerequisite (Test-ArmResourceExists $UsagePlanResourceId $script:ApiVersions.UsagePlan) "Usage Plan '$UsagePlanResourceId' does not exist."
    Assert-Prerequisite (Test-ServiceGroupExists $ServiceGroupResourceId) "Service Group '$ServiceGroupResourceId' does not exist or did not become visible after $ResourcePropagationRetryCount propagation retries."
    $id = "$UsagePlanResourceId/enrollments/$([uri]::EscapeDataString($Config.enrollment.name))"
    $existing = Get-ArmResource $id $script:ApiVersions.Enrollment -AllowNotFound
    if (-not $existing.NotFound) {
        if ([string]$existing.Body.properties.serviceGroupId -ine $ServiceGroupResourceId) { throw "Enrollment conflict: existing serviceGroupId is '$($existing.Body.properties.serviceGroupId)'." }
        return New-StageResult Enrollment Succeeded $id Reused $started $null
    }
    $outcome = Invoke-VerifiedPut $id $script:ApiVersions.Enrollment @{ properties = @{ serviceGroupId = $ServiceGroupResourceId } } 'Create enrollment' -WhatIf:$WhatIfPreference
    New-StageResult Enrollment Succeeded $id $outcome $started $null
}

function Invoke-GoalAssignmentStage {
    [CmdletBinding(SupportsShouldProcess)] param($Config, [string]$ServiceGroupResourceId)
    $started = Get-Date; Assert-ArmName $Config.goalAssignment.name 'Goal Assignment name'
    Assert-Prerequisite (Test-ServiceGroupExists $ServiceGroupResourceId) "Service Group '$ServiceGroupResourceId' does not exist or did not become visible after $ResourcePropagationRetryCount propagation retries."
    $id = "$ServiceGroupResourceId/providers/Microsoft.AzureResilienceManagement/goalAssignments/$([uri]::EscapeDataString($Config.goalAssignment.name))"
    $existing = Get-ArmResource $id $script:ApiVersions.GoalAssignment -AllowNotFound
    if (-not $existing.NotFound -and $existing.Body.properties.requireZonalResiliency -eq $true) { return New-StageResult GoalAssignment Succeeded $id Reused $started $null }
    if (-not $existing.NotFound -and -not $Force) { throw 'Existing Goal Assignment is not a zonal-only resiliency assignment. Use -Force to update script-owned intent.' }
    $outcome = Invoke-VerifiedPut $id $script:ApiVersions.GoalAssignment @{ properties = @{ requireZonalResiliency = $true } } 'Create zonal resiliency Goal Assignment' -WhatIf:$WhatIfPreference
    New-StageResult GoalAssignment Succeeded $id $outcome $started $null
}

function Invoke-DrillStage {
    [CmdletBinding(SupportsShouldProcess)] param($Config, [string]$ServiceGroupResourceId)
    $started = Get-Date; $drill = $Config.drill
    Assert-SubscriptionAndResourceGroup $drill.subscriptionId $drill.resourceGroupName; Assert-ArmName $drill.name 'Drill name'
    $id = "$ServiceGroupResourceId/providers/Microsoft.AzureResilienceManagement/drills/$([uri]::EscapeDataString($drill.name))"
    $existing = Get-ArmResource $id $script:ApiVersions.Drill -AllowNotFound
    if (-not $existing.NotFound) {
        if ([string]$existing.Body.properties.serviceGroupId -and [string]$existing.Body.properties.serviceGroupId -ine $ServiceGroupResourceId) { throw 'Existing drill is associated with a different Service Group.' }
        if ([string]$existing.Body.properties.drillType -ine 'Zonal') { throw 'Existing drill is not a Zonal drill.' }
        if ([string]$existing.Body.identity.type -notmatch 'SystemAssigned') { throw 'Existing drill does not use a system-assigned managed identity.' }
        if ([string]$existing.Body.properties.provisioningState -notin @('Failed', 'Canceled', 'Cancelled')) {
            return New-StageResult Drill Succeeded $id Reused $started $null
        }
        Write-Warning "Retrying drill '$id' because its provisioning state is '$($existing.Body.properties.provisioningState)'."
    }
    $systemAssignedIdentity = @{ type = 'SystemAssigned' }
    $body = @{
        identity = $systemAssignedIdentity
        properties = @{
            drillType = 'Zonal'
            rbacSetupMode = 'Manual'
            drillAssetProperties = @{
                subscription = [string]$drill.subscriptionId
                region = [string]$drill.location
                resourceGroup = [string]$drill.resourceGroupName
            }
            chaosResourceProperties = @{
                identity = $systemAssignedIdentity
                chaosResourceIdentityForFaults = $systemAssignedIdentity
            }
            recoveryPlanProperties = @{ identity = $systemAssignedIdentity }
            monitoringProperties = @{ identity = $systemAssignedIdentity }
        }
    }
    $outcome = Invoke-VerifiedPut $id $script:ApiVersions.Drill $body 'Create zonal drill (does not execute it)' -WhatIf:$WhatIfPreference
    New-StageResult Drill Succeeded $id $outcome $started $null
}

function Get-AllArmPages {
    param([string]$Path, [string]$ApiVersion)
    $items = [Collections.Generic.List[object]]::new()
    $next = Add-ApiVersion $Path $ApiVersion
    while ($next) {
        $response = Invoke-ArmRequest GET $next $null
        $valueProperty = if ($null -ne $response.Body) { $response.Body.PSObject.Properties['value'] } else { $null }
        if ($null -eq $valueProperty) { throw "ARM list response for '$next' does not contain a value collection." }
        foreach ($item in @($valueProperty.Value)) { $items.Add($item) }
        $nextLinkProperty = $response.Body.PSObject.Properties['nextLink']
        $next = if ($null -ne $nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
    }
    return @($items)
}

function Assert-DrillResourcesConverged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Classifications,
        [Parameter(Mandatory)][object[]]$VerifiedResources
    )
    $verifiedById = @{}
    foreach ($item in $VerifiedResources) { $verifiedById[[string]$item.id.ToLowerInvariant()] = $item }
    foreach ($classification in $Classifications | Where-Object Status -in @('Included', 'Excluded')) {
        if (-not $classification.DrillResourceId -or -not $verifiedById.ContainsKey($classification.DrillResourceId.ToLowerInvariant())) {
            throw "Drill Resource verification failed for '$($classification.ResourceId)': the API did not return the expected Drill Resource."
        }
        $actual = $verifiedById[$classification.DrillResourceId.ToLowerInvariant()]
        $inclusionStateProperty = $actual.properties.PSObject.Properties['inclusionState']
        $provisioningStateProperty = $actual.properties.PSObject.Properties['provisioningState']
        $attentionReasonProperty = $actual.properties.PSObject.Properties['attentionReason']
        $resourceStateProperty = if ($attentionReasonProperty -and $attentionReasonProperty.Value) { $attentionReasonProperty.Value.PSObject.Properties['resourceState'] } else { $null }
        $inclusionState = if ($inclusionStateProperty) { [string]$inclusionStateProperty.Value } else { $null }
        $provisioningState = if ($provisioningStateProperty) { [string]$provisioningStateProperty.Value } else { $null }
        $resourceState = if ($resourceStateProperty) { @($resourceStateProperty.Value) -join ', ' } else { $null }
        $stateDetail = "inclusionState='$inclusionState'; provisioningState='$provisioningState'; resourceState='$resourceState'"
        if ($classification.Status -eq 'Included') {
            if ($inclusionState -notmatch '(?i)include') { throw "Expected '$($classification.ResourceId)' to be included; $stateDetail." }
            if ([string]$actual.properties.faultProperties.defaultFault.faultUrn -ine $classification.FaultUrn) { throw "Default fault verification failed for '$($classification.ResourceId)'." }
        }
        elseif ($inclusionState -notmatch '(?i)exclude') { throw "Expected '$($classification.ResourceId)' to be excluded; $stateDetail." }
    }
}

function Invoke-DrillResourcesStage {
    [CmdletBinding(SupportsShouldProcess)] param($Config, [string]$DrillResourceId)
    $started = Get-Date
    Assert-Prerequisite (Test-ArmResourceExists $DrillResourceId $script:ApiVersions.Drill) "Drill '$DrillResourceId' does not exist."
    $resources = if ($script:MembershipSummary) { $script:MembershipSummary.ValidResources } else { (Get-ValidatedResources $Config).Valid }
    Write-Information "Discovering Drill Resources for $(@($resources).Count) configured resource(s)." -InformationAction Continue
    $drillResources = Get-AllArmPages "$DrillResourceId/drillResources" $script:ApiVersions.Drill
    Write-Information "Discovered $(@($drillResources).Count) Drill Resource record(s)." -InformationAction Continue
    $byResourceId = @{}; foreach ($item in $drillResources) { $byResourceId[[string]$item.properties.resourceId.ToLowerInvariant()] = $item }
    $classifications = foreach ($resource in $resources) { Get-DrillResourceClassification $resource $byResourceId[[string]$resource.ResourceId.ToLowerInvariant()] }
    $unresolved = @($classifications | Where-Object Status -eq 'Unresolved')
    if ($unresolved.Count -and -not $ContinueOnResourceError) { throw "Unable to verify native Zone Down faults for $($unresolved.Count) supported resource(s). Use -ContinueOnResourceError to configure the remaining resources." }
    $include = @($classifications | Where-Object Status -eq 'Included' | ForEach-Object { @{ id = $_.DrillResourceId } })
    $exclude = @($classifications | Where-Object { $_.Status -eq 'Excluded' -and $_.DrillResourceId } | ForEach-Object { $_.DrillResourceId })
    $body = @{ faultDurationInMin = 0; forceInclusionAndUpdate = 'Disable'; resourceLists = @{ includeResources = $include; excludeResources = $exclude; updateResources = @() } }
    if ($PSCmdlet.ShouldProcess($DrillResourceId, 'Converge drill resource inclusion and native default faults')) {
        $requestHeaders = @{ 'operation-id' = [guid]::NewGuid().ToString('D') }
        Write-Information "Submitting Drill Resources action $($requestHeaders['operation-id']) with $($include.Count) inclusion(s) and $($exclude.Count) exclusion(s)." -InformationAction Continue
        $response = Invoke-ArmRequest -Method POST -Path "$DrillResourceId/addOrUpdateResources" -ApiVersion $script:ApiVersions.Drill -Body $body -RequestHeaders $requestHeaders
        Write-Information "Drill Resources action returned HTTP $($response.StatusCode); waiting for completion when asynchronous." -InformationAction Continue
        $operationTimedOut = $false
        try {
            Wait-ArmOperation $response.Headers | Out-Null
        }
        catch [System.TimeoutException] {
            $operationTimedOut = $true
            Write-Warning "$($_.Exception.Message) Performing final Drill Resource state verification because the server-side operation may have completed despite stale polling."
        }
        Write-Information 'Verifying Drill Resources state.' -InformationAction Continue
        $verified = Get-AllArmPages "$DrillResourceId/drillResources" $script:ApiVersions.Drill
        try {
            Assert-DrillResourcesConverged -Classifications $classifications -VerifiedResources $verified
        }
        catch {
            if ($operationTimedOut) {
                throw "Drill Resources operation timed out and final state verification did not converge. $($_.Exception.Message) Resolve the reported Drill RBAC/readiness issue before retrying, or increase -OperationTimeoutSeconds if the service is still making progress."
            }
            throw
        }
    }
    $script:ClassificationSummary = @($classifications)
    New-StageResult DrillResources $(if ($unresolved.Count) { 'Partial' } else { 'Succeeded' }) $DrillResourceId Updated $started $null
}

function Test-ProviderRegistrations {
    [CmdletBinding(SupportsShouldProcess)] param([string[]]$SubscriptionIds)
    $providers = @('Microsoft.AzureResilienceManagement', 'Microsoft.Chaos', 'Microsoft.Insights', 'Microsoft.OperationalInsights', 'Microsoft.Automation')
    foreach ($subscription in $SubscriptionIds | Select-Object -Unique) {
        foreach ($namespace in $providers) {
            $path = "/subscriptions/$subscription/providers/$namespace"
            $state = (Get-ArmResource $path $script:ApiVersions.Provider).Body.registrationState
            if ($state -ine 'Registered') {
                if ($RegisterMissingProviders -and $PSCmdlet.ShouldProcess("$subscription/$namespace", 'Register resource provider')) {
                    $response = Invoke-ArmRequest POST "$path/register" $script:ApiVersions.Provider $null; Wait-ArmOperation $response.Headers | Out-Null
                }
                else { Write-Warning "Provider $namespace is '$state' in subscription $subscription. Register it before drill creation, or use -RegisterMissingProviders." }
            }
        }
    }
}

function Get-StageRange {
    [CmdletBinding()] param([string]$Start = 'ServiceGroup', [string]$Stop = 'DrillResources')
    $startIndex = [array]::IndexOf($script:StageOrder, $Start); $stopIndex = [array]::IndexOf($script:StageOrder, $Stop)
    if ($startIndex -gt $stopIndex) { throw "StartAtStage '$Start' occurs after StopAfterStage '$Stop'." }
    return @($script:StageOrder[$startIndex..$stopIndex])
}

function Assert-SkippedStagePrerequisites {
    [CmdletBinding(SupportsShouldProcess)]
    param($Config, [string]$ServiceGroupId, [string]$UsagePlanId, [string]$DrillId)
    $startIndex = [array]::IndexOf($script:StageOrder, $StartAtStage)
    if ($startIndex -le 0) { return }
    $priorStages = @($script:StageOrder[0..($startIndex - 1)])
    if ($CreateMissingPrerequisites) {
        foreach ($priorStage in $priorStages) {
            $result = switch ($priorStage) {
                ServiceGroup { Invoke-ServiceGroupStage $Config -WhatIf:$WhatIfPreference }
                Membership { Invoke-MembershipStage $Config $ServiceGroupId -WhatIf:$WhatIfPreference }
                UsagePlan { Invoke-UsagePlanStage $Config -WhatIf:$WhatIfPreference }
                Enrollment { Invoke-EnrollmentStage $Config $ServiceGroupId $UsagePlanId -WhatIf:$WhatIfPreference }
                GoalAssignment { Invoke-GoalAssignmentStage $Config $ServiceGroupId -WhatIf:$WhatIfPreference }
                Drill { Invoke-DrillStage $Config $ServiceGroupId -WhatIf:$WhatIfPreference }
            }
            $script:StageResults.Add($result)
        }
        return
    }
    Assert-Prerequisite (Test-ServiceGroupExists $ServiceGroupId) "Skipped Service Group '$ServiceGroupId' does not exist or did not become visible after $ResourcePropagationRetryCount propagation retries."
    if ($priorStages -contains 'Membership') {
        $resources = Get-ValidatedResources $Config
        Assert-Prerequisite ($resources.Invalid.Count -eq 0) 'One or more configured resources are invalid or inaccessible.'
        foreach ($resource in $resources.Valid) {
            $name = Get-StableRelationshipName $ServiceGroupId $resource.ResourceId
            $id = "$($resource.ResourceId)/providers/Microsoft.Relationships/serviceGroupMember/$name"
            $membership = Get-ArmResource $id $script:ApiVersions.Membership -AllowNotFound
            Assert-Prerequisite (-not $membership.NotFound) "Skipped membership '$id' does not exist."
            Assert-Prerequisite ([string]$membership.Body.properties.targetId -ieq $ServiceGroupId) "Skipped membership '$id' targets a different Service Group."
        }
    }
    if ($priorStages -contains 'UsagePlan') {
        $plan = Get-ArmResource $UsagePlanId $script:ApiVersions.UsagePlan -AllowNotFound
        Assert-Prerequisite (-not $plan.NotFound) "Skipped Usage Plan '$UsagePlanId' does not exist."
        Assert-Prerequisite ([string]$plan.Body.properties.planType -ieq 'Standard') "Skipped Usage Plan '$UsagePlanId' is not Standard."
    }
    if ($priorStages -contains 'Enrollment') {
        $enrollmentId = "$UsagePlanId/enrollments/$([uri]::EscapeDataString($Config.enrollment.name))"
        $enrollment = Get-ArmResource $enrollmentId $script:ApiVersions.Enrollment -AllowNotFound
        Assert-Prerequisite (-not $enrollment.NotFound) "Skipped Enrollment '$enrollmentId' does not exist."
        Assert-Prerequisite ([string]$enrollment.Body.properties.serviceGroupId -ieq $ServiceGroupId) "Skipped Enrollment '$enrollmentId' targets a different Service Group."
    }
    if ($priorStages -contains 'GoalAssignment') {
        $goalId = "$ServiceGroupId/providers/Microsoft.AzureResilienceManagement/goalAssignments/$([uri]::EscapeDataString($Config.goalAssignment.name))"
        $goal = Get-ArmResource $goalId $script:ApiVersions.GoalAssignment -AllowNotFound
        Assert-Prerequisite (-not $goal.NotFound) "Skipped Goal Assignment '$goalId' does not exist."
        Assert-Prerequisite ($goal.Body.properties.requireZonalResiliency -eq $true) "Skipped Goal Assignment '$goalId' is not zonal."
    }
    if ($priorStages -contains 'Drill') {
        $drill = Get-ArmResource $DrillId $script:ApiVersions.Drill -AllowNotFound
        Assert-Prerequisite (-not $drill.NotFound) "Skipped Drill '$DrillId' does not exist."
        Assert-Prerequisite ([string]$drill.Body.properties.drillType -ieq 'Zonal') "Skipped Drill '$DrillId' is not Zonal."
        Assert-Prerequisite ([string]$drill.Body.identity.type -match 'SystemAssigned') "Skipped Drill '$DrillId' does not use a system-assigned identity."
    }
}

function Write-DeploymentSummary {
    [CmdletBinding()] param([AllowNull()][string]$Path)
    Write-Information 'Infrastructure Resiliency Manager deployment summary:' -InformationAction Continue
    $script:StageResults | Format-Table Stage, Status, Outcome, ResourceId, DurationSeconds -AutoSize | Out-String | Write-Information -InformationAction Continue
    if ($script:ClassificationSummary) { $script:ClassificationSummary | Format-Table ResourceId, ResourceType, Status, FaultName, Reason -AutoSize | Out-String | Write-Information -InformationAction Continue }
    if ($Path) {
        $document = [ordered]@{ generatedAt = (Get-Date).ToUniversalTime().ToString('o'); stages = @($script:StageResults); memberships = $script:MembershipSummary; drillResources = $script:ClassificationSummary }
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
        Write-Information "JSON summary written to $Path" -InformationAction Continue
    }
}

function Invoke-IrmDeployment {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()
    Assert-Prerequisite (-not [string]::IsNullOrWhiteSpace($ParameterFile)) 'Specify -ParameterFile.'
    Assert-Prerequisite (Test-Path -LiteralPath $ParameterFile -PathType Leaf) "Parameter file '$ParameterFile' does not exist."
    $script:AzContext = Get-AzContext -ErrorAction SilentlyContinue
    Assert-Prerequisite ($null -ne $script:AzContext -and $null -ne $script:AzContext.Account) 'Authenticate with Connect-AzAccount first.'
    if ($TenantId -and [string]$script:AzContext.Tenant.Id -ine $TenantId) { throw "Active tenant '$($script:AzContext.Tenant.Id)' does not match requested tenant '$TenantId'." }
    $config = Get-Content -LiteralPath $ParameterFile -Raw | ConvertFrom-Json -Depth 100
    $serviceGroupId = "/providers/Microsoft.Management/serviceGroups/$($config.serviceGroup.id)"
    $usagePlanId = "/subscriptions/$($config.usagePlan.subscriptionId)/resourceGroups/$($config.usagePlan.resourceGroupName)/providers/Microsoft.AzureResilienceManagement/usagePlans/$($config.usagePlan.name)"
    $drillId = "$serviceGroupId/providers/Microsoft.AzureResilienceManagement/drills/$($config.drill.name)"
    Write-Warning 'This workflow uses preview Service Groups and Azure Resilience Management APIs.'
    Write-Information "Tenant: $($script:AzContext.Tenant.Id)" -InformationAction Continue
    Write-Information "Subscriptions: usage=$($config.usagePlan.subscriptionId), drill=$($config.drill.subscriptionId)" -InformationAction Continue
    Write-Information "Service Group: $serviceGroupId; Usage Plan: $usagePlanId; Drill: $($config.drill.name)" -InformationAction Continue
    Test-ProviderRegistrations @($config.usagePlan.subscriptionId, $config.drill.subscriptionId) -WhatIf:$WhatIfPreference
    $stages = Get-StageRange $StartAtStage $StopAfterStage
    Assert-SkippedStagePrerequisites $config $serviceGroupId $usagePlanId $drillId -WhatIf:$WhatIfPreference
    foreach ($stage in $stages) {
        Write-Information "Starting stage: $stage" -InformationAction Continue
        $result = switch ($stage) {
            ServiceGroup { Invoke-ServiceGroupStage $config -WhatIf:$WhatIfPreference }
            Membership { Invoke-MembershipStage $config $serviceGroupId -WhatIf:$WhatIfPreference }
            UsagePlan { Invoke-UsagePlanStage $config -WhatIf:$WhatIfPreference }
            Enrollment { Invoke-EnrollmentStage $config $serviceGroupId $usagePlanId -WhatIf:$WhatIfPreference }
            GoalAssignment { Invoke-GoalAssignmentStage $config $serviceGroupId -WhatIf:$WhatIfPreference }
            Drill { Invoke-DrillStage $config $serviceGroupId -WhatIf:$WhatIfPreference }
            DrillResources { Invoke-DrillResourcesStage $config $drillId -WhatIf:$WhatIfPreference }
        }
        $script:StageResults.Add($result)
        Write-Information "Completed stage: $stage ($($result.Outcome))" -InformationAction Continue
    }
    Write-DeploymentSummary -Path $OutputPath
    return [pscustomobject]@{ Stages = @($script:StageResults); Memberships = $script:MembershipSummary; DrillResources = $script:ClassificationSummary }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-IrmDeployment -WhatIf:$WhatIfPreference
}