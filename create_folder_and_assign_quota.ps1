# Define the base path where folders will be created
$basePath = "D:\"

# Define your user list (can be updated as needed)
$userList = @(
    "SAPB1MM\SLPRO01"
    "SAPB1MM\SLPRO02"
    "SAPB1MM\SLPRO03"
    "SAPB1MM\SLPRO04"
    "SAPB1MM\SLPRO05"
    "SAPB1MM\SLFIN01"
    "SAPB1MM\SLFIN02"
    "SAPB1MM\SLFIN03"
    "SAPB1MM\SLFIN04"
    "SAPB1MM\SLFIN05"
    "SAPB1MM\SLFIN06"
    "SAPB1MM\SLLOG01"
    "SAPB1MM\SLLOG02"
    "SAPB1MM\SLLOG03"
    "SAPB1MM\SLLOG04"
    "SAPB1MM\SLLOG05"
    "SAPB1MM\SLLOG06"
    "SAPB1MM\SLLOG07"
    "SAPB1MM\SLLOG08"
    "SAPB1MM\SLLOG09"
    "SAPB1MM\SLLOG10"
    "SAPB1MM\SLLOG11"
    "SAPB1MM\SLLOG12"
    "SAPB1MM\SLLOG13"
    "SAPB1MM\SLLOG14"
    "SAPB1MM\SLCRM01"
    "SAPB1MM\SLCRM02"
    "SAPB1MM\SLCRM03"
    "SAPB1MM\SLCRM04"
    "SAPB1MM\SLCRM05"
    "SAPB1MM\SLCRM06"
    "SAPB1MM\SLCRM07"
    "SAPB1MM\SLCRM08"
    "SAPB1MM\SLCRM09"
    "SAPB1MM\SLCRM10"
    "SAPB1MM\SLCRM11"
    "SAPB1MM\SLCRM12"
    "SAPB1MM\SLCRM13"
    "SAPB1MM\SLCRM14"
    "SAPB1MM\SLCRM15"
    "SAPB1MM\SLCRM16"

)

# Create base path if it doesn't exist
if (!(Test-Path -Path $basePath)) {
    New-Item -Path $basePath -ItemType Directory -Force
}

foreach ($user in $userList) {
    # Extract the username only (e.g., user1 from domain\user1)
    $userName = $user.Split('\')[-1]

    # Create user-specific folder
    $userFolder = Join-Path $basePath $userName
    if (!(Test-Path -Path $userFolder)) {
        New-Item -Path $userFolder -ItemType Directory -Force
        Write-Host "Created folder: $userFolder"
    }

    # Remove inherited permissions
    icacls $userFolder /inheritance:r

    # Grant full control to domain user and administrators group
    icacls $userFolder /grant:r "${user}:(OI)(CI)F"
    icacls $userFolder /grant:r "Administrators:(OI)(CI)F"
    icacls $userFolder /grant:r "Domain Admins:(OI)(CI)F"
    Write-Host "Permissions set for $user"
    # Apply 100MB quota template using FSRM
    New-FsrmQuota -Path $userFolder -Template "100 MB Limit"
    Write-Host "Quota applied to $userFolder"
}
