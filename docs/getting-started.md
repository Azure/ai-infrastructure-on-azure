# Getting Started

This section provides the essential setup steps to prepare for using Azure's AI Supercomputing infrastructure. It covers subscription readiness, quota configuration, access roles, and optional onboarding for advanced features like Guest Health Reporting (GHR).

## 1. Subscription Preparation

Before deploying GPU clusters, ensure the following:

- You have access to an Azure subscription in the correct region.
- Sufficient quota for the target VM SKU (NDv4 or NDv5) is available.
- Required resource providers are registered:
    - Microsoft.Network

Use the Azure CLI to validate and request quota increases if needed.

## 2. Role Assignments and Access Control

Assign the following roles to the appropriate identities in your Azure subscription:

- **Contributor** or **Owner**: to deploy infrastructure and manage resources.
- **Impact Reporter**: for GHR operations (if enabled).
- **Reader**: for monitoring and telemetry dashboards.

Ensure your automation identities (e.g., Terraform, Bicep, AzHPC) have adequate permissions.

## 3. Register for Guest Health Reporting (Optional)

Guest Health Reporting (GHR) enables qualified customers to notify Azure about faulty hardware nodes.

To register:

1. Go to your Azure subscription.
2. In **Resource Providers**, register `Microsoft.Impact`.
3. In **Preview Features**, register `Allow Impact Reporting`.
4. Under **Access Control (IAM)**, assign the **Impact Reporter** role to the app or user that will report issues.
5. Fill out the [Onboarding Questionnaire](https://forms.office.com/Pages/DesignPageV2.aspx?origin=NeoPortalPage&subpage=design&id=v4j5cvGGr0GRqy180BHbR5TDsw2DhHZCkjVm4E5h1NNUNTZQMkRRWUw4S1ZOTUM1UlJIQkhXQ0czSi4u&analysis=false&topview=Preview).

See the [Guest Health Reporting section](ghr.md) for usage details.

## 4. Next Steps

Once your subscription is ready and roles assigned, proceed to the [Deployment Guide](deployment.md) to launch your supercomputing cluster.