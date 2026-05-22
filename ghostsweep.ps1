# GhostSweep v1.0 — Windows
# Remove .DS_Store, ._* (resource forks), __MACOSX e outros arquivos fantasma do macOS
# Requer: Windows PowerShell 5.1+ ou PowerShell 7+
#
# Feito por Bruno Maia & Claude
# https://github.com/bguimaia/ghostsweep

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

# C# helper: move itens para Lixeira via SHFileOperation + suporte a cancelamento
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
    private const short FOF_ALLOWUNDO      = 0x0040;
    private const short FOF_NOCONFIRMATION = 0x0010;
    private const short FOF_SILENT         = 0x0004;
    private const short FOF_NOERRORUI      = 0x0400;

    public static void DeleteAsync(string[] items, Hashtable sync) {
        var t = new Thread(() => {
            int deleted = 0, errors = 0, progress = 0;
            foreach (string item in items) {
                // Verifica cancelamento antes de cada item
                object cancelObj = sync["cancel"];
                if (cancelObj != null && (bool)cancelObj) break;

                if (string.IsNullOrEmpty(item)) { progress++; sync["progress"] = progress; continue; }

                bool isDir  = Directory.Exists(item);
                bool isFile = !isDir && File.Exists(item);
                if (!isDir && !isFile) {
                    deleted++; progress++;
                    sync["deleted"] = deleted; sync["progress"] = progress;
                    continue;
                }

                try {
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
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
    }
}
"@ }

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GhostSweep v1.0"
        SizeToContent="Height"
        Width="600" MinWidth="580" MinHeight="520"
        WindowStartupLocation="CenterScreen"
        AllowDrop="True"
        FontFamily="Inter, Segoe UI"
        FontSize="13"
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

    <!-- Botao cancelar (laranja suave) -->
    <Style x:Key="CBtn" TargetType="Button">
      <Setter Property="Background"      Value="#2a1a0a"/>
      <Setter Property="Foreground"      Value="#C4907A"/>
      <Setter Property="BorderBrush"     Value="#3a2010"/>
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
                <Setter Property="Background" Value="#3a2515"/>
                <Setter Property="BorderBrush" Value="#C4907A"/>
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

    <!-- CheckBox customizado — dark theme -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#666"/>
      <Setter Property="Cursor"     Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Border x:Name="box" Width="13" Height="13" CornerRadius="3"
                      Background="Transparent" BorderBrush="#333" BorderThickness="1.5"
                      Margin="0,0,6,0" VerticalAlignment="Center">
                <TextBlock x:Name="chk" Text="&#x2713;" FontSize="9" FontWeight="Bold"
                           Foreground="#FDEABF" HorizontalAlignment="Center"
                           VerticalAlignment="Center" Margin="0,-1,0,0"
                           Visibility="Collapsed"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="BorderBrush"  Value="#FDEABF"/>
                <Setter TargetName="box" Property="Background"   Value="#1c1505"/>
                <Setter TargetName="chk" Property="Visibility"   Value="Visible"/>
                <Setter Property="Foreground" Value="#888"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="box" Property="BorderBrush" Value="#555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ListBoxItem customizado — dark theme sem highlight azul do sistema -->
    <Style TargetType="ListBoxItem">
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Cursor"  Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="bg" Background="Transparent"
                    CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#222"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bg" Property="Background" Value="#2a2a2a"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Botao icone flat (historico de pastas, contextos sem borda) -->
    <Style x:Key="IconBtn" TargetType="Button">
      <Setter Property="Background"   Value="Transparent"/>
      <Setter Property="BorderBrush"  Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor"       Value="Hand"/>
      <Setter Property="Padding"      Value="7,5"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="5"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#252525"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#303030"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Grid Margin="26,22,26,22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>  <!-- 0: Titulo -->
      <RowDefinition Height="Auto"/>  <!-- 1: Seletor de pasta -->
      <RowDefinition Height="Auto"/>  <!-- 2: Subpastas + toggle avancado -->
      <RowDefinition Height="Auto"/>  <!-- 3: Painel opcoes avancadas -->
      <RowDefinition Height="Auto"/>  <!-- 4: Drop hint / Card de resultados -->
      <RowDefinition Height="Auto"/>  <!-- 5: Detalhes (colapsavel) -->
      <RowDefinition Height="Auto"/>  <!-- 6: Progresso -->
      <RowDefinition Height="Auto"/>  <!-- 7: Botoes -->
      <RowDefinition Height="Auto"/>  <!-- 8: Status -->
      <RowDefinition Height="Auto"/>  <!-- 9: Atalhos hint -->
    </Grid.RowDefinitions>

    <!-- Titulo + Logo -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,20">
      <TextBlock Text="GhostSweep" FontSize="21" FontWeight="Bold"
                 Foreground="#e8e8e8" VerticalAlignment="Center"/>
    </StackPanel>

    <!-- Selecao de pasta -->
    <Grid Grid.Row="1" Margin="0,0,0,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnSelect" Style="{StaticResource SBtn}" Grid.Column="0" Margin="0,0,8,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="lblSelectIco" Text="&#x1F4C1;" FontFamily="Segoe UI Emoji" FontSize="14"
                     VerticalAlignment="Center" Margin="0,0,7,0"/>
          <TextBlock Text="Selecionar Pasta" VerticalAlignment="Center"/>
        </StackPanel>
      </Button>
      <!-- Path + botao de historico integrado no final do campo -->
      <Border x:Name="pathBorder" Grid.Column="1" Background="#161616" CornerRadius="7"
              BorderBrush="#2a2a2a" BorderThickness="1" Padding="12,6,4,6">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="lblPath" Grid.Column="0" Text="Nenhuma pasta selecionada"
                   Foreground="#555" VerticalAlignment="Center"
                   Background="Transparent" BorderThickness="0"
                   CaretBrush="#FDEABF" SelectionBrush="#5a4000"
                   FocusVisualStyle="{x:Null}" Padding="0,3"
                   ToolTip="Digite um caminho e pressione Enter"/>
          <!-- Botao historico — fim do campo, icone clock + seta -->
          <Grid Grid.Column="1" Margin="4,0,0,0">
            <Button x:Name="btnHistory" Style="{StaticResource IconBtn}"
                    IsEnabled="False" ToolTip="Pastas recentes">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="&#x1F550;" FontFamily="Segoe UI Emoji" FontSize="12"
                           Foreground="#555" VerticalAlignment="Center" Margin="0,0,4,0"/>
                <TextBlock Text="&#x25BE;" FontSize="10" Foreground="#555"
                           VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Popup x:Name="popHistory" Placement="Bottom" StaysOpen="False"
                   PlacementTarget="{Binding ElementName=pathBorder}"
                   AllowsTransparency="True" VerticalOffset="4">
              <Border Background="#1a1a1a" BorderBrush="#333" BorderThickness="1"
                      CornerRadius="7" Padding="4"
                      MinWidth="{Binding ActualWidth, ElementName=pathBorder}">
                <ListBox x:Name="lstHistory" Background="Transparent" BorderThickness="0"
                         Foreground="#ccc" FontSize="12" Padding="0" MaxHeight="160"/>
              </Border>
            </Popup>
          </Grid>
        </Grid>
      </Border>
    </Grid>

    <!-- Subpastas (proeminente) + toggle opcoes avancadas -->
    <Grid Grid.Row="2" Margin="0,0,0,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Vertical" VerticalAlignment="Center"
                  Margin="0,0,12,0">
        <CheckBox x:Name="chkRecursive" Content="Incluir subpastas" IsChecked="True"
                  FontSize="13" Foreground="#888"/>
        <TextBlock Text="Escaneia a pasta e todas as subpastas recursivamente"
                   FontSize="12" Foreground="#444" Margin="19,3,0,0"
                   TextWrapping="Wrap"/>
      </StackPanel>
      <Button x:Name="btnAdvanced" Grid.Column="1" Style="{StaticResource SBtn}"
              FontSize="12" Padding="10,7" VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="&#x2699;" FontFamily="Segoe UI Emoji" FontSize="13"
                     VerticalAlignment="Center" Margin="0,0,7,0"/>
          <TextBlock x:Name="lblAdvancedTxt"
                     Text="Op&#xE7;&#xF5;es Avan&#xE7;adas  &#x25BE;"
                     VerticalAlignment="Center"/>
        </StackPanel>
      </Button>
    </Grid>

    <!-- Painel de opcoes avancadas (colapsavel) — linhas zebradas -->
    <Border x:Name="pnlAdvanced" Grid.Row="3"
            Background="#111" CornerRadius="8"
            BorderBrush="#2a2a2a" BorderThickness="1"
            Margin="0,0,0,14" Visibility="Collapsed"
            ClipToBounds="True">
      <StackPanel>
        <TextBlock Text="TIPOS DE ARQUIVO" FontSize="11" FontWeight="SemiBold"
                   Foreground="#444" Margin="16,14,16,10"/>
        <!-- .DS_Store — linha clara -->
        <Border Background="#1a1a1a" Padding="16,9,16,9">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="145"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="chkDS" Content=".DS_Store" IsChecked="True" Grid.Column="0" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" Text="Indice do Finder com preferencias de icones e pastas"
                       Foreground="#555" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="8,0,0,0"/>
          </Grid>
        </Border>
        <!-- ._* — linha escura -->
        <Border Background="#111" Padding="16,9,16,9">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="145"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="chkRF" Content="._* (forks)" IsChecked="True" Grid.Column="0" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" Text="Resource forks do macOS em drives externos"
                       Foreground="#555" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="8,0,0,0"/>
          </Grid>
        </Border>
        <!-- __MACOSX — linha clara -->
        <Border Background="#1a1a1a" Padding="16,9,16,9">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="145"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="chkMX" Content="__MACOSX" IsChecked="True" Grid.Column="0" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" Text="Pasta oculta gerada ao zipar arquivos no macOS"
                       Foreground="#555" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="8,0,0,0"/>
          </Grid>
        </Border>
        <!-- .Spotlight — linha escura -->
        <Border Background="#111" Padding="16,9,16,9">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="145"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="chkSP" Content=".Spotlight-V100" IsChecked="True" Grid.Column="0" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" Text="Cache do Spotlight (busca do macOS) em volumes externos"
                       Foreground="#555" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="8,0,0,0"/>
          </Grid>
        </Border>
        <!-- .Trashes — linha clara -->
        <Border Background="#1a1a1a" Padding="16,9,16,9">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="145"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="chkTR" Content=".Trashes" IsChecked="True" Grid.Column="0" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" Text="Lixeira do macOS em volumes externos"
                       Foreground="#555" FontSize="12" TextWrapping="Wrap" VerticalAlignment="Center" Margin="8,0,0,0"/>
          </Grid>
        </Border>
      </StackPanel>
    </Border>

    <!-- Drop hint (estado inicial) -->
    <Border x:Name="pnlDropHint" Grid.Row="4"
            Background="#111" CornerRadius="10"
            BorderBrush="#2a2a2a" BorderThickness="1.5"
            Padding="20,36" Margin="0,0,0,12"
            Visibility="Visible">
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
        <TextBlock Text="&#x1F4C1;" FontFamily="Segoe UI Emoji" FontSize="36"
                   HorizontalAlignment="Center" Margin="0,0,0,12" Opacity="0.45"/>
        <TextBlock Text="Arraste uma pasta aqui" FontSize="15" FontWeight="SemiBold"
                   Foreground="#555" HorizontalAlignment="Center" Margin="0,0,0,4"/>
        <TextBlock Text="ou use o botao Selecionar Pasta acima" FontSize="12"
                   Foreground="#333" HorizontalAlignment="Center"/>
      </StackPanel>
    </Border>

    <!-- Card de resultados (aparece apos primeiro scan) -->
    <Border x:Name="pnlResultsCard" Grid.Row="4" Background="#161616" CornerRadius="10"
            BorderBrush="#2a2a2a" BorderThickness="1"
            Padding="18,16" Margin="0,0,0,12"
            Visibility="Collapsed">
      <StackPanel>
        <!-- Contagem -->
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="lblCount"      Text="--" FontSize="36" FontWeight="Bold" Foreground="#FDEABF"/>
          <TextBlock x:Name="lblCountLabel" Text=""   FontSize="15" Foreground="#888"
                     VerticalAlignment="Bottom" Margin="10,0,0,8"/>
        </StackPanel>
        <!-- Tamanho para liberar -->
        <TextBlock x:Name="lblSize" Text="" FontSize="15" FontWeight="SemiBold"
                   Foreground="#FDEABF" Margin="0,8,0,0"/>
        <!-- Breakdown por tipo (preenchido dinamicamente com cores) -->
        <StackPanel x:Name="spBreakdown" Margin="0,6,0,0"/>
        <!-- Botoes inferiores do card -->
        <WrapPanel Margin="0,14,0,0">
          <Button x:Name="btnToggle" Style="{StaticResource SBtn}" Visibility="Collapsed"
                  Margin="0,0,8,0" FontSize="13" Padding="12,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="lblToggleIco" Text="&#x25BC;"
                         FontSize="9" VerticalAlignment="Center" Margin="0,0,7,0"/>
              <TextBlock x:Name="lblToggleTxt" Text="Ver detalhes" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button x:Name="btnSaveLog" Style="{StaticResource SBtn}" Visibility="Collapsed"
                  Margin="0,0,8,0" FontSize="13" Padding="12,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="&#x1F4BE;" FontFamily="Segoe UI Emoji" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,7,0"/>
              <TextBlock Text="Salvar log" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button x:Name="btnOpenRecycleBin" Style="{StaticResource SBtn}" Visibility="Collapsed"
                  FontSize="13" Padding="12,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="&#x1F5D1;" FontFamily="Segoe UI Emoji" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,7,0"/>
              <TextBlock Text="Abrir Lixeira" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </WrapPanel>
      </StackPanel>
    </Border>

    <!-- Lista de detalhes (colapsavel) — duplo clique abre pasta no Explorer -->
    <Border x:Name="pnlDetails" Grid.Row="5" Background="#111"
            CornerRadius="7" BorderBrush="#2a2a2a" BorderThickness="1"
            Margin="0,0,0,12" MaxHeight="160" Visibility="Collapsed">
      <ListBox x:Name="lstFiles" Background="Transparent" BorderThickness="0"
               Foreground="#888" FontFamily="Consolas, Courier New" FontSize="12" Padding="10,6"
               ScrollViewer.HorizontalScrollBarVisibility="Auto"
               ScrollViewer.VerticalScrollBarVisibility="Auto"
               ToolTip="Duplo clique para abrir a pasta no Explorer"/>
    </Border>

    <!-- Progresso -->
    <Grid Grid.Row="6" Margin="0,0,0,0">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="0,0,0,5">
        <TextBlock x:Name="lblProgTxt" Text="" Foreground="#555" FontSize="12"/>
        <TextBlock x:Name="lblProgPct" Text="" Foreground="#555" FontSize="12" HorizontalAlignment="Right"/>
      </Grid>
      <ProgressBar x:Name="pbMain" Grid.Row="1" Height="7" Value="0" Maximum="100"/>
    </Grid>

    <!-- Botoes de acao -->
    <Grid Grid.Row="7" Margin="0,18,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="12"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnScan" Style="{StaticResource SBtn}" Grid.Column="0" IsEnabled="False">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock Text="&#x1F50D;" FontFamily="Segoe UI Emoji" FontSize="14"
                     VerticalAlignment="Center" Margin="0,0,8,0"/>
          <TextBlock Text="Escanear" VerticalAlignment="Center"/>
        </StackPanel>
      </Button>
      <!-- btnDelete e btnCancel compartilham col 2; so um visivel por vez -->
      <Grid Grid.Column="2">
        <Button x:Name="btnDelete" Style="{StaticResource PBtn}" IsEnabled="False" Visibility="Visible">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock Text="&#x1F5D1;" FontFamily="Segoe UI Emoji" FontSize="14"
                       VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock Text="Mover para Lixeira" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
        <Button x:Name="btnCancel" Style="{StaticResource CBtn}" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock Text="&#x2715;" FontSize="14"
                       VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock Text="Cancelar" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
      </Grid>
    </Grid>

    <!-- Status -->
    <TextBlock x:Name="lblStatus" Grid.Row="8" Text="Pronto."
               Foreground="#555" FontSize="13" Margin="0,12,0,0"/>

    <!-- Hints de atalhos — keycaps -->
    <StackPanel Grid.Row="9" Orientation="Horizontal" Margin="0,12,0,0">
      <Border Background="#1a1a1a" BorderBrush="#333" BorderThickness="1"
              CornerRadius="4" Padding="6,3" Margin="0,0,6,0">
        <TextBlock Text="Enter" Foreground="#888" FontSize="11"/>
      </Border>
      <TextBlock Text="Escanear" Foreground="#444" FontSize="11"
                 VerticalAlignment="Center" Margin="0,0,16,0"/>
      <Border Background="#1a1a1a" BorderBrush="#333" BorderThickness="1"
              CornerRadius="4" Padding="6,3" Margin="0,0,6,0">
        <TextBlock Text="Del" Foreground="#888" FontSize="11"/>
      </Border>
      <TextBlock Text="Mover" Foreground="#444" FontSize="11"
                 VerticalAlignment="Center" Margin="0,0,16,0"/>
      <Border Background="#1a1a1a" BorderBrush="#333" BorderThickness="1"
              CornerRadius="4" Padding="6,3" Margin="0,0,6,0">
        <TextBlock Text="Esc" Foreground="#888" FontSize="11"/>
      </Border>
      <TextBlock Text="Cancelar" Foreground="#444" FontSize="11"
                 VerticalAlignment="Center"/>
    </StackPanel>
  </Grid>
</Window>
"@

# ── Carregar janela ────────────────────────────────────────────────────────────
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$c = @{}
"btnSelect","pathBorder","lblPath","lblCount","lblCountLabel","lblSize","spBreakdown",
"lblSelectIco","lblAdvancedTxt","lblToggleTxt","lblToggleIco",
"btnToggle","btnSaveLog","btnOpenRecycleBin","btnAdvanced","pnlAdvanced","pnlDropHint","pnlResultsCard","pnlDetails","lstFiles",
"btnHistory","popHistory","lstHistory",
"pbMain","lblProgTxt","lblProgPct","btnScan","btnDelete","btnCancel","lblStatus",
"chkDS","chkRF","chkMX","chkSP","chkTR","chkRecursive" | ForEach-Object {
    $c[$_] = $window.FindName($_)
}

# Estado da aplicacao (sincronizado para acesso cross-thread)
$app = [System.Collections.Hashtable]::Synchronized(@{
    folder      = ""
    items       = @()
    detailsOpen = $false
    scanSync    = $null   # hashtable da operacao de scan em andamento
    deleteSync  = $null   # hashtable da operacao de delete em andamento
    scanPS      = $null   # instancia PowerShell do scan async
})

# ── Helpers ────────────────────────────────────────────────────────────────────
function Get-Brush([string]$hex) {
    $col = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    [System.Windows.Media.SolidColorBrush]::new($col)
}

# Adiciona uma linha de breakdown com tipo (cinza) e count (branco negrito)
function Add-BreakdownRow([System.Windows.Controls.StackPanel]$panel, [string]$tipo, [int]$count) {
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $row.Margin      = [System.Windows.Thickness]::new(0, 0, 0, 3)

    $lTipo  = New-Object System.Windows.Controls.TextBlock
    $lTipo.Text       = $tipo
    $lTipo.Foreground = Get-Brush "#666"
    $lTipo.FontSize   = 14
    $lTipo.Width      = 155

    $lNum  = New-Object System.Windows.Controls.TextBlock
    $lNum.Text       = $count.ToString("N0")
    $lNum.Foreground = Get-Brush "#e8e8e8"
    $lNum.FontSize   = 14
    $lNum.FontWeight = [System.Windows.FontWeights]::SemiBold

    $row.Children.Add($lTipo) | Out-Null
    $row.Children.Add($lNum)  | Out-Null
    $panel.Children.Add($row) | Out-Null
}

# Calcula tamanho de arquivo ou pasta (recursivo)
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

function Format-Size([long]$bytes) {
    if     ($bytes -ge 1073741824) { "{0:F1} GB" -f ($bytes / 1073741824) }
    elseif ($bytes -ge 1048576)    { "{0:F1} MB" -f ($bytes / 1048576)    }
    elseif ($bytes -ge 1024)       { "{0:F0} KB" -f ($bytes / 1024)       }
    else                           { "$bytes B" }
}

# Salva/carrega ultima pasta usada no registry
function Save-LastFolder([string]$path) {
    try {
        if (-not (Test-Path "HKCU:\Software\GhostSweep")) {
            New-Item -Path "HKCU:\Software\GhostSweep" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\GhostSweep" -Name "LastFolder" -Value $path
    } catch {}
}

function Load-LastFolder {
    try {
        (Get-ItemProperty -Path "HKCU:\Software\GhostSweep" -Name "LastFolder" -ErrorAction SilentlyContinue).LastFolder
    } catch { "" }
}

# Salva/carrega historico das ultimas 5 pastas usadas
function Save-FolderHistory([string]$path) {
    try {
        $regPath = "HKCU:\Software\GhostSweep"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        $raw  = (Get-ItemProperty -Path $regPath -Name "FolderHistory" -ErrorAction SilentlyContinue).FolderHistory
        $list = [System.Collections.Generic.List[string]]::new()
        if ($raw) { foreach ($f in ($raw -split "`n")) { if ($f.Trim()) { $list.Add($f.Trim()) } } }
        [void]$list.Remove($path)
        $list.Insert(0, $path)
        while ($list.Count -gt 5) { $list.RemoveAt($list.Count - 1) }
        Set-ItemProperty -Path $regPath -Name "FolderHistory" -Value ($list -join "`n")
    } catch {}
}

function Load-FolderHistory {
    try {
        $raw = (Get-ItemProperty -Path "HKCU:\Software\GhostSweep" -Name "FolderHistory" -ErrorAction SilentlyContinue).FolderHistory
        if ($raw) { @($raw -split "`n" | Where-Object { $_.Trim() -ne "" -and (Test-Path -LiteralPath $_.Trim() -PathType Container) }) }
        else { @() }
    } catch { @() }
}

# ── UI: reset para estado de scan em andamento ────────────────────────────────
$setScanningState = {
    $c["lblStatus"].Text          = "Escaneando..."
    $c["btnScan"].IsEnabled       = $false
    $c["btnDelete"].IsEnabled     = $false
    $c["btnDelete"].Visibility    = "Collapsed"
    $c["btnCancel"].Visibility    = "Visible"
    $c["lblCount"].Text           = "..."
    $c["lblCountLabel"].Text      = ""
    $c["lblSize"].Text            = ""
    $c["spBreakdown"].Children.Clear()
    $c["btnSaveLog"].Visibility        = "Collapsed"
    $c["btnOpenRecycleBin"].Visibility = "Collapsed"
    $c["lstFiles"].Items.Clear()
    $c["pbMain"].Value            = 0
    $c["lblProgTxt"].Text         = ""
    $c["lblProgPct"].Text         = ""

    # Transiciona para card de resultados
    $c["pnlDropHint"].Visibility    = "Collapsed"
    $c["pnlResultsCard"].Visibility = "Visible"
    & $syncWindowHeight
}.GetNewClosure()

# ── UI: popula card com resultados do scan ────────────────────────────────────
$showScanResults = {
    param([string[]]$found, [bool]$wasCancelled)

    $c["btnDelete"].Visibility = "Visible"
    $c["btnCancel"].Visibility = "Collapsed"
    $c["btnScan"].IsEnabled    = $true

    if ($wasCancelled) {
        $c["lblCount"].Text      = "--"
        $c["lblCountLabel"].Text = ""
        $c["lblStatus"].Text     = "Scan cancelado."
        return
    }

    if ($found.Count -eq 0) {
        $c["lblCount"].Text           = "0"
        $c["lblCountLabel"].Text      = "itens"
        $c["lblSize"].Text            = ""
        $c["spBreakdown"].Children.Clear()
        $c["btnSaveLog"].Visibility   = "Collapsed"
        $lOk = New-Object System.Windows.Controls.TextBlock
        $lOk.Text       = "Pasta limpa! Nenhum arquivo macOS encontrado."
        $lOk.Foreground = Get-Brush "#7AB898"
        $lOk.FontSize   = 14
        $c["spBreakdown"].Children.Add($lOk) | Out-Null
        $c["btnToggle"].Visibility    = "Collapsed"
        $c["lblStatus"].Text          = "Scan concluido. Pasta ja esta limpa."
    } else {
        $totalBytes = [long]0
        foreach ($item in $found) { $totalBytes += Get-ItemSize $item }
        $app["lastScanSize"] = $totalBytes

        $ds = @($found | Where-Object { $_ -match "[/\\]\.DS_Store$"                }).Count
        $rf = @($found | Where-Object { (Split-Path $_ -Leaf) -like "._*"           }).Count
        $mx = @($found | Where-Object { (Split-Path $_ -Leaf) -eq "__MACOSX"        }).Count
        $sp = @($found | Where-Object { (Split-Path $_ -Leaf) -eq ".Spotlight-V100" }).Count
        $tr = @($found | Where-Object { (Split-Path $_ -Leaf) -eq ".Trashes"        }).Count

        $numFmt = $found.Count.ToString("N0")
        $c["lblCount"].Text      = $numFmt
        $c["lblCountLabel"].Text = "itens encontrados"
        $c["lblSize"].Text       = "$(Format-Size $totalBytes) para liberar"

        $c["spBreakdown"].Children.Clear()
        if ($ds -gt 0) { Add-BreakdownRow $c["spBreakdown"] ".DS_Store"      $ds }
        if ($rf -gt 0) { Add-BreakdownRow $c["spBreakdown"] "._* (forks)"    $rf }
        if ($mx -gt 0) { Add-BreakdownRow $c["spBreakdown"] "__MACOSX"       $mx }
        if ($sp -gt 0) { Add-BreakdownRow $c["spBreakdown"] ".Spotlight-V100" $sp }
        if ($tr -gt 0) { Add-BreakdownRow $c["spBreakdown"] ".Trashes"       $tr }

        $c["btnToggle"].Visibility = "Visible"
        $c["btnDelete"].IsEnabled  = $true
        $c["lblStatus"].Text       = "$numFmt itens prontos para mover para Lixeira."
        $app["scanBreakdown"]      = @{ DS=$ds; RF=$rf; MX=$mx; SP=$sp; TR=$tr }

        $found | ForEach-Object { $c["lstFiles"].Items.Add($_) | Out-Null }
    }
    & $syncWindowHeight
}.GetNewClosure()

# ── Scan assincrono (PowerShell runspace dedicado) ────────────────────────────
$doScan = {
    # Sincroniza app.folder com o texto atual do campo (editar sem Enter tambem funciona)
    $typed = $c["lblPath"].Text.Trim()
    if ($typed -and $typed -ne "Nenhuma pasta selecionada") {
        if ([System.IO.Directory]::Exists($typed)) {
            if ($typed -ne $app.folder) {
                $app.folder              = $typed
                $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        & $resetPathError
                Save-LastFolder $typed
                Save-FolderHistory $typed
                & $updateHistoryBtn
            }
        } else {
            & $setPathError "Pasta nao encontrada. Verifique o caminho digitado."
            return
        }
    }

    if (-not $app.folder) { return }

    & $setScanningState

    # Captura estado dos filtros antes de spawnar thread
    $doDS  = [bool]$c["chkDS"].IsChecked
    $doRF  = [bool]$c["chkRF"].IsChecked
    $doMX  = [bool]$c["chkMX"].IsChecked
    $doSP  = [bool]$c["chkSP"].IsChecked
    $doTR  = [bool]$c["chkTR"].IsChecked
    $doRec = [bool]$c["chkRecursive"].IsChecked
    $scanPath = $app.folder

    $scanSync = [System.Collections.Hashtable]::Synchronized(@{
        done = $false; cancel = $false; result = $null; error = ""
    })
    $app["scanSync"] = $scanSync

    # Script de scan — roda em runspace separado, sem acesso a funcoes do script pai
    $scanScript = {
        param($scanPath, $sync, $doDS, $doRF, $doMX, $doSP, $doTR, $doRec)
        try {
            $list = [System.Collections.Generic.List[string]]::new()
            $opts = @{ LiteralPath=$scanPath; Force=$true; ErrorAction='SilentlyContinue' }
            if ($doRec) { $opts["Recurse"] = $true }

            if ($doDS -and -not $sync["cancel"]) {
                Get-ChildItem @opts -Filter ".DS_Store" |
                    Where-Object { -not $_.PSIsContainer } |
                    ForEach-Object { $list.Add($_.FullName) }
                $sync["found"] = $list.Count
            }
            if ($doRF -and -not $sync["cancel"]) {
                Get-ChildItem @opts |
                    Where-Object { $_.Name -like "._*" -and -not $_.PSIsContainer } |
                    ForEach-Object { $list.Add($_.FullName) }
                $sync["found"] = $list.Count
            }
            if ($doMX -and -not $sync["cancel"]) {
                Get-ChildItem @opts -Filter "__MACOSX" |
                    Where-Object { $_.PSIsContainer } |
                    ForEach-Object { $list.Add($_.FullName) }
                $sync["found"] = $list.Count
            }
            if ($doSP -and -not $sync["cancel"]) {
                Get-ChildItem @opts -Filter ".Spotlight-V100" |
                    Where-Object { $_.PSIsContainer } |
                    ForEach-Object { $list.Add($_.FullName) }
                $sync["found"] = $list.Count
            }
            if ($doTR -and -not $sync["cancel"]) {
                Get-ChildItem @opts -Filter ".Trashes" |
                    Where-Object { $_.PSIsContainer } |
                    ForEach-Object { $list.Add($_.FullName) }
                $sync["found"] = $list.Count
            }

            $sync["result"] = @($list | Select-Object -Unique | ForEach-Object { [string]$_ })
        } catch {
            $sync["error"]  = $_.Exception.Message
            $sync["result"] = @()
        }
        $sync["done"] = $true
    }

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($scanScript).AddParameters(@{
        scanPath = $scanPath; sync = $scanSync
        doDS = $doDS; doRF = $doRF; doMX = $doMX; doSP = $doSP; doTR = $doTR
        doRec = $doRec
    })
    $handle = $ps.BeginInvoke()
    $app["scanPS"]     = $ps
    $app["scanHandle"] = $handle

    # Timer: aguarda conclusao e atualiza UI
    $scanTmr = New-Object System.Windows.Threading.DispatcherTimer
    $scanTmr.Interval = [TimeSpan]::FromMilliseconds(200)

    $scanTick = {
        # Atualiza contador em tempo real enquanto scan ainda roda
        if (-not $scanSync["done"]) {
            $n = $scanSync["found"]
            if ($null -ne $n -and [int]$n -gt 0) {
                $c["lblCount"].Text      = ([int]$n).ToString("N0")
                $c["lblCountLabel"].Text = "encontrados..."
            }
            return
        }
        $scanTmr.Stop()
        try { $ps.EndInvoke($handle) | Out-Null } catch {}
        $ps.Dispose()
        $app["scanSync"] = $null

        $wasCancelled = [bool]$scanSync["cancel"]
        $found = if ($null -ne $scanSync["result"] -and -not $wasCancelled) {
            [string[]]$scanSync["result"]
        } else { @() }
        $app.items = $found

        & $showScanResults -found $found -wasCancelled $wasCancelled
    }.GetNewClosure()

    $scanTmr.Add_Tick($scanTick)
    $scanTmr.Start()
}.GetNewClosure()

# ── Helpers: estado de erro / sucesso no campo de path ───────────────────────
$setPathError = {
    param([string]$msg)
    $c["pathBorder"].BorderBrush     = Get-Brush "#C4907A"
    $c["pathBorder"].BorderThickness = [System.Windows.Thickness]::new(2)
    $c["lblPath"].Foreground         = Get-Brush "#C4907A"
    $c["lblStatus"].Text             = "$([char]0x26A0)  $msg"
    $c["lblStatus"].Foreground       = Get-Brush "#C4907A"
}.GetNewClosure()

$resetPathError = {
    $c["pathBorder"].BorderBrush     = Get-Brush "#2a2a2a"
    $c["pathBorder"].BorderThickness = [System.Windows.Thickness]::new(1)
    $c["lblStatus"].Foreground       = Get-Brush "#555"
}.GetNewClosure()

# ── Helper: fecha painel de detalhes ─────────────────────────────────────────
$closeDetails = {
    if ($app.detailsOpen) {
        $c["pnlDetails"].Visibility = "Collapsed"
        $c["lblToggleTxt"].Text     = "Ver detalhes"
        $c["lblToggleIco"].Text     = [char]0x25BC
        $app.detailsOpen            = $false
    }
}.GetNewClosure()

# ── Helper: re-aplica SizeToContent apos mudancas de layout ──────────────────
# DispatcherTimer garante disparo apos layout completo (BeginInvoke pode perder timing)
$syncWindowHeight = {
    $tmrH = New-Object System.Windows.Threading.DispatcherTimer
    $tmrH.Interval = [TimeSpan]::FromMilliseconds(60)
    $tmrH.Add_Tick({
        $tmrH.Stop()
        # Re-aplica SizeToContent para ajustar altura ao conteudo atual
        $window.SizeToContent = [System.Windows.SizeToContent]::Manual
        $window.SizeToContent = [System.Windows.SizeToContent]::Height
        # Apos layout concluir, trava MinHeight no novo tamanho
        $window.Dispatcher.BeginInvoke([Action]{
            if ($window.ActualHeight -gt 0) {
                $window.MinHeight = $window.ActualHeight
            }
        }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    }.GetNewClosure())
    $tmrH.Start()
}.GetNewClosure()

# ── Helper: habilita botao de historico se houver pastas salvas ───────────────
$updateHistoryBtn = {
    $h = Load-FolderHistory
    $c["btnHistory"].IsEnabled = ($h.Count -gt 0)
}.GetNewClosure()

# ── Eventos ────────────────────────────────────────────────────────────────────

# Toggle opcoes avancadas
$c["btnAdvanced"].Add_Click({
    if ($c["pnlAdvanced"].Visibility -eq "Visible") {
        $c["pnlAdvanced"].Visibility = "Collapsed"
        $c["lblAdvancedTxt"].Text    = "Op$([char]0xE7)$([char]0xF5)es Avan$([char]0xE7)adas  $([char]0x25BE)"
    } else {
        $c["pnlAdvanced"].Visibility = "Visible"
        $c["lblAdvancedTxt"].Text    = "Op$([char]0xE7)$([char]0xF5)es Avan$([char]0xE7)adas  $([char]0x25B4)"
    }
    & $syncWindowHeight
})

# Path editavel — Enter valida e escaneia; GotFocus seleciona tudo
$c["lblPath"].Add_GotFocus({
    if ($c["lblPath"].Text -ne "Nenhuma pasta selecionada") {
        $c["lblPath"].SelectAll()
    }
})

$c["lblPath"].Add_KeyDown({
    $e = $args[1]
    if ($e.Key.ToString() -eq "Return") {
        $typed = $c["lblPath"].Text.Trim()
        if ([System.IO.Directory]::Exists($typed)) {
            $app.folder              = $typed
            $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        & $resetPathError
            $c["btnScan"].IsEnabled  = $true
            & $closeDetails
            Save-LastFolder $typed
            Save-FolderHistory $typed
            & $updateHistoryBtn
            & $doScan
        } else {
            & $setPathError "Pasta nao encontrada. Verifique o caminho digitado."
        }
        $e.Handled = $true
    }
}.GetNewClosure())

# Historico de pastas — abre popup com ultimas 5
$c["btnHistory"].Add_Click({
    $history = Load-FolderHistory
    if (-not $history -or $history.Count -eq 0) { return }
    $c["lstHistory"].Items.Clear()
    foreach ($f in $history) { $c["lstHistory"].Items.Add($f) | Out-Null }
    $c["lstHistory"].SelectedIndex = -1
    $c["popHistory"].IsOpen = $true
})

$c["lstHistory"].Add_SelectionChanged({
    $sel = $c["lstHistory"].SelectedItem
    if ($sel -and [System.IO.Directory]::Exists($sel)) {
        $c["popHistory"].IsOpen = $false
        $app.folder              = $sel
        $c["lblPath"].Text       = $sel
        $c["lblPath"].ScrollToEnd()
        $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        & $resetPathError
        $c["btnScan"].IsEnabled  = $true
        & $closeDetails
        Save-LastFolder $sel
        Save-FolderHistory $sel
        & $updateHistoryBtn
        & $doScan
    }
})

# Hover 📁 → 📂 no botao de selecionar pasta
$c["btnSelect"].Add_MouseEnter({ $c["lblSelectIco"].Text = [System.Char]::ConvertFromUtf32(0x1F4C2) })
$c["btnSelect"].Add_MouseLeave({ $c["lblSelectIco"].Text = [System.Char]::ConvertFromUtf32(0x1F4C1) })

# Selecionar pasta — picker moderno + salva registry + auto-scan
$c["btnSelect"].Add_Click({
    $hwnd   = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    $picked = [FolderDialog]::ShowDialog($hwnd, "Selecionar pasta para limpar arquivos macOS")
    if ($picked) {
        $app.folder              = $picked
        $c["lblPath"].Text       = $picked
        $c["lblPath"].ScrollToEnd()
        $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        & $resetPathError
        $c["btnScan"].IsEnabled  = $true
        & $closeDetails
        Save-LastFolder $picked
        Save-FolderHistory $picked
        & $updateHistoryBtn
        & $doScan
    }
})

# Escanear
$c["btnScan"].Add_Click({
    & $doScan
})

# Cancelar — funciona para scan e delete
$c["btnCancel"].Add_Click({
    $sc = $app["scanSync"]
    if ($null -ne $sc) { $sc["cancel"] = $true }
    $dc = $app["deleteSync"]
    if ($null -ne $dc) { $dc["cancel"] = $true }
    $c["lblStatus"].Text = "Cancelando..."
    $c["btnCancel"].IsEnabled = $false
})

# Drag over — destaca zona de drop
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
            $c["lblPath"].ScrollToEnd()
            $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
        & $resetPathError
            $c["btnScan"].IsEnabled  = $true
            & $closeDetails
            Save-LastFolder $folder
            Save-FolderHistory $folder
            & $updateHistoryBtn
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
        $c["lblToggleTxt"].Text     = "Ocultar detalhes"
        $c["lblToggleIco"].Text     = [char]0x25B2
    } else {
        $c["pnlDetails"].Visibility = "Collapsed"
        $c["lblToggleTxt"].Text     = "Ver detalhes"
        $c["lblToggleIco"].Text     = [char]0x25BC
    }
    & $syncWindowHeight
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

    $c["btnDelete"].Visibility = "Collapsed"
    $c["btnCancel"].Visibility = "Visible"
    $c["btnCancel"].IsEnabled  = $true
    $c["btnScan"].IsEnabled    = $false
    $c["btnSelect"].IsEnabled  = $false
    $c["pbMain"].Value         = 0
    $c["lblProgTxt"].Text      = "0 / $total"
    $c["lblProgPct"].Text      = "0%"
    $c["lblStatus"].Text       = "Movendo para Lixeira..."

    $sync = [System.Collections.Hashtable]::Synchronized(@{
        progress = 0; deleted = 0; errors = 0; done = $false; cancel = $false
    })
    $app["deleteSync"] = $sync
    $items    = [string[]]$app.items
    $logSize  = if ($null -ne $app["lastScanSize"]) { [long]$app["lastScanSize"] } else { [long]0 }

    # Captura timestamps antes de deletar (arquivos ainda existem no disco)
    $app["logDateStart"] = [datetime]::Now
    $itemTimes = @{}
    foreach ($p in $items) {
        $fi = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($fi) { $itemTimes[$p] = $fi.LastWriteTime }
    }
    $app["logItemTimes"] = $itemTimes

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
            $app["deleteSync"] = $null

            $del = [int]$sync["deleted"]
            $err = [int]$sync["errors"]
            $delFmt = $del.ToString("N0")

            $c["pbMain"].Value         = 100
            $c["lblProgPct"].Text      = "100%"
            $c["lblProgTxt"].Text      = "Concluido"
            $c["btnSelect"].IsEnabled  = $true
            $c["btnCancel"].Visibility = "Collapsed"
            $c["lstFiles"].Items.Clear()
            $c["pnlDetails"].Visibility = "Collapsed"
            $c["btnToggle"].Visibility  = "Collapsed"
            $app.detailsOpen            = $false
            $app.items                  = @()

            $c["spBreakdown"].Children.Clear()

            if ($err -eq 0) {
                $c["lblCount"].Text      = $delFmt
                $c["lblCountLabel"].Text = "itens na Lixeira"
                $c["lblSize"].Text       = ""
                $lOk = New-Object System.Windows.Controls.TextBlock
                $lOk.Text       = "Pasta limpa! Restaure pela Lixeira se necessario."
                $lOk.Foreground = Get-Brush "#7AB898"
                $lOk.FontSize   = 14
                $c["spBreakdown"].Children.Add($lOk) | Out-Null
                $c["lblStatus"].Text = "$delFmt itens movidos para a Lixeira."
            } else {
                $c["lblCount"].Text      = $delFmt
                $c["lblCountLabel"].Text = "movidos  $([char]0x00B7)  $err erros"
                $c["lblSize"].Text       = ""
                $lErr = New-Object System.Windows.Controls.TextBlock
                $lErr.Text       = "Alguns itens nao puderam ser movidos (permissao negada?)."
                $lErr.Foreground = Get-Brush "#C4907A"
                $lErr.FontSize   = 14
                $c["spBreakdown"].Children.Add($lErr) | Out-Null
                $c["lblStatus"].Text = "$delFmt movidos, $err erros. Verifique permissoes."
            }

            # Guarda dados para log e exibe botoes de acao pos-delete
            $app["logItems"]     = $items
            $app["logFolder"]    = $path
            $app["logDate"]      = [datetime]::Now
            $app["logSize"]      = $logSize
            $app["logBreakdown"] = $app["scanBreakdown"]
            $c["btnSaveLog"].Visibility        = "Visible"
            $c["btnOpenRecycleBin"].Visibility = "Visible"

            # Restaura UI — usuario decide quando re-escanear
            $c["btnCancel"].Visibility = "Collapsed"
            $c["btnScan"].IsEnabled    = $true
            $c["btnSelect"].IsEnabled  = $true
            & $syncWindowHeight
        }
    }.GetNewClosure()

    $tmr.Add_Tick($tickHandler)
    $tmr.Start()

    [MacJunkDeleter]::DeleteAsync($items, $sync)
})

