$DomainName = Read-Host "Domain name (e.g. corp.example.dk)"

$DefaultNetbios = ($DomainName.Split('.')[0]).ToUpper()
$NetbiosName = Read-Host "NetBIOS name [$DefaultNetbios]"
if ([string]::IsNullOrWhiteSpace($NetbiosName)) { $NetbiosName = $DefaultNetbios }

$SafeModePwd = Read-Host -AsSecureString "DSRM password"

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
  -DomainName $DomainName `
  -DomainNetbiosName $NetbiosName `
  -InstallDns `
  -SafeModeAdministratorPassword $SafeModePwd `
  -Force