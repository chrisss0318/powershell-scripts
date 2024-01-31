# expiringcerts.ps1 - Parses certificates in Entra ID instance and lists any that are expiring soon using MS Graph API
# by Chris Hewinson
#

# Connects to MS Graph API and gets list of all Applications, creates logs
Connect-MgGraph
$Applications = Get-MgApplication -all
$Logs = @()

# Prompts for number of days from expiration and whether or not certs are expired
Write-host "I would like to see the Applications with the Secrets and Certificates that expire in the next X amount of Days? <<Replace X with the number of days. The answer should be ONLY in Numbers>>" -ForegroundColor Green
$Days = Read-Host

Write-host "Would you like to see Applications with already expired secrets or certificates as well? <<Answer with [Yes] [No]>>" -ForegroundColor Green
$AlreadyExpired = Read-Host

$now = get-date

# Checks each app and extracts/logs information for expired certs depending on prompted criteria
foreach ($app in $Applications) {
    $AppName = $app.DisplayName
    $applicationId = $app.Id
    $ApplID = $app.AppId
    $AppCreds = Get-MgApplication -ApplicationId $applicationId | select PasswordCredentials, KeyCredentials
    $secret = $AppCreds.PasswordCredentials
    $cert = $AppCreds.KeyCredentials

    foreach ($s in $secret) {
        $StartDate = $s.StartDateTime
        $EndDate = $s.EndDateTime
        $operation = $EndDate - $now
        $ODays = $operation.Days

        if ($AlreadyExpired -eq "No") {
            if ($ODays -le $Days -and $ODays -ge 0) {

                $Owner = Get-MgApplicationOwner -ApplicationId $app.Id
                $Username = $Owner.UserPrincipalName -join ";"
                $OwnerID = $Owner.ObjectID -join ";"
                if ($owner.UserPrincipalName -eq $Null) {
                    $Username = $Owner.DisplayName + " **<This is an Application>**"
                }
                if ($Owner.DisplayName -eq $null) {
                    $Username = "<<No Owner>>"
                }

                $Log = New-Object System.Object

                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationName" -Value $AppName
                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationID" -Value $ApplID
                $Log | Add-Member -MemberType NoteProperty -Name "Secret Start Date" -Value $StartDate
                $Log | Add-Member -MemberType NoteProperty -Name "Secret End Date" -value $EndDate
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate Start Date" -Value $Null
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate End Date" -value $Null
                $Log | Add-Member -MemberType NoteProperty -Name "Owner" -Value $Username
                $Log | Add-Member -MemberType NoteProperty -Name "Owner_ObjectID" -value $OwnerID

                $Logs += $Log
            }
        }
        elseif ($AlreadyExpired -eq "Yes") {
            if ($ODays -le $Days) {
                $Owner = Get-MgApplicationOwner -ApplicationId $app.Id
                $Username = $Owner.UserPrincipalName -join ";"
                $OwnerID = $Owner.ObjectID -join ";"
                if ($owner.UserPrincipalName -eq $Null) {
                    $Username = $Owner.DisplayName + " **<This is an Application>**"
                }
                if ($Owner.DisplayName -eq $null) {
                    $Username = "<<No Owner>>"
                }

                $Log = New-Object System.Object
    
                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationName" -Value $AppName
                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationID" -Value $ApplID
                $Log | Add-Member -MemberType NoteProperty -Name "Secret Start Date" -Value $StartDate
                $Log | Add-Member -MemberType NoteProperty -Name "Secret End Date" -value $EndDate
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate Start Date" -Value $Null
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate End Date" -value $Null
                $Log | Add-Member -MemberType NoteProperty -Name "Owner" -Value $Username
                $Log | Add-Member -MemberType NoteProperty -Name "Owner_ObjectID" -value $OwnerID

                $Logs += $Log
            }
        }
    }

    foreach ($c in $cert) {
        $CStartDate = $c.StartDateTime
        $CEndDate = $c.EndDateTime
        $COperation = $CEndDate - $now
        $CODays = $COperation.Days

        if ($AlreadyExpired -eq "No") {
            if ($CODays -le $Days -and $CODays -ge 0) {

                $Owner = Get-MgApplicationOwner -ApplicationId $app.Id
                $Username = $Owner.UserPrincipalName -join ";"
                $OwnerID = $Owner.ObjectID -join ";"
                if ($owner.UserPrincipalName -eq $Null) {
                    $Username = $Owner.DisplayName + " **<This is an Application>**"
                }
                if ($Owner.DisplayName -eq $null) {
                    $Username = "<<No Owner>>"
                }

                $Log = New-Object System.Object

                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationName" -Value $AppName
                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationID" -Value $ApplID
                $Log | Add-Member -MemberType NoteProperty -Name "Secret Start Date" -Value $null
                $Log | Add-Member -MemberType NoteProperty -Name "Secret End Date" -value $null
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate Start Date" -Value $CStartDate
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate End Date" -value $CEndDate
                $Log | Add-Member -MemberType NoteProperty -Name "Owner" -Value $Username
                $Log | Add-Member -MemberType NoteProperty -Name "Owner_ObjectID" -value $OwnerID

                $Logs += $Log
            }
        }
        elseif ($AlreadyExpired -eq "Yes") {
            if ($CODays -le $Days) {

                $Owner = Get-MgApplicationOwner -ApplicationId $app.Id
                $Username = $Owner.UserPrincipalName -join ";"
                $OwnerID = $Owner.ObjectID -join ";"
                if ($owner.UserPrincipalName -eq $Null) {
                    $Username = $Owner.DisplayName + " **<This is an Application>**"
                }
                if ($Owner.DisplayName -eq $null) {
                    $Username = "<<No Owner>>"
                }

                $Log = New-Object System.Object

                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationName" -Value $AppName
                $Log | Add-Member -MemberType NoteProperty -Name "ApplicationID" -Value $ApplID
                $Log | Add-Member -MemberType NoteProperty -Name "Secret Start Date" -Value $null
                $Log | Add-Member -MemberType NoteProperty -Name "Secret End Date" -value $null
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate Start Date" -Value $CStartDate
                $Log | Add-Member -MemberType NoteProperty -Name "Certificate End Date" -value $CEndDate
                $Log | Add-Member -MemberType NoteProperty -Name "Owner" -Value $Username
                $Log | Add-Member -MemberType NoteProperty -Name "Owner_ObjectID" -value $OwnerID

                $Logs += $Log
            }
        }
    }
}

#Creates path for CSV file export
Write-host "Add the Path you'd like us to export the CSV file to, in the format of <C:\Users\<USER>\Desktop\Users.csv>" -ForegroundColor Green
$Path = Read-Host
$Logs | Export-CSV $Path -NoTypeInformation -Encoding UTF8