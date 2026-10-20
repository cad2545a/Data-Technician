# Run as Administrator on your AD Domain Server
$port = 8080
$domainSuffix = "asmild.online"
$baseDN = "DC=asmild,DC=online"  # Roden af dit AD

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

            $users = $jsonBody | ConvertFrom-Json
            if ($null -eq $users) {
                throw "No users were provided."
            }
            if ($users -isnot [System.Array]) {
                $users = @($users)
            }

            foreach ($user in $users) {
                if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.name)) { continue }

                $fullName = [string]$user.name.Trim()
                $nameParts = $fullName -split '\s+'
                $givenName = $nameParts[0]
                if ($nameParts.Length -gt 1) {
                    $surname = ($nameParts[1..($nameParts.Length - 1)]) -join ' '
                }
                else {
                    $surname = ""
                }

                if ($surname -ne "") {
                    $username = ($givenName.Substring(0, 1) + $surname.Replace(" ", "")).ToLower()
                }
                else {
                    $username = $givenName.ToLower()
                }

                $userEmail = "$username@$domainSuffix"
                $upn = "$username@$domainSuffix"
                $dept = if ($null -ne $user.department) { [string]$user.department.Trim() } else { "" }
                $title = if ($null -ne $user.title) { [string]$user.title.Trim() } else { "" }

                $enabledValue = $user.enabled
                if ($enabledValue -is [bool]) {
                    $enabled = $enabledValue
                }
                elseif ($enabledValue -is [string]) {
                    $enabled = $enabledValue.Trim().ToLowerInvariant() -in @("yes", "true", "1")
                }
                else {
                    $enabled = [bool]$enabledValue
                }

                $targetOUPath = $baseDN
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

                    Move-ADObject -Identity $existingUser.DistinguishedName -TargetPath $targetOUPath -ErrorAction SilentlyContinue
                    Write-Host "Opdaterede og flyttede bruger: $username" -ForegroundColor Yellow
                }
                else {
                    $password = ConvertTo-SecureString "ChangeMe123!" -AsPlainText -Force

                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName $upn `
                        -Name $fullName `
                        -GivenName $givenName `
                        -Surname $surname `
                        -DisplayName $fullName `
                        -Department $dept `
                        -Title $title `
                        -EmailAddress $userEmail `
                        -AccountPassword $password `
                        -Enabled $enabled `
                        -ChangePasswordAtLogon $true `
                        -Path $targetOUPath

                    Write-Host "Oprettede ny bruger: $username i OU: $targetOUPath" -ForegroundColor Green
                }
            }

            $jsonResponse = '{"status":"success","message":"Synkronisering gennemført!"}'
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
            $response.StatusCode = 200
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        catch {
            $errMessage = $_.Exception.Message.Replace('\\', '\\\\').Replace('"', '\"')
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