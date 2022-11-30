# Authenticate to Azure Subscription
# Connect-AzAccount -Environment AzureCloud -Subscription <subscription_guid>
$location                 = 'westus2'
$tfbackend_rg_name        = 'bootcampterrastate'
$tfbackend_sa_name        = 'dangernoobsabootcamp'
$tfbackend_container_name = 'tfstate'
$tf_sp_name               = 'dev-az-bootcamp'
$ghUsername               = 'dangernoob'
$ghPAT                    = '' # Pass in your GitHub Personal Access Token with repo & org access premissions
$ghOrgName                = 'dangernooborg'
$ghRepoName               = 'az-tf-gh-bootcamp'
$ghRepoEnvironmentName    = 'Azure-Public-Dev'

$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id

####################### CREATE SERVICE PRINCIPAL AND FEDERATED CREDENTIAL #######################
if (-Not ($sp = Get-AzADServicePrincipal -DisplayName $tf_sp_name -ErrorAction 'SilentlyContinue'))
{
    $sp = New-AzADServicePrincipal -DisplayName $tf_sp_name -ErrorAction 'Stop'
}

$app = Get-AzADApplication -ApplicationId $sp.AppId

if (-Not (Get-AzADAppFederatedCredential -ApplicationObjectId $app.Id))
{
    $params = @{
        ApplicationObjectId = $app.Id
        Audience            = 'api://AzureADTokenExchange'
        Issuer              = 'https://token.actions.githubusercontent.com'
        Name                = "$tf_sp_name-bootcamp"
        Subject             = "repo:$ghOrgName/${ghRepoName}:environment:$ghRepoEnvironmentName"
    }
    $cred = New-AzADAppFederatedCredential @params
}

####################### CREATE BACKEND RESOURCES #######################
if (-Not (Get-AzResourceGroup -Name $tfbackend_rg_name -Location $location -ErrorAction 'SilentlyContinue'))
{
    New-AzResourceGroup -Name $tfbackend_rg_name -Location $location -ErrorAction 'Stop'
}

if (-Not ($sa = Get-AzStorageAccount -ResourceGroupName $tfbackend_rg_name -Name $tfbackend_sa_name -ErrorAction 'SilentlyContinue'))
{
    $sa = New-AzStorageAccount -ResourceGroupName $tfbackend_rg_name -Name $tfbackend_sa_name -Location $location -SkuName 'Standard_GRS' -AllowBlobPublicAccess $false -ErrorAction 'Stop'
}

if (-Not (Get-AzStorageContainer -Name $tfbackend_container_name -Context $sa.Context -ErrorAction 'SilentlyContinue'))
{
    $container = New-AzStorageContainer -Name $tfbackend_container_name -Context $sa.Context -ErrorAction 'Stop'
}

if (-Not (Get-AzRoleAssignment -ServicePrincipalName $sp.AppId -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName 'Contributor' -ErrorAction 'SilentlyContinue'))
{
    $subContributorRA = New-AzRoleAssignment -ApplicationId $sp.AppId -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName 'Contributor' -ErrorAction 'Stop'
}

if (-Not (Get-AzRoleAssignment -ServicePrincipalName $sp.AppId -Scope $sa.Id -RoleDefinitionName 'Storage Blob Data Contributor' -ErrorAction 'SilentlyContinue'))
{
    $saBlobContributorRA = New-AzRoleAssignment -ApplicationId $sp.AppId -Scope $sa.Id -RoleDefinitionName 'Storage Blob Data Contributor' -ErrorAction 'Stop'
}

####################### CREATE GitHub Environment & Secrets #######################
if (-Not [string]::IsNullOrEmpty($ghPAT))
{
    $headers = @{"Authorization"="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::Ascii.GetBytes("${ghUsername}:$ghPAT")))"}

    $environmentCreate = Invoke-WebRequest -Uri "https://api.github.com/repos/$ghOrgName/$ghRepoName/environments/$ghRepoEnvironmentName" -Method Put -Headers $headers
    if (-Not $environmentCreate.StatusCode -eq 200)
    {
        throw "Could not create environment '$ghRepoEnvironmentName'"
    }
    $repoId = (Invoke-WebRequest -Uri "https://api.github.com/repos/$ghOrgName/$ghRepoName" -Headers $headers | ConvertFrom-Json).Id
    $envPublicKeyObj = Invoke-WebRequest -Uri "https://api.github.com/repositories/$repoId/environments/$ghRepoEnvironmentName/secrets/public-key" -Headers $headers | ConvertFrom-Json
    $envPublicKey = $envPublicKeyObj.key
    $envPublicKeyId = $envPublicKeyObj.key_id

    $secrets = @{
        AZURE_CLIENT_ID       = $app.AppId
        AZURE_SUBSCRIPTION_ID = $subscriptionId
        AZURE_TENANT_ID       = $tenantId
    }

    $response = @()
    foreach ($secret in $secrets.GetEnumerator())
    {
        $encryptedValue = ConvertTo-SodiumEncryptedString -Text $secret.Value -PublicKey $envPublicKey
        $clientIdBody = @{
            encrypted_value = $encryptedValue
            key_id          = $envPublicKeyId
        } | ConvertTo-Json

        $response += Invoke-WebRequest -Uri "https://api.github.com/repositories/$repoId/environments/$ghRepoEnvironmentName/secrets/$($secret.Key)" -Method Put -Headers $headers -Body $clientIdBody
    }
}
else {
    Write-Host 'No PAT passed in - no GitHub secrets created.' -ForegroundColor 'Cyan'
}
Write-Host "Application/Client ID is: $($app.AppId)" -ForegroundColor 'Green'
