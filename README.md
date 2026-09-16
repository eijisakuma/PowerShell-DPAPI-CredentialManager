# PowerShell DPAPI Credential Manager

Windows のタスクスケジューラにて **SYSTEM アカウント（最上位の特権）** で実行し、DB 接続情報（User, Password）を **DPAPI (Data Protection API)** で安全に暗号化・保存・復号するための PowerShell スクリプト一式です。

---

## 特徴

- **SYSTEM アカウント専用 DPAPI 暗号化**:
  Windows 標準の DPAPI（`CurrentUser` スコープ）を利用し、暗号化した SYSTEM アカウントのコンテキストでのみ復号可能（他の一般ユーザーや管理者アカウントがファイルを持ち出しても復号不可）。
- **一時ファイルの自動削除**:
  平文パスワードが書かれた一時定義ファイル（`db_input.json`）は、暗号化完了後に自動で上書き消去（シュレッディング）されて安全に削除されます。
- **冪等性とスキップ処理**:
  定義ファイルが存在しない場合はエラーにならず、安全に処理をスキップしてログを記録します。
- **関数化・モジュール設計**:
  各処理がモジュール・関数化されており、他のバッチ処理や自動化スクリプトから簡単に組み込み可能です。

---

## ファイル構成

| ファイル名 | 役割 |
|---|---|
| `DbCredentials.psm1` | 暗号化 (`Save-DbCredentials`) および復号 (`Get-DbCredentials`) を行う共通モジュール |
| `Execute-SaveCredentials.ps1` | `db_input.json` から暗号化を行い、元ファイルを削除するタスク実行スクリプト（関数: `Invoke-SaveDbCredentialsTask`） |
| `Execute-ReadCredentials.ps1` | 暗号化ファイルを復号し、平文の `User` と `Password` オブジェクトを返すスクリプト（関数: `Get-DecryptedDbCredentials`） |
| `Main-CredentialWorkflow.ps1` | 暗号化から復号・接続文字列生成までの一連の流れを実行するメインスクリプト |
| `db_input.example.json` | ユーザー名・パスワード定義用の一時テンプレートファイル |
| `.gitignore` | 平文ファイル (`db_input.json`) や暗号化ファイル (`db_credentials.xml`)、ログファイルの誤コミットを防止 |

---

## 使い方

### 1. 定義ファイルの準備
`db_input.example.json` をコピーして `db_input.json` を作成し、実際の DB ユーザー名とパスワードを入力します。

```json
{
  "User": "your_db_user",
  "Password": "your_secure_password"
}
```

### 2. タスクスケジューラでの実行（推奨）
管理者権限の PowerShell で以下のコマンドを実行し、タスクスケジューラに登録・実行します。

```powershell
# パラメータ設定
$taskName   = "Db-Credential-Workflow-Task"
$scriptPath = "D:\Dev\PowerShell\Main-CredentialWorkflow.ps1"
$workDir    = "D:\Dev\PowerShell"

# アクション定義
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $workDir

# SYSTEM アカウント・最上位特権の指定
$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# タスク登録と即時実行
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force
Start-ScheduledTask -TaskName $taskName
```

### 3. 他のスクリプトから復号して利用する
業務スクリプトから認証情報を呼び出す場合は、以下のようにドットソースで読み込みます。

```powershell
# 関数スクリプトを読み込み
. "D:\Dev\PowerShell\Execute-ReadCredentials.ps1"

# 復号して平文情報を取得
$cred = Get-DecryptedDbCredentials

$user = $cred.User
$password = $cred.Password

# DB 接続文字列の作成例
$connectionString = "Server=myServer;Database=myDb;User Id=$user;Password=$password;"
```

---

## セキュリティに関する推奨事項

- スクリプトおよび生成された `db_credentials.xml` が配置されるフォルダは、NTFS アクセス権により **SYSTEM** および **Administrators** のみにアクセスを限定することを強く推奨します。
