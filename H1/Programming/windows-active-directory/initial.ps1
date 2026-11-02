# Initial setup script for Windows Active Directory environment. Static ip, and hostname.
# Step 1: Ask for network settings
$IP = Read-Host "Enter IP address"
$MaskBits = Read-Host "Enter Prefix Length (example: 24 for 255.255.255.0)"
$Gateway = Read-Host "Enter Gateway"
$DNS = Read-Host "Enter DNS Server"
$IPType = "IPv4"

# Get active network adapter
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

# Remove existing IP configuration
if (($adapter | Get-NetIPConfiguration).IPv4Address) {
    $adapter | Remove-NetIPAddress -AddressFamily $IPType -Confirm:$false
}

if (($adapter | Get-NetIPConfiguration).IPv4DefaultGateway) {
    $adapter | Remove-NetRoute -AddressFamily $IPType -Confirm:$false
}

# Configure IP and Gateway
$adapter | New-NetIPAddress `
    -AddressFamily $IPType `
    -IPAddress $IP `
    -PrefixLength $MaskBits `
    -DefaultGateway $Gateway

# Configure DNS
$adapter | Set-DnsClientServerAddress -ServerAddresses $DNS

Write-Host "Network configuration completed."

# Step 2: Set hostname.
$hostname = Read-Host "Enter new hostname"
Rename-Computer -NewName $hostname -Force

Write-Host "Hostname changed to $hostname. A restart is required for the changes to take effect." -ForegroundColor Red