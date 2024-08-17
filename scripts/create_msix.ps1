# this script convert a directory to a msix package file
# take two parameters of the directory path and the output msix file
param(
    [string] $manifesTemplate,
    [string] $version,
    [string] $directory,
    [string] $package
)

# create a manifest file
$content = [System.IO.File]::ReadAllText($manifesTemplate).Replace("{{version}}", $version)
[System.IO.File]::WriteAllText("$directory\AppxManifest.xml", $content)

# create the msix package
if ($env:MSIXHeroCLI) {
    &$env:MSIXHeroCLI pack -d $directory -p $package
}
else {
    MSIXHeroCLI.exe pack -d $directory -p $package
}
