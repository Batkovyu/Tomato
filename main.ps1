Write-Host "Launching...Please wait..."
# bad comment
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'




$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition 
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework') 
[void][System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')  
[void][System.Reflection.Assembly]::LoadFrom("$scriptPath\assembly\MahApps.Metro.dll")      
[void][System.Reflection.Assembly]::LoadFrom("$scriptPath\assembly\MahApps.Metro.IconPacks.dll")  

#Initialize WPF variable
$Global:WPF = [hashtable]::Synchronized(@{})

#region Functions
function Load-XamlFromFile($Path){
    $XamlLoader = New-Object System.Xml.XmlDocument
    $XamlLoader.Load($Path)
    
    $Reader = New-Object System.Xml.XmlNodeReader $XamlLoader
    
    $Form = [Windows.Markup.XamlReader]::Load($Reader)
    #Fill WPF Variables
    $XamlLoader.SelectNodes("//*[@Name]") | ForEach-Object { $WPF."$($_.Name)" = $Form.FindName($_.Name)}
    
    $Form
}

function ConvertTo-Seconds($minutes){
    $global:minutes = $minutes
    $global:totalseconds = new-timespan -Minutes $minutes

    $WPF.Time.Text    = $([string]::Format("{0:d2}:{1:d2}", `
                            $global:totalseconds.minutes, `
                            $global:totalseconds.seconds))

    $WPF.Pbar.Maximum = $global:totalseconds.TotalSeconds
    $WPF.Pbar.Value   = 0

}
#endregion Functions






$Form = Load-XamlFromFile -Path "$scriptPath\main.xaml" 

[xml]$settings = Get-Content -Path "$scriptPath\Settings.xml"

$WPF.Desktop_c.IsChecked = [System.Convert]::ToBoolean($settings.Settings.Desktop)
$WPF.Sound_c.IsChecked   = [System.Convert]::ToBoolean($settings.Settings.Sound)
#Session Time
$WPF.Minutes1_s.Value    = $settings.Settings.Minutes.Value1
#Time for Rest
$WPF.Minutes2_s.Value    = $settings.Settings.Minutes.Value2

$global:rest = $false 

ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value1
 
#Handlers deffinitions
$Handler = [PSCustomObject]@{
    Start = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
            if ($WPF.Sound_c.IsChecked) {
                [System.Media.SystemSounds]::Beep.Play()
            }
            $WPF.Start.Visibility      = "Hidden"
            $WPF.Stop.Visibility       = "Visible"
            $WPF.Settings_B.Visibility = "Hidden"
            $Form.TaskbarItemInfo.ProgressState = "Normal"

            [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
            $WPF.Timer          = New-Object System.Windows.Forms.Timer
            $WPF.Timer.Interval = 1000    

            $TickAction = {
                if ($WPF.Timer) {
                    #If time not finished
                    if ([math]::Ceiling($global:timeSpan.TotalSeconds) -gt 0 ) {
                        $global:timeSpan = New-Timespan $(get-date) $global:endTime 

                        #Update Text
                        $WPF.Time.Text = $([string]::Format("{0:d2}:{1:d2}", `
                            $global:timeSpan.minutes, `
                            $global:timeSpan.seconds))
                        #Update Progress Bar
                        $WPF.Pbar.Value = $global:totalseconds.TotalSeconds - $global:timeSpan.TotalSeconds

                        $Form.TaskbarItemInfo.ProgressValue = $($WPF.Pbar.Value/$WPF.Pbar.Maximum)
                    }Else {
                        $WPF.Timer.Stop()

                        if ($WPF.Sound_c.IsChecked) {
                            [System.Media.SystemSounds]::Beep.Play()
                        }

                        if ($WPF.Desktop_c.IsChecked) {
                            $ShellExp = New-Object -ComObject Shell.Application
                            $ShellExp.ToggleDesktop()
                        }

                        if ($global:rest -eq $false) {
                            ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value2 
                            $global:rest = $true
                        }Else{
                            ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value1
                            $global:rest = $false
                        }

                        $WPF.Start.Visibility      = "Visible"
                        $WPF.Stop.Visibility       = "Hidden"
                        $WPF.Settings_B.Visibility = "Visible"
                        $WPF.Timer.Remove_Tick($TickAction)
                    }
                }
            }
            
            $global:startTime = Get-Date
            $global:endTime   = $startTime.addMinutes($minutes)
            $global:timeSpan  = New-Timespan $global:startTime $global:endTime
            
            $WPF.Timer.Add_Tick($TickAction)
            $WPF.Timer.Start()
        }
    }
    
    Stop = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
            $WPF.Timer.Stop()
            $Form.TaskbarItemInfo.ProgressState = "None"
            if ($global:rest -eq $false) {
                ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value1
            }Else{
                ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value2
            }

            $WPF.Start.Visibility      = "Visible"
            $WPF.Stop.Visibility       = "Hidden"
            $WPF.Settings_B.Visibility = "Visible"

            $WPF.Time.Text = $([string]::Format("{0:d2}:{1:d2}", `
                        $global:totalseconds.minutes, `
                        $global:totalseconds.seconds))
            $WPF.Pbar.Value = 0
        }
    }
    Settings = [PSCustomObject]@{
        Click = [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
            if ($WPF.Main_G.Visibility -eq "Visible"){
                $WPF.Settings_G.Visibility = "Visible"
                $WPF.Main_G.Visibility     = "Hidden"
                $Form.TaskbarItemInfo.ProgressState = "None"
            }Else{
                if ($global:rest -eq $false) {
                    ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value1 
                }Else{
                    ConvertTo-Seconds -minutes $settings.Settings.Minutes.Value2 
                }
                $WPF.Main_G.Visibility     = "Visible"
                $WPF.Settings_G.Visibility = "Hidden"
                $Form.TaskbarItemInfo.ProgressState = "Normal"
            }
        }
    }
    Desktop = [PSCustomObject]@{
        Checked= [System.Windows.RoutedEventHandler]{
           $settings.Settings.Desktop = "True"
           $settings.Save("$scriptPath\Settings.xml")
        }
        Unchecked= [System.Windows.RoutedEventHandler]{
           $settings.Settings.Desktop = "False"
           $settings.Save("$scriptPath\Settings.xml")
        }
    }
    Sound = [PSCustomObject]@{
        Checked= [System.Windows.RoutedEventHandler]{
           $settings.Settings.Sound = "True"
           $settings.Save("$scriptPath\Settings.xml")
        }
        Unchecked= [System.Windows.RoutedEventHandler]{
           $settings.Settings.Sound = "False"
           $settings.Save("$scriptPath\Settings.xml")
        }
    } 
    Minutes1= [PSCustomObject]@{
        ValueChanged= [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
           $settings.Settings.Minutes.Value1 = "$($EventArgs.NewValue)"
           $settings.Save("$scriptPath\Settings.xml")
        }
    }  
    Minutes2= [PSCustomObject]@{
        ValueChanged= [System.Windows.RoutedEventHandler]{
           param($Sender, $EventArgs)
           $settings.Settings.Minutes.Value2 = "$($EventArgs.NewValue)"
           $settings.Save("$scriptPath\Settings.xml")
        }
    }           
}


