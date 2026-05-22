# Mac Junk Cleaner — Windows
# Remove .DS_Store, ._* (resource forks), __MACOSX e outros arquivos macOS
# Requer: Windows PowerShell 5.1+ ou PowerShell 7+

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# C# helper: picker moderno IFileDialog (Vista+) — zero dependencias
if (-not ([System.Management.Automation.PSTypeName]'FolderDialog').Type) { Add-Type @"
using System;
using System.Runtime.InteropServices;

public class FolderDialog {
    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    [ClassInterface(ClassInterfaceType.None)]
    private class FileOpenDialogRCW {}

    [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog {
        [PreserveSig] int Show(IntPtr hwnd);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(uint fos);
        void GetOptions(out uint pfos);
        void SetDefaultFolder([MarshalAs(UnmanagedType.Interface)] IShellItem psi);
        void SetFolder([MarshalAs(UnmanagedType.Interface)] IShellItem psi);
        void GetFolder([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
        void GetCurrentSelection([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
        void AddPlace([MarshalAs(UnmanagedType.Interface)] IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare([MarshalAs(UnmanagedType.Interface)] IShellItem psi, uint hint, out int piOrder);
    }

    public static string ShowDialog(IntPtr parentHwnd, string title) {
        var dialog = new FileOpenDialogRCW() as IFileDialog;
        if (dialog == null) return null;
        try {
            dialog.SetOptions(0x00000020 | 0x00000040); // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
            if (!string.IsNullOrEmpty(title)) dialog.SetTitle(title);
            int hr = dialog.Show(parentHwnd);
            if (hr != 0) return null;
            IShellItem item;
            dialog.GetResult(out item);
            string path;
            item.GetDisplayName(0x80058000, out path); // SIGDN_FILESYSPATH
            Marshal.ReleaseComObject(item);
            return path;
        } finally {
            Marshal.ReleaseComObject(dialog);
        }
    }
}
"@ }

# C# helper: move itens para Lixeira via SHFileOperation (Win32 Shell) — suporta desfazer
if (-not ([System.Management.Automation.PSTypeName]'MacJunkDeleter').Type) { Add-Type @"
using System;
using System.IO;
using System.Collections;
using System.Threading;
using System.Runtime.InteropServices;

public class MacJunkDeleter {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT FileOp);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        [MarshalAs(UnmanagedType.U4)] public int wFunc;
        public string pFrom;
        public string pTo;
        public short fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }

    private const int   FO_DELETE          = 0x0003;
    private const short FOF_ALLOWUNDO      = 0x0040; // envia para Lixeira
    private const short FOF_NOCONFIRMATION = 0x0010;
    private const short FOF_SILENT         = 0x0004;
    private const short FOF_NOERRORUI      = 0x0400;

    public static void DeleteAsync(string[] items, Hashtable sync) {
        var t = new Thread(() => {
            int deleted = 0, errors = 0, progress = 0;
            foreach (string item in items) {
                if (string.IsNullOrEmpty(item)) { progress++; sync["progress"] = progress; continue; }

                // Item ja nao existe (pai removido antes) — conta como deletado
                bool isDir  = Directory.Exists(item);
                bool isFile = !isDir && File.Exists(item);
                if (!isDir && !isFile) {
                    deleted++; progress++;
                    sync["deleted"] = deleted; sync["progress"] = progress;
                    continue;
                }

                try {
                    // pFrom requer duplo null-terminator conforme API Win32
                    var op = new SHFILEOPSTRUCT {
                        hwnd   = IntPtr.Zero,
                        wFunc  = FO_DELETE,
                        pFrom  = item + "\0\0",
                        pTo    = null,
                        fFlags = unchecked((short)(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI))
                    };
                    int ret = SHFileOperation(ref op);
                    if (ret == 0 && !op.fAnyOperationsAborted) deleted++;
                    else errors++;
                } catch { errors++; }

                progress++;
                sync["deleted"]  = deleted;
                sync["errors"]   = errors;
                sync["progress"] = progress;
            }
            sync["done"] = true;
        });
        t.IsBackground = true;
        t.SetApartmentState(ApartmentState.STA); // Shell API requer STA
        t.Start();
    }
}
"@ }

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mac Junk Cleaner"
        Height="450" Width="520"
        MinHeight="450" MinWidth="520"
        WindowStartupLocation="CenterScreen"
        AllowDrop="True"
        FontFamily="Inter, Segoe UI"
        Background="#0d0d0d">
  <Window.Resources>

    <!-- Botao primario (accent creme) -->
    <Style x:Key="PBtn" TargetType="Button">
      <Setter Property="Background"      Value="#FDEABF"/>
      <Setter Property="Foreground"      Value="#0d0d0d"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontWeight"      Value="SemiBold"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="7" Padding="18,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#c9b78a"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Background" Value="#161616"/>
                <Setter Property="Foreground"  Value="#555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Botao secundario (surface) -->
    <Style x:Key="SBtn" TargetType="Button">
      <Setter Property="Background"      Value="#161616"/>
      <Setter Property="Foreground"      Value="#e8e8e8"/>
      <Setter Property="BorderBrush"     Value="#2a2a2a"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="7" Padding="14,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#1f1f1f"/>
                <Setter Property="BorderBrush" Value="#555"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Background" Value="#111"/>
                <Setter Property="Foreground"  Value="#555"/>
                <Setter Property="BorderBrush" Value="#161616"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Barra de progresso customizada -->
    <Style TargetType="ProgressBar">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border Name="PART_Track" Background="#161616" CornerRadius="4"/>
              <Border Name="PART_Indicator" Background="#FDEABF"
                      HorizontalAlignment="Left" CornerRadius="4"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Scrollbar customizado — thin, dark, sem arrows -->
    <Style TargetType="ScrollBar">
      <Setter Property="Background"  Value="Transparent"/>
      <Setter Property="Width"       Value="6"/>
      <Setter Property="MinWidth"    Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Border Background="#161616" CornerRadius="3" Margin="2,0"/>
              <Track x:Name="PART_Track" IsDirectionReversed="True" Focusable="False">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False" Opacity="0" Height="0"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Focusable="False">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="bg" Background="#2a2a2a" CornerRadius="3" Margin="2,1"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="bg" Property="Background" Value="#555"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="bg" Property="Background" Value="#FDEABF"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False" Opacity="0" Height="0"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Height"    Value="6"/>
          <Setter Property="MinHeight" Value="6"/>
          <Setter Property="Width"     Value="Auto"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="Transparent">
                  <Border Background="#161616" CornerRadius="3" Margin="0,2"/>
                  <Track x:Name="PART_Track" IsDirectionReversed="False" Focusable="False">
                    <Track.DecreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageLeftCommand" Focusable="False" Opacity="0" Width="0"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                      <Thumb Focusable="False">
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border x:Name="bg" Background="#2a2a2a" CornerRadius="3" Margin="1,2"/>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#555"/>
                              </Trigger>
                              <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#FDEABF"/>
                              </Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                      <RepeatButton Command="ScrollBar.PageRightCommand" Focusable="False" Opacity="0" Width="0"/>
                    </Track.IncreaseRepeatButton>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>

  </Window.Resources>

  <Grid Margin="26,22,26,22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Titulo -->
    <TextBlock Grid.Row="0" Text="Mac Junk Cleaner" FontSize="19" FontWeight="Bold"
               Foreground="#e8e8e8" Margin="0,0,0,20"/>

    <!-- Selecao de pasta -->
    <Grid Grid.Row="1" Margin="0,0,0,16">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnSelect" Content="Selecionar Pasta"
              Style="{StaticResource SBtn}" Grid.Column="0" Margin="0,0,10,0"/>
      <Border Grid.Column="1" Background="#161616" CornerRadius="7"
              BorderBrush="#2a2a2a" BorderThickness="1" Padding="12,10">
        <TextBlock x:Name="lblPath" Text="Nenhuma pasta selecionada"
                   Foreground="#555" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      </Border>
    </Grid>

    <!-- Drop hint (estado inicial — visivel ate primeiro scan) -->
    <Border x:Name="pnlDropHint" Grid.Row="2"
            Background="#111" CornerRadius="10"
            BorderBrush="#2a2a2a" BorderThickness="1.5"
            Padding="20,36" Margin="0,0,0,12"
            Visibility="Visible">
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
        <TextBlock Text="&#x2B07;" FontSize="22" Foreground="#333"
                   HorizontalAlignment="Center" Margin="0,0,0,10"/>
        <TextBlock Text="Arraste uma pasta aqui" FontSize="13" FontWeight="SemiBold"
                   Foreground="#555" HorizontalAlignment="Center" Margin="0,0,0,4"/>
        <TextBlock Text="ou use o botao Selecionar Pasta acima" FontSize="11"
                   Foreground="#333" HorizontalAlignment="Center"/>
      </StackPanel>
    </Border>

    <!-- Card de resultados (aparece apos primeiro scan) -->
    <Border x:Name="pnlResultsCard" Grid.Row="2" Background="#161616" CornerRadius="10"
            BorderBrush="#2a2a2a" BorderThickness="1"
            Padding="18,16" Margin="0,0,0,12"
            Visibility="Collapsed">
      <StackPanel>
        <TextBlock x:Name="lblCount"     Text="--"  FontSize="28" FontWeight="Bold" Foreground="#FDEABF"/>
        <TextBlock x:Name="lblSize"      Text=""    FontSize="12" Foreground="#888" Margin="0,2,0,0"/>
        <TextBlock x:Name="lblBreakdown" Text=""
                   Foreground="#888" FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/>
        <Button x:Name="btnToggle" Content="ver detalhes"
                Style="{StaticResource SBtn}" Visibility="Collapsed"
                HorizontalAlignment="Left" Margin="0,12,0,0" FontSize="11" Padding="10,6"/>
      </StackPanel>
    </Border>

    <!-- Lista de detalhes (colapsavel) — duplo clique abre pasta no Explorer -->
    <Border x:Name="pnlDetails" Grid.Row="3" Background="#111"
            CornerRadius="7" BorderBrush="#2a2a2a" BorderThickness="1"
            Margin="0,0,0,12" MaxHeight="150" Visibility="Collapsed">
      <ListBox x:Name="lstFiles" Background="Transparent" BorderThickness="0"
               Foreground="#888" FontFamily="Consolas, Courier New" FontSize="11" Padding="10,6"
               ScrollViewer.HorizontalScrollBarVisibility="Auto"
               ScrollViewer.VerticalScrollBarVisibility="Auto"
               ToolTip="Duplo clique para abrir a pasta no Explorer"/>
    </Border>

    <!-- Progresso -->
    <Grid Grid.Row="4" Margin="0,0,0,16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="0,0,0,5">
        <TextBlock x:Name="lblProgTxt" Text="" Foreground="#555" FontSize="11"/>
        <TextBlock x:Name="lblProgPct" Text="" Foreground="#555" FontSize="11" HorizontalAlignment="Right"/>
      </Grid>
      <ProgressBar x:Name="pbMain" Grid.Row="1" Height="7" Value="0" Maximum="100"/>
    </Grid>

    <!-- Botoes de acao -->
    <Grid Grid.Row="5" VerticalAlignment="Bottom">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="12"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnScan"   Content="Escanear"           Style="{StaticResource SBtn}" Grid.Column="0" IsEnabled="False"/>
      <Button x:Name="btnDelete" Content="Mover para Lixeira" Style="{StaticResource PBtn}" Grid.Column="2" IsEnabled="False"/>
    </Grid>

    <!-- Status -->
    <TextBlock x:Name="lblStatus" Grid.Row="6" Text="Pronto."
               Foreground="#555" FontSize="11" Margin="0,10,0,0"/>
  </Grid>
</Window>
"@

# ── Carregar janela ────────────────────────────────────────────────────────────
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$c = @{}
"btnSelect","lblPath","lblCount","lblBreakdown","lblSize",
"btnToggle","pnlDropHint","pnlResultsCard","pnlDetails","lstFiles",
"pbMain","lblProgTxt","lblProgPct","btnScan","btnDelete","lblStatus" | ForEach-Object {
    $c[$_] = $window.FindName($_)
}

# Estado da aplicacao
$app = [System.Collections.Hashtable]::Synchronized(@{
    folder      = ""
    items       = @()
    detailsOpen = $false
})

# ── Helpers ────────────────────────────────────────────────────────────────────
function Get-Brush([string]$hex) {
    $col = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    [System.Windows.Media.SolidColorBrush]::new($col)
}

# Calcula tamanho total de um arquivo ou pasta (recursivo)
function Get-ItemSize([string]$Path) {
    try {
        if ([System.IO.Directory]::Exists($Path)) {
            $sum = [long]0
            foreach ($f in [System.IO.Directory]::GetFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)) {
                try { $sum += ([System.IO.FileInfo]::new($f)).Length } catch {}
            }
            $sum
        } else {
            ([System.IO.FileInfo]::new($Path)).Length
        }
    } catch { [long]0 }
}

# Formata bytes em unidade legivel
function Format-Size([long]$bytes) {
    if     ($bytes -ge 1073741824) { "{0:F1} GB" -f ($bytes / 1073741824) }
    elseif ($bytes -ge 1048576)    { "{0:F1} MB" -f ($bytes / 1048576)    }
    elseif ($bytes -ge 1024)       { "{0:F0} KB" -f ($bytes / 1024)       }
    else                           { "$bytes B" }
}

# ── Scan: encontra arquivos macOS ──────────────────────────────────────────────
function Find-MacJunk([string]$Path) {
    $opts = @{ LiteralPath=$Path; Recurse=$true; Force=$true; ErrorAction='SilentlyContinue' }
    $list = [System.Collections.Generic.List[string]]::new()

    Get-ChildItem @opts -Filter ".DS_Store"       | Where-Object { -not $_.PSIsContainer } |
        ForEach-Object { $list.Add($_.FullName) }
    Get-ChildItem @opts                           | Where-Object { $_.Name -like "._*" -and -not $_.PSIsContainer } |
        ForEach-Object { $list.Add($_.FullName) }
    Get-ChildItem @opts -Filter "__MACOSX"        | Where-Object { $_.PSIsContainer } |
        ForEach-Object { $list.Add($_.FullName) }
    Get-ChildItem @opts -Filter ".Spotlight-V100" | Where-Object { $_.PSIsContainer } |
        ForEach-Object { $list.Add($_.FullName) }
    Get-ChildItem @opts -Filter ".Trashes"        | Where-Object { $_.PSIsContainer } |
        ForEach-Object { $list.Add($_.FullName) }

    $list | Select-Object -Unique | ForEach-Object { [string]$_ }
}

# ── Logica de scan (reutilizada por picker, drop e botao Escanear) ─────────────
$doScan = {
    $c["lblStatus"].Text          = "Escaneando..."
    $c["btnScan"].IsEnabled       = $false
    $c["btnDelete"].IsEnabled     = $false
    $c["lblCount"].Text           = "..."
    $c["lblSize"].Text            = ""
    $c["lblBreakdown"].Text       = "Buscando arquivos macOS..."
    $c["lblBreakdown"].Foreground = Get-Brush "#888"
    $c["lstFiles"].Items.Clear()
    $c["pbMain"].Value            = 0
    $c["lblProgTxt"].Text         = ""
    $c["lblProgPct"].Text         = ""

    # Transiciona para card de resultados (colapsa drop hint)
    $c["pnlDropHint"].Visibility    = "Collapsed"
    $c["pnlResultsCard"].Visibility = "Visible"

    # Libera UI antes de bloquear no scan
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

    $found     = @(Find-MacJunk -Path $app.folder)
    $app.items = $found

    if ($found.Count -eq 0) {
        $c["lblCount"].Text           = "0 itens"
        $c["lblSize"].Text            = ""
        $c["lblBreakdown"].Text       = "Pasta limpa! Nenhum arquivo macOS encontrado."
        $c["lblBreakdown"].Foreground = Get-Brush "#7AB898"
        $c["btnToggle"].Visibility    = "Collapsed"
        $c["lblStatus"].Text          = "Scan concluido. Pasta ja esta limpa."
    } else {
        # Tamanho total para liberar
        $totalBytes = [long]0
        foreach ($item in $found) { $totalBytes += Get-ItemSize $item }

        $ds = @($found | Where-Object { $_ -match "[/\\]\.DS_Store$"                }).Count
        $rf = @($found | Where-Object { (Split-Path $_ -Leaf) -like "._*"           }).Count
        $mx = @($found | Where-Object { (Split-Path $_ -Leaf) -eq "__MACOSX"        }).Count
        $sp = @($found | Where-Object { (Split-Path $_ -Leaf) -eq ".Spotlight-V100" }).Count
        $tr = @($found | Where-Object { (Split-Path $_ -Leaf) -eq ".Trashes"        }).Count

        $parts = @()
        if ($ds -gt 0) { $parts += ".DS_Store: $ds"   }
        if ($rf -gt 0) { $parts += "._*: $rf"         }
        if ($mx -gt 0) { $parts += "__MACOSX: $mx"    }
        if ($sp -gt 0) { $parts += ".Spotlight: $sp"  }
        if ($tr -gt 0) { $parts += ".Trashes: $tr"    }

        $c["lblCount"].Text           = "$($found.Count) itens encontrados"
        $c["lblSize"].Text            = "$(Format-Size $totalBytes) para liberar"
        $c["lblBreakdown"].Text       = ($parts -join "  $([char]0x00B7)  ")
        $c["lblBreakdown"].Foreground = Get-Brush "#888"
        $c["btnToggle"].Visibility    = "Visible"
        $c["btnDelete"].IsEnabled     = $true
        $c["lblStatus"].Text          = "Scan concluido. $($found.Count) itens prontos para mover para Lixeira."

        $found | ForEach-Object { $c["lstFiles"].Items.Add($_) | Out-Null }
    }
    $c["btnScan"].IsEnabled = $true
}.GetNewClosure()

# ── Helper interno: reseta detalhe aberto ─────────────────────────────────────
$closeDetails = {
    if ($app.detailsOpen) {
        $c["pnlDetails"].Visibility = "Collapsed"
        $c["btnToggle"].Content     = "ver detalhes"
        $app.detailsOpen            = $false
        $window.Height              = 450
    }
}.GetNewClosure()

# ── Eventos ────────────────────────────────────────────────────────────────────

# Selecionar pasta — picker moderno + auto-scan
$c["btnSelect"].Add_Click({
    $hwnd   = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    $picked = [FolderDialog]::ShowDialog($hwnd, "Selecionar pasta para limpar arquivos macOS")
    if ($picked) {
        $app.folder              = $picked
        $c["lblPath"].Text       = $picked
        $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        $c["btnScan"].IsEnabled  = $true
        & $closeDetails
        & $doScan
    }
})

# Escanear
$c["btnScan"].Add_Click({
    & $doScan
})

# Drag over — destaca zona de drop com cor accent
$window.Add_DragOver({
    $e = $args[1]
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
        $c["pnlDropHint"].BorderBrush    = Get-Brush "#FDEABF"
        $c["pnlResultsCard"].BorderBrush = Get-Brush "#FDEABF"
    } else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
    $e.Handled = $true
})

# Drag leave — remove destaque ao sair da janela
$window.Add_DragLeave({
    $e = $args[1]
    try {
        $pt = $e.GetPosition($window)
        if ($pt.X -le 0 -or $pt.Y -le 0 -or $pt.X -ge $window.ActualWidth -or $pt.Y -ge $window.ActualHeight) {
            $c["pnlDropHint"].BorderBrush    = Get-Brush "#2a2a2a"
            $c["pnlResultsCard"].BorderBrush = Get-Brush "#2a2a2a"
        }
    } catch {
        $c["pnlDropHint"].BorderBrush    = Get-Brush "#2a2a2a"
        $c["pnlResultsCard"].BorderBrush = Get-Brush "#2a2a2a"
    }
    $e.Handled = $true
})

# Drop — aceita pasta arrastada e dispara scan automatico
$window.Add_Drop({
    $e = $args[1]
    $c["pnlDropHint"].BorderBrush    = Get-Brush "#2a2a2a"
    $c["pnlResultsCard"].BorderBrush = Get-Brush "#2a2a2a"

    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files  = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        $folder = @($files) | Where-Object { [System.IO.Directory]::Exists($_) } | Select-Object -First 1
        if ($folder) {
            $app.folder              = $folder
            $c["lblPath"].Text       = $folder
            $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
            $c["btnScan"].IsEnabled  = $true
            & $closeDetails
            & $doScan
        }
    }
    $e.Handled = $true
})

# Duplo clique na lista — abre pasta pai no Explorer com item destacado
$c["lstFiles"].Add_MouseDoubleClick({
    $selected = $c["lstFiles"].SelectedItem
    if ($selected) {
        $parent = [System.IO.Path]::GetDirectoryName($selected)
        if ([System.IO.Directory]::Exists($parent)) {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$selected`""
        }
    }
})

# Toggle detalhes
$c["btnToggle"].Add_Click({
    $app.detailsOpen = -not $app.detailsOpen
    if ($app.detailsOpen) {
        $c["pnlDetails"].Visibility = "Visible"
        $c["btnToggle"].Content     = "ocultar detalhes"
        $window.Height = 600
    } else {
        $c["pnlDetails"].Visibility = "Collapsed"
        $c["btnToggle"].Content     = "ver detalhes"
        $window.Height = 450
    }
})

# Mover para Lixeira
$c["btnDelete"].Add_Click({
    $total = $app.items.Count
    $path  = $app.folder

    $r = [System.Windows.MessageBox]::Show(
        "Mover $total itens para a Lixeira?`n`n$path`n`nVoce pode restaura-los pela Lixeira do Windows.",
        "Confirmar",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $c["btnDelete"].IsEnabled  = $false
    $c["btnScan"].IsEnabled    = $false
    $c["btnSelect"].IsEnabled  = $false
    $c["pbMain"].Value         = 0
    $c["lblProgTxt"].Text      = "0 / $total"
    $c["lblProgPct"].Text      = "0%"
    $c["lblStatus"].Text       = "Movendo para Lixeira..."

    # Hashtable sincronizada: C# thread escreve, timer PS le
    $sync = [System.Collections.Hashtable]::Synchronized(@{
        progress = 0; deleted = 0; errors = 0; done = $false
    })
    $items = [string[]]$app.items

    # Timer de UI — atualiza progresso a cada 120ms
    $tmr = New-Object System.Windows.Threading.DispatcherTimer
    $tmr.Interval = [TimeSpan]::FromMilliseconds(120)

    $tickHandler = {
        $prog = [int]$sync["progress"]
        $pct  = if ($total -gt 0) { [int]($prog / $total * 100) } else { 0 }
        $c["pbMain"].Value    = $pct
        $c["lblProgPct"].Text = "$pct%"
        $c["lblProgTxt"].Text = "$prog / $total"

        if ($sync["done"]) {
            $tmr.Stop()
            $del = [int]$sync["deleted"]
            $err = [int]$sync["errors"]

            $c["pbMain"].Value         = 100
            $c["lblProgPct"].Text      = "100%"
            $c["lblProgTxt"].Text      = "Concluido"
            $c["btnSelect"].IsEnabled  = $true
            $c["btnScan"].IsEnabled    = $true
            $c["lstFiles"].Items.Clear()
            $c["pnlDetails"].Visibility = "Collapsed"
            $c["btnToggle"].Visibility  = "Collapsed"
            $app.detailsOpen            = $false
            $window.Height              = 450
            $app.items                  = @()

            if ($err -eq 0) {
                $c["lblCount"].Text           = "$del itens na Lixeira"
                $c["lblSize"].Text            = ""
                $c["lblBreakdown"].Text       = "Pasta limpa! Restaure pela Lixeira se necessario."
                $c["lblBreakdown"].Foreground = Get-Brush "#7AB898"
                $c["lblStatus"].Text          = "$del itens movidos para a Lixeira."
            } else {
                $c["lblCount"].Text           = "$del na Lixeira  $([char]0x00B7)  $err erros"
                $c["lblSize"].Text            = ""
                $c["lblBreakdown"].Text       = "Alguns itens nao puderam ser movidos (permissao negada?)."
                $c["lblBreakdown"].Foreground = Get-Brush "#C4907A"
                $c["lblStatus"].Text          = "$del movidos, $err erros. Verifique permissoes."
            }
        }
    }.GetNewClosure()

    $tmr.Add_Tick($tickHandler)
    $tmr.Start()

    # Dispara delecao em thread C# (sem PS runspace — thread-safe)
    [MacJunkDeleter]::DeleteAsync($items, $sync)
})

# ── Mostrar janela ─────────────────────────────────────────────────────────────
$window.ShowDialog() | Out-Null
