<#
.SYNOPSIS

Parses the specified PowerShell script to check for syntax errors.
#>

Param(
    # The path to the PowerShell script to parse.
    [Parameter(Mandatory = $True, Position = 1)]
    [string] $path
)

Trap { Write-Warning $_; Exit 1 }
& `
{
    Write-Verbose "Parsing file $path"
    $contents = Get-Content $path
    $contents = [string]::Join([Environment]::NewLine, $contents)
    [void]$ExecutionContext.InvokeCommand.NewScriptBlock($contents)
    Write-Verbose "Parsed without errors"
} 