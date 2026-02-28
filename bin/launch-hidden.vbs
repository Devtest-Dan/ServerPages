Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory this script is in (bin\), then go up one level
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
rootDir = fso.GetParentFolderName(scriptDir)
serverJs = rootDir & "\server\server.js"

' Find node.exe from PATH
Set objExec = WshShell.Exec("cmd /c where node")
nodePath = Trim(objExec.StdOut.ReadLine())

WshShell.Run """" & nodePath & """ """ & serverJs & """", 0, False
