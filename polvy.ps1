# Script to manage SSH connections to AWS instances

# Get the directory of the script
$SCRIPT_DIR = $PSScriptRoot
$KEYS_DIR = Join-Path $SCRIPT_DIR "keys"
$DATA_FILE = Join-Path $SCRIPT_DIR "connections.txt"

# Create keys directory if it doesn't exist
if (-not (Test-Path $KEYS_DIR)) {
    New-Item -ItemType Directory -Path $KEYS_DIR | Out-Null
}

# Create data file if it doesn't exist
if (-not (Test-Path $DATA_FILE)) {
    New-Item -ItemType File -Path $DATA_FILE | Out-Null
}

# Function to list instances and connect
function Connect-Instance {
    $content = Get-Content $DATA_FILE
    if ($content.Count -eq 0) {
        Write-Host "No instances found. Add one first."
        return
    }

    Write-Host "Available instances:"
    $i = 1
    $instances = @{}
    foreach ($line in $content) {
        $parts = $line -split '\|'
        $name = $parts[0]
        $desc = $parts[1]
        $ip = $parts[2]
        $user = $parts[3]
        $key = $parts[4]
        Write-Host "$i) $name - $desc (IP: $ip, User: $user, Key: $key)"
        $instances[$i] = "$name|$desc|$ip|$user|$key"
        $i++
    }

    $choice = Read-Host "Select instance number to connect (or q to quit)"
    if ($choice -eq "q") {
        return
    }

    if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -ge $i) {
        Write-Host "Invalid choice."
        return
    }

    $selected = $instances[[int]$choice]
    $parts = $selected -split '\|'
    $name = $parts[0]
    $ip = $parts[2]
    $user = $parts[3]
    $key = $parts[4]
    Write-Host "Connecting to $name ($ip)..."
    ssh -i (Join-Path $KEYS_DIR $key) "$user@$ip"
}

# Function to add a new instance
function Add-Instance {
    $name = Read-Host "Enter instance name"
    if ([string]::IsNullOrEmpty($name)) {
        Write-Host "Name cannot be empty."
        return
    }

    $desc = Read-Host "Enter description (optional)"

    $ip = Read-Host "Enter IP address"
    if ([string]::IsNullOrEmpty($ip)) {
        Write-Host "IP cannot be empty."
        return
    }

    $user = Read-Host "Enter username (default: ubuntu)"
    if ([string]::IsNullOrEmpty($user)) {
        $user = "ubuntu"
    }

    $key = Read-Host "Enter key file name (relative to keys/)"
    if ([string]::IsNullOrEmpty($key)) {
        Write-Host "Key file cannot be empty."
        return
    }

    "$name|$desc|$ip|$user|$key" | Out-File -FilePath $DATA_FILE -Append -Encoding utf8
    Write-Host "Instance added."
}

# Main menu loop
while ($true) {
    Write-Host ""
    Write-Host "SSH Manager"
    Write-Host "1) Connect to an instance"
    Write-Host "2) Add new instance"
    Write-Host "3) Quit"
    $option = Read-Host "Choose an option"

    switch ($option) {
        "1" { Connect-Instance }
        "2" { Add-Instance }
        "3" { exit 0 }
        default { Write-Host "Invalid option." }
    }
}
