# RCpolycomAdminPasswordTool
Tool to pull the admin password for Polycom phones registered to Ringcentral

Setup Steps
1. Create the API app —
   --developers.ringcentral.com > Console > Create App > "REST API App",
   --auth type JWT auth flow,
   --app type Server/No UI.
   --Add permission 'Read Accounts'.
   --Note the API URL, Client ID and Client Secret someplace safe.
2.  Create a JWT credential —
    --In the dev portal, your profile > Credentials > Create JWT,
    --scoped to that app's Client ID (from the previous step) and "Production".
    --Copy the JWT string someplace safe.
3.  Setup the script -
    --Run the script once — it writes a template RCConfig.json in the folder where it is saved.
    --Edit the json file in a text editor
    --Fill in ClientId, ClientSecret, Jwt.
    --Save
4.  Run the script - It should prompt for the extension or serial number you want to work with and it will return the admin password
