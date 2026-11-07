# PCGuard GUI - modern dark dashboard: live health, process manager, disk analysis,
# historical trends, and configurable settings.
# Run: powershell -ExecutionPolicy Bypass -File PCGuard-GUI.ps1
# Or double-click PCGuard.bat / the Desktop shortcut.

# --- Request administrator privileges (standard UAC consent prompt) ---
# Needed to reliably end system/protected processes, manage scheduled tasks, and
# run Docker/WSL cleanup. If the user declines the UAC prompt, PCGuard keeps
# running without admin rights instead of closing.
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
$script:IsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop | Out-Null
        exit
    } catch {
        # User declined the UAC prompt - continue running without admin rights.
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $RootDir 'PCGuardCore.psm1') -Force
$LogDir = Join-Path $RootDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cortexa - System Health Monitor" Height="840" Width="1040" MinWidth="700" MinHeight="500"
        WindowStartupLocation="CenterScreen" Background="#0f1115"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
    <Window.Resources>

        <!-- Palette -->
        <SolidColorBrush x:Key="BgBrush" Color="#0f1115"/>
        <SolidColorBrush x:Key="CardBrush" Color="#1a1d23"/>
        <SolidColorBrush x:Key="CardAltBrush" Color="#20232b"/>
        <SolidColorBrush x:Key="CardBorderBrush" Color="#2a2e37"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="#f3f5f7"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#9aa0ac"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#5b8def"/>
        <SolidColorBrush x:Key="AccentHoverBrush" Color="#71a0f5"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#22c55e"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#f59e0b"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#ef4444"/>
        <SolidColorBrush x:Key="HoverOverlayBrush" Color="#16FFFFFF"/>
        <SolidColorBrush x:Key="SelectedOverlayBrush" Color="#335b8def"/>

        <!-- Text styles -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
        </Style>
        <Style x:Key="PageTitle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="24"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
        </Style>
        <Style x:Key="CardHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="StatLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
        </Style>
        <Style x:Key="StatValue" TargetType="TextBlock">
            <Setter Property="FontSize" Value="22"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Margin" Value="0,4,0,8"/>
        </Style>
        <Style x:Key="MutedText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>

        <!-- Card container -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource CardBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>
        <Style x:Key="StatTile" TargetType="Border" BasedOn="{StaticResource Card}">
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Padding" Value="14"/>
        </Style>

        <!-- Buttons -->
        <Style x:Key="BaseButton" TargetType="Button">
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Margin" Value="0,0,8,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Background" Value="{StaticResource CardAltBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.65"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button" BasedOn="{StaticResource BaseButton}"/>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Foreground" Value="White"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
            <Setter Property="Foreground" Value="White"/>
        </Style>
        <Style x:Key="WarningButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="{StaticResource WarningBrush}"/>
            <Setter Property="Foreground" Value="#1a1a1a"/>
        </Style>

        <!-- ProgressBar -->
        <Style TargetType="ProgressBar">
            <Setter Property="Height" Value="8"/>
            <Setter Property="Background" Value="#2a2e37"/>
            <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid>
                            <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="5"/>
                            <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="5" HorizontalAlignment="Left"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox (with placeholder/watermark support via Tag + focus highlight) -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#242832"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="#3a3f4b"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7">
                            <Grid>
                                <TextBlock x:Name="Placeholder" Text="{TemplateBinding Tag}" Foreground="#6b7280" Margin="{TemplateBinding Padding}" IsHitTestVisible="False" Visibility="Collapsed"/>
                                <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Text" Value="">
                                <Setter TargetName="Placeholder" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="12.5"/>
        </Style>

        <!-- TabControl / TabItem -->
        <Style TargetType="TabItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Grid>
                            <Border x:Name="Bd" Background="Transparent" CornerRadius="8,8,0,0" Padding="13,10,13,12" Margin="0,0,1,0">
                                <ContentPresenter x:Name="Cp" ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <Border x:Name="Underline" Height="3" Background="{StaticResource AccentBrush}" VerticalAlignment="Bottom" CornerRadius="2" Opacity="0" Margin="18,0,18,0"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource CardBrush}"/>
                                <Setter TargetName="Underline" Property="Opacity" Value="1"/>
                                <Setter TargetName="Cp" Property="TextBlock.Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                                <Setter TargetName="Cp" Property="TextBlock.FontWeight" Value="Bold"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter TargetName="Cp" Property="TextBlock.Foreground" Value="{StaticResource TextSecondaryBrush}"/>
                                <Setter TargetName="Cp" Property="TextBlock.FontWeight" Value="SemiBold"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabControl">
                        <DockPanel>
                            <ScrollViewer DockPanel.Dock="Top" VerticalScrollBarVisibility="Disabled" HorizontalScrollBarVisibility="Auto" Padding="0,0,0,4">
                                <TabPanel IsItemsHost="True" Background="Transparent"/>
                            </ScrollViewer>
                            <Border Background="{StaticResource CardBrush}" CornerRadius="0,10,10,10" Padding="16" Margin="0,2,0,0">
                                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                    <ContentPresenter ContentSource="SelectedContent"/>
                                </ScrollViewer>
                            </Border>
                        </DockPanel>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ListView rows -->
        <Style x:Key="ModernListViewItem" TargetType="ListViewItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListViewItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}" Margin="0,1">
                            <GridViewRowPresenter Margin="0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource HoverOverlayBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource SelectedOverlayBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="GridViewColumnHeader">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="10,0,10,8"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GridViewColumnHeader">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,0,0,1" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ListView">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="ItemContainerStyle" Value="{StaticResource ModernListViewItem}"/>
        </Style>

        <!-- Alert list -->
        <Style x:Key="AlertItem" TargetType="ListBoxItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border Background="#241a1a" BorderBrush="#4a2a2a" BorderThickness="1" CornerRadius="7" Margin="0,3" Padding="10,7">
                            <ContentPresenter/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="ItemContainerStyle" Value="{StaticResource AlertItem}"/>
        </Style>
        <DataTemplate x:Key="AlertTemplate">
            <TextBlock Text="{Binding}" TextWrapping="Wrap" Foreground="#f3b4b4" FontSize="12"/>
        </DataTemplate>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
            <TextBlock Text="Cortexa" Style="{StaticResource PageTitle}"/>
            <TextBlock Text="  System Health Monitor" Style="{StaticResource MutedText}" VerticalAlignment="Bottom" Margin="8,0,0,3"/>
            <Border x:Name="AdminBadge" CornerRadius="10" Padding="10,3" Margin="12,0,0,0" VerticalAlignment="Bottom">
                <TextBlock x:Name="AdminBadgeText" FontSize="11" FontWeight="SemiBold"/>
            </Border>
        </StackPanel>

        <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12">
            <StackPanel>
                <WrapPanel>
                    <TextBlock Text="Ask Cortexa to do something:" VerticalAlignment="Center" Margin="0,0,10,8"/>
                    <TextBox x:Name="CommandBarInput" Width="460" Tag="e.g. 'free up my ram' or 'clean temp files'" Margin="0,0,8,8"/>
                    <Button x:Name="BtnCommandBarRun" Content="Run" Style="{StaticResource PrimaryButton}"/>
                </WrapPanel>
                <TextBlock x:Name="CommandBarStatus" Text="This maps your request to a fixed set of known Cortexa actions and always asks you to confirm before doing anything - it never runs arbitrary commands." Style="{StaticResource MutedText}" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <TabControl x:Name="MainTabControl" Grid.Row="2">
        <!-- ================= DASHBOARD ================= -->
        <TabItem Header="Dashboard">
            <StackPanel>
                <Grid Margin="0,0,0,4">
                    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
                    <Border Grid.Column="0" Style="{StaticResource StatTile}">
                        <StackPanel>
                            <TextBlock Text="RAM" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="RamText" Text="--" Style="{StaticResource StatValue}"/>
                            <ProgressBar x:Name="RamBar" Minimum="0" Maximum="100"/>
                            <Canvas x:Name="RamSparkline" Height="26" Margin="0,8,0,0" ClipToBounds="True"/>
                        </StackPanel>
                    </Border>
                    <Border Grid.Column="1" Style="{StaticResource StatTile}">
                        <StackPanel>
                            <TextBlock Text="CPU" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="CpuText" Text="--" Style="{StaticResource StatValue}"/>
                            <ProgressBar x:Name="CpuBar" Minimum="0" Maximum="100"/>
                            <Canvas x:Name="CpuSparkline" Height="26" Margin="0,8,0,0" ClipToBounds="True"/>
                        </StackPanel>
                    </Border>
                    <Border Grid.Column="2" Style="{StaticResource StatTile}">
                        <StackPanel>
                            <TextBlock Text="DISK C:" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="DiskCText" Text="--" Style="{StaticResource StatValue}"/>
                            <ProgressBar x:Name="DiskCBar" Minimum="0" Maximum="100"/>
                        </StackPanel>
                    </Border>
                    <Border Grid.Column="3" Style="{StaticResource StatTile}" Margin="0,0,0,0">
                        <StackPanel>
                            <TextBlock Text="DISK D:" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="DiskDText" Text="--" Style="{StaticResource StatValue}"/>
                            <ProgressBar x:Name="DiskDBar" Minimum="0" Maximum="100"/>
                        </StackPanel>
                    </Border>
                </Grid>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="SYSTEM INFO" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <StackPanel Margin="0,0,30,0">
                                <TextBlock Text="UPTIME" Style="{StaticResource StatLabel}"/>
                                <TextBlock x:Name="UptimeText" Text="--" FontSize="15" FontWeight="SemiBold" Margin="0,3,0,0"/>
                            </StackPanel>
                            <StackPanel Margin="0,0,30,0">
                                <TextBlock Text="BATTERY" Style="{StaticResource StatLabel}"/>
                                <TextBlock x:Name="BatteryText" Text="--" FontSize="15" FontWeight="SemiBold" Margin="0,3,0,0"/>
                            </StackPanel>
                            <StackPanel>
                                <TextBlock Text="GPU" Style="{StaticResource StatLabel}"/>
                                <TextBlock x:Name="GpuText" Text="--" FontSize="15" FontWeight="SemiBold" Margin="0,3,0,0"/>
                            </StackPanel>
                        </WrapPanel>
                        <Button x:Name="BtnBatteryReport" Content="Battery Health Report" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                        <TextBlock x:Name="BatteryReportStatus" Text="" Style="{StaticResource MutedText}" Margin="2,6,0,0"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="QUICK ACTIONS" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <Button x:Name="BtnScan" Content="Scan Now" Style="{StaticResource PrimaryButton}"/>
                            <Button x:Name="BtnSpeedBoost" Content="Speed Boost Now" Style="{StaticResource PrimaryButton}" Background="#8b5cf6"/>
                            <Button x:Name="BtnFreeRam" Content="Free Up RAM"/>
                            <Button x:Name="BtnStopUnwanted" Content="Stop Unwanted Software" Style="{StaticResource WarningButton}"/>
                            <Button x:Name="BtnClean" Content="Clean Temp Junk"/>
                            <Button x:Name="BtnWslShutdown" Content="Shutdown WSL"/>
                            <Button x:Name="BtnWatchdog" Content="Install Watchdog"/>
                            <Button x:Name="BtnExport" Content="Export Health Report"/>
                            <Button x:Name="BtnLogs" Content="Open Logs Folder"/>
                            <Button x:Name="BtnRestorePoint" Content="Create Restore Point"/>
                            <CheckBox x:Name="ChkAuto" Content="Auto-refresh (10s)" VerticalAlignment="Center" Margin="10,10,0,0"/>
                            <CheckBox x:Name="ChkFocusMode" Content="Focus Mode (suppress notifications)" VerticalAlignment="Center" Margin="10,10,0,0"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="TOP PROCESSES BY MEMORY" Style="{StaticResource CardHeader}"/>
                        <ListView x:Name="ProcList" Height="220">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Process" Width="420" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Memory (MB)" Width="150" DisplayMemberBinding="{Binding MemMB}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="RECENT ALERTS" Style="{StaticResource CardHeader}"/>
                        <ListBox x:Name="AlertList" Height="110" ItemTemplate="{StaticResource AlertTemplate}"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="RECENT SYSTEM ERRORS (LAST 24H)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnEventsRefresh" Content="Refresh"/>
                        </WrapPanel>
                        <ListView x:Name="EventList" Height="180">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Time" Width="140" DisplayMemberBinding="{Binding Time}"/>
                                    <GridViewColumn Header="Level" Width="80" DisplayMemberBinding="{Binding Level}"/>
                                    <GridViewColumn Header="Source" Width="170" DisplayMemberBinding="{Binding Source}"/>
                                    <GridViewColumn Header="Message" Width="400" DisplayMemberBinding="{Binding Message}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>

                <TextBlock x:Name="StatusText" Text="Ready." Style="{StaticResource MutedText}" Margin="2,6,0,0"/>
            </StackPanel>
        </TabItem>

        <!-- ================= PROCESSES ================= -->
        <TabItem Header="Processes">
            <StackPanel>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="ADVANCED TASK MANAGER" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <TextBox x:Name="ProcFilter" Width="220" Tag="Search by process name..." Margin="0,0,8,8"/>
                            <Button x:Name="BtnProcRefresh" Content="Refresh"/>
                            <Button x:Name="BtnEndTask" Content="End Selected Task(s)" Style="{StaticResource DangerButton}"/>
                            <Button x:Name="BtnEndTaskTree" Content="End Task Tree" Style="{StaticResource DangerButton}"/>
                            <Button x:Name="BtnOpenFileLocation" Content="Open File Location"/>
                            <Button x:Name="BtnAskAiProcess" Content="Ask AI About Selected" Background="#8b5cf6"/>
                            <CheckBox x:Name="ChkProcAuto" Content="Auto-refresh (5s)" VerticalAlignment="Center" Margin="10,10,0,0"/>
                        </WrapPanel>
                        <Border x:Name="ProcessAiPanel" Background="{StaticResource CardAltBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,8" Visibility="Collapsed">
                            <TextBlock x:Name="ProcessAiText" Text="" TextWrapping="Wrap"/>
                        </Border>
                        <WrapPanel Margin="0,0,0,8">
                            <TextBlock Text="Set priority:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <ComboBox x:Name="PriorityCombo" Width="150" Margin="0,0,8,0" SelectedIndex="2">
                                <ComboBoxItem Content="Idle"/>
                                <ComboBoxItem Content="BelowNormal"/>
                                <ComboBoxItem Content="Normal"/>
                                <ComboBoxItem Content="AboveNormal"/>
                                <ComboBoxItem Content="High"/>
                                <ComboBoxItem Content="RealTime"/>
                            </ComboBox>
                            <Button x:Name="BtnSetPriority" Content="Apply Priority"/>
                        </WrapPanel>
                        <ListView x:Name="FullProcList" Height="400" SelectionMode="Extended">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Process" Width="190" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="PID" Width="60" DisplayMemberBinding="{Binding Id}"/>
                                    <GridViewColumn Header="Status" Width="100" DisplayMemberBinding="{Binding Status}"/>
                                    <GridViewColumn Header="Memory (MB)" Width="100" DisplayMemberBinding="{Binding MemMB}"/>
                                    <GridViewColumn Header="CPU (s)" Width="80" DisplayMemberBinding="{Binding CpuSec}"/>
                                    <GridViewColumn Header="Threads" Width="70" DisplayMemberBinding="{Binding Threads}"/>
                                    <GridViewColumn Header="Priority" Width="100" DisplayMemberBinding="{Binding Priority}"/>
                                    <GridViewColumn Header="Started" Width="140" DisplayMemberBinding="{Binding StartTime}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <TextBlock x:Name="ProcStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= DISK ANALYSIS ================= -->
        <TabItem Header="Disk Analysis">
            <StackPanel>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="FOLDER SIZE SCANNER" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,4">
                            <TextBox x:Name="ScanPath" Width="420" Text="C:\Users\Charm" Tag="Folder path to scan..." Margin="0,0,8,8"/>
                            <Button x:Name="BtnScanFolders" Content="Scan Largest Folders" Style="{StaticResource PrimaryButton}"/>
                            <Button x:Name="BtnOpenFolder" Content="Open Selected"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="DISK I/O (LIVE)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <StackPanel Margin="0,0,30,8">
                                <TextBlock Text="READ" Style="{StaticResource StatLabel}"/>
                                <TextBlock x:Name="DiskReadText" Text="-- MB/s" FontSize="18" FontWeight="Bold" Foreground="#22c55e" Margin="0,3,0,0"/>
                            </StackPanel>
                            <StackPanel Margin="0,0,30,8">
                                <TextBlock Text="WRITE" Style="{StaticResource StatLabel}"/>
                                <TextBlock x:Name="DiskWriteText" Text="-- MB/s" FontSize="18" FontWeight="Bold" Foreground="#22d3ee" Margin="0,3,0,0"/>
                            </StackPanel>
                            <Button x:Name="BtnDiskIoRefresh" Content="Refresh" VerticalAlignment="Center" Margin="10,8,0,0"/>
                            <CheckBox x:Name="ChkDiskIoAuto" Content="Live auto-refresh (3s)" VerticalAlignment="Center" Margin="10,12,0,0"/>
                        </WrapPanel>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Height="70" Margin="0,4,0,0">
                            <Canvas x:Name="DiskIoSparkline" ClipToBounds="True"/>
                        </Border>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="WSL / DOCKER FOOTPRINT" Style="{StaticResource CardHeader}"/>
                        <TextBlock x:Name="WslInfoText" Text="--" TextWrapping="Wrap" Margin="0,0,0,8"/>
                        <WrapPanel>
                            <Button x:Name="BtnWslShutdown2" Content="Shutdown WSL"/>
                            <Button x:Name="BtnDockerPrune" Content="Prune Docker (unused images/volumes)" Style="{StaticResource WarningButton}"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="LARGEST FOLDERS" Style="{StaticResource CardHeader}"/>
                        <ListView x:Name="FolderList" Height="260">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Folder" Width="480" DisplayMemberBinding="{Binding Folder}"/>
                                    <GridViewColumn Header="Size (GB)" Width="140" DisplayMemberBinding="{Binding SizeGB}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <TextBlock x:Name="DiskStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="LARGEST INDIVIDUAL FILES" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnScanFiles" Content="Scan Largest Files"/>
                        </WrapPanel>
                        <ListView x:Name="FileList" Height="220">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="File" Width="500" DisplayMemberBinding="{Binding FilePath}"/>
                                    <GridViewColumn Header="Size (MB)" Width="120" DisplayMemberBinding="{Binding SizeMB}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= NETWORK ================= -->
        <TabItem Header="Network">
            <StackPanel>
                <Grid Margin="0,0,0,4">
                    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
                    <Border Grid.Column="0" Style="{StaticResource StatTile}">
                        <StackPanel>
                            <TextBlock Text="DOWNLOAD" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="NetDownText" Text="-- MB/s" Style="{StaticResource StatValue}" Foreground="#22c55e"/>
                        </StackPanel>
                    </Border>
                    <Border Grid.Column="1" Style="{StaticResource StatTile}" Margin="0,0,0,0">
                        <StackPanel>
                            <TextBlock Text="UPLOAD" Style="{StaticResource StatLabel}"/>
                            <TextBlock x:Name="NetUpText" Text="-- MB/s" Style="{StaticResource StatValue}" Foreground="#22d3ee"/>
                        </StackPanel>
                    </Border>
                </Grid>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="LIVE THROUGHPUT (last ~80s)" Style="{StaticResource CardHeader}"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border Width="10" Height="10" Background="#22c55e" CornerRadius="5" Margin="0,0,5,0"/>
                            <TextBlock Text="Download" Style="{StaticResource MutedText}" Margin="0,0,14,0"/>
                            <Border Width="10" Height="10" Background="#22d3ee" CornerRadius="5" Margin="0,0,5,0"/>
                            <TextBlock Text="Upload" Style="{StaticResource MutedText}"/>
                        </StackPanel>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Height="90">
                            <Canvas x:Name="NetSparkline" ClipToBounds="True"/>
                        </Border>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="ADAPTERS (TOTAL SINCE LAST RESET)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnNetRefresh" Content="Refresh Now" Style="{StaticResource PrimaryButton}"/>
                            <CheckBox x:Name="ChkNetAuto" Content="Live auto-refresh (3s)" VerticalAlignment="Center" Margin="10,10,0,0"/>
                        </WrapPanel>
                        <ListView x:Name="AdapterList" Height="110">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Adapter" Width="300" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Sent (MB)" Width="140" DisplayMemberBinding="{Binding SentMB}"/>
                                    <GridViewColumn Header="Received (MB)" Width="150" DisplayMemberBinding="{Binding ReceivedMB}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="ACTIVE CONNECTIONS" Style="{StaticResource CardHeader}"/>
                        <TextBox x:Name="ConnFilter" Width="280" Tag="Search by process name or IP..." HorizontalAlignment="Left" Margin="0,0,0,8"/>
                        <ListView x:Name="ConnList" Height="230">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Process" Width="140" DisplayMemberBinding="{Binding Process}"/>
                                    <GridViewColumn Header="PID" Width="55" DisplayMemberBinding="{Binding Pid}"/>
                                    <GridViewColumn Header="Local Address" Width="160" DisplayMemberBinding="{Binding LocalAddress}"/>
                                    <GridViewColumn Header="Local Port" Width="80" DisplayMemberBinding="{Binding LocalPort}"/>
                                    <GridViewColumn Header="Remote Address" Width="150" DisplayMemberBinding="{Binding RemoteAddress}"/>
                                    <GridViewColumn Header="Remote Port" Width="85" DisplayMemberBinding="{Binding RemotePort}"/>
                                    <GridViewColumn Header="State" Width="85" DisplayMemberBinding="{Binding State}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="TRAFFIC HISTORY (WATCHDOG SCANS)" Style="{StaticResource CardHeader}"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                            <Border Width="10" Height="10" Background="#22c55e" CornerRadius="5" Margin="0,0,5,0"/>
                            <TextBlock Text="Received (MB per interval)" Style="{StaticResource MutedText}" Margin="0,0,14,0"/>
                            <Border Width="10" Height="10" Background="#22d3ee" CornerRadius="5" Margin="0,0,5,0"/>
                            <TextBlock Text="Sent (MB per interval)" Style="{StaticResource MutedText}"/>
                        </StackPanel>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Height="220">
                            <Canvas x:Name="NetHistoryCanvas" Background="Transparent" ClipToBounds="True"/>
                        </Border>
                        <TextBlock Text="Note: this is bandwidth/connection monitoring, not raw packet capture. Full packet-level inspection would require a capture driver (e.g. Npcap) and admin rights." Style="{StaticResource MutedText}" Margin="2,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= TASKS ================= -->
        <TabItem Header="Tasks">
            <StackPanel>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="WINDOWS SCHEDULED TASKS" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <TextBox x:Name="TaskFilter" Width="280" Tag="Search by task name or path..." Margin="0,0,8,8"/>
                            <Button x:Name="BtnTaskRefresh" Content="Refresh" Style="{StaticResource PrimaryButton}"/>
                            <Button x:Name="BtnTaskEnable" Content="Enable Selected"/>
                            <Button x:Name="BtnTaskDisable" Content="Disable Selected" Style="{StaticResource WarningButton}"/>
                        </WrapPanel>
                        <ListView x:Name="TaskList" Height="420">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Name" Width="260" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Path" Width="220" DisplayMemberBinding="{Binding Path}"/>
                                    <GridViewColumn Header="State" Width="80" DisplayMemberBinding="{Binding State}"/>
                                    <GridViewColumn Header="Last Run" Width="140" DisplayMemberBinding="{Binding LastRunTime}"/>
                                    <GridViewColumn Header="Next Run" Width="140" DisplayMemberBinding="{Binding NextRunTime}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <TextBlock x:Name="TaskStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= STARTUP ================= -->
        <TabItem Header="Startup">
            <StackPanel>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="STARTUP ITEMS (REGISTRY RUN KEYS + STARTUP FOLDER)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <TextBox x:Name="StartupFilter" Width="260" Tag="Search startup items..." Margin="0,0,8,8"/>
                            <Button x:Name="BtnStartupRefresh" Content="Refresh" Style="{StaticResource PrimaryButton}"/>
                            <Button x:Name="BtnStartupEnable" Content="Enable Selected"/>
                            <Button x:Name="BtnStartupDisable" Content="Disable Selected" Style="{StaticResource WarningButton}"/>
                            <Button x:Name="BtnAiReviewStartup" Content="AI Review Startup Items" Background="#8b5cf6"/>
                        </WrapPanel>
                        <Border x:Name="StartupAiPanel" Background="{StaticResource CardAltBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,8" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="AI REVIEW (qwen2.5:3b or whichever model you've selected - always double-check before disabling anything)" Style="{StaticResource StatLabel}" Margin="0,0,0,6"/>
                                <TextBlock x:Name="StartupAiText" Text="" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                        <ListView x:Name="StartupList" Height="360">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Name" Width="220" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Command" Width="360" DisplayMemberBinding="{Binding Command}"/>
                                    <GridViewColumn Header="Source" Width="110" DisplayMemberBinding="{Binding Source}"/>
                                    <GridViewColumn Header="Enabled" Width="80" DisplayMemberBinding="{Binding Enabled}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <TextBlock x:Name="StartupStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= SECURITY ================= -->
        <TabItem Header="Security">
            <StackPanel>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="PROTECTION STATUS" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnSecurityRefresh" Content="Refresh" Style="{StaticResource PrimaryButton}"/>
                        </WrapPanel>
                        <TextBlock x:Name="DefenderStatusText" Text="--" Margin="0,2"/>
                        <TextBlock x:Name="FirewallStatusText" Text="--" Margin="0,2"/>
                        <TextBlock x:Name="BitLockerStatusText" Text="--" Margin="0,2" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="DISK HEALTH" Style="{StaticResource CardHeader}"/>
                        <ListView x:Name="DiskHealthList" Height="110">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Disk" Width="260" DisplayMemberBinding="{Binding FriendlyName}"/>
                                    <GridViewColumn Header="Type" Width="80" DisplayMemberBinding="{Binding MediaType}"/>
                                    <GridViewColumn Header="Health" Width="100" DisplayMemberBinding="{Binding HealthStatus}"/>
                                    <GridViewColumn Header="Status" Width="100" DisplayMemberBinding="{Binding OperationalStatus}"/>
                                    <GridViewColumn Header="Temp (C)" Width="90" DisplayMemberBinding="{Binding TemperatureC}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="DEVICES WITH ERRORS" Style="{StaticResource CardHeader}"/>
                        <ListView x:Name="PnpErrorList" Height="150">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Device" Width="320" DisplayMemberBinding="{Binding FriendlyName}"/>
                                    <GridViewColumn Header="Instance Id" Width="320" DisplayMemberBinding="{Binding InstanceId}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= HISTORY ================= -->
        <TabItem Header="History">
            <StackPanel>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="TREND (WATCHDOG SCANS)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,10">
                            <Button x:Name="BtnHistoryRefresh" Content="Refresh Chart" Style="{StaticResource PrimaryButton}"/>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="10,10,0,0">
                                <Border Width="10" Height="10" Background="#22c55e" CornerRadius="5" Margin="0,0,5,0"/>
                                <TextBlock Text="RAM free %" Style="{StaticResource MutedText}" Margin="0,0,14,0"/>
                                <Border Width="10" Height="10" Background="#f59e0b" CornerRadius="5" Margin="0,0,5,0"/>
                                <TextBlock Text="Disk C free %" Style="{StaticResource MutedText}" Margin="0,0,14,0"/>
                                <Border Width="10" Height="10" Background="#22d3ee" CornerRadius="5" Margin="0,0,5,0"/>
                                <TextBlock Text="CPU %" Style="{StaticResource MutedText}"/>
                            </StackPanel>
                        </WrapPanel>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Height="360">
                            <Canvas x:Name="HistoryCanvas" Background="Transparent" ClipToBounds="True"/>
                        </Border>
                        <TextBlock x:Name="HistoryStatusText" Text="Chart reflects the background watchdog's logged scans (every 15 min once installed)." Style="{StaticResource MutedText}" Margin="2,10,0,0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= AI AGENT ================= -->
        <TabItem Header="AI Agent">
            <StackPanel>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="OLLAMA (LOCAL LLM)" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <TextBlock x:Name="OllamaStatusText" Text="Checking..." VerticalAlignment="Center" Margin="0,0,16,8"/>
                            <Button x:Name="BtnOllamaRefresh" Content="Refresh Status"/>
                            <Button x:Name="BtnOllamaStart" Content="Start Ollama"/>
                            <TextBlock Text="Model:" VerticalAlignment="Center" Margin="12,0,6,8"/>
                            <ComboBox x:Name="AiModelCombo" Width="160"/>
                        </WrapPanel>
                        <TextBlock Text="Everything here runs 100% locally through your installed Ollama model - nothing is sent anywhere external. The AI only gives advice; it never executes actions on its own, you always click the button yourself." Style="{StaticResource MutedText}" TextWrapping="Wrap" Margin="0,8,0,0"/>

                        <TextBlock Text="MODEL MANAGER" Style="{StaticResource CardHeader}" Margin="0,16,0,8"/>
                        <WrapPanel>
                            <TextBox x:Name="PullModelName" Width="200" Tag="e.g. llama3.2:3b" Margin="0,0,8,8"/>
                            <Button x:Name="BtnPullModel" Content="Pull Model"/>
                            <Button x:Name="BtnDeleteModel" Content="Delete Selected Model" Style="{StaticResource DangerButton}"/>
                        </WrapPanel>
                        <TextBlock x:Name="ModelManagerStatus" Text="Browse models at ollama.com/library. Pulling a new model can take several minutes depending on its size and your connection." Style="{StaticResource MutedText}" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="SYSTEM ANALYSIS" Style="{StaticResource CardHeader}"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnAiAnalyze" Content="Analyze My System Now" Style="{StaticResource PrimaryButton}"/>
                        </WrapPanel>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Padding="14" MinHeight="90">
                            <TextBlock x:Name="AiAnalysisText" Text="Click &quot;Analyze My System Now&quot; to get an AI-generated diagnosis and recommendations based on your live system data." TextWrapping="Wrap"/>
                        </Border>
                        <WrapPanel x:Name="AiActionChips" Margin="0,8,0,0"/>
                        <Button x:Name="BtnRunAllSteps" Content="Run All Suggested Steps In Order" Background="#8b5cf6" HorizontalAlignment="Left" Margin="0,4,0,0" Visibility="Collapsed"/>
                        <TextBlock x:Name="AiAnalysisStatus" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="ASK CORTEXA AI" Style="{StaticResource CardHeader}"/>
                        <Border Background="{StaticResource CardAltBrush}" CornerRadius="8" Height="300" Margin="0,0,0,8">
                            <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Padding="10">
                                <ItemsControl x:Name="ChatItems">
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="8" Margin="0,4" Padding="10" Background="{Binding Background}">
                                                <StackPanel>
                                                    <TextBlock Text="{Binding Speaker}" FontWeight="Bold" FontSize="11" Foreground="{Binding SpeakerColor}"/>
                                                    <TextBlock Text="{Binding Text}" TextWrapping="Wrap" Margin="0,4,0,0"/>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </ScrollViewer>
                        </Border>
                        <WrapPanel>
                            <TextBox x:Name="ChatInput" Width="540" Tag="Ask about your system, e.g. 'why is my PC slow right now?'"/>
                            <Button x:Name="BtnChatSend" Content="Send" Style="{StaticResource PrimaryButton}"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="ACTION HISTORY (AUDIT LOG)" Style="{StaticResource CardHeader}"/>
                        <TextBlock Text="Every action the AI has suggested through chips or the command bar, and what you decided. Nothing here was executed without your explicit confirmation." Style="{StaticResource MutedText}" TextWrapping="Wrap" Margin="0,0,0,8"/>
                        <WrapPanel Margin="0,0,0,8">
                            <Button x:Name="BtnAiHistoryRefresh" Content="Refresh"/>
                        </WrapPanel>
                        <ListView x:Name="AiHistoryList" Height="180">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Time" Width="140" DisplayMemberBinding="{Binding Time}"/>
                                    <GridViewColumn Header="Source" Width="110" DisplayMemberBinding="{Binding Source}"/>
                                    <GridViewColumn Header="Action" Width="150" DisplayMemberBinding="{Binding Label}"/>
                                    <GridViewColumn Header="Decision" Width="90" DisplayMemberBinding="{Binding Decision}"/>
                                    <GridViewColumn Header="Detail" Width="200" DisplayMemberBinding="{Binding Detail}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>

        <!-- ================= SETTINGS ================= -->
        <TabItem Header="Settings">
            <StackPanel>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="ALERT THRESHOLDS" Style="{StaticResource CardHeader}"/>
                        <Grid Margin="0,2">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="320"/><ColumnDefinition Width="80"/></Grid.ColumnDefinitions>
                            <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Warn when RAM free % falls below" VerticalAlignment="Center" Margin="0,8"/>
                            <TextBox Grid.Row="0" Grid.Column="1" x:Name="CfgRamWarn"/>
                            <TextBlock Grid.Row="1" Grid.Column="0" Text="Warn when Disk free % falls below" VerticalAlignment="Center" Margin="0,8"/>
                            <TextBox Grid.Row="1" Grid.Column="1" x:Name="CfgDiskWarn"/>
                            <TextBlock Grid.Row="2" Grid.Column="0" Text="Auto-clean C: when free % falls below" VerticalAlignment="Center" Margin="0,8"/>
                            <TextBox Grid.Row="2" Grid.Column="1" x:Name="CfgDiskCritical"/>
                        </Grid>
                        <CheckBox x:Name="CfgAutoClean" Content="Enable automatic Temp/npm-cache cleanup" Margin="0,10,0,4"/>

                        <TextBlock Text="Unwanted software (process names, comma-separated)" Margin="0,16,0,4"/>
                        <TextBlock Text="Used by &quot;Stop Unwanted Software&quot; and &quot;Speed Boost Now&quot; on the Dashboard. Example: Spotify, Skype, Teams, Opera" Style="{StaticResource MutedText}" Margin="0,0,0,6" TextWrapping="Wrap"/>
                        <TextBox x:Name="CfgUnwantedProcesses" Width="500" HorizontalAlignment="Left" Tag="e.g. Spotify, Skype, Teams"/>

                        <TextBlock Text="Webhook alerts (optional - Slack or Discord incoming webhook URL)" Margin="0,16,0,4"/>
                        <TextBlock Text="The background watchdog will post alerts here in addition to the Windows notification. Leave blank to disable." Style="{StaticResource MutedText}" Margin="0,0,0,6" TextWrapping="Wrap"/>
                        <WrapPanel>
                            <ComboBox x:Name="CfgWebhookType" Width="120" Margin="0,0,8,0" SelectedIndex="0">
                                <ComboBoxItem Content="Slack"/>
                                <ComboBoxItem Content="Discord"/>
                            </ComboBox>
                            <TextBox x:Name="CfgWebhookUrl" Width="440" Tag="https://hooks.slack.com/services/..."/>
                        </WrapPanel>

                        <Button x:Name="BtnSaveConfig" Content="Save Settings" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left" Margin="0,16,0,0"/>
                        <TextBlock x:Name="ConfigStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,10,0,0"/>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="BACKUP / RESTORE SETTINGS" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <Button x:Name="BtnExportSettings" Content="Export Settings"/>
                            <Button x:Name="BtnImportSettings" Content="Import Settings"/>
                        </WrapPanel>
                        <TextBlock x:Name="BackupStatusText" Text="" Style="{StaticResource MutedText}" Margin="2,8,0,0"/>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="AI AGENT" Style="{StaticResource CardHeader}"/>
                        <CheckBox x:Name="CfgAiEnabled" Content="Let the background watchdog run an AI analysis every 15 minutes (logged, not shown as a popup)" Margin="0,4"/>
                        <TextBlock Text="Requires Ollama to be running. Uses whichever model is selected on the AI Agent tab." Style="{StaticResource MutedText}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,0,0,4">
                    <StackPanel>
                        <TextBlock Text="OTHER" Style="{StaticResource CardHeader}"/>
                        <WrapPanel>
                            <Button x:Name="BtnOpenStartup" Content="Open Windows Startup Apps Settings"/>
                            <Button x:Name="BtnOpenLogs2" Content="Open Logs Folder"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>
            </StackPanel>
        </TabItem>
        </TabControl>

        <!-- ================= FIRST-RUN WELCOME OVERLAY ================= -->
        <Border x:Name="WelcomeOverlay" Grid.Row="0" Grid.RowSpan="3" Background="#CC0f1115" Visibility="Collapsed">
            <Border Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="1" CornerRadius="14" Padding="28" MaxWidth="620" HorizontalAlignment="Center" VerticalAlignment="Center">
                <StackPanel>
                    <TextBlock Text="Welcome to Cortexa" FontSize="22" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="A quick tour before you dive in." Style="{StaticResource MutedText}" Margin="0,0,0,16"/>
                    <StackPanel Margin="0,0,0,4">
                        <TextBlock TextWrapping="Wrap" Margin="0,4"><Run Text="Dashboard" FontWeight="Bold"/><Run Text=" - live RAM/CPU/disk, quick actions like Speed Boost and Free Up RAM, recent alerts."/></TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,4"><Run Text="Processes / Startup / Tasks" FontWeight="Bold"/><Run Text=" - advanced task manager, startup programs, and scheduled tasks, all with AI explanations available."/></TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,4"><Run Text="Disk Analysis / Network / Security" FontWeight="Bold"/><Run Text=" - find what's eating space or bandwidth, check Defender/Firewall/disk health."/></TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,4"><Run Text="AI Agent" FontWeight="Bold"/><Run Text=" - chat about your system or run a full analysis, powered by a local Ollama model. It only ever suggests - you always click to confirm."/></TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,4"><Run Text="Settings" FontWeight="Bold"/><Run Text=" - alert thresholds, unwanted-software list, webhook alerts, and more."/></TextBlock>
                    </StackPanel>
                    <TextBlock Text="A background watchdog can also run every 15 minutes even when this window is closed (Dashboard &quot;Install Watchdog&quot; button)." Style="{StaticResource MutedText}" TextWrapping="Wrap" Margin="0,12,0,16"/>
                    <Button x:Name="BtnWelcomeDismiss" Content="Got it - let's go" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$iconPath = Join-Path $RootDir 'cortexa.ico'
