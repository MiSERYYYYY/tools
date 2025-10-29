<#
.SYNOPSIS
  GhostSPN-Search: find SPNs whose host does not match the computer's sAMAccountName (LDAP, no RSAT required)

.DESCRIPTION
  Dot-source this script to load the function into your session:
    . .\GhostSPN-Search.ps1

  Then call:
    GhostSPN-Search -All -Domain test.local
    GhostSPN-Search -ComputerName PKTLABS -Domain test.local -Credential (Get-Credential)
#>

function GhostSPN-Search {
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [switch]$All,
        [string]$Domain,
        [System.Management.Automation.PSCredential]$Credential,
        [switch]$Table
    )

    function Normalize-Name { param([string]$n) if (-not $n) { return "" } return $n.ToLower().Trim() }
    function Get-SPNHostPart { param([string]$spn) if($spn -match '^[^/]+/([^/:]+)'){return $matches[1]}; return $null }

    # Determine LDAP bind path
    try {
        if ($Domain) {
            $rdsePath = "LDAP://$Domain/RootDSE"
            if ($Credential) {
                $rdse = New-Object System.DirectoryServices.DirectoryEntry($rdsePath, $Credential.UserName, $Credential.GetNetworkCredential().Password)
            } else {
                $rdse = New-Object System.DirectoryServices.DirectoryEntry($rdsePath)
            }
            $defaultNamingContext = $rdse.Properties["defaultNamingContext"].Value
            $ldapBase = if ($defaultNamingContext) { "LDAP://$Domain/$defaultNamingContext" } else { "LDAP://$Domain" }
        } else {
            $rdse = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
            $defaultNamingContext = $rdse.Properties["defaultNamingContext"].Value
            $ldapBase = "LDAP://$defaultNamingContext"
        }

        if ($Credential) {
            $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBase, $Credential.UserName, $Credential.GetNetworkCredential().Password)
        } else {
            $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBase)
        }
    } catch {
        throw "Failed to bind to LDAP path '$ldapBase' : $_"
    }

    # Build searcher
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
    $searcher.PageSize = 1000
    $searcher.PropertiesToLoad.AddRange(@("servicePrincipalName","sAMAccountName")) | Out-Null

    if ($ComputerName) {
        $samQuery = if ($ComputerName.EndsWith('$')) { $ComputerName } else { "$ComputerName$" }
        $samQueryEsc = $samQuery -replace '\\','\\5c' -replace '\*','\\2a' -replace '\(','\\28' -replace '\)','\\29'
        $searcher.Filter = "(&(objectClass=computer)(sAMAccountName=$samQueryEsc))"
    } elseif ($All) {
        $searcher.Filter = "(objectClass=computer)"
    } else {
        throw "Specify -ComputerName or -All"
    }

    $out = @()

    foreach ($entry in $searcher.FindAll()) {
        $comp = $entry.Properties

        $sam = if ($comp.samaccountname.Count -gt 0) { Normalize-Name($comp.samaccountname[0]) } else { "" }
        if ($sam -and $sam.EndsWith('$')) { $sam = $sam.TrimEnd('$') }

        $spns = $comp.serviceprincipalname
        if (-not $spns) { continue }

        foreach ($spn in $spns) {
            $hostPart = Get-SPNHostPart -spn $spn
            if (-not $hostPart) { continue }
            $hostNorm = Normalize-Name($hostPart)

            if (-not ($sam -and ($hostNorm -like "*$sam*"))) {
                $obj = [PSCustomObject]@{
                    CheckedComputer = if ($sam) { $sam } else { "(no-sAMAccountName)" }
                    SPN             = $spn
                    SPN_Host        = $hostPart
                }
                $out += $obj
            }
        }
    }

    if ($out.Count -eq 0) {
        Write-Verbose "No mismatched SPNs found."
    } elseif ($Table) {
        $out | Format-Table -AutoSize
    }

    return $out
}
