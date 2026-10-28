Import-Module ActiveDirectory

# ==================================================
# CONFIGURATION
# ==================================================

$DomainSuffix = "asmild.online"
$BaseDN = "DC=asmild,DC=online"

$ParentOUName = "asmild.online"
$ParentOUDN = "OU=$ParentOUName,$BaseDN"

$GoogleSheetCsvUrl = "https://docs.google.com/spreadsheets/d/1nLxzP70sR0n3z6oV_uNI2-KRtxAp3Sb7kLWeqvoNzeA/export?format=csv"

# ==================================================
# FUNCTIONS
# ==================================================

function ConvertTo-Bool {
    param($Value)

    return ([string]$Value).Trim().ToLower() -in @(
        "true",
        "yes",
        "1"
    )
}

function Get-Username {
    param([string]$FullName)

    if (:IsNullOrWhiteSpace($FullName)) {
        return $null
    }

    $parts = $FullName.Trim() -split '\s+'

    if ($parts.Count -eq 1) {
        return $parts[0].ToLower()
    }

    return (
        $parts[0].Substring(0,1) +
        ($parts[1..($parts.Count - 1)] -join '')
    ).ToLower()
}

function Get-NameParts {
    param([string]$FullName)

    $parts = $FullName.Trim() -split '\s+'

    $firstName = $parts[0]

    if ($parts.Count -gt 1) {
        $lastName = $parts[-1]
    }
    else {
        $lastName = ""
    }

    return @{
        FirstName = $firstName
        LastName  = $lastName
    }
}

function Get-DepartmentOU {
    param([string]$Department)

    if (:IsNullOrWhiteSpace($Department)) {
        return $ParentOUDN
    }

    $ouDN = "OU=$Department,$ParentOUDN"

    $existingOU = Get-ADOrganizationalUnit `
        -Filter "DistinguishedName -eq '$ouDN'" `
        -ErrorAction SilentlyContinue

    if (-not $existingOU) {

        New-ADOrganizationalUnit `
            -Name $Department `
            -Path $ParentOUDN

        Write-Host "Created OU: $Department" -ForegroundColor Cyan
    }

    return $ouDN
}

function Sync-ADUser {
    param($User)

    if (:IsNullOrWhiteSpace($User.name)) {
        return
    }

    $username = Get-Username $User.name

    if (-not $username) {
        return
    }

    $nameParts = Get-NameParts $User.name

    $firstName = $nameParts.FirstName
    $lastName  = $nameParts.LastName

    $email   = "$username@$DomainSuffix"
    $enabled = ConvertTo-Bool $User.enabled
    $ouPath  = Get-DepartmentOU $User.department

    $existingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$username'" `
        -Properties DistinguishedName `
        -ErrorAction SilentlyContinue

    if ($existingUser) {

        Set-ADUser `
            -Identity $existingUser `
            -GivenName $firstName `
            -Surname $lastName `
            -DisplayName $User.name `
            -Department $User.department `
            -Title $User.title `
            -EmailAddress $email

        if ($existingUser.DistinguishedName -notlike "*$ouPath*") {

            Write-Host "Moving $username to $ouPath" -ForegroundColor DarkCyan

            Move-ADObject `
                -Identity $existingUser.DistinguishedName `
                -TargetPath $ouPath `
                -ErrorAction Stop
        }

        Write-Host "Updated: $username" -ForegroundColor Yellow
    }
    else {

        $password = ConvertTo-SecureString `
            "ChangeMe123!" `
            -AsPlainText `
            -Force

        Write-Host "Creating $username in $ouPath" -ForegroundColor Green

        New-ADUser `
            -Name $User.name `
            -SamAccountName $username `
            -UserPrincipalName $email `
            -GivenName $firstName `
            -Surname $lastName `
            -DisplayName $User.name `
            -Department $User.department `
            -Title $User.title `
            -EmailAddress $email `
            -AccountPassword $password `
            -Enabled $enabled `
            -ChangePasswordAtLogon $true `
            -Path $ouPath

        Write-Host "Created: $username" -ForegroundColor Green
    }

    if ($enabled) {
        Enable-ADAccount `
            -Identity $username `
            -ErrorAction SilentlyContinue
    }
    else {
        Disable-ADAccount `
            -Identity $username `
            -ErrorAction SilentlyContinue

        Write-Host "Disabled: $username" -ForegroundColor Red
    }
}

# ==================================================
# EXECUTION
# ==================================================

try {

    Write-Host "Updating data collected from Google Sheets..." -ForegroundColor Gray

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $response = Invoke-WebRequest `
        -Uri $GoogleSheetCsvUrl `
        -UseBasicParsing

    $users = $response.Content | ConvertFrom-Csv

    Write-Host "Found $($users.Count) user(s)." -ForegroundColor Gray

    foreach ($user in $users) {
        Sync-ADUser $user
    }

    Write-Host "Sync completed successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    throw
}