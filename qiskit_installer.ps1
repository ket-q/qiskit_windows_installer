# Stop the script when a cmdlet or a native command fails
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$qiskit_windows_installer_version = '0.1.0'
$python_version = '3.12.9' # 3.13 not working because ray requires Python 3.12
$qiskit_version = '1.3.2'

# Name of venv in .virtualenvs
$qwi_vstr = 'qiskit_' + $qiskit_version.Replace('.', '_')

#
# Folders and files
#

# Name and URL of the requirements.txt file to download from GitHub:
$requirements_file = 'requirements_qiskit_1_3_2.txt'
#$requirements_file = "symeng_requirements.txt"
$req_URL = "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/resources/config/${requirements_file}"

# Top-level folder of installer to keep files other than the venvs:
$ROOT_DIR = Join-Path ${env:LOCALAPPDATA} -ChildPath 'qiskit_windows_installer'

# Log file name and full path and name to the log:
$LOG_DIR = Join-Path $ROOT_DIR -ChildPath 'log'
$LOG_FILE = Join-Path $LOG_DIR -ChildPath 'log.txt'

# Flag to keep track whether our log file is already in place and ready to
# be used. Initially this flag is $false. It will be set to $true as soon
# as the $LOG_FILE is known to exist.
$log_up = $false



function Output {
<#
.SYNOPSIS
Take a string and write it to the target location(s).
    
Parameters:
(1) $msg: the string to write out
(2) $target: a string containing the target(s) to write to. Possible targets
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
        if ( $log_up ) {        
            Add-content $LOG_FILE -value $msg
        }
        # else {
        #    Write-Host "DISCARD $msg"
        # }
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


function Fatal-Error {
    param(
        [Parameter(Mandatory=$true, Position=1, HelpMessage="The error message to write")]
        [string]$err_msg,

        [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Exit code of the program")]
        [int]$err_val
    )
    $first = $true
    ForEach ($line in $($err_msg -split "\r?\n|\r")) {
        if ($first) {
            Output "ERROR: $line"
            $first = $false
        } else {
            Output "       $line"
        }
    }
    Exit $err_val
}


function Log-Err {
<#
.SYNOPSIS
Take a variable-length list of error variables and output them one by one. If
the firstArg=='fatal', then terminate the script if any of the error variables
is non-empty.

Parameters:
(1) firstArg: 'fatal' or 'warn', to determine whether to terminate if any error
    variable is non-empty
(2) secondArg: a string containing an overall description what theses errors
    are about.
(3) listArgs: one or more error variables
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
        # Terminate the script
        Exit 1
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
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ( $arch -ne 'AMD64' ) {
        $err_msg = (
            "The installer currently only supports the 'AMD64' architecture",
            "But this computer is of architecture '$arch'."
            ) -join "`r`n"
        Log-Err 'fatal' 'Check-Install-Platform' $err_msg
    }

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

    # Use 'curl.exe' which is the Curl version provided on Win 10 and Win 11.
    # (The command 'curl' internally maps to Invoke-WebRequest.)
    # -L ... download across redirects
    try {
        Invoke-Native curl.exe --silent -L -o $target_name $source_URL
    }
    catch {
        $err_msg = (
            "File download from $source_URL failed.",
            "Manual check required."
            ) -join "`r`n"
        Log-Err 'fatal' 'file download attempt' $err_msg
    }

    Log-Status 'Download DONE'
}


function Install-VSCode {
    $VSCode_installer = 'vscode_installer.exe'
    $VSCode_installer_path = Join-Path ${env:TEMP} -ChildPath $VSCode_installer
    # Download the local installer by appending '-user' to the download URL:
    $VSCode_URL = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user'

    # Download VSCode
    Log-Status 'Downloading VSCode installer'
    Download-File $VSCode_URL $VSCode_installer_path

    # Install VSCode
    Log-Status 'Running VSCode installer'
    $unattended_args = '/VERYSILENT /MERGETASKS=!runcode'
    Start-Process -FilePath $VSCode_installer_path -ArgumentList $unattended_args -Wait -Passthru

    # Cleanup
    Remove-Item $VSCode_installer_path

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
        Log-Err 'fatal' "code extension $ext" $($_.Exception.Message)
    }
}


function Install-pyenv-win {

    Log-Status 'Downloading pyenv-win'

    $pyenv_installer = 'install-pyenv-win.ps1'
    $pyenv_installer_path = Join-Path ${env:TEMP} -ChildPath $pyenv_installer
    $pyenv_win_URL = 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1'

    Download-File $pyenv_win_URL $pyenv_installer

    Log-Status 'Installing pyenv-win'
    try {
        Invoke-Native "./${pyenv_installer}"
    }
    catch {
        Log-Err 'fatal' 'pyenv-win installation' $($_.Exception.Message)
    }

    # Cleanup
    Remove-Item $pyenv_installer

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
        Log-Err 'fatal' 'pyenv install -l' $($_.Exception.Message)
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
        Log-Err 'fatal' 'pyenv update' $($_.Exception.Message)
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
        Invoke-Native python -c 'import symengine'
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
        Log-Err 'warn' 'Qiskit version test' $($_.Exception.Message)
    }

    if ( $v -eq $qiskit_version ) {
        Write-Host "Detected Qiskit version number $v"
    } else {
        Log-Err 'warn' 'Qiskit version number check' 'Failed'
    }
}


