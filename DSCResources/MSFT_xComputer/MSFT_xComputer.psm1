function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$DomainName,

		[System.String]
		$OUPath,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$Credential
	)

	$returnValue = @{
		Name = $env:COMPUTERNAME
		DomainName = (Get-WmiObject -Class Win32_ComputerSystem).Domain
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$DomainName,

		[System.String]
		$OUPath,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$Credential
	)

    # Write registry timestamp, so we can test later that we rebooted after set
    if(!(Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Cloud Solutions'))
    {
        $null = New-Item -Path 'HKLM:\SOFTWARE\Microsoft' -Name 'Cloud Solutions'
    }
    if(!(Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment'))
    {
        $null = New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Cloud Solutions' -Name 'Deployment'
    }
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment' -Name 'xComputerSetTime' -Value (Get-Date)

    if($env:COMPUTERNAME -ne $Name)
    {
        $Success = $false
        $Attempt = 0
        do
        {
            $Attempt++
            try
            {
                Write-Verbose "Rename computer from $($env:COMPUTERNAME) to $Name, attempt $Attempt"
                Rename-Computer -NewName $Name -Force -ErrorAction Stop
                $Success = $true
            }
            catch
            {
                Write-Verbose "Failed renaming computer with exception `"$($_.Exception)`""
                Start-Sleep 10
            }
        }
        until(($Success -eq $true) -or ($Attempt -gt 10))
    }
    elseif((Get-WmiObject -Class Win32_ComputerSystem).Domain -ne $DomainName)
    {
        $Success = $false
        $Attempt = 0
        do
        {
            $Attempt++
            try
            {
                Write-Verbose "Join computer to domain $DomainName, attempt $Attempt"
                if($PSBoundParameters.ContainsKey('OUPath'))
                {
                    Add-Computer -DomainName $DomainName -OUPath $OUPath -Credential $Credential -ErrorAction Stop
                }
                else
                {
                    Add-Computer -DomainName $DomainName -Credential $Credential -ErrorAction Stop
                }
                $Success = $true
            }
            catch
            {
                Write-Verbose "Failed joining computer to domain with exception `"$($_.Exception)`""
                Start-Sleep 10
            }
        }
        until(($Success -eq $true) -or ($Attempt -ge 10))
    }

    $global:DSCMachineStatus = 1
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
		$DomainName,

		[System.String]
		$OUPath,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$Credential
	)

    $ComputerDomain = Get-TargetResource @PSBoundParameters

	if(($ComputerDomain.Name -eq $Name) -and ($ComputerDomain.DomainName -eq $DomainName))
    {
        # check registry timestamp and last boot time to ensure we rebooted after last set
        if($LastSetTime = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment' -Name 'xComputerSetTime' -ErrorAction SilentlyContinue).xComputerSetTime)
        {
            Write-Verbose "Last set time is $LastSetTime"
            $LastBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
            Write-Verbose "Last boot time is $LastBootTime"
            if($LastBootTime -le [DateTime]$LastSetTime)
            {
                Write-Verbose 'System was not rebooted after last set'
                $result = $false
            }
            else
            {
                Write-Verbose 'System was rebooted after last set'
                $result = $true
            }
        }
        else
        {
            Write-Verbose 'No registry timestamp for last set'
            $result = $true
        }
    }
    else
    {
        Write-Verbose "Name is $($ComputerDomain.Name) and should be $Name"
        Write-Verbose "DomainName is $($ComputerDomain.DomainName) and should be $DomainName"
        $result = $false
    }

	$result
}


Export-ModuleMember -Function *-TargetResource