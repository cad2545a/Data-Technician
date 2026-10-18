# Exercise 1: Find the last 10 warnings in Windows' Event Log. Then save them in a file in XML format
Clear-Host
$file = "$env:USERPROFILE\Desktop\warnings.txt"
if (!(Test-Path $file)) {
    New-Item -Path $file -ItemType File -Force | Out-Null
}
Write-Host "Finding warnings and saving them to '$file'"
Get-WinEvent -FilterHashTable @{ # -FilterHashTable allows to store parameters.
    LogName = 'System'
    Level = 3 # Level 3 is warning, level 2 is error, level 1 is critical.
} -MaxEvents 10 | Tee-Object -FilePath $file # Tee-Object allows to print into terminal and also write to file.
# I decided to print into terminal as well, to see warnings faster.
Write-Host "Warnings saved to '$file'"