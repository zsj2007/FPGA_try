# run_demo.ps1 -- One-click FPGA vision pipeline demo
# Usage: .\run_demo.ps1 "C:\video.mp4" [-Name prefix] [-Frames N] [-NoSim]

param(
    [Parameter(Mandatory=$true)]  [string]$VideoPath,
    [Parameter(Mandatory=$false)] [string]$Name = "",
    [Parameter(Mandatory=$false)] [int]$Frames = 0,
    [Parameter(Mandatory=$false)] [switch]$NoSim = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = "D:\new_FPGA"
$Vivado   = "D:\Xilinx\Vivado\2023.2\bin\vivado.bat"
$W = 640; $H = 400

if ($Name -eq "") {
    $Name = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
}
$InputRaw  = "$RepoRoot\sim\data\input\$($Name)_640x400.raw"
$OutputRaw = "$RepoRoot\sim\data\output\$($Name)_boxed_640x400.raw"
$DetsJson  = "$RepoRoot\sim\data\output\$($Name)_dets.json"
$OutputMp4 = "$RepoRoot\sim\data\output\$($Name)_boxed.mp4"
$TbFile    = "$RepoRoot\modules\vision_pipeline\vision_pipeline_video_tb.sv"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " FPGA Vision Pipeline Demo" -ForegroundColor Cyan
Write-Host "================================"
Write-Host "  Video : $VideoPath"
Write-Host "  Output: $OutputMp4"

# Step 1: Video -> RAW
Write-Host "`n[1/4] Converting video to RAW ..." -ForegroundColor Yellow
$frameArg = if ($Frames -gt 0) { @("--max-frames", $Frames) } else { @() }
python "$RepoRoot\sim\scripts\video_to_raw.py" $VideoPath $InputRaw --width $W --height $H @frameArg
if ($LASTEXITCODE -ne 0) { throw "Video conversion failed" }

$rawSize = (Get-Item $InputRaw).Length
$totalFrames = $rawSize / ($W * $H)
Write-Host "  Done: $totalFrames frames, $rawSize bytes" -ForegroundColor Green

# Step 2: Update TB file paths
Write-Host "`n[2/4] Updating TB paths ..." -ForegroundColor Yellow
$inputPat  = ($InputRaw  -replace "\\", "/")
$outputPat = ($OutputRaw -replace "\\", "/")
$detsPat   = ($DetsJson  -replace "\\", "/")

$tbLines = Get-Content $TbFile -Encoding UTF8
for ($i = 0; $i -lt $tbLines.Count; $i++) {
    if ($tbLines[$i] -match 'localparam string INPUT_FILE') {
        $tbLines[$i] = "    localparam string INPUT_FILE  = `"$inputPat`";"
    }
    if ($tbLines[$i] -match 'localparam string OUTPUT_FILE') {
        $tbLines[$i] = "    localparam string OUTPUT_FILE = `"$outputPat`";"
    }
    if ($tbLines[$i] -match 'localparam string DETS_FILE') {
        $tbLines[$i] = "    localparam string DETS_FILE   = `"$detsPat`";"
    }
}
[System.IO.File]::WriteAllLines($TbFile, $tbLines, [System.Text.UTF8Encoding]::new($false))
Write-Host "  Done" -ForegroundColor Green

# Step 3: Vivado simulation
if (-not $NoSim) {
    # Clean previous sim artifacts (prevents simulate.log lock)
    cmd /c "rmdir /s /q $RepoRoot\build\vivado\new_fpga.sim 2>nul"
    $estMin = [math]::Ceiling($totalFrames * 0.015)
    Write-Host "`n[3/4] Vivado sim ($totalFrames frames, ~$estMin min) ..." -ForegroundColor Yellow
    $startTime = Get-Date
    & $Vivado -mode batch -source "$RepoRoot\vivado\run_sim.tcl" -tclargs vision_pipeline_video_tb "$RepoRoot/build/vivado/new_fpga.xpr" -notrace
    if ($LASTEXITCODE -ne 0) { throw "Simulation failed" }
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-Host "  Done: ${elapsed} min" -ForegroundColor Green
} else {
    Write-Host "`n[3/4] Skipping simulation (-NoSim)" -ForegroundColor DarkYellow
}

# Step 4: Output RAW -> MP4
Write-Host "`n[4/4] Converting output RAW -> MP4 ..." -ForegroundColor Yellow
python "$RepoRoot\sim\convert_mp4.py" $OutputRaw $OutputMp4 $W $H
if ($LASTEXITCODE -ne 0) { throw "MP4 conversion failed" }
Write-Host "  Done: $OutputMp4" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Demo complete!" -ForegroundColor Cyan
Write-Host "  Result video : $OutputMp4" -ForegroundColor White
Write-Host "  Detections   : $DetsJson" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
