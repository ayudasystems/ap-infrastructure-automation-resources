@echo off

REM Convert params to Environment Variables
:loop
IF "%~1"=="" GOTO cont
SET %~1=%~2
@echo Env Variable "%~1" set to "%~2"
SHIFT & SHIFT & GOTO loop
:cont


if [%BUILD_NUMBER%] EQU [] SET BUILD_NUMBER=local
if [%DEPLOYMENT_SLOT%] EQU [] SET DEPLOYMENT_SLOT=CI
if [%IS_VALIDATION_BUILD%] EQU [] SET IS_VALIDATION_BUILD=0

SET BUILD_TOOLS_DIR=%~dp0.build
mkdir "%BUILD_TOOLS_DIR%"

echo Retrieve FAKE build tools
SET FAKE_VERSION=4.57.4
SET OCTOPUSTOOLS_VERSION=3.5.4
SET NUGET_VERSION=4.3.0
echo ^<Project Sdk="Microsoft.NET.Sdk"^>^<PropertyGroup^>^<TargetFramework^>netstandard1.0^</TargetFramework^>^</PropertyGroup^>^<ItemGroup^>^<PackageReference Include="Fake" Version="%FAKE_VERSION%" /^>^<PackageReference Include="NuGet.CommandLine" Version="%NUGET_VERSION%" /^>^<PackageReference Include="NuGet.CommandLine" Version="%NUGET_VERSION%" /^>^</ItemGroup^>^</Project^> > "%BUILD_TOOLS_DIR%\project.csproj"
dotnet restore "%BUILD_TOOLS_DIR%" --packages "%BUILD_TOOLS_DIR%"
del /F /Q "%BUILD_TOOLS_DIR%\project*.csproj"

@echo Start FAKE build
copy %BUILD_TOOLS_DIR%\FAKE\%FAKE_VERSION%\tools\FakeLib.dll %BUILD_TOOLS_DIR%\FAKE\FakeLib.dll
%BUILD_TOOLS_DIR%\FAKE\%FAKE_VERSION%\tools\Fake.exe build.fsx --envvar deploymentSlot=%DEPLOYMENT_SLOT%
if ERRORLEVEL 1 exit /b %ERRORLEVEL%
