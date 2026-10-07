param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ImagePath,

    [ValidateSet("crop", "contain", "stretch")]
    [string]$Fit = "crop"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pythonExe = "C:\Users\Lenovo\miniconda3\python.exe"
$vivadoExe = "D:\Xilinx\Vivado\2023.2\bin\vivado.bat"
$inputRaw = Join-Path $repoRoot "sim\data\input\input_640x400.raw"
$inputPng = Join-Path $repoRoot "sim\data\output\input_preview.png"
$outputRaw = Join-Path $repoRoot "sim\data\output\boxed_640x400.raw"
$outputPng = Join-Path $repoRoot "sim\data\output\boxed_result.png"
$projectFile = Join-Path $repoRoot "build\vivado\new_fpga.xpr"

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "Image does not exist: $ImagePath"
}
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Python does not exist: $pythonExe"
}
if (-not (Test-Path -LiteralPath $vivadoExe)) {
    throw "Vivado does not exist: $vivadoExe"
}

& $pythonExe (Join-Path $PSScriptRoot "image_to_raw.py") `
    $ImagePath $inputRaw --fit $Fit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $pythonExe (Join-Path $PSScriptRoot "raw8_to_png.py") `
    $inputRaw $inputPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $repoRoot
try {
    $projectNeedsCreate = -not (Test-Path -LiteralPath $projectFile)
    if (-not $projectNeedsCreate) {
        $registeredImageTest = Select-String -LiteralPath $projectFile `
            -SimpleMatch "vision_pipeline_image_tb.sv" -Quiet
        $projectNeedsCreate = -not $registeredImageTest
    }

    if ($projectNeedsCreate) {
        Write-Host "Creating/updating the Vivado project..."
        & $vivadoExe -mode batch -source vivado/create_project.tcl
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado project creation failed. Close any Vivado window using this project and retry."
        }
    }

    & $vivadoExe -mode batch -source vivado/run_sim.tcl `
        -tclargs vision_pipeline_image_tb
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

& $pythonExe (Join-Path $PSScriptRoot "raw10_to_png.py") `
    $outputRaw $outputPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Input preview: $inputPng"
Write-Host "Boxed result: $outputPng"
Write-Host "Open both with:"
Write-Host "  Start-Process `"$inputPng`""
Write-Host "  Start-Process `"$outputPng`""