$WPF.Start.     AddHandler([System.Windows.Controls.Button]::ClickEvent,       $Handler.Start.Click)
$WPF.Stop.      AddHandler([System.Windows.Controls.Button]::ClickEvent,       $Handler.Stop.Click)

$WPF.Settings_B.AddHandler([System.Windows.Controls.Button]::ClickEvent,       $Handler.Settings.Click)
$WPF.Desktop_c. AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent,   $Handler.Desktop.Checked)
$WPF.Desktop_c. AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent, $Handler.Desktop.Unchecked)
$WPF.Sound_c.   AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent,   $Handler.Sound.Checked)
$WPF.Sound_c.   AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent, $Handler.Sound.Unchecked)

$WPF.Minutes1_s.AddHandler([System.Windows.Controls.Slider]::ValueChangedEvent,$Handler.Minutes1.ValueChanged)
$WPF.Minutes2_s.AddHandler([System.Windows.Controls.Slider]::ValueChangedEvent,$Handler.Minutes2.ValueChanged)

#Hide console
$consolePtr = [Console.Window]::GetConsoleWindow()
[void][Console.Window]::ShowWindow($consolePtr, 0)

#Run
[void]$Form.Dispatcher.InvokeAsync({[void]$Form.ShowDialog()}).Wait()