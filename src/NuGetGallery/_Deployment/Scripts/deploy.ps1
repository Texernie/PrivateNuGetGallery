function Log-And-Run ($cmd, $returnObj){

	Write-Host "$cmd"
	Invoke-Expression -Command "& $cmd" | Out-Host
	$returnObj.ec = $LastExitCode
}

function Log-And-Copy ($srcFile, $dstFile, $returnObj){

	$msg = "=== $([System.IO.Path]::GetFileName($srcFile)) ==="
	$msg2 = [String]::new('=', $msg.Length)
	Write-Host $msg2
	Write-Host $msg
	Write-Host $msg2
	Get-Content -Path $([System.IO.Path]::GetFullPath($srcFile)) | Write-Host
	Write-Host $msg2

	$c = "Add-DockerFile -ContainerName $containerName -SourceFilePath `"$([System.IO.Path]::GetFullPath($srcFile))`" -DestinationFilePath '$dstFile'"
	Log-And-Run $c $returnObj
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
		$dockerRegistry = "250949537405.dkr.ecr.us-east-1.amazonaws.com"
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

	$eco = @{ec = 0}

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

	Log-And-Copy $installationPath\_Deployment\Config\web.config C:\app\bin\web.config $eco
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
