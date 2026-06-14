Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$BASE = "https://github.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/releases/latest/download"

# ── טעינת manifest ──────────────────────────────────────────────────
try {
    $manifest = Invoke-RestMethod "$BASE/manifest.json" -UseBasicParsing
} catch {
    [System.Windows.Forms.MessageBox]::Show("שגיאה בטעינת רשימת הספרים:`n$_", "שגיאה")
    exit
}
$roots = @($manifest | Where-Object { $_.depth -eq 0 } | Sort-Object label)

# ── בניית חלון ──────────────────────────────────────────────────────
$form = New-Object Windows.Forms.Form
$form.Text       = "הורדת מאגר ספרים — אוצריא"
$form.Size       = New-Object Drawing.Size(520, 540)
$form.StartPosition = "CenterScreen"
$form.RightToLeft = "Yes"
$form.RightToLeftLayout = $true
$form.Font       = New-Object Drawing.Font("Segoe UI", 10)

$lbl1 = New-Object Windows.Forms.Label
$lbl1.Text     = "בחר ספרים להורדה:"
$lbl1.Location = "10,10"
$lbl1.Size     = "460,22"
$form.Controls.Add($lbl1)

$list = New-Object Windows.Forms.CheckedListBox
$list.Location    = "10,35"
$list.Size        = "480,300"
$list.CheckOnClick = $true
foreach ($r in $roots) {
    $list.Items.Add("$($r.label)  ($($r.size))") | Out-Null
}
$form.Controls.Add($list)

$lbl2 = New-Object Windows.Forms.Label
$lbl2.Text     = "תיקיית יעד (ספרים של אוצריא):"
$lbl2.Location = "10,348"
$lbl2.Size     = "460,22"
$form.Controls.Add($lbl2)

$txtPath = New-Object Windows.Forms.TextBox
$txtPath.Location = "10,372"
$txtPath.Size     = "380,26"
$form.Controls.Add($txtPath)

$btnBrowse = New-Object Windows.Forms.Button
$btnBrowse.Text     = "..."
$btnBrowse.Location = "396,370"
$btnBrowse.Size     = "94,28"
$btnBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "בחר תיקיית ספרים של אוצריא"
    if ($dlg.ShowDialog() -eq "OK") { $txtPath.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowse)

$bar = New-Object Windows.Forms.ProgressBar
$bar.Location = "10,410"
$bar.Size     = "480,18"
$form.Controls.Add($bar)

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Location = "10,432"
$lblStatus.Size     = "480,22"
$lblStatus.Text     = ""
$form.Controls.Add($lblStatus)

$btnDl = New-Object Windows.Forms.Button
$btnDl.Text     = "הורד וחלץ"
$btnDl.Location = "160,462"
$btnDl.Size     = "180,38"
$btnDl.Font     = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$btnDl.Add_Click({
    if (-not $txtPath.Text -or -not (Test-Path $txtPath.Text)) {
        [Windows.Forms.MessageBox]::Show("בחר תיקיית יעד תקינה", "שגיאה")
        return
    }
    $sel = @()
    for ($i = 0; $i -lt $list.CheckedIndices.Count; $i++) {
        $sel += $roots[$list.CheckedIndices[$i]]
    }
    if ($sel.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show("בחר לפחות ספר אחד", "שגיאה")
        return
    }

    $btnDl.Enabled = $false
    $dest = $txtPath.Text
    $n = $sel.Count
    $done = 0

    foreach ($item in $sel) {
        $bar.Value = [int](($done / $n) * 100)
        $lblStatus.Text = "מוריד: $($item.label) ($($item.size))..."
        $form.Refresh()

        $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), $item.zip)
        try {
            (New-Object Net.WebClient).DownloadFile("$BASE/$($item.zip)", $tmp)

            $lblStatus.Text = "מחלץ: $($item.label)..."
            $form.Refresh()

            $outDir = Join-Path $dest ($item.path.Replace("/", "\"))
            Expand-Archive -LiteralPath $tmp -DestinationPath $outDir -Force
            Remove-Item $tmp -Force
            $done++
        } catch {
            [Windows.Forms.MessageBox]::Show("שגיאה ב-$($item.label):`n$_", "שגיאה")
            if (Test-Path $tmp) { Remove-Item $tmp -Force }
        }
    }

    $bar.Value  = 100
    $lblStatus.Text = "הושלם! $done/$n ספרים הורדו וחולצו בהצלחה."
    $btnDl.Enabled = $true
})
$form.Controls.Add($btnDl)

$form.ShowDialog() | Out-Null
