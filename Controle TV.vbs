Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
strScriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
strAdb = strScriptDir & "\platform-tools\adb.exe"
strSetup = strScriptDir & "\setup.ps1"
strPs1 = strScriptDir & "\remote_gui.ps1"

If Not objFSO.FileExists(strAdb) Then
    ' Primeira vez neste notebook: baixa o adb.exe antes de abrir o controle.
    ' Mostra uma janela visivel so desta vez, para acompanhar o download.
    objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & strSetup & """", 1, True
End If

objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strPs1 & """", 0, False
