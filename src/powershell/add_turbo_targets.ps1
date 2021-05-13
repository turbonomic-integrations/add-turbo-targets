<#
    .SYNOPSIS
    This script adds targets to Turbonomic in bulk from csv files for each target type

    .DESCRIPTION
    This script allows you to define the required fields in csv files to bulk add targets to Turbonomic.  Each 
    target type is it's own csv file since each target requires different fields.  

    .PARAMETER Turbo_Instance
    Hostname or IP address of the Turbonomic instance to add targets to.

    .PARAMETER Username
    Username used to add targets to Turbonomic instance.  Must had administrator priviledges.

    .PARAMETER Password
    Password for Username parameter.  
	  	
	  .PARAMETER csvFolder
    Optional parameter to specify the folder that contains the csv files.  Default is csvFiles.

    .PARAMETER updateTargets
    Optional parameter.  If specified and target already exists, it will be updated.  If target does not exist, it will be added

    .EXAMPLE
    ./add_turbo_targets.ps1 -Turbo_Instance 10.16.173.59 -Username administrator -Password administrator

    .Notes
    The targetmetadata-0.2.json file is also required and should be placed in the same directory as the script.
    Currently, this script only supports the following targets:
      -AWS (with or without IAM Role)
      -AWS Billing (with or without IAM Role)
      -Microsoft Enterprise Agreement
      -Azure Service Principle
      -vCenter
      -Hyper-V
      -SQL Server

#>

