# escape=`
FROM microsoft/aspnet:4.7.1-windowsservercore-10.0.14393.1884

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# disable DNS cache so container addresses always fetched from Docker
# Remove any existing websites
# Remove any existing AppPools
# Create directory for application
# Create new AppPool
# Set runtimeversion of new AppPool
# Create "Default Web Site" in IIS
# Turn off IIS logging on all sites
# Set the owner of the new application directory to IIS_IUSRS (including all subfolders)
RUN Set-ItemProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name ServerPriorityTimeLimit -Value 0 -Type DWord; `
    Get-Website | Remove-Website; `
	Get-ChildItem 'IIS:\AppPools' | Select-Object Name | % { remove-webapppool $_.Name }; `
	New-Item -Path 'C:\install' -Type Directory -Force; `
	New-Item -Path 'C:\app\bin' -Type Directory -Force; `
	New-Item -Path 'C:\app\config' -Type Directory -Force; `
	$a = New-WebAppPool -Name 'DefaultAppPool' -Force; `
	$a.managedRuntimeVersion = 'v4.0'; `
    New-Website -Name 'Default Web Site' -PhysicalPath 'C:\app\bin' -Port 80 -ApplicationPool 'DefaultAppPool' -Force; `
	Set-WebConfigurationProperty -PSPath 'IIS:\' -filter 'system.webServer/httpLogging' -name dontLog -value $true; `
	$path='C:\app'; `
    $acl = Get-Acl $path; `
    $newOwner = [System.Security.Principal.NTAccount]('BUILTIN\IIS_IUSRS'); `
    $acl.SetOwner($newOwner); `
    dir -r $path | Set-Acl -aclobject  $acl

EXPOSE 80

WORKDIR /install
ADD https://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi rewrite_amd64.msi
RUN Write-Host 'Installing URL Rewrite' ; `
	Start-Process msiexec.exe -ArgumentList '/i', 'rewrite_amd64.msi', '/quiet', '/norestart' -NoNewWindow -Wait

WORKDIR /App/Bin
RUN Remove-Item -Recurse -Force c:\install

ARG source=obj/Docker/publish
COPY $source .
