#Made by Teva Jalink, Error logs are created in the pap01sftp SFTP Automation folder
#Using Zendesk API to retrive ticket information, create a user, and create a SFTP directory
#User information and Zendesk api URL
$user = "tjalink@crossriver.com"
$pass = ""
$ticketnum = 5
$uri = "https://crossriver9820.zendesk.com/api/v2/tickets/$($ticketnum).json"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$pass)))

#Invoking the Zendesk API for a Json file with the ticket information.
try
{
    $TicketInfo = Invoke-RestMethod -Uri $uri -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -ContentType "application/json"
    $CompNameField = $TicketInfo.ticket.custom_fields | select value | out-string
    $CompName = $CompNameField.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries).trim()
    $newuser = $CompName[0] + $CompName[1]
    $description = $a.ticket.id
}
catch
{
    $Date = (get-date -Format 'MM/dd/yyyy')
    set-content -path "\\pap01sftp\C$\SFTP Automation\Logs\$($user).ZenDeskAPIErrorlog - $($Date)" -Value $Error
}
#Creating a User for the SFTP
add-type -AssemblyName system.web
$password = [System.Web.Security.Membership]::GeneratePassword((Get-Random -Minimum 20 -Maximum 32), 3)
$securedpassword = ConvertTo-SecureString -String $password -AsPlainText -force
try
{
    new-aduser -name "$($newuser).sftp" -otherattributes @{'description'="Ticket#$($description)"} -path "OU=serviceaccounts,DC=CRB,DC=cloud" -password $securedpassword -passwordneverexpires $true
}
catch
{
    $Date = (get-date -Format 'MM/dd/yyyy')
    set-content -path "\\pap01sftp\C$\SFTP Automation\Logs\$($user).UserCreationErrorlog - $($Date)" -Value $Error
}

#Creating a new directory with NTFS permissions
$DirName = $newuser
$path = "\\pap01sftp\D$\PTPs\$($DirName)"
New-Item -path $path -ItemType "directory"
$acl = Get-Acl $path
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($($newuser),"Modify","ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($AccessRule)
$acl | Set-Acl $path
Copy-Item -path "C:\SFTP Template Structure\*" -Destination $path -Recurse

#Running a batch file for the sftp configuration
$user = "$($newuser).sftp"
$Alias = $newuser
$Comment = "ticket# + $($description)"
try
{
    set-content -path "\\pap01sftp\C$\SFTP Automation\User Files\$($user).bat" -Value  "acl add crbcloud\$($user) allow login sftp","sftp add $Alias $path $comment","sftp allow $path crbcloud\$($user)","sftp togglehome $path crbcloud\$($user)","save","exit"
    Invoke-Command -ComputerName "pap01sftp.crbcloud.com" -ScriptBlock {vshellconfig exec "\\pap01sftp\C$\SFTP Automation\User Files\$($user).bat"}
}
catch
{
    $Date = (get-date -Format 'MM/dd/yyyy')
    set-content -path "\\pap01sftp\C$\SFTP Automation\Logs\$($user).SFTPconfErrorlog - $($Date)" -Value $Error
}

#Send the user cred to client using password pusher
$Days = 7
$Views = 5
$server = "pwpush.com"
try
{
    $Reply = Invoke-RestMethod -Method 'Post' -Uri "https://$Server/p.json" -ContentType "application/json" -Body ([pscustomobject]@{
    password = [pscustomobject]@{
                    payload = $password
                    expire_after_days = $Days
                    expire_after_views = $Views
            }
        } | ConvertTo-Json)
        $returnURL =  "https://$Server/p/$($Reply.url_token)"
}
catch
{
    $Date = (get-date -Format 'MM/dd/yyyy')
    set-content -path "\\pap01sftp\C$\SFTP Automation\Logs\$($user).pwpushErrorlog - $($Date)" -Value $Error
}

#returning the required credentials to the Zendesk ticket.
$commentbody = '{"ticket": {"comment": { "body": "Hello, the SFTP user has been created. Username: (' + $($user) + ') Password can be retrived from this url:' + $($returnURL) + '","public": true}}}'
$comment = Invoke-RestMethod -Method Put -UseBasicParsing -ContentType "application/json" -Uri $uri -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $commentbody