function showMenu
{
    param (
        [string]$Title = 'Client Information Administration'
    )
    Clear-Host
    Write-Host "================ $Title ================"
    
    Write-Host "1: Press '1' for hardware information"
    Write-Host "2: Press '2' for operating system information"
    Write-Host "Q: Press 'Q' to quit."
}

do
 {
     showMenu
     $selection = Read-Host "Select an option"
     switch ($selection)
     {
         '1' {
             'Client hardware information'
             Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -Property Manufacturer, Model, Name, NumberOfProcessors, TotalPhysicalMemory
         }
         '2' {
             'Client operating system information'
             Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -Property Caption, Version, OSArchitecture, LastBootUpTime
         }
     }
     pause
 }
 until ($selection -eq 'q')
