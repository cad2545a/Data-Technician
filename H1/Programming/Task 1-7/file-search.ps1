<# Exercise 3: Create a script that searches the computer for files matching a specified pattern. 
The script should be able to take wildcards and display all locations where a file with a matching name is found.#>
Clear-Host
Write-Host "File searcher"
$file = Read-Host "Enter filename or part of filename to search for, you can use wildcard search using *"
# Now using same logic as file-format-search.ps1 to search for a file.
$files = Get-ChildItem -Path C:\ -Recurse -Filter $file `
-ErrorAction SilentlyContinue

# Using a loop here to display, as multiple files could be shown.
if ($files) {
    $files | Select-Object FullName
    Write-Host "`nFile found here $($files.Count) file(s)."
}
else {
    Write-Host "No files found matching the pattern '$file'."
}