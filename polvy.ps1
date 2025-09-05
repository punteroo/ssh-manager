# Script to manage SSH connections to AWS instances

# Get the directory of the script
$SCRIPT_DIR = $PSScriptRoot
$KEYS_DIR = Join-Path $SCRIPT_DIR "keys"
$MIGRATION_DIR = Join-Path $SCRIPT_DIR "migration"
$DATA_FILE = Join-Path $SCRIPT_DIR "connections.txt"
$SSH_DIR = Join-Path $env:USERPROFILE ".ssh"

# Create keys directory if it doesn't exist
if (-not (Test-Path $KEYS_DIR)) {
    New-Item -ItemType Directory -Path $KEYS_DIR | Out-Null
}

# Create migration directory if it doesn't exist
if (-not (Test-Path $MIGRATION_DIR)) {
    New-Item -ItemType Directory -Path $MIGRATION_DIR | Out-Null
}

# Create data file if it doesn't exist
if (-not (Test-Path $DATA_FILE)) {
    New-Item -ItemType File -Path $DATA_FILE | Out-Null
}

# Function to print directory tree
function Print-Tree {
    param (
        [string]$dir,
        [string]$prefix = ""
    )
    $items = Get-ChildItem -Path $dir -Force
    $count = $items.Count
    $i = 0
    foreach ($item in $items) {
        $i++
        $base = $item.Name
        if ($i -eq $count) {
            Write-Host "$prefix└── $base"
            $new_prefix = "$prefix    "
        } else {
            Write-Host "$prefix├── $base"
            $new_prefix = "$prefix│   "
        }
        if ($item.PSIsContainer) {
            Print-Tree -dir $item.FullName -prefix $new_prefix
        }
    }
}

# Function to manage connection to a selected instance
function Manage-Connection {
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

    $choice = Read-Host "Select instance number (or q to quit)"
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
    $key_path = Join-Path $KEYS_DIR $key

    # Check if key exists in keys directory, otherwise try .ssh
    if (-not (Test-Path $key_path)) {
        Write-Host "Key file not found in keys directory, checking $SSH_DIR..."
        $key_path = Join-Path $SSH_DIR $key
        if (-not (Test-Path $key_path)) {
            Write-Host "Key file not found: $key (checked both $KEYS_DIR and $SSH_DIR)"
            return
        }
        Write-Host "Key file found in $SSH_DIR"
    }

    # Check and fix permissions if too open
    $acl = Get-Acl $key_path
    $has_extra_permissions = $acl.Access | Where-Object {
        $_.IdentityReference -notmatch 'NT AUTHORITY\\SYSTEM' -and
        $_.IdentityReference -notmatch $env:USERNAME -and
        $_.FileSystemRights -match 'Read|Write|FullControl'
    }
    if ($has_extra_permissions) {
        Write-Host "Key permissions are too open. Fixing automatically..."
        $acl = Get-Acl $key_path
        $acl.SetAccessRuleProtection($true, $false) # Disable inheritance, remove existing rules
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME, "FullControl", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $key_path -AclObject $acl
        if ($?) {
            Write-Host "Permissions fixed."
        } else {
            Write-Host "Failed to fix permissions."
            return
        }
    }

    # Sub-menu for connection options
    while ($true) {
        Write-Host ""
        Write-Host "Connection options for $name ($ip):"
        Write-Host "1) Connect only"
        Write-Host "2) Connect and migrate files"
        Write-Host "3) Back"
        $sub_option = Read-Host "Choose an option"

        switch ($sub_option) {
            "1" {
                Write-Host "Connecting to $name ($ip)..."
                ssh -i $key_path "$user@$ip"
                return
            }
            "2" {
                # Show tree view
                Write-Host "Files ready for migration:"
                Print-Tree -dir $MIGRATION_DIR
                # Check if migration dir is empty
                if ((Get-ChildItem -Path $MIGRATION_DIR -Force).Count -eq 0) {
                    Write-Host "(No files in migration directory)"
                }
                Write-Host ""
                Write-Host "These files will be copied to $ip`:/home/$user/migration"
                $confirm = Read-Host "Proceed with migration and connect? (y/n)"
                if ($confirm -eq "y" -or $confirm -eq "Y") {
                    # Create remote directory
                    ssh -i $key_path "$user@$ip" "mkdir -p /home/$user/migration"
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "Failed to create remote migration directory."
                        continue
                    }
                    # Copy files
                    scp -i $key_path -r (Join-Path $MIGRATION_DIR *) "$user@$ip`:/home/$user/migration/"
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "Failed to copy files."
                        continue
                    }
                    Write-Host "Files migrated successfully."
                    Write-Host "Connecting to $name ($ip)..."
                    ssh -i $key_path "$user@$ip"
                    return
                } else {
                    Write-Host "Migration cancelled."
                    # Back to sub-menu
                }
            }
            "3" {
                return
            }
            default {
                Write-Host "Invalid option."
            }
        }
    }
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

    $key = Read-Host "Enter key file name (relative to keys/ or ~/.ssh)"
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
        "1" { Manage-Connection }
        "2" { Add-Instance }
        "3" { exit 0 }
        default { Write-Host "Invalid option." }
    }
}
