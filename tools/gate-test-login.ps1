# Checks from OUTSIDE (run on your own Windows computer) that the site login works and private pages are private.
#   powershell -ExecutionPolicy Bypass -File tools\gate-test-login.ps1 -Domain sanjaysubramanian.com
# Needs curl.exe (Windows 10 and later). Asks for the passphrase with the typing hidden; nothing is stored. Makes ONE wrong attempt on purpose.
# Written without a Windows machine to run it on: if a check looks wrong, compare with tools/gate-test-login.sh.
param([Parameter(Mandatory = $true)][string]$Domain)
$secure = Read-Host "Passphrase" -AsSecureString
$plain = [System.Net.NetworkCredential]::new("", $secure).Password
$jar = [System.IO.Path]::GetTempFileName()
# The passphrase goes to curl through a temporary file, never on the command line: Windows PowerShell mangles quotes, backslashes and some
# other characters when it passes an argument to a program, which made the right passphrase look wrong. The file holds exactly the passphrase
# (no trailing newline, UTF-8 without a BOM), and is deleted at the end.
$pwfile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($pwfile, $plain, (New-Object System.Text.UTF8Encoding($false)))
$script:failed = $false
function Get-Code { param([string[]]$CurlArgs) return (& curl.exe -s -o NUL -w "%{http_code}" @CurlArgs) }
function Check {
  param([string]$Name, [string]$Wanted, [string]$Got)
  if ($Wanted -eq $Got) { Write-Host "PASS: $Name ($Got)" } else { Write-Host "FAIL: $Name (wanted $Wanted, got $Got)"; $script:failed = $true }
}
$base = "https://$Domain"
Check "public home page"                                  "200" (Get-Code @("$base/"))
Check "sign-in page is public"                            "200" (Get-Code @("$base/login"))
Check "private page, not signed in (script)"              "401" (Get-Code @("$base/private/index.html"))
Check "private page, not signed in (browser): to sign-in" "303" (Get-Code @("-H", "Accept: text/html", "$base/private/index.html"))
Check "sign-in with a wrong passphrase"                   "401" (Get-Code @("-c", $jar, "--data-urlencode", "passphrase=definitely-wrong", "$base/login"))
Check "sign-in with the right passphrase"                 "303" (Get-Code @("-c", $jar, "--data-urlencode", "passphrase@$pwfile", "$base/login"))
Check "private page, signed in"                           "200" (Get-Code @("-b", $jar, "$base/private/index.html"))
Check "sign out"                                          "303" (Get-Code @("-b", $jar, "-c", $jar, "-X", "POST", "$base/login/logout"))
Check "private page, after signing out"                   "401" (Get-Code @("-b", $jar, "$base/private/index.html"))
Check "plain-http address redirects to https"             "301" (Get-Code @("http://$Domain/login"))
Remove-Item $jar, $pwfile -ErrorAction SilentlyContinue
if ($script:failed) { exit 1 } else { exit 0 }
