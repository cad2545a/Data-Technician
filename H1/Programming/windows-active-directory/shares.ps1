# ============ SETTINGS ============
$dom   = (Get-ADDomain).NetBIOSName    # short domain name, e.g. NORDIKTECH
$root  = "C:\Shares"                   # where all folders live
$depts = "Salg","Udvikling","HR","Finans","Ledelse","IT"

# ============ PART 1: DEPARTMENT FOLDERS + SHARES ============
foreach ($d in $depts) {
    $path = "$root\Afdelinger\$d"      # e.g. C:\Shares\Afdelinger\Salg

    # create the folder
    New-Item -ItemType Directory -Force -Path $path | Out-Null

    # NTFS permissions: only admins, SYSTEM, IT_sec and the department's own group
    icacls $path /inheritance:r /grant:r "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "$dom\IT_sec:(OI)(CI)M" "$dom\${d}_sec:(OI)(CI)M" | Out-Null

    # share it as \\server\Salg (Everyone/Full on the share, NTFS does the real restricting)
    New-SmbShare -Name $d -Path $path -FullAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null
}

# ============ PART 2: PERSONAL FOLDERS ============
# the root folder for all personal folders, shared as a hidden share (\\server\Home$)
New-Item -ItemType Directory -Force -Path "$root\Home" | Out-Null
New-SmbShare -Name 'Home$' -Path "$root\Home" -FullAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null

# the fix: root is read-only for normal users, and each user only sees their own folder
icacls "$root\Home" /inheritance:r /grant:r "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "$dom\IT_sec:(OI)(CI)M" "$dom\Domain Users:(RX)" | Out-Null
Set-SmbShare -Name 'Home$' -FolderEnumerationMode AccessBased -Force

# one folder per user, found from the department groups
foreach ($d in $depts) {
    foreach ($user in Get-ADGroupMember "${d}_sec") {
        $name = $user.SamAccountName
        $path = "$root\Home\$name"     # e.g. C:\Shares\Home\lhansen

        New-Item -ItemType Directory -Force -Path $path | Out-Null

        # only this user, IT_sec, admins and SYSTEM
        icacls $path /inheritance:r /grant:r "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "$dom\IT_sec:(OI)(CI)M" "$dom\${name}:(OI)(CI)M" | Out-Null
    }
}

# ============ CHECK ============
Get-SmbShare | Where-Object Name -notin "ADMIN$","C$","IPC$" | Format-Table Name, Path, FolderEnumerationMode
icacls "$root\Afdelinger\Salg"
icacls "$root\Home"