if (Test-Path $iconPath) {
    try {
        $iconBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $iconBitmap.BeginInit()
        $iconBitmap.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $iconBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $iconBitmap.EndInit()
        $window.Icon = $iconBitmap
    } catch {}
}

foreach ($n in @('RamText','RamBar','CpuText','CpuBar','DiskCText','DiskCBar','DiskDText','DiskDBar',
                 'ProcList','AlertList','StatusText','BtnScan','BtnClean','BtnWatchdog','BtnLogs','ChkAuto',
                 'BtnExport','BtnWslShutdown',
                 'ProcFilter','BtnProcRefresh','BtnEndTask','FullProcList','ProcStatusText',
                 'ScanPath','BtnScanFolders','BtnOpenFolder','WslInfoText','BtnWslShutdown2','BtnDockerPrune','FolderList','DiskStatusText',
                 'BtnHistoryRefresh','HistoryCanvas','HistoryStatusText',
                 'NetDownText','NetUpText','BtnNetRefresh','ChkNetAuto','AdapterList','ConnFilter','ConnList','NetHistoryCanvas',
                 'CfgRamWarn','CfgDiskWarn','CfgDiskCritical','CfgAutoClean','BtnSaveConfig','ConfigStatusText','BtnOpenStartup','BtnOpenLogs2',
                 'AdminBadge','AdminBadgeText','UptimeText','BatteryText','GpuText','BtnEventsRefresh','EventList',
                 'DiskReadText','DiskWriteText','BtnDiskIoRefresh','ChkDiskIoAuto','DiskIoSparkline',
                 'RamSparkline','CpuSparkline','NetSparkline',
                 'TaskFilter','BtnTaskRefresh','BtnTaskEnable','BtnTaskDisable','TaskList','TaskStatusText',
                 'BtnSpeedBoost','BtnFreeRam','BtnStopUnwanted','CfgUnwantedProcesses',
                 'BtnEndTaskTree','BtnOpenFileLocation','PriorityCombo','BtnSetPriority','ChkProcAuto',
                 'BtnRestorePoint','ChkFocusMode','BtnBatteryReport','BatteryReportStatus',
                 'StartupFilter','BtnStartupRefresh','BtnStartupEnable','BtnStartupDisable','StartupList','StartupStatusText',
                 'BtnSecurityRefresh','DefenderStatusText','FirewallStatusText','BitLockerStatusText','DiskHealthList','PnpErrorList',
                 'BtnScanFiles','FileList',
                 'CfgWebhookType','CfgWebhookUrl','BtnExportSettings','BtnImportSettings','BackupStatusText',
                 'OllamaStatusText','BtnOllamaRefresh','BtnOllamaStart','AiModelCombo',
                 'BtnAiAnalyze','AiAnalysisText','AiAnalysisStatus',
                 'ChatScroll','ChatItems','ChatInput','BtnChatSend','CfgAiEnabled',
                 'BtnAskAiProcess','ProcessAiPanel','ProcessAiText',
                 'BtnAiReviewStartup','StartupAiPanel','StartupAiText','AiActionChips',
                 'WelcomeOverlay','BtnWelcomeDismiss','CommandBarInput','BtnCommandBarRun','CommandBarStatus','MainTabControl',
                 'PullModelName','BtnPullModel','BtnDeleteModel','ModelManagerStatus',
                 'BtnRunAllSteps','BtnAiHistoryRefresh','AiHistoryList')) {
    Set-Variable -Name $n -Value $window.FindName($n)
}

