# this script convert a directory to a msix package file
# take two parameters of the directory path and the output msix file
param(
    [string] $manifesTemplate,
    [string] $version,
    [string] $directory,
    [string] $package,
    [string] $cert,
    [string] $secret
)

# create a manifest file
$content = [System.IO.File]::ReadAllText($manifesTemplate).Replace("{{version}}", $version)
[System.IO.File]::WriteAllText("$directory\AppxManifest.xml", $content)

$msixcli = if ($env:MSIXHeroCLI) { $env:MSIXHeroCLI } else { "MSIXHeroCLI.exe" }
# create the msix package
& $msixcli pack -d $directory -p $package

# sign the msix package
& $msixcli sign -f $cert -p $secret -t "http://timestamp.comodoca.com" "$package"
