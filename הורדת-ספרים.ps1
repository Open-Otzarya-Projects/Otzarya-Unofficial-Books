if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    powershell.exe -ExecutionPolicy Bypass -STA -File $MyInvocation.MyCommand.Path
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {

$BASE = "https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download"

try {
    $manifest = Invoke-RestMethod "$BASE/manifest.json" -UseBasicParsing
} catch {
    [System.Windows.Forms.MessageBox]::Show("Error loading book list:`n$_")
    exit
}
$roots = @($manifest | Where-Object { $_.depth -eq 0 } | Sort-Object label)

$form = New-Object Windows.Forms.Form
$form.Text = "Otzarya Book Downloader"
$form.Size = New-Object Drawing.Size(520, 570)
$form.StartPosition = "CenterScreen"
$form.RightToLeft = "Yes"
$form.RightToLeftLayout = $true
$form.Font = New-Object Drawing.Font("Segoe UI", 10)

$lbl1 = New-Object Windows.Forms.Label
$lbl1.Text = "Select books to download:"
$lbl1.Location = "10,10"
$lbl1.Size = "490,22"
$form.Controls.Add($lbl1)

$list = New-Object Windows.Forms.CheckedListBox
$list.Location = "10,35"
$list.Size = "490,300"
$list.CheckOnClick = $true
foreach ($r in $roots) { $list.Items.Add("$($r.label)  ($($r.size))") | Out-Null }
$form.Controls.Add($list)

$lbl2 = New-Object Windows.Forms.Label
$lbl2.Text = "Target folder (Otzarya library root):"
$lbl2.Location = "10,348"
$lbl2.Size = "490,22"
$form.Controls.Add($lbl2)

$txtPath = New-Object Windows.Forms.TextBox
$txtPath.Location = "10,372"
$txtPath.Size = "385,26"
$form.Controls.Add($txtPath)

$btnBrowse = New-Object Windows.Forms.Button
$btnBrowse.Text = "..."
$btnBrowse.Location = "400,370"
$btnBrowse.Size = "100,28"
$btnBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq "OK") { $txtPath.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowse)

$bar = New-Object Windows.Forms.ProgressBar
$bar.Location = "10,412"
$bar.Size = "490,20"
$form.Controls.Add($bar)

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Location = "10,436"
$lblStatus.Size = "490,22"
$lblStatus.Text = ""
$form.Controls.Add($lblStatus)

$btnDl = New-Object Windows.Forms.Button
$btnDl.Text = "Download + Extract"
$btnDl.Location = "150,468"
$btnDl.Size = "200,40"
$btnDl.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$btnDl.Add_Click({
    if (-not $txtPath.Text -or -not (Test-Path $txtPath.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please choose a valid target folder.")
        return
    }
    $sel = @()
    for ($i = 0; $i -lt $list.CheckedIndices.Count; $i++) {
        $sel += $roots[$list.CheckedIndices[$i]]
    }
    if ($sel.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one book.")
        return
    }
    $btnDl.Enabled = $false
    $dest = $txtPath.Text
    $n = $sel.Count
    $done = 0
    foreach ($item in $sel) {
        $bar.Value = [int](($done / $n) * 100)
        $lblStatus.Text = "Downloading: $($item.label) ($($item.size))..."
        $form.Refresh()
        $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), $item.zip)
        try {
            (New-Object Net.WebClient).DownloadFile("$BASE/$($item.zip)", $tmp)
            $lblStatus.Text = "Extracting: $($item.label)..."
            $form.Refresh()
            $outDir = Join-Path $dest ($item.path.Replace("/", "\"))
            Expand-Archive -LiteralPath $tmp -DestinationPath $outDir -Force
            Remove-Item $tmp -Force
            $done++
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error on '$($item.label)':`n$_")
            if (Test-Path $tmp) { Remove-Item $tmp -Force }
        }
    }
    $bar.Value = 100
    $lblStatus.Text = "Done! $done of $n books downloaded and extracted."
    $btnDl.Enabled = $true
})
$form.Controls.Add($btnDl)
$form.ShowDialog() | Out-Null

} catch {
    $log = "$env:TEMP\otzarya_error.txt"
    $_ | Out-File $log -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Fatal error:`n$_`n`nLog: $log")
}
