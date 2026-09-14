; 猫卷 Windows 安装包脚本（Inno Setup 6）
;
; 编译（推荐 —— 版本号与源目录都由发布脚本传入）：
;   ISCC.exe /DMyAppVersion=1.28.1 /DSrcDir="...\dist\猫卷-Windows-20260914" tools\maojuan_setup.iss
;
; 直接双击编译也可以，但 MyAppVersion 会退化成 0.0.0 —— 这是刻意的：
; 宁可版本号明显是错的，也不要静默沿用上一次的版本。
;
; 关于 SrcDir：以前这里写死了一个带日期的目录（dist\猫卷-Windows-20260911），
; 而发布脚本只替换版本号、从不更新它 —— 于是打包可能装进旧日期的绿色版内容。
; 现在改为由 publish_release.ps1 显式传入，与实际产物目录由构造保证一致。
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
; 项目根目录 = 本文件所在目录的上级。用 SourcePath 推导而不是写死绝对路径，
; 这样本地（D:\dev\flashcard_app）与 CI（windows-latest 的检出目录）都能编译。
#define ProjectRoot SourcePath + ".."
#ifndef SrcDir
  #define SrcDir ProjectRoot + "\dist\猫卷-Windows-未指定"
#endif
#ifndef OutDir
  #define OutDir ProjectRoot + "\dist"
#endif
#define MyAppName "猫卷"
#define MyAppPublisher "Damao"
#define MyAppExeName "flashcard_app.exe"

[Setup]
; 固定 AppId：升级安装时识别为同一应用（不随版本变化）
AppId={{8E9B7A32-5C4D-4E6F-9A1B-2C3D4E5F6A70}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\猫卷
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutDir}
OutputBaseFilename=猫卷-Setup-{#MyAppVersion}-Windows-x64
SetupIconFile={#ProjectRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; 支持「为所有用户安装 / 仅当前用户」二选一
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
; 安装前关闭正在运行的猫卷（防文件占用）
CloseApplications=yes
RestartApplications=no
; 数据目录提示：卸载保留 %LOCALAPPDATA%\flashcard_app 的题库数据
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
LicenseFile={#ProjectRoot}\tools\setup_license.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
; 绿色版全部文件（exe + 插件 DLL + data 资源），含使用说明
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 卸载不清理用户数据（题库/记录在 %LOCALAPPDATA%\flashcard_app），如需彻底清除由用户手动删除