function Licenses-window{
    Add-Type -AssemblyName PresentationFramework

    $window = New-Object System.Windows.Window
    $window.Title = "Qiskit Windows Installer"
    $window.Width = 800
    $window.Height = 600
    $window.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(35, 35, 35))  # Light black

    # Title TextBlock
    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = "Qiskit Windows Installer"
    $titleBlock.FontSize = 34
    $titleBlock.FontWeight = "Bold"  # Bold text
    $titleBlock.HorizontalAlignment = "Center"
    $titleBlock.Margin = [System.Windows.Thickness]::new(10)
    $titleBlock.FontFamily = "Segoe UI"  # Modern font
    $titleBlock.Foreground = [System.Windows.Media.Brushes]::White  # White text

    # Notice TextBlock
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = "The Qiskit Windows Installer will install the following software packages on your computer. You are required to agree with their license agreements to proceed:"
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textBlock.Margin = [System.Windows.Thickness]::new(10,30,30,30)
    $textBlock.FontSize = 20  # Reduced font size
    $textBlock.FontWeight = "Bold"  # Bold text
    $textBlock.FontFamily = "Segoe UI"  # Modern font
    $textBlock.Foreground = [System.Windows.Media.Brushes]::White  # White text

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
        $textBlock.FontWeight = "Bold"
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
        $button.FontWeight = "Bold"  # Bold text
        $button.FontFamily = "Segoe UI"  # Modern font
        $button.Background = [System.Windows.Media.Brushes]::$color
        $button.Foreground = [System.Windows.Media.Brushes]::White  # White text
        $button.BorderBrush = $color

        # Center the button within its container (prevent stretching)
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
    $borderProceed, $buttonProceed = Create-RoundedButton "Accept" "DarkGreen"
    $borderCancel, $buttonCancel = Create-RoundedButton "Cancel" "DarkRed"


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





    # Checkbox event handler
    $checkBoxChangedHandler = {
        if ($checkBoxVSCode.IsChecked -and $checkBoxPython.IsChecked -and $checkBoxQiskit.IsChecked -and $checkBoxPyenv.IsChecked -and $checkBoxInstaller.IsChecked) {
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

    $checkBoxVSCode.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxPython.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxQiskit.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxPyenv.Add_Unchecked($checkBoxChangedHandler)
    $checkBoxInstaller.Add_Unchecked($checkBoxChangedHandler)

    # StackPanel Layout
    $stackPanel = New-Object System.Windows.Controls.StackPanel
    $null = $stackPanel.Children.Add($titleBlock)
    $null = $stackPanel.Children.Add($textBlock)
    $null = $stackPanel.Children.Add($checkBoxVSCode)
    $null = $stackPanel.Children.Add($checkBoxPython)
    $null = $stackPanel.Children.Add($checkBoxQiskit)
    $null = $stackPanel.Children.Add($checkBoxPyenv)
    $null = $stackPanel.Children.Add($checkBoxInstaller)
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

    if ($global:acceptedLicense) {
        Write-Host "User accepted the license agreements."
        return $true
    } else {
        Write-Host "User cancelled or closed the window."
        return $false
    }


}




#
# Main
#
Write-Header 'Step 1/16: Set install script execution policy'
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force
}
catch {
    Log-Err 'fatal' 'install script execution policy' $($_.Exception.Message)
}

Write-Header 'Step 2/16: Check installation platform'
Check-Installation-Platform

#
# Set up installer root directory structure
#
Write-Header 'Step 3/16: set up installer root folder structure'
if (!(Test-Path $ROOT_DIR)){
    New-Item -Path $ROOT_DIR -ItemType Directory
}

$qinst_root_obj = get-item $ROOT_DIR

