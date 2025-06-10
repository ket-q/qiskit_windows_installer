# ==================================================
# ================ GLOBAL VARIABLES ================
# ==================================================
$QISKIT_WINDOWS_INSTALLER_VERSION = '0.1.8'


# Stop the script when a cmdlet or a native command fails
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$CPU_ARCHITECTURE_CODE = [int](Get-CimInstance Win32_Processor).Architecture

# Mapping of CPU Architecture Codes to Names
$archMap = @{
    0  = "x86"
    1  = "MIPS"
    2  = "Alpha"
    3  = "PowerPC"
    5  = "ARM"
    6  = "Itanium"
    9  = "AMD64"
    12 = "ARM64"
}

# Get the architecture string from the map based on the CPU architecture code
$CPU_ARCHITECTURE = $archMap[$CPU_ARCHITECTURE_CODE]

# Check if the architecture is valid
if (-not $CPU_ARCHITECTURE) {
    $err_msg = (
        "Unsupported CPU architecture code '$CPU_ARCHITECTURE_CODE'.",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg
}

$PYTHON_VERSION = '3.12.2' # 3.13 not working because ray requires Python 3.12


switch ($CPU_ARCHITECTURE) {
    'x86' { $PYTHON_VERSION = "$PYTHON_VERSION-win32" }   # For x86 systems, use the win32 version
    'AMD64' { $PYTHON_VERSION = $PYTHON_VERSION }            # For AMD64 systems, no change needed
    'ARM64' { $PYTHON_VERSION = $PYTHON_VERSION }      # For ARM64 systems, use the arm version
    default {
        $err_msg = (
            "Unsupported CPU architecture '$CPU_ARCHITECTURE' for Python installation.",
            "Manual intervention required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg
    }
}




# Minimum required version for Microsoft Visual C++ Redistributable (MVCR)
$MVCR_MIN_VERSION = [System.Version]"14.42.34438.0"



# Top-level folder of installer to keep files other than the venvs:
$ROOT_DIR = Join-Path ${env:LOCALAPPDATA} -ChildPath 'qiskit_windows_installer'

# Log file name and full path and name to the log:
$LOG_DIR = Join-Path $ROOT_DIR -ChildPath 'log'
$LOG_FILE = Join-Path $LOG_DIR -ChildPath 'log.txt'
$USER_CODE_CMD = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
$USER_CODE_EXE = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
$SYS_CODE_EXE = "C:\Program Files\Microsoft VS Code\Code.exe"
$SYS_CODE_CMD = "C:\Program Files\Microsoft VS Code\bin\code.cmd"
$PYENV_EXE = "$env:USERPROFILE\.pyenv\pyenv-win\bin\pyenv.bat"
$PYENV_PYTHON_EXE = Join-Path $env:USERPROFILE ".pyenv\pyenv-win\versions\$PYTHON_VERSION\python.exe"





# Flag to keep track whether our log file is already in place and ready to
# be used. Initially this flag is $false. It will be set to $true as soon
# as the $LOG_FILE is known to exist.
$log_up = $false
$log_cache = ""
$first_time_log_up = $true


# ===================================================
# ================ UTILITY FUNCTIONS ================
# ===================================================

function Output {
    <#
.SYNOPSIS
Take a string and write it to the target location(s).

.PARAMETER msg
The string to write out

.PARAMETER target

A string containing the target(s) to write to. Possible targets
include the console (via Write-Host), and the logfile $LOG.

'c' .. write to console only
'f' .. write to logfile only
'cf .. write to both console and logfile (default)
'n' .. discard $msg (may be useful to supress logs without requiring an if
        statement with the caller)

Note that the logfile only becomes accessible once our $ROOT_DIR folder
structure is set up. Until then, logs to the logfile are simply discarded.
(Depending on $log_up.)
#>
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        $msg,

        [Parameter(
            Mandatory = $false,
            Position = 1
        )]
        [ValidateSet('c', 'f', 'cf', 'n')]
        [string]
        $target = 'cf'  # default value
    )

    # Write to console
    if ( ($target -eq 'c') -or ($target -eq 'cf') ) {
        Write-Host $msg
    }

    # Write to logfile
    if ( ($target -eq 'f') -or ($target -eq 'cf') ) {
        # Can only log if the logfile is in place


        if ($log_up) {

            # If the log just got up, we need to write the buffer into it.
            # On the first time this condition is true, add the content of $log_cache to $LOG_FILE.

            if ($global:first_time_log_up -eq $true) {
                Set-Content $LOG_FILE -Value $global:log_cache
                $global:first_time_log_up = $false
            }

            # Then add the new message
            Add-Content $LOG_FILE -Value $msg

        }
        else {

            # Cache into a variable if the log isn't up yet
            $global:log_cache += $msg + "`n"
        }
    }
}


function Write-Header {
    param(
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "The message to write")]
        [string]$msg
    )
    $fill = "=" * $msg.Length
    Output "====$fill===="
    Output "==  $msg  =="
    Output "====$fill===="
}


function Log-Err {
    <#
.SYNOPSIS
Take a variable-length list of error variables and output them one by one. If
the firstArg=='fatal', then terminate the script if any of the error variables
is non-empty.

Parameters:
.PARAMETER firstArg
'fatal' or 'warn', to determine whether to terminate if any error variable is non-empty
.PARAMETER secondArg
 a string containing an overall description what theses errors are about.
.PARAMETER listArgs
one or more error variables
#>
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ValidateSet('fatal', 'warn')]
        [string]
        $firstArg = 'fatal',

        [Parameter(
            Mandatory = $true,
            Position = 1
        )]
        [string]
        $secondArg,

        [Parameter(
            Mandatory = $false,
            ValueFromRemainingArguments = $true,
            Position = 2
        )]
        [AllowEmptyString()]
        [string[]]
        $listArgs
    )
    # $listArgs cannot be empty, thus at least one error variable must be present
    $have_error = $false
    $err_count = 0
    $var_count = $listArgs.Length
    foreach ($listArg in $listArgs) {
        if ($listArg) {
            $have_error = $true
            $err_count = $err_count + 1
        }
    }

    # If all error variables are empty (no error occurred), we only log
    # and return.
    if (!$have_error) {
        $msg = "|STATUS| ${secondArg}: DONE"
        Output $msg
        return
    }

    # Falling through here means at least one error variable was non-empty,
    # and we log the details.
    $sep = "-" * 79
    Output $sep
    $kind = $(if ($firstArg -eq 'fatal') { "ERROR" } else { "WARNING" })
    $ending = $(if ($var_count -gt 1) { "s" } else { "" })
    Output "${kind}${ending} from ${secondArg}:"
    $count = 0
    foreach ($listArg in $listArgs) {
        Output $sep
        $err_str = $(if ($listArg) { $listArg } else { "OK" })
        Output $('Err[{0}]: {1}' -f $count, $err_str)
        $count++
    }
    Output $sep

    if (($firstArg -eq 'fatal') -and $have_error) {
        Write-Notice-Logfile
        Read-Host "The program encountered a fatal error. Please check the logfile. Press Enter to close the console..."
        exit 1
    }
}


