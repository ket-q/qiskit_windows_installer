# ==================================================
# ================ GLOBAL VARIABLES ================
# ==================================================


# Stop the script when a cmdlet or a native command fails
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$QISKIT_WINDOWS_INSTALLER_VERSION = '0.1.2'
$PYTHON_VERSION = '3.12.2' # 3.13 not working because ray requires Python 3.12

# Minimum required version for Microsoft Visual C++ Redistributable (MVCR)
$MVCR_MIN_VERSION = [System.Version]"14.42.34438.0"  



# Top-level folder of installer to keep files other than the venvs:
$ROOT_DIR = Join-Path ${env:LOCALAPPDATA} -ChildPath 'qiskit_windows_installer'

# Log file name and full path and name to the log:
$LOG_DIR = Join-Path $ROOT_DIR -ChildPath 'log'
$LOG_FILE = Join-Path $LOG_DIR -ChildPath 'log.txt'

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
            Mandatory=$true,
            Position=0
        )]
        [string]
        $msg,

        [Parameter(
            Mandatory=$false,
            Position=1
        )]
        [ValidateSet('c', 'f', 'cf', 'n')]
        [string]
        $target='cf'  # default value
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
        
        } else {
        
            # Cache into a variable if the log isn't up yet
            $global:log_cache += $msg + "`n"
        }        
    }
}


