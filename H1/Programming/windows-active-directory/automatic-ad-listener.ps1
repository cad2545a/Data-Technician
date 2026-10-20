# Run as Administrator on your AD Domain Server
$port = 8080
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/sync-ad/")
$listener.Start()

Write-Host "AD Sync Service running on port $port..." -ForegroundColor Green

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

            $bodyText = ""
            if ($request.HasEntityBody) {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                try {
                    $bodyText = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
            }

            if ([string]::IsNullOrWhiteSpace($bodyText)) {
                throw "Request body is empty."
            }

            $users = $bodyText | ConvertFrom-Json
            if ($null -eq $users) {
                throw "No users were provided."
            }
            if ($users -isnot [System.Array]) {
                $users = @($users)
            }

            $ouPath = "OU=Users,DC=corp,DC=local"

            foreach ($user in $users) {
                if ($null -eq $user) { continue }

                $username = if ($null -ne $user.username) { [string]$user.username } else { "" }
                if ([string]::IsNullOrWhiteSpace($username)) { continue }

                $username = $username.Trim()
                $givenName = if ($null -ne $user.firstName) { [string]$user.firstName.Trim() } else { "" }
                $surname = if ($null -ne $user.lastName) { [string]$user.lastName.Trim() } else { "" }
                $dept = if ($null -ne $user.department) { [string]$user.department.Trim() } else { "" }
                $title = if ($null -ne $user.title) { [string]$user.title.Trim() } else { "" }
                $email = if ($null -ne $user.email) { [string]$user.email.Trim() } else { "" }

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

                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

                if ($existingUser) {
                    Set-ADUser -Identity $username `
                        -GivenName $givenName `
                        -Surname $surname `
                        -Department $dept `
                        -Title $title `
                        -EmailAddress $email `
                        -Enabled $enabled
                }
                else {
                    $password = ConvertTo-SecureString "ChangeMe123!" -AsPlainText -Force
                    $displayName = "$givenName $surname".Trim()
                    if ([string]::IsNullOrWhiteSpace($displayName)) {
                        $displayName = $username
                    }

                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@corp.local" `
                        -Name $displayName `
                        -GivenName $givenName `
                        -Surname $surname `
                        -DisplayName $displayName `
                        -Department $dept `
                        -Title $title `
                        -EmailAddress $email `
                        -AccountPassword $password `
                        -Enabled $enabled `
                        -ChangePasswordAtLogon $true `
                        -Path $ouPath
                }
            }

            $jsonResponse = '{"status":"success","message":"Sync completed successfully"}'
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
            if ($null -ne $response) {
                $response.Close()
            }
        }
    }
}
finally {
    $listener.Stop()
}