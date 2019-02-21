
try
{
	Write-Host "Running predeploy script..."

	if($OctopusParameters)
    {
		$nugetUrl = $OctopusParameters["ABCNugetServerBaseUrl"]
    }
    else
    {
		$nugetUrl = "https://nuget-e191776759b9.abcimaging.com/api/v2/"
    }

	$nugetPublishUrl = "$($nugetUrl)package/"

	Write-Host "Variables:"
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

	Write-Host "Running predeploy script finished."

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

