# Exercise 2: Search the computer to check for ".BAT" and ".CMD" files on the entire C: drive. Will display total amount.
Clear-Host
Write-Host "Which file format do you wish to search for? .bat .cmd etc."
$fileformats = (Read-Host "Enter file format, put . in front, for multiple also use a space.").Split(" ")
foreach ($fileformat in $fileformats) {
Get-ChildItem -Path C:\ -Recurse -File -Filter "*$fileformat*" -ErrorAction SilentlyContinue `
    | Measure-Object `
    |Select-Object -ExpandProperty Count
Write-Host "Total amount of $fileformat files found ^"
}