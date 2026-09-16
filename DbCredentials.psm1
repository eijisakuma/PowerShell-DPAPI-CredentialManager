<#
.SYNOPSIS
    DB認証情報をDPAPIで暗号化して保存・復号するためのPowerShellモジュールです。

.DESCRIPTION
    一時的な平文の定義ファイルからユーザー名・パスワードを読み込み、
    DPAPI（CurrentUserスコープ）で暗号化されたXMLファイルを出力します。
    暗号化完了後、元の定義ファイルは自動的に安全に削除されます。
#>

# 内部用の簡易ログ出力関数
function Write-DbLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [string]$LogFilePath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    # コンソールへの色分け表示
    switch ($Level) {
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        "WARN"    { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logLine -ForegroundColor Red }
        default   { Write-Host $logLine -ForegroundColor Cyan }
    }

    # ログファイルへの追記（指定がある場合）
    if (-not [string]::IsNullOrEmpty($LogFilePath)) {
        try {
            Add-Content -LiteralPath $LogFilePath -Value $logLine -Encoding UTF8
        }
        catch {
            Write-Warning "ログファイルへの書き込みに失敗しました: $_"
        }
    }
}

function Save-DbCredentials {
    [CmdletBinding()]
    param (
        # 認証情報が書かれた一時入力ファイルのパス（JSON形式）
        [Parameter(Mandatory = $false)]
        [string]$InputFilePath,

        # 暗号化後の出力先XMLファイルパス
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath,

        # ログ出力先ファイルパス（指定がない場合は実行フォルダの db_credentials.log）
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,

        # 暗号化完了後に元ファイルを削除するかどうか（デフォルト: True）
        [Parameter(Mandatory = $false)]
        [bool]$RemoveSourceFile = $true
    )

    # エラー発生時は処理を中断
    $ErrorActionPreference = "Stop"

    # デフォルトパスの補完（指定がない場合は実行ディレクトリ基準）
    $baseDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($baseDir)) {
        $baseDir = (Get-Location).Path
    }

    if ([string]::IsNullOrEmpty($InputFilePath)) {
        $InputFilePath = Join-Path -Path $baseDir -ChildPath "db_input.json"
    }
    if ([string]::IsNullOrEmpty($OutputFilePath)) {
        $OutputFilePath = Join-Path -Path $baseDir -ChildPath "db_credentials.xml"
    }
    if ([string]::IsNullOrEmpty($LogFilePath)) {
        $LogFilePath = Join-Path -Path $baseDir -ChildPath "db_credentials.log"
    }

    # 1. 定義ファイルの存在確認
    # ファイルが存在しない場合はエラーにせず、ログを出力して正常終了する
    if (-not (Test-Path -LiteralPath $InputFilePath)) {
        Write-DbLog -Message "定義ファイルが存在しないため、暗号化処理をスキップしました (ファイル: $InputFilePath)" -Level "INFO" -LogFilePath $LogFilePath
        return $false
    }

    try {
        Write-DbLog -Message "定義ファイルを検出しました。暗号化処理を開始します: $InputFilePath" -Level "INFO" -LogFilePath $LogFilePath

        # 2. 定義ファイル（JSON）の読み込み
        $rawContent = Get-Content -LiteralPath $InputFilePath -Raw -Encoding UTF8
        $config = $rawContent | ConvertFrom-Json

        # 必須プロパティのチェック
        if ([string]::IsNullOrEmpty($config.User) -or [string]::IsNullOrEmpty($config.Password)) {
            throw "定義ファイル内に 'User' または 'Password' が正しく設定されていません。"
        }

        # 3. パスワード文字列を SecureString（DPAPI暗号化形式）に変換
        $securePassword = ConvertTo-SecureString -String $config.Password -AsPlainText -Force

        # 4. PSCredential オブジェクトを作成
        $credential = New-Object System.Management.Automation.PSCredential($config.User, $securePassword)

        # 5. Export-Clixml でファイルに出力（DPAPIで保護されて保存されます）
        $credential | Export-Clixml -LiteralPath $OutputFilePath

        # 成功ログの出力
        Write-DbLog -Message "認証情報をDPAPIで暗号化して正常に出力しました: $OutputFilePath" -Level "SUCCESS" -LogFilePath $LogFilePath

        # 6. 元の定義ファイルを削除（セキュリティ向上のため内容を上書きした後に削除）
        if ($RemoveSourceFile) {
            Set-Content -LiteralPath $InputFilePath -Value "OVERWRITTEN" -Encoding UTF8
            Remove-Item -LiteralPath $InputFilePath -Force
            Write-DbLog -Message "元の一時定義ファイルを安全に削除しました: $InputFilePath" -Level "SUCCESS" -LogFilePath $LogFilePath
        }

        return $true
    }
    catch {
        Write-DbLog -Message "認証情報の暗号化処理中にエラーが発生しました: $_" -Level "ERROR" -LogFilePath $LogFilePath
        throw
    }
}

function Get-DbCredentials {
    [CmdletBinding()]
    param (
        # 暗号化されたXMLファイルのパス
        [Parameter(Mandatory = $false)]
        [string]$CredentialFilePath
    )

    $ErrorActionPreference = "Stop"

    # デフォルトパスの補完
    $baseDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($baseDir)) {
        $baseDir = (Get-Location).Path
    }

    if ([string]::IsNullOrEmpty($CredentialFilePath)) {
        $CredentialFilePath = Join-Path -Path $baseDir -ChildPath "db_credentials.xml"
    }

    if (-not (Test-Path -LiteralPath $CredentialFilePath)) {
        throw "暗号化ファイルが見つかりません: $CredentialFilePath"
    }

    try {
        # Import-Clixml で復号して PSCredential を取得
        $credential = Import-Clixml -LiteralPath $CredentialFilePath
        return $credential
    }
    catch {
        Write-Error "[エラー] 認証情報の復号に失敗しました（暗号化したアカウントと異なる可能性があります）: $_"
        throw
    }
}

# 外部から呼び出し可能な関数をエクスポート
Export-ModuleMember -Function Save-DbCredentials, Get-DbCredentials, Write-DbLog
