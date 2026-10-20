# Script used to listen for a sheets document to ad users.
# Run as Administrator on your AD Domain Server
$port = 8080$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/sync-ad/")
$listener.Start()

Write-Host "AD Sync Service running on port $port..." -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context =$listener.GetContext()
        $request =$context.Request
        $response =$context.Response

        if ($request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $jsonBody =$reader.ReadToEnd()
            $users =$jsonBody | ConvertFrom-Json

            $ouPath = "OU=Users,DC=corp,DC=local"

            foreach ($user in$users) {
                if ([string]::IsNullOrWhiteSpace($user.username)) { continue }

                $username  =$user.username.Trim()
                $givenName =$user.firstName.Trim()
                $surname   =$user.lastName.Trim()
                $dept      =$user.department.Trim()
                $title     =$user.title.Trim()
                $email     =$user.email.Trim()
                $enabled   = ($user.enabled.Trim() -eq "Yes")

                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

                if ($existingUser) {
                    Set-ADUser -Identity $username `
                        -GivenName $givenName `
                        -Surname $surname `
                        -Department $dept `
                        -Title $title `
                        -EmailAddress $email `
                        -Enabled $enabled
                } else {
                    $password = ConvertTo-SecureString "ChangeMe123!" -AsPlainText -Force
                    New-ADUser `
                        -SamAccountName $username `
                        -UserPrincipalName "$username@corp.local" `
                        -Name "$givenName$surname" `
                        -GivenName $givenName `
                        -Surname $surname `
                        -DisplayName "$givenName $surname" `
                        -Department $dept `
                        -Title $title `
                        -EmailAddress $email `
                        -AccountPassword $password `
                        -Enabled $enabled `
                        -ChangePasswordAtLogon $true `
                        -Path $ouPath
                }
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes("{\"status\":\"success\"}")
            $response.ContentType = "application/json"
            $response.OutputStream.Write($buffer, 0,$buffer.Length)
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
}