if ($script:IsAdmin) {
    $AdminBadge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40,34,197,94))
    $AdminBadgeText.Text = "Administrator"
    $AdminBadgeText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,197,94))
    $window.Title = "Cortexa - System Health Monitor (Administrator)"
} else {
    $AdminBadge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40,245,158,11))
    $AdminBadgeText.Text = "Standard user - some actions may be restricted"
    $AdminBadgeText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(245,158,11))
}

function Draw-Sparkline {
    param($Canvas, [System.Collections.Generic.List[double][]]$Series, [string[]]$Colors, [double]$FixedMax = 0)
    $Canvas.Children.Clear()
    $w = [math]::Max($Canvas.ActualWidth, 100)
    $h = [math]::Max($Canvas.ActualHeight, 26)
    $allMax = 0.001
    if ($FixedMax -gt 0) { $allMax = $FixedMax }
    else {
        foreach ($s in $Series) { foreach ($v in $s) { if ($v -gt $allMax) { $allMax = $v } } }
    }
    for ($i = 0; $i -lt $Series.Count; $i++) {
        $vals = $Series[$i]
        if ($vals.Count -lt 2) { continue }
        $stepX = $w / [math]::Max(1, ($vals.Count - 1))
        $poly = New-Object System.Windows.Shapes.Polyline
        $poly.Stroke = $Colors[$i]
        $poly.StrokeThickness = 1.8
        $pts = New-Object System.Windows.Media.PointCollection
        for ($j = 0; $j -lt $vals.Count; $j++) {
            $y = $h - (([double]$vals[$j] / $allMax) * $h)
            $pts.Add((New-Object System.Windows.Point ($j * $stepX), $y))
        }
        $poly.Points = $pts
        $Canvas.Children.Add($poly) | Out-Null
    }
}

