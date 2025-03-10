param environmentType string
param linuxAdminUsername string
//@secure()
param sshRSAPublicKey string
param  cloudInitScriptUri string
param dnsLabelPrefix string
param location string

@description('The name of the Virtual Machine.')
param vmName string 

@description('Size of virtual machine.')
param vmSize string

@minLength(3)
@maxLength(63)
@description('Name of file share.  Must be between 3 and 63 characters long.')
param fileShareName string

@allowed([
  'SMB'
  'NFS'
])
@description('Fileshare type.  Must be SMB or NFS.')
param fileShareType string

@description('Name of network security group')
var nsgName = 'onprem-nsg'

@description('Name of virtual network')
param vnetName string = 'onprem-vnet'

@description('Name of subnet')
var subnetName = 'onprem-snet'

@description('List of service endpoints to be enabled on subnet' )
param serviceEndpoints array = [
  {
    service: 'Microsoft.Storage'
  }
]

param tags object

@description('Storage account prefix')
param storageAccountNamePrefix string

@description('Address space of virtual network')
param vnetAddressPrefix string = '10.1.0.0/16'

@description('Address space of subnet prefix')
param subnetAddressPrefix string = '10.1.0.0/24'

@description('Name of public IP resource')
var publicIPAddressName = '${vmName}-public-ip'

@description('Name of virtual NIC')
var networkInterfaceName = '${vmName}-nic'
var subnetRef = '${vnet.id}/subnets/${subnetName}'
var osDiskType = 'Standard_LRS'

@description('Disable password login and configure SSH')
var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${linuxAdminUsername}/.ssh/authorized_keys'
        keyData: sshRSAPublicKey
      }
    ]
  }
}

var storageAccountSkuName = (environmentType == 'prod') ? 'Premium_ZRS' : 'Premium_LRS'
var resourceNameSuffix  = uniqueString(resourceGroup().id)
var storageAccountName = '${storageAccountNamePrefix}${resourceNameSuffix}'
var nfs =  (fileShareType == 'NFS') ? true : false
var domainNameLabel = '${dnsLabelPrefix}-${resourceNameSuffix}'

// Config data needed for dymanically created cloud-init config file.
@description('Name of managed identity used when creating cloud-init.yaml dynmically')
var identityName = 'boot'
var customRoleName = 'cloudinit-sp-${resourceNameSuffix}'

@description('Generate resource ID of managed identity since .id property appears to be unsupported')
var miId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', identityName)

var rancherDockerInstallUrl = 'https://releases.rancher.com/install-docker/18.09.sh'
var argocdInstallUrl = 'https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64'
var helmTarBall = 'helm-v3.7.1-linux-amd64.tar.gz'
var argocdVersion = '3.26.12'
var argocdNamespace = 'argocd'
var argocdReleaseName = 'argocd-demo'

// Create virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Create subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' =  {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    serviceEndpoints: serviceEndpoints
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Create empty network security group
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: nsgName
  location: location
  tags: tags
}