function Write-Header {
    param(
        [Parameter(Mandatory=$true, Position=1, HelpMessage="The message to write")]
        [string]$msg
    )
    $fill = "="*$msg.Length
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
            Mandatory=$true,
            Position=0
        )]
        [ValidateSet('fatal', 'warn')]
        [string]
        $firstArg = 'fatal',

        [Parameter(
            Mandatory=$true,
            Position=1
        )]
        [string]
        $secondArg,
     
        [Parameter(
            Mandatory=$true,
            ValueFromRemainingArguments=$true,
            Position=2
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
    $sep = "-"*79
    Output $sep
    $kind = $(If ($firstArg -eq 'fatal') {"ERROR"} Else {"WARNING"})
    $ending = $(If ($var_count -gt 1) {"s"} Else {""})
    Output "${kind}${ending} from ${secondArg}:"
    $count = 0
    foreach ($listArg in $listArgs) {
        Output $sep
        $err_str = $(If ($listArg) {$listArg} Else {"OK"})
        Output $('Err[{0}]: {1}' -f $count, $err_str)
        $count++
    }
    Output $sep

    if (($firstArg -eq 'fatal') -and $have_error) {
        
        Write-Notice-Logfile

        Exit 1

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


2. PLEASE ALSO CHECK the SUPPORT/TROUBLESHOOTING section on our github.
Link: https://github.com/ket-q/qiskit_windows_installer?tab=readme-ov-file#-faq--support--troubleshooting


Sorry for this, we will respond to you as fast as we can.

        
        
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
    } else { 
        
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
            Mandatory=$True,
            ValueFromRemainingArguments=$true,
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
        $arch = $env:PROCESSOR_ARCHITECTURE
        if ( $arch -ne 'AMD64' ) {
            $err_msg = (
                "The installer currently only supports the 'AMD64' architecture inside Check-Installation-Platform function",
                "But this computer is of architecture '$arch'."
                ) -join "`r`n"
            Log-Err 'fatal' 'Check-Install-Platform' $err_msg
    }
    } catch {
        $err_msg = (
            "Error while checking processor architecture",
            "Manual intervention required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
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
            Log-Err 'fatal' 'Check-Install-Platform' $err_msg       
        }
    } catch {
        $err_msg = (
            "Error while checking Windows version inside Check-Installation-Platform function",
            "Manual intervention required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }

    try {
        # Free disk space
        $req_space = 4GB
        $free_space = (Get-PSDrive 'C').Free
        if ( $free_space -lt $req_space ) {
            $req_rnd = [math]::Round($req_space/1GB, 1)
            $free_rnd = [math]::Round($free_space/1GB, 1)
            $err_msg = (
                "The installer requires a minimum of ${req_rnd} GB of free disk space",
                "on the C drive. But the C drive currently has only ${free_rnd} GB ",
                "available. Please make space on the C drive, and try again."
                ) -join "`r`n"
            Log-Err $err_msg   
        }
    } catch {
        $err_msg = (
            "Error while checking disk space inside Check-Installation-Platform function",
            "Manual intervention required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }
}


function Refresh-PATH {
    # Reload PATH environment variable to get modifications from program installers
    Output "Refresh-Env old PATH: $env:Path"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") +
              ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
    Output "Refresh-Env new PATH: $env:Path"
}


function Refresh-pyenv_Env {
    # Reload PyEnv environment variable (except PATH) to get modifications from installer
    Output "Refresh-Env old PYENV: $env:PYENV"
    $env:PYENV = [System.Environment]::GetEnvironmentVariable("PYENV","Machine") +
               ";" +
               [System.Environment]::GetEnvironmentVariable("PYENV","User")
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

    if ( $args.Count -eq 0) {
        throw 'Invoke-Native called without arguments'
    }

    $cmd = $args[0]

    $cmd_args = $null
    if ($args.Count -gt 1) {
        $cmd_args = $args[1..($args.Count-1)]
    }
 
    & $cmd $cmd_args
    $err = $LASTEXITCODE

    if ( $err -ne 0 ) {
        throw "Native command '$cmd $cmd_args' returned $err"
    }
}


function Download-File {
    param(
        [Parameter(
            Mandatory=$true,
            Position=0
        )]
        [string]
        $source_URL,

        [Parameter(
            Mandatory=$true,
            Position=1
        )]
        [string]
        $target_name
    )

    Log-Status "Downloading $source_URL..."

    try {
	    Invoke-Native curl.exe --noproxy '*' --silent -L -o $target_name $source_URL
    }
    catch {
        $err_msg = (
            "File download from $source_URL failed in Download-File function",
            "Manual check required."
            ) -join "rn"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
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

   # Possible outputs:
    # MVCRStatus::NotInstalled  -> No version found, needs to be installed
    # MVCRStatus::Outdated      -> Outdated version found, needs to be uninstalled and updated
    # MVCRStatus::UpToDate      -> Newest version found, nothing to do
    

    $VCKeys = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\17.0\VC\Runtimes\x64"
    )

    foreach ($Key in $VCKeys) {
        if (Test-Path $Key) {
            $Installed = Get-ItemProperty -Path $Key -Name "Installed" -ErrorAction SilentlyContinue
            $Version = Get-ItemProperty -Path $Key -Name "Version" -ErrorAction SilentlyContinue  

            if ($Installed.Installed -eq 1) {

                if ($Version.Version) {
                    $VersionString = $Version.Version -replace "^v", ""
            
                    $InstalledVersion = [System.Version]$VersionString   

                    if ($InstalledVersion -ge $MVCR_min_version) {
                        Log-Status "Installed VC++ version ($InstalledVersion) is up-to-date."
                        return [MVCRStatus]::UpToDate
                    }
                }
                return [MVCRStatus]::Outdated
            }
        }
    }
    return [MVCRStatus]::NotInstalled
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

    # Function to install Microsoft Visual C++ Redistributable and resolve SYMENGINE dependency


    $MVCR_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $MVCR_Installer_Path = "$env:TEMP\vc_redist.x64.exe"



    Log-Status 'Downloading Microsoft Visual C++ Redistributable installer'

    # Download the installer
    try {
    Download-File $MVCR_URL $MVCR_Installer_Path
    } catch {
        $err_msg = (
            "Download file of Visual C++ inside the Install-MVCR function failed",
            "Manual check required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }

    # Run the installer silently
    try {
    $process = Start-Process -FilePath $MVCR_Installer_Path -ArgumentList "/quiet /norestart" -Verb RunAs -PassThru -Wait
    } catch {
        $err_msg = (
            "Installation failed inside the Install-MVCR function",
            "Manual check required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }

    if ($process.ExitCode -ne 0) {
        Log-Err 'fatal' "Error inside Install-MVCR function" "User refused to give admin rights to install Visual C++"
    }


    # Remove the installer after installation
    try {
    Remove-Item -Path $MVCR_Installer_Path -Force
    } catch {
        $err_msg = (
            "Couldn't remove installer in $MVCR_Installer_Path",
            "Manual check required"
            ) -join "`r`n"
        Log-Err 'warn' $err_msg $($_.Exception.Message)
    }

}


function Install-VSCode {
    $VSCode_installer = 'vscode_installer.exe'
    $VSCode_installer_path = Join-Path ${env:TEMP} -ChildPath $VSCode_installer
    # Download the local installer by appending '-user' to the download URL:
    $VSCode_URL = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user'

    # Download VSCode

    Log-Status 'Downloading VSCode installer'

    try {
        Download-File $VSCode_URL $VSCode_installer_path
    }
    catch {
        $err_msg = (
            "Download file of VS Code inside the Install-VScode function failed",
            "Manual check required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message) 
    }
    # Install VSCode
    Log-Status 'Running VSCode installer'
    $unattended_args = '/VERYSILENT /MERGETASKS=desktopicon,addtopath,!runcode'

    try {
        Start-Process -FilePath $VSCode_installer_path -ArgumentList $unattended_args -Wait -Passthru
    } catch {
        $err_msg = (
            "Installation of VScode insinde the Install-VScode  function failed",
            "Manual check required"
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }

    try {
        Remove-Item $VSCode_installer_path
    }
    catch {
        $err_msg = (
        "Cleaning of VSCode_installer path failed inside Install-VScode function failed",
        "Manual check required"
        ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)

    }
    Log-Status 'DONE'
}


function Install-VSCode-Extension {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = 'Name of VSCode extension to install')]
        [string]$ext
    )

    if ( $(@(code --list-extensions | ? { $_ -match $ext }).Count -ge 1) ) {
        Log-Status "VSCode extension $ext already installed"
        return
    }
    
    try {
        Invoke-Native code --install-extension $ext
    }
    catch {
        Log-Err 'fatal' "VS Ccode extension $ext failed insidine Install-VSCode-Extension function" $($_.Exception.Message)
    }
}


function Install-pyenv-win {

    Log-Status 'Downloading pyenv-win'

    $pyenv_installer = 'install_pyenv_win.ps1'
    $pyenv_installer_path = Join-Path ${env:TEMP} -ChildPath $pyenv_installer
    $pyenv_win_URL = 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1'

    try {
        Download-File $pyenv_win_URL $pyenv_installer_path
    } catch {
        $err_msg = (
            "Download-call error inside the Install-pyenv-win function",
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)
    }

    $pyvenv_test_path = Join-Path ${env:USERPROFILE} -ChildPath '.pyenv'


    if ((Test-Path $pyvenv_test_path)) { 
        try {
            Remove-Item -Recurse -Force $pyvenv_test_path
        } catch {
            $err_msg = (
                "Error removing $pyvenv_test_path inside the Install-pyenv-win function",
                'Manual check required.'
                ) -join "`r`n"
            Log-Err 'fatal' $err_msg $($_.Exception.Message)        
        }
    }

    

    Log-Status 'Installing pyenv-win'
    try {
        & "${pyenv_installer_path}"
    }
    catch {
        Log-Err 'fatal' "./{pyenv_installer} failed inside the Install-pyenv-win function" $($_.Exception.Message)
    }

    # Cleanup
    try {
        Remove-Item $pyenv_installer_path
    } catch {
        $err_msg = (
                "Error removing $pyenv_installer_path inside the Install-pyenv-win function",
                'Manual check required.'
                ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message) 
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
        $versions = Invoke-Native pyenv install -l
    }
    catch {
        Log-Err 'fatal' 'pyenv install -l failed inside Check-pyenv-List function' $($_.Exception.Message)
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

    $need_refesh = $false  # Will be set to $true if pyenv cache is outdated
    $now = Get-Date

    if (!(Test-Path $stamp)) {
        # $stamp file does not exist, we never refreshed the cache
        $need_refresh = $true
    } else {
        # $stamp exists, determine whether the last check is past long enough
        # to warrant re-checking.
        $found = switch -File $stamp -RegEx {
            '^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d$' {
                $timestamp = $matches[0]
                $true
                break }
            }
        if ( !$found ) {
            # $stamp does not contain a valid timestamp -> error out
            $err_args = 'fatal',
                'reading out timestamp of last pyenv cache update',
                'The timestamp file is corrupted.',
                "Path: $stamp"
            Log-Err @err_args
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
        $discard = Invoke-Native pyenv update
    }
    catch {
        Log-Err 'fatal' 'pyenv update failed inside the Lookup-pyenv-Cache function' $($_.Exception.Message)
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
        Invoke-Native python -c "import symengine"
        Log-Status 'PASSED'
    }
    catch {
        Log-Err 'fatal' 'symengine module test' $($_.Exception.Message)
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
        $v = Invoke-Native python -c $py_cmd
    }
    catch {
        Log-Err 'warn' 'Qiskit version test failed' $($_.Exception.Message)
    }

    if ( $v -eq $qiskit_version ) {
        Log-Status "Detected Qiskit version number $v"
    } else {
        Log-Err 'warn' 'Qiskit version number check failed' $($_.Exception.Message)
    }
}


function Setup-Qiskit {

    param (
        [Parameter(
            Mandatory = $true,
            Position = 1)]
        [string]$qiskit_output
    )

    if ($qiskit_output -eq "qiskit_1.4.2 (latest)") {
        $qiskit_output = "qiskit_1.4.2"
    }

    $qiskit_version = $qiskit_output.Replace("qiskit_", "")

    # Name of venv in .virtualenvs
    $qwi_vstr = 'qiskit_' + $qiskit_version.Replace('.', '_')

    $requirements_file = 'requirements_'+ $qwi_vstr +'.txt'
    #$requirements_file = "symeng_requirements.txt"

    $req_URL = "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/resources/config/${requirements_file}"

    return $qiskit_version, $qwi_vstr, $requirements_file, $req_URL
}


# ===============================================
# ================ CONFIG WINDOW ================
# ===============================================

function Config-window{
    Add-Type -AssemblyName PresentationFramework

    $window = New-Object System.Windows.Window
    $window.Title = "Qiskit Windows Installer"
    $window.Width = 900
    $window.Height = 800
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(35, 35, 35))  



    # Logo ImageBlock
    $logoBlock = New-Object System.Windows.Controls.Image
    $logoBlock.HorizontalAlignment = "Center"

    # Create a BitmapImage and set the Uri to the raw GitHub image URL
    $logoBlock.Margin = [System.Windows.Thickness]::new(0,-40,0,0)

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
    $textBlock.Margin = [System.Windows.Thickness]::new(-20,-100,10,0)
    $textBlock.FontSize = 20  
    $textBlock.HorizontalAlignment = "Center"
    $textBlock.FontStyle = [System.Windows.FontStyles]::Italic
    $textBlock.FontFamily = "Segoe UI"  
    $textBlock.Foreground = [System.Windows.Media.Brushes]::White  


    # Notice TextBlock
    $textBlock2 = New-Object System.Windows.Controls.TextBlock
    $textBlock2.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textBlock2.Margin = [System.Windows.Thickness]::new(10,-30,30,20)
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
        $textBlock.FontSize = 16
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
    $checkBoxVSCode = Create-CheckboxWithLink "VSCode" "(VSCode EULA)" "https://code.visualstudio.com/license"
    $checkBoxPython = Create-CheckboxWithLink "Python" "(Python License Agreement)" "https://docs.python.org/3/license.html"
    $checkBoxQiskit = Create-CheckboxWithLink "Qiskit" "(Qiskit License Agreement)" "https://quantum.ibm.com/terms"
    $checkBoxPyenv = Create-CheckboxWithLink "Pyenv-win" "(Pyenv License Agreement)" "https://github.com/pyenv-win/pyenv-win/blob/master/LICENSE"
    $checkBoxVisualC = Create-CheckboxWithLink "Visual C++ Redistributable" "(Visual C++ License Agreement)" "https://visualstudio.microsoft.com/license-terms/vs2022-cruntime/"
    $checkBoxInstaller = Create-CheckboxWithLink "Qiskit Windows Installer" "(Installer License Agreement)" "https://github.com/ket-q/qiskit_windows_installer/blob/main/LICENSE"



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
            } else {
            $buttonProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
            $buttonProceed.Foreground = [System.Windows.Media.Brushes]::White
            $borderProceed.Background = [System.Windows.Media.Brushes]::DarkGreen
        }
    })



    $buttonProceed.IsEnabled = $false

    # Notice TextBlock
    $textQiskit = New-Object System.Windows.Controls.TextBlock
    $textQiskit.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textQiskit.Margin = [System.Windows.Thickness]::new(10,0,30,0)
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
    @("qiskit_1.4.2 (latest)", "qiskit_1.3.2") | ForEach-Object {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Content = $_
        $item.FontSize = 20
        $null = $comboBox.Items.Add($item)
    }

    # Event handler for selection changed
    $comboBox.Add_SelectionChanged({
        $selectedItem = $comboBox.SelectedItem
        $global:qiskit_selection = $($selectedItem.Content)

        if ($selectedItem -ne $null) {
            $global:checkSelection = $true
        }

        & $checkBoxChangedHandler
    })


    # Checkbox event handler
    $checkBoxChangedHandler = {
        if ($checkBoxVSCode.IsChecked -and $checkBoxPython.IsChecked -and $checkBoxQiskit.IsChecked -and $checkBoxPyenv.IsChecked -and $checkBoxInstaller.IsChecked -and $checkBoxVisualC.IsChecked -and $global:checkSelection) {
            $buttonProceed.IsEnabled = $true
        } else {
            $buttonProceed.IsEnabled = $false
        }
    }

    $checkBoxVSCode.Add_Checked($checkBoxChangedHandler)
    $checkBoxPython.Add_Checked($checkBoxChangedHandler)
    $checkBoxQiskit.Add_Checked($checkBoxChangedHandler)
    $checkBoxPyenv.Add_Checked($checkBoxChangedHandler)
    $checkBoxInstaller.Add_Checked($checkBoxChangedHandler)
    $checkBoxVisualC.Add_Checked($checkBoxChangedHandler)


    $checkBoxVSCode.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxPython.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxQiskit.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxPyenv.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxInstaller.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxVisualC.Add_Checked($checkBoxChangedHandler)






    # StackPanel Layout
    $stackPanel = New-Object System.Windows.Controls.StackPanel
    $null = $stackPanel.Children.Add($logoBlock)
    $null = $stackPanel.Children.Add($textBlock)
    $null = $stackPanel.Children.Add($textBlock2)
    $null = $stackPanel.Children.Add($checkBoxVSCode)
    $null = $stackPanel.Children.Add($checkBoxPython)
    $null = $stackPanel.Children.Add($checkBoxQiskit)
    $null = $stackPanel.Children.Add($checkBoxPyenv)
    $null = $stackPanel.Children.Add($checkBoxVisualC)
    $null = $stackPanel.Children.Add($checkBoxInstaller)
    $null = $stackPanel.Children.Add($textQiskit)
    $null = $stackPanel.Children.Add($comboBox)
    $null = $stackPanel.Children.Add($borderProceed)
    $null = $stackPanel.Children.Add($borderCancel)

    $window.Content = $stackPanel

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

    Log-Status "Qiskit_version = $global:qiskit_selection"


    if ($global:acceptedLicense) {
        Log-Status "User accepted the license agreements."
        return $true , $qiskit_selection
    } else {
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
    Log-Err 'fatal' 'Install script execution policy failed at Step 1' $($_.Exception.Message)
}

#
# Step 2: Check installation plaform
#

Write-Header 'Step 2/18: Check installation platform'
try {
    Check-Installation-Platform
} catch {
    Log-Err 'fatal' "Error when calling Check-Installation-Platform at Step 2" $($_.Exception.Message)
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
    Log-Err 'fatal' $err_msg $($_.Exception.Message) 

}

if (!$result){ #User didn't accept the software Licence, program should stop
    $err_msg = (
        'User refused the software licences or closed the window in Step 3',
        'Manual check required.'
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg
}

try {
    $qiskit_version, $qwi_vstr, $requirements_file, $req_URL = Setup-Qiskit $qiskit_output

} catch {
    $err_msg = (
        "Unable to setup qiskit Step 3",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message) 
}

#
# Step 4: Set up installer root directory structure
#

Write-Header 'Step 4/18: set up installer root folder structure'

try {
    if (!(Test-Path $ROOT_DIR)){
        New-Item -Path $ROOT_DIR -ItemType Directory
    }

} catch {
    $err_msg = (
        "Root folder setup error. Can't check $ROOT_DIR in Step 4",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message) 

}

try {
    $qinst_root_obj = get-item $ROOT_DIR

    # Check that $ROOT_DIR is a folder and not a file. Required if
    # the name already pre-existed in the filesystem.
    if ( !($qinst_root_obj.PSIsContainer) ) {
        $err_msg = (
            "$ROOT_DIR is not a folder.",
            "Please move $ROOT_DIR out of the way and re-run the script."
            ) -join "`r`n"
        Log-Err 'fatal' 'Setup installer root folder structure failed in Step 4' $err_msg
    }
} catch {
    $err_msg = (
        'Root folder setup failed in Step 4',
        "Can't check qinst_root_obj",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message) 
}

#
# Step 4a: Create log directory
#


Write-Header 'Step 4a/18: set up log folder'
try {
    if ( !(Test-Path $LOG_DIR) ) {
        # Log folder does not exist yet => create
        $discard = New-Item -Path $LOG_DIR -ItemType Directory
    }
    if ( !(Test-Path $LOG_FILE) ) {
        # Log file does not exist yet => create
        New-Item $LOG_FILE -ItemType File
    }
    # Flag that logging is up-and-running
    $discard = $log_up = $true
}
catch {
    $err_msg = (
        "'Setup of log folder failed in Step 4a.", 
        "Unable to set up $LOG_DIR.",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg  $($_.Exception.Message) 
}

#
# Step 4b: Set up the enclave folder 
#

Write-Header 'Step 4b/18: set up enclave folder'
try {
    $ENCLAVE_DIR = Join-Path $ROOT_DIR -ChildPath $qwi_vstr
    if (!(Test-Path $ENCLAVE_DIR)) {
         $err = New-Item -Path $ENCLAVE_DIR -ItemType Directory
    }
    $err = Set-Location -Path $ENCLAVE_DIR
}
catch {
    $err_msg = (
        "Setup of enclave folder failed in Step 4b",
        "Unable to cd into $ENCLAVE_DIR.",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message) 
}

#
# Step 5: Visual C++ Redistributable
#


Write-Header 'Step 5/18 Installing Visual C++ Redistributable'

$CheckResult = Check-MVCR

switch ($CheckResult) {
    ([MVCRStatus]::NotInstalled) {
        Log-Status "Microsoft Visual C++ Redistributable is not installed at all"
        try {
            Install-MVCR
        } catch {
            $err_msg = (
                "Installation of Visual C++ failed in Step 5.1",
                "Manual intervention required."
            ) -join "`r`n"
            Log-Err 'fatal' $err_msg $($_.Exception.Message) 
        }
    }

    ([MVCRStatus]::Outdated) {
        Log-Status "An older version of Microsoft Visual C++ Redistributable is installed."
        try {
            Uninstall-MVCR
            Install-MVCR
        } catch {
            $err_msg = (
                "Installation of Visual C++ failed in Step 5.1",
                "Manual intervention required."
            ) -join "`r`n"
            Log-Err 'fatal' $err_msg $($_.Exception.Message) 
        }
    }

    ([MVCRStatus]::UpToDate) {
        Log-Status "Latest version is already installed"
    }
}

#
# Step 6: Visual Studio Code
#

Write-Header 'Step 6/18: Install VSCode'
if ( !(Get-Command code -ErrorAction SilentlyContinue) ) {
    Log-Status 'VSCode not installed, running installer'
    Install-VSCode
    Refresh-PATH
    # Ensure VScode installation succeeded:
    if ( !(Get-Command code -ErrorAction SilentlyContinue) ) {
        $err_msg = (
            'VSCode installation failed in Step 6',
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg
    } else {
        Log-Status 'VSCode installation succeeded'
    }
} else {
    Log-Status 'VSCode already installed'
}

Log-Status 'Installing VSCode Python extension'
Install-VSCode-Extension 'ms-python.python'

Log-Status 'Installing VSCode Jupyter extension'
Install-VSCode-Extension 'ms-toolsai.jupyter'

#
# Step 7: pyenv-win
#
Write-Header 'Step 7/18: Install pyenv-win'
if ( !(Get-Command pyenv -ErrorAction SilentlyContinue) ) {
    Log-Status 'pyenv-win not installed, running installer'
    Install-pyenv-win
    Refresh-PATH
    Refresh-pyenv_Env
    # Ensure pyenv-win installation succeeded:
    if ( !(Get-Command pyenv -ErrorAction SilentlyContinue) ) {
        $err_msg = (
            'pyenv-win installation failed inside Step 7',
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' $err_msg $($_.Exception.Message)  
    } else {
        Log-Status 'pyenv-win installation succeeded'
    }
} else {
    Log-Status 'pyenv-win already installed'
}

#
# Step 8: pyenv support Python version
#

Write-Header "Step 8/18: Check if pyenv supports Python $python_version"
if ( !(Lookup-pyenv-Cache $python_version $ROOT_DIR) ) {
    $err_msg = (
        "availability-check of Python failed in Step 7",
        "Requested Python version $python_version not available with pyenv.",
        "Manual check required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)      
}

#
# Step 9: Setup Python for venv
#

Write-Header "Step 9/18: Set up Python $python_version for venv"
try {
    $err = Invoke-Native pyenv install $python_version
    $err = Invoke-Native pyenv local $python_version
}
catch {
    Log-Err 'fatal' 'Python installation for pyenv failed in Step 9' $($_.Exception.Message)   
}

try {
# Make sure that user's '.virtualenvs' folder exists or otherwise create it.
$DOT_VENVS_DIR = Join-Path ${env:USERPROFILE} -ChildPath '.virtualenvs'
if (!(Test-Path $DOT_VENVS_DIR)){
    New-Item -Path $DOT_VENVS_DIR -ItemType Directory
}

} catch {
    $err_msg = (
        "Check that .virtualenvs exists failed in Step 9",
        "Manual check required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}
try {
    $dot_venvs_dir_obj = get-item $DOT_VENVS_DIR
} catch {
    $err_msg = (
        "Can't get-item DOT_VENVS_DIR in Step 9",
        "Manual check required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

try {
    # Check that '.virtualenvs' is a folder and not a file. Required if
    # the name already pre-existed in the filesystem.
    if ( !($dot_venvs_dir_obj.PSIsContainer) ) {
        $err_msg = (
            "$DOT_VENVS_DIR is not a folder.",
            "Please move $DOT_VENVS_DIR out of the way and re-run the script."
            ) -join "`r`n"
        Log-Err 'fatal' '.virtualenvs check' $err_msg
    }
} catch {
    $err_msg = (
        "Check that .virtualenvs exists failed in Step 9",
        "Manual check required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
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
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
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
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 10: Download requirements_file
#

Write-Header "Step 10/18: Download $requirements_file from $req_URL"

try {
# Download the requirements.txt file for the new venv
Download-File $req_URL ${requirements_file}

if ((Get-Content $requirements_file -TotalCount 1).Substring(0,3) -eq '404') {
    $err_msg = (
        "The download file $requirements_file contains a 404 error at Step 10",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg "404 error"
}

} catch {
    $err_msg = (
        "Download of requirements file failed at Step 9",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 11: Set up venv
#

# Create venv
Write-Header "Step 11/18: Set up venv $MY_VENV_DIR"
try {
    # create venv
    Invoke-Native pyenv exec python -m venv $MY_VENV_DIR
    # activate venv
    Invoke-Native "${MY_VENV_DIR}\Scripts\activate.ps1"
}
catch {
    $err_msg = (
        "Setting up venv failed at Step 11",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 12: Update pip of venv
#

Write-Header "Step 12/18: update pip of venv $MY_VENV_DIR"
try {
    Invoke-Native python -m pip install --upgrade pip
}
catch {
    $err_msg = (
        "Pip update failed at Step 12",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'warn' $err_msg $($_.Exception.Message)
} 

#
# Step 13: Install Qiskit in venv
#

Write-Header "Step 13/18: install Qiskit in venv $MY_VENV_DIR"
try {   
    Invoke-Native pip install -r $requirements_file
}
catch {
    $err_msg = (
        "Installation of Qiskit in venv $MY_VENV_DIR failed at Step 13",
        "Pip couldn't install the requirements_file",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 14: Install ipykernel module in venv
#

Write-Header "Step 14/18: install ipykernel module in venv $MY_VENV_DIR"
try {
    Invoke-Native pip install ipykernel
}
catch {
    $err_msg = (
        "Installation of ipykernel module in venv $MY_VENV_DIR failed at Step 14",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 15: Install ipykernel kernel in venv
#

Write-Header "Step 15/18: install ipykernel kernel in venv $MY_VENV_DIR"
try {
    $python_args = "-m", "ipykernel", "install",
        "--user",
        "--name=$qwi_vstr",
        "--display-name", "`"$qwi_vstr`""
    # splat $args array (@args):
    Invoke-Native python @python_args
}
catch {
    $err_msg = (
        "Installation of ipykernel in venv $MY_VENV_DIR failed at Step 15",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
}

#
# Step 16: Write installer version in pyvenv.cfg
#

Write-Header "Step 16/18: Write installer version in pyvenv.cfg"

try {
    $cfg_path = "$MY_VENV_DIR\pyvenv.cfg"
    Add-Content $cfg_path "qiskit_windows_installer_version = $QISKIT_WINDOWS_INSTALLER_VERSION"
} catch {

    $err_msg = (
        "Writing of installer version in pyvenv.cfg failed at Step 16",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'warn' $err_msg $($_.Exception.Message)
    
}

#
# Step 17: Test the installation
#
Write-Header "Step 17/18: testing the installation in $MY_VENV_DIR"
Test-symeng-Module
try {
    Invoke-Native "${MY_VENV_DIR}\Scripts\activate.ps1"
    Test-qiskit-Version
} catch {
    $err_msg = (
        "Error for Test-Qiskit-version function at Step 17",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'warn' $err_msg $($_.Exception.Message)
}


# Deactivate the Python venv
try {
   Invoke-Native deactivate
}
catch {
    $err_msg = (
        "Error when deactivating the python venv at Step 17",
        "Manual intervention required"
        ) -join "`r`n"
    Log-Err 'fatal' $err_msg $($_.Exception.Message)
} 

#
# Step 18: Open VS code with the notebook
#

Write-Header "Step 18/18: Open Visual Studio code with the notebook"
try {

    $NoteBookURL = "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/resources/notebook/IBM_account_setup.ipynb"
    Invoke-WebRequest -Uri $NoteBookURL -OutFile "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb"
    Invoke-Native code --disable-workspace-trust 
    Start-Sleep -Seconds 2
    Invoke-Native code  --reuse-window "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb"

}
catch {
    Log-Err 'fatal' 'Error during VS code opening' $($_.Exception.Message)
}

Log-Status "INSTALLATION DONE"
Log-Status "You can close this window."