function Add-RollingPoint {
    param([System.Collections.Generic.List[double]]$List, [double]$Value, [int]$MaxLen = 40)
    $List.Add($Value)
    while ($List.Count -gt $MaxLen) { $List.RemoveAt(0) }
}

$script:LiveRam = New-Object 'System.Collections.Generic.List[double]'
$script:LiveCpu = New-Object 'System.Collections.Generic.List[double]'
$script:LiveDown = New-Object 'System.Collections.Generic.List[double]'
$script:LiveUp = New-Object 'System.Collections.Generic.List[double]'
$script:LiveDiskRead = New-Object 'System.Collections.Generic.List[double]'
$script:LiveDiskWrite = New-Object 'System.Collections.Generic.List[double]'

function Set-BarColor {
    param($Bar, [double]$FreePercent)
    if ($FreePercent -lt 10) { $Bar.Foreground = [System.Windows.Media.Brushes]::OrangeRed }
    elseif ($FreePercent -lt 25) { $Bar.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(245,158,11)) }
    else { $Bar.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,197,94)) }
}

# ---------- Dashboard ----------
function Refresh-Dashboard {
    $health = Get-SystemHealth -TopProcessCount 10

    $RamText.Text = "$($health.RamFreePercent)%"
    $RamBar.Value = $health.RamFreePercent
    Set-BarColor -Bar $RamBar -FreePercent $health.RamFreePercent

    $CpuText.Text = "$($health.CpuPercent)%"
    $CpuBar.Value = $health.CpuPercent
    $CpuBar.Foreground = if ($health.CpuPercent -ge 90) { [System.Windows.Media.Brushes]::OrangeRed } elseif ($health.CpuPercent -ge 70) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(245,158,11)) } else { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,197,94)) }

    $cDrive = $health.Disks | Where-Object { $_.Drive -eq 'C:' }
    if ($cDrive) {
        $DiskCText.Text = "$($cDrive.FreePercent)%"
        $DiskCBar.Value = $cDrive.FreePercent
        Set-BarColor -Bar $DiskCBar -FreePercent $cDrive.FreePercent
    }
    $dDrive = $health.Disks | Where-Object { $_.Drive -eq 'D:' }
    if ($dDrive) {
        $DiskDText.Text = "$($dDrive.FreePercent)%"
        $DiskDBar.Value = $dDrive.FreePercent
        Set-BarColor -Bar $DiskDBar -FreePercent $dDrive.FreePercent
    } else {
        $DiskDText.Text = "N/A"; $DiskDBar.Value = 0
    }

    $ProcList.ItemsSource = $null
    $ProcList.ItemsSource = @($health.TopProcesses)

    $alerts = @(Get-RecentAlerts -LogDir $LogDir -Count 15)
    $AlertList.ItemsSource = $null
    $AlertList.ItemsSource = if ($alerts.Count -eq 0) { @("No alerts recorded yet.") } else { $alerts }

    $installed = Test-WatchdogInstalled
    $BtnWatchdog.Content = if ($installed) { "Uninstall Watchdog" } else { "Install Watchdog" }
    $StatusText.Text = "Last scan: $($health.Timestamp.ToString('HH:mm:ss'))  |  RAM $($health.RamFreeGB) GB free of $($health.RamTotalGB) GB  |  Watchdog: $(if ($installed) {'Running every 15 min'} else {'Not installed'})"

    $sysInfo = Get-SystemInfo
    $UptimeText.Text = $sysInfo.UptimeText
    $BatteryText.Text = $sysInfo.BatteryText
    $GpuText.Text = if ($null -ne $sysInfo.GpuPercent) { "$($sysInfo.GpuPercent)%" } else { "N/A" }
}

function Refresh-Events {
    $events = @(Get-RecentSystemEvents -Hours 24 -Top 20)
    $EventList.ItemsSource = $null
    $EventList.ItemsSource = $events
}
$BtnEventsRefresh.Add_Click({ Refresh-Events })

$BtnScan.Add_Click({ Refresh-Dashboard })

$BtnClean.Add_Click({
    $StatusText.Text = "Cleaning Temp and npm-cache..."
    $freed = Invoke-SafeCleanup
    [System.Windows.MessageBox]::Show("Freed approximately $freed MB from Temp/npm-cache.", "Cleanup Complete") | Out-Null
    Refresh-Dashboard
})

$BtnWatchdog.Add_Click({
    if (Test-WatchdogInstalled) {
        Uninstall-Watchdog
        [System.Windows.MessageBox]::Show("Watchdog uninstalled. Background monitoring stopped.", "PCGuard") | Out-Null
    } else {
        try {
            Install-Watchdog -ScriptDir $RootDir
            [System.Windows.MessageBox]::Show("Watchdog installed. PCGuard will now check your system every 15 minutes in the background.", "PCGuard") | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Failed to install watchdog: $_", "PCGuard - Error") | Out-Null
        }
    }
    Refresh-Dashboard
})

$BtnLogs.Add_Click({ Start-Process explorer.exe $LogDir })
$BtnOpenLogs2.Add_Click({ Start-Process explorer.exe $LogDir })

$BtnExport.Add_Click({
    $path = Export-HealthReport -RootDir $RootDir -LogDir $LogDir
    $result = [System.Windows.MessageBox]::Show("Report saved to:`n$path`n`nOpen it now?", "Report Exported", [System.Windows.MessageBoxButton]::YesNo)
    if ($result -eq 'Yes') { Start-Process $path }
})

$BtnWslShutdown.Add_Click({
    Invoke-WslShutdown
    [System.Windows.MessageBox]::Show("WSL shutdown command sent. RAM should free up within a few seconds.", "PCGuard") | Out-Null
    Refresh-Dashboard
})

$BtnFreeRam.Add_Click({
    $StatusText.Text = "Freeing up RAM (trimming idle process working sets)..."
    $result = Invoke-FreeUpRam
    [System.Windows.MessageBox]::Show("Trimmed $($result.ProcessesTrimmed) background processes.`nFree RAM changed by approximately $($result.FreedMB) MB.`n`nNote: this reclaims memory apps aren't actively using - it's not a substitute for closing apps you don't need.", "Free Up RAM") | Out-Null
    Refresh-Dashboard
})

$BtnStopUnwanted.Add_Click({
    $names = Get-UnwantedProcessNames
    if ($names.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No unwanted software list configured yet.`n`nGo to Settings and add process names (e.g. Spotify, Skype, Teams) under 'Unwanted software'.", "PCGuard") | Out-Null
        return
    }
    $running = $names | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
    if ($running.Count -eq 0) {
        [System.Windows.MessageBox]::Show("None of your configured unwanted software is currently running.", "PCGuard") | Out-Null
        return
    }
    $confirm = [System.Windows.MessageBox]::Show("Stop these running applications?`n`n$($running -join "`n")", "Confirm Stop Unwanted Software", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        $stopped = Invoke-StopUnwantedProcesses -Names $running
        [System.Windows.MessageBox]::Show("Stopped:`n$($stopped -join "`n")", "PCGuard") | Out-Null
        Refresh-Dashboard
        Refresh-ProcessList
    }
})

