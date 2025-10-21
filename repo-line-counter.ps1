# TITLE: Repo Line Auditor
# Description: Are you onboarding SAST or DAST? Do you need a count of total lines of code across an entire project for costing purposes?
#              Do you need an overengineered and clanky solution?
#              Then enjoy!
# ASCII BANNER
$banner = @'
        _______ _____    _____                   _ _                ______   ______  ______  ______
   /\  (_______|____ \  / ___ \   /\            | (_)_             (_____ \ / __   |/ __   |/ __   |
  /  \    __    _   \ \| |   | | /  \  _   _  _ | |_| |_  ___   ____ ____) ) | //| | | //| | | //| |
 / /\ \  / /   | |   | | |   | |/ /\ \| | | |/ || | |  _)/ _ \ / ___)_____/| |// | | |// | | |// | |
| |__| |/ /____| |__/ /| |___| | |__| | |_| ( (_| | | |_| |_| | |   _______|  /__| |  /__| |  /__| |
|______(_______)_____/  \_____/|______|\____|\____|_|\___)___/|_|  (_______)\_____/ \_____/ \_____/
'@
Write-Host $banner -ForegroundColor Cyan
# CONFIG
$project = "ENTER-PROJECT-NAME-HERE"
$targetRepoName = "ENTER-REPO-NAME-HERE"
$branchName = "master"
# AUTH
$organisation = Read-Host "Enter your Azure DevOps organisation name"
$personalAccessToken = Read-Host "Enter your PAT" -AsSecureString
$plainTextToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($personalAccessToken)
)
$base64AuthInfo = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::ASCII.GetBytes(":$($plainTextToken)")
)
$headers = @{ Authorization = ("Basic {0}" -f $base64AuthInfo) }
# FETCH TARGET REPO
Write-Host "Fetching repository '$targetRepoName' in project '$project'..."
$reposUri = "https://dev.azure.com/$organisation/$project/_apis/git/repositories?api-version=6.0"
$reposResponse = Invoke-RestMethod -Uri $reposUri -Method Get -Headers $headers
$repo = $reposResponse.value | Where-Object { $_.name -eq $targetRepoName }
if (-not $repo) {
    Write-Host "ERROR: Repo '$targetRepoName' not found." -ForegroundColor Red
    exit
}
# FETCH FILES
$itemsUri = "https://dev.azure.com/$organisation/$project/_apis/git/repositories/$($repo.id)/items?scopePath=/&recursionLevel=Full&versionDescriptor.version=$branchName&versionDescriptor.versionType=branch&api-version=6.0"
$itemsResponse = Invoke-RestMethod -Uri $itemsUri -Method Get -Headers $headers
$files = $itemsResponse.value | Where-Object { $_.gitObjectType -eq "blob" }
$fileCount = $files.Count
Write-Host "Total files: $fileCount"
# INIT
$commitData = [PSCustomObject]@{
    Project   = $project
    RepoName  = $targetRepoName
    Branch    = $branchName
    FileCount = $fileCount
}
$lineData = @()
# LOOP FILES
$i = 0
foreach ($file in $files) {
    $i++
    $percent = [math]::Round(($i / $fileCount) * 100, 2)
    Write-Progress -Activity "Processing files..." -Status "$i of $fileCount" -PercentComplete $percent
    $filePath = $file.path
    $fileUrl = "https://dev.azure.com/$organisation/$project/_apis/git/repositories/$($repo.id)/items?path=$($filePath)&versionDescriptor.version=$branchName&versionDescriptor.versionType=branch&includeContent=true&api-version=6.0"
    try {
        $fileContent = Invoke-RestMethod -Uri $fileUrl -Method Get -Headers $headers
        $lineCount = ($fileContent -split "`n").Count
        $lineData += [PSCustomObject]@{
            FilePath  = $filePath
            LineCount = $lineCount
        }
    } catch {
        Write-Warning "Failed to read file: $filePath"
    }
}
# FINALIZE
Write-Progress -Activity "Processing files..." -Completed
# EXPORT
$summaryPath = "./azure_repo_filecounts.csv"
$detailPath = "./azure_repo_linecounts.csv"
$commitData | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
$lineData   | Export-Csv -Path $detailPath -NoTypeInformation -Encoding UTF8
Write-Host "`nFile summary written to: $summaryPath"
Write-Host "Line details written to: $detailPath"
Write-Host "Done."
