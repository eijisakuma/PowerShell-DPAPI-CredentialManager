# ==========================================
# Win32 API および マーシャリングヘルパー
# ==========================================
if (-not ([System.Management.Automation.PSTypeName]'Win32CredentialHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32CredentialHelper {
    public const int CRED_TYPE_GENERIC = 1;
    public const int CRED_PERSIST_LOCAL_MACHINE = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite([In] ref CREDENTIAL userCredential, [In] uint flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("Advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    public static extern void CredFree([In] IntPtr credPointer);

    // PowerShellを介さず C# 側で確実に型安全に構造体を読み出すメソッド
    public static bool ReadCredential(string targetName, out string userName, out string password, out int errorCode) {
        userName = null;
        password = null;
        errorCode = 0;
        IntPtr credPtr = IntPtr.Zero;

        if (!CredRead(targetName, CRED_TYPE_GENERIC, 0, out credPtr)) {
            errorCode = Marshal.GetLastWin32Error();
            return false;
        }

        try {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
            userName = cred.UserName;
            if (cred.CredentialBlobSize > 0 && cred.CredentialBlob != IntPtr.Zero) {
                byte[] blob = new byte[cred.CredentialBlobSize];
                Marshal.Copy(cred.CredentialBlob, blob, 0, cred.CredentialBlobSize);
                password = Encoding.Unicode.GetString(blob);
            }
            return true;
        } finally {
            if (credPtr != IntPtr.Zero) {
                CredFree(credPtr);
            }
        }
    }
}
"@
}

# ==========================================
# 登録関数
# ==========================================
function Set-Credencial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$TargetName,
        [Parameter(Mandatory = $true, Position = 1)][string]$UserName,
        [Parameter(Mandatory = $true, Position = 2)][string]$Password
    )

    $cred = New-Object Win32CredentialHelper+CREDENTIAL
    $cred.Type = [Win32CredentialHelper]::CRED_TYPE_GENERIC
    $cred.TargetName = $TargetName
    $cred.UserName = $UserName
    $cred.Persist = [Win32CredentialHelper]::CRED_PERSIST_LOCAL_MACHINE

    $passBytes = [System.Text.Encoding]::Unicode.GetBytes($Password)
    $cred.CredentialBlobSize = $passBytes.Length
    $cred.CredentialBlob = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($passBytes.Length)

    try {
        [System.Runtime.InteropServices.Marshal]::Copy($passBytes, 0, $cred.CredentialBlob, $passBytes.Length)
        $result = [Win32CredentialHelper]::CredWrite([ref]$cred, 0)
        if (-not $result) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CredWrite に失敗しました。エラーコード: $err"
        }
    }
    finally {
        if ($cred.CredentialBlob -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($cred.CredentialBlob)
        }
    }
}

# ==========================================
# 取得関数（C#の静的メソッドを直接呼び出し）
# ==========================================
function Get-Credencial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$TargetName
    )

    $userName = ""
    $password = ""
    $errorCode = 0

    $success = [Win32CredentialHelper]::ReadCredential($TargetName, [ref]$userName, [ref]$password, [ref]$errorCode)

    if (-not $success) {
        # 1168 = ERROR_NOT_FOUND
        if ($errorCode -eq 1168) {
            return $null
        }
        throw "CredRead に失敗しました。エラーコード: $errorCode"
    }

    return [PSCustomObject]@{
        TargetName = $TargetName
        UserId     = $userName
        Password   = $password
    }
}

# ==========================================
# JSON 連携関数
# ==========================================
function Get-OrSetCredentialFromJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$TargetName,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$JsonPath
    )

    # ① 既存チェック
    $cred = Get-Credencial -TargetName $TargetName

    # ② なければ登録
    if ($null -eq $cred) {
        if (-not (Test-Path -Path $JsonPath)) {
            throw "初期化用のJSONファイルが見つかりません: $JsonPath"
        }

        $jsonContent = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if (-not $jsonContent.TargetName -or -not $jsonContent.UserName -or -not $jsonContent.Password) {
            throw "JSONファイルに必要なキー (TargetName, UserName, Password) が不足しています。"
        }

        Set-Credencial -TargetName $jsonContent.TargetName -UserName $jsonContent.UserName -Password $jsonContent.Password

        # 登録確認
        $cred = Get-Credencial -TargetName $jsonContent.TargetName

        if ($null -ne $cred) {
            Remove-Item -Path $JsonPath -Force
        } else {
            throw "資格情報の登録後の確認取得に失敗しました。"
        }
    }

    # ③ 返却
    return $cred
}

Export-ModuleMember -Function Set-Credencial, Get-Credencial, Get-OrSetCredentialFromJson