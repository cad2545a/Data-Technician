# Import activedirectory module required to control ad.
Import-Module ActiveDirectory -ErrorAction Stop

# Script is made to control active directory for school use. Since domain can change, it will start to see if previous set domain is available.
$script:Domain    = ""     # optionally hardcode, e.g. "corp.local"
$script:AdParams  = @{}
$script:DefaultOU = $null
$script:UpnSuffix = $null

function test-domain {
    param([string]$Name, [pscredential]$Credential)
    $p = @{ Server = $Name; ErrorAction = 'Stop' }
    if ($Credential) { $p.Credential = $Credential }
    try { Get-ADDomain @p } catch { $null }
}

function select-domain {
    $candidate = if ($script:Domain) { $script:Domain } else { $env:USERDNSDOMAIN }
    $cred = $null

    while ($true) {
        if ($candidate) {
            $d = test-domain -Name $candidate -Credential $cred

            if (-not $d -and -not $cred) {
                Write-Host "No access to '$candidate' as current user." -ForegroundColor Yellow
                if ((Read-Host "Try with other credentials? (y/N)") -eq 'y') {
                    $cred = Get-Credential
                    if ($cred) { $d = test-domain -Name $candidate -Credential $cred }
                }
            }

            if ($d) {
                $script:Domain    = $d.DNSRoot
                $script:DefaultOU = $d.UsersContainer
                $script:UpnSuffix = $d.DNSRoot
                $script:AdParams  = @{ Server = $d.DNSRoot }
                if ($cred) { $script:AdParams.Credential = $cred }
                Write-Host "Connected to $($d.DNSRoot)" -ForegroundColor Green
                return $true
            }
            Write-Host "Could not connect to '$candidate'." -ForegroundColor Red
        }

        $candidate = Read-Host "Domain to manage"
        if (-not $candidate) { return $false }
        $cred = $null
    }
}

function resolve-ou-path {
    param(
        [string]$Ou
    )

    if ([string]::IsNullOrWhiteSpace($Ou)) {
        return $null
    }

    if ($Ou -match '^(?:OU=|CN=|DC=)') {
        return $Ou
    }

    $domainDn = (Get-ADDomain @script:AdParams).DistinguishedName
    return "OU=$Ou,$domainDn"
}

function add-user {
    $ad = $script:AdParams
    $first = Read-Host "First name"
    $last  = Read-Host "Last name"
    $sam = Read-Host "Username"
    $ou = Read-Host "OU (for example: salg)"
    $pass = Read-Host "Password" -AsSecureString

    if ([string]::IsNullOrWhiteSpace($sam)) {
        Write-Host "Username cannot be empty."
        return
    }

    $ouPath = resolve-ou-path -Ou $ou
    if (-not $ouPath) {
        Write-Host "OU cannot be empty."
        return
    }

    if (Get-ADUser @ad -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "User '$sam' already exists."
        return
    }

    try {
        New-ADUser @ad `
            -Name "$first $last" `
            -GivenName $first `
            -Surname $last `
            -SamAccountName $sam `
            -UserPrincipalName "$sam@$($script:UpnSuffix)" `
            -Path $ouPath `
            -AccountPassword $pass `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop
        Write-Host "User '$sam' has been created in $ouPath."
    }
    catch {
        Write-Host "Error while creating user: $($_.Exception.Message)"
    }
}

function disable-user {
    $ad = $script:AdParams
    $sam = Read-Host "Username"

    try {
        $user = Get-ADUser @ad -Identity $sam -ErrorAction Stop
        Disable-ADAccount @ad -Identity $user -ErrorAction Stop
        Write-Host "User '$sam' has been disabled."
    }
    catch {
        Write-Host "Error while disabling user: $($_.Exception.Message)"
    }
}

function reset-password {
    $ad = $script:AdParams
    $sam = Read-Host "Username"
    $pw = Read-Host "New password" -AsSecureString
    try {
        $user = Get-ADUser @ad -Identity $sam -ErrorAction Stop
        Set-ADAccountPassword @ad -Identity $user -NewPassword $pw -Reset -ErrorAction Stop
        Unlock-ADAccount @ad -Identity $user
        Set-ADUser @ad -Identity $user -ChangePasswordAtLogon $true
        Write-Host "Password for user '$sam' has been reset. Password must be changed at next logon."
    }
    catch {
        Write-Host "Error while resetting password: $($_.Exception.Message)"
    }
}

function showMenu {
    if (-not (select-domain)) { return }

    do {
        Clear-Host
        Write-Host "Active Directory Administration Menu"
        Write-Host "1. Add User"
        Write-Host "2. Disable user"
        Write-Host "3. Reset password"
        Write-Host "4. Change domain"
        Write-Host "0. Exit"
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            '1' { add-user }
            '2' { disable-user }
            '3' { reset-password }
            '4' { $script:Domain = ""; select-domain | Out-Null }
            '0' { break }
            default { Write-Host "Invalid option. Please try again." }
        }

        if ($choice -ne "0") { Read-Host "`nPress enter to continue" | Out-Null }
    } while ($choice -ne "0")
}

<#function menu
menu switch option
function add-user
code for adding user to ad
function disable-user
code for disabling user in ad
function reset-password
code for resetting user password in ad
#>

showMenu