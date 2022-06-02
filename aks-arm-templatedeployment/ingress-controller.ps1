$ResourceGroup="wpa-aks-rg"
$RegistryName = "wpaContainerRegistry"
$ResourceGroup = (Get-AzContainerRegistry | Where-Object {$_.name -eq $RegistryName} ).ResourceGroupName
$ControllerRegistry = "k8s.gcr.io"
$ControllerImage = "ingress-nginx/controller"
$ControllerTag = "v1.0.4"
$PatchRegistry = "docker.io"
$PatchImage = "jettech/kube-webhook-certgen"
$PatchTag = "v1.5.1"
$DefaultBackendRegistry = "k8s.gcr.io"
$DefaultBackendImage = "defaultbackend-amd64"
$DefaultBackendTag = "1.5"
$CertManagerRegistry = "quay.io"
$CertManagerTag = "v1.3.1"
$CertManagerImageController = "jetstack/cert-manager-controller"
$CertManagerImageWebhook = "jetstack/cert-manager-webhook"
$CertManagerImageCaInjector = "jetstack/cert-manager-cainjector"

Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $ControllerRegistry -SourceImage "${ControllerImage}:${ControllerTag}"
Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $PatchRegistry -SourceImage "${PatchImage}:${PatchTag}"
Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $DefaultBackendRegistry -SourceImage "${DefaultBackendImage}:${DefaultBackendTag}"
Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $CertManagerRegistry -SourceImage "${CertManagerImageController}:${CertManagerTag}"
Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $CertManagerRegistry -SourceImage "${CertManagerImageWebhook}:${CertManagerTag}"
Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroup -RegistryName $RegistryName -SourceRegistryUri $CertManagerRegistry -SourceImage "${CertManagerImageCaInjector}:${CertManagerTag}"

$mgmt_rgname=(Get-AzAksCluster -ResourceGroupName $ResourceGroup -Name myAKSCluster).NodeResourceGroup

$StaticIp=(New-AzPublicIpAddress -ResourceGroupName $mgmt_rgname -Name myAKSPublicIP -Sku Standard -AllocationMethod Static -Location eastus).IpAddress
# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Set variable for ACR location to use for pulling images
$AcrUrl = (Get-AzContainerRegistry -ResourceGroupName $ResourceGroup -Name $RegistryName).LoginServer
$DnsLabel = "rak3234"

helm install nginx-ingress ingress-nginx/ingress-nginx `
    --namespace ingress-basic --create-namespace `
    --set controller.replicaCount=2 `
    --set controller.nodeSelector."kubernetes\.io/os"=linux `
    --set controller.image.registry=$AcrUrl `
    --set controller.image.image=$ControllerImage `
    --set controller.image.tag=$ControllerTag `
    --set controller.image.digest="" `
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz `
    --set controller.admissionWebhooks.patch.image.registry=$AcrUrl `
    --set controller.admissionWebhooks.patch.image.image=$PatchImage `
    --set controller.admissionWebhooks.patch.image.tag=$PatchTag `
    --set controller.admissionWebhooks.patch.image.digest="" `
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux `
    --set defaultBackend.image.registry=$AcrUrl, `
    --set defaultBackend.image.image=$DefaultBackendImage `
    --set defaultBackend.image.tag=$DefaultBackendTag `
    --set defaultBackend.image.digest="" `
    --set controller.service.loadBalancerIP=$StaticIp `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DnsLabel