$BtnSpeedBoost.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Speed Boost will:`n  - Clean Temp/npm-cache junk`n  - Shut down WSL (if running)`n  - Trim idle process memory (free up RAM)`n  - Stop your configured unwanted software (if any is running)`n`nContinue?",
        "Confirm Speed Boost", [System.Windows.MessageBoxButton]::YesNo)
    if ($confirm -ne 'Yes') { return }

    $StatusText.Text = "Speed Boost running..."
    $summary = @()
    $before = Get-SystemHealth -TopProcessCount 1

    $freedTemp = Invoke-SafeCleanup
    $summary += "Temp/cache cleanup: freed ~$freedTemp MB"

    Invoke-WslShutdown
    $summary += "WSL: shutdown sent"

    $ramResult = Invoke-FreeUpRam
    $summary += "RAM trim: $($ramResult.ProcessesTrimmed) processes trimmed, ~$($ramResult.FreedMB) MB freed"

    $names = Get-UnwantedProcessNames
    if ($names.Count -gt 0) {
        $running = $names | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
        if ($running.Count -gt 0) {
            $stopped = Invoke-StopUnwantedProcesses -Names $running
            $summary += "Unwanted software stopped: $($stopped -join ', ')"
        } else {
            $summary += "Unwanted software: none currently running"
        }
    }

    $after = Get-SystemHealth -TopProcessCount 1
    $summary += "`nRAM free: $($before.RamFreePercent)% -> $($after.RamFreePercent)%  ($('{0:+0.0;-0.0;0}' -f ($after.RamFreeGB - $before.RamFreeGB)) GB)"

    [System.Windows.MessageBox]::Show(($summary -join "`n`n"), "Speed Boost Complete") | Out-Null
    Refresh-Dashboard
    Refresh-ProcessList
})

$BtnRestorePoint.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("Create a Windows System Restore point now? This gives you an undo point before risky cleanups.", "Confirm Restore Point", [System.Windows.MessageBoxButton]::YesNo)
    if ($confirm -ne 'Yes') { return }
    $StatusText.Text = "Creating restore point..."
    $result = Invoke-CreateRestorePoint -Description "Cortexa manual checkpoint $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    if ($result.Success) {
        [System.Windows.MessageBox]::Show($result.Message, "Restore Point Created") | Out-Null
    } else {
        [System.Windows.MessageBox]::Show("Could not create a restore point: $($result.Message)`n`nThis usually means System Protection is turned off for this drive (System Properties > System Protection), which Windows disables by default on many PCs.", "PCGuard - Could Not Create Restore Point") | Out-Null
    }
    $StatusText.Text = "Ready."
})

$ChkFocusMode.Add_Checked({
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    $cfg.FocusMode = $true
    Save-PCGuardConfig -RootDir $RootDir -Config $cfg
})
$ChkFocusMode.Add_Unchecked({
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    $cfg.FocusMode = $false
    Save-PCGuardConfig -RootDir $RootDir -Config $cfg
})

