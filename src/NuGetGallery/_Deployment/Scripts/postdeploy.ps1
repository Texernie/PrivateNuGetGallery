
try
{
	Write-Host "Running postdeploy script..."

	if($OctopusParameters)
    {
		$installationPath = $OctopusParameters["Octopus.Action.Package.CustomInstallationDirectory"]

		If (Test-Path $installationPath)
		{
			Remove-Item $installationPath\* -Recurse -Force -Exclude postdeploy.ps1
		}

		$dockerRegistry = $OctopusParameters["DockerRegistry"]
		$dockerRepository = $OctopusParameters["NuGetGalleryDockerRepository"]
		$packageVersion = $OctopusParameters["Octopus.Action.Package.NuGetPackageVersion"]

		$allImages = docker images --quiet "$dockerRegistry/${dockerRepository}"
		$currentImage = docker images --quiet "$dockerRegistry/${dockerRepository}:$packageVersion"

		$imagesToRemove = $allImages | ? {$currentImage -notcontains $_} | select -Unique

		foreach ($i in $imagesToRemove) { write-host "Removing image $i"; docker rmi --force $i  }
    }

	Write-Host "Postdeploy script finished."

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
	if ($finishedScript -ne 'true')
	{
		$LastExitCode = 1
	}
}

