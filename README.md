# PowerShell Config

My personal PowerShell configuration — including dotfiles, modules, themes, and additional setups to make the shell experience more comfortable and productive.

## Features

- Custom PowerShell profile (`Microsoft.PowerShell_profile.ps1`) for aliases, functions, and other tweaks  
- Additional modules in the `Modules/` folder  
- Themes / prompt / extra configuration through JSON files (`powershell.config.json`, `takuya.omp.json`, etc.)  
- `images/` folder for screenshots or visual references  

## Repository Structure

```
├── Modules/                 # Additional PowerShell modules
├── images/                  # Screenshots / visual references
├── Microsoft.PowerShell_profile.ps1  # Main PowerShell profile
├── powershell.config.json   # Main configuration file (theme, prompt, etc.)
├── takuya.omp.json          # Extra / alternative prompt configuration
└── README.md                # This documentation
```

## Requirements

- Windows / macOS / Linux with a recent version of PowerShell  
- Access to required modules (install via PowerShell Gallery or local modules if missing)  
- Permission to run PowerShell scripts (Execution Policy)  

## Installation & Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/itsmeowdev/powershell-config.git
   cd powershell-config
   ```

2. Copy or symlink the profile file to your PowerShell profile path:
   - Windows:
     ```powershell
     cp Microsoft.PowerShell_profile.ps1 $HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
     ```
   - macOS/Linux:
     ```bash
     cp Microsoft.PowerShell_profile.ps1 ~/.config/powershell/Microsoft.PowerShell_profile.ps1
     ```

3. Make sure the configuration files (`powershell.config.json`, `takuya.omp.json`) are located where referenced in your profile, or adjust the path accordingly.

4. Install the modules from the `Modules` folder if not already available:
   ```powershell
   Import-Module ./Modules/ModuleName
   ```
   Or from PowerShell Gallery:
   ```powershell
   Install-Module ModuleName -Scope CurrentUser
   ```

5. Reload your PowerShell profile:
   ```powershell
   . $PROFILE
   ```

## Additional Setup

- If you are using a prompt/theme engine (like Oh My Posh), ensure it is installed and that the JSON themes included here match your version.  
- Adjust your Execution Policy if you run into script execution errors:
  ```powershell
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

## Screenshots

Here’s a preview of the PowerShell configuration in action:

![PowerShell Preview](./images/powershell.png)

## All Available Modules / Tools

These are the main modules and tools used in this configuration:

- [Oh My Posh](https://ohmyposh.dev) — A prompt theme engine for PowerShell  
- [PSReadLine](https://github.com/PowerShell/PSReadLine) — Command-line editing, syntax highlighting, history  
- [posh-git](https://github.com/dahlbyk/posh-git) — Git status summary information in prompt  
- [z](https://github.com/agkozak/zsh-z) — Directory jumper (`Modules/z/`)  
- [PowerShell Gallery](https://www.powershellgallery.com/) — Source for installing extra modules  

*(You can expand this list with more tools/modules as you add them to the repository.)*  

## License

Specify your license here (e.g., MIT, Apache, etc.) so that others know how they can use your configuration.
