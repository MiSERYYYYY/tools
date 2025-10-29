<#
.SYNOPSIS
  Find SPNs whose host does not match the computer's name using LDAP (no RSAT needed)
#>

param(
    [string]$ComputerName,
    [switch]$All
)

function Normalize-Name { param([string]$n) if (-not $n) { return "" } return $n.ToLower().Trim() }
function Get-SPNHostPart { param([string]$spn) if($spn -match '^[^/]+/([^/:]+)'){return $matches[1]}; return $null }

# Connect to default domain
$root = New-Object System.DirectoryServices.DirectoryEntry
$searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
$searcher.PageSize = 500
$searcher.PropertiesToLoad.AddRange(@("servicePrincipalName","sAMAccountName","dnsHostName")) | Out-Null

# Determine filter
if ($ComputerName) {
    $searcher.Filter = "(&(objectClass=computer)(sAMAccountName=$ComputerName`$))"
} elseif ($All) {
    $searcher.Filter = "(objectClass=computer)"
} else {
    Write-Error "Specify -ComputerName or -All"
    return
}

$results = @()

foreach ($entry in $searcher.FindAll()) {
    $comp = $entry.Properties

    # safely get sAMAccountName
    $sam = if ($comp.samaccountname.Count -gt 0) { Normalize-Name($comp.samaccountname[0]) } else { "" }
    if ($sam.EndsWith('$')) { $sam = $sam.TrimEnd('$') }

    # safely get dnsHostName
    $fqdn = if ($comp.dnshostname.Count -gt 0) { Normalize-Name($comp.dnshostname[0]) } else { "" }

    $spns = $comp.serviceprincipalname
    if (-not $spns) { continue }

    foreach ($spn in $spns) {
        $hostPart = Get-SPNHostPart -spn $spn
        if (-not $hostPart) { continue }
        $hostNorm = Normalize-Name($hostPart)

        # mismatch check
        if (($sam -and $hostNorm -notlike "*$sam*") -and ($fqdn -and $hostNorm -notlike "*$fqdn*")) {
            $results += [PSCustomObject]@{
                Computer   = $sam
                SPN        = $spn
                SPN_Host   = $hostPart
                DNS_Host   = $fqdn
            }
        }
    }
}

if ($results.Count -eq 0) {
    Write-Output "No mismatched SPNs found."
} else {
    $results | Format-Table -AutoSize
}
