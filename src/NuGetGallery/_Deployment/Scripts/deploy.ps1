function Log-And-Run ($cmd, $returnObj){

	Write-Host "$cmd"
	Invoke-Expression -Command "& $cmd" | Out-Host
	$returnObj.ec = $LastExitCode
}

try
{
	$finishedScript = 'false'

	Write-Host "Running deploy script on container host..."

	if($OctopusParameters)
    {
		$machineName = $OctopusParameters["Octopus.Machine.Name"]
		$packageVersion = $OctopusParameters["Octopus.Action.Package.NuGetPackageVersion"]
		$releaseVersion = $OctopusParameters["Octopus.Release.Number"]
		$environmentName = $OctopusParameters["Octopus.Environment.Name"]
		$installationPath = $OctopusParameters["Octopus.Action.Package.CustomInstallationDirectory"]
		$deploymentId = $OctopusParameters["Octopus.Deployment.Id"]

		$containerPort = $OctopusParameters["NuGetGalleryContainerPort"]
		$containerHostname = $OctopusParameters["NuGetGalleryContainerHostname"]
		$containerName = $OctopusParameters["NuGetGalleryContainerName"]
		$hostPort = $OctopusParameters["NuGetGalleryHostPort"]
		$dockerRegistry = $OctopusParameters["DockerRegistry"]
		$dockerRepository = $OctopusParameters["NuGetGalleryDockerRepository"]
		$nugetUrl = $OctopusParameters["ABCNugetServerBaseUrl"]
    }
    else
    {
		$machineName  = "**Development**"
		$packageVersion = "1.0.383.1152"
		$releaseVersion = "**Development**"
		$environmentName = "**Development**"
		$installationPath = "."
		$deploymentId = "**Development**"
	
		$containerName = "NuGetGallery"
		$containerHostname = ""
		$containerPort = 80
		$hostPort = ""
		$dockerRegistry = "dad-docker.abcimaging.com"
		$dockerRepository = "AbcNuGetGallery"
		$nugetUrl = "https://nuget-e191776759b9.abcimaging.com/api/v2/"
    }
	
	if ([string]::IsNullOrWhiteSpace($containerHostname))
	{
		$containerHostname = 'T-' + [Guid]::NewGuid().ToString("N").Substring(0,13)
	}

	$containerHostname = $containerHostname[0..15] -join ''

	if (-not ($containerHostname -match '^[a-zA-Z][a-zA-Z0-9\-]*$'))
	{
		$on = $containerHostname
		$containerHostname = 'T-' + [Guid]::NewGuid().ToString("N").Substring(0,13)
		Write-Warning "Invalid hostname [$on] using [$containerHostname] instead"
	}
	
	$nugetPublishUrl = "$($nugetUrl)package/"

	Write-Host "Variables:"
	Write-Host "    Octopus.Deployment.Id:'$deploymentId'"
	Write-Host "    Octopus.Action.Package.CustomInstallationDirectory:'$installationPath'"
	Write-Host "    MachineName: '$machineName'"
	Write-Host "    ReleaseVersion: '$releaseVersion'"
	Write-Host "    PackageVersion: '$packageVersion'"
	Write-Host "    EnvironmentName: '$environmentName'"
	Write-Host "    InstallationPath: '$installationPath'"
	Write-Host "    ContainerName: '$containerName'"
	Write-Host "    ContainerHostname: '$containerHostname'"
	Write-Host "    ContainerPort: '$containerPort'"
	Write-Host "    HostPort: '$hostPort'"
	Write-Host "    DockerRegistry: '$dockerRegistry'"
	Write-Host "    DockerRepository: '$dockerRepository'"
	Write-Host "    NugetSourceUrl: '$nugetUrl'"
	Write-Host "    NugetPublishUrl: '$nugetPublishUrl'"

	$eco = @{ec = 0}

	$r = Get-PsRepository | Where-Object { $_.Name -eq 'abc-ps' }
	if ($null -eq $r){
		$c = "Register-PSRepository -Name abc-ps -InstallationPolicy Trusted -SourceLocation $nugetUrl -PublishLocation $nugetPublishUrl"
		Log-And-Run $c $eco
		if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }
	}

	$lv = $(Find-Module -name AbcDeploymentDockerTools -Repository "abc-ps" | Select-Object Version)

	$em = Get-Module -Name AbcDeploymentDockerTools -ListAvailable | Where-Object { $_.Version -ne $lv.Version }
	while ($null -ne $em){
		Write-Host "Removing AbcDeploymentDockerTools module..."
		$c = 'Uninstall-Module -Name AbcDeploymentDockerTools -Force'
		Log-And-Run $c $eco
		if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }

		$em = Get-Module -Name AbcDeploymentDockerTools -ListAvailable | Where-Object { $_.Version -ne $lv.Version }
	}

	$em = Get-Module -Name AbcDeploymentDockerTools -ListAvailable | Where-Object { $_.Version -eq $lv.Version }
	if ($null -eq $em){
		$c = 'Install-Module -Repository "abc-ps" -Name AbcDeploymentDockerTools -Force -AllowClobber'
		Log-And-Run $c $eco
		if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }
	}

	$c = 'Get-Module -Name "AbcDeploymentDockerTools" -ListAvailable | Format-Table'
	Log-And-Run $c $eco
	if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }

	$c = 'Import-Module AbcDeploymentDockerTools'
	Log-And-Run $c $eco
	if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }

	$c = "Redo-DockerContainer -ContainerName $containerName ``
 -Registry $dockerRegistry ``
 -Repository $dockerRepository ``
 -Tag $packageVersion ``
 -AlwaysRestart ``
 -HostName $containerHostname ``
 -TcpPorts @(@{ExternalPort=$hostPort; InternalPort=$containerPort})"
	Log-And-Run $c $eco
	if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }

	Write-Host "Copying configuration files"

	Write-Host '================'
	Write-Host '== web.config =='
	Write-Host '================'
	Get-Content -Path $installationPath\_Deployment\Config\web.config | Write-Host

	$c = "Add-DockerFile -ContainerName $containerName -SourceFilePath `"$installationPath\_Deployment\Config\web.config`" -DestinationFilePath 'C:\app\bin\web.config'"
	Log-And-Run $c $eco
	if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }


	Write-Host "Updating databases"
	$c = "`"$installationPath\_Deployment\DbUpdater\migrate.exe`" `"NuGetGallery.dll`" MigrationsConfiguration `"NuGetGallery.Core.dll`" `"/startUpDirectory:$installationPath\_Deployment\DbUpdater\`" `"/startUpConfigurationFile:$installationPath\_Deployment\Config\web.config`""
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	$c = "`"$installationPath\_Deployment\DbUpdater\migrate.exe`" `"NuGetGallery.dll`" SupportRequestMigrationsConfiguration `"NuGetGallery.dll`" `"/startUpDirectory:$installationPath\_Deployment\DbUpdater\`" `"/startUpConfigurationFile:$installationPath\_Deployment\Config\web.config`""
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	Write-Host "Starting container"
	$c = "Start-DockerContainer -ContainerName $containerName"
	Log-And-Run $c $eco
	if (( $eco.ec -ne 0 ) -and ($null -ne $eco.ec )) { exit }

	Write-Host "Deploy script finished."

	$finishedScript = 'true'
}
catch [system.exception]
{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	Write-Host $FailedItem
	Write-Host $ErrorMessage
	$LastExitCode = 1
}
finally
{
	Write-Host "Deploy finalizing."

	if ($finishedScript -ne 'true')
	{
		$LastExitCode = 1
	}
	else
	{
		$LastExitCode = 0
	}

	exit $LastExitCode
}
