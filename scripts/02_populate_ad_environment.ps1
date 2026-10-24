<#
.SYNOPSIS
    Populates Active Directory with realistic OUs, Users, Service Accounts,
    SPNs (Kerberoasting), and Vulnerable Pre-Auth Accounts (AS-REP Roasting).
.DESCRIPTION
    Run this script on DC01 AFTER the domain controller promotion has completed
    and the server has rebooted.
#>

Import-Module ActiveDirectory

$domain = Get-ADDomain
$domainName = $domain.DNSRoot
$domainDN = $domain.DistinguishedName
$defaultPassword = ConvertTo-SecureString "Winter2026!Corporate" -AsPlainText -Force
$weakPassword = ConvertTo-SecureString "Password123!" -AsPlainText -Force

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 1: Creating Organizational Units (OUs)           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$OUs = @("Corp", "Corp\Users", "Corp\IT_Admins", "Corp\Finance", "Corp\ServiceAccounts", "Corp\Workstations", "Corp\Servers")

foreach ($ou in $OUs) {
    $parts = $ou -split '\\'
    if ($parts.Count -eq 1) {
        $name = $parts[0]
        $path = $domainDN
    } else {
        $name = $parts[1]
        $path = "OU=$($parts[0]),$domainDN"
    }
    
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$name'" -SearchBase $path -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Creating OU: $ou" -ForegroundColor Green
        New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion $false
    } else {
        Write-Host "[+] OU exists: $ou" -ForegroundColor Green
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 2: Creating Domain Security Groups               " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$groups = @(
    @{ Name = "Tier1-Admins"; Path = "OU=IT_Admins,OU=Corp,$domainDN"; Description = "Helpdesk & Tier 1 Support Admins" },
    @{ Name = "Finance-Staff"; Path = "OU=Finance,OU=Corp,$domainDN"; Description = "Finance and Accounting Team" },
    @{ Name = "SQL-Admins"; Path = "OU=IT_Admins,OU=Corp,$domainDN"; Description = "Database Administrators" }
)

foreach ($g in $groups) {
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($g.Name)'" -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Creating Security Group: $($g.Name)" -ForegroundColor Green
        New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope Global -GroupCategory Security -Path $g.Path -Description $g.Description
    } else {
        Write-Host "[+] Group exists: $($g.Name)" -ForegroundColor Green
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 3: Creating Standard & Administrative Users      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$users = @(
    @{ Sam = "asmith"; First = "Alice"; Last = "Smith"; OU = "OU=Finance,OU=Corp,$domainDN"; Title = "Senior Financial Analyst"; Pass = $defaultPassword },
    @{ Sam = "jdoe"; First = "John"; Last = "Doe"; OU = "OU=Users,OU=Corp,$domainDN"; Title = "Sales Representative"; Pass = $defaultPassword },
    @{ Sam = "bwayne"; First = "Bruce"; Last = "Wayne"; OU = "OU=IT_Admins,OU=Corp,$domainDN"; Title = "Tier 1 Support Lead"; Pass = $defaultPassword }
)

foreach ($u in $users) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue)) {
        Write-Host "[+] Creating User: $($u.Sam) ($($u.First) $($u.Last))" -ForegroundColor Green
        New-ADUser -SamAccountName $u.Sam -UserPrincipalName "$($u.Sam)@$domainName" `
                   -Name "$($u.First) $($u.Last)" -GivenName $u.First -Surname $u.Last `
                   -DisplayName "$($u.First) $($u.Last)" -Path $u.OU -AccountPassword $u.Pass `
                   -Enabled $true -PasswordNeverExpires $true -Title $u.Title
    } else {
        Write-Host "[+] User exists: $($u.Sam)" -ForegroundColor Green
    }
}

# Add Bruce Wayne to Tier1-Admins
Add-ADGroupMember -Identity "Tier1-Admins" -Members "bwayne" -ErrorAction SilentlyContinue

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 4: Creating Kerberoastable Service Account       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$spnUser = "svc_sql"
if (-not (Get-ADUser -Filter "SamAccountName -eq '$spnUser'" -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Creating Service Account: $spnUser (Kerberoastable)" -ForegroundColor Yellow
    New-ADUser -SamAccountName $spnUser -UserPrincipalName "$spnUser@$domainName" `
               -Name "SQL Service Account" -DisplayName "SQL Service Account" `
               -Path "OU=ServiceAccounts,OU=Corp,$domainDN" -AccountPassword $weakPassword `
               -Enabled $true -PasswordNeverExpires $true -Description "Service Account for MSSQL Database Cluster"
}

# Register SPN using universal setspn.exe tool
Write-Host "[+] Registering ServicePrincipalName with setspn: MSSQLSvc/dc01.$domainName:1433" -ForegroundColor Yellow
& setspn.exe -s "MSSQLSvc/dc01.$domainName:1433" $spnUser
& setspn.exe -s "MSSQLSvc/dc01:1433" $spnUser

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 5: Creating AS-REP Roasting Vulnerable Account    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$asrepUser = "svc_backup"
if (-not (Get-ADUser -Filter "SamAccountName -eq '$asrepUser'" -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Creating Vulnerable Pre-Auth Account: $asrepUser (AS-REP Roasting Target)" -ForegroundColor Yellow
    New-ADUser -SamAccountName $asrepUser -UserPrincipalName "$asrepUser@$domainName" `
               -Name "Backup Service Account" -DisplayName "Backup Automation Service" `
               -Path "OU=ServiceAccounts,OU=Corp,$domainDN" -AccountPassword $weakPassword `
               -Enabled $true -PasswordNeverExpires $true -Description "Automated Veeam/Backup sync account"
}

# Disable Kerberos Pre-Authentication using standard Set-ADUser cmdlet
Write-Host "[!] Setting -DoesNotRequirePreAuth `$true on $asrepUser" -ForegroundColor Red
Set-ADUser -Identity $asrepUser -DoesNotRequirePreAuth $true

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 6: Setting Up Shared Folder Simulation           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$sharePath = "C:\CorporateShares\Finance"
if (-not (Test-Path $sharePath)) {
    New-Item -Path $sharePath -ItemType Directory -Force | Out-Null
    New-SmbShare -Name "FinanceShare" -Path $sharePath -FullAccess "Everyone" -ErrorAction SilentlyContinue
    
    $mockFile = @"
Internal Database Credentials & Configurations:
===============================================
Host: sql01.adlab.test:1433
User: svc_sql
Password: Password123!
Note: Service account password rotation scheduled for next quarter.
Contact: bruce.wayne@adlab.test for access grant.
"@
    Set-Content -Path "$sharePath\db_notes.txt" -Value $mockFile
    Write-Host "[+] Created Simulated SMB Share: \\DC01\FinanceShare with mock secrets" -ForegroundColor Green
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   Active Directory Environment Population Completed!     " -ForegroundColor Green
Write-Host "   - Domain: $domainName                                  " -ForegroundColor Green
Write-Host "   - Users: asmith, jdoe, bwayne                          " -ForegroundColor Green
Write-Host "   - Kerberoasting Target: svc_sql (Password: Password123!)" -ForegroundColor Yellow
Write-Host "   - AS-REP Roasting Target: svc_backup (Password: Password123!)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
