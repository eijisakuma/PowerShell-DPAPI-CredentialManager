# ==============================================================================
# スクリプト名: Execute-SaveCredentials.ps1
# 概要: DbCredentials モジュールを呼び出して、db_input.json から認証情報を暗号化し、
#       db_credentials.xml を生成後、元ファイルを削除する処理を関数化しています。
# 実行権限: SYSTEMアカウント (または最上位の特権)
# ==============================================================================

function Invoke-SaveDbCredentialsTask {
    [CmdletBinding()]
    param (
        # 入力ファイルのパス（省略時はスクリプト配置フォルダの db_input.json）
        [Parameter(Mandatory = $false)]
        [string]$InputFilePath,

        # 出力先XMLファイルのパス（省略時はスクリプト配置フォルダの db_credentials.xml）
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath,

        # ログファイルのパス（省略時はスクリプト配置フォルダの db_credentials.log）
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,

        # 完了時に入力ファイルを削除するかどうか（デフォルト: True）
        [Parameter(Mandatory = $false)]
        [bool]$RemoveSourceFile = $true
    )

    $ErrorActionPreference = "Stop"

    try {
        # スクリプトが置かれているディレクトリパスを取得
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

        # パスの初期値設定
        if ([string]::IsNullOrEmpty($InputFilePath)) {
            $InputFilePath = Join-Path -Path $scriptDir -ChildPath "db_input.json"
        }
        if ([string]::IsNullOrEmpty($OutputFilePath)) {
            $OutputFilePath = Join-Path -Path $scriptDir -ChildPath "db_credentials.xml"
        }
        if ([string]::IsNullOrEmpty($LogFilePath)) {
            $LogFilePath = Join-Path -Path $scriptDir -ChildPath "db_credentials.log"
        }

        # モジュールの暗号化関数を実行
        $result = Save-DbCredentials `
            -InputFilePath $InputFilePath `
            -OutputFilePath $OutputFilePath `
            -LogFilePath $LogFilePath `
            -RemoveSourceFile $RemoveSourceFile

        return $result
    }
    catch {
        Write-Error "[エラー] タスク実行中に例外が発生しました: $_"
        exit 1
    }
}

# ==============================================================================
# スクリプト直接実行時の処理
# タスクスケジューラ等から `-File Execute-SaveCredentials.ps1` で呼ばれた場合は
# 自動的に上記関数を実行します。
# （ドットソース読み込み `. .\Execute-SaveCredentials.ps1` 時は実行されず、関数の定義のみが行われます）
# ==============================================================================
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SaveDbCredentialsTask
}
