<div align="center">
  <h1 align="center">Qiskit Installer for WIndows</h1>
</div>

<div align="center">

  <!-- PROJECT LOGO -->
  <br />
    
  <img alt="QiskitWindowslogo" src="resources/assets/Logo.svg" width="700" height="300">
    
  <br />
</div>

##  📍 What is QIWI ?

QIWI, the **Q**iskit **I**nstaller for **WI**ndows, will set up Qiskit and a local copy of Visual Studio Code (VS Code) on your computer, with a ready-to-use Python virtual environment for Jupyter notebooks. After the installation, a Jupyter notebook
walks the user through the initial setup on the IBM Quantum Platform.

<br />

## ⚠️ Important Notices Before Using QIWI

- Only install software on a computer that is not production-level or mission-critical to you. (This is a general truth that does not pertain only to this installer.)

- You are recommended to install Qiskit in a **fresh user account** on your computer.
  - This will help insulate your Qiskit SDK from other software you may have already installed on your computer, particularly if your computer already has a complicated software installation history.
  - Please refer to this [tutorial video](https://www.youtube.com/watch?v=LpPZ1oBjsnM) on how to create a fresh user account.
  - Please log in under this account to install Qiskit.
  - **Note:** if you forego to create a fresh user account, there is still a very
    high likelyhood for your installation to succeed. But you effectively omit one
    safety-net to safe-guard your existing computer configuration and insulate
    the Qiskit environment from software already installed on your computer. 

- Installation requirements for using QIWI:

  - Windows 11 or Windows 10 on the x86 platform
  - At least 4GB of free disk space
  - PowerShell 5.1 (comes pre-installed with both Windows 11 and 10)

<br />


## 💥 Installation
<!---
### 📷  Watch the Youtube tutorial to install Qiskit!

**Video coming soon**

---
-->
### 🏃 Running the Installer  


- **Method 1:** (recommended if you're fine with downloading and executing an executable on your computer):

  - Download and execute qiskit_installer.exe ([click here](https://github.com/ket-q/qiskit_windows_installer_pub/raw/refs/heads/main/qiskit_installer.exe)).
  - Windows may present you with a security warning in a blue box because it considers the installer as a security thread. To proceed with the installation,
  please click on "More information" and "Execute anyway".



  
- **Method 2:** (if you want visibility into the script you will execute on your computer): Run the provided installation script with Windows PowerShell.

  **Step 1**: Open a PowerShell console window
  - Type ``PowerShell`` in the Windows search bar and click ``Windows PowerShell`` (the blue square with the white '>' prompt).  

   **Step 2:** Copy the following command into the clipboard (by clicking
   on the square symbol in the right corner):
  
  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process -Force; if($?) { irm "https://github.com/ket-q/qiskit_windows_installer/raw/refs/heads/main/qiskit_installer.ps1" | iex}
  ```


  **Step 3:** Paste the command from the clipboard into
   your PowerShell console window (click on the PowerShell console window
   and press CTRL+ V, followed by ENTER). 

---


### 🚶 Step-by-step Guide Through the Installation Process: 

#### Step 1️⃣: License Agreements and Qiskit Version Selection
A configuration window will present you with the license agreements of all software packages that will be installed on your computer.

Depending on pre-installed software, the installation will include at the maximum
1. the Qiskit SDK,
2. a version of Python that matches the Qiskit SDK,
3. Pyenv-win ([link](https://github.com/pyenv-win/pyenv-win)), for the local management of multiple Python installations,
4. the VS Code editor ([link](https://code.visualstudio.com/)), and
4. the Microsoft Visual C++ Redistributable (MVCR, ([link](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170))), a set of DLLs that Qiskit modules such as Symengine depend upon.

You are asked to review and accept each license agreement. You need to select the version of Qiskit that you want to install.

![GIF aceppting licenses](https://github.com/ket-q/qiskit_windows_installer/blob/main/resources/assets/accepting.gif)


#### Step 2️⃣: Software Download and Installation

- Download and setup of Qiskit and will require selveral minutes, depending on the speed of your internet connection and your computer.

- If the installation includes MVCR, the Windows User Account Control (UAC) will ask for your confirmation. Otherwise the installation can run unattended.

#### Step 3️⃣: IBM Quantum Platform Access Setup. 

Once the installation is complete, VS Code will automatically open with a Jupyter notebook that walks you throught the setup of your API token for the IBM Quantum Platform.
This Jupyter notebok includes:
- Selecting a Python interpreter for your Jupyter notebook
- Adding your IBM Quantum API token to the Qiskit installation on your
  local computer. 


*You can also download the setup [notebook](https://github.com/ket-q/qiskit_windows_installer/blob/main/resources/notebook/IBM_account_setup.ipynb) manually. Click on the ``download raw file'' button next to the pen (top-right)*



## ✏️ Use of the Installed Qiskit SDK
### With Jupyter Notebooks
For every new Jupyter notebook that uses Qiskit, you will have to select the fitting Python interpreter to use:

 1. In the top-right corner of the Jupyter notebook window, click on "Select Kernel"

 2. Click on "Python Environments..."

 3. In the drop-down list, select the Python environment name that starts with ``qiskit_``, followed by the Qiskit version you chose during installation.
    - Example: If during installation you chose version 1.4.2, your Python environment name will be ``qiskit_1_4_2``.
    
    - **Note:** It is **essential** to select the **correct** Python environment. VS Code may offer several alternative Python environments to you, but only the one starting with ``qiskit_`` contains your Qiskit installation.
   
![GIF aceppting licenses](https://github.com/ket-q/qiskit_windows_installer/blob/main/resources/assets/select.gif)
### With Python Source Code
Python source code in the form of ``*.py`` files that use Qiskit require you to select the fitting Python interpreter.

In VS Code,
1. open the command palette (Ctrl + Shift + P)
2. select "Python : select interpreter",
3. select our Qiskit environment "Python 3.* (Qiskit 1.*)"

You can now run Qiskit on Windows.


## 🔌 Technical information


### Location of Installed Software

The installer itself does not stay resident on your computer system.
Rather, it keeps
files isolated in your user account's ``${env:LOCALAPPDATA}`` folder to minimize possible
interference with existing system-wide and/or user-level software installations
you your computer.

The installer will create a Python virtual environment (venv) in ``${env:USERPROFILE}/.virtualenvs``.

## Troubleshooting
The installer has to step through many hoops to accomplish its task and may encounter network conditions or an environment on your local computer that constitute unforseen and unsurmountable problems. In the following, we provide general trouble-shooting guidelines as well as remedies for a few specific issues.

### General Guidelines

- Always run the installer on a Windows installation that is up-to-date.
Please refer to the following link on how to install the latest updates
on your computer ([link](https://support.microsoft.com/en-us/windows/install-windows-updates-3c5ae7fc-9fb6-9af1-1984-b5e0412c556a)).
- As discussed above, you are recommended to install Qiskit in a **fresh user account**.
Thereby you ensure that no pre-installed user-level software can interfere, particularly
through the ``$env:path`` variable.
- Re-running the installer after a failed attempt can sometimes remedy the problem. E.g., when the QIWI installer invokes the MVCR installer, the return value of MVCR may insinuate a problem when in fact the MVCR installation went well. When running the QIWI installer the second time, it will detect the installed MVCR and proceed with subsequent installation steps.
- Re-running the installer in a different network environment may help. E.g., on a slow, public WiFi the download of a package may time out due to network congestion. Re-running the installer
on an institutional or home network, and/or connecting via Ethernet (cable) may resolve
the problem.
- **Problem Diagnosis and Getting Help**

    The installer creates a log file on your local computer that can be used for diagnosing problems that occurred during the installation. The name of the log file is ``log.txt`` and can be accessed from a PowerShell console window as follows.
    ```powershell
    Set-Location "$env:localappdata/qiskit_windows_installer/log"
    cat log.txt
    ```
    Please be aware that this log by its very nature will contain private information, including your account user ID and the contents of your ``$env.path`` variable. The installer itself will not share any information from your computer (you can infer this from the source code of the [script](https://raw.githubusercontent.com/ket-q/qiskit_windows_installer/refs/heads/main/qiskit_installer.ps1)), but you may consider the contents of the log file before sharing it with others (e.g., if you want to ask for help).


### Specific Issues


**Microsoft Visual C++ Redistributable refuses to download (Error 28)** <br />
*This error may occur when you are connected to a network with a proxy or a network with specific network settings.*
<br />
Solution:
Download and install the Microsoft Visual C++ Redistributable manually from [here](https://aka.ms/vs/17/release/vc_redist.x64.exe) and rerun the QIWI installer.

**Visual studio code refuses to download (Error 28)** <br />
*This error may occur when you are connected to a network with a proxy or a network with specific network settings.*
<br />
Solution:
Download and install VS Code manually from [here](https://code.visualstudio.com/) and re-run the QIWI installer.

## FAQ
### Why does QIWI only provide specific Qiskit versions, such as version 1.3.2 and 1.4.2?
QIWI only supports Qiskit configurations and Python versions which have been tested by the QIWI developers. The configurations are curated to make sure that no missed dependencies
or incompatibilites arise with an installed SDK.
  
 

## 📜 Licenses

Please find the license of the Qiskit Windows Installer [here](https://github.com/ket-q/qiskit_windows_installer/blob/main/LICENSE).

In addition, you will be asked to accept (a subset of) the following licences during installation:
- [VS Code](https://code.visualstudio.com/license)
- [Qiskit](https://github.com/Qiskit/qiskit/blob/main/LICENSE.txt)
- [Python](https://docs.python.org/3/license.html#terms-and-conditions-for-accessing-or-otherwise-using-python)
- [Pyenv-win](https://pyenv-win.github.io/pyenv-win/#license-and-copyright)
- [Microsoft Visual C++ Redistributable](https://visualstudio.microsoft.com/license-terms/vs2022-cruntime/)
