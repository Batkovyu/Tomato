#requires -version 3.0
<#
.SYNOPSIS
  Tomato timer via WPF and Mahapps
.DESCRIPTION
  Script realizes the Pomodoro Technique. It is a time management method that uses a timer to break down work into intervals,
  traditionally 25 minutes in length, separated by short breaks (5 min). 
.PARAMETER 
  Not available
.INPUTS
  Not available
.OUTPUTS
  WPF form
.NOTES
  Version:        1.1
  Author:         batkovyu@gmail.com
  Creation Date:  01.05.2017
  Purpose/Change: Aligned with PowerShell 'PracticeAndStyle' guidline
  
.EXAMPLE
  Not available
#>

#region [Requirements]

Write-Host "Launching...Please wait..."

#Required Function Libraries
$LoadedAssemblies = [AppDomain]::CurrentDomain.GetAssemblies()

if ($LoadedAssemblies -notmatch "PresentationFramework") {
	Add-Type -AssemblyName PresentationFramework
}

if ($LoadedAssemblies -notmatch "System.Windows.Forms") {
	Add-Type -AssemblyName System.Windows.Forms
}

$ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition 

[void][System.Reflection.Assembly]::LoadFrom("$ScriptPath\assembly\MahApps.Metro.dll")      
[void][System.Reflection.Assembly]::LoadFrom("$ScriptPath\assembly\MahApps.Metro.IconPacks.dll")  


#Required WinAPI Functions
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
#endregion [Requirements]

#region [Declarations]

#Script Version
$ScriptVersion = [System.Version]"1.1"

#Initialize WPF variable
$global:WPF = [hashtable]::Synchronized(@{})

#Marker for 'time to rest' form
$global:Rest = $false 

#endregion [Declarations]

#region [Functions]

