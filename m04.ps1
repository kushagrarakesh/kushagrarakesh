# First, we need a Key Vault
$KVName="AKSKeyVault"+(Get-Random -Minimum 100000000 -Maximum 99999999999)
$RG = "myResourceGroup"
$Region = "eastus"
az keyvault create --name $KVName --resource-group $RG --location $Region

# Let's save a secret
az keyvault secret set --vault-name $KVName --name "sapassword" --value "citadel@123"
az keyvault secret show --name "sapassword" --vault-name $KVName --query "value"

# New Namespace
kubectl create namespace keyvault
kubectl config set-context --current --namespace keyvault

# Install CSI Driver including auto rotation
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
helm repo update
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --set enableSecretRotation=True


kubectl get pods

# And the CSI Azure Provider
kubectl apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml

kubectl get pods

# To access our secrets and keys, we need a Secret Provider Class
code secret-provide-class-dist.yaml 

# We can automate modifying all  settings in YAML through PowerShell
$SPC = Get-Content "C:\AKS with AKV\04\demos\m04\m04.ps1\secret-provide-class-dist.yaml" | ConvertFrom-YAML
$SPC.spec.parameters.keyvaultName=$KVName
$SPC.spec.parameters.resourceGroup=$RG
$SPC.spec.parameters.subscriptionId=$Sub
$SPC.spec.parameters.tenantId=(az account show --query tenantId -o tsv)
$SPC=ConvertTo-YAML $SPC
Set-Content "secret-provide-class.yaml" -Value $SPC

# The order has changed - but that doesn't matter!
code --diff secret-provide-class.yaml secret-provide-class-dist.yaml 

# Create the class
kubectl apply -f secret-provide-class.yaml 

# Auth can happen through SP, VM (System/User) or Pod Identity
# We use a Service Principal
$SP="http://AKVAKSSP"
$SP_Key=$(az ad sp create-for-rbac --skip-assignment --name $SP --query password -o tsv)
$SP_ClientID=$(az ad sp show --id $SP --query appId -o tsv)

# Role Assignment for AKV
az role assignment create --role Reader --assignee $SP_ClientID `
        --scope /subscriptions/$Sub/resourcegroups/$RG/providers/Microsoft.KeyVault/vaults/$KVName

# Set permissions to read secrets
az keyvault set-policy -n $KVName --secret-permissions get --spn $SP_ClientID

# Let's add Key and Cert permissions, too
az keyvault set-policy -n $KVName --key-permissions get --spn $SP_ClientID
az keyvault set-policy -n $KVName --certificate-permissions get --spn $SP_ClientID

# The SP needs it's credentials stored in (one single) secret (other auth types don't require that)
kubectl create secret generic akv-creds --from-literal clientid=$SP_ClientID --from-literal clientsecret=$SP_Key

# Now let's deploy a Pod that access our Secret
code nginx-secrets-store.yaml

kubectl apply -f nginx-secrets-store.yaml

kubectl get pods
kubectl describe pod nginx-secrets-store  

# We can see the Secret in the Pod
kubectl exec -it nginx-secrets-store -- ls -l /mnt/secrets-store/

kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/sapassword"

# What if we upgrade the key?
# Currently, AKS and AKV are in sync
kubectl get secretproviderclasspodstatus `
        (kubectl get secretproviderclasspodstatus -o custom-columns=":metadata.name" ) -o yaml | grep version:
az keyvault secret show --name "TestKey" --vault-name $KVName --query "id" -o tsv

# Set a new value for the secret
az keyvault secret set --vault-name $KVName --name "TestKey" --value "NewSecret"
az keyvault secret show --name "TestKey" --vault-name $KVName --query "value"

# What does our pod show?
kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/TestKey"

# They are not in sync!
kubectl get secretproviderclasspodstatus `
        (kubectl get secretproviderclasspodstatus -o custom-columns=":metadata.name" ) -o yaml | grep version:
az keyvault secret show --name "TestKey" --vault-name $KVName --query "id"

# Default is 2 minutes
# Try again!
kubectl get secretproviderclasspodstatus `
        (kubectl get secretproviderclasspodstatus -o custom-columns=":metadata.name" ) -o yaml | grep version:
az keyvault secret show --name "TestKey" --vault-name $KVName --query "id"

# The key has been updated!
kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/TestKey"

# How about environment variables?
# Delete the pod
kubectl delete pod nginx-secrets-store

# Create a new pod, which requires an environment variable
code nginx-secrets-store-with-ENV.yaml

kubectl apply -f nginx-secrets-store-with-ENV.yaml

# The Pod won't start because the variable is missing
kubectl get pod nginx-secrets-store
kubectl describe pod nginx-secrets-store

# Let's set the variable
code secret-provide-class-with-ENV-dist.yaml

kubectl edit SecretProviderClass azure-kv-provider

# Delete and Create the Pod again
kubectl delete pod nginx-secrets-store
kubectl apply -f nginx-secrets-store-with-ENV.yaml

# And it's running!
kubectl get pod nginx-secrets-store

# Both, the file and the environment variable reflect our key
kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/TestKey"
kubectl exec -it nginx-secrets-store -- bash -c "printenv TestKey"

# Let's change it again:
az keyvault secret set --vault-name $KVName --name "TestKey" --value "AnotherNewSecret"

# Wait for 2 minutes
# They aren't in sync - environment variables are only exposed at Pod startup!
kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/TestKey"
kubectl exec -it nginx-secrets-store -- bash -c "printenv TestKey"

# Delete the Pod again
# In a deployment, we could also kill the Pod and have a new one created automatically
kubectl delete pod nginx-secrets-store
kubectl apply -f nginx-secrets-store-with-ENV.yaml

# And they are in sync
kubectl exec -it nginx-secrets-store -- bash -c "cat /mnt/secrets-store/TestKey"
kubectl exec -it nginx-secrets-store -- bash -c "printenv TestKey"


# How about using the VM Identity instead of a Service Principal?
# Delete the existing deployment, secret and also the SP
kubectl delete pod nginx-secrets-store
kubectl delete secret akv-creds
az ad sp delete --id $SP

# Let's change the config to VMM Identity
kubectl edit SecretProviderClass azure-kv-provider

# And create another Pod with a new manifest
# Let's compare the two manifests first!
code --diff nginx-secrets-store.yaml nginx-secrets-store-vmm.yaml

kubectl apply -f nginx-secrets-store-vmm.yaml

# But the Pod isn't starting
kubectl get pod nginx-secrets-store
kubectl describe pod nginx-secrets-store

# We need to grant this Identity permissions first
kubectl delete pod nginx-secrets-store

# Get the AKS Cluster's client ID and grant permissions to it
az aks show -n $AKSCluster -g $RG --query identityProfile

$clientId=(az aks show -n $AKSCluster -g $RG --query identityProfile.kubeletidentity.clientId -o tsv)

az keyvault set-policy -n $KVName --secret-permissions get --spn $clientId

# Let's try again
kubectl apply -f nginx-secrets-store-vmm.yaml

kubectl get pod nginx-secrets-store

# Cleanup
kubectl delete namespace keyvault
Clear-Host