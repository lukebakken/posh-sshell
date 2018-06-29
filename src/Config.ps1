<#
.SYNOPSIS
    Retrieves entries from the OpenSSH config file.
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> Get-SshConfig
    Gets all configured hosts in the ssh config file residing at ~/.ssh/config
    PS C:\> Get-SshConfig 'foo'
    Gets the config entry with the name 'foo'
.PARAMETER SshHost
    The host name to look up. If not specified, will return all hosts.
.PARAMETER Path
    The path of the OpenSSH config file. If not specified, defaults to ~/.ssh/config
#>
function Get-SshConfig {
    param(
        [Parameter(Position = 0)]
        [string]
        $SshHost,

        [Parameter()]
        [string]
        $Path = (Get-SshPath 'config'),

        [Parameter()]
        [switch]
        $Raw
    )

    if (! (Test-Path $Path)) {
        # If we've requested the entire config as a raw object and it doesn't exist
        # at that path, just return a new one.
        if ($Raw -and !$SshHost) {
            return [SshConfig]::new()
        }

        throw "'$Path' could not be found."
    }

    # Parse-SshConfig defined in ConfigParser.ps1
    $cfg = Parse-SshConfig (Get-Content $Path -Raw)

    if($SshHost -and $Raw) {
        # Find a speific host as the raw Node object.
        return $cfg.Find($SshHost);
    }
    elseif($SshHost) {
        # Specific host, parsed into a dictionary with computed properties.
        return $cfg.Compute($SshHost);
    }
    elseif($Raw) {
        # All raw nodes.
        return $cfg;
    }
    else {
        # All computed nodes.
        return $cfg.Nodes `
           | Where-Object { $_.Type -eq "Directive" -and $_.Param -eq "Host" } `
           | Where-Object { $_.Value -ne "*" -and !$_.Value.Contains("?") } `
           | Foreach-Object { $cfg.Compute($_.Value) } `

    }
}

<#
.SYNOPSIS
    Displays a list of available SSH connections and allows you to connect to one of them.
.PARAMETER Name
(Optional) the name of host to connect. If not specified, a list of connections is displayed.
.PARAMETER Path
(Optional) the path to the ssh config file. Defaults to ~/.ssh/config
.EXAMPLE
    PS C:\> Connect-Ssh
#>
function Connect-Ssh {
    param(
        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter()]
        $Command = (Get-Command ssh)
    )

    # If a name is specified, then find the matching config entry
    if ($Name) {
        $match = Get-SshConfig $Name

        if($match -and $match["HostName"]) {
            & $Command $match["HostName"]
        }
        else {
            # Couldn't find a match. Assume an address and pass through to ssh.
            & $Command $Name
        }
        return
    }

    # No name specified. Print out a list of connections to choose from.

    $display = @()
    $config = @(Get-SshConfig) # Force array if there's only a single item.

    foreach ($entry in $config) {
        # Config entries may have "Host server.com" or they may have an alias:
        # Host server
        #   HostName server.com
        # If the former, then set the host entry to be the URI.
        # If the latter, use the hostname entry
        if (!$entry["HostName"]) {
            $entry["HostName"] = $entry["Host"]
            $entry["Host"] = ""
        }

        # Add a row to the output with a numeric index, name and URI.
        $properties = [PSCustomObject][ordered]@{
            "#" = ($config.IndexOf($entry) + 1)
            Name = $entry["Host"];
            Uri = $entry["HostName"]
        }

        $display += $properties
    }

    $display | Format-Table -AutoSize

    $userInput = (Read-Host "Enter a connection (or leave blank to cancel)").Trim()
    $index = 0

    # If the user has entered an index, connect to that the connection at that location
    if([int]::TryParse($userInput, [ref]$index)) {
        if ($index) {
            $selected = $config[$index - 1]
            if ($selected) {
                & $Command $selected["HostName"]
            }
        }
    }
    elseif($userInput) {
        # User entered a string. Find hostname instead.
        $selected = $config | Where-Object { $_["Host"] -eq $userInput } | Select-Object -First 1
        if($selected) {
            & $Command $selected["HostName"]
        }
    }
}

<#
.SYNOPSIS
    Adds an SSH connection
.DESCRIPTION
   Adds a new connection to the OpenSSH config file.
.EXAMPLE
    PS C:\> Add-SshConnection dev dev@example.com
    Adds a new ssh connection with the host alias 'Dev', which connects to 'dev@example.com'
.PARAMETER Name
    The name (alias) of the connection
.PARAMETER Uri
    The URI for the connection
.PARAMETER IdentityFile
    (Optional) The path to the IdentityFile to use for this connection
.PARAMETER User
    (Optional) The username for this connection
.PARAMETER AdditionalOptions
    (Optional) Hashtable of additional options for the connection
#>
function Add-SshConnection {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        $Uri,

        [Parameter()]
        [string]
        $IdentityFile,

        [Parameter()]
        [string]
        $User,

        [Parameter()]
        [hashtable]
        $AdditionalOptions = @{},

        [Parameter()]
        [string]
        $Path = (Get-SshPath 'config')
    )

    $parameters = @{}
    if ($Name) { $parameters["Host"] = $Name }
    if ($Uri) { $parameters["HostName"] = $Uri }
    if ($User) { $parameters["User"] = $User }
    if ($IdentityFile) { $parameters["IdentityFile"] = $IdentityFile }

    $AdditionalOptions.Keys | ForEach-Object { $parameters[$_] = $AdditionalOptions[$_] }

    $config = Get-SshConfig -Raw -Path $Path
    $config.Add($parameters)

    $config.Stringify() | Out-File $Path
}

<#
.SYNOPSIS
    Removes an SSH connection from the config file.
.EXAMPLE
    PS C:\> Remove-SshConnection 'dev'
    Removes the SSH connection from the config file with a Host (alias) of Dev.
.PARAMETER Name
    Name of the connection to remove.
#>
function Remove-SshConnection {
    param(
        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Path = (Get-SshPath 'config')
    )

    $config = Get-SshConfig -Raw -Path $Path
    $config.RemoveHost($Name)
    $config.Stringify() | Out-File $Path
}
