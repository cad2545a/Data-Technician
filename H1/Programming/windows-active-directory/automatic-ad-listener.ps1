# Run as Administrator on your AD Domain Server
$port = 8080$domainSuffix = "asmild.online"
$baseDN = "DC=asmild,DC=online"  # Roden af dit AD

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/sync-ad/")
$listener.Start()

Write-Host "AD Sync Service kører på port $port..." -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context =$listener.GetContext()
        $request =$context.Request
        $response =$context.Response

        if ($request.HttpMethod -eq "POST") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $jsonBody =$reader.ReadToEnd()
                $users =$jsonBody | ConvertFrom-Json

                foreach ($user in$users) {
                    if ([string]::IsNullOrWhiteSpace($user.name)) { continue }

                    # 1. Opdel Navn i Fornavn og Efternavn
                    $fullName =$user.name.Trim()
                    $nameParts =$fullName -split '\s+'
                    $givenName =$nameParts[0]
                    if ($nameParts.Length -gt 1) {$surname = ($nameParts[1..($nameParts.Length - 1)]) -join ' '
                    } else {
                        $surname = ""
                    }

                    # 2. Generér Brugernavn (f.eks. John Doe -> jdoe)
                    if ($surname -ne "") {
                        $username = ($givenName.Substring(0,1) +$surname.Replace(" ", "")).ToLower()
                    } else {
                        $username =$givenName.ToLower()
                    }

                    # Generér Email og UPN
                    $userEmail = "$username@$domainSuffix"
                    $upn = "$username@$domainSuffix"
                    $dept =$user.department.Trim()
                    $title =$user.title.Trim()
                    $enabled = ($user.enabled.Trim() -eq "Yes")

                    # 3. Håndter OU (Tjek om afdelingens OU eksisterer, ellers opret den)
                    $targetOUPath =$baseDN
                    if (-not [string]::IsNullOrWhiteSpace($dept)) {$ouFilter = "OU=$dept,$baseDN"
                        $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouFilter'" -ErrorAction SilentlyContinue

                        if (-not $existingOU) {
                            New-ADOrganizationalUnit -Name $dept -Path$baseDN
                            Write-Host "Oprettede ny OU: $dept" -ForegroundColor Cyan
                        }
                        $targetOUPath =$ouFilter
                    }

                    # 4. Tjek om brugeren eksisterer i AD
                    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

                    if ($existingUser) {
                        # Opdatér eksisterende bruger
                        Set-ADUser -Identity $username `
                            -GivenName $givenName `
                            -Surname $surname `
                            -DisplayName $fullName `
                            -Department $dept `
                            -Title $title `
                            -EmailAddress $userEmail `
                            -Enabled $enabled
                        
                        # Flyt brugeren til den rigtige OU hvis afdelingen er ændret
                        Move-ADObject -Identity $existingUser.DistinguishedName -TargetPath $targetOUPath -ErrorAction SilentlyContinue
                        
                        Write-Host "Opdaterede og flyttede bruger: $username" -ForegroundColor Yellow
                    } else {
                        # Opret ny bruger
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

                        Write-Host "Oprettede ny bruger: $username i OU:$targetOUPath" -ForegroundColor Green
                    }
                }

                # Send 200 OK Svar
                $jsonResponse = '{"status":"success","message":"Synkronisering gennemført!"}'
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.StatusCode = 200$response.ContentType = "application/json"
                $response.ContentLength64 =$buffer.Length
                $response.OutputStream.Write($buffer, 0,$buffer.Length)

            } catch {
                $errResponse = "{`"status`":`"error`",`"message`":`"$($_.Exception.Message.Replace('\','\\').Replace('"','\"'))`"}"
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($errResponse)
                $response.StatusCode = 500$response.ContentType = "application/json"
                $response.ContentLength64 =$buffer.Length
                $response.OutputStream.Write($buffer, 0,$buffer.Length)
            }
        } else {
            $response.StatusCode = 405
        }

        $response.Close()
    }
} finally {
    $listener.Stop()
}