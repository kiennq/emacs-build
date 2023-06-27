# My docs
Commands to build locally. End up with `emacs-emacs-29-x86_64-full.zip`

```
.\emacs-build.cmd --clone --repo https://git.savannah.gnu.org/git/emacs.git --branch emacs-29 --depth 1
.\emacs-build.cmd --branch emacs-29 --nativecomp --slim --without-pop --without-imagemagick --without-compress-install --without-dbus --with-gnutls --with-json --with-tree-sitter --without-gconf --with-rsvg --without-gsettings --with-mailutils --with-modules  --with-xml2 --with-wide-int --build
.\emacs-build.cmd --branch emacs-29 --nativecomp --slim --without-pop --without-imagemagick --without-compress-install --without-dbus --with-gnutls --with-json --with-tree-sitter --without-gconf --with-rsvg --without-gsettings --with-mailutils --with-modules  --with-xml2 --with-wide-int --pack-all
```

# emacs-build v0.4

Scripts to build a distribution of Emacs from sources, using MSYS2 and Mingw64(32)

## Rationale

I wanted a script to build Emacs from sources, package it and install it on
different computers, with the following conditions

- I should be able to build any branch or release from Emacs. This includes the last release branch (right now emacs-27), as well as the master branch for development. Always using pristine sources from Savannah.
- I want to build emacs with different options from the default, which is to use all features available. For instance, I do not care for SVG support.
- The script needs to track all packages that are required by the Emacs build even if I change the build options.
- The installation should take as little space as possible, removing useless directories or files that come from the dependencies. For instance, headers from libraries used by emacs, spurious documentation files, etc.
- The script should be able to build other components I regularly use, such as mu, mu4e or pdf-tools, in a way that is not affected by updates to the mingw or msys environments.

## Usage

The script supports two way of being invoked:

- The `emacs-build.cmd` assumes nothing about your system, except for an existing installation of PowerShell. It will download and install a minimal MSYS/MINGW64 environment and build Emacs and all other requested components. This allows for a more deterministic build, without perturbing your computer.
- The `emacs-build.sh` is meant to be ran from an existing MSYS/MINGW64 environment, which will be modified to allow building Emacs and all tools. Use this version at your own risk.

### Steps

1. Download or clone the script from GitHub
2. Open a Windows terminal and move to the folder for this script
3. Issue whatever commands you need, such as `.\emacs-build.cmd --clone --deps --build --pack-emacs`
4. Inspect the `zips` folder for the products of the script

### General options

````
Usage:
   emacs-build [--version] [--help] [--features]
                    [--branch b] [--clone] [--build] [--deps]
                    [--slim] [--[no-]compress] [--[no-]strip]
                    [--with-all] [--without-X] [--with-X]
                    [--pdf-tools] [--aspell] [--hunspell] [--mu] [--isync]
                    [--pack-emacs] [--pack-all]
Actions:
   --build       Configure and build Emacs from sources.
   --clean       Remove all directories except sources and zip files.
   --clone       Download Savannah's git repository for Emacs.
   --deps        Create a ZIP file with all the Mingw64/32 dependencies.
   --help        Output this help message, --features and exit.
   --pack-emacs  Package an Emacs previously built with the --build option.
   --pack-all    Package an Emacs previously built, with all the Mingw64/32
                 dependencies, as well as all extensions (see Extensions below).
   --features    Shows all active and inactive features for the selected options.
   --version     Output emacs-build version number and exit.

   Multiple actions can be selected. The default is to run them all in a logical
   order: clone, build, deps and pack-all.

Build options:
   --branch b    Select Emacs branch (or tag) 'b' for the remaining operations.
   --compress    Ship Emacs with gunzip and compress documentation and Emacs
                 script files.
   --debug       Output all statements run by the script.
   --debug-dependencies
                 Describe which MSYS/MINGW packages depend on which, and
                 which files are discarded from the ZIP files.
   --no-strip    Disable the --strip option.
   --no-compress Disable the --compress option.
   --slim        Remove Cairo, SVG and TIFF support for a slimmer build.
                 Remove also documentation files and other support files
                 from the dependencies file. Activate --compress and
                 --strip. (Default configuration)
   --strip       Strip executables and DLL's from debug information.
   --with-all    Add all Emacs features.
   --with-*      Add requested feature in the dependencies and build
                 * is any of the known features for emacs in Windows/Mingw
                 (see --features).
   --without-*   Remove requested feature in the dependencies and build.

   Options are processed in order. Thus --slim followed by --with-cairo
   would enable Cairo, even though --slim removes it.