[CmdletBinding()]
param(
  [parameter(Mandatory, HelpMessage = 'Turbonomic Hostname')]
  [string] $Turbo_Instance,

  [parameter(Mandatory, HelpMessage = 'Turbonomic User to add targets (must be assigned administrator role)')]
  [string] $Username,

  [parameter(Mandatory, HelpMessage = 'Password for Turbonomic User')]
  [string] $Password,

  [parameter(HelpMessage = 'PSCredential for Turbonomic Instance')]
  [System.Management.Automation.PSCredential] $Credential,

  [parameter(HelpMessage = 'Folder with CSV files to import target from')]
  [string] $csvFolder = 'csvFiles',

  [parameter(DontShow)]
  [string] $jsonMap = 'targetmetadata-0.2.json',

  [parameter(HelpMessage = 'Will update target if it already exists')]
  [switch] $updateTargets

)
function Get-Auth {
    # Authentication function
    param(
      [string] $Username,
      [string] $Password,
      [System.Management.Automation.PSCredential] $Credential
    )
    if ($Credential) {
      $auth = @{
        username  = $Credential.Username
        password  = $Credential.GetNetworkCredential().password
      } 
    }
    elseif ($Username -and $Password) {
      $auth = @{
        username  = $Username
        password  = $Password
      }
    }
    else {
      $creds = Get-Credential -Message "Please provide credentials for Turbonomic:"
      
      $auth = @{
        username  = $creds.Username
        password  = $creds.GetNetworkCredential().password
      } 
    }
    $auth
}
function Invoke-TurboRequest {
    # General REST API call function
    param (
        [string] $Method = 'Get',
        [bool] $ssl = 1,
        [string] $Server,
        [string] $BaseUrl = '/api/v3',
        [AllowNull()][string] $ContentType,
        [string] $Url,
        [hashtable] $Form,
        [AllowNull()][string] $Body,
        [AllowNull()][Microsoft.PowerShell.Commands.WebRequestSession] $Session = $Script:vmtSession,
        [hashtable] $q,
        [string] $disable_hateoas = 'true',
        [string] $Limit,
        [string] $Cursor,
        [scriptblock] $functionModifier
        
        
    )
    function Set-RequestArgs {
      # Function to set arguments
  
      if ( $disable_hateoas -eq 'true' ) { $Query = "disable_hateoas=true" }
      elseif ($disable_hateoas -eq 'false') { $Query = "disable_hateoas=false" }
  
      if ($Limit) {
          if ( -Not($Query )) { $Query = "limit=$Limit" }
          else { $Query += "&limit=$Limit" }
          
      }
  
      if ($Cursor) {
          if ( -Not($Query )) {$Query = "cursor=$Cursor" }
          else { $Query += "&cursor=$Cursor" }
      }
  
      if ( $q ) {
          $qq = ''
          foreach ($key in $q.Keys) {
            if ( $qq ) {
            $qq += "&${key}=$($q.Item($key))" 
            }
            else {$qq += "${key}=$($q.Item($key))" }
          }
          if ( -Not($Query )) { $Query = "$qq" }
          else { $Query += "&$qq" }
      }
  
      if ($Query) {$uri = "https://{0}{1}/{2}?{3}" -f $Server, $BaseUrl, $Url, $Query}
      else {$uri = "https://{0}{1}/{2}" -f $Server, $BaseUrl, $Url}
  
      $requestArgs = @{
          Method = $Method
          Uri = $uri
      }
  
      if (![string]::IsNullOrEmpty($ContentType))
      { $requestArgs.Add('ContentType', $ContentType)}

      if (![string]::IsNullOrEmpty($Session))
      { $requestArgs.Add('WebSession', $Session) }
      else
      { $requestArgs.Add('SessionVariable', 'Session') }

      if (![string]::IsNullOrEmpty($Form))
      {
          # for backwards compatibility with PS 5.1
          foreach ($key in $Form.Keys)
          {
              if ($Body.Length -gt 0)
              { $Body += "&" }
              $Body += "$key=$($Form[$key])"
          }
      }
      if (![string]::IsNullOrEmpty($Body))
      { $requestArgs.Add('Body', $Body) }
      
      return $requestArgs
    }
  
    $requestArgs = Set-RequestArgs @PSBoundParameters
    # Write-Host @requestArgs

    if ($ssl -eq 0) { $apiCall = {Invoke-WebRequest @requestArgs -SkipCertificateCheck}}
    else { $apiCall = {Invoke-WebRequest @requestArgs}}

    try {
      $response = &$apiCall
    }
    catch {
      return @(($_.ErrorDetails.Message), $_.Exception.Response.Headers, ($_.Exception.Response.StatusCode.value__))
    }
    $content = ConvertFrom-Json $([String]::new($response.Content))
    $Headers = $response.Headers
    if ($functionModifier) {
        $output += &{ &$functionModifier $content }
    }
    else {$output = $content}
    $totalPages = $Headers.'X-Total-Record-Count'
    while ($Headers.'X-Next-Cursor') {
        $Cursor = $Headers.'X-Next-Cursor'
        $requestArgs = Set-RequestArgs @PSBoundParameters
        $response = &$apiCall
        $content = ConvertFrom-Json $([String]::new($response.Content))
        $Headers = $response.Headers
        if ($functionModifier) {
            $output += &{ &$functionModifier $content }
        }
        else {$output += $content}
        if ($Headers.'X-Total-Record-Count' -ne $totalPages) {throw 'Cursor Exception'}
    }
    return @($output, $Headers, $response.StatusCode)
}
function Get-ScopeUUID {
  param([Parameter()]
        [string] $scopeName)

  $response = Invoke-TurboRequest -Method 'GET' -Server $Turbo_Instance -ContentType 'application/json' `
    -Url 'search' -Session $vmtSession -ssl $ps_version -q @{"types"="Group";"q"=$scopeName}

  if ($response[0].count -eq 1) { return $response[0].uuid}
  elseif ($response[0].count -eq 0) { return 0 }
  else { return -1 }
  
}
function Get-TargetUUID {
  param([Parameter(Mandatory)]
        [PSCustomObject] $line,

        [Parameter(Mandatory)]
        [PSNoteProperty] $item,
        
        [Parameter(Mandatory)]
        [Object] $currentTargets)

  foreach ($target in $currentTargets[0]) {

    if ($target.displayName -eq $line.($item.value.CSV_TAG)) {
      if (!([string]::IsNullOrEmpty($target.uuid))) {return $target.uuid}
      else {return $null}
    }
  }
  return $null
}
function Set-Scope {
  param([Parameter(Mandatory)]
        [PSCustomObject] $line,

        [Parameter(Mandatory)]
        [PSNoteProperty] $item)


  $grpUUID = Get-ScopeUUID -scopeName $line.($item.value.CSV_TAG)
  if ($grpUUID -lt 1) {
    Write-Host -ForegroundColor "RED" "Scope Name $($line.($item.value.CSV_TAG)) does not exist or is not unique for target $($line.($objMap.PSObject.properties['targetId'].value.CSV_TAG))"
    return $null
  }
  # Required to create array of array for groupProperties 
  $scopeArray = New-Object System.Collections.ArrayList
  [void]$scopeArray.Add(@($grpUUID))

  # $DTO.inputFields += @{"name" = $item.Name; "value" = $grpUUID; `
  #  "defaultValue" = $line.($item.value.CSV_TAG); "groupProperties" = @($scopeArray) }
  return @{"name" = $item.Name; "value" = $grpUUID; `
  "defaultValue" = $line.($item.value.CSV_TAG); "groupProperties" = @($scopeArray) }
  # return $DTO
}
function Set-BooleanValue {

  param([Parameter(Mandatory)]
        [PSCustomObject] $line,

        [Parameter(Mandatory)]
        [PSNoteProperty] $item)

  if ($line.($item.value.CSV_TAG) -iin ("yes", "true")) {
    return $true
  }
  elseif ($line.($item.value.CSV_TAG) -iin ("no", "false")) {
    return $false
  }
  else {return $null}
  # return $DTO
}
function New-Target{
  param([Parameter()]
        [string] $targetUUID,
        
        [Parameter(Mandatory)]
        [hashtable] $targetDTO)

  
  if (($updateTargets) -and ($targetUUID)) {
    $createTargetResp = Invoke-TurboRequest -Method 'PUT' -Server $Turbo_Instance -ContentType 'application/json;charset=UTF-8' `
     -Url "targets/$targetUUID" -Session $vmtSession -ssl $ps_version -Body ($targetDTO |ConvertTo-Json -Depth 10)
     Start-Job -ScriptBlock {Invoke-TurboRequest -Method 'POST' -Server $Turbo_Instance -ContentType 'application/json;charset=UTF-8' `
     -Url "targets/$targetUUID" -q @{"rediscover"="false"; "validate"="true"} -Session $vmtSession -ssl $ps_version -Body "{}" } | Out-Null
  }
  else {
    $createTargetResp = Invoke-TurboRequest -Method 'POST' -Server $Turbo_Instance -ContentType 'application/json;charset=UTF-8' `
     -Url 'targets' -Session $vmtSession -ssl $ps_version -Body ($targetDTO |ConvertTo-Json -Depth 10)
  }
  
  if ($createTargetResp[2] -eq 200) {
    if (!($targetUUID)) {Write-Host "Created Target $($createTargetResp[0].displayName)"}
    else {Write-Host "Updated Target $($createTargetResp[0].displayName)"}
  }
  elseif ($createTargetResp[0] -Match "already exists") {
    $extractName = '(?<=400com.vmturbo.api.exceptions.OperationFailedException: Target )\S*'
    $name = [regex]::matches($createTargetResp[0], $extractName)
    Write-Host -ForegroundColor "RED" "Target Name $name Already Exists"
    Write-Host $createTargetResp[0]
    # write-host ($targetDTO |ConvertTo-Json -Depth 10)
  }
  else {
    Write-Host "Unexpected Error:"
    Write-Host $createTargetResp[0]
  }
}
function Set-Target {
  param([Parameter(Mandatory)]
        [PSCustomObject] $objMap,

        [Parameter(Mandatory)]
        [PSCustomObject] $csvObj)

  
  $currentTargets = Invoke-TurboRequest -Method 'GET' -Server $Turbo_Instance -ContentType 'application/json;charset=UTF-8' `
  -Url 'targets' -Session $vmtSession -ssl $ps_version 

  :outer foreach ($line in $csvObj) {
    $targetDTO = @{
      "category" = ""
      "type" = ""
      "inputFields" = New-Object System.Collections.ArrayList
      "uuid" = $null
    }
    $targetUUID = $null
    :inner foreach ($item in $objMap.PSObject.properties) { 
      
    
      # if (($item.value.REQUIRED -eq $true) -and (!($line.($item.value.CSV_TAG))) ) {
      #   Write-Host -ForegroundColor "RED" "Missing Requred Field $($item.value.CSV_TAG) to add target $($line.($objMap.PSObject.properties['targetId'].value.CSV_TAG))"
      #   continue outer
      # }
      if (($item.value.REQUIRED -eq $true) -and (!($line.($item.value.CSV_TAG)))) {
        if ((!($updateTargets)) -or ($updateTargets -and $item.Name -ne "targetEntities")) {
          Write-Host -ForegroundColor "RED" "Missing Requred Field $($item.value.CSV_TAG) to add target $($line.($objMap.PSObject.properties['targetId'].value.CSV_TAG))"
          continue outer
        }
      }
      if ($item.Name -eq "category"){$targetDTO.category = $item.value}
      elseif ($item.Name -eq "type") {$targetDTO.type = $item.value}
      elseif ($item.value.type -eq "target") {

        $targetUUID = Get-TargetUUID -line $line -item $item -currentTargets $currentTargets
        if ($null -ne $targetUUID) {
          if (!($updateTargets)) {
            Write-Host -ForegroundColor "RED" "$($line.($item.value.CSV_TAG)) already exists, skipping"
            continue outer
          }
          else {
            $targetDTO.uuid = $targetUUID
            $targetDTO.inputFields += @{"name" = $item.Name; "value" = $line.($item.value.CSV_TAG)}
          }
        }
        else {$targetDTO.inputFields += @{"name" = $item.Name; "value" = $line.($item.value.CSV_TAG)}}
      }
      elseif ($item.value.type -eq "scope") {
        
        if ($targetUUID) {continue inner}

        $targetDTO.inputFields += Set-Scope -line $line -item $item

        if ($null -eq $targetDTO.inputFields) {continue outer}
      }
      elseif ($item.value.type -eq "boolean") {
        if ($line.($item.value.CSV_TAG)) {

          $boolValue = Set-BooleanValue -line $line -item $item
          $targetDTO.inputFields += @{"name" = $item.Name; "value" = $boolValue}
        }
        else {$targetDTO.inputFields += @{"name" = $item.Name; "value" = $item.value.DEFAULT}}
      }
      elseif ($item.value.type -eq "port") {
        if ($line.($item.value.CSV_TAG)) {
          $targetDTO.inputFields += @{"name" = $item.Name; "value" = [int]$line.($item.value.CSV_TAG)}
        }
        else {$targetDTO.inputFields += @{"name" = $item.Name; "value" = $item.value.DEFAULT}}
        
      } 

      else {
        $targetDTO.inputFields += @{"name" = $item.Name; "value" = $line.($item.value.CSV_TAG)}
      }
    }
    # Write-Host ($targetDTO |ConvertTo-Json -Depth 10) 
    New-Target -targetUUID $targetUUID -targetDTO $targetDTO
  }
}



if (Test-Path $jsonMap -PathType Leaf) {
    $csvMap = Get-Content -Raw -Path $jsonMap | ConvertFrom-Json
}
else { 
    throw "JSON Mapping File not found"
}

# Support for PS < 6
if ($PSVersionTable.PSVersion.Major -lt 6)
{ 
  [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $ps_version = 1
}
else { $ps_version = 0}
# Pass parameters for authentication or prompt for it
$auth = Get-Auth -Username $Username -Password $Password 

# Web Session object
$script:vmtSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# Make authentication call to Turbonomic
$auth_resp = Invoke-TurboRequest -Method 'POST' -Server $Turbo_Instance `
 -ContentType 'application/x-www-form-urlencoded' -Url 'login' -Form $auth -ssl $ps_version

if (Test-Path $csvFolder -PathType Container) {
  $csvFiles = Get-ChildItem $csvFolder
  foreach ($file in $csvFiles) {
    # Write-Host 'Creating {0} target(s) from {1}' -f $csvObj[0].psobject.properties.value[0], $file.FullName
    
    if ($file.Extension -eq ".csv") {

      $csvObj = Import-Csv $file.FullName
      Write-Host "*** Creating/Updating $($csvObj[0].psobject.properties.value[0]) target(s) from $($file.BaseName) ***" 
      $objMap = $csvMap.MAP.($csvObj[0].psobject.properties.value[0])

      # $createTargets = "Set-$($csvObj[0].psobject.properties.value[0])"
      # &$createTargets -objMap $objMap -csvObj $csvObj
      $createTargets = Set-Target -objMap $objMap -csvObj $csvObj

    }
  } 
}
else {
  throw "Folder does not exist"
}
