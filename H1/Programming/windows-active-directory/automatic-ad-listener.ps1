Import-Module ActiveDirectory

# ==========================================================
# CONFIGURATION
# ==========================================================

$Config = @{
    Port            = 8080
    DomainSuffix    = "asmild.online"
    BaseDN          = "DC=asmild,DC=online"

    DefaultPassword = "ChangeMe123!"
    ResetPassword   = "ResetMe123!"
}

# ==========================================================
# HELPERS
# ==========================================================

function ConvertTo-Bool {
    param($Value)

    return ([string]$Value).Trim().ToLower() -in @(
        "yes",
        "true",
        "1"
    )
}

function Get-UserInfo {
    param(
        [string]$FullName
    )

    $parts = $FullName.Trim() -split '\s+'

    $givenName = $parts[0]

    $surname = if ($parts.Count -gt 1) {
        ($parts[1..($parts.Count - 1)]) -join " "
    }
    else {
        ""
    }

    $cleanGiven = $givenName.ToLower().
        Replace("æ","ae").
        Replace("ø","oe").
        Replace("å","aa")

    $cleanSurname = $surname.ToLower().
        Replace("æ","ae").
        Replace("ø","oe").
        Replace("å","aa").
        Replace(" ","")

    $username = if ($cleanSurname) {
        $cleanGiven.Substring(0,1) + $cleanSurname
    }
    else {
        $cleanGiven
    }

    [PSCustomObject]@{
        Username  = $username
        FullName  = $FullName
        GivenName = $givenName
        Surname   = $surname
        Email     = "$username@$($Config.DomainSuffix)"
        UPN       = "$username@$($Config.DomainSuffix)"
    }
}

function Send-JsonResponse {

    param(
        $Response,
        [int]$StatusCode,
        $Body
    )

    $json = $Body | ConvertTo-Json -Depth 5

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json"
    $Response.ContentLength64 = $buffer.Length

    $Response.OutputStream.Write($buffer,0,$buffer.Length)
}

function Ensure-DepartmentOU {

    param(
        [string]$Department
    )

    if ([string]::IsNullOrWhiteSpace($Department)) {
        return $null
    }

    $ouPath = "OU=$Department,$($Config.BaseDN)"

    $existingOU = Get-ADOrganizationalUnit `
        -Filter "DistinguishedName -eq '$ouPath'" `
        -ErrorAction SilentlyContinue

    if (-not $existingOU) {

        New-ADOrganizationalUnit `
            -Name $Department `
            -Path $Config.BaseDN

        Write-Host "Created OU: $Department" -ForegroundColor Cyan
    }

    return $ouPath
}

# ==========================================================
# AD USER ACTIONS
# ==========================================================

