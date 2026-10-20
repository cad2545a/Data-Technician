# Run as Administrator on your AD Domain Server
$port = 8080
$domainSuffix = "asmild.online"
$baseDN = "DC=asmild,DC=online"

# -------------------------------------------------------------------
# FUNKTION: Generer brugernavn og rens danske tegn
# -------------------------------------------------------------------
function Get-SanitizedUsername {
    param (
        [string]$fullName
    )

    $nameParts = $fullName.Trim() -split '\s+'
    $givenName = $nameParts[0]
    $surname = if ($nameParts.Length -gt 1) { ($nameParts[1..($nameParts.Length - 1)]) -join ' ' } else { "" }

    $cleanGiven = $givenName.ToLower() -replace 'æ','ae' -replace 'ø','oe' -replace 'å','aa'
    $cleanSurname = $surname.ToLower() -replace 'æ','ae' -replace 'ø','oe' -replace 'å','aa' -replace '\s+',''

    if ($cleanSurname -ne "") {
        $username = $cleanGiven.Substring(0, 1) + $cleanSurname
    } else {
        $username = $cleanGiven
    }

    return @{
        Username  = $username
        GivenName = $givenName
        Surname   = $surname
        FullName  = $fullName
    }
}

# -------------------------------------------------------------------
# 1. FUNKTION: Opret eller opdater bruger i AD
# -------------------------------------------------------------------
function Add-ADUserFromSheet {
    param (
        $user
    )

    $parsedName = Get-SanitizedUsername -fullName $user.name
    $username  = $parsedName.Username
    $givenName = $parsedName.GivenName
    $surname   = $parsedName.Surname
    $fullName  = $parsedName.FullName

    $userEmail = "$username@$domainSuffix"
    $upn       = "$username@$domainSuffix"
    $dept      = if ($null -ne $user.department) { [string]$user.department.Trim() } else { "" }
    $title     = if ($null -ne $user.title) { [string]$user.title.Trim() } else { "" }

    $enabled = $true
    if ($null -ne $user.enabled) {
        $enabledStr = [string]$user.enabled
        $enabled = $enabledStr.Trim().ToLowerInvariant() -in @("yes", "true", "1")
    }

    $targetOUPath = $null
    if (-not [string]::IsNullOrWhiteSpace($dept)) {
        $ouFilter = "OU=$dept,$baseDN"
        $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouFilter'" -ErrorAction SilentlyContinue

        if (-not $existingOU) {
            New-ADOrganizationalUnit -Name $dept -Path $baseDN
            Write-Host "Oprettede ny OU: $dept" -ForegroundColor Cyan
        }
        $targetOUPath = $ouFilter
    }

    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

    if ($existingUser) {
        Set-ADUser -Identity $username `
            -GivenName $givenName `
            -Surname $surname `
            -DisplayName $fullName `
            -Department $dept `
            -Title $title `
            -EmailAddress $userEmail `
            -Enabled $enabled

        if ($null -ne $targetOUPath) {
            Move-ADObject -Identity $existingUser.DistinguishedName -TargetPath $targetOUPath -ErrorAction SilentlyContinue
        }
        Write-Host "Opdaterede og flyttede bruger: $username" -ForegroundColor Yellow
    }
    else {
        $password = ConvertTo-SecureString "ChangeMe123!" -AsPlainText -Force
        $adUserParams = @{
            SamAccountName        = $username
            UserPrincipalName     = $upn
            Name                  = $fullName
            GivenName             = $givenName
            Surname               = $surname
            DisplayName           = $fullName
            Department            = $dept
            Title                 = $title
            EmailAddress          = $userEmail
            AccountPassword       = $password
            Enabled               = $enabled
            ChangePasswordAtLogon = $true
        }

        if ($null -ne $targetOUPath) {
            $adUserParams.Add("Path", $targetOUPath)
        }

        New-ADUser @adUserParams
        Write-Host "Oprettede ny bruger: $username" -ForegroundColor Green
    }
}

# -------------------------------------------------------------------
# 2. FUNKTION: Deaktiver bruger i AD (Tjekker om kunden er sat til "No")
# -------------------------------------------------------------------
function Disable-ADUserFromSheet {
    param (
        $user
    )

    # Tjek om brugeren rent faktisk er sat til No/false i Sheets
    $enabledStr = if ($null -ne $user.enabled) { [string]$user.enabled.Trim().ToLowerInvariant() } else { "yes" }
    if ($enabledStr -in @("no", "false", "0")) {
        $parsedName = Get-SanitizedUsername -fullName $user.name
        $username = $parsedName.Username

        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue
        if ($existingUser) {
            Disable-ADAccount -Identity $username
            Write-Host "Deaktiverede bruger: $username" -ForegroundColor Red
        }
    }
}

# -------------------------------------------------------------------
# 3. FUNKTION: Nulstil adgangskode i AD
# -------------------------------------------------------------------
function Reset-ADUserPasswordFromSheet {
    param (
        $user
    )

    $parsedName = Get-SanitizedUsername -fullName $user.name
    $username = $parsedName.Username

    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue
    if ($existingUser) {
        $secPassword = ConvertTo-SecureString "ResetMe123!" -AsPlainText -Force
        Set-ADAccountPassword -Identity $username -NewPassword $secPassword -Reset
        Set-ADUser -Identity $username -ChangePasswordAtLogon $true
        Write-Host "Nulstillede adgangskode for: $username" -ForegroundColor Magenta
    }
}

# -------------------------------------------------------------------
# 4. FUNKTION: Hent alle deaktiverede brugere (Filtrerer systemkonti fra)
# -------------------------------------------------------------------
function Get-DisabledADUsers {
    $disabledUsers = Get-ADUser -Filter "Enabled -eq '$false'" -Properties DisplayName, Department, Title, EmailAddress
    
    # Liste over indbyggede systemkonti der skal ekskluderes
    $systemAccounts = @("krbtgt", "Guest", "WDAGUtilityAccount", "DefaultAccount")
    
    $result = @()

    foreach ($u in $disabledUsers) {
        if ($u.SamAccountName -notin $systemAccounts) {
            $result += @{
                name       = if ($u.DisplayName) { $u.DisplayName } else { $u.SamAccountName }
                username   = $u.SamAccountName
                department = $u.Department
                title      = $u.Title
                email      = $u.EmailAddress
            }
        }
    }
    return $result
}

# -------------------------------------------------------------------
# HTTP LISTENER LOOP
# -------------------------------------------------------------------
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/sync-ad/")
$listener.Start()

Write-Host "AD Sync Service kører på port $port..." -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            if ($request.HttpMethod -ne "POST") {
                $response.StatusCode = 405
                $response.ContentType = "application/json"
                $jsonResponse = '{"status":"error","message":"Only POST requests are allowed"}'
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                continue
            }

            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $jsonBody = $reader.ReadToEnd()
            $reader.Dispose()

            if ([string]::IsNullOrWhiteSpace($jsonBody)) {
                throw "Request body is empty."
            }

            $items = $jsonBody | ConvertFrom-Json
            if ($items -isnot [System.Array]) {
                $items = @($items)
            }

            # Tjek om anmodningen er get_disabled
            if ($items[0].action -eq "get_disabled") {
                $disabledList = Get-DisabledADUsers
                $jsonResponse = $disabledList | ConvertTo-Json -Depth 2

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.StatusCode = 200
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                continue
            }

            # Eksekver handling pr. bruger
            foreach ($item in $items) {
                switch ($item.action) {
                    "add"            { Add-ADUserFromSheet -user $item }
                    "disable"        { Disable-ADUserFromSheet -user $item }
                    "reset_password" { Reset-ADUserPasswordFromSheet -user $item }
                    default          { Add-ADUserFromSheet -user $item }
                }
            }

            $jsonResponse = '{"status":"success","message":"Handling gennemfoert!"}'
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
            $response.StatusCode = 200
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        catch {
            $errMessage = $_.Exception.Message.Replace('\', '\\').Replace('"', '\"')
            $errResponse = "{`"status`":`"error`",`"message`":`"$errMessage`"}"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($errResponse)

            $response.StatusCode = 500
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        finally {
            $response.Close()
        }
    }
}
finally {
    $listener.Stop()
}