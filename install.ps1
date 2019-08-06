<#
.SYNOPSIS
  Infrastructure as Code Component
.DESCRIPTION
  Install a Time Series Instance Solution
.EXAMPLE
  .\install.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 6.2.1
#Requires -Module @{ModuleName='Az'; ModuleVersion='2.2.0'}

Param(
  [string]$Subscription = $env:ARM_SUBSCRIPTION_ID,
  [string]$Initials = $env:PROJECT_CONTACT,
  [string]$ResourceGroupName,
  [string]$Location = $env:AZURE_LOCATION,
  [string]$ServicePrincipalAppId = $env:AZURE_USER_ID,
  [boolean]$Deploy = $false
)

. ./.env.ps1
Get-ChildItem Env:ARM*
Get-ChildItem Env:AZURE*
Get-ChildItem Env:PROJECT*

if ( !$Initials) { $Initials = "cat" }
if ( !$ResourceGroupName) { $ResourceGroupName = "$Initials-iot-loriot" }


###############################
## FUNCTIONS                 ##
###############################
function Write-Color([String[]]$Text, [ConsoleColor[]]$Color = "White", [int]$StartTab = 0, [int] $LinesBefore = 0, [int] $LinesAfter = 0, [string] $LogFile = "", $TimeFormat = "yyyy-MM-dd HH:mm:ss") {
  # version 0.2
  # - added logging to file
  # version 0.1
  # - first draft
  #
  # Notes:
  # - TimeFormat https://msdn.microsoft.com/en-us/library/8kb3ddd4.aspx

  $DefaultColor = $Color[0]
  if ($LinesBefore -ne 0) {  for ($i = 0; $i -lt $LinesBefore; $i++) { Write-Host "`n" -NoNewline } } # Add empty line before
  if ($StartTab -ne 0) {  for ($i = 0; $i -lt $StartTab; $i++) { Write-Host "`t" -NoNewLine } }  # Add TABS before text
  if ($Color.Count -ge $Text.Count) {
    for ($i = 0; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine }
  }
  else {
    for ($i = 0; $i -lt $Color.Length ; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine }
    for ($i = $Color.Length; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $DefaultColor -NoNewLine }
  }
  Write-Host
  if ($LinesAfter -ne 0) {  for ($i = 0; $i -lt $LinesAfter; $i++) { Write-Host "`n" } }  # Add empty line after
  if ($LogFile -ne "") {
    $TextToFile = ""
    for ($i = 0; $i -lt $Text.Length; $i++) {
      $TextToFile += $Text[$i]
    }
    Write-Output "[$([datetime]::Now.ToString($TimeFormat))]$TextToFile" | Out-File $LogFile -Encoding unicode -Append
  }
}

function Get-ScriptDirectory {
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

function LoginAzure() {
  Write-Color -Text "Logging in and setting subscription..." -Color Green
  if ([string]::IsNullOrEmpty($(Get-AzContext).Account.Id)) {
    if($env:ARM_CLIENT_ID) {

      $securePwd = $env:ARM_CLIENT_SECRET | ConvertTo-SecureString
      $pscredential = New-Object System.Management.Automation.PSCredential -ArgumentList $env:ARM_CLIENT_ID, $securePwd
      Connect-AzAccount -ServicePrincipal -Credential $pscredential -TenantId $tenantId

      Login-AzAccount -TenantId $env:AZURE_TENANT
    } else {
      Connect-AzAccount
    }
  }
  Set-AzContext -SubscriptionId $env:ARM_SUBSCRIPTION_ID | Out-null

}

function CreateResourceGroup([string]$ResourceGroupName, [string]$Location) {
  # Required Argument $1 = RESOURCE_GROUP
  # Required Argument $2 = LOCATION

  $group = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
  if($group) {
    Write-Color -Text "Resource Group ", "$ResourceGroupName ", "already exists." -Color Green, Red, Green
  } else {
    Write-Host "Creating Resource Group $ResourceGroupName..." -ForegroundColor Yellow

    $UNIQUE = Get-Random -Minimum 100 -Maximum 9999
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{ RANDOM=$UNIQUE; contact=$Initials }
  }
}

function ResourceProvider([string]$ProviderNamespace) {
  # Required Argument $1 = RESOURCE

  $result = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace | Where-Object -Property RegistrationState -eq "Registered"

  if ($result) {
    Write-Color -Text "Provider ", "$ProviderNamespace ", "already registered." -Color Green, Red, Green
  }
  else {
    Write-Host "Registering Provider $ProviderNamespace..." -ForegroundColor Yellow
    Register-AzResourceProvider -ProviderNamespace $ProviderNamespace
  }
}

function UserId() {
  if ($ServicePrincipalAppId) {
    $ID = $servicePrincipalAppId
  }
  else {
    $ACCOUNT = $(Get-AzContext).Account
    if ($ACCOUNT.Type -eq 'User' -or $ACCOUNT.Type -eq 'ManagedService') {
      $UPN = $(Get-AzContext).Account.Id
      $USER = Get-AzureADUser -Filter "userPrincipalName eq '$UPN'"
      $ID = $USER.ObjectId
    }
    else {
      $ID = Read-Host 'Input your Service Principal.'
    }
  }
  Write-Color -Text "User Object Id: ", "$ID ", "detected" -Color Green, Red, Green
  return $ID
}


###############################
## Environment               ##
###############################



if ( !$Subscription) { throw "Subscription Required" }
if ( !$Location) { throw "Location Required" }

###############################
## Azure Initialize          ##
###############################
$BASE_DIR = Get-ScriptDirectory
$DEPLOYMENT = Split-Path $BASE_DIR -Leaf
LoginAzure

$UNIQUE = CreateResourceGroup $ResourceGroupName $Location

if ($Deploy -eq $false) {
    ResourceProvider Microsoft.Sql
    ResourceProvider Microsoft.DocumentDB
    ResourceProvider Microsoft.ServiceBus
    ResourceProvider Microsoft.Storage
    ResourceProvider Microsoft.Devices
    ResourceProvider Microsoft.EventHub
    ResourceProvider Microsoft.TimeSeriesInsights
    ResourceProvider Microsoft.Web

    Write-Host "---------------------------------------------" -ForegroundColor "blue"
    Write-Host "Environment Loaded!!!!!" -ForegroundColor "red"
    Write-Host "---------------------------------------------" -ForegroundColor "blue"
    exit
  }

##############################
## Deploy Template          ##
##############################
Write-Color -Text "`r`n---------------------------------------------------- "-Color Yellow
Write-Color -Text "Deploying ", "$DEPLOYMENT ", "template..." -Color Green, Red, Green
Write-Color -Text "---------------------------------------------------- "-Color Yellow
New-AzResourceGroupDeployment -Name $DEPLOYMENT `
  -TemplateFile $BASE_DIR\azuredeploy.json `
  -TemplateParameterFile $BASE_DIR\azuredeploy.parameters.json `
  -initials $INITIALS `
  -random $(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Tags.RANDOM `
  -ResourceGroupName $ResourceGroupName