# Import-Module ActiveDirectory
# Hent data fra csv fil og gem i variable
$ADUsers = Import-Csv C:\Users\Administrator\Documents\brugerliste.csv -Delimiter ";"

# Define UPN
$UPN = "asmild.local"

# Loop igennem felterne i csv filen
foreach ($User in $ADUsers) {

    $username = $User.firstname+"."+$User.lastname

    $Attributes = @{
    Enabled = $True
    ChangePasswordAtLogon = $True
    Name = $username
    SamAccountName=$username
    UserPrincipalName=$User.username+"@"+$UPN
    GivenName = $User.firstname
    SurName = $User.lastname
    Initials = $User.initials
    DisplayName = $User.lastname+","+$User.firstname
    Path = $User.ou
    EmailAddress = $User.email
    StreetAddress = $User.streetaddress
    City = $User.city
    PostalCode = $User.zipcode
    State = $User.state
    OfficePhone = $User.telephone
    Country = $User.Country
    Title = $User.jobtitle
    Company = $User.company
    Department = $User.department
    AccountPassword = (ConvertTo-secureString $user.Password -AsPlainText -Force)
    }

    # Tjek om bruger er oprettet
    if (Get-ADUser -F { SamAccountName -eq $username }) {
        
        # Hvis oprettet skriv en warning til skærm
        Write-Warning "En bruger med brugernavn $username er allerede oprettet i Active Directory."
    }
    else {

        # Opret bruger
        New-ADUser @Attributes

        # Hvis bruger er oprettet skriv
        Write-Host "Brugeren $username er oprettet." -ForegroundColor Cyan
    }
}

# Read-Host -Prompt "Tryk på en tast for at afslutte"