$BtnBatteryReport.Add_Click({
    $BatteryReportStatus.Text = "Generating battery health report..."
    $report = Get-BatteryHealthReport -RootDir $RootDir
    if (-not $report.Available) {
        $BatteryReportStatus.Text = if ($report.Error) { "Could not generate report: $($report.Error)" } else { "No battery detected on this system." }
        return
    }
    $wearText = if ($null -ne $report.WearPercent) { " Estimated wear: $($report.WearPercent)%." } else { "" }
    $BatteryReportStatus.Text = "Report saved.$wearText"
    $result = [System.Windows.MessageBox]::Show("Battery health report generated.$wearText`n`nOpen the full report now?", "Battery Health Report", [System.Windows.MessageBoxButton]::YesNo)
    if ($result -eq 'Yes') { Start-Process $report.HtmlPath }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(10)
$timer.Add_Tick({ if ($ChkAuto.IsChecked) { Refresh-Dashboard } })
$timer.Start()

# Lightweight live sampler (always on, independent of the full 10s dashboard
# refresh) - feeds the RAM/CPU sparklines, Task-Manager style.
$liveTimer = New-Object System.Windows.Threading.DispatcherTimer
$liveTimer.Interval = [TimeSpan]::FromSeconds(2)
$liveTimer.Add_Tick({
    $os = Get-CimInstance Win32_OperatingSystem
    $ramFree = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Add-RollingPoint -List $script:LiveRam -Value $ramFree
    Add-RollingPoint -List $script:LiveCpu -Value ([double]$cpu)
    Draw-Sparkline -Canvas $RamSparkline -Series @(,$script:LiveRam) -Colors @('#22c55e') -FixedMax 100
    Draw-Sparkline -Canvas $CpuSparkline -Series @(,$script:LiveCpu) -Colors @('#22d3ee') -FixedMax 100
})
$liveTimer.Start()

# ---------- Processes tab ----------
$script:AllProcesses = @()

function Refresh-ProcessList {
    $script:AllProcesses = Get-ProcessesDetailed
    Apply-ProcessFilter
    $ProcStatusText.Text = "Showing $($FullProcList.Items.Count) of $($script:AllProcesses.Count) processes. Last refreshed $(Get-Date -Format 'HH:mm:ss')."
}

function Apply-ProcessFilter {
    $f = $ProcFilter.Text
    $FullProcList.ItemsSource = $null
    if ([string]::IsNullOrWhiteSpace($f)) {
        $FullProcList.ItemsSource = @($script:AllProcesses)
    } else {
        $FullProcList.ItemsSource = @($script:AllProcesses | Where-Object { $_.Name -like "*$f*" })
    }
}

$BtnProcRefresh.Add_Click({ Refresh-ProcessList })
$ProcFilter.Add_TextChanged({ Apply-ProcessFilter })

$procTimer = New-Object System.Windows.Threading.DispatcherTimer
$procTimer.Interval = [TimeSpan]::FromSeconds(5)
$procTimer.Add_Tick({ if ($ChkProcAuto.IsChecked) { Refresh-ProcessList } })
$procTimer.Start()

$BtnEndTask.Add_Click({
    $sel = @($FullProcList.SelectedItems)
    if ($sel.Count -eq 0) { [System.Windows.MessageBox]::Show("Select one or more processes first.", "PCGuard") | Out-Null; return }
    $names = ($sel | ForEach-Object { "$($_.Name) (PID $($_.Id))" }) -join "`n"
    $confirm = [System.Windows.MessageBox]::Show("End the following process(es)?`n`n$names`n`nUnsaved work in these apps will be lost.", "Confirm End Task", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        $failed = @()
        foreach ($p in $sel) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { $failed += $p.Name }
        }
        $ProcStatusText.Text = if ($failed.Count -eq 0) { "Ended $($sel.Count) process(es)." } else { "Ended $($sel.Count - $failed.Count); failed: $($failed -join ', ')" }
        Refresh-ProcessList
    }
})

$BtnEndTaskTree.Add_Click({
    $sel = @($FullProcList.SelectedItems)
    if ($sel.Count -eq 0) { [System.Windows.MessageBox]::Show("Select one or more processes first.", "PCGuard") | Out-Null; return }
    $names = ($sel | ForEach-Object { "$($_.Name) (PID $($_.Id))" }) -join "`n"
    $confirm = [System.Windows.MessageBox]::Show("End these process(es) AND all of their child processes?`n`n$names`n`nThis is more aggressive than End Task - use it for apps that spawn helper processes.", "Confirm End Task Tree", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        foreach ($p in $sel) { Stop-ProcessTree -ProcessId $p.Id }
        $ProcStatusText.Text = "Ended $($sel.Count) process tree(s)."
        Refresh-ProcessList
    }
})

$BtnOpenFileLocation.Add_Click({
    $sel = $FullProcList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a process first.", "PCGuard") | Out-Null; return }
    $path = Get-ProcessFilePath -ProcessId $sel.Id
    if ($path -and (Test-Path $path)) {
        Start-Process explorer.exe "/select,`"$path`""
    } else {
        [System.Windows.MessageBox]::Show("Could not locate the file for '$($sel.Name)' (it may be a protected system process).", "PCGuard") | Out-Null
    }
})

$BtnSetPriority.Add_Click({
    $sel = @($FullProcList.SelectedItems)
    if ($sel.Count -eq 0) { [System.Windows.MessageBox]::Show("Select one or more processes first.", "PCGuard") | Out-Null; return }
    $priority = ($PriorityCombo.SelectedItem).Content.ToString()
    $failed = @()
    foreach ($p in $sel) {
        try { Set-ProcessPriority -ProcessId $p.Id -Priority $priority } catch { $failed += $p.Name }
    }
    $ProcStatusText.Text = if ($failed.Count -eq 0) { "Set priority '$priority' on $($sel.Count) process(es)." } else { "Priority set on $($sel.Count - $failed.Count); failed: $($failed -join ', ')" }
    Refresh-ProcessList
})

$BtnAskAiProcess.Add_Click({
    $sel = $FullProcList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a process first.", "PCGuard") | Out-Null; return }
    if (-not $AiModelCombo.SelectedItem) { [System.Windows.MessageBox]::Show("No Ollama model available. Go to the AI Agent tab and click Refresh Status (start Ollama first if needed).", "PCGuard") | Out-Null; return }
    $ProcessAiPanel.Visibility = 'Visible'
    $ProcessAiText.Text = "Asking AI about '$($sel.Name)'..."
    $BtnAskAiProcess.IsEnabled = $false
    $path = Get-ProcessFilePath -ProcessId $sel.Id
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    $model = $AiModelCombo.SelectedItem.ToString()
    Start-AiJob -ScriptBlock {
        param($mp, $m, $name, $procPath, $mem)
        Import-Module $mp -Force
        Invoke-AiExplainProcess -Model $m -ProcessName $name -ProcessPath $procPath -MemMB $mem
    } -ArgumentList @($modelPath, $model, $sel.Name, $path, $sel.MemMB) -OnComplete {
        param($result)
        $BtnAskAiProcess.IsEnabled = $true
        $ProcessAiText.Text = if ($result.Success) { $result.Response } else { "Could not reach Ollama: $($result.Response)" }
    }
})

# ---------- Disk Analysis tab ----------
$script:FolderScanJob = $null
$script:FolderScanTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FolderScanTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:FolderScanTimer.Add_Tick({
    if ($script:FolderScanJob -and $script:FolderScanJob.State -in @('Completed','Failed','Stopped')) {
        $script:FolderScanTimer.Stop()
        $results = @(Receive-Job -Job $script:FolderScanJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:FolderScanJob -Force
        $script:FolderScanJob = $null
        $FolderList.ItemsSource = $null
        $FolderList.ItemsSource = $results
        $DiskStatusText.Text = "Scan complete: $(Get-Date -Format 'HH:mm:ss')"
        $BtnScanFolders.IsEnabled = $true
    }
})

$BtnScanFolders.Add_Click({
    $path = $ScanPath.Text
    if (-not (Test-Path $path)) {
        [System.Windows.MessageBox]::Show("Path not found: $path", "PCGuard") | Out-Null
        return
    }
    $DiskStatusText.Text = "Scanning $path (this can take a minute for large folders)..."
    $BtnScanFolders.IsEnabled = $false
    $FolderList.ItemsSource = $null
    $script:FolderScanJob = Start-Job -ScriptBlock {
        param($p)
        Get-ChildItem $p -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            [PSCustomObject]@{ Folder = $_.FullName; SizeGB = [math]::Round($size / 1GB, 2) }
        } | Sort-Object SizeGB -Descending | Select-Object -First 20
    } -ArgumentList $path
    $script:FolderScanTimer.Start()
})

$BtnOpenFolder.Add_Click({
    $sel = $FolderList.SelectedItem
    if ($sel) { Start-Process explorer.exe $sel.Folder } else { [System.Windows.MessageBox]::Show("Select a folder first.", "PCGuard") | Out-Null }
})

$script:FileScanJob = $null
$script:FileScanTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FileScanTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:FileScanTimer.Add_Tick({
    if ($script:FileScanJob -and $script:FileScanJob.State -in @('Completed', 'Failed', 'Stopped')) {
        $script:FileScanTimer.Stop()
        $results = @(Receive-Job -Job $script:FileScanJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:FileScanJob -Force
        $script:FileScanJob = $null
        $FileList.ItemsSource = $null
        $FileList.ItemsSource = $results
        $DiskStatusText.Text = "File scan complete: $(Get-Date -Format 'HH:mm:ss')"
        $BtnScanFiles.IsEnabled = $true
    }
})

$BtnScanFiles.Add_Click({
    $path = $ScanPath.Text
    if (-not (Test-Path $path)) {
        [System.Windows.MessageBox]::Show("Path not found: $path", "PCGuard") | Out-Null
        return
    }
    $DiskStatusText.Text = "Scanning $path for the largest files (this can take a while for large folders)..."
    $BtnScanFiles.IsEnabled = $false
    $FileList.ItemsSource = $null
    $script:FileScanJob = Start-Job -ScriptBlock {
        param($p)
        Get-ChildItem $p -File -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 30 |
            ForEach-Object { [PSCustomObject]@{ FilePath = $_.FullName; SizeMB = [math]::Round($_.Length / 1MB, 2) } }
    } -ArgumentList $path
    $script:FileScanTimer.Start()
})

function Refresh-DiskIo {
    $io = Get-DiskIoStats
    if ($io.Available) {
        $DiskReadText.Text = "{0} MB/s" -f $io.ReadMBs
        $DiskWriteText.Text = "{0} MB/s" -f $io.WriteMBs
        Add-RollingPoint -List $script:LiveDiskRead -Value $io.ReadMBs
        Add-RollingPoint -List $script:LiveDiskWrite -Value $io.WriteMBs
        Draw-Sparkline -Canvas $DiskIoSparkline -Series @($script:LiveDiskRead, $script:LiveDiskWrite) -Colors @('#22c55e', '#22d3ee')
    } else {
        $DiskReadText.Text = "N/A"
        $DiskWriteText.Text = "N/A"
    }
}
$BtnDiskIoRefresh.Add_Click({ Refresh-DiskIo })

$diskIoTimer = New-Object System.Windows.Threading.DispatcherTimer
$diskIoTimer.Interval = [TimeSpan]::FromSeconds(3)
$diskIoTimer.Add_Tick({ if ($ChkDiskIoAuto.IsChecked) { Refresh-DiskIo } })
$diskIoTimer.Start()

function Refresh-WslInfo {
    $info = Get-WslDockerInfo
    $distroText = if ($info.Distros.Count -gt 0) { $info.Distros -join ', ' } else { 'none detected' }
    $WslInfoText.Text = "WSL running memory: $($info.WslRunningMemMB) MB   |   Docker disk: $($info.DockerDiskGB) GB   |   WSL disk: $($info.WslDiskGB) GB   |   Distros: $distroText"
}

$BtnWslShutdown2.Add_Click({
    Invoke-WslShutdown
    [System.Windows.MessageBox]::Show("WSL shutdown sent.", "PCGuard") | Out-Null
    Refresh-WslInfo
})

$BtnDockerPrune.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "This runs 'docker system prune -a --volumes', which removes ALL unused Docker images, containers, networks, and volumes (anything not currently in use by a running container).`n`nThis can free tens of GB but you will need to re-pull/rebuild images later. Continue?",
        "Confirm Docker Prune", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        $DiskStatusText.Text = "Pruning Docker... this may take a moment."
        $out = docker system prune -a --volumes -f 2>&1 | Out-String
        [System.Windows.MessageBox]::Show($out, "Docker Prune Result") | Out-Null
        Refresh-WslInfo
        $DiskStatusText.Text = "Docker prune finished: $(Get-Date -Format 'HH:mm:ss')"
    }
})

# ---------- History tab ----------
function Draw-HistoryChart {
    $HistoryCanvas.Children.Clear()
    $points = Get-HealthHistory -LogDir $LogDir -MaxPoints 60

    $width = [math]::Max($HistoryCanvas.ActualWidth, 600)
    $height = [math]::Max($HistoryCanvas.ActualHeight, 300)

    # gridlines
    foreach ($pct in 0,25,50,75,100) {
        $y = $height - ($pct / 100 * $height)
        $line = New-Object System.Windows.Shapes.Line
        $line.X1 = 0; $line.X2 = $width; $line.Y1 = $y; $line.Y2 = $y
        $line.Stroke = '#2a2e37'; $line.StrokeThickness = 1
        $HistoryCanvas.Children.Add($line) | Out-Null
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "$pct%"; $lbl.Foreground = '#6b7280'; $lbl.FontSize = 10
        [System.Windows.Controls.Canvas]::SetLeft($lbl, 4)
        [System.Windows.Controls.Canvas]::SetTop($lbl, [math]::Max(0, $y - 14))
        $HistoryCanvas.Children.Add($lbl) | Out-Null
    }

    if (-not $points -or $points.Count -lt 2) {
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = "Not enough history yet. The watchdog needs to run a few times (every 15 min) to build a trend."
        $txt.Foreground = 'Gray'
        [System.Windows.Controls.Canvas]::SetLeft($txt, 20)
        [System.Windows.Controls.Canvas]::SetTop($txt, 20)
        $HistoryCanvas.Children.Add($txt) | Out-Null
        return
    }

    $stepX = $width / ($points.Count - 1)

    function New-Series {
        param($Values, $Color)
        $poly = New-Object System.Windows.Shapes.Polyline
        $poly.Stroke = $Color
        $poly.StrokeThickness = 2.5
        $ptCollection = New-Object System.Windows.Media.PointCollection
        for ($i = 0; $i -lt $Values.Count; $i++) {
            $v = [double]$Values[$i]
            $y = $height - ($v / 100 * $height)
            $ptCollection.Add((New-Object System.Windows.Point ($i * $stepX), $y))
        }
        $poly.Points = $ptCollection
        return $poly
    }

    $ramVals = $points | ForEach-Object { $_.RamFree }
    $cpuVals = $points | ForEach-Object { $_.Cpu }
    $diskVals = $points | ForEach-Object { if ($null -ne $_.DiskCFree) { $_.DiskCFree } else { 0 } }

    $HistoryCanvas.Children.Add((New-Series -Values $ramVals -Color '#22c55e')) | Out-Null
    $HistoryCanvas.Children.Add((New-Series -Values $diskVals -Color '#f59e0b')) | Out-Null
    $HistoryCanvas.Children.Add((New-Series -Values $cpuVals -Color '#22d3ee')) | Out-Null
}

$BtnHistoryRefresh.Add_Click({ Draw-HistoryChart })

# ---------- Network tab ----------
$script:PrevNetSample = $null
$script:AllConnections = @()

function Refresh-NetworkTab {
    $snap = Get-NetworkStats

    if ($script:PrevNetSample) {
        $dt = ($snap.Timestamp - $script:PrevNetSample.Timestamp).TotalSeconds
        if ($dt -gt 0.5) {
            $down = [math]::Max(0, (($snap.TotalReceivedBytes - $script:PrevNetSample.TotalReceivedBytes) / 1MB) / $dt)
            $up   = [math]::Max(0, (($snap.TotalSentBytes - $script:PrevNetSample.TotalSentBytes) / 1MB) / $dt)
            $NetDownText.Text = "{0:N2} MB/s" -f $down
            $NetUpText.Text   = "{0:N2} MB/s" -f $up
            Add-RollingPoint -List $script:LiveDown -Value $down
            Add-RollingPoint -List $script:LiveUp -Value $up
            Draw-Sparkline -Canvas $NetSparkline -Series @($script:LiveDown, $script:LiveUp) -Colors @('#22c55e', '#22d3ee')
        }
    } else {
        $NetDownText.Text = "sampling..."
        $NetUpText.Text   = "sampling..."
    }
    $script:PrevNetSample = @{ Timestamp = $snap.Timestamp; TotalReceivedBytes = $snap.TotalReceivedBytes; TotalSentBytes = $snap.TotalSentBytes }

    $AdapterList.ItemsSource = $null
    $AdapterList.ItemsSource = @($snap.Adapters)

    $script:AllConnections = Get-ActiveConnections -Top 300
    Apply-ConnFilter

    Draw-NetHistoryChart
}

function Apply-ConnFilter {
    $f = $ConnFilter.Text
    $ConnList.ItemsSource = $null
    if ([string]::IsNullOrWhiteSpace($f)) {
        $ConnList.ItemsSource = @($script:AllConnections)
    } else {
        $ConnList.ItemsSource = @($script:AllConnections | Where-Object {
            $_.Process -like "*$f*" -or $_.RemoteAddress -like "*$f*" -or $_.LocalAddress -like "*$f*"
        })
    }
}

$BtnNetRefresh.Add_Click({ Refresh-NetworkTab })
$ConnFilter.Add_TextChanged({ Apply-ConnFilter })

$netTimer = New-Object System.Windows.Threading.DispatcherTimer
$netTimer.Interval = [TimeSpan]::FromSeconds(3)
$netTimer.Add_Tick({ if ($ChkNetAuto.IsChecked) { Refresh-NetworkTab } })
$netTimer.Start()

function Draw-NetHistoryChart {
    $NetHistoryCanvas.Children.Clear()
    $points = @(Get-NetworkHistory -LogDir $LogDir -MaxPoints 40)

    $width = [math]::Max($NetHistoryCanvas.ActualWidth, 600)
    $height = [math]::Max($NetHistoryCanvas.ActualHeight, 200)

    if ($points.Count -lt 2) {
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = "Not enough history yet. The watchdog needs to run a few times (every 15 min) to build a trend."
        $txt.Foreground = 'Gray'
        [System.Windows.Controls.Canvas]::SetLeft($txt, 10)
        [System.Windows.Controls.Canvas]::SetTop($txt, 10)
        $NetHistoryCanvas.Children.Add($txt) | Out-Null
        return
    }

    $recvDeltas = @()
    $sentDeltas = @()
    for ($i = 1; $i -lt $points.Count; $i++) {
        $recvDeltas += [math]::Max(0, $points[$i].ReceivedMB - $points[$i - 1].ReceivedMB)
        $sentDeltas += [math]::Max(0, $points[$i].SentMB - $points[$i - 1].SentMB)
    }
    $maxVal = [math]::Max(1, (($recvDeltas + $sentDeltas) | Measure-Object -Maximum).Maximum)
    $stepX = $width / [math]::Max(1, ($recvDeltas.Count - 1))

    function New-NetSeries {
        param($Values, $Color)
        $poly = New-Object System.Windows.Shapes.Polyline
        $poly.Stroke = $Color
        $poly.StrokeThickness = 2.5
        $pts = New-Object System.Windows.Media.PointCollection
        for ($i = 0; $i -lt $Values.Count; $i++) {
            $y = $height - (($Values[$i] / $maxVal) * $height)
            $pts.Add((New-Object System.Windows.Point ($i * $stepX), $y))
        }
        $poly.Points = $pts
        return $poly
    }

    $NetHistoryCanvas.Children.Add((New-NetSeries -Values $recvDeltas -Color '#22c55e')) | Out-Null
    $NetHistoryCanvas.Children.Add((New-NetSeries -Values $sentDeltas -Color '#22d3ee')) | Out-Null
}

# ---------- Tasks tab ----------
$script:AllTasks = @()

function Refresh-TaskList {
    $TaskStatusText.Text = "Loading scheduled tasks..."
    $script:AllTasks = Get-ScheduledTasksList
    Apply-TaskFilter
    $TaskStatusText.Text = "Showing $($TaskList.Items.Count) of $($script:AllTasks.Count) scheduled tasks. Last refreshed $(Get-Date -Format 'HH:mm:ss')."
}

function Apply-TaskFilter {
    $f = $TaskFilter.Text
    $TaskList.ItemsSource = $null
    if ([string]::IsNullOrWhiteSpace($f)) {
        $TaskList.ItemsSource = @($script:AllTasks)
    } else {
        $TaskList.ItemsSource = @($script:AllTasks | Where-Object { $_.Name -like "*$f*" -or $_.Path -like "*$f*" })
    }
}

$BtnTaskRefresh.Add_Click({ Refresh-TaskList })
$TaskFilter.Add_TextChanged({ Apply-TaskFilter })

$BtnTaskEnable.Add_Click({
    $sel = $TaskList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a task first.", "PCGuard") | Out-Null; return }
    try {
        Set-ScheduledTaskState -TaskName $sel.Name -TaskPath $sel.Path -Enable $true
        $TaskStatusText.Text = "Enabled '$($sel.Name)'."
    } catch {
        [System.Windows.MessageBox]::Show("Could not enable task: $_", "PCGuard - Error") | Out-Null
    }
    Refresh-TaskList
})

$BtnTaskDisable.Add_Click({
    $sel = $TaskList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a task first.", "PCGuard") | Out-Null; return }
    $confirm = [System.Windows.MessageBox]::Show("Disable scheduled task '$($sel.Name)'?`n`nIt will no longer run automatically until re-enabled.", "Confirm Disable", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        try {
            Set-ScheduledTaskState -TaskName $sel.Name -TaskPath $sel.Path -Enable $false
            $TaskStatusText.Text = "Disabled '$($sel.Name)'."
        } catch {
            [System.Windows.MessageBox]::Show("Could not disable task: $_", "PCGuard - Error") | Out-Null
        }
        Refresh-TaskList
    }
})

# ---------- Startup tab ----------
$script:AllStartupItems = @()

function Refresh-StartupList {
    $StartupStatusText.Text = "Loading startup items..."
    $script:AllStartupItems = Get-StartupItemsDetailed
    Apply-StartupFilter
    $StartupStatusText.Text = "Showing $($StartupList.Items.Count) of $($script:AllStartupItems.Count) startup items. Last refreshed $(Get-Date -Format 'HH:mm:ss')."
}

function Apply-StartupFilter {
    $f = $StartupFilter.Text
    $StartupList.ItemsSource = $null
    if ([string]::IsNullOrWhiteSpace($f)) {
        $StartupList.ItemsSource = @($script:AllStartupItems)
    } else {
        $StartupList.ItemsSource = @($script:AllStartupItems | Where-Object { $_.Name -like "*$f*" -or $_.Command -like "*$f*" })
    }
}

$BtnStartupRefresh.Add_Click({ Refresh-StartupList })
$StartupFilter.Add_TextChanged({ Apply-StartupFilter })

$BtnStartupDisable.Add_Click({
    $sel = $StartupList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a startup item first.", "PCGuard") | Out-Null; return }
    if (-not $sel.Enabled) { [System.Windows.MessageBox]::Show("That item is already disabled.", "PCGuard") | Out-Null; return }
    $confirm = [System.Windows.MessageBox]::Show("Disable startup item '$($sel.Name)'?`n`nIt will no longer launch at sign-in. You can re-enable it anytime from this tab.", "Confirm Disable", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq 'Yes') {
        try {
            Disable-StartupItem -Item $sel -RootDir $RootDir
            $StartupStatusText.Text = "Disabled '$($sel.Name)'."
        } catch {
            [System.Windows.MessageBox]::Show("Could not disable: $_", "PCGuard - Error") | Out-Null
        }
        Refresh-StartupList
    }
})

$BtnStartupEnable.Add_Click({
    $sel = $StartupList.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a startup item first.", "PCGuard") | Out-Null; return }
    if ($sel.Enabled) { [System.Windows.MessageBox]::Show("That item is already enabled.", "PCGuard") | Out-Null; return }
    try {
        Enable-StartupItem -Item $sel -RootDir $RootDir
        $StartupStatusText.Text = "Enabled '$($sel.Name)'."
    } catch {
        [System.Windows.MessageBox]::Show("Could not enable: $_", "PCGuard - Error") | Out-Null
    }
    Refresh-StartupList
})

$BtnAiReviewStartup.Add_Click({
    if ($script:AllStartupItems.Count -eq 0) { [System.Windows.MessageBox]::Show("No startup items loaded yet. Click Refresh first.", "PCGuard") | Out-Null; return }
    if (-not $AiModelCombo.SelectedItem) { [System.Windows.MessageBox]::Show("No Ollama model available. Go to the AI Agent tab and click Refresh Status (start Ollama first if needed).", "PCGuard") | Out-Null; return }
    $StartupAiPanel.Visibility = 'Visible'
    $StartupAiText.Text = "Reviewing your startup items..."
    $BtnAiReviewStartup.IsEnabled = $false
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    $model = $AiModelCombo.SelectedItem.ToString()
    $itemsForAi = @($script:AllStartupItems | Where-Object { $_.Enabled } | Select-Object Name, Command)
    Start-AiJob -ScriptBlock {
        param($mp, $m, $items)
        Import-Module $mp -Force
        Invoke-AiReviewStartupItems -Model $m -Items $items
    } -ArgumentList @($modelPath, $model, $itemsForAi) -OnComplete {
        param($result)
        $BtnAiReviewStartup.IsEnabled = $true
        $StartupAiText.Text = if ($result.Success) { $result.Response } else { "Could not reach Ollama: $($result.Response)" }
    }
})

# ---------- Security tab ----------
function Refresh-SecurityTab {
    $status = Get-SecurityStatus

    $DefenderStatusText.Text = if ($null -ne $status.DefenderEnabled) {
        "Windows Defender: $(if ($status.DefenderEnabled) {'Enabled'} else {'Disabled'})  |  Real-time protection: $(if ($status.RealTimeProtection) {'On'} else {'Off'})  |  Signature age: $($status.SignaturesAge) day(s)"
    } else { "Windows Defender: status unavailable (another antivirus may be managing protection)" }

    $FirewallStatusText.Text = if ($status.Firewall.Count -gt 0) {
        "Firewall: " + (($status.Firewall | ForEach-Object { "$($_.Name)=$(if ($_.Enabled) {'On'} else {'Off'})" }) -join '  ')
    } else { "Firewall: status unavailable" }

    $BitLockerStatusText.Text = if ($status.BitLocker.Count -gt 0) {
        "BitLocker: " + (($status.BitLocker | ForEach-Object { "$($_.MountPoint)=$($_.ProtectionStatus)" }) -join '  ')
    } else { "BitLocker: not enabled on any volume (or unavailable on this Windows edition)" }

    $DiskHealthList.ItemsSource = $null
    $DiskHealthList.ItemsSource = @(Get-DiskHealth)

    $PnpErrorList.ItemsSource = $null
    $pnpErrors = @($status.PnpErrors)
    if ($pnpErrors.Count -eq 0) {
        $PnpErrorList.ItemsSource = @([PSCustomObject]@{ FriendlyName = "No devices reporting errors"; InstanceId = "" })
    } else {
        $PnpErrorList.ItemsSource = ,$pnpErrors
    }
}

$BtnSecurityRefresh.Add_Click({ Refresh-SecurityTab })

# ---------- AI Agent tab ----------
$script:AiMessages = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$script:LastSuggestedActions = @()
$ChatItems.ItemsSource = $script:AiMessages

function Add-ChatMessage {
    param([string]$Speaker, [string]$Text, [bool]$IsUser)
    $script:AiMessages.Add([PSCustomObject]@{
        Speaker      = $Speaker
        Text         = $Text
        Background   = if ($IsUser) { '#20232b' } else { '#16233a' }
        SpeakerColor = if ($IsUser) { '#9aa0ac' } else { '#5b8def' }
    })
    $ChatScroll.ScrollToBottom()
}

function Refresh-OllamaStatus {
    $status = Test-OllamaAvailable
    if ($status.Available) {
        $OllamaStatusText.Text = "Ollama: Connected ($($status.Models.Count) model(s) installed)"
        $AiModelCombo.ItemsSource = $status.Models
        if (-not $AiModelCombo.SelectedItem -and $status.Models.Count -gt 0) {
            $savedModel = (Get-PCGuardConfig -RootDir $RootDir).AiModel
            if ($savedModel -and ($status.Models -contains $savedModel)) {
                $AiModelCombo.SelectedItem = $savedModel
            } else {
                $AiModelCombo.SelectedIndex = 0
            }
        }
    } else {
        $OllamaStatusText.Text = "Ollama: not running"
        $AiModelCombo.ItemsSource = $null
    }
    return $status.Available
}

$BtnOllamaRefresh.Add_Click({ Refresh-OllamaStatus | Out-Null })

$AiModelCombo.Add_SelectionChanged({
    if ($AiModelCombo.SelectedItem) {
        $cfg = Get-PCGuardConfig -RootDir $RootDir
        $cfg.AiModel = $AiModelCombo.SelectedItem.ToString()
        Save-PCGuardConfig -RootDir $RootDir -Config $cfg
    }
})

$BtnOllamaStart.Add_Click({
    $OllamaStatusText.Text = "Starting Ollama..."
    $started = Start-OllamaServer
    if ($started) { Refresh-OllamaStatus | Out-Null } else { $OllamaStatusText.Text = "Could not start Ollama. Is it installed?" }
})

$BtnPullModel.Add_Click({
    $name = $PullModelName.Text.Trim()
    if (-not $name) { [System.Windows.MessageBox]::Show("Enter a model name first, e.g. llama3.2:3b (see ollama.com/library).", "PCGuard") | Out-Null; return }
    $BtnPullModel.IsEnabled = $false
    $ModelManagerStatus.Text = "Pulling '$name' - this can take several minutes, please wait..."
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    Start-AiJob -ScriptBlock {
        param($mp, $m)
        Import-Module $mp -Force
        Invoke-OllamaPullModel -ModelName $m
    } -ArgumentList @($modelPath, $name) -OnComplete {
        param($result)
        $BtnPullModel.IsEnabled = $true
        $ModelManagerStatus.Text = $result.Message
        if ($result.Success) { $PullModelName.Text = ""; Refresh-OllamaStatus | Out-Null }
    }
})

$BtnDeleteModel.Add_Click({
    if (-not $AiModelCombo.SelectedItem) { [System.Windows.MessageBox]::Show("No model selected.", "PCGuard") | Out-Null; return }
    $name = $AiModelCombo.SelectedItem.ToString()
    $confirm = [System.Windows.MessageBox]::Show("Delete the local model '$name'? You'll need to pull it again to use it later.", "Confirm Delete Model", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne 'Yes') { return }
    $ModelManagerStatus.Text = "Deleting '$name'..."
    $result = Invoke-OllamaDeleteModel -ModelName $name
    $ModelManagerStatus.Text = $result.Message
    Refresh-OllamaStatus | Out-Null
})

$script:AiJob = $null
$script:AiJobTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:AiJobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:AiJobTimer.Add_Tick({
    if ($script:AiJob -and $script:AiJob.State -in @('Completed', 'Failed', 'Stopped')) {
        $script:AiJobTimer.Stop()
        $result = Receive-Job -Job $script:AiJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:AiJob -Force
        $script:AiJob = $null
        & $script:AiJobCallback $result
    }
})

function Start-AiJob {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList, [scriptblock]$OnComplete)
    $script:AiJobCallback = $OnComplete
    $script:AiJob = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $script:AiJobTimer.Start()
}

$script:AiActionLabels = @{
    FreeRam      = 'Free Up RAM'
    CleanTemp    = 'Clean Temp Junk'
    StopUnwanted = 'Stop Unwanted Software'
    SpeedBoost   = 'Speed Boost Now'
    ShutdownWsl  = 'Shutdown WSL'
    RestorePoint = 'Create Restore Point'
}

function Refresh-AiHistory {
    $AiHistoryList.ItemsSource = $null
    $AiHistoryList.ItemsSource = @(Get-AiActionLog -RootDir $RootDir -Top 50)
}
$BtnAiHistoryRefresh.Add_Click({ Refresh-AiHistory })

function Get-ActionButton {
    # The single source of truth mapping a whitelisted AI action token to the
    # real, existing Dashboard button that performs it. Used by both the
    # action chips and the command bar, so there is exactly one place that
    # defines "what button does this token mean."
    param([string]$Action)
    switch ($Action) {
        'FreeRam'      { return $BtnFreeRam }
        'CleanTemp'    { return $BtnClean }
        'StopUnwanted' { return $BtnStopUnwanted }
        'SpeedBoost'   { return $BtnSpeedBoost }
        'ShutdownWsl'  { return $BtnWslShutdown }
        'RestorePoint' { return $BtnRestorePoint }
        default        { return $null }
    }
}

function Build-AiActionChips {
    param([string[]]$Actions)
    $AiActionChips.Children.Clear()
    $script:LastSuggestedActions = @($Actions | Where-Object { $script:AiActionLabels.ContainsKey($_) -and (Get-ActionButton -Action $_) })

    foreach ($action in $script:LastSuggestedActions) {
        $targetButton = Get-ActionButton -Action $action
        $chip = New-Object System.Windows.Controls.Button
        $chip.Content = $script:AiActionLabels[$action]
        $chip.Style = $window.FindResource('PrimaryButton')
        $chip.Tag = [PSCustomObject]@{ Button = $targetButton; Action = $action; Label = $script:AiActionLabels[$action] }
        $chip.Add_Click({
            param($s, $e)
            # Triggers the real Dashboard button's own existing handler, so the
            # AI never runs an action directly - it only points at the same
            # control the user could click themselves.
            Write-AiActionLog -RootDir $RootDir -Source 'Analysis' -Action ($s.Tag).Action -Label ($s.Tag).Label -Decision 'Accepted'
            (($s.Tag).Button).RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            Refresh-AiHistory
        })
        $AiActionChips.Children.Add($chip) | Out-Null
    }

    $BtnRunAllSteps.Visibility = if ($script:LastSuggestedActions.Count -gt 1) { 'Visible' } else { 'Collapsed' }
}

$BtnRunAllSteps.Add_Click({
    $actions = @($script:LastSuggestedActions)
    if ($actions.Count -eq 0) { return }
    $steps = for ($i = 0; $i -lt $actions.Count; $i++) { "$($i + 1). $($script:AiActionLabels[$actions[$i]])" }
    $confirm = [System.Windows.MessageBox]::Show("Run this plan, in order?`n`n$($steps -join "`n")`n`nNote: some of these steps show their own additional confirmation (e.g. Speed Boost, Restore Point) - that's intentional, not a bug.", "Confirm Multi-Step Plan", [System.Windows.MessageBoxButton]::YesNo)
    if ($confirm -ne 'Yes') { return }
    $BtnRunAllSteps.IsEnabled = $false
    foreach ($action in $actions) {
        $label = $script:AiActionLabels[$action]
        $targetButton = Get-ActionButton -Action $action
        Write-AiActionLog -RootDir $RootDir -Source 'Analysis-MultiStep' -Action $action -Label $label -Decision 'Accepted'
        $targetButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        Start-Sleep -Milliseconds 400
    }
    $BtnRunAllSteps.IsEnabled = $true
    $AiAnalysisStatus.Text = "Ran all $($actions.Count) suggested steps."
    Refresh-AiHistory
})

function Switch-ToTab {
    param([string]$TabName)
    foreach ($item in $MainTabControl.Items) {
        if ($item.Header -eq $TabName) { $MainTabControl.SelectedItem = $item; return $true }
    }
    return $false
}

$BtnCommandBarRun.Add_Click({
    $req = $CommandBarInput.Text.Trim()
    if (-not $req) { return }
    if (-not $AiModelCombo.SelectedItem) {
        $CommandBarStatus.Text = "No Ollama model available. Open the AI Agent tab and click Refresh Status (start Ollama first if needed)."
        return
    }
    $BtnCommandBarRun.IsEnabled = $false
    $CommandBarStatus.Text = "Thinking about: `"$req`"..."
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    $model = $AiModelCombo.SelectedItem.ToString()
    Start-AiJob -ScriptBlock {
        param($mp, $m, $userReq)
        Import-Module $mp -Force
        $result = Invoke-AiParseCommand -Model $m -UserRequest $userReq
        if ($result.Success) {
            Get-AiParsedCommand -ResponseText $result.Response
        } else {
            [PSCustomObject]@{ Action = 'Error'; Arg = $result.Response }
        }
    } -ArgumentList @($modelPath, $model, $req) -OnComplete {
        param($parsed)
        $BtnCommandBarRun.IsEnabled = $true

        if ($parsed.Action -eq 'Error') {
            $CommandBarStatus.Text = "Could not reach Ollama: $($parsed.Arg)"
            return
        }
        if ($parsed.Action -eq 'None') {
            $CommandBarStatus.Text = "Couldn't map that to a known action. Try things like `"free up my ram`", `"clean temp files`", `"close spotify`", or `"open the security tab`"."
            return
        }
        if ($parsed.Action -eq 'OpenTab') {
            $tabName = $script:CommandBarTabWhitelist | Where-Object { $_ -eq $parsed.Arg } | Select-Object -First 1
            if (-not $tabName -and $parsed.Arg) {
                $tabName = $script:CommandBarTabWhitelist | Where-Object { $_.ToLower() -eq $parsed.Arg.ToLower() } | Select-Object -First 1
            }
            if ($tabName -and (Switch-ToTab -TabName $tabName)) {
                Write-AiActionLog -RootDir $RootDir -Source 'CommandBar' -Action 'OpenTab' -Label "Open $tabName tab" -Decision 'Accepted' -Detail $tabName
                $CommandBarStatus.Text = "Opened the $tabName tab."
            } else {
                $CommandBarStatus.Text = "AI suggested opening a tab, but '$($parsed.Arg)' isn't a recognized tab name."
            }
            return
        }
        if ($parsed.Action -eq 'EndProcess') {
            if (-not $parsed.Arg) { $CommandBarStatus.Text = "AI didn't specify which process to end."; return }
            $cleanName = $parsed.Arg -replace '\.exe$', ''
            $procMatches = @(Get-Process -Name $cleanName -ErrorAction SilentlyContinue)
            if ($procMatches.Count -eq 0) { $procMatches = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*$cleanName*" }) }
            if ($procMatches.Count -eq 0) {
                $CommandBarStatus.Text = "No running process matching '$($parsed.Arg)' found."
                return
            }
            $names = ($procMatches | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join "`n"
            $confirm = [System.Windows.MessageBox]::Show("Cortexa understood: end the following process(es)?`n`n$names", "Confirm (from command bar)", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($confirm -eq 'Yes') {
                foreach ($p in $procMatches) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
                Write-AiActionLog -RootDir $RootDir -Source 'CommandBar' -Action 'EndProcess' -Label "End process: $($parsed.Arg)" -Decision 'Accepted' -Detail $names
                $CommandBarStatus.Text = "Ended: $($procMatches.Count) process(es)."
                Refresh-ProcessList
            } else {
                Write-AiActionLog -RootDir $RootDir -Source 'CommandBar' -Action 'EndProcess' -Label "End process: $($parsed.Arg)" -Decision 'Declined' -Detail $names
                $CommandBarStatus.Text = "Cancelled."
            }
            return
        }

        $targetButton = Get-ActionButton -Action $parsed.Action
        if (-not $targetButton) {
            $CommandBarStatus.Text = "AI suggested an unrecognized action - ignored."
            return
        }
        $label = $script:AiActionLabels[$parsed.Action]
        $confirm = [System.Windows.MessageBox]::Show("Cortexa understood: `"$label`". Run it now?", "Confirm (from command bar)", [System.Windows.MessageBoxButton]::YesNo)
        if ($confirm -eq 'Yes') {
            Write-AiActionLog -RootDir $RootDir -Source 'CommandBar' -Action $parsed.Action -Label $label -Decision 'Accepted' -Detail $req
            $targetButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            $CommandBarStatus.Text = "Ran: $label"
        } else {
            Write-AiActionLog -RootDir $RootDir -Source 'CommandBar' -Action $parsed.Action -Label $label -Decision 'Declined' -Detail $req
            $CommandBarStatus.Text = "Cancelled."
        }
        Refresh-AiHistory
    }
})

$CommandBarInput.Add_KeyDown({
    param($eventSource, $e)
    if ($e.Key -eq 'Return') { $BtnCommandBarRun.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
})

$BtnAiAnalyze.Add_Click({
    if (-not $AiModelCombo.SelectedItem) { [System.Windows.MessageBox]::Show("No Ollama model selected. Refresh status first.", "PCGuard") | Out-Null; return }
    $BtnAiAnalyze.IsEnabled = $false
    $AiAnalysisStatus.Text = "Analyzing (this can take 10-30 seconds on a local model)..."
    $AiActionChips.Children.Clear()
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    $model = $AiModelCombo.SelectedItem.ToString()
    Start-AiJob -ScriptBlock {
        param($mp, $m)
        Import-Module $mp -Force
        Invoke-AiSystemAnalysis -Model $m
    } -ArgumentList @($modelPath, $model) -OnComplete {
        param($result)
        $BtnAiAnalyze.IsEnabled = $true
        if ($result.Success) {
            $parsed = Get-AiSuggestedActions -ResponseText $result.Response
            $AiAnalysisText.Text = $parsed.DisplayText
            Build-AiActionChips -Actions $parsed.Actions
            $AiAnalysisStatus.Text = "Last analyzed: $(Get-Date -Format 'HH:mm:ss')" + $(if ($parsed.Actions.Count -gt 0) { " - click a suggestion below to act on it" } else { "" })
        } else {
            $AiAnalysisText.Text = "Could not reach Ollama. Make sure it's running (use the Start Ollama button above)."
            $AiAnalysisStatus.Text = "Error: $($result.Response)"
        }
    }
})

$BtnChatSend.Add_Click({
    $msg = $ChatInput.Text.Trim()
    if (-not $msg) { return }
    if (-not $AiModelCombo.SelectedItem) { [System.Windows.MessageBox]::Show("No Ollama model selected. Refresh status first.", "PCGuard") | Out-Null; return }
    Add-ChatMessage -Speaker "You" -Text $msg -IsUser $true
    $ChatInput.Text = ""
    $BtnChatSend.IsEnabled = $false
    Add-ChatMessage -Speaker "Cortexa AI" -Text "Thinking..." -IsUser $false
    $modelPath = Join-Path $RootDir 'PCGuardCore.psm1'
    $model = $AiModelCombo.SelectedItem.ToString()
    Start-AiJob -ScriptBlock {
        param($mp, $m, $userMsg)
        Import-Module $mp -Force
        Invoke-AiChat -Model $m -UserMessage $userMsg
    } -ArgumentList @($modelPath, $model, $msg) -OnComplete {
        param($result)
        $BtnChatSend.IsEnabled = $true
        $script:AiMessages.RemoveAt($script:AiMessages.Count - 1)
        if ($result.Success) {
            Add-ChatMessage -Speaker "Cortexa AI" -Text $result.Response -IsUser $false
        } else {
            Add-ChatMessage -Speaker "Cortexa AI" -Text "Could not reach Ollama: $($result.Response)" -IsUser $false
        }
    }
})

$ChatInput.Add_KeyDown({
    param($eventSource, $e)
    if ($e.Key -eq 'Return') { $BtnChatSend.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
})

# ---------- Settings tab ----------
function Load-ConfigIntoUI {
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    $CfgRamWarn.Text = $cfg.RamFreePercentWarn
    $CfgDiskWarn.Text = $cfg.DiskFreePercentWarn
    $CfgDiskCritical.Text = $cfg.DiskFreePercentCritical
    $CfgAutoClean.IsChecked = [bool]$cfg.AutoClean
    $CfgUnwantedProcesses.Text = ($cfg.UnwantedProcesses -join ', ')
    $CfgWebhookUrl.Text = $cfg.WebhookUrl
    foreach ($item in $CfgWebhookType.Items) { if ($item.Content -eq $cfg.WebhookType) { $CfgWebhookType.SelectedItem = $item } }
    $ChkFocusMode.IsChecked = [bool]$cfg.FocusMode
    $CfgAiEnabled.IsChecked = [bool]$cfg.AiEnabled
}

function Get-UnwantedProcessNames {
    $cfg = Get-PCGuardConfig -RootDir $RootDir
    @($cfg.UnwantedProcesses | Where-Object { $_ -and $_.Trim() })
}

$BtnSaveConfig.Add_Click({
    $unwantedList = @($CfgUnwantedProcesses.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $existing = Get-PCGuardConfig -RootDir $RootDir
    $cfg = [PSCustomObject]@{
        RamFreePercentWarn      = [int]$CfgRamWarn.Text
        DiskFreePercentWarn     = [int]$CfgDiskWarn.Text
        DiskFreePercentCritical = [int]$CfgDiskCritical.Text
        AutoClean                = [bool]$CfgAutoClean.IsChecked
        UnwantedProcesses        = $unwantedList
        FocusMode                = [bool]$existing.FocusMode
        WebhookUrl               = $CfgWebhookUrl.Text
        WebhookType              = ($CfgWebhookType.SelectedItem).Content.ToString()
        AiEnabled                = [bool]$CfgAiEnabled.IsChecked
        AiModel                  = $existing.AiModel
    }
    Save-PCGuardConfig -RootDir $RootDir -Config $cfg
    $ConfigStatusText.Text = "Saved at $(Get-Date -Format 'HH:mm:ss'). The watchdog will use these on its next 15-minute run."
})

$BtnExportSettings.Add_Click({
    $dest = Join-Path $RootDir "cortexa-settings-backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    Export-PCGuardSettings -RootDir $RootDir -DestPath $dest
    $BackupStatusText.Text = "Settings exported to: $dest"
    Start-Process explorer.exe "/select,`"$dest`""
})

$BtnImportSettings.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.InitialDirectory = $RootDir
    $dialog.Filter = "Cortexa settings (*.json)|*.json"
    if ($dialog.ShowDialog()) {
        try {
            Import-PCGuardSettings -RootDir $RootDir -SourcePath $dialog.FileName
            Load-ConfigIntoUI
            $BackupStatusText.Text = "Settings imported from: $($dialog.FileName)"
        } catch {
            [System.Windows.MessageBox]::Show("Could not import settings: $_", "PCGuard - Error") | Out-Null
        }
    }
})

$BtnOpenStartup.Add_Click({ Start-Process "ms-settings:startupapps" })

# ---------- Initial load ----------
Refresh-Dashboard
Refresh-Events
Refresh-ProcessList
Refresh-WslInfo
Refresh-DiskIo
Refresh-TaskList
Refresh-StartupList
Refresh-SecurityTab
Refresh-OllamaStatus | Out-Null
Refresh-AiHistory
Refresh-NetworkTab
Start-Sleep -Milliseconds 700
Refresh-NetworkTab   # second quick sample so Download/Upload show a real rate immediately instead of "sampling..."
Load-ConfigIntoUI

$firstRunMarker = Join-Path $RootDir '.first_run_done'
if (-not (Test-Path $firstRunMarker)) {
    $WelcomeOverlay.Visibility = 'Visible'
}
$BtnWelcomeDismiss.Add_Click({
    $WelcomeOverlay.Visibility = 'Collapsed'
    try { New-Item -ItemType File -Path $firstRunMarker -Force | Out-Null } catch {}
})

$window.Add_ContentRendered({ Draw-HistoryChart })

$window.ShowDialog() | Out-Null
