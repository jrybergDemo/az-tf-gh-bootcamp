# Azure, Terraform, and GitHub
This repository contains a template exemplifying how to use Terraform to deploy Azure resources from GitHub Actions, authenticating with a Service Principal using [OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect) (federated credentials), and remotely storing the Terraform state using an Azure Storage Account as the backend.

___
&nbsp;

# Prerequisites
## Azure
- Azure Active Directory Tenant
- Active Subscription
- Service Principal with federated credential
  - Use the [bootstrap script](bootstrap-remote-backend.ps1) to create the Service Principal and [federated credential](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cwindows#create-an-azure-active-directory-application-and-service-principal)
  - **IMPORTANT**: The bootstrap script will also create the GitHub Environment and Secrets required, if you provide the appropriate GitHub variables (most importantly a GitHub Personal Access Token to authenticate the API calls). If you want to create the secrets on your own, make sure to copy down the Service Principal's Application ID from the output to save as a GitHub secret. If forgotten, simply rerun the bootstrap script again to output the Application ID.
- Resources to support Terraform remote backend
  - Use the [bootstrap script](bootstrap-remote-backend.ps1) to deploy the following resources:
    - Resource Group
    - Storage Account
    - Container
    - RBAC Role 'Storage Blob Data Contributor' assigned to the Service Principal on the Storage Account
    - RBAC Role 'Contributor' assigned to the Service Principal on the current Subscription

## GitHub
- A [GitHub Organization](https://docs.github.com/en/get-started/learning-about-github/githubs-products#github-free-for-organizations) is required to use Azure federated credentials with GitHub Actions
- A GitHub Repository
- A GitHub 'Environment' in the target repository that matches the name of the federated credential
- The following secrets created in the Environment:
    | Secret Name               | Value                            |
    | ------------------------- | -----------                      |
    | AZURE_TENANT_ID           | Service Principal Tenant ID      | 
    | AZURE_CLIENT_ID           | Service Principal Application ID | 
    | AZURE_SUBSCRIPTION_ID     | Target Azure Subscription ID     |


## Terraform
- OIDC support was added in version `3.7.0`, so that is the minimum version required
- The Terraform configuration used in this example will connect to the [remote backend using OIDC & AAD RBAC](https://www.terraform.io/language/settings/backends/azurerm)
- The Terraform configuration used in this example will connect to [Azure using OIDC for the AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_oidc)

___
&nbsp;

# Bootstrap Azure Requirements
- The [bootstrap script](bootstrap-remote-backend.ps1) will only need to be run once (it is idempotent and can be run many times as necessary)
- Requires the following PowerShell modules:
  - PSSodium - to create the GitHub secrets
    - Not required if manually creating the secrets
  - Az.Accounts
  - Az.Resources
  - Az.Storage
- Ensure to establish a connection to the appropriate Cloud environment and subscription
- Variables can be passed in as parameters or hardcoded in the script:

    | Variable Name             | Description |
    | ------------------------- | ----------- |
    | location                  | The target Azure region to deploy into |
    | tfbackend_rg_name         | The name for the Resource Group containing the Storage Account for the Terraform remote backend |
    | tfbackend_sa_name         | The name for the Storage Account containing the Terraform remote backend |
    | tfbackend_container_name  | The name for the Storage Account Container |
    | tf_sp_name                | The name for the Service Principal |
    | ghUsername                | The username to authenticate to the GitHub Organization |
    | ghPAT                     | The Personal Access Token used to authenticate to the GitHub Organization. Must include Repo & Org permissions |
    | ghOrgName                 | The name for the GitHub Organization |
    | ghRepoName                | The name for the GitHub Repository |
    | ghRepoEnvironmentName     | The name for the GitHub Repository Environment |
- Creates the following:
  - Service Principal with the `tf_sp_name` variable value
  - Federated credential for the Service Principal using the variables beginning with `gh`
  - Resource Group with the `tfbackend_rg_name` variable value
  - Storage Account with the `tfbackend_sa_name` variable value
  - Storage Account Container with the `tfbackend_container_name` variable value
  - Role Assignment on the subscription with Contributor assigned to the Service Principal
  - Role Assignment on the Storage Account with Storage Blob Data Contributor assigned to the Service Principal
  - GitHub Environment and required Secrets if a GitHub Personal Access Token is provided
    - Requires all `gh*` variables
    - If the ghPAT variable is not provided, the GitHub Environment and Secrets will not be created and will need to be created manually
- If any variable values from the bootstrap script are changed, the [Terraform backend configuration file](.tfbackend/dev-azure-bootcamp) needs to be updated with those changed values for the following resources:
  - Resource Group name
  - Storage Account name
  - Container name

___
&nbsp;

# Environments Overview
To follow DevOps best practices in maintaining seperate deployment boundaries, two environments are referenced in this template: DEV and TEST. In a real-world scenario, different Subscriptions with accompanying Service Principals would be assigned to each environment to keep the environments separate. To save on costs and complexity, this example actually uses the same subsciption. To reproduce a real-world scenario with separate boundaries, the bootstrap script would need to be run against the different subscriptions, with the resulting Service Principal Application ID and Subscription ID values added to each appropriate GitHub Environment Secrets.

The DEV environment is meant to represent the initial 'development' environment that developers/engineers can use to build out new configurations or prove out any desired change in code/configuration. The expectations for the DEV environment are that supporting infrastructure (Identity, Networking/Routing, etc) might or might not be up and running, so integration tests are not required.

The more formal TEST environment is expected to have supporting infrastructure or services available in order to fully test any changes using functional or integration test suites. The PROD environment is not covered in this template (but might be added in a later commit 🤷). Changes to PROD would be deployed through a formal release process, currently outside the scope of this template.

___
&nbsp;

# Workflow Overview
The workflow file ['dev-azure-bootcamp.yml'](.github/workflows/dev-azure-bootcamp.yml) is the mechanism that deploys the Azure resources to the DEV environment using the terraform configuration. Its trigger is set to `workflow_dispatch` (manual) and also any `pull_request` on the main (trunk) branch.

The workflow filename and assigned name are the same value and must match the filename of the [Terraform partial backend configuration](.tfbackend/dev-azure-bootcamp) and [TFVars filename](terraform/data/dev-azure-bootcamp.tfvars). This is because the workflow name, which is defined in the workflow's `name` attribute (on line 1), is stored as an environment variable ('github.workflow') in the [GitHub context](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context). That value is referenced to pull in the backend configuration for the `terraform init` execution and TFVars for the `terraform plan`. This allows us to maintain the same Terraform configuration and GitHub workflow structure across deployment environments. This is more easily seen with a graphic representation of the directory structure:

```text
/
├───.github
│   └───workflows
│           DEV-azure-bootcamp.yml      <-- DEV
│           test-azure-bootcamp.yml
│
├───.tfbackend
│       DEV-azure-bootcamp              <-- DEV
│       test-azure-bootcamp
│       
└───terraform
    │   main.tf
    │   providers.tf
    │   variables.tf
    │   
    └───data
            DEV-azure-bootcamp.tfvars   <-- DEV
            test-azure-bootcamp.tfvars
```

The DEV workflow is set to trigger on `pull_request` to the main (trunk) branch of the repository. The TEST workflow will trigger on the pull request being merged (pushed) to the main branch.

NOTE: The Terraform steps are performed separately to ensure that any errors are not swallowed by the shell.
___
&nbsp;

# Data Structures
A central tenant to good development is good data structure. In order to reduce maintenance, confusion, and to keep IaC code simple, the data for the configuration is stored in a single location, within a data directory inside the terraform directory. Another approach is to move all the required variables to the GitHub workflow file as environment variables starting with `TF_VAR_` and ending with the actual variable name. The values will be passed into all defined GitHub Actions steps and pulled in by Terraform during execution. The upside to this approach is that literally all required data for the execution of the workflow will be in one place: the workflow file. The downside to this approach is when attempting to run Terraform locally, the variable values will need to be populated in the console as environment variables, which can get messy.

NOTE: It is NEVER a good idea to create separate Terraform configurations based on environment. This eliminates the confidence that parallel configurations are being deployed to separate environments. Separate configurations increase code management, decrease confidence in resource deployment parity, and will only lead to frustration. The approach given in this template is meant to provide a scalable solution to deploying across multiple environments with the same configuration with only the variable values and/or counts changing.