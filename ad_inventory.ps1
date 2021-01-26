<#
.SYNOPSIS
  Get the Inventory of computer objects in the entire forest
.DESCRIPTION
  Get the Inventory of computer objects in the entire forest
.INPUTS
  None. The script captures Forest and Domain details when running in the environment. 
.OUTPUTS
  The generated output CSV file will be created in the same path from where the script was executed.
.NOTES
  Version:        1.0
  Author:         Mohammed Wasay
  Email:          hello@mowasay.com
  Web:            www.mowasay.com
  Creation Date:  04/28/2020
.EXAMPLE
  Get-Inventory.ps1 
#>

#Get Logged on user details
$cuser = $env:USERDOMAIN + "\" + $env:USERNAME
Write-Host -ForegroundColor Gray "Running script as: $cuser authenticated on $env:LOGONSERVER"

#Get the Forest Domain
$forest = (Get-ADForest).RootDomain

#Get all the Domains in the Forest
$domains = (Get-ADForest).Domains

#Time format for report naming
$timer = (Get-Date -Format MM-dd-yyyy)

Write-Host -ForegroundColor Magenta "Your Forest is: $forest"

#Loop through each domain
foreach ($domain in $domains) {
    Write-Host -ForegroundColor Yellow "Working on Domain: $domain"

    #Get one domain controller in the domain
    Import-Module ActiveDirectory
    $dcs = Get-ADDomainController -Discover -DomainName $domain

    #Run the following once on the DC
    foreach ($dc in $dcs.Hostname) {
        Write-Host -ForegroundColor Cyan "Working on Domain Controller: $dc"
    
        #Getting results
        $results = Get-ADComputer -Filter * -Server $dc -Properties Enabled, Name, DNSHostName, IPv4Address, LastLogonDate, OperatingSystem, OperatingSystemServicePack, OperatingSystemVersion, CanonicalName, whenCreated | Select-Object @{Name = "Domain"; Expression = { $domain } }, Enabled, Name, DNSHostName, IPv4Address, LastLogonDate, OperatingSystem, OperatingSystemServicePack, OperatingSystemVersion, CanonicalName, whenCreated
        
        #One results file inclusive of all domains
        $results | Export-Csv ./$forest-Servers-$timer.csv -NoTypeInformation -Append

        #Seperate results file for each domain
        #$results | Export-Csv ./$domain-Servers-$timer.csv -NoTypeInformation
    }

    Write-Host -ForegroundColor Green "Report for $domain generated!"
}
Write-Host -ForegroundColor Green "------======= Done! =======------"