function Write-Notice-Logfile {

    <#
.SYNOPSIS
    Write notice insode the logfile including an error message and also adding the log cache if necessary.
#>

    $msg = @"
AN ERROR OCCURED DURING THE INSTALLATION.

1. PLEASE CHECK that you are running the latest version of the Installer.
Link: https://github.com/ket-q/qiskit_windows_installer


2. PLEASE ALSO CHECK the SUPPORT/TROUBLESHOOTING section on our GitHub repository.
Link: https://github.com/ket-q/qiskit_windows_installer?tab=readme-ov-file#-faq--support--troubleshooting


We apologize for the possible inconvenience.
You will find the details of the installation process in this log file.
When sharing this log file with others please be aware that it contains certain private information such as your user ID.



"@

    if ($log_up) {
        # Read the beginning of the file (as many lines as $msg has)
        $linesToCheck = ($msg -split "`n").Count
        $currentTop = Get-Content $LOG_FILE -TotalCount $linesToCheck

        # Compare the top of the file with $msg
        if (($currentTop -join "`n").Trim() -ne $msg.Trim()) {
            $existingContent = Get-Content $LOG_FILE
            $msg | Set-Content $LOG_FILE
            $existingContent | Add-Content $LOG_FILE
        }
        Invoke-Native notepad $LOG_FILE
    }
    else {

        $downloadsPath = [System.IO.Path]::Combine($env:USERPROFILE, 'Downloads', 'log.txt')
        # Create and write to the new log file in Downloads
        $msg | Set-Content -Path $downloadsPath
        $global:log_cache | Add-Content -Path $downloadsPath
        Invoke-Native notepad $downloadsPath
    }
}


function Log-Status {
    <#
.SYNOPSIS
Friendly, informative-character logging only (no error, no warnings).
Take a variable-length list of status variables and output them one by one.

Parameters:
(1) statusVars: one or more status variables of type string to output

#>
    param(
        [Parameter(
            Mandatory = $True,
            ValueFromRemainingArguments = $true,
            Position = 0
        )]
        [AllowEmptyString()]
        [string[]]
        $statusVars
    )

    foreach ($statusVar in $statusVars) {
        Output $statusVar
    }
}


function Check-Installation-Platform {
    <#
.SYNOPSIS
Check whether the computer we're running on complies with the requirements
of this installer.
.DESCRIPTION
Conduct all possible up-front checks that ensure that the installation
will be possible on this computer:

1) platform is x86-64 (as our to-be-downloaded binary file names are
   currently hard-coded to the ABI version)
2) Windows version (v. 10 and 11 currently supported)
3) sufficient disk space (min 4GB of free space).
   FIXME: Because the space requirement will
   vary across Qiskit versions, a better space estimation method will
   be required in the future. Perhaps provide the required space in the
   requirements.txt file?
