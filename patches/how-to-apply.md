# How to apply patches notes

``` powershell
dir ..\..\patches\emacs\*.patch | %{git am $_ && mv $_ ..\..\patches\emacs\.applied\ -force}

# if conflicts
git apply --ignore-whitespace ..\..\patches\emacs\<name>.patch --reject
# resolve conflicts
# remove rej files
git add .
git am --continue
mv ..\..\patches\emacs\<name>.patch ..\..\patches\emacs\.applied\ -force
```

# How to export

``` powershell
git format-patch -<num> HEAD
mv 00* ..\..\patches\emacs\ -Force
```