// Allow SSH connections from anywhere
resource sshRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'SSH'
  parent: nsg
  properties : {
    protocol: 'Tcp' 
    sourcePortRange:  '*'
    destinationPortRange:  '22'
    sourceAddressPrefix:  '*'
    destinationAddressPrefix: '*'
    access:  'Allow'
    priority: 100
    direction: 'Inbound'
    sourcePortRanges: []
    destinationPortRanges: []
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Allow HTTP connections from anywhere
resource httpRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'HTTP'
  parent: nsg
  properties: {
    protocol:  'Tcp'
    sourcePortRange:  '*'
    destinationPortRange:  '80'
    sourceAddressPrefix:  '*'
    destinationAddressPrefix:  '*'
    access:  'Allow'
    priority: 110
    direction:  'Inbound'
    sourcePortRanges: []
    destinationPortRanges: []
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Allow HTTPS connections from anywhere
resource httpsRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'HTTPS'
  parent: nsg
  properties: {
    protocol:  'Tcp'
    sourcePortRange:  '*'
    destinationPortRange:  '443'
    sourceAddressPrefix:  '*'
    destinationAddressPrefix:  '*'
    access:  'Allow'
    priority: 120
    direction:  'Inbound'
    sourcePortRanges: []
    destinationPortRanges: []
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Allow kube API connections from anywhere
resource k8sRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'K8S'
  parent: nsg
  properties: {
    protocol:  'Tcp'
    sourcePortRange:  '*'
    destinationPortRange:  '6443'
    sourceAddressPrefix:  '*'
    destinationAddressPrefix:  '*'
    access:  'Allow'
    priority: 130
    direction:  'Inbound'
    sourcePortRanges: []
    destinationPortRanges: []
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Create Public IP
resource publicIP 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: publicIPAddressName
  location: location
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: domainNameLabel
    }
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Basic'
  }
}

// Create virtual network interface card
resource nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: networkInterfaceName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Create virtual machine
resource vm 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: linuxAdminUsername
      //adminPassword: adminPasswordOrKey
      linuxConfiguration: linuxConfiguration
      customData: generateCloudInitDeploymentScript.properties.outputs.cloudInitFileAsBase64
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
}

// Create storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'FileStorage'
  properties: {
    accessTier: 'Hot'
    networkAcls: nfs ? {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: subnet.id
        }
      ]
    } : null
    supportsHttpsTrafficOnly: nfs ? false : true
  }
}

// Create file service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

// Create file share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    accessTier: 'Premium'
    shareQuota: 128
    enabledProtocols: nfs ? 'NFS' : 'SMB'
    rootSquash: nfs ? 'NoRootSquash' : null
  }
}

// Create user managed identity (to be used by custom deployment script)
resource mi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

resource deploymentScriptCustomRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' = {
  name: guid(customRoleName, resourceGroup().id)
  properties: {
    roleName: customRoleName
    description: 'Configure least privilege for the deployment principal in deployment script'
    permissions: [
      {
        actions: [
          'Microsoft.Storage/storageAccounts/*'
          'Microsoft.ContainerInstance/containerGroups/*'
          'Microsoft.Resources/deployments/*'
          'Microsoft.Resources/deploymentScripts/*'
          'Microsoft.Storage/register/action'
          'Microsoft.ContainerInstance/register/action'
        ]
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }    
}

resource miCustomRoleAssign 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(customRoleName, identityName, resourceGroup().id)
  properties: {
      roleDefinitionId: deploymentScriptCustomRole.id
      principalId: mi.properties.principalId
      principalType: 'ServicePrincipal'
  }
}

resource generateCloudInitDeploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'createCloudInit'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${miId}': {}
    }
  }
  properties: {
    azCliVersion: '2.24.0'
    environmentVariables: [
      {
        name: 'RANCHER_DOCKER_INSTALL_URL'
        value: rancherDockerInstallUrl
      }
      {
        name: 'ARGOCD_INSTALL_URL'
        value: argocdInstallUrl
      }
      {
        name: 'LINUX_ADMIN_USERNAME'
        value: linuxAdminUsername
      }
      {
        name: 'HELM_TAR_BALL'
        value: helmTarBall
      }
      {
        name: 'ARGOCD_VERSION'
        value: argocdVersion
      }
      {
        name: 'ARGOCD_NAMESPACE'
        value: argocdNamespace
      }
      {
        name: 'ARGOCD_RELEASE_NAME'
        value: argocdReleaseName
      }
      {
        name: 'HOST_IP_ADDRESS_OR_FQDN'
        value: publicIP.properties.dnsSettings.fqdn
      }
    ]
    storageAccountSettings: {
      storageAccountName: storageAccountName
      storageAccountKey: listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2021-04-01').keys[0].value
    }
    primaryScriptUri: cloudInitScriptUri
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

output cloudInitFileAsBase64 string = generateCloudInitDeploymentScript.properties.outputs.cloudInitFileAsBase64
output fqdn string = publicIP.properties.dnsSettings.fqdn
output miId string = miId
