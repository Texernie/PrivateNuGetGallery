function Log-And-Run ($cmd, $returnObj){

	echo "$cmd"
	iex "& $cmd"
	$returnObj.ec = $LastExitCode
}

function StopAndRemoveContainer($containerName)
{
	$e = docker ps -a --filter name="$containerName"
	$e2 = ($e -split '[\r\n]')

	if ($e2.length -eq 1)
	{
		return
	}

	$r = docker ps --filter name="$containerName"
	$r2 = ($r -split '[\r\n]')

	if ($r2.length -gt 1)
	{
		Write-Host "Stopping old container"
		$c = "docker stop -t 15 `"$containerName`""
		Log-And-Run $c $eco
	}

	Write-Host "Removing old container"
	$c = "docker rm `"$containerName`""
	Log-And-Run $c $eco

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
	
		$containerPort = $OctopusParameters["NuGetGalleryContainerPort"]
		$containerHostname = $OctopusParameters["NuGetGalleryContainerHostname"]
		$containerName = $OctopusParameters["NuGetGalleryContainerName"]
		$hostPort = $OctopusParameters["NuGetGalleryHostPort"]
		$dockerRegistry = $OctopusParameters["DockerRegistry"]
		$dockerRepository = $OctopusParameters["NuGetGalleryDockerRepository"]
    }
    else
    {
		$machineName  = "**Development**"
		$packageVersion = "1.0.383.1152"
		$releaseVersion = "**Development**"
		$environmentName = "**Development**"
		$installationPath = "."
	
		$containerName = "NuGetGallery"
		$containerHostname = ""
		$containerPort = 80
		$hostPort = ""
		$dockerRegistry = "dad-docker.abcimaging.com"
		$dockerRepository = "AbcNuGetGallery"
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

	echo "Variables:"
	echo "    Octopus.Action.Package.CustomInstallationDirectory:'$installationPath'"
	echo "    MachineName: '$machineName'"
	echo "    ReleaseVersion: '$releaseVersion'"
	echo "    PackageVersion: '$packageVersion'"
	echo "    EnvironmentName: '$environmentName'"
	echo "    InstallationPath: '$installationPath'"
	echo "    ContainerName: '$containerName'"
	echo "    ContainerHostname: '$containerHostname'"
	echo "    ContainerPort: '$containerPort'"
	echo "    HostPort: '$hostPort'"
	echo "    DockerRegistry: '$dockerRegistry'"
	echo "    DockerRepository: '$dockerRepository'"
	
	$eco = @{ec = 0}
	
	Write-Host "Pulling new container"
	$c = "docker pull $dockerRegistry/${dockerRepository}:$packageVersion"
	Log-And-Run $c $eco
	
	StopAndRemoveContainer $containerName
	
	Write-Host "Creating new container"
	
	$c ="docker create --name `"$containerName`" --publish ${hostPort}:$containerPort --restart always --hostname $containerHostname --network nat $dockerRegistry/${dockerRepository}:$packageVersion"
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	$c = "docker cp `"$installationPath\_Deployment\Config\web.config`" ${containerName}:C:\app\web.config"
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	Write-Host "Updating databases"
	$c = "`"$installationPath\_Deployment\DbUpdater\migrate.exe`" `"NuGetGallery.dll`" MigrationsConfiguration `"NuGetGallery.Core.dll`" `"/startUpDirectory:$installationPath\_Deployment\DbUpdater\`" `"/startUpConfigurationFile:$installationPath\_Deployment\Config\web.config`""
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	$c = "`"$installationPath\_Deployment\DbUpdater\migrate.exe`" `"NuGetGallery.dll`" SupportRequestMigrationsConfiguration `"NuGetGallery.dll`" `"/startUpDirectory:$installationPath\_Deployment\DbUpdater\`" `"/startUpConfigurationFile:$installationPath\_Deployment\Config\web.config`""
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	Write-Host "Starting container"
	$c = "docker start `"$containerName`""
	Log-And-Run $c $eco
	if ( $eco.ec -ne 0 ) { exit }

	Write-Host "Deploy script finished."

	$finishedScript = 'true'
}
catch [system.exception]
{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	write-host $FailedItem
	write-host $ErrorMessage
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
