# Scan the entire filesystem for .bat files and count them.
Get-ChildItem -Path C:\ -Recurse -Filter *.bat -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count