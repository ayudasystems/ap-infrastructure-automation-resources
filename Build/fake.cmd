@echo off

REM set build number to local if not specified
if [%BUILD_NUMBER%] EQU [] SET BUILD_NUMBER=local

SET BUILD_TOOLS_DIR=%~dp0.build
mkdir "%BUILD_TOOLS_DIR%"

echo Retrieve FAKE build tools
SET FAKE_VERSION=4.57.4
SET OCTOPUSTOOLS_VERSION=3.5.4
SET NUGET_VERSION=4.1.0
echo ^<Project Sdk="Microsoft.NET.Sdk"^>^<PropertyGroup^>^<TargetFramework^>netstandard1.0^</TargetFramework^>^</PropertyGroup^>^<ItemGroup^>^<PackageReference Include="Fake" Version="%FAKE_VERSION%" /^>^<PackageReference Include="NuGet.CommandLine" Version="%NUGET_VERSION%" /^>^<PackageReference Include="NuGet.CommandLine" Version="%NUGET_VERSION%" /^>^</ItemGroup^>^</Project^> > "%BUILD_TOOLS_DIR%\project.csproj"
dotnet restore "%BUILD_TOOLS_DIR%" --packages "%BUILD_TOOLS_DIR%"
del /F /Q "%BUILD_TOOLS_DIR%\project*.csproj"

@echo Start FAKE build
%BUILD_TOOLS_DIR%\FAKE\%FAKE_VERSION%\tools\Fake.exe --envvar deploymentSlot %DEPLOYMENT_SLOT% --fsiargs --reference:%BUILD_TOOLS_DIR%\FAKE\%FAKE_VERSION%\tools\FakeLib.dll build.fsx
if ERRORLEVEL 1 exit /b %ERRORLEVEL%