# Check that $ROOT_DIR is a folder and not a file. Required if
# the name already pre-existed in the filesystem.
if ( !($qinst_root_obj.PSIsContainer) ) {
    $err_msg = (
        "$ROOT_DIR is not a folder.",
        "Please move $ROOT_DIR out of the way and re-run the script."
        ) -join "`r`n"
    Fatal-Error $err_msg 1
}

# Create log directory
Write-Header 'Step 3a/16: set up log folder'
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
        "Unable to set up $LOG_DIR.",
        "Manual intervention required."
        ) -join "`r`n"
    Log-Err 'fatal' 'setup of log folder' $err_msg  
}

# Create the enclave folder $ROOT_DIR\$qwi_vstr. This is from where we
# set up the virtual environment.
Write-Header 'Step 3b/16: set up enclave folder'
try {
    $ENCLAVE_DIR = Join-Path $ROOT_DIR -ChildPath $qwi_vstr
    if (!(Test-Path $ENCLAVE_DIR)) {
         $err = New-Item -Path $ENCLAVE_DIR -ItemType Directory
    }
    $err = Set-Location -Path $ENCLAVE_DIR
}
catch {
    $err_msg = (
        "Unable to cd into $ENCLAVE_DIR.",
        "Manual intervention required."
        ) -join "`r`n"
    Fatal-Error $err_msg 1
}

#
# Get software license checked by user
#

Write-Header 'Step 4/16: check software licenses'


try {

    $result = Licenses-window

    if (!$result){ #User didn't accept the software Licence, program should stop
    $err_msg = (
        'User refused the software licence',
        'Manual check required.'
        ) -join "`r`n"
    Log-Err 'fatal' 'Licence acceptation' $err_msg
    }
} 
catch {

    $err_msg = (
        "Unable to open licence windows",
        "Manual intervention required."
        ) -join "`r`n"
    Fatal-Error $err_msg 1  

}



