<#
Excercise 4: For every drive on the computer, display the following information:
  - Total amount of files on the drive
  - Amount of free space.
  - Top 5 largest files on the drive. And their location.
#>

<#
I found this to help solve this problem. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-psdrive?view=powershell-7.6
Using this an example 3 We can search for drives both physical and network mapped. "Get-PSDrive -PSProvider FileSystem"
#>

Clear-Host
Write-Host "Doing a deep dive of computer."
$drives = Get-PSDrive -PSProvider FileSystem
foreach ($drive in $drives) {
    Write-Host "`nSearching drive $($drive.Name):"
    $totalFiles = (Get-ChildItem -Path $drive.Root -Recurse -File -ErrorAction SilentlyContinue `
   | Measure-Object).Count
    $freeSpace = [math]::Round($drive.Free / 1GB, 2)
    $largestFiles = Get-ChildItem -Path $drive.Root -Recurse -File -ErrorAction SilentlyContinue `
    | Sort-Object Length -Descending `
    | Select-Object -First 5 FullName, @{
        Name = "SizeGB"
        Expression = { [math]::Round($_.Length / 1GB, 2) }
    }
    Write-Host "Total amount of files on drive $($drive.Name): $totalFiles"
    Write-Host "Free space on drive $($drive.Name): $freeSpace GB"
    Write-Host "Top 5 biggest file on drive $($drive.Name) $largestFiles"
}