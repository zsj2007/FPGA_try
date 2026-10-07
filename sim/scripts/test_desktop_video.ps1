param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$VideoPath,
    [ValidateSet("crop", "contain", "stretch")]
    [string]$Fit = "crop",
    [int]$MaxFrames = 0
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pythonExe = "C:\Users\Lenovo\miniconda3\python.exe"
$vivadoExe = "D:\Xilinx\Vivado\2023.2\bin\vivado.bat"

$inputRaw  = Join-Path $repoRoot "sim\data\input\video_640x400.raw"
$outputRaw = Join-Path $repoRoot "sim\data\output\boxed_video_640x400.raw"
$outputDets = Join-Path $repoRoot "sim\data\output\video_detections.json"
$outputVideo = Join-Path $repoRoot "sim\data\output\boxed_result.mp4"
$projectFile = Join-Path $repoRoot "build\vivado\new_fpga.xpr"

if (-not (Test-Path $VideoPath)) { throw "Video not found: $VideoPath" }

# Step 1: MP4 -> RAW8
Write-Host "=== Step 1/3: MP4 -> RAW8 ==="
$v2rArgs = @((Join-Path $PSScriptRoot "video_to_raw.py"), $VideoPath, $inputRaw, "--fit", $Fit)
if ($MaxFrames -gt 0) { $v2rArgs += "--max-frames", $MaxFrames }
& $pythonExe $v2rArgs; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$meta = Get-Content ($inputRaw + ".json") -Raw | ConvertFrom-Json
$fps = $meta.fps
Write-Host "Video: $($meta.frame_count) frames, $fps FPS"

# Step 2: Vivado simulation
Write-Host "=== Step 2/3: Vivado simulation ==="
Push-Location $repoRoot
try {
    & $vivadoExe -mode batch -source vivado/create_project.tcl
    if ($LASTEXITCODE -ne 0) { throw "Project creation failed" }
    & $vivadoExe -mode batch -source vivado/run_sim.tcl -tclargs vision_pipeline_video_tb
    if ($LASTEXITCODE -ne 0) { throw "Simulation failed" }
} finally { Pop-Location }

# Step 3: RAW -> MP4 (LOS data is already in detections JSON)
Write-Host "=== Step 3/3: RAW10/16 -> annotated MP4 ==="
& $pythonExe (Join-Path $PSScriptRoot "raw_to_video.py") $outputRaw $outputVideo --fps $fps --detections $outputDets
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nDone! Output: $outputVideo"
Write-Host "  Start-Process `"$outputVideo`""