function Add-OrUpdateADUser {

    param(
        $User
    )

    $info = Get-UserInfo $User.name

    $department = [string]$User.department
    $title      = [string]$User.title
    $enabled    = ConvertTo-Bool $User.enabled

    $targetOU = Ensure-DepartmentOU $department

    $existingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$($info.Username)'" `
        -ErrorAction SilentlyContinue

    if ($existingUser) {

        Set-ADUser `
            -Identity $info.Username `
            -GivenName $info.GivenName `
            -Surname $info.Surname `
            -DisplayName $info.FullName `
            -Department $department `
            -Title $title `
            -EmailAddress $info.Email `
            -Enabled $enabled

        if ($targetOU) {

            Move-ADObject `
                -Identity $existingUser.DistinguishedName `
                -TargetPath $targetOU `
                -ErrorAction SilentlyContinue
        }

        Write-Host "Updated User: $($info.Username)" `
            -ForegroundColor Yellow
    }
    else {

        $password = ConvertTo-SecureString `
            $Config.DefaultPassword `
            -AsPlainText `
            -Force

        $params = @{
            SamAccountName        = $info.Username
            UserPrincipalName     = $info.UPN
            Name                  = $info.FullName
            GivenName             = $info.GivenName
            Surname               = $info.Surname
            DisplayName           = $info.FullName
            Department            = $department
            Title                 = $title
            EmailAddress          = $info.Email
            AccountPassword       = $password
            Enabled               = $enabled
            ChangePasswordAtLogon = $true
        }

        if ($targetOU) {
            $params.Path = $targetOU
        }

        New-ADUser @params

        Write-Host "Created User: $($info.Username)" `
            -ForegroundColor Green
    }
}

function Disable-ADUserFromSheet {

    param(
        $User
    )

    if (ConvertTo-Bool $User.enabled) {
        return
    }

    $info = Get-UserInfo $User.name

    $existingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$($info.Username)'" `
        -ErrorAction SilentlyContinue

    if ($existingUser) {

        Disable-ADAccount -Identity $info.Username

        Write-Host "Disabled User: $($info.Username)" `
            -ForegroundColor Red
    }
}

function Reset-ADUserPasswordFromSheet {

    param(
        $User
    )

    $info = Get-UserInfo $User.name

    $existingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$($info.Username)'" `
        -ErrorAction SilentlyContinue

    if (-not $existingUser) {
        return
    }

    $password = ConvertTo-SecureString `
        $Config.ResetPassword `
        -AsPlainText `
        -Force

    Set-ADAccountPassword `
        -Identity $info.Username `
        -NewPassword $password `
        -Reset

    Set-ADUser `
        -Identity $info.Username `
        -ChangePasswordAtLogon $true

    Write-Host "Password Reset: $($info.Username)" `
        -ForegroundColor Magenta
}

function Get-DisabledADUsers {

    $systemAccounts = @(
        "krbtgt",
        "Guest",
        "DefaultAccount",
        "WDAGUtilityAccount"
    )

    Get-ADUser `
        -Filter "Enabled -eq '$false'" `
        -Properties DisplayName,Department,Title,EmailAddress |

    Where-Object {
        $_.SamAccountName -notin $systemAccounts
    } |

    ForEach-Object {

        @{
            name       = $_.DisplayName
            username   = $_.SamAccountName
            department = $_.Department
            title      = $_.Title
            email      = $_.EmailAddress
        }
    }
}

# ==========================================================
# HTTP SERVICE
# ==========================================================

$listener = New-Object System.Net.HttpListener

$listener.Prefixes.Add(
    "http://*:$($Config.Port)/sync-ad/"
)

$listener.Start()

Write-Host ""
Write-Host "AD Sync Service Started" -ForegroundColor Green
Write-Host "Port: $($Config.Port)"
Write-Host ""

try {

    while ($listener.IsListening) {

        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        try {

            if ($request.HttpMethod -ne "POST") {

                Send-JsonResponse `
                    $response `
                    405 `
                    @{
                        status  = "error"
                        message = "POST required"
                    }

                continue
            }

            $reader = New-Object System.IO.StreamReader(
                $request.InputStream,
                $request.ContentEncoding
            )

            $body = $reader.ReadToEnd()

            $reader.Dispose()

            if ([string]::IsNullOrWhiteSpace($body)) {
                throw "Request body is empty"
            }

            $items = $body | ConvertFrom-Json

            if ($items -isnot [System.Array]) {
                $items = @($items)
            }

            if ($items[0].action -eq "get_disabled") {

                $disabledUsers = Get-DisabledADUsers

                Send-JsonResponse `
                    $response `
                    200 `
                    $disabledUsers

                continue
            }

            foreach ($item in $items) {

                switch ($item.action) {

                    "add" {
                        Add-OrUpdateADUser $item
                    }

                    "disable" {
                        Disable-ADUserFromSheet $item
                    }

                    "reset_password" {
                        Reset-ADUserPasswordFromSheet $item
                    }

                    default {
                        Add-OrUpdateADUser $item
                    }
                }
            }

            Send-JsonResponse `
                $response `
                200 `
                @{
                    status  = "success"
                    message = "Completed"
                }
        }
        catch {

            Send-JsonResponse `
                $response `
                500 `
                @{
                    status  = "error"
                    message = $_.Exception.Message
                }
        }
        finally {

            $response.Close()
        }
    }
}
finally {

    $listener.Stop()
}