# Salvar log de limpeza
$c["btnSaveLog"].Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title            = "Salvar log de limpeza"
    $dlg.Filter           = "Arquivo de texto (*.txt)|*.txt"
    $startTs = if ($app["logDateStart"]) { $app["logDateStart"].ToString('yyyy-MM-dd_HH-mm-ss') } else { Get-Date -Format 'yyyy-MM-dd_HH-mm-ss' }
    $dlg.FileName         = "ghostsweep-$startTs.txt"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog($window)) {
        $logItems  = $app["logItems"]
        $logFolder = $app["logFolder"]
        $logDate   = $app["logDate"]
        $logSize   = if ($null -ne $app["logSize"]) { [long]$app["logSize"] } else { [long]0 }

        $logDateStart = $app["logDateStart"]
        $logItemTimes = $app["logItemTimes"]
        $logBreakdown = $app["logBreakdown"]

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("GhostSweep v1.0 $([char]0x2014) Log de limpeza")
        $lines.Add("=" * 60)
        $lines.Add("Inicio:  $($logDateStart.ToString('dd/MM/yyyy HH:mm:ss'))")
        $lines.Add("Fim:     $($logDate.ToString('dd/MM/yyyy HH:mm:ss'))")
        $lines.Add("Pasta:   $logFolder")
        $lines.Add("Total:   $($logItems.Count.ToString('N0')) itens  ($(Format-Size $logSize))")

        if ($logBreakdown) {
            $lines.Add("")
            $lines.Add("RESUMO POR TIPO:")
            if ($logBreakdown.DS -gt 0) { $lines.Add("  .DS_Store:        $($logBreakdown.DS.ToString('N0'))") }
            if ($logBreakdown.RF -gt 0) { $lines.Add("  ._* (forks):      $($logBreakdown.RF.ToString('N0'))") }
            if ($logBreakdown.MX -gt 0) { $lines.Add("  __MACOSX:         $($logBreakdown.MX.ToString('N0'))") }
            if ($logBreakdown.SP -gt 0) { $lines.Add("  .Spotlight-V100:  $($logBreakdown.SP.ToString('N0'))") }
            if ($logBreakdown.TR -gt 0) { $lines.Add("  .Trashes:         $($logBreakdown.TR.ToString('N0'))") }
        }

        $lines.Add("")
        $lines.Add("ITENS MOVIDOS PARA A LIXEIRA:")
        $lines.Add("-" * 60)
        $lines.Add("$("MODIFICADO EM".PadRight(22))ARQUIVO")
        $lines.Add("-" * 60)
        foreach ($item in $logItems) {
            $ts = if ($logItemTimes -and $logItemTimes.ContainsKey($item)) {
                $logItemTimes[$item].ToString('dd/MM/yyyy HH:mm:ss')
            } else { "                   " }
            $lines.Add("$($ts.PadRight(22))$item")
        }

        [System.IO.File]::WriteAllLines($dlg.FileName, $lines, [System.Text.Encoding]::UTF8)
        $c["lblStatus"].Text = "Log salvo: $($dlg.FileName)"
    }
}.GetNewClosure())

