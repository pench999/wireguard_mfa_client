# WireGuard MFA Client

`wireguard_webadmin_ja`の接続前MFAと、WireGuard for Windowsのトンネル操作を一つにまとめるFlutterクライアントです。

## MVPの対象

- Windows 11
- WebView2を利用したアプリ内の既存TOTP画面
- WebView2が利用できない場合のシステムブラウザへのフォールバック
- 事前にインストールされたWireGuardトンネルサービスの開始・停止
- MFAセッション状態と接続許可期限の表示

WebとAndroidはビルド可能な構成を維持しますが、VPNサービス制御は初回版ではWindowsのみ対応します。

## 前提

サーバーには`wireguard_webadmin_ja`の`codex/windows-client-api`ブランチに含まれるクライアントセッションAPIが必要です。サーバー側でマイグレーションを実行してください。

Windowsには公式のWireGuard for Windowsをインストールし、対象設定をトンネルサービスとして登録します。管理者権限の端末で実行します。

```powershell
& "$env:ProgramFiles\WireGuard\wireguard.exe" /installtunnelservice "C:\path\to\office-wg.conf"
```

この例のサービス名は`WireGuardTunnel$office-wg`です。通常ユーザーで本アプリを動かす場合、そのサービスだけを開始・停止できるようWindowsサービスACLを管理者が設定する必要があります。アプリを常時管理者権限で起動する構成は推奨しません。

## 開発環境

```powershell
$flutter = 'C:\Users\kudo\Documents\Codex\tools\flutter\bin\flutter.bat'
& $flutter pub get
& $flutter analyze
& $flutter test
& $flutter run -d windows
```

Windowsでプラグインを使用するため、WindowsのDeveloper Modeを有効にしてください。

## 設定

アプリ右上の設定から次を入力します。

- サーバーURL: `https://vpn.example.com`
- peer UUID: WebAdminで利用者に割り当てたpeerのUUID
- トンネル名: `.conf`のファイル名から拡張子を除いた名前

サーバーURL、peer UUID、トンネル名だけを端末に保存します。WebAdminのパスワード、TOTPシークレット、管理APIキーは保存しません。接続セッションのpoll tokenはメモリ上だけに保持します。

## 接続フロー

1. アプリが5分間有効なクライアントセッションを作成します。
2. アプリ内のWebView2でWebAdminの既存ログイン・MFA画面を開きます。
   WebView2が利用できない場合や利用者が選択した場合は、既定ブラウザで続行します。
3. MFA成功後、アプリがサーバー状態を確認します。
4. peerの有効化を確認してから`WireGuardTunnel$<name>`を開始します。
5. 切断時はローカルサービスを停止し、サーバーへ即時ロックを要求します。

## 既知の制約

- WireGuardトンネルサービスの作成とACL設定はインストーラーへ未統合です。
- Windows以外では接続操作を実行できません。
- サーバーAPIをインターネットへ公開する場合、HTTPSとリバースプロキシ側のレート制限が必要です。
- 実際のMFAサーバーとWireGuardサービスを使うEnd-to-Endテストは別途必要です。
