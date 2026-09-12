; 猫卷 Windows 安装包脚本（Inno Setup 6）
; 编译：& "C:\Users\CTSwe\AppData\Local\Programs\Inno Setup 6\ISCC.exe" d:\dev\flashcard_app\tools\maojuan_setup.iss
#define MyAppName "猫卷"
#define MyAppVersion "1.28.1"
#define MyAppPublisher "Damao"
#define MyAppExeName "flashcard_app.exe"
#define SrcDir "d:\dev\flashcard_app\dist\猫卷-Windows-20260911"
#define OutDir "d:\dev\flashcard_app\dist"

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
SetupIconFile=d:\dev\flashcard_app\windows\runner\resources\app_icon.ico
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
LicenseFile=d:\dev\flashcard_app\tools\setup_license.txt

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
