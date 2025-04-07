# Top-level folder of installer to keep files other than the venvs:
$ROOT_DIR = Join-Path ${env:LOCALAPPDATA} -ChildPath 'qiskit_windows_installer'



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


function Uninstall-VSCode {
    $uninstaller = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\unins000.exe"

    if (Test-Path $uninstaller) {
        Log-Status 'Uninstalling VSCode'
        Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT' -Wait -Passthru
        Log-Status 'VSCode Uninstalled'
    } else {
        Log-Status 'VSCode uninstaller not found'
    }
}


function Uninstall-pyenv-win {

    Log-Status 'Checking for pyenv-win installation...'

    $pyenvRoot = "$env:USERPROFILE\.pyenv"

    if (Test-Path $pyenvRoot) {
        Log-Status "Found pyenv-win at $pyenvRoot. Removing..."

        # Remove the pyenv-win directory
        Remove-Item -Path $pyenvRoot -Recurse -Force

        Log-Status 'Removed pyenv-win files.'
    } else {
        Log-Status 'pyenv-win directory not found. Nothing to remove.'
    }
    # Clean up environment variables and PATH
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

    $pyenvBin   = "$env:USERPROFILE\.pyenv\pyenv-win\bin"
    $pyenvShims = "$env:USERPROFILE\.pyenv\pyenv-win\shims"

    if ($userPath -like "*$pyenvBin*" -or $userPath -like "*$pyenvShims*") {

        Log-Status 'pyenv-win PATH entries found. Cleaning...'

        # Split path entries, filter out pyenv paths
        $cleanPathArray = $userPath -split ';' | Where-Object {
            ($_ -ne $pyenvBin) -and ($_ -ne $pyenvShims)
        }

        # Rebuild PATH string safely, even if cleanPathArray is empty
        $cleanPath = ($cleanPathArray -join ';').Trim(';')

        # Update the PATH environment variable
        [Environment]::SetEnvironmentVariable('Path', $cleanPath, 'User')

        Log-Status 'Cleaned pyenv-win entries from PATH.'
    } else {
        Log-Status 'No pyenv-win PATH entries found.'
    }

    # Remove environment variables PYENV, PYENV_HOME, PYENV_ROOT
    [Environment]::SetEnvironmentVariable('PYENV', $null, 'User')
    [Environment]::SetEnvironmentVariable('PYENV_HOME', $null, 'User')
    [Environment]::SetEnvironmentVariable('PYENV_ROOT', $null, 'User')

    Log-Status 'Removed PYENV, PYENV_HOME, PYENV_ROOT environment variables.'



        Log-Status 'pyenv-win uninstall complete.'
}



#
# Main
#
Write-Header 'Step 1/9: Set install script execution policy'
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force
}
catch {
    Log-Err 'fatal' 'install script execution policy' $($_.Exception.Message)
}

Write-Header 'Step 2/9: delete installer root folder structure'


if (Test-Path $ROOT_DIR) {
    Remove-Item -Path $ROOT_DIR -Recurse -Force
}

Write-Header 'Step 3/9: Uninstall VSCode'

try {
    if ((Get-Command code -ErrorAction SilentlyContinue) ) {
        Log-Status 'VSCode installed, running uninstaller'
        
        Uninstall-VSCode
        # Ensure VScode installation succeeded:
        if ((Get-Command code -ErrorAction SilentlyContinue) ) {
            $err_msg = (
                'VSCode uninstallation failed.',
                'Manual check required.'
                ) -join "`r`n"
            Log-Err 'fatal' 'VSCode uninstallation' $err_msg
        } else {
            Log-Status 'VSCode uninstallation succeeded'
        }
    } else {
        Log-Status 'VSCode already deleted'
    }
} catch {
    Log-Err 'fatal' 'Error uninstalling VScode' $($_.Exception.Message)
}

$CODE_DIR = Join-Path ${env:APPDATA} -ChildPath 'Code'

try {
    if(Test-Path $CODE_DIR){
        Remove-Item -Recurse -Force -Path $CODE_DIR
    }
} catch {
    Log-Status $($_.Exception.Message)
}


$CODE_DIR_LOCAL = Join-Path ${env:USERPROFILE} -ChildPath '.vscode'

try {
    if(Test-Path $CODE_DIR_LOCAL){
        Remove-Item -Recurse -Force -Path $CODE_DIR_LOCAL
    }
} catch {
    Log-Status $($_.Exception.Message)
}




Write-Header 'Step 4/9: Uninstall pyenv-win'
if ((Get-Command pyenv -ErrorAction SilentlyContinue) ) {
    Log-Status 'pyenv-win installed, running uninstaller'
    Uninstall-pyenv-win
    
    
    # Ensure pyenv-win installation succeeded:
    if ((Get-Command pyenv -ErrorAction SilentlyContinue) ) {
        $err_msg = (
            'pyenv-win uninstallation failed.',
            'Manual check required.'
            ) -join "`r`n"
        Log-Err 'fatal' 'pyenv-win uninstallation' $err_msg
    } else {
        Log-Status 'pyenv-win uninstallation succeeded'
    }
} else {
    Log-Status 'pyenv-win already uninstalled'
}


Write-Header 'Step 5/9: Uninstalling .ipython'

try {
    $IPYTHON_PATH = Join-Path ${env:USERPROFILE} -ChildPath '.ipython'
    if (Test-Path $IPYTHON_PATH){
        Remove-Item -Recurse -Force -Path $IPYTHON_PATH
    }
}
catch {
    Log-Status $($_.Exception.Message)
}



Write-Header 'Step 6/9: Uninstalling .virtualsenv'

try {
    $DOT_VENVS_DIR = Join-Path ${env:USERPROFILE} -ChildPath '.virtualenvs'
    if (Test-Path $DOT_VENVS_DIR){
        Remove-Item -Recurse -Force -Path $DOT_VENVS_DIR
    } 
} catch {
    Log-Status $($_.Exception.Message)
}

Write-Header 'Step 7/9: Uninstalling Jupyter in Roaming'

$JUPYTER_CODE = Join-Path ${env:APPDATA} -ChildPath 'Jupyter'

try {
    if(Test-Path $JUPYTER_CODE){
        Remove-Item -Recurse -Force -Path $JUPYTER_CODE
    }
} catch {
    Log-Status $($_.Exception.Message)
}

Write-Header 'Step 8/9: Uninstalling pip in Local'

$PIP_CODE = Join-Path ${env:LOCALAPPDATA} -ChildPath 'pip'

try {
    if(Test-Path $PIP_CODE){
        Remove-Item -Recurse -Force -Path $PIP_CODE
    }
} catch {
    Log-Status $($_.Exception.Message)
}

Write-Header 'Step 9/9: Uninstalling qiskit in Users'


$QISKIT_PATH = Join-Path ${env:USERPROFILE} -ChildPath '.qiskit'

try {
    if(Test-Path $QISKIT_PATH){
        Remove-Item -Recurse -Force -Path $QISKIT_PATH
    }
} catch {
    Log-Status $($_.Exception.Message)
}

Log-Status "UNINSTALLATION DONE"
Log-Status "You can close this window"

Start-Sleep -Seconds 600

