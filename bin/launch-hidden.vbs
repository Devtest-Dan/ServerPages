Set WshShell = CreateObject("WScript.Shell")
' Find node.exe from PATH
Set objExec = WshShell.Exec("cmd /c where node")
nodePath = Trim(objExec.StdOut.ReadLine())
WshShell.Run """" & nodePath & """ ""D:\ServerPages\server\server.js""", 0, False
