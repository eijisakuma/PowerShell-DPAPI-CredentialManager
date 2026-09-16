# ==============================================================================
# スクリプト名: Main-CredentialWorkflow.ps1
# 概要: タスクスケジューラ（SYSTEMアカウント・最上位特権）から実行され、
#       1. 定義ファイル(db_input.json)から暗号化ファイル(db_credentials.xml)の作成と定義ファイルの削除
#       2. 暗号化ファイルから平文のCredential情報(User, Password)を取り出して利用
#       という一連の処理を順番に実行するメインワークフロースクリプトです。
# ==============================================================================

# エラー発生時は処理を停止
$ErrorActionPreference = "Stop"

function Start-CredentialWorkflow {
    [CmdletBinding()]
    param()

    # 1. スクリプト実行フォルダのパスを安全に取得
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptDir)) {
        $scriptDir = (Get-Location).Path
    }

    # 各種ファイルパスの定義
    $saveScriptPath = Join-Path -Path $scriptDir -ChildPath "Execute-SaveCredentials.ps1"
    $readScriptPath = Join-Path -Path $scriptDir -ChildPath "Execute-ReadCredentials.ps1"
    $inputJsonPath  = Join-Path -Path $scriptDir -ChildPath "db_input.json"
    $outputXmlPath  = Join-Path -Path $scriptDir -ChildPath "db_credentials.xml"
    $logFilePath    = Join-Path -Path $scriptDir -ChildPath "db_credentials.log"

    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "[開始] 認証情報ワークフロー処理を開始します" -ForegroundColor Cyan
    Write-Host "実行アカウント: $env:USERNAME" -ForegroundColor Cyan
    Write-Host "実行フォルダ   : $scriptDir" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan

    try {
        # 2. 各スクリプトファイルをドットソース（. ）で読み込み、関数を利用可能にする
        if (-not (Test-Path -LiteralPath $saveScriptPath)) {
            throw "スクリプトが見つかりません: $saveScriptPath"
        }
        if (-not (Test-Path -LiteralPath $readScriptPath)) {
            throw "スクリプトが見つかりません: $readScriptPath"
        }

        # ドットソースで関数を読み込む
        . $saveScriptPath
        . $readScriptPath

        # ----------------------------------------------------------------------
        # ステップ 1: 定義ファイルから暗号化ファイルを作成 & 定義ファイルを削除
        # ----------------------------------------------------------------------
        Write-Host "`n--- [ステップ 1: 暗号化処理] ---" -ForegroundColor Yellow

        # ※ もし定義ファイルが存在しない場合は、暗号化処理内でスキップログが出力されます
        $saveResult = Invoke-SaveDbCredentialsTask `
            -InputFilePath $inputJsonPath `
            -OutputFilePath $outputXmlPath `
            -LogFilePath $logFilePath `
            -RemoveSourceFile $true

        if ($saveResult -eq $true) {
            Write-Host "[ステップ 1 完了] 暗号化ファイルを作成し、元ファイルを削除しました。" -ForegroundColor Green
        }
        else {
            Write-Host "[ステップ 1 スキップ] db_input.json が存在しなかったため、暗号化はスキップされました。" -ForegroundColor Yellow
        }

        # ----------------------------------------------------------------------
        # ステップ 2: 暗号化ファイルから平文の認証情報を取り出す
        # ----------------------------------------------------------------------
        Write-Host "`n--- [ステップ 2: 復号処理] ---" -ForegroundColor Yellow

        if (-not (Test-Path -LiteralPath $outputXmlPath)) {
            throw "暗号化ファイル ($outputXmlPath) が存在しないため、復号処理を実行できません。"
        }

        # 関数を実行して、平文の User と Password を保持するオブジェクトを取得
        $dbCred = Get-DecryptedDbCredentials -CredentialFilePath $outputXmlPath

        $dbUser = $dbCred.User
        $dbPass = $dbCred.Password

        # 取得確認（セキュリティのためパスワードは最初の2文字以外マスクして表示）
        $maskedPass = if ($dbPass.Length -gt 2) { $dbPass.Substring(0, 2) + ("*" * ($dbPass.Length - 2)) } else { "***" }
        Write-Host "[ステップ 2 完了] 認証情報を正常に復号・取得しました。" -ForegroundColor Green
        Write-Host "  復号されたユーザー名  : $dbUser" -ForegroundColor White
        Write-Host "  復号されたパスワード  : $maskedPass (平文長: $($dbPass.Length) 文字)" -ForegroundColor White

        # ----------------------------------------------------------------------
        # ステップ 3: 復号した平文情報を用いて接続文字列を作成・活用する
        # ----------------------------------------------------------------------
        Write-Host "`n--- [ステップ 3: DB接続文字列の生成] ---" -ForegroundColor Yellow

        $server = "db-server.local"
        $database = "ProductionDB"

        # 平文のユーザー名・パスワードを使用して接続文字列を構築
        $connectionString = "Server=$server;Database=$database;User Id=$dbUser;Password=$dbPass;"

        Write-Host "[成功] DB接続文字列の作成に成功しました。" -ForegroundColor Green
        Write-Host "接続文字列サンプル: Server=$server;Database=$database;User Id=$dbUser;Password=$maskedPass;" -ForegroundColor Gray

        # ※ ここに実際のDB処理（SQL実行など）を記述できます
        # 例:
        # $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        # $connection.Open()
        # ...
        # $connection.Close()

        Write-Host "`n=========================================================" -ForegroundColor Cyan
        Write-Host "[完了] 一連のワークフローが正常に完了しました。" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Cyan
    }
    catch {
        Write-Error "[致命的エラー] ワークフローの実行中にエラーが発生しました: $_"
        exit 1
    }
}

# スクリプト直接実行時にメイン関数を開始
Start-CredentialWorkflow
