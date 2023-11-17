$user = "crb_service_not_a_real_email@crossriver.com/token"
$Token = ""
$uri = "https://crossriver.zendesk.com/api/v2/tickets/$ticket_id.json"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("$($user):$($Token)")))
$ticket_id = 446090

$uri = "https://crossriver.zendesk.com/api/v2/tickets/$ticket_id"
$commentbody = '{"ticket": {"comment": { "body": "Hello, the SFTP user has been created. Username: ' + $using:companyname + '.sftp Password can be retrived from ticket internal note section. SFTP URL: sftp01.crbnj.com, Port: 22", "uploads": "' + $($uploadstring) + '","public": true},"brand_id": "10735709383831","assignee_id": "400040863993"}}'
$comment = Invoke-RestMethod -Method Put -UseBasicParsing -ContentType "application/json" -Uri $uri -Headers @{Authorization=("Basic {0}" -f $using:base64AuthInfo)} -Body $commentbody


$a = Invoke-RestMethod -Method Get -UseBasicParsing -ContentType "application/json" -Uri $uri -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}