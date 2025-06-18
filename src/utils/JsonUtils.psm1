# JSON utilities for PowerShell 5.1 compatibility

function ConvertFrom-JsonToHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$InputObject
    )
    
    try {
        $jsonObject = $InputObject | ConvertFrom-Json
        return ConvertTo-Hashtable -InputObject $jsonObject
    }
    catch {
        throw "Failed to convert JSON to hashtable: $_"
    }
}

function ConvertTo-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $InputObject
    )
    
    if ($null -eq $InputObject) {
        return $null
    }
    
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $collection = @()
        foreach ($item in $InputObject) {
            $collection += ConvertTo-Hashtable -InputObject $item
        }
        return $collection
    }
    
    if ($InputObject -is [psobject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }
    
    return $InputObject
}

function Test-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        return @{
            Valid = $false
            Error = "File not found: $Path"
        }
    }
    
    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        $null = $content | ConvertFrom-Json -ErrorAction Stop
        return @{
            Valid = $true
            Error = $null
        }
    }
    catch {
        return @{
            Valid = $false
            Error = "Invalid JSON: $_"
        }
    }
}

Export-ModuleMember -Function @(
    "ConvertFrom-JsonToHashtable",
    "ConvertTo-Hashtable",
    "Test-JsonFile"
)