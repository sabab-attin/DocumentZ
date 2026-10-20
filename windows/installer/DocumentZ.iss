#ifndef BundleDir
  #error BundleDir must point to the complete Flutter release folder.
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef OutputDir
  #define OutputDir "output"
#endif
#ifndef VcRedist
  #error VcRedist must point to Microsoft's signed x64 redistributable.
#endif
[Setup]
AppId={{4A350BCE-7ACB-4C38-A773-E5C501CA1D2D}
AppName=DocumentZ
AppVersion={#AppVersion}
AppPublisher=DocumentZ
AppPublisherURL=https://github.com/sabab-attin/DocumentZ
DefaultDirName={autopf}\DocumentZ
DefaultGroupName=DocumentZ
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=DocumentZ-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\DocumentZ.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
AppMutex=Local\DocumentZ.Desktop.Instance.v1
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#VcRedist}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall
[Icons]
Name: "{autoprograms}\DocumentZ"; Filename: "{app}\DocumentZ.exe"; WorkingDir: "{app}"
[Registry]
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "DocumentZ"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "DocumentZ"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Read documents, annotate, and edit PDFs."
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "DocumentZ"; ValueData: "Software\DocumentZ\Capabilities"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pdf"; ValueType: string; ValueData: "DocumentZ PDF document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pdf\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pdf\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.pdf"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".pdf"; ValueData: "DocumentZ.pdf"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.epub"; ValueType: string; ValueData: "DocumentZ EPUB document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.epub\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.epub\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.epub\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.epub"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".epub"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".epub"; ValueData: "DocumentZ.epub"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.txt"; ValueType: string; ValueData: "DocumentZ TXT document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.txt\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.txt\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.txt"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".txt"; ValueData: "DocumentZ.txt"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.md"; ValueType: string; ValueData: "DocumentZ MD document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.md\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.md\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.md"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".md"; ValueData: "DocumentZ.md"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.markdown"; ValueType: string; ValueData: "DocumentZ MARKDOWN document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.markdown\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.markdown\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".markdown"; ValueData: "DocumentZ.markdown"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.docx"; ValueType: string; ValueData: "DocumentZ DOCX document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.docx\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.docx\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.docx\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.docx"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".docx"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".docx"; ValueData: "DocumentZ.docx"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.doc"; ValueType: string; ValueData: "DocumentZ DOC document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.doc\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.doc\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.doc\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.doc"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".doc"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".doc"; ValueData: "DocumentZ.doc"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xlsx"; ValueType: string; ValueData: "DocumentZ XLSX document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xlsx\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xlsx\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.xlsx\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.xlsx"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".xlsx"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".xlsx"; ValueData: "DocumentZ.xlsx"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xls"; ValueType: string; ValueData: "DocumentZ XLS document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xls\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.xls\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.xls\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.xls"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".xls"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".xls"; ValueData: "DocumentZ.xls"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pptx"; ValueType: string; ValueData: "DocumentZ PPTX document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pptx\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.pptx\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.pptx\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.pptx"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".pptx"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".pptx"; ValueData: "DocumentZ.pptx"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ppt"; ValueType: string; ValueData: "DocumentZ PPT document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ppt\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ppt\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.ppt\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.ppt"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".ppt"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ppt"; ValueData: "DocumentZ.ppt"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odt"; ValueType: string; ValueData: "DocumentZ ODT document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odt\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odt\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.odt\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.odt"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".odt"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".odt"; ValueData: "DocumentZ.odt"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ods"; ValueType: string; ValueData: "DocumentZ ODS document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ods\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ods\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.ods\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.ods"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".ods"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ods"; ValueData: "DocumentZ.ods"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odp"; ValueType: string; ValueData: "DocumentZ ODP document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odp\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.odp\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.odp\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.odp"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".odp"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".odp"; ValueData: "DocumentZ.odp"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.rtf"; ValueType: string; ValueData: "DocumentZ RTF document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.rtf\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.rtf\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.rtf\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.rtf"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".rtf"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".rtf"; ValueData: "DocumentZ.rtf"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.html"; ValueType: string; ValueData: "DocumentZ HTML document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.html\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.html\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.html\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.html"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".html"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".html"; ValueData: "DocumentZ.html"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.htm"; ValueType: string; ValueData: "DocumentZ HTM document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.htm\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.htm\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.htm\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.htm"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".htm"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".htm"; ValueData: "DocumentZ.htm"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mhtml"; ValueType: string; ValueData: "DocumentZ MHTML document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mhtml\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mhtml\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.mhtml\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.mhtml"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".mhtml"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mhtml"; ValueData: "DocumentZ.mhtml"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mht"; ValueType: string; ValueData: "DocumentZ MHT document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mht\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mht\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.mht\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.mht"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".mht"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mht"; ValueData: "DocumentZ.mht"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mobi"; ValueType: string; ValueData: "DocumentZ MOBI document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mobi\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.mobi\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.mobi\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.mobi"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".mobi"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mobi"; ValueData: "DocumentZ.mobi"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.png"; ValueType: string; ValueData: "DocumentZ PNG document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.png\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.png\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.png\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.png"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".png"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".png"; ValueData: "DocumentZ.png"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpg"; ValueType: string; ValueData: "DocumentZ JPG document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpg\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpg\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.jpg\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.jpg"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".jpg"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpg"; ValueData: "DocumentZ.jpg"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpeg"; ValueType: string; ValueData: "DocumentZ JPEG document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpeg\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.jpeg\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.jpeg\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.jpeg"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".jpeg"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".jpeg"; ValueData: "DocumentZ.jpeg"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tiff"; ValueType: string; ValueData: "DocumentZ TIFF document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tiff\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tiff\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.tiff\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.tiff"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".tiff"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".tiff"; ValueData: "DocumentZ.tiff"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tif"; ValueType: string; ValueData: "DocumentZ TIF document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tif\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.tif\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.tif\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.tif"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".tif"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".tif"; ValueData: "DocumentZ.tif"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.bmp"; ValueType: string; ValueData: "DocumentZ BMP document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.bmp\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.bmp\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.bmp\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.bmp"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".bmp"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".bmp"; ValueData: "DocumentZ.bmp"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.gif"; ValueType: string; ValueData: "DocumentZ GIF document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.gif\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.gif\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.gif\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.gif"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".gif"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".gif"; ValueData: "DocumentZ.gif"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.svg"; ValueType: string; ValueData: "DocumentZ SVG document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.svg\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.svg\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.svg\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.svg"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".svg"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".svg"; ValueData: "DocumentZ.svg"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.eps"; ValueType: string; ValueData: "DocumentZ EPS document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.eps\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.eps\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.eps\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.eps"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".eps"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".eps"; ValueData: "DocumentZ.eps"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ps"; ValueType: string; ValueData: "DocumentZ PS document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ps\DefaultIcon"; ValueType: string; ValueData: "{app}\DocumentZ.exe,0"
Root: HKLM; Subkey: "Software\Classes\DocumentZ.ps\shell\open\command"; ValueType: string; ValueData: """{app}\DocumentZ.exe"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.ps\OpenWithProgids"; ValueType: string; ValueName: "DocumentZ.ps"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\Applications\DocumentZ.exe\SupportedTypes"; ValueType: string; ValueName: ".ps"; ValueData: ""
Root: HKLM; Subkey: "Software\DocumentZ\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ps"; ValueData: "DocumentZ.ps"
[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ runtime..."; Flags: waituntilterminated; Check: NeedsVCRuntime
Filename: "{app}\DocumentZ.exe"; Description: "Open DocumentZ"; Flags: nowait postinstall skipifsilent runasoriginaluser
[Code]
function NeedsVCRuntime: Boolean;
var Installed, Major, Minor, Build: Cardinal;
    Key: String;
begin
  Key := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  Result := True;
  if not RegQueryDWordValue(HKLM64, Key, 'Installed', Installed) then Exit;
  if Installed <> 1 then Exit;
  if not RegQueryDWordValue(HKLM64, Key, 'Major', Major) then Exit;
  if not RegQueryDWordValue(HKLM64, Key, 'Minor', Minor) then Exit;
  if not RegQueryDWordValue(HKLM64, Key, 'Bld', Build) then Exit;
  Result := (Major < {#RuntimeMajor}) or
    ((Major = {#RuntimeMajor}) and (Minor < {#RuntimeMinor})) or
    ((Major = {#RuntimeMajor}) and (Minor = {#RuntimeMinor}) and (Build < {#RuntimeBuild}));
end;

procedure FirewallRule(Action: String; Name: String; Extra: String);
var Code: Integer;
begin
  if not Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall ' + Action +
    ' rule name="' + Name + '" ' + Extra, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  if (Action = 'add') and (Code <> 0) then
    MsgBox('DocumentZ installed, but Windows could not allow its local sync connection. Your network policy may be managed by an administrator. Reading and editing still work.', mbInformation, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var ProgramPath: String;
begin
  if CurStep = ssPostInstall then begin
    ProgramPath := ExpandConstant('{app}\DocumentZ.exe');
    FirewallRule('delete', 'DocumentZ Private TCP Sync', '');
    FirewallRule('delete', 'DocumentZ Private UDP Discovery', '');
    FirewallRule('delete', 'DocumentZ Local TCP Sync', '');
    FirewallRule('delete', 'DocumentZ Local UDP Discovery', '');
    FirewallRule('add', 'DocumentZ Local TCP Sync',
      'dir=in action=allow program="' + ProgramPath + '" protocol=TCP localport=45831-45839 profile=private,public remoteip=localsubnet enable=yes');
    FirewallRule('add', 'DocumentZ Local UDP Discovery',
      'dir=in action=allow program="' + ProgramPath + '" protocol=UDP localport=45832 profile=private,public remoteip=localsubnet enable=yes');
  end;
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    FirewallRule('delete', 'DocumentZ Private TCP Sync', '');
    FirewallRule('delete', 'DocumentZ Private UDP Discovery', '');
    FirewallRule('delete', 'DocumentZ Local TCP Sync', '');
    FirewallRule('delete', 'DocumentZ Local UDP Discovery', '');
  end;
end;
