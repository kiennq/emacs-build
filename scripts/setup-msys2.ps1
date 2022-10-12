# Ensure a minimal MSYS2/MINGW64 environment. We follow the recipes
# from the GitHub Action setup-msys2, found at
# https://github.com/msys2/setup-msys2/blob/master/main.js

$emacs_build_dir = $PSScriptRoot + '\..'
$msys2_dir = $env:msys2_dir
if ($msys2_dir)
{
    if (!(Test-Path "$msys2_dir"))
    {
        Write-Output "Environment variable msys2_dir suggests that MSYS2 is installed in"
        Write-Output "  $msys2_dir"
        Write-Output "but there is no valid MSYS2 system there."
        exit -1
    }
}
else
{
    # Location of MSYS can be overriden
    $msys2_dir = $emacs_build_dir + '\msys64'
    $env:msys2_dir = $msys2_dir
    if ( !(Test-Path "$msys2_dir") )
    {
        Write-Output "Creating MSYS2 directory $msys2_dir"
        mkdir $msys2_dir
    }
}

if (!(Test-Path "$msys2_dir\msys2_shell.cmd"))
{
    $inst_url = 'https://github.com/msys2/msys2-installer/releases/download/2022-09-04/msys2-base-x86_64-20220904.sfx.exe'
    $installer_checksum = 'BB92718BCE932398A2E236D60C53EF35C3BC9A96999A26DD5814E66A2F4BAF1F'
    $installer = $msys2_dir + '\msys2-base.exe'

    if (!(Test-Path $installer))
    {
        Write-Output "Downloading MSYS2 installer to $installer"
        [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
        Invoke-WebRequest -Uri $inst_url -OutFile $installer
    }

    $checksum = (Get-FileHash $installer -Algorithm SHA256)[0].Hash
    if ($checksum -ne $installer_checksum)
    {
        Write-Output "Downloaded file $installer has checksum $checksum"
        Write-Output "which differs from $installer_checksum"
    }

    Write-Output "Emacs build root: $emacs_build_dir"
    Set-Location "$emacs_build_dir"
    Write-Output "Unpack MSYS2"
    & $installer -y

    Set-Location $emacs_build_dir
    # Reduce time required to install packages by disabling pacman's disk space checking
    .\scripts\msys2.cmd -c 'sed -i "s/^CheckSpace/#CheckSpace/g" /etc/pacman.conf'
    # Force update packages
    Write-Output "First forced update"
    .\scripts\msys2.cmd -c 'pacman --noprogressbar --noconfirm -Syuu'
    # We have changed /etc/pacman.conf above which means on a pacman upgrade
    # pacman.conf will be installed as pacman.conf.pacnew
    #.\scripts\msys2.cmd -c 'mv -f /etc/pacman.conf.pacnew /etc/pacman.conf'
    .\scripts\msys2.cmd -c 'sed -i "s/^CheckSpace/#CheckSpace/g" /etc/pacman.conf'
    # Kill remaining tasks
    taskkill /f /fi 'MODULES EQ msys-2.0.dll'
}

if (!(Test-Path "$emacs_build_dir\msys2-upgraded.log"))
{
    Set-Location "$emacs_build_dir"

    # Final upgrade
    # Write-Output "Final upgrade"
    # .\scripts\msys2.cmd -c 'pacman --noprogressbar --noconfirm -Syuu'
    # Install packages required by emacs-build
    Write-Output "Install essential packages"
    .\scripts\msys2.cmd -c 'pacman --noprogressbar --needed --noconfirm -S git unzip zip base-devel mingw-w64-x86_64-toolchain autoconf automake'

    Write-Output "done" > "$emacs_build_dir\msys2-upgraded.log"
}

