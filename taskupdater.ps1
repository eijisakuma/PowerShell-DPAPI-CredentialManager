# エラー発生時に処理を停止
$ErrorActionPreference = "Stop"

# 同一フォルダにあるモジュールを読み込み
Import-Module "$PSScriptRoot\CredentialHelper.psm1" -Force

# 設定情報
$targetName = "MyTargetService"
$jsonPath   = "$PSScriptRoot\initial_cred.json"
$logPath    = "$PSScriptRoot\credential_run.log"

# ログ出力用補助関数
function Write-Log {
    param(
        [string]$Message,
        [string]$Path
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] $Message"
    
    # 画面とファイルの両方に出力（UTF-8）
    Write-Host $logLine
    Add-Content -Path $Path -Value $logLine -Encoding UTF8
}

try {
    Write-Log -Message "資格情報の取得処理を開始します。Target: $targetName" -Path $logPath

    # 資格情報の取得（存在しなければ JSON から初期登録して JSON 削除）
    $cred = Get-OrSetCredentialFromJson -TargetName $targetName -JsonPath $jsonPath

    # 取得結果をログに出力
    Write-Log -Message "資格情報の取得に成功しました。" -Path $logPath
    Write-Log -Message "TargetName : $($cred.TargetName)" -Path $logPath
    Write-Log -Message "UserName   : $($cred.UserId)" -Path $logPath
    Write-Log -Message "Password   : $($cred.Password)" -Path $logPath

    # --------------------------------------------------
    # ここに後続の業務処理（$cred.UserId, $cred.Password を使用）を記述
    # --------------------------------------------------

    Write-Log -Message "すべての処理が正常終了しました。" -Path $logPath
}
catch {
    Write-Log -Message "[ERROR] 処理中にエラーが発生しました: $_" -Path $logPath
    exit 1
}