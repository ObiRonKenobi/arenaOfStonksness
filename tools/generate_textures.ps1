$ErrorActionPreference = "Stop"
$key = [Environment]::GetEnvironmentVariable("GEMINI_API_KEY", "User")
if ([string]::IsNullOrWhiteSpace($key)) { throw "GEMINI_API_KEY is missing" }

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $root "project.godot"))) {
	$root = "c:\Users\sudol\arenaOfStonksness"
}
$outDir = Join-Path $root "assets\textures"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$jobs = @(
	@{ Name = "brick"; Prompt = "Square tileable video game albedo of a dirty tenement brick wall. Bold black ink outlines, cel-shaded comic style, muddy red bricks, grime in the mortar, flat lighting, no text, no people." },
	@{ Name = "planks"; Prompt = "Square tileable video game albedo of worn wooden barricade planks. Bold black ink outlines, cel-shaded, dirty brown boards with nail holes, flat lighting, no text, no people." },
	@{ Name = "punk"; Prompt = "Character concept sheet of a young Hispanic male punk rocker, spiked hair, patches, high-strung expression, full body front view, bold ink outlines, cel-shaded comic, dirty saturated colors, plain gray background, no text." },
	@{ Name = "hobo"; Prompt = "Character concept sheet of a white male hobo in a worn coat, calm wise eyes, beard, full body front view, bold ink outlines, cel-shaded comic, dirty saturated colors, plain gray background, no text." },
	@{ Name = "dreads"; Prompt = "Character concept sheet of a Black woman with long dreadlocks, relaxed stoner energy, jacket, full body front view, bold ink outlines, cel-shaded comic, dirty saturated colors, plain gray background, no text." },
	@{ Name = "lazy"; Prompt = "Character concept sheet of a young Asian man who looks sleepy and lazy, loose hoodie, half-closed eyes, full body front view, bold ink outlines, cel-shaded comic, dirty saturated colors, plain gray background, no text." },
	@{ Name = "rich_horde"; Prompt = "Character concept sheet of three cartoon rich villains side by side: a tax collector with a briefcase, a stockbroker in a loud suit, and a short king with a crown. Bold ink outlines, cel-shaded comic, plain gray background, no text." }
)

$models = @("gemini-2.5-flash-image", "gemini-nano-banana-2.1", "gemini-3.1-flash-image")

function Save-GeminiImage([string]$model, [string]$prompt, [string]$dest) {
	$bodyObj = @{
		contents = @(@{ role = "user"; parts = @(@{ text = $prompt }) })
		generationConfig = @{ responseModalities = @("IMAGE") }
	}
	$json = $bodyObj | ConvertTo-Json -Depth 8 -Compress
	$uri = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
	$headers = @{ "x-goog-api-key" = $key; "Content-Type" = "application/json" }
	$resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json
	$parts = @($resp.candidates[0].content.parts)
	foreach ($part in $parts) {
		$data = $null
		if ($part.PSObject.Properties.Name -contains "inlineData" -and $part.inlineData.data) { $data = $part.inlineData.data }
		elseif ($part.PSObject.Properties.Name -contains "inline_data" -and $part.inline_data.data) { $data = $part.inline_data.data }
		if ($data) {
			[IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($data))
			return $true
		}
	}
	return $false
}

$chosen = $null
foreach ($model in $models) {
	try {
		$test = Join-Path $outDir "brick.png"
		if (Save-GeminiImage $model $jobs[0].Prompt $test) {
			$chosen = $model
			Write-Output "model=$model saved=brick.png"
			break
		}
		Write-Output "model=$model no-image"
	} catch {
		$msg = $_.Exception.Message
		if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
		Write-Output "model=$model fail=$msg"
	}
}
if (-not $chosen) { throw "No Gemini image model returned a picture" }

foreach ($job in $jobs) {
	if ($job.Name -eq "brick") { continue }
	$dest = Join-Path $outDir ($job.Name + ".png")
	if (Save-GeminiImage $chosen $job.Prompt $dest) {
		Write-Output "saved=$($job.Name).png"
	} else {
		Write-Output "empty=$($job.Name)"
	}
}
