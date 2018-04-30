
try
{
	echo "Running predeploy script..."

	####
	#do stuff here
	####

	echo "Predeploy script finished."

	$finishedScript = 'true'
}
catch [system.exception]
{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	echo $FailedItem
	echo $ErrorMessage
	$LastExitCode = 1
}
finally
{
	if ($finishedScript -ne 'true')
	{
		$LastExitCode = 1
	}
}


