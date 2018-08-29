@echo off

REM Convert params to Environment Variables
:loop
IF "%~1"=="" GOTO cont
SET %~1=%~2
@echo Env Variable "%~1" set to "%~2"
SHIFT & SHIFT & GOTO loop
:cont

SET BUILD_TOOLS_DIR=%~dp0.build
mkdir "%BUILD_TOOLS_DIR%"

@echo Installing build tools
SET OCTOPUSTOOLS_VERSION=4.39.4
SET NUGET_VERSION=4.7.1
echo ^<Project Sdk="Microsoft.NET.Sdk"^>^<PropertyGroup^>^<TargetFramework^>netstandard1.0^</TargetFramework^>^</PropertyGroup^>^<ItemGroup^>^<PackageReference Include="OctopusTools" Version="%OCTOPUSTOOLS_VERSION%" /^>^<PackageReference Include="NuGet.CommandLine" Version="%NUGET_VERSION%" /^>^</ItemGroup^>^</Project^> > "%BUILD_TOOLS_DIR%\project.csproj"
dotnet restore "%BUILD_TOOLS_DIR%" --packages "%BUILD_TOOLS_DIR%"
del /F /Q "%BUILD_TOOLS_DIR%\project*.csproj"

@echo Installing Fake CLI
IF NOT EXIST "%BUILD_TOOLS_DIR%\fake.exe" (
  dotnet tool install fake-cli ^
    --tool-path %BUILD_TOOLS_DIR% ^
    --version 5.5.0
)

@echo Start FAKE build
"%BUILD_TOOLS_DIR%/fake.exe" run build.fsx

if ERRORLEVEL 1 exit /b %ERRORLEVEL%