#
# VSCode
#
Write-Header 'Step 5/16: Install VSCode'
if ( !(Get-Command code -ErrorAction SilentlyContinue) ) {
    Log-Status 'VSCode not installed, running installer'
    Install-VSCode
    Refresh-PATH
    # Ensure VScode installation succeeded:
    if ( !(Get-Command code -ErrorAction SilentlyContinue) ) {
        $err_msg = (
            'VSCode installation failed.',
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' 'VSCode installation' $err_msg
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
# pyenv-win
#
Write-Header 'Step 6/16: Install pyenv-win'
if ( !(Get-Command pyenv -ErrorAction SilentlyContinue) ) {
    Log-Status 'pyenv-win not installed, running installer'
    Install-pyenv-win
    Refresh-PATH
    Refresh-pyenv_Env
    # Ensure pyenv-win installation succeeded:
    if ( !(Get-Command pyenv -ErrorAction SilentlyContinue) ) {
        $err_msg = (
            'pyenv-win installation failed.',
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' 'pyenv-win installation' $err_msg
    } else {
        Log-Status 'pyenv-win installation succeeded'
    }
} else {
    Log-Status 'pyenv-win already installed'
}

#
# We arrived in the enclave. Now
# (0) Make sure that pyenv supported Python list is up-to-date
# (1) Check that the Python version asked by the user exists in pyenv
# (2) Install the Python version asked by the user
# (3) create the bootstrap venv that contains pipenv etc.
# (4) Use pipenv to create the ``official'' venv visible to the user in VSCode
#

Write-Header "Step 7/16: Check if pyenv supports Python $python_version"
if ( !(Lookup-pyenv-Cache $python_version $ROOT_DIR) ) {
    $err_msg = (
        "Requested Python version $python_version not available with pyenv.",
        "Please check manually on Python.org if you believe that Python",
        "version $python_version should be available."
        ) -join "`r`n"
    Log-Err 'fatal' "availability-check of Python $python_version" $err_msg    
}

Write-Header "Step 8/16: Set up Python $python_version for venv"
try {
    $err = Invoke-Native pyenv install $python_version
    $err = Invoke-Native pyenv local $python_version
}
catch {
    Log-Err 'fatal' 'pyenv Python setup in enclave' $($_.Exception.Message)   
}

# Make sure that user's '.virtualenvs' folder exists or otherwise create it.
$DOT_VENVS_DIR = Join-Path ${env:USERPROFILE} -ChildPath '.virtualenvs'
if (!(Test-Path $DOT_VENVS_DIR)){
    New-Item -Path $DOT_VENVS_DIR -ItemType Directory
}

$dot_venvs_dir_obj = get-item $DOT_VENVS_DIR

# Check that '.virtualenvs' is a folder and not a file. Required if
# the name already pre-existed in the filesystem.
if ( !($dot_venvs_dir_obj.PSIsContainer) ) {
    $err_msg = (
        "$DOT_VENVS_DIR is not a folder.",
        "Please move $DOT_VENVS_DIR out of the way and re-run the script."
        ) -join "`r`n"
    Log-Err 'fatal' '.virtualenvs check' $err_msg
}

# Test whether a venv of name $qwi_vstr already exists and delete it.
# Note 1: VSCode etc. should not use the venv in that moment, but we don't
# actually check this.
# FIXME: If a Jupyter notebook is open, then the rm command on the venv
#        will fail.

$MY_VENV_DIR = Join-Path ${DOT_VENVS_DIR} -ChildPath $qwi_vstr

try {
    if (Test-Path $MY_VENV_DIR) {
        # A venv of that name seems to exist already -> remove
        #rm -R $MY_VENV_DIR
        # Remove-Item -Force -Recurse -Path $MY_VENV_DIR
        Get-ChildItem $MY_VENV_DIR -Recurse | Remove-Item -Force -Recurse
    }
}
catch {
    $err_1 = $($_.Exception.Message)
    $err_0 = (
        "Unable to remove existing venv.",
        "Path/venv: $MY_VENV_DIR"
        ) -join "`r`n"
    Log-Err 'fatal' $err_0 $err_1
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
    Log-Err 'fatal' 'cd into enclave folder' $err_msg  
}

# Download the requirements.txt file for the new venv
Download-File $req_URL ${requirements_file}

# Create venv
Write-Header "Step 9/16: Set up venv $MY_VENV_DIR"
try {
    # create venv
    Invoke-Native pyenv exec python -m venv $MY_VENV_DIR
    # activate venv
    Invoke-Native "${MY_VENV_DIR}\Scripts\activate.ps1"
}
catch {
    Log-Err 'fatal' 'setting up venv' $($_.Exception.Message)
}

#
# venv activated
# PATH now includes our venv
#

# Update pip of venv
Write-Header "Step 10/16: update pip of venv $MY_VENV_DIR"
try {
    Invoke-Native python -m pip install --upgrade pip
}
catch {
    Log-Err 'fatal' 'Update pip of venv $MY_VENV_DIR' $($_.Exception.Message)
}

# Install ipykernel module in venv
Write-Header "Step 11/16: install ipykernel module in venv $MY_VENV_DIR"
try {
    Invoke-Native pip install ipykernel
}
catch {
    $err = $($_.Exception.Message)
    $err_args = 'fatal',
        'ipykernel module installation in venv $MY_VENV_DIR',
        $err
    Log-Err @err_args
}

# Install Qiskit in venv
Write-Header "Step 12/16: install Qiskit in venv $MY_VENV_DIR"
try {   
    Invoke-Native pip install -r $requirements_file
}
catch {
    $err = $($_.Exception.Message)
    $err_args = 'fatal',
        'Qiskit installation in venv $MY_VENV_DIR',
        $err
    Log-Err @err_args
}

# Install Jupyter server in venv
Write-Header "Step 13/16: install ipykernel kernel in venv $MY_VENV_DIR"
try {
    $args = "-m", "ipykernel", "install",
        "--user",
        "--name=$qwi_vstr",
        "--display-name", "`"$qwi_vstr`""
    # splat $args array (@args):
    Invoke-Native python @args
}
catch {
    $err = $($_.Exception.Message)
    $err_args = 'fatal',
        'ipykernel installation in venv $MY_VENV_DIR',
        $err
    Log-Err @err_args
}

Write-Header "Step 14/16: Write installer version in pyvenv.cfg"

$cfg_path = "$MY_VENV_DIR\pyvenv.cfg"
Add-Content $cfg_path "qiskit_windows_installer_version = $qiskit_windows_installer_version"

# Test the installation
Write-Header "Step 15/16: testing the installation in $MY_VENV_DIR"
#Test-symeng-Module
Test-qiskit-Version

# Deactivate the Python venv
try {
   Invoke-Native deactivate
}
catch {
    Log-Err 'fatal' $($_.Exception.Message)
} 


Write-Header "Step 16/16: Open Visual Studio code with the notebook"
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ket-q/qiskit_windows_installer_pub/refs/heads/main/ressources/notebook/IBM_account_setup.ipynb" -OutFile "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb"
    Invoke-Native code --disable-workspace-trust 
    Start-Sleep -Seconds 2
    Invoke-Native code  --reuse-window "$env:USERPROFILE\Downloads\IBM_account_setup.ipynb"

    
}
catch {
    Log-Err 'fatal' $($_.Exception.Message)
}

Log-Status "INSTALLATION DONE"

Start-Sleep -Seconds 30

# Done
Exit 0
