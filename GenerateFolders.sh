
cd "C:\CKA-Lab"

$folders = @(
  "01-prerequisites",
  "02-container-runtime",
  "03-kubernetes-install",
  "04-application",
  "05-crd-baseline",
  "06-cert-manager",
  "07-prometheus",
  "08-argocd",
  "09-flannel",
  "10-calico-migration",
  "11-network-policies",
  "12-cluster-upgrade",
  "13-hpa",
  "14-vpa"
)

foreach ($folder in $folders) {
  New-Item -ItemType Directory -Force -Path $folder | Out-Null
  New-Item -ItemType File -Force -Path "$folder/README.md" | Out-Null
}

New-Item -ItemType File -Force -Path "README.md" | Out-Null

@"
*.log
*.tmp
.env
*.key
*.pem
kubeconfig
admin.conf
**/pki/
**/secrets/
"@ | Set-Content ".gitignore"
