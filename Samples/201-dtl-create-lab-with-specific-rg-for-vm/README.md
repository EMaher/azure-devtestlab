# Create a new DevTestLab instance

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-devtestlab%2Fmaster%2FSamples%2F201-dtl-create-lab-with-specific-rg-for-vm%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>


This template creates a new DevTestLab instance that creates all new lab virtual machines in a specific resource group.

When deploying via PowerShell, if you use -DeploymentMode parameter, it is recommended to use the "Incremental" option. The "Complete" option will delete the target resource group first. If a lab or other resources are in that resource group, you could lose them or encounter errors.