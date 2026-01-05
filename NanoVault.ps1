#  _   _                __     __          _ _   
# | \ | | __ _ _ __   __\ \   / /_ _ _   _| | |_ 
# |  \| |/ _` | '_ \ / _ \ \ / / _` | | | | | __|
# | |\  | (_| | | | | (_) \ V / (_| | |_| | | |_ 
# |_| \_|\__,_|_| |_|\___/ \_/ \__,_|\__,_|_|\__|
#
# Minimal and portable vault for Windows.
# Secure a secret in a single PowerShell script.
#
#
#
# LICENSE:
#
# MIT License
# 
# Copyright (c) 2026 brunodsf05
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

Add-Type -AssemblyName PresentationFramework

# --- CONFIGURATION ---

# If $secret is empty: Generate one in "encrypt" mode, copy and paste it
# Example: $secret = '{"Data":"...","IV":"...","Salt":"..."}'
$secret = ''

$help = @{
    decrypting = @"
Enter the password to decrypt the secret.
If the password is incorrect, the operation will fail.
The decrypted value can be copied by clicking it.
"@

    encrypting = @"
Write the secret you want to encrypt.
To embed it into the script, copy the result, open the
script and replace the "`$secret" line.
"@

    noSecret = 'There is no secret in this script! Please go to "Encrypt"...'
}

# --- CRYPTOGRAPHY ---
function Encrypt-Text {
    param ($PlainText, $Password)

    try {
        $salt = New-Object byte[] 16
        $iv   = New-Object byte[] 16
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)

        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, 100000)
        $key = $kdf.GetBytes(32)

        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV  = $iv

        $encryptor = $aes.CreateEncryptor()
        $cipher = $encryptor.TransformFinalBlock(
            [Text.Encoding]::UTF8.GetBytes($PlainText), 0, $PlainText.Length
        )

        @{
            Salt = [Convert]::ToBase64String($salt)
            IV   = [Convert]::ToBase64String($iv)
            Data = [Convert]::ToBase64String($cipher)
        } | ConvertTo-Json -Compress
    }
    catch {
        return $null
    }
}

function Decrypt-Text {
    param ($EncryptedJson, $Password)

    try {
        $obj  = $EncryptedJson | ConvertFrom-Json
        $salt = [Convert]::FromBase64String($obj.Salt)
        $iv   = [Convert]::FromBase64String($obj.IV)
        $data = [Convert]::FromBase64String($obj.Data)

        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, 100000)
        $key = $kdf.GetBytes(32)

        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $key
        $aes.IV  = $iv

        $decryptor = $aes.CreateDecryptor()
        $plain = $decryptor.TransformFinalBlock($data, 0, $data.Length)

        [Text.Encoding]::UTF8.GetString($plain)
    }
    catch {
        return $null
    }
}

# --- UI --- #


# Utils
function Add-CopyOnClick {
    param ($TextBox)
    $TextBox.Add_PreviewMouseLeftButtonDown({
        if ($this.IsReadOnly -and $this.Text -ne "") {
            [System.Windows.Clipboard]::SetText($this.Text)
        }
    })
}

# Layout

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="NanoVault"
        SizeToContent="WidthAndHeight"
        WindowStartupLocation="CenterScreen"
        MinWidth="400"
        >

    <Grid Margin="10">
        <!-- Grid: Settings -->
        <Grid.Resources>
            <Style TargetType="Control">
                <Setter Property="Margin" Value="5"/>
            </Style>
        </Grid.Resources>

        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Control: Password -->
        <Label Grid.Row="0" Grid.Column="0" Content="Password:"/>
        <PasswordBox Grid.Row="0" Grid.Column="1" Name="Password" Margin="0,4,0,0"/>

        <!-- Control: Secret -->
        <Label Grid.Row="1" Grid.Column="0" Content="Secret:"/>
        <TextBox Grid.Row="1" Grid.Column="1" Name="Secret" Margin="0,4,0,0" IsReadOnly="True"/>

        <!-- Control: Output mode -->
        <Label Grid.Row="2" Grid.Column="0" Content="Mode:"/>
        <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,0">
            <RadioButton GroupName="Mode" Name="Decrypt" Content="Decrypt" IsChecked="True" Margin="0,3,10,0"/>
            <RadioButton GroupName="Mode" Name="Encrypt" Content="Encrypt" Margin="0,3,0,0"/>
        </StackPanel>

        <!-- Control: Encrypted -->
        <Label Grid.Row="3" Grid.Column="0" Content="Encrypted:" Name="LabelEncrypted" Visibility="Hidden"/>
        <TextBox Grid.Row="3" Grid.Column="1" Name="Encrypted" Margin="0,4,0,0" Visibility="Hidden" IsReadOnly="True"/>

        <!-- Control: Hint -->
        <Label Grid.Row="4" Grid.Column="0" Name="Hint" Margin="0,20,0,0" Grid.ColumnSpan="2" Foreground="#AA000000"/>
    </Grid>