function Load-XamlFromFile{
    <#
    .SYNOPSIS
    Load xaml file, Create global WPF variable with objects and output form to a host.
    #>
    param(
        [Parameter(Position = 0,
                   Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path
    )
    $XamlLoader = New-Object System.Xml.XmlDocument
    $XamlLoader.Load($Path)
    
    $Reader = New-Object System.Xml.XmlNodeReader $XamlLoader
    
    $Form = [Windows.Markup.XamlReader]::Load($Reader)
    
    #Fill WPF Variables
    $XamlLoader.SelectNodes("//*[@Name]") | foreach { 
        $WPF."$($_.Name)" = $Form.FindName($_.Name)
    }
    
    $Form
}

function Update-Form{
    <#
    .SYNOPSIS
    Convert seconds to TimeSpan and update ProgressBar
    #>
    param(
        [Parameter(Position = 0,
                   Mandatory = $true)]
        [Int]
        $Minutes
    )
    $global:Minutes = $Minutes
    $global:TotalSeconds = New-TimeSpan -Minutes $Minutes

    $WPF.Time.Text = $([string]::Format(
                            "{0:d2}:{1:d2}", 
                            $global:TotalSeconds.Minutes, 
                            $global:TotalSeconds.Seconds)
                      )

    $WPF.ProgressBar.Maximum = $global:TotalSeconds.TotalSeconds
    $WPF.ProgressBar.Value = 0
}

#endregion [Functions]

#region [Initialisations]

#Load xaml Form and fill $WPF variable
$Form = Load-XamlFromFile -Path "$ScriptPath\main.xaml" 

#Timer will update Form every second
$WPF.Timer = New-Object System.Windows.Forms.Timer
$WPF.Timer.Interval = 1000  #1 second   

#Filling Form with data saved in settings.xml
[xml]$Settings = Get-Content -Path "$ScriptPath\Settings.xml"

$WPF.ToggleDesktop_c.IsChecked = [System.Convert]::ToBoolean($Settings.Values.ToggleDesktop)
$WPF.PlaySound_c.IsChecked = [System.Convert]::ToBoolean($Settings.Values.PlaySound)
$WPF.SessionTime_s.Value = $Settings.Values.SessionTime  
$WPF.BreakTime_s.Value = $Settings.Values.BreakTime

Update-Form -Minutes $Settings.Values.SessionTime

#endregion [Initialisations]

#region [Handlers]
$Handler = [PSCustomObject]@{
    Start = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
            param($Sender, $EventArgs)
            
            if ($WPF.PlaySound_c.IsChecked) {
                [System.Media.SystemSounds]::Beep.Play()
            }

            $WPF.Start.Visibility = "Hidden"
            $WPF.Stop.Visibility = "Visible"
            $WPF.Settings_B.Visibility = "Hidden"

            $Form.TaskbarItemInfo.ProgressState = "Normal"

            $TickAction = {
                if ($WPF.Timer) {
                    #If time not finished
                    if ([math]::Ceiling($global:TimeSpan.TotalSeconds) -gt 0 ) {
                        $global:TimeSpan = New-TimeSpan $(Get-Date) $global:EndTime 

                        #Update Text
                        $WPF.Time.Text = $([string]::Format(
                                                "{0:d2}:{1:d2}",
                                                $global:TimeSpan.minutes,
                                                $global:TimeSpan.seconds)
                                          )
                        #Update Progress Bar
                        $WPF.ProgressBar.Value = $global:TotalSeconds.TotalSeconds - $global:TimeSpan.TotalSeconds

                        $Form.TaskbarItemInfo.ProgressValue = $($WPF.ProgressBar.Value/$WPF.ProgressBar.Maximum)
                    }else {
                        $WPF.Timer.Stop()

                        if ($WPF.PlaySound_c.IsChecked) {
                            [System.Media.SystemSounds]::Beep.Play()
                        }

                        if ($WPF.ToggleDesktop_c.IsChecked) {
                            $ShellExp = New-Object -ComObject Shell.Application
                            $ShellExp.ToggleDesktop()
                        }

                        if ($global:Rest -eq $false) {
                            Update-Form -minutes $Settings.Values.BreakTime 
                            $global:Rest = $true
                        }else{
                            Update-Form -minutes $Settings.Values.SessionTime 
                            $global:Rest = $false
                        }

                        $WPF.Start.Visibility = "Visible"
                        $WPF.Stop.Visibility = "Hidden"
                        $WPF.Settings_B.Visibility = "Visible"
                        $WPF.Timer.Remove_Tick($TickAction)
                    }
                }
            }
            
            $global:StartTime = Get-Date
            $global:EndTime = $StartTime.AddMinutes($Minutes)
            $global:TimeSpan = New-Timespan $global:StartTime $global:EndTime
            
            $WPF.Timer.Add_Tick($TickAction)
            $WPF.Timer.Start()
        }
    }
    
    Stop = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
            param($Sender, $EventArgs)
            
            $WPF.Timer.Stop()
            $Form.TaskbarItemInfo.ProgressState = "None"
            if ($global:Rest -eq $false) {
                Update-Form -Minutes $settings.Values.SessionTime
            }else{
                Update-Form -Minutes $settings.Values.BreakTime
            }

            $WPF.Start.Visibility = "Visible"
            $WPF.Stop.Visibility = "Hidden"
            $WPF.Settings_B.Visibility = "Visible"

            $WPF.Time.Text = $([string]::Format(
                                "{0:d2}:{1:d2}",
                                $global:TotalSeconds.minutes,
                                $global:TotalSeconds.seconds)
                              )
            $WPF.ProgressBar.Value = 0
        }
    }

    Settings = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
            param($Sender, $EventArgs)
            
            if ($WPF.Main_G.Visibility -eq "Visible"){
                $WPF.Settings_G.Visibility = "Visible"
                $WPF.Main_G.Visibility = "Hidden"
                $Form.TaskbarItemInfo.ProgressState = "None"
            }else{
                if ($global:Rest -eq $false) {
                    Update-Form -Minutes $Settings.Values.SessionTime
                }else{
                    Update-Form -Minutes $Settings.Values.BreakTime 
                }
                $WPF.Main_G.Visibility = "Visible"
                $WPF.Settings_G.Visibility = "Hidden"
                $Form.TaskbarItemInfo.ProgressState = "Normal"
            }
        }
    }

    ToggleDesktop = [PSCustomObject]@{
        Checked= [System.Windows.RoutedEventHandler]{
           $Settings.Values.ToggleDesktop = "True"
           $Settings.Save("$ScriptPath\Settings.xml")
        }
        Unchecked= [System.Windows.RoutedEventHandler]{
           $settings.Values.ToggleDesktop = "False"
           $settings.Save("$ScriptPath\Settings.xml")
        }
    }

    PlaySound = [PSCustomObject]@{
        Checked= [System.Windows.RoutedEventHandler]{
           $Settings.Values.PlaySound = "True"
           $Settings.Save("$ScriptPath\Settings.xml")
        }
        Unchecked= [System.Windows.RoutedEventHandler]{
           $Settings.Values.PlaySound = "False"
           $Settings.Save("$ScriptPath\Settings.xml")
        }
    } 

    SessionTime= [PSCustomObject]@{
        ValueChanged= [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
           
           $Settings.Values.SessionTime = "$($EventArgs.NewValue)"
           $Settings.Save("$ScriptPath\Settings.xml")
        }
    }  

    BreakTime= [PSCustomObject]@{
        ValueChanged= [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
           
           $Settings.Values.BreakTime = "$($EventArgs.NewValue)"
           $Settings.Save("$ScriptPath\Settings.xml")
        }
    }           
}

$WPF.Start.AddHandler([System.Windows.Controls.Button]::ClickEvent,$Handler.Start.Click)
$WPF.Stop.AddHandler([System.Windows.Controls.Button]::ClickEvent,$Handler.Stop.Click)

$WPF.Settings_B.AddHandler([System.Windows.Controls.Button]::ClickEvent,$Handler.Settings.Click)

$WPF.ToggleDesktop_c.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent,$Handler.ToggleDesktop.Checked)
$WPF.ToggleDesktop_c.AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent,$Handler.ToggleDesktop.Unchecked)

$WPF.PlaySound_c.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent,$Handler.PlaySound.Checked)
$WPF.PlaySound_c.AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent,$Handler.PlaySound.Unchecked)

$WPF.SessionTime_s.AddHandler([System.Windows.Controls.Slider]::ValueChangedEvent,$Handler.SessionTime.ValueChanged)
$WPF.BreakTime_s.AddHandler([System.Windows.Controls.Slider]::ValueChangedEvent,$Handler.BreakTime.ValueChanged)
#endregion [Handlers]

#Hide console
$ConsolePtr = [Console.Window]::GetConsoleWindow()
[void][Console.Window]::ShowWindow($ConsolePtr, 0)

#Run
[void]$Form.Dispatcher.InvokeAsync({
    [void]$Form.ShowDialog()
}).Wait()