# Abrir Lixeira do Windows
$c["btnOpenRecycleBin"].Add_Click({
    Start-Process "explorer.exe" -ArgumentList "shell:RecycleBinFolder"
})

# Atalhos de teclado — Enter: escanear | Delete: mover lixeira | Escape: cancelar
$window.Add_KeyDown({
    $e = $args[1]
    switch ($e.Key.ToString()) {
        "Return" {
            if ($c["btnScan"].IsEnabled) { & $doScan; $e.Handled = $true }
        }
        "Delete" {
            if ($c["btnDelete"].IsEnabled -and $c["btnDelete"].Visibility -eq "Visible") {
                [void]$c["btnDelete"].RaiseEvent(
                    (New-Object System.Windows.RoutedEventArgs(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $e.Handled = $true
            }
        }
        "Escape" {
            if ($c["btnCancel"].Visibility -eq "Visible" -and $c["btnCancel"].IsEnabled) {
                [void]$c["btnCancel"].RaiseEvent(
                    (New-Object System.Windows.RoutedEventArgs(
                        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                $e.Handled = $true
            }
        }
    }
}.GetNewClosure())

# ── Carregar ultima pasta usada ao iniciar ────────────────────────────────────
& $updateHistoryBtn
$lastF = Load-LastFolder
if ($lastF -and (Test-Path -LiteralPath $lastF -PathType Container)) {
    $app.folder              = $lastF
    $c["lblPath"].Text       = $lastF
    $c["lblPath"].ScrollToEnd()
    $c["lblPath"].Foreground = Get-Brush "#e8e8e8"
    $c["btnScan"].IsEnabled  = $true
    $c["lblStatus"].Text     = "Ultima pasta carregada. Clique em Escanear ou arraste uma nova."
}


# Escala largura pela resolucao da tela: min(max(560, sw*0.32), 720)
# SystemParameters usa WPF DIPs — ja ciente de DPI, funciona em qualquer escala
$sw      = [System.Windows.SystemParameters]::PrimaryScreenWidth
$winW    = [Math]::Round([Math]::Min([Math]::Max(560.0, $sw * 0.32), 720.0))
$window.Width    = $winW
$window.MinWidth = $winW - 20

# Fixa MinHeight ao renderizar — impede redimensionar abaixo do conteudo inicial
$window.Add_ContentRendered({
    $window.MinHeight = $window.ActualHeight
})

# ── Mostrar janela ─────────────────────────────────────────────────────────────
$window.ShowDialog() | Out-Null
