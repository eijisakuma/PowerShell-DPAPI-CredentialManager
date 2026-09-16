# ==============================================================================
# スクリプト名: Execute-ReadCredentials.ps1
# 概要: DbCredentials モジュールを利用して db_credentials.xml を復号し、
#       平文のユーザー名とパスワードを持つオブジェクトを返す関数を提供します。
# 実行権限: 暗号化時と同じアカウント (SYSTEM)
# ==============================================================================

<#
.SYNOPSIS
    DPAPIで暗号化されたXMLファイルを復号し、平文のユーザー名とパスワードを返します。

.DESCRIPTION
    指定されたXMLファイルを復号し、User と Password プロパティを持つ
    PSCustomObject を返却します。他のスクリプトからドットソースで読み込んで利用可能です。

.EXAMPLE
    . .\Execute-ReadCredentials.ps1
    $cred = Get-DecryptedDbCredentials
    Write-Host "ユーザー: $($cred.User)"
    Write-Host "パスワード: $($cred.Password)"
#>
function Get-DecryptedDbCredentials {
    [CmdletBinding()]
    param (
        # 暗号化されたXMLファイルのパス（省略時はスクリプト配置フォルダの db_credentials.xml）
        [Parameter(Mandatory = $false)]
        [string]$CredentialFilePath
    )

    $ErrorActionPreference = "Stop"

    try {
        # 実行フォルダを取得
        $scriptDir = $PSScriptRoot
        if ([string]::IsNullOrEmpty($scriptDir)) {
            $scriptDir = (Get-Location).Path
        }

        # モジュールファイルのフルパスを指定してインポート
        $modulePath = Join-Path -Path $scriptDir -ChildPath "DbCredentials.psm1"
        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw "モジュールが見つかりません: $modulePath"
        }
        Import-Module -Name $modulePath -Force

        # 暗号化ファイルパスの補完
        if ([string]::IsNullOrEmpty($CredentialFilePath)) {
            $CredentialFilePath = Join-Path -Path $scriptDir -ChildPath "db_credentials.xml"
        }

        # モジュールの Get-DbCredentials を呼び出して PSCredential を取得
        $credential = Get-DbCredentials -CredentialFilePath $CredentialFilePath

        # ユーザー名の取得
        $dbUser = $credential.UserName

        # パスワードの復号（SecureString から平文文字列へ安全に変換）
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        $dbPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        # メモリから平文ポインタを解放
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        # 平文のユーザー名とパスワードを格納したカスタムオブジェクトを返す
        return [PSCustomObject]@{
            User     = $dbUser
            Password = $dbPassword
        }
    }
    catch {
        Write-Error "[エラー] 認証情報の復号処理中に例外が発生しました: $_"
        throw
    }
}

# ==============================================================================
# スクリプト直接実行時の処理
# `-File Execute-ReadCredentials.ps1` などで直接実行された場合は
# 自動的に関数を実行して結果を出力します。
# （ドットソース読み込み `. .\Execute-ReadCredentials.ps1` 時は関数の定義のみが行われます）
# ==============================================================================
if ($MyInvocation.InvocationName -ne '.') {
    Get-DecryptedDbCredentials
}