</Window>
"@

# Init window
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.Add_ContentRendered({
    $window.MinHeight = $window.ActualHeight
    $window.SizeToContent = [System.Windows.SizeToContent]::Manual
})

$uiControlPassword = $window.FindName("Password")
$uiControlSecret = $window.FindName("Secret")
$uiControlDecrypt = $window.FindName("Decrypt")
$uiControlEncrypt = $window.FindName("Encrypt")
$uiControlLabelEncrypted = $window.FindName("LabelEncrypted")
$uiControlEncrypted = $window.FindName("Encrypted")
$uiControlHint = $window.FindName("Hint")

$uiControlHint.Content = $help.decrypting

if ($secret -eq "") {
    $uiControlSecret.Text = $help.noSecret
}

# Debounce handler
$uiSemaphoreDenyUpdate = $false
$uiDebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(500)

function Ui-Update {
    # Skip updates triggered by programmatic text changes
    if ($uiSemaphoreDenyUpdate) { return }
    $uiDebounceTimer.Stop()
    Ui-Update-Init
    $uiDebounceTimer.Start()
}

$uiDebounceTimer.Add_Tick({
    $uiDebounceTimer.Stop()
    $uiSemaphoreDenyUpdate = $true
    Ui-Update-Late
    $uiSemaphoreDenyUpdate = $false
})

# Update values
function Ui-Update-Init() {
    $isDecrypting = ($uiControlDecrypt.IsChecked -eq $true)

    if ($isDecrypting) {
        $uiControlSecret.Text = if ($secret -eq "") { $help.noSecret } else { "Decrypting..." }
        $uiControlSecret.IsReadOnly = $true

        $uiControlLabelEncrypted.Visibility = [System.Windows.Visibility]::Hidden
        $uiControlEncrypted.Visibility = [System.Windows.Visibility]::Hidden

        $uiControlHint.Content = $help.decrypting
    }
    else {
        $uiControlSecret.IsReadOnly = $false

        $uiControlLabelEncrypted.Visibility = [System.Windows.Visibility]::Visible
        $uiControlEncrypted.Visibility = [System.Windows.Visibility]::Visible

        $uiControlEncrypted.Text = if ($uiControlSecret.Text -eq "") { "Write your secret!" } else { "Encrypting..." }

        $uiControlHint.Content = $help.encrypting
    }
}

function Ui-Update-Late() {
    $isDecrypting = ($uiControlDecrypt.IsChecked -eq $true -and $secret -ne "")

    if ($isDecrypting) {
        $decrypted = Decrypt-Text $secret $uiControlPassword.Password
        $uiControlSecret.Text = if ($decrypted -eq $null) { "Bad password" } else { $decrypted }
    }
    elseif ($uiControlSecret.Text -ne  "") {
        $encrypted = Encrypt-Text $uiControlSecret.Text $uiControlPassword.Password
        $uiControlEncrypted.Text = '$secret = ''' + $encrypted + ''''
    }
}

# Initialize listeners
$uiControlPassword.Add_PasswordChanged({ Ui-Update })
$uiControlSecret.Add_TextChanged({ Ui-Update })
$uiControlDecrypt.Add_Checked({ Ui-Update })
$uiControlEncrypt.Add_Checked({ Ui-Update; $uiControlSecret.Text = "" })
Add-CopyOnClick $uiControlSecret
Add-CopyOnClick $uiControlEncrypted

# --- INIT --- #

$result = $window.ShowDialog()
