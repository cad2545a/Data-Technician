# Option 1, count both seperate and give a count.

# Scan the entire filesystem for .bat files and count them.
Get-ChildItem -Path C:\ -Recurse -Filter *.bat -File -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count
# Scan the entire filesystem for .cmd files and count them.
Get-ChildItem -Path C:\ -Recurse -Filter *.cmd -File -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count

<#
$count = 0
Get-ChildItem -Path C:\ -Recurse -File -ErrorAction SilentlyContinue
    ForEach-Object {
        if ($_.Extension -eq ".bat" -or $_.Extension -eq ".cmd") {
            $count++
        }
    }
Write-Host "Total .bat and .cmd files found: $count"
#>
<#
$files = Get-ChildItem -Path C:\ -Include *.bat,*.cmd -Recurse -File -ErrorAction SilentlyContinue
$count = @($files).Count
Write-Host "Total amount of .bat and .cmd files found: $count"
#>