Extensions:
   --pdf-tools   Build and package PDF-TOOLS.
   --hunspell    Install Hunspell spell checker.
   --aspell      Install Aspell spell checker.
   --mu          Mail search system and supporting Emacs mu4e libraries.
   --isync       Synchronize email from IMAP/POP to Maildir format (mbsync).
````

### An example

Assume you invoke this script as follows
````
.\emacs-build.cmd --slim --clone --deps --build --pdf-tools --hunspell --mu --isync --pack-all
````

It will take care of the following tasks

1. Download the latest release of MSYS
2. Download a minimal set of MSYS and MINGW programs needed to build Emacs and the extensions
3. Clone the latest emacs repository on the branch emacs-27
4. Ensure that all required packages Mingw64 are installed, or install them.
5. Configure and build Emacs using those packages
6. Pack all the dependencies into a ZIP file.
7. Download and build pdf-tools, hunspell, mu and isync (plus xapian and gmime3). In the process, ensure that the required packages are also installed.
8. Create a ZIP file with Emacs, all the dependencies and all the extensions.

The script, just like its creator, is a bit opinionated. The default build (without arguments), assumes --slim and performs takes some extra steps to reduce the size of the distribution

- It eliminates the manual pages and large documentation files for the libraries that are used by Emacs.
- It eliminates the library files (*.a).
- It strips the executable files and DLL's from debugging information.


### Considerations

There are implicit dependencies in the various actions:

- `--clone` is required to get the sources
- `--build` is assumed to be run before `--pack-all` or `--pack-emacs`, and also before the extensions.

Note that `--clean` or `--clean-all` do not remove the `msys64` directory, because it is very time consuming to create and update it.

The tool produces zip files that are stored in `./zips` and can be uncompressed wherever you want:

- `emacs-xx-xxxx-deps.zips` is the file with optional libraries (png, jpeg, etc) used by Emacs.
- `emacs-xx-xxxx-nodeps.zip` is a bare Emacs installation. It runs even if the 'deps' file is not used
- `emacs-xx-xxxx-full.zip` is a complete Emacs installation, with the optional libraries and all extensions (pdf-tools, mu, etc) you mentioned in the command line.
- `pdf-tools-xxxx.zip` and others are the Zip files for the extensions. They can be unpacked inside an Emacs installation, but may assume that 'deps' have also been unpacked.

Regarding the extensions to Emacs and third-party utilities:

- They can be built separately from Emacs.
- If `c:\emacs` is where you unpacked the full installation, some extensions will reside in `c:\emacs\bin` (e.g. pdftools) and some others in `c:\emacs\usr\bin` (e.g. mu and mbsync).
- Even though elisp files are provided, it is highly recommended that you install pdf-tools and mu4e from Melpa or other repositories, to properly take care of dependencies from other elisp libraries.


## TO-DO

- Consider GitHub actions for automated continuous integration and release
  system. References:
  - Setting up an MSYS/MINGW system https://github.com/marketplace/actions/setup-msys2
  - MINGW packages recipes https://github.com/msys2/MINGW-packages/blob/master/.github/workflows/main.yml
  - Uploading artifacts https://github.com/actions/upload-artifact
    - https://github.com/actions/create-release

# Changelog

## v0.1

- First version of the script, to be run from a preexisting MSYS2/MINGW environment.

## v0.2

- New version of the script using also Windows shell and powershell scripts.
- The script downloads and creates a fresh new MSYS2/MINGW environment to build Emacs.
- Fixed some dependency issues, whereby MINGW packages depended on MSYS2 /usr directories.

## v0.3

- Improved help text.
- New option --compress, which ships gzip with Emacs and compresses non-essential files.
- Option --slim is now default.
- Emacs ships with a `site-start.el` that activates the directories for MSYS2 extensions.
- Only one branch of Emacs can be built.
- emacs-build no longer uses log files.

## v0.3.1

- Emacs-build upgrades GNU TLS version to at least 3.7.0, to allow safe https to MELPA.

## v0.3.2

- Undo the fix to GNU TLS, because this library is no longer available for download.
- Simplify and correct the process to detect dependencies between packages.
- Only remove non-essential data from executables (fix how we call 'strip').
- Enforce Emacs' latest stable release as default.
- Add hunspell and aspell from MINGW, replacing the one downloaded from Sourceforge.
- Cleanup of the build rules.
- Add tests for the extensions.
- Fix the behavior of --slim and --not-slim with respect to features.

## v0.4

- Clarify the order of execution of command line options.
- Remove --not-slim.
- Add --strip, and --with-all.
- Construct --slim out of --with-all, --without-*, --compress and --strip, so that users can counteract their behavior.
