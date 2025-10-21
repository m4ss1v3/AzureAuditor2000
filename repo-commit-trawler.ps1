## TITLE:   Grimwoods over-engineered repo trawler
## DESCRIP: Trawls selected repos, dumps last 5 commits per repo.
##          As this is essentially just an API call you can modify quite simply to audit other AZDO related stuff
## USAGE:   - Generate Read Only PAT at either the Project or Organization tier.
##          - Create a CSV with a single column with ProjectName as the header. List out target projects.
##          - Run and follow the prompts.
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
# USER INPUTS
$organisation = Read-Host "Enter your Azure DevOps organisation name"
$personalAccessToken = Read-Host "Enter your PAT" -AsSecureString
$plainTextToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($personalAccessToken))
$base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($plainTextToken)"))
$headers = @{ Authorization = ("Basic {0}" -f $base64AuthInfo) }

# LOAD PROJECTS FROM CSV
$csvPath = "./target_projects.csv"
if (!(Test-Path $csvPath)) {
    Write-Error "Missing CSV file at $csvPath. It should contain a column 'ProjectName'"
    exit
}
$targetProjects = Import-Csv $csvPath | Select-Object -ExpandProperty ProjectName

# FETCH AND FILTER PROJECTS
Write-Host "Fetching project list..."
$projectsResponse = Invoke-RestMethod -Uri "https://dev.azure.com/$organisation/_apis/projects?api-version=6.0" -Method Get -Headers $headers
$projectNames = $projectsResponse.value.name | Where-Object { $_ -in $targetProjects }

# MAIN LOGIC
$commitData = @()
foreach ($project in $projectNames) {
    Write-Host "Processing project: $project"
    $reposResponse = Invoke-RestMethod -Uri "https://dev.azure.com/$organisation/$project/_apis/git/repositories?api-version=6.0" -Method Get -Headers $headers
    foreach ($repo in $reposResponse.value) {
        Write-Host "  → Repo: $($repo.name)"
        if ($repo.defaultBranch) {
            $branchName = $repo.defaultBranch -replace "^refs/heads/", ""
            $commitsUri = "https://dev.azure.com/$organisation/$project/_apis/git/repositories/$($repo.id)/commits?searchCriteria.itemVersion.version=$branchName&searchCriteria.itemVersion.versionType=branch&`$top=5&api-version=6.0"
            try {
                $commitsResponse = Invoke-RestMethod -Uri $commitsUri -Method Get -Headers $headers
                foreach ($commit in $commitsResponse.value) {
                    $commitData += [PSCustomObject]@{
                        Project       = $project
                        RepoName      = $repo.name
                        Committer     = $commit.committer.name
                        CommitDate    = $commit.committer.dat
                        CommitMessage = $commit.comment
                        CommitID      = $commit.commitId
                    }
                }
                if ($commitsResponse.value.Count -eq 0) {
                    $commitData += [PSCustomObject]@{v
                        Project       = $project
                        RepoName      = $repo.name
                        Committer     = "N/A"
                        CommitDate    = "No commits"
                        CommitMessage = "No commits"
                        CommitID      = "N/A"
                    }
                }
            } catch {
                Write-Host "    • Error fetching commits: $($_.Exception.Message)"
                $commitData += [PSCustomObject]@{
                    Project       = $project
                    RepoName      = $repo.name
                    Committer     = "Error"
                    CommitDate    = "Error"
                    CommitMessage = $_.Exception.Message
                    CommitID      = "Error"
                }
            }
        } else {
            Write-Host "    • No default branch set."
            $commitData += [PSCustomObject]@{
                Project       = $project
                RepoName      = $repo.name
                Committer     = "N/A"
                CommitDate    = "No default branch"
                CommitMessage = "N/A"
                CommitID      = "N/A"
            }
        }
    }
}
# OUTPUT
$outPath = "./azure_repo_commits.csv"
