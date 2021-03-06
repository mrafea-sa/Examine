$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path).FullName
$SolutionRoot = Split-Path -Path $PSScriptFilePath -Parent
$ProgFiles86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)");
$MSBuild = "$ProgFiles86\MSBuild\14.0\Bin\MSBuild.exe"

# Read XML
$buildXmlFile = (Join-Path $SolutionRoot "build.xml")
[xml]$buildXml = Get-Content $buildXmlFile

# Make sure we don't have a release folder for this version already
$BuildFolder = Join-Path -Path $SolutionRoot -ChildPath "build";
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Release";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}

# Set the version number in SolutionInfo.cs
$SolutionInfoPath = Join-Path -Path $SolutionRoot -ChildPath "src\SolutionInfo.cs"

# Set the copyright
$Copyright = "Copyright � Shannon Deminick " + (Get-Date).year
(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyCopyright\(`").*(?=`"\))", $Copyright |
	sc -Path $SolutionInfoPath -Encoding UTF8

# Iterate projects and update their versions
[System.Xml.XmlElement] $root = $buildXml.get_DocumentElement()
[System.Xml.XmlElement] $project = $null
foreach($project in $root.ChildNodes) {

	$projectPath = Join-Path -Path $SolutionRoot -ChildPath ("src\" + $project.id)
	$projectAssemblyInfo = Join-Path -Path $projectPath -ChildPath "Properties\AssemblyInfo.cs"
	$projectVersion = $project.version.Split("-")[0];

	Write-Host "Updating verion for $projectPath to $($project.version) ($projectVersion)"

	#update assembly infos with correct version

	(gc -Path $projectAssemblyInfo) `
		-replace "(?<=Version\(`")[.\d]*(?=`"\))", "$projectVersion.0" |
		sc -Path $projectAssemblyInfo -Encoding UTF8

	(gc -Path $projectAssemblyInfo) `
		-replace "(?<=AssemblyInformationalVersion\(`")[.\w-]*(?=`"\))", $project.version |
		sc -Path $projectAssemblyInfo -Encoding UTF8
}

# Build the solution in release mode
$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "Examine.sln"
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Rebuild
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

# Iterate projects and output them

# Go get nuget.exe if we don't hae it
$NuGet = "$BuildFolder\nuget.exe"
$FileExists = Test-Path $NuGet 
If ($FileExists -eq $False) {
	$SourceNugetExe = "http://nuget.org/nuget.exe"
	Invoke-WebRequest $SourceNugetExe -OutFile $NuGet
}

$include = @('*Examine*.dll','*Examine*.pdb','*Lucene*.dll','ICSharpCode.SharpZipLib.dll')
foreach($project in $root.ChildNodes) {
	$projectRelease = Join-Path -Path $ReleaseFolder -ChildPath "$($project.id)";
	New-Item $projectRelease -Type directory

	$projectBin = Join-Path -Path $SolutionRoot -ChildPath "src\$($project.id)\bin\Release";
	Copy-Item "$projectBin\*.*" -Destination $projectRelease -Include $include

	$nuSpecSource = Join-Path -Path $BuildFolder -ChildPath "Nuspecs\$($project.id)\*";
	Copy-Item $nuSpecSource -Destination $projectRelease
	$nuSpec = Join-Path -Path $projectRelease -ChildPath "$($project.id).nuspec";
		
	& $NuGet pack $nuSpec -OutputDirectory $ReleaseFolder -Version $project.version -Properties copyright=$Copyright
}


""
"Build is done!"