#>
    # CPU architecture


    try {

        if (($CPU_ARCHITECTURE -eq 'AMD64')) {
            Log-Status "AMD64 processor detected."

        }
        elseif (($CPU_ARCHITECTURE -eq 'x86')) {
            Log-Status "x86 processor detected."

        }
        elseif (($CPU_ARCHITECTURE -eq 'ARM64')) {
            Log-Status "ARM64 processor detected."
        }
        else {
            $err_msg = (
                "The installer currently only supports the 'AMD64','x86' and 'ARM64' architecture.",
                "Failed inside Check-Installation-Platform function"
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg
        }

    }
    catch {
        $err_msg = (
            "Error while checking processor architecture",
            "Manual intervention required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }


    try {
        # Windows version
        $ver_prop = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $win_ver = (Get-ItemProperty $ver_prop).CurrentMajorVersionNumber
        if ( ($win_ver -ne 10) -and ($win_ver -ne 11) ) {
            $err_msg = (
                "The installer currently only supports Windows 10 and 11.",
                "But this computer is running Windows version $win_ver."
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg
        }
    }
    catch {
        $err_msg = (
            "Error while checking Windows version inside Check-Installation-Platform function",
            "Manual intervention required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    try {
        # Free disk space
        $req_space = 4GB
        $free_space = (Get-PSDrive 'C').Free
        if ( $free_space -lt $req_space ) {
            $req_rnd = [math]::Round($req_space / 1GB, 1)
            $free_rnd = [math]::Round($free_space / 1GB, 1)
            $err_msg = (
                "The installer requires a minimum of ${req_rnd} GB of free disk space",
                "on the C drive. But the C drive currently has only ${free_rnd} GB ",
                "available. Please make space on the C drive, and try again."
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg
        }
    }
    catch {
        $err_msg = (
            "Error while checking disk space inside Check-Installation-Platform function",
            "Manual intervention required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
}


function Refresh-PATH {
    # Reload PATH environment variable to get modifications from program installers
    Output "Refresh-Env old PATH: $env:Path"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") +
    ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
    Output "Refresh-Env new PATH: $env:Path"
}


function Refresh-pyenv_Env {
    # Reload PyEnv environment variable (except PATH) to get modifications from installer
    Output "Refresh-Env old PYENV: $env:PYENV"
    $env:PYENV = [System.Environment]::GetEnvironmentVariable("PYENV", "Machine") +
    ";" +
    [System.Environment]::GetEnvironmentVariable("PYENV", "User")
    Output "Refresh-Env new PYENV: $env:PYENV"

    #
    # PYENV_ROOT and PYENV_HOME seem to be unpopulated from pyenv-win installer
    #
    # Write-Host "Refresh-Env old PYENV_ROOT: $env:PYENV_ROOT"
    # $env:PYENV_ROOT = [System.Environment]::GetEnvironmentVariable("PYENV_ROOT","User")
    # Write-Host "Refresh-Env new PYENV_ROOT: $env:PYENV_ROOT"

    # Write-Host "Refresh-Env old PYENV_HOME: $env:PYENV_HOME"
    # $env:PYENV_HOME = [System.Environment]::GetEnvironmentVariable("PYENV_HOME","User")
    # Write-Host "Refresh-Env new PYENV_HOME: $env:PYENV_HOME"
}


function Invoke-Native {
    <#
.SYNOPSIS
PoSH v. 5 does not automatically check the exit code of native commands.

Wrap passed native command to check its exit code and throw an exception
if non-zero.

Parameters:
(1) command: the native command to run
(2) command arguments: possibly empty list of arguments (usually strings)

#>

    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $false)]
        [string[]] $Arguments = @()
    )

    & $Command @Arguments
    $err = $LASTEXITCODE

    if ($err -ne 0) {
        throw "Native command '$Command $Arguments' returned $err"
    }
}


function Download-File {
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        $source_URL,

        [Parameter(
            Mandatory = $true,
            Position = 1
        )]
        [string]
        $target_name
    )

    Log-Status "Downloading $source_URL..."

    try {
        Invoke-Native -Command 'curl.exe' -Arguments @('--noproxy', '*', '--silent', '-L', '-o', $target_name, $source_URL)
    }
    catch {
        $err_msg = (
            "File download from $source_URL failed in Download-File function",
            "Manual check required."
        ) -join "rn"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    Log-Status 'Download DONE'

}


enum MVCRStatus {
    NotInstalled = 0
    Outdated = 1
    UpToDate = 2
}

# Function to check if VC++ Redistributable is installed
function Check-MVCR {

    $Path = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"

    # Define architecture-specific requirements
    $RequiredRedistributables = @()
    switch ($CPU_ARCHITECTURE) {
        "ARM64" {
            # ARM64 needs x86, x64, and ARM64 redistributables
            $RequiredRedistributables = @(
                "Microsoft Visual C++ 2015-2022 Redistributable (x86)*",
                "Microsoft Visual C++ 2015-2022 Redistributable (x64)*",
                "Microsoft Visual C++ 2022 Redistributable (Arm64)*"
            )
        }
        "AMD64" {
            # AMD64 needs x86 and x64 redistributables
            $RequiredRedistributables = @(
                "Microsoft Visual C++ 2015-2022 Redistributable (x86)*",
                "Microsoft Visual C++ 2015-2022 Redistributable (x64)*"
            )
        }
        "x86" {
            # x86 only needs the x86 redistributable
            $RequiredRedistributables = @(
                "Microsoft Visual C++ 2015-2022 Redistributable (x86)*"
            )
        }
        default {
            return [MVCRStatus]::NotInstalled
        }
    }

    # Check for the required redistributables
    $AtLeastOneOutdated = $false

    foreach ($redistributable in $RequiredRedistributables) {
        $entry = Get-ItemProperty $Path |
            Where-Object { $_.DisplayName -like $redistributable } |
            Select-Object -First 1

        if (-not $entry) {
            return [MVCRStatus]::NotInstalled
        }
        Log-Status "Found : $($entry.DisplayName)"

        $InstalledVersion = [System.Version]$entry.DisplayVersion

        if ($InstalledVersion -lt $MVCR_min_version) {
            $AtLeastOneOutdated = $true
        }
    }

    if ($AtLeastOneOutdated) {
        return [MVCRStatus]::Outdated
    }

    return [MVCRStatus]::UpToDate
}



# Function to uninstall all installed VC++ Redistributables
function Uninstall-MVCR {
    $UninstallKeys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

    $InstalledProducts = Get-ChildItem -Path $UninstallKeys | ForEach-Object {
        $Product = Get-ItemProperty -Path $_.PsPath
        if ($Product.DisplayName -match "Microsoft Visual C\+\+.*Redistributable") {
            return $Product
        }
    }

    foreach ($Product in $InstalledProducts) {
        if ($Product -and $Product.UninstallString) {
            Log-Status "Uninstalling: $($Product.DisplayName)"
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($Product.PSChildName) /quiet /norestart" -Wait
        }
    }
}



function Install-MVCR {
    function Install-MVCR-Version($arch, $url) {
        $installerPath = "$env:TEMP\vc_redist.$arch.exe"

        Log-Status "Downloading Microsoft Visual C++ Redistributable $arch installer"
        try {
            Download-File $url $installerPath
        }
        catch {
            $err_msg = "Download file of MVCR $arch failed`r`nManual check required"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
            return
        }

        try {
            $process = Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Verb RunAs -PassThru -Wait
        }
        catch {
            $err_msg = "Installation of MVCR $arch failed`r`nManual check required"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
            return
        }

        if ($process.ExitCode -eq 3010) {
            Log-Status "MVCR $arch installed successfully, but a reboot may be required (Exit Code 3010)"
        }
        elseif ($process.ExitCode -ne 0) {
            $err_msg = "Error during MVCR $arch installation`r`nManual check required"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs "Code Error: $($process.ExitCode)"
        }

        try {
            Remove-Item -Path $installerPath -Force
        }
        catch {
            $err_msg = "Couldn't remove MVCR $arch installer`r`nManual check required"
            Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
        }
    }

    Install-MVCR-Version 'x86' "https://aka.ms/vs/17/release/vc_redist.x86.exe"

    if ($CPU_ARCHITECTURE -eq 'ARM64' -or $CPU_ARCHITECTURE -eq 'AMD64') {
        Install-MVCR-Version 'x64' "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    }

    if ($CPU_ARCHITECTURE -eq 'ARM64') {
        Install-MVCR-Version 'arm64' "https://aka.ms/vs/17/release/vc_redist.arm64.exe"
    }
}



function Install-VSCode {
    # Determine installer URL based on architecture
    switch ($CPU_ARCHITECTURE) {
        'x86' { $VSCode_URL = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-user' }
        'AMD64' { $VSCode_URL = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user' }
        'ARM64' { $VSCode_URL = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-arm64-user' }
        default {
            $err_msg = "Unsupported CPU architecture '$CPU_ARCHITECTURE' for VSCode installation."
            Log-Err -firstArg 'fatal' -secondArg $err_msg
            return
        }
    }

    $VSCode_installer = 'vscode_installer.exe'
    $VSCode_installer_path = Join-Path ${env:TEMP} -ChildPath $VSCode_installer

    # Download VSCode
    Log-Status "Downloading VSCode installer for $CPU_ARCHITECTURE"

    try {
        Download-File $VSCode_URL $VSCode_installer_path
    }
    catch {
        $err_msg = (
            "Download of VS Code inside the Install-VSCode function failed",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    # Install VSCode
    Log-Status 'Running VSCode installer'
    $unattended_args = '/VERYSILENT /MERGETASKS=desktopicon,addtopath,!runcode'

    try {
        Start-Process -FilePath $VSCode_installer_path -ArgumentList $unattended_args -Wait -PassThru
    }
    catch {
        $err_msg = (
            "Installation of VSCode inside the Install-VSCode function failed",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    try {
        Remove-Item $VSCode_installer_path
    }
    catch {
        $err_msg = (
            "Cleanup of VSCode installer path failed inside Install-VSCode function",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    Log-Status 'VSCode installation DONE'
}


function Install-VSCode-Extension {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = 'Name of VSCode extension to install')]
        [string]$ext
    )

    try {
        if ( @(& $CODE_CMD --list-extensions | Where-Object { $_ -match $ext }).Count -ge 1 ) {
            Log-Status "VSCode extension $ext already installed"
            return
        }
    }
    catch {
        $err_msg = (
            "VS Code extension check failed inside Install-VSCode-Extension function",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)

    }


    try {
        Invoke-Native -Command $CODE_CMD -Arguments @('--install-extension', $ext)
    }
    catch {
        $err_msg = (
            "VS Code extension $ext failed inside Install-VSCode-Extension function",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
}


function Install-pyenv-win {

    Log-Status 'Downloading pyenv-win'

    $pyenv_installer = 'install_pyenv_win.ps1'
    $pyenv_installer_path = Join-Path ${env:TEMP} -ChildPath $pyenv_installer
    $pyenv_win_URL = 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1'

    try {
        Download-File $pyenv_win_URL $pyenv_installer_path
    }
    catch {
        $err_msg = (
            "Download-call error inside the Install-pyenv-win function",
            'Manual check required.'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    $pyvenv_test_path = Join-Path ${env:USERPROFILE} -ChildPath '.pyenv'


    if ((Test-Path $pyvenv_test_path)) {
        try {
            Remove-Item -Recurse -Force $pyvenv_test_path
        }
        catch {
            $err_msg = (
                "Error removing $pyvenv_test_path inside the Install-pyenv-win function",
                'Manual check required.'
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
        }
    }



    Log-Status 'Installing pyenv-win'
    try {
        & "${pyenv_installer_path}"
    }
    catch {
        $err_msg = (
            "./{pyenv_installer} failed inside the Install-pyenv-win function",
            'Manual check required.'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    # Cleanup
    try {
        Remove-Item $pyenv_installer_path
    }
    catch {
        $err_msg = (
            "Error removing $pyenv_installer_path inside the Install-pyenv-win function",
            'Manual check required.'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
    Log-Status 'DONE'
}


function Check-pyenv-List {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = "Python version to look for in pyenv local list")]
        [string]$ver
    )
    try {
        $versions = & $PYENV_EXE install -l
    }
    catch {
        $err_msg = (
            'pyenv install -l failed inside Check-pyenv-List function',
            'Manual check required.'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
    # For the regexp match, the dots in the version string are meta-chars
    # that we need to escape:
    $version_pattern = [regex]::Escape($ver)

    # \b means we only match on word boundaries.
    if ( !($versions -match "\b${version_pattern}\b") ) {
        Log-Status "pyenv does not list Python version '$ver'"
        return $false
    }
    Log-Status "pyenv supports Python version $ver"
    return $true
}


function Lookup-pyenv-Cache {
    <#
.SYNOPSIS
Consult the pyenv local list of supported Python versions whether $ver is provided.
If not, determine whether our local pyenv list should be updated and re-check
after the update.

We generally try to avoid updating the local pyenv list because it is slow.
The only time we ever consider updating is when the thought-after Python version
in $ver does not show up in our local list. At that point we consider updating
the cache, but only if the last check is older than 12h.

Parameters:
    $ver: the version of Python we're looking for.

Return value:
    $true: if $ver can be provided by pyenv
    $false: otherwise
#>
    param (
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = "Python version to look for in pyenv local list")]
        [string]$ver,

        [Parameter(
            Mandatory = $true,
            Position = 2,
            HelpMessage = "Path to the installer root folder")]
        [string]$ROOT_DIR
    )

    if ( (Check-pyenv-List $ver) ) {
        # Python $ver is supported
        return $true
    }

    # If we fall through here, then pyenv's local list of supported Python
    # versions does not contain $ver.

    $stamp = Join-Path $ROOT_DIR -ChildPath 'stamp.txt' # timestamp file
    $format = "yyyy-MM-dd_HH:mm:ss"  # timestamp format

    $need_refresh = $false  # Will be set to $true if pyenv cache is outdated
    $now = Get-Date

    if (!(Test-Path $stamp)) {
        # $stamp file does not exist, we never refreshed the cache
        $need_refresh = $true
    }
    else {
        # $stamp exists, determine whether the last check is past long enough
        # to warrant re-checking.
        $found = switch -File $stamp -RegEx {
            '^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d$' {
                $timestamp = $matches[0]
                $true
                break 
            }
        }
        if ( !$found ) {
            # $stamp does not contain a valid timestamp -> error out

            $err_msg = (
                'reading out timestamp of last pyenv cache update',
                'The timestamp file is corrupted.',
                "Path: $stamp"
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg

        }
        # If we fall through here we have date/time of last check in $timestamp
        $last_checked = [datetime]::ParseExact($timestamp, $format, $null)
        $hours_since_last_check = ($now - $last_checked).TotalHours

        if ($hours_since_last_check -gt 12) {
            $need_refresh = $true
        }
    }

    if ( !$need_refresh ) {
        # A cache update was not necessary. Thus
        # there's no point in another lookup and we give up.
        Log-Status "pywin cache already updated within the last 12 hours."
        Log-Status "No further update was attempted."
        return $false
    }

    # If we fall through here, the cache update and re-lookup is required
    Log-Status "Your pywin cache was not updated within the last 12 hours."
    Log-Status "Updating now, which may take some time..."
    try {
        Invoke-Native -Command $PYENV_EXE -Arguments @('update')
    }
    catch {
        $err_msg = (
            "pyenv update failed inside the Lookup-pyenv-Cache function",
            'Manual check required'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
    # Update $stamp with new timestamp
    $now.ToString($format) | Out-File -FilePath $stamp

    # Cache update succeeded, test one more time and return result
    return Check-pyenv-List $ver
}


function Test-symeng-Module {
    <#
.SYNOPSIS
Import the symengine Python module from the Python interpreter. The symengine
module is a Python wrapper for a machine-code library and thus error-prone for
installation failures.
#>
    Log-Status 'Testing the symengine Python module'
    try {
        Invoke-Native -Command $VENV_PYTHON -Arguments @('-c', 'import symengine')
        Log-Status 'PASSED'
    }
    catch {
        $err_msg = (
            "Symengine module test",
            'Manual check required'
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
}


function Test-qiskit-version {
    <#
.SYNOPSIS
Import the qiskit version number, and compare it to the expected version.
#>
    Log-Status 'Testing installed Qiskit version number'

    try {
        $py_cmd = 'from qiskit import __version__; print(__version__)'
        $v = Invoke-Native -Command $VENV_PYTHON -Arguments @('-c', $py_cmd)
    }
    catch {
        $err_msg = (
            "Qiskit version test failed"
        ) -join "`r`n"
        Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

    if ( $v -eq $qiskit_version ) {
        Log-Status "Detected Qiskit version number $v"
    }
    else {
        $err_msg = (
            "Qiskit version number check failed"
        ) -join "`r`n"
        Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
}


function Setup-Qiskit {

    param (
        [Parameter(
            Mandatory = $true,
            Position = 1)]
        [string]$qiskit_output
    )
    Log-Status "Still working"
    $qiskit_output = $qiskit_output -replace '\s*\(latest\)$', ''

    $qiskit_version = $qiskit_output.Replace("qiskit_", "")

    # Name of venv in .virtualenvs
    $qwi_vstr = 'qiskit_' + $qiskit_version.Replace('.', '_')

    $requirements_file = 'requirements_' + $qwi_vstr + '.txt'
    #$requirements_file = "symeng_requirements.txt"

    $req_URL = "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/resources/config/${requirements_file}"

    return $qiskit_version, $qwi_vstr, $requirements_file, $req_URL
}


# ===============================================
# ================ CONFIG WINDOW ================
# ===============================================

function Config-window {
    Add-Type -AssemblyName PresentationFramework

    $window = New-Object System.Windows.Window
    $window.Title = "Qiskit Windows Installer"
    $window.Width = 900
    $window.Height = 750
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(35, 35, 35))



    # Logo ImageBlock
    $logoBlock = New-Object System.Windows.Controls.Image
    $logoBlock.HorizontalAlignment = "Center"

    # Create a BitmapImage and set the Uri to the raw GitHub image URL
    $logoBlock.Margin = [System.Windows.Thickness]::new(0, -40, 0, 0)

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.UriSource = New-Object System.Uri("https://github.com/ket-q/qiskit_windows_installer/blob/main/resources/assets/QIWI_logo_white.png?raw=true", [System.UriKind]::Absolute)
    $bitmap.EndInit()

    # Set the source of the Image control
    $logoBlock.Source = $bitmap
    $logoBlock.Width = 750
    $logoBlock.Height = 250




    # Notice TextBlock
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = "The Qiskit Installer for WIndows will install the following software packages on your computer."
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textBlock.Margin = [System.Windows.Thickness]::new(-20, -100, 10, 0)
    $textBlock.FontSize = 20
    $textBlock.HorizontalAlignment = "Center"
    $textBlock.FontStyle = [System.Windows.FontStyles]::Italic
    $textBlock.FontFamily = "Segoe UI"
    $textBlock.Foreground = [System.Windows.Media.Brushes]::White


    # Notice TextBlock
    $textBlock2 = New-Object System.Windows.Controls.TextBlock
    $textBlock2.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textBlock2.Margin = [System.Windows.Thickness]::new(10, -30, 30, 20)
    $textBlock2.FontSize = 20
    $textBlock2.FontFamily = "Segoe UI"

    # First part - white color
    $run1 = New-Object System.Windows.Documents.Run "By validating the checkbox and continuing the execution, you "
    $run1.FontWeight = "Bold"
    $run1.Foreground = [System.Windows.Media.Brushes]::White


    # Second part - red color
    $run2 = New-Object System.Windows.Documents.Run "agree to respect the following license agreements:"
    $run2.FontWeight = "Bold"
    $run2.Foreground = [System.Windows.Media.Brushes]::Red

    # Add both runs to the TextBlock
    $textBlock2.Inlines.Add($run1)
    $textBlock2.Inlines.Add($run2)


    # Function to create a checkbox with a hyperlink
    function Create-CheckboxWithLink {
        param (
            [string]$checkBoxContent,
            [string]$linkText,
            [string]$url
        )

        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Margin = [System.Windows.Thickness]::new(5)
        $checkBox.Width = 500
        $checkBox.Height = 40
        $checkBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $checkBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.Margin = [System.Windows.Thickness]::new(0, -3, 0, 0)
        $textBlock.Inlines.Add($checkBoxContent)
        $textBlock.FontSize = 18
        $textBlock.FontFamily = "Segoe UI"
        $textBlock.Foreground = [System.Windows.Media.Brushes]::White
        $textBlock.HorizontalAlignment = "Left"

        $hyperlink = New-Object System.Windows.Documents.Hyperlink
        $hyperlink.Inlines.Add($linkText)
        $hyperlink.Foreground = [System.Windows.Media.Brushes]::LightSkyBlue
        $hyperlink.Cursor = [System.Windows.Input.Cursors]::Hand
        $hyperlink.Tag = $url  # Store the URL in the Tag property

        # Event handler that retrieves the URL from the Tag property
        $hyperlink.Add_Click({
                $clickedLink = $_.Source
                $linkUrl = $clickedLink.Tag
                if ($linkUrl) {
                    Start-Process $linkUrl
                }
            })

        $textBlock.Inlines.Add(" ")
        $textBlock.Inlines.Add($hyperlink)
        $checkBox.Content = $textBlock

        return $checkBox
    }

    # Checkboxes
    $checkBoxInstaller = Create-CheckboxWithLink "Qiskit Windows Installer" "(Installer License Agreement)" "https://github.com/ket-q/qiskit_windows_installer/blob/main/LICENSE"
    $checkBoxPython = Create-CheckboxWithLink "Python" "(Python License Agreement)" "https://docs.python.org/3/license.html"
    $checkBoxQiskit = Create-CheckboxWithLink "Qiskit" "(Qiskit License Agreement)" "https://quantum.ibm.com/terms"


    if (-not $VSCode_license_status) {
        $checkBoxVSCode = Create-CheckboxWithLink "VSCode" "(VSCode EULA)" "https://code.visualstudio.com/license"
    }
    if (-not $Pyenv_license_status) {
        $checkBoxPyenv = Create-CheckboxWithLink "Pyenv-win" "(Pyenv License Agreement)" "https://github.com/pyenv-win/pyenv-win/blob/master/LICENSE"
    }

    if (-not $MVCR_license_status) {
        $checkBoxVisualC = Create-CheckboxWithLink "Visual C++ Redistributable" "(Visual C++ License Agreement)" "https://visualstudio.microsoft.com/license-terms/vs2022-cruntime/"
    }



    # Button Styles
    $cornerRadius = New-Object System.Windows.CornerRadius(15)

    function Create-RoundedButton {
        param (
            [string]$content,
            [string]$color
        )

        # Create the button
        $button = New-Object System.Windows.Controls.Button
        $button.Content = $content
        $button.Width = 150
        $button.Height = 50
        $button.FontSize = 22
        $button.FontWeight = "Bold"
        $button.FontFamily = "Segoe UI"
        $button.Background = [System.Windows.Media.Brushes]::$color
        $button.Foreground = [System.Windows.Media.Brushes]::White
        $button.BorderBrush = $color

        $button.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $button.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        # Create a Border with rounded corners
        $border = New-Object System.Windows.Controls.Border
        $border.Width = $button.Width + 30
        $border.CornerRadius = $cornerRadius
        $border.Background = $button.Background
        $border.Child = $button

        return $border, $button
    }


    # Create buttons
    $borderProceed, $buttonProceed = Create-RoundedButton "Continue" "DarkGreen"
    $borderCancel, $buttonCancel = Create-RoundedButton "Cancel" "DarkRed"

    $borderCancel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)



    # Add MouseEnter and MouseLeave event to both buttons
    $buttonProceed.Add_MouseEnter({
            $buttonProceed.Foreground = [System.Windows.Media.Brushes]::Black
            $borderProceed.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(190, 230, 253))

        })
    $buttonProceed.Add_MouseLeave({
            $buttonProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
            $borderProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
            $buttonProceed.Foreground = [System.Windows.Media.Brushes]::White

        })

    $buttonCancel.Add_MouseEnter({
            $buttonCancel.Foreground = [System.Windows.Media.Brushes]::Black
            $borderCancel.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(190, 230, 253))

        })
    $buttonCancel.Add_MouseLeave({
            $buttonCancel.Background = [System.Windows.Media.Brushes]::DarkRed
            $borderCancel.Background = [System.Windows.Media.Brushes]::DarkRed
            $buttonCancel.Foreground = [System.Windows.Media.Brushes]::White

        })




    $buttonProceed.Add_IsEnabledChanged({
            if (-not $buttonProceed.IsEnabled) {
                $buttonProceed.Foreground = [System.Windows.Media.Brushes]::DarkGray
                $borderProceed.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(244, 244, 244))  # Red color
            }
            else {
                $buttonProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
                $buttonProceed.Foreground = [System.Windows.Media.Brushes]::White
                $borderProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
            }
        })



    $buttonProceed.IsEnabled = $false

    # Notice TextBlock
    $textQiskit = New-Object System.Windows.Controls.TextBlock
    $textQiskit.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textQiskit.Margin = [System.Windows.Thickness]::new(10, 0, 30, 0)
    $textQiskit.FontSize = 20
    $textQiskit.FontFamily = "Segoe UI"
    $textQiskit.FontWeight = "Bold"

    # First part - normal white text
    $run1 = New-Object System.Windows.Documents.Run "Please also "
    $run1.Foreground = [System.Windows.Media.Brushes]::White

    # Red part - emphasized text
    $run2 = New-Object System.Windows.Documents.Run "select the Qiskit Version "
    $run2.Foreground = [System.Windows.Media.Brushes]::Red

    # Last part - normal white text
    $run3 = New-Object System.Windows.Documents.Run "you wish to install:"
    $run3.Foreground = [System.Windows.Media.Brushes]::White

    # Add the runs to the TextBlock
    $textQiskit.Inlines.Add($run1)
    $textQiskit.Inlines.Add($run2)
    $textQiskit.Inlines.Add($run3)


    # Create the ComboBox
    $comboBox = New-Object Windows.Controls.ComboBox
    $comboBox.Width = 200
    $comboBox.Height = 35
    $comboBox.FontSize = 20
    $comboBox.Margin = '10'
    $comboBox.HorizontalAlignment = "Left"

    $global:checkSelection = $false


    $global:qiskit_selection = $null

    # Add items to the ComboBox
    @("qiskit_2.0.0 (latest)", "qiskit_1.4.2", "qiskit_1.3.2") | ForEach-Object {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $_
        $item.FontSize = 20
        $null = $comboBox.Items.Add($item)
    }

    # Event handler for selection changed
    $comboBox.Add_SelectionChanged({
            $selectedItem = $comboBox.SelectedItem
            $global:qiskit_selection = $($selectedItem.Content)

            if ($null -ne $selectedItem) {
                $global:checkSelection = $true
            }

            & $checkBoxChangedHandler
        })


    # Checkbox event handler
    $checkBoxChangedHandler = {
        $allChecked = $true

        if (-not $checkBoxPython.IsChecked) { $allChecked = $false }
        if (-not $checkBoxQiskit.IsChecked) { $allChecked = $false }
        if (-not $checkBoxInstaller.IsChecked) { $allChecked = $false }
        if ($null -ne $checkBoxVSCode -and -not $checkBoxVSCode.IsChecked) { $allChecked = $false }
        if ($null -ne $checkBoxPyenv -and -not $checkBoxPyenv.IsChecked) { $allChecked = $false }
        if ($null -ne $checkBoxVisualC -and -not $checkBoxVisualC.IsChecked) { $allChecked = $false }
        $buttonProceed.IsEnabled = $allChecked -and $global:checkSelection
    }

    $checkBoxInstaller.Add_Checked($checkBoxChangedHandler)
    $checkBoxPython.Add_Checked($checkBoxChangedHandler)
    $checkBoxQiskit.Add_Checked($checkBoxChangedHandler)
    if ($checkBoxPyenv) { $checkBoxPyenv.Add_Checked($checkBoxChangedHandler) }
    if ($checkBoxVisualC) { $checkBoxVisualC.Add_Checked($checkBoxChangedHandler) }
    if ($checkBoxVSCode) { $checkBoxVSCode.Add_Checked($checkBoxChangedHandler) }


    $checkBoxInstaller.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxPython.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxQiskit.Add_Unchecked($checkBoxChangedHandler)
    if ($checkBoxPyenv) { $checkBoxPyenv.Add_Unchecked($checkBoxChangedHandler) }
    if ($checkBoxVisualC) { $checkBoxVisualC.Add_Unchecked($checkBoxChangedHandler) }
    if ($checkBoxVSCode) { $checkBoxVSCode.Add_Unchecked($checkBoxChangedHandler) }

    # StackPanel Layout
    $stackPanel = New-Object System.Windows.Controls.StackPanel
    $null = $stackPanel.Children.Add($logoBlock)
    $null = $stackPanel.Children.Add($textBlock)
    $null = $stackPanel.Children.Add($textBlock2)
    $null = $stackPanel.Children.Add($checkBoxPython)
    $null = $stackPanel.Children.Add($checkBoxQiskit)
    if ($checkBoxVSCode) { $null = $stackPanel.Children.Add($checkBoxVSCode) }
    if ($checkBoxPyenv) { $null = $stackPanel.Children.Add($checkBoxPyenv) }
    if ($checkBoxVisualC) { $null = $stackPanel.Children.Add($checkBoxVisualC) }
    $null = $stackPanel.Children.Add($checkBoxInstaller)
    $null = $stackPanel.Children.Add($textQiskit)
    $null = $stackPanel.Children.Add($comboBox)
    $null = $stackPanel.Children.Add($borderProceed)
    $null = $stackPanel.Children.Add($borderCancel)

    $window.Content = $stackPanel

    #Resize of the window

    $baseHeight = 800
    $checkboxHeight = 40
    $missingCount = 0

    if (-not $checkBoxVSCode) { $missingCount++ }
    if (-not $checkBoxPyenv) { $missingCount++ }
    if (-not $checkBoxVisualC) { $missingCount++ }

    $window.Height = $baseHeight - ($missingCount * $checkboxHeight)




    # License acceptance tracking
    $global:acceptedLicense = $false

    $buttonProceed.Add_Click({
            $global:acceptedLicense = $true
            $window.Close()
        })

    $buttonCancel.Add_Click({
            $global:acceptedLicense = $false
            $window.Close()
        })

    $null = $window.ShowDialog()

    Log-Status "Selected qiskit version: $global:qiskit_selection"

    if ($global:acceptedLicense) {
        Log-Status "User accepted the license agreements."
        return $true , $qiskit_selection
    }
    else {
        Log-Status "User cancelled or closed the window."
        return $false , $qiskit_selection
    }

}


# ======================================
# ================ MAIN ================
# ======================================

Log-Status "QIWI version: $qiskit_windows_installer_version"

#
# Step 1: Set install script execution policy
#

Write-Header 'Step 1/18: Set install script execution policy'
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force

}
catch {
    $err_msg = (
        "Install script execution policy failed at Step 1",
        "Manual check required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 2: Check installation plaform
#

Write-Header 'Step 2/18: Check installation platform'
try {
    Check-Installation-Platform
}
catch {
    $err_msg = (
        "Error when calling Check-Installation-Platform at Step 2",
        "Manual check required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

Write-Header 'Step 2b/18 Check installed softwares'

$VSCode_license_status = $false
$MVCR_license_status = $false
$Pyenv_license_status = $false

#False = the user needs to accept the licenses
#True = the user has already accepted the the licenses


if ((Test-Path $USER_CODE_EXE) -or (Test-Path $SYS_CODE_EXE)) {
    Log-Status "VS Code is installed"
    $VSCode_license_status = $true
}
else {
    Log-Status "VS Code is not installed"
}




$CheckResult = Check-MVCR
switch ($CheckResult) {
    ([MVCRStatus]::NotInstalled) {
        Log-Status "Microsoft Visual C++ Redistributable (MVCR) is not installed. The latest version will be installed"
    }

    ([MVCRStatus]::Outdated) {
        Log-Status "An older version of Microsoft Visual C++ Redistributable is installed. The latest version will be installed"
    }

    ([MVCRStatus]::UpToDate) {
        Log-Status "Latest version of Microsoft Visual C++ Redistributable is already installed"
        $MVCR_license_status = $true

    }
}

if (Test-Path $PYENV_EXE) {
    Log-Status "Pyenv is already installed"
    $Pyenv_license_status = $true
}
else {
    Log-Status "Pyenv is not installed"
}

#
# Step 3: Config window
#

Write-Header 'Step 3/18: Config window (licences and qiskit version)'
try {
    $result, $qiskit_output = Config-window

}
catch {
    $err_msg = (
        "Unable to open config windows in Step 3",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)

}

if (!$result) {
    #User didn't accept the software Licence, program should stop
    $err_msg = (
        'User refused the software licences or closed the window in Step 3',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg
}

try {
    $qiskit_version, $qwi_vstr, $requirements_file, $req_URL = Setup-Qiskit -qiskit_output "$qiskit_output"

}
catch {
    $err_msg = (
        "Unable to setup qiskit Step 3",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 4: Set up installer root directory structure
#

Write-Header 'Step 4/18: set up installer root folder structure'

try {
    if (!(Test-Path $ROOT_DIR)) {
        New-Item -Path $ROOT_DIR -ItemType Directory
    }

}
catch {
    $err_msg = (
        "Root folder setup error. Can't check $ROOT_DIR in Step 4",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)

}

try {
    $qinst_root_obj = Get-Item $ROOT_DIR

    # Check that $ROOT_DIR is a folder and not a file. Required if
    # the name already pre-existed in the filesystem.
    if ( !($qinst_root_obj.PSIsContainer) ) {
        $err_msg = (
            'Setup installer root folder structure failed in Step 4',
            "$ROOT_DIR is not a folder.",
            "Please move $ROOT_DIR out of the way and re-run the script."
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg
    }
}
catch {
    $err_msg = (
        'Root folder setup failed in Step 4',
        "Can't check qinst_root_obj",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 4a: Create log directory
#


Write-Header 'Step 4a/18: set up log folder'
try {
    if ( !(Test-Path $LOG_DIR) ) {
        # Log folder does not exist yet => create
        New-Item -Path $LOG_DIR -ItemType Directory
    }
    if ( !(Test-Path $LOG_FILE) ) {
        # Log file does not exist yet => create
        New-Item $LOG_FILE -ItemType File
    }
    # Flag that logging is up-and-running
    $log_up = $true
}
catch {
    $err_msg = (
        "'Setup of log folder failed in Step 4a.",
        "Unable to set up $LOG_DIR.",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 4b: Set up the enclave folder
#

Write-Header 'Step 4b/18: set up enclave folder'
try {
    $ENCLAVE_DIR = Join-Path $ROOT_DIR -ChildPath $qwi_vstr
    if (!(Test-Path $ENCLAVE_DIR)) {
        $null = New-Item -Path $ENCLAVE_DIR -ItemType Directory
    }
    $null = Set-Location -Path $ENCLAVE_DIR
}
catch {
    $err_msg = (
        "Setup of enclave folder failed in Step 4b",
        "Unable to cd into $ENCLAVE_DIR.",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 5: Visual C++ Redistributable
#


Write-Header 'Step 5/18 Installing Microsoft Visual C++ Redistributable (MVCR)'

$CheckResult = Check-MVCR

switch ($CheckResult) {
    ([MVCRStatus]::NotInstalled) {
        Log-Status "Microsoft Visual C++ Redistributable (MVCR) is not installed at all. The latest version will be installed"
        try {
            Install-MVCR
        }
        catch {
            $err_msg = (
                "Installation of MVCR failed in Step 5.1",
                "Manual intervention required."
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
        }
    }

    ([MVCRStatus]::Outdated) {
        Log-Status "An older version of Microsoft Visual C++ Redistributable is installed. The latest version will be installed"
        try {
            #Uninstall-MVCR
            Install-MVCR
        }
        catch {
            $err_msg = (
                "Installation of MVCR failed in Step 5.2",
                "Manual intervention required."
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
        }
    }

    ([MVCRStatus]::UpToDate) {
        Log-Status "Latest version is already installed"
    }
}

#
# Step 6: Visual Studio Code
#

Write-Header 'Step 6a/18: Install VSCode'


try {
    $env:NODE_OPTIONS = "--force-node-api-uncaught-exceptions-policy=true" #To prevent DEP0168 error
}
catch {
    $err_msg = (
        'Initialization of node option failed at Step 6a',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

try {

    if (!((Test-Path $USER_CODE_EXE) -or (Test-Path $SYS_CODE_EXE))) {
    Log-Status 'VSCode not installed, running installer'
    Install-VSCode
    Refresh-PATH
    # Ensure VScode installation succeeded:
        if (!(Test-Path $CODE_EXE)) {
            $err_msg = (
                'VSCode installation failed in Step 6a',
                'Manual check required.'
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg
        }
        else {
            Log-Status 'VSCode installation succeeded'
        }
    }
    else {
        Log-Status 'VSCode already installed'

        if (Test-Path $SYS_CODE_EXE) {
            Log-Status "System-wide VScode already installed"
            $CODE_EXE = $SYS_CODE_EXE
            $CODE_CMD = $SYS_CODE_CMD
        }
        else {
            Log-Status "User VScode already installed"
            $CODE_EXE = $USER_CODE_EXE
            $CODE_CMD = $USER_CODE_CMD
        }
    }

}
catch {
    $err_msg = (
        'Installation of VSCode installation failed at Step 6a',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

Log-Status 'Installing VSCode Python extension'
Install-VSCode-Extension 'ms-python.python'

Log-Status 'Installing VSCode Jupyter extension'
Install-VSCode-Extension 'ms-toolsai.jupyter'


Write-Header 'Step 6b/18: Preloading VSCode extensions'


try {
    Invoke-Native -Command $CODE_CMD -Arguments @('--disable-workspace-trust')
}  
catch {
    $err_msg = (
        'Preloading of VSCode failed at Step 6b',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

$timeout = 10
$elapsed = 0
$processes = $null
try {
    while (-not $processes -and $elapsed -lt $timeout) {
        $processes = Get-Process -Name "Code" -ErrorAction SilentlyContinue
        if (-not $processes) {
            Start-Sleep -Seconds 1
            $elapsed++
        }
    }

    if ($processes) {
        Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class WinAPI {
                [DllImport("user32.dll")]
                public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            }
"@
        foreach ($proc in $processes) {
            if ($proc.MainWindowHandle -ne 0) {
                [void][WinAPI]::ShowWindow($proc.MainWindowHandle, 6)
            }
        }
    }
}
catch {
    $err_msg = (
        'Preloading visual studio code extension failed at Step 6b',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


#
# Step 7: pyenv-win
#
Write-Header 'Step 7/18: Install pyenv-win'

try{
    if ( !(Test-Path $PYENV_EXE) ) {
    Log-Status 'pyenv-win not installed, running installer'
    Install-pyenv-win
    Refresh-PATH
    Refresh-pyenv_Env
    # Ensure pyenv-win installation succeeded:
        if ( !(Test-Path $PYENV_EXE) ) {
            $err_msg = (
                'pyenv-win installation failed inside Step 7',
                'Manual check required.'
            ) -join "`r`n"
            Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
        }
        else {
            Log-Status 'pyenv-win installation succeeded'
        }
    }
    else {
        Log-Status 'pyenv-win already installed'
    }
}
catch {
    $err_msg = (
        'Installation pyenv-win failed at Step 7',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 8: pyenv support Python version
#

Write-Header "Step 8/18: Check if pyenv supports Python $python_version"
try{
    if ( !(Lookup-pyenv-Cache $python_version $ROOT_DIR) ) {
        $err_msg = (
            "availability-check of Python failed in Step 8",
            "Requested Python version $python_version not available with pyenv.",
            "Manual check required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }
}
catch {
    $err_msg = (
        'Python pyenv checked raised error at Step 8',
        'Manual check required.'
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


#
# Step 9: Setup Python for venv
#

Write-Header "Step 9/18: Set up Python $python_version for venv"

try {

    Invoke-Native -Command $PYENV_EXE -Arguments @('install', $python_version)
    Invoke-Native -Command $PYENV_EXE -Arguments @('local', $python_version)
}
catch {
    $err_msg = (
        'Python installation for pyenv failed in Step 9',
        "Manual check required"
    ) -join "`r`n"

    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

try {
    # Make sure that user's '.virtualenvs' folder exists or otherwise create it.
    $DOT_VENVS_DIR = Join-Path ${env:USERPROFILE} -ChildPath '.virtualenvs'
    if (!(Test-Path $DOT_VENVS_DIR)) {
        New-Item -Path $DOT_VENVS_DIR -ItemType Directory
    }

}
catch {
    $err_msg = (
        "Check that .virtualenvs exists failed in Step 9",
        "Manual check required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}
try {
    $dot_venvs_dir_obj = Get-Item $DOT_VENVS_DIR
}
catch {
    $err_msg = (
        "Can't get-item DOT_VENVS_DIR in Step 9",
        "Manual check required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

try {
    # Check that '.virtualenvs' is a folder and not a file. Required if
    # the name already pre-existed in the filesystem.
    if ( !($dot_venvs_dir_obj.PSIsContainer) ) {
        $err_msg = (
            'Error in .virtualenvs check',
            "$DOT_VENVS_DIR is not a folder.",
            "Please move $DOT_VENVS_DIR out of the way and re-run the script."
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg
    }
}
catch {
    $err_msg = (
        "Check that .virtualenvs exists failed in Step 9",
        "Manual check required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}
# Test whether a venv of name $qwi_vstr already exists and delete it.
# Note 1: VSCode etc. should not use the venv in that moment, but we don't
# actually check this.
# FIXME: If a Jupyter notebook is open, then the rm command on the venv
#        will fail.

try {
    $MY_VENV_DIR = Join-Path ${DOT_VENVS_DIR} -ChildPath $qwi_vstr
    if (Test-Path $MY_VENV_DIR) {
        # A venv of that name seems to exist already -> remove
        #rm -R $MY_VENV_DIR
        # Remove-Item -Force -Recurse -Path $MY_VENV_DIR
        Get-ChildItem $MY_VENV_DIR -Recurse | Remove-Item -Force -Recurse
    }
}
catch {
    $err_msg = (
        "Unable to remove existing venv inside Step 9",
        "Path/venv: $MY_VENV_DIR"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

# Create and enter enclave folder $ROOT_DIR\$qwi_vstr. This is from where we
# will set up the virtual environment in .virtualenvs
try {
    $ENCLAVE_DIR = Join-Path $ROOT_DIR -ChildPath $qwi_vstr
    if ( !(Test-Path $ENCLAVE_DIR) ) {
        New-Item -Path $ENCLAVE -ItemType Directory
    }
    Set-Location -Path $ENCLAVE_DIR
}
catch {
    $err_msg = (
        "Unable to cd into $ENCLAVE_DIR.",
        "Manual intervention required."
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


#
# Step 10: Download requirements_file
#


Write-Header "Step 10/18: Download $requirements_file"

try {
    # Download the requirements.txt file for the new venv
    Download-File -source_URL "$req_URL" -target_name "$requirements_file"

    if ((Get-Content $requirements_file -TotalCount 1).Substring(0, 3) -eq '404') {
        $err_msg = (
            "The download file $requirements_file contains a 404 error at Step 10",
            "Manual intervention required"
        ) -join "`r`n"
        Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
    }

}
catch {
    $err_msg = (
        "Download of requirements file failed at Step 10",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


#
# Step 11: Set up venv
#

# Create venv
Write-Header "Step 11/18: Set up venv $MY_VENV_DIR"
try {
    # create venv
    Invoke-Native -Command $PYENV_EXE -Arguments @('exec', $PYENV_PYTHON_EXE, '-m', 'venv', $MY_VENV_DIR)
    # activate venv
    Invoke-Native -Command "${MY_VENV_DIR}\Scripts\activate.ps1" -Arguments @()

    $VENV_PYTHON = "${MY_VENV_DIR}\Scripts\python.exe"
    $VENV_PIP = "${MY_VENV_DIR}\Scripts\pip.exe"

}
catch {
    $err_msg = (
        "Setting up venv failed at Step 11",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


#
# Step 12: Update pip of venv
#

Write-Header "Step 12/18: update pip of venv $MY_VENV_DIR"
try {
    Invoke-Native -Command $VENV_PYTHON -Arguments @('-m', 'pip', 'install', '--upgrade', 'pip')

}
catch {
    $err_msg = (
        "Pip update failed at Step 12",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 13: Install Qiskit in venv
#



Write-Header "Step 13/18: install Qiskit in venv $MY_VENV_DIR"
try {
    Invoke-Native -Command $VENV_PIP -Arguments @('install', '-r', $requirements_file)
}
catch {
    $err_msg = (
        "Installation of Qiskit in venv $MY_VENV_DIR failed at Step 13",
        "Pip couldn't install the requirements_file",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 14: Install ipykernel module in venv
#

Write-Header "Step 14/18: install ipykernel module in venv $MY_VENV_DIR"
try {
    Invoke-Native -Command $VENV_PIP -Arguments @('install', 'ipykernel')
}
catch {
    $err_msg = (
        "Installation of ipykernel module in venv $MY_VENV_DIR failed at Step 14",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 15: Install ipykernel kernel in venv
#

Write-Header "Step 15/18: install ipykernel kernel in venv $MY_VENV_DIR"
try {

    Invoke-Native -Command $VENV_PYTHON -Arguments @('-m', 'ipykernel', 'install', '--user', '--name', $qwi_vstr, '--display-name', "`"$qwi_vstr`"")
}
catch {
    $err_msg = (
        "Installation of ipykernel in venv $MY_VENV_DIR failed at Step 15",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 16: Write installer version in pyvenv.cfg
#

Write-Header "Step 16/18: Write installer version in pyvenv.cfg"

try {
    $cfg_path = "$MY_VENV_DIR\pyvenv.cfg"
    Add-Content $cfg_path "qiskit_windows_installer_version = $QISKIT_WINDOWS_INSTALLER_VERSION"
}
catch {

    $err_msg = (
        "Writing of installer version in pyvenv.cfg failed at Step 16",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)

}

#
# Step 17: Test the installation
#
Write-Header "Step 17/18: testing the installation in $MY_VENV_DIR"
Test-symeng-Module
try {
    Invoke-Native -Command "${MY_VENV_DIR}\Scripts\activate.ps1"
    Test-qiskit-Version
}
catch {
    $err_msg = (
        "Error for Test-Qiskit-version function at Step 17",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
}


# Deactivate the Python venv
try {
    Invoke-Native -Command "${MY_VENV_DIR}\Scripts\deactivate.bat"

}
catch {
    $err_msg = (
        "Error when deactivating the python venv at Step 17",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'fatal' -secondArg $err_msg -listArgs $($_.Exception.Message)
}

#
# Step 18: Open VS Code with the notebook
#

Write-Header "Step 18/18: Open Visual Studio code with the notebook"
try {
    $NoteBookURL = "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/resources/notebook/IBM_account_setup.ipynb"
    Invoke-WebRequest -Uri $NoteBookURL -OutFile "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb"
    Invoke-Native -Command $CODE_CMD -Arguments @('--reuse-window', "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb")
}
catch {
    $err_msg = (
        "'Error during opening of VS Code",
        "Open VScode by yourself with the IBM_Account_setup",
        "Manual intervention required"
    ) -join "`r`n"
    Log-Err -firstArg 'warn' -secondArg $err_msg -listArgs $($_.Exception.Message)
}



Log-Status "INSTALLATION DONE"
Log-Status "You can close this window."

Start-Sleep -Seconds 600
