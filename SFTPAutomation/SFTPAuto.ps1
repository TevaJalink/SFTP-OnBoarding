param($companyname,$ticket_id)

$user = "crb_service_not_a_real_email@crossriver.com/token"
$Token = $env:ZENDESK_TOKEN
$uri = "https://crossriver.zendesk.com/api/v2/tickets/$ticket_id.json"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("$($user):$($Token)")))

#Creating a User for the SFTP
$securedpassword = $env:PASSWORD
$ADpass = $env:ADUSERPASSWORD
$cred = New-Object System.Management.Automation.PSCredential ("svcSREIaC", (ConvertTo-SecureString -AsPlainText -Force $ADpass))
try
{
Invoke-Command -ComputerName "cdc04.crbcloud.com" -Authentication Negotiate -Credential $cred -ErrorAction Stop -ScriptBlock {
        $UserName = "SFTP $using:companyname"
        $company = $using:companyname
        $securedpassword = "$using:securedpassword"
        powershell -file "C:\Temp\sftptest\test.ps1" -UserName $UserName -ticket_id $using:ticket_id -securedpassword $securedpassword -company $company
    }
}
catch
{
    Write-Error -message "$($Error)"
}

#Creating a new directory with NTFS permissions
$session = New-PSsession -Computername "pap01sftp.crbcloud.com" -Authentication Negotiate -Credential $cred
invoke-command -session $session -ScriptBlock {
    $TextInfo = (Get-Culture).TextInfo
    $path = "\\pap01sftp\D$\PTPs\$($TextInfo.ToTitleCase($using:companyname))"
    $identity = "$using:companyname" + ".sftp"
    New-Item -path $path -ItemType "directory"
    $acl = Get-Acl $path
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity,"Modify","ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($AccessRule)
    $acl | Set-Acl $path
    Copy-Item -path "C:\SFTP Template Structure\*" -Destination $path -Recurse

    #Checking if the SFTP Console is running
    $process = Get-Process | ?{$_.ProcessName -eq 'VShellCP'}
    if ($process -ne $null)
    {
        Stop-Process -Name VShellCP -Force
    }
    else 
    {
        write-host "VShell console is not running. Cofiguring user."
    }

    #Running a batch file for the sftp configuration
    $Comment = "Ticket#" + "$using:ticket_id"
    $homedir = "D:\PTPs\$using:companyname"
    try
    {
        set-content -path "\\pap01sftp\C$\SFTP Automation\User Files\$using:companyname.bat" -Value  "acl add crbcloud\$identity allow login sftp","sftp add $using:companyname $homedir $comment","sftp allow $using:companyname crbcloud\$identity","sftp togglehome $using:companyname crbcloud\$identity","save","exit"
        vshellconfig exec "\\pap01sftp\C$\SFTP Automation\User Files\$using:companyname.bat"
    }
    catch
    {
        Write-Error -message "$($Error)"
    }
    
    #uploading SFTP public key to zendesk, does not add it as a comment yet.
    $filepath = "\\pap01sftp\C$\SFTP Automation\publickey.txt"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
    $uri = "https://crossriver.zendesk.com/api/v2/uploads.json?filename=SFTP_pubKey.txt"
    $file = Invoke-RestMethod -Uri $uri -Method Post -ContentType test/plain -InFile $filepath -Headers @{Authorization=("Basic {0}" -f $using:base64AuthInfo)}

    #creating a password push URL with the relevant credentials
    $Days = 7
    $Views = 5
    $server = "pwpush.com"
    try
    {
        $Reply = Invoke-RestMethod -Method 'Post' -Uri "https://$Server/p.json" -ContentType "application/json" -Body ([pscustomobject]@{
        password = [pscustomobject]@{
                        payload = $using:securedpassword
                        expire_after_days = $Days
                        expire_after_views = $Views
                }
            } | ConvertTo-Json)
            $returnURL =  "https://$Server/p/$($Reply.url_token)"
    }
    catch
    {
        Write-Error -message "$($Error)"
    }

    #adding Internal notes
    $uri = "https://crossriver.zendesk.com/api/v2/tickets/$using:ticket_id"
    $commentbody = '{"ticket": {"comment": { "body": "Password can be retrived from this url:' + $($returnURL) + '.","public": false}}}'
    $comment = Invoke-RestMethod -Method Put -UseBasicParsing -ContentType "application/json" -Uri $uri -Headers @{Authorization=("Basic {0}" -f $using:base64AuthInfo)} -Body $commentbody

    #comments on the zendesk ticket with the SFTP publickey file
    $uploadstring = $file.upload.token
    $uri = "https://crossriver.zendesk.com/api/v2/tickets/$using:ticket_id"
    $commentbody = '{"ticket": {"comment": { "body": "Hello, the SFTP user has been created. Username: ' + $using:companyname + '.sftp Password can be retrived from ticket internal note section. SFTP URL: sftp01.crbnj.com, Port: 22", "uploads": "' + $($uploadstring) + '","public": true},"brand_id": "10735709383831","assignee_id": "400040863993"}}'
    $comment = Invoke-RestMethod -Method Put -UseBasicParsing -ContentType "application/json" -Uri $uri -Headers @{Authorization=("Basic {0}" -f $using:base64AuthInfo)} -Body $commentbody

    #remove the file from zendesk
    $uri = "https://crossriver.zendesk.com/api/v2/uploads/$($file.upload.token)"
    $removefile = Invoke-RestMethod -uri $uri -Method Delete -UseBasicParsing -Headers @{Authorization=("Basic {0}" -f $using:base64AuthInfo)} -ContentType "application/json"
}
