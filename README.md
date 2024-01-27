SFTP-OnBoarding repo:
The repo contain powershell code that runs inside a jekins container, the code executes when given a username and a ticket it.
1. The user is added to AD and then on boarded to the SFTP system.
2. the pipeline automatically commends on the ticket, sends the password using a secured url and closes the ticket. - currently works for Zendesk and SNOW.
