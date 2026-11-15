# Checks from OUTSIDE (run on your own Windows computer) that /private/ really is private. Windows PowerShell version of gate-test.sh.
#   powershell -ExecutionPolicy Bypass -File tools\gate-test.ps1 -Domain sanjaysubramanian.com -User me
# Needs curl.exe (included with Windows 10 and later). Asks for the password with the typing hidden; nothing is stored.
param(
  [Parameter(Mandatory = $true)][string]$Domain,
  [Parameter(Mandatory = $true)][string]$User
)
$secure = Read-Host "Password for $User" -AsSecureString
$plain = [System.Net.NetworkCredential]::new("", $secure).Password
$script:failed = $false

function Get-Code {
  param([string[]]$CurlArgs)
  # -s quiet, -o NUL throw the page away, -w print only the status code
  return (& curl.exe -s -o NUL -w "%{http_code}" @CurlArgs)
}
function Check {
  param([string]$Name, [string]$Wanted, [string]$Got)
  if ($Wanted -eq $Got) { Write-Host "PASS: $Name ($Got)" }
  else { Write-Host "FAIL: $Name (wanted $Wanted, got $Got)"; $script:failed = $true }
}

Check "public home page"                      "200" (Get-Code @("https://$Domain/"))
Check "private page, no password"             "401" (Get-Code @("https://$Domain/private/index.html"))
Check "private page, wrong password"          "401" (Get-Code @("-u", "${User}:definitely-wrong", "https://$Domain/private/index.html"))
Check "private page, right password"          "200" (Get-Code @("-u", "${User}:$plain", "https://$Domain/private/index.html"))
Check "plain-http address redirects to https" "301" (Get-Code @("http://$Domain/private/index.html"))

if ($script:failed) { exit 1 } else { exit 0 }
