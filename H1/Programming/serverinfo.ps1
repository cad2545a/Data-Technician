function showMenu
{
    param (
        [string]$Title = 'Server Information Administration'
    )
    Clear-Host
    Write-Host "================ $Title ================"

    Write-Host "1: Press '1' for server hardware and domain information"
    Write-Host "2: Press '2' for operating system information"
    Write-Host "3: Press '3' for running services"
    Write-Host "Q: Press 'Q' to quit."
}

do
{
    showMenu
    $selection = Read-Host "Select an option"
    switch ($selection)
    {
        '1' {
            'Server hardware and domain information'
            Get-CimInstance -ClassName Win32_ComputerSystem |
                Select-Object Manufacturer, Model, Name, Domain, PartOfDomain, NumberOfProcessors, TotalPhysicalMemory
        }
        '2' {
            'Server operating system information'
            Get-CimInstance -ClassName Win32_OperatingSystem |
                Select-Object Caption, Version, OSArchitecture, LastBootUpTime
        }
        '3' {
            'Running services'
            Get-Service | Where-Object Status -EQ 'Running' | Select-Object Name, DisplayName, Status
        }
    }
    pause
}
until ($selection -eq 'q')
