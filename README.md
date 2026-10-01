# WireGuard MFA Client

`wireguard_webadmin_ja`の接続前MFAと、WireGuard for Windowsのトンネル操作を一つにまとめるFlutterクライアントです。

## MVPの対象

- Windows 11
- WebView2を利用したアプリ内の既存TOTP画面
- WebView2が利用できない場合のシステムブラウザへのフォールバック
- 初回認証後のWireGuard設定取得とトンネルサービス登録
- MFAセッション状態と接続許可期限の表示
- 1ユーザー1台のMFA Client登録、失効、再登録許可
- MFA Client必須peerの通常ブラウザ経由アンロック禁止
- 接続中のタスクトレイ常駐と、トレイからの表示・切断・終了
- スリープ時の自動切断と、復帰後のMFA再認証
- 接続状態を色で識別できる独自の「認証ゲート」アイコン

WebとAndroidはビルド可能な構成を維持しますが、VPNサービス制御は初回版ではWindowsのみ対応します。

## セキュリティ境界

- 接続設定と秘密鍵はWebAdminで管理し、初回認証後に一度だけクライアントへ配布します。
- 利用者が`.conf`を選択・ダウンロードする操作はありません。
- Windowsのローカル管理者は信頼対象とし、設定解析やサービスの直接操作は脅威モデルに含めません。
- MFA Client登録はクライアントトークンの識別であり、TPMなどによる端末真正性の証明ではありません。
- ローカル管理者による設定の複製防止、peer自動発行、端末内WireGuard鍵生成、MDM連携、複数端末承認は対象外です。
- MFA Client必須peerは端末認証済みクライアントセッションからのみ利用者が有効化できます。管理者の緊急バイパスは維持します。

## 前提

サーバーには`wireguard_webadmin_ja`のクライアントセッションAPIが必要です。サーバー側でマイグレーションを実行してください。

Windowsインストーラーは、Microsoft Visual C++ Runtimeと、未導入の場合に同梱した公式WireGuard for Windowsをサイレントインストールします。トンネル登録は初回起動時の認証後に行うため、インストール時のconf指定や利用者指定はありません。

HTTPS API通信はOSの信頼済み証明書に加え、Let’s Encrypt公式のISRG Root X1/X2を信頼アンカーとして同梱します。証明書検証の無効化は行いません。

## 開発環境

```powershell
$flutter = 'C:\Users\kudo\Documents\Codex\tools\flutter\bin\flutter.bat'
& $flutter pub get
& $flutter analyze
& $flutter test
& $flutter run -d windows
```

Windowsでプラグインを使用するため、WindowsのDeveloper Modeを有効にしてください。

## 初回設定

1. アプリへサーバーURLを入力します。
2. WebView2または既定ブラウザでWebAdminへログインし、割り当て済みpeerを選択してTOTP認証します。
3. アプリが一回限りの接続設定を取得し、管理者権限の確認後にトンネルサービスを登録します。
4. 設定は`C:\ProgramData\WireGuard MFA Client\Configurations`へ保存し、SYSTEMとAdministratorsだけにアクセスを制限します。

端末にはサーバーURL、peer UUID、トンネル名と、Windows資格情報保護された端末トークンを保存します。WebAdminのパスワードとTOTPシークレットは保存しません。

## 接続フロー

1. アプリが5分間有効なクライアントセッションを作成します。
2. アプリ内のWebView2でWebAdminの既存ログイン・MFA画面を開きます。
   WebView2が利用できない場合や利用者が選択した場合は、既定ブラウザで続行します。
3. MFA成功後、アプリがサーバー状態を確認します。
4. peerの有効化を確認してから`WireGuardTunnel$<name>`を開始します。
5. 切断時はローカルサービスを停止し、サーバーへ即時ロックを要求します。

接続中にウィンドウを閉じてもアプリは終了せず、タスクトレイへ格納されます。トレイの
メニューからウィンドウ表示、切断、アプリ終了を操作できます。「終了」はWireGuardを
停止し、サーバーへ即時ロックを要求してからアプリを閉じます。

Windowsがスリープへ移行すると、アプリはローカルのWireGuardトンネルを停止してから
サーバーへ即時ロックを要求します。復帰時にもトンネルが停止していることを確認し、
次回接続では新しいMFA認証を要求します。スリープ直前にネットワークが切断された場合は、
サーバー側のセッション有効期限が最終的なロック手段になります。

タスクトレイの認証ゲートアイコンは、未接続をグレー、MFA認証中を黄、接続中を緑、
エラーを赤で表示します。アイコンを再生成する場合は`python tool/generate_icons.py`を実行します。

## 既知の制約

- Windows以外では接続操作を実行できません。
- サーバーAPIをインターネットへ公開する場合、HTTPSとリバースプロキシ側のレート制限が必要です。
- 実際のMFAサーバーとWireGuardサービスを使うEnd-to-Endテストは別途必要です。

## Windowsインストーラー

FlutterとNSIS 3を`PATH`から実行できる開発端末で、次を実行します。

```powershell
.\tool\build_installer.ps1
```

`installer\prerequisites\README.md`に記載された公式WireGuard MSIを配置してから実行してください。
ビルド時にMSIのSHA-256とAuthenticode署名を検証します。静的解析とテストを実行して
Windowsリリース版をビルドした後、`dist\installer\WireGuardMfaClient-<version>-windows-x64-setup.exe`を生成します。

セットアップは管理者権限で動作します。WireGuard for Windowsが未導入の場合は、固定・検証済みの
公式WireGuard 1.1.1 MSIをサイレントインストールし、GUIを起動しません。導入済みの場合は既存版を使用します。
初回起動時の認証後にトンネルサービスを登録し、現在のWindows利用者へそのサービスの
照会・開始・停止権限を付与します。トンネルサービスは手動起動に設定され、Windows起動時に
MFAを経ず自動接続されることを防ぎます。アンインストール時は、本アプリが作成した`wgmfa_`
トンネルサービスと保護設定を削除します。WireGuard for Windows本体は削除しません。

初回版のインストーラーは未署名です。組織外へ配布する前にコード署名を追加してください。
NSIS本体は商用利用を許可するzlib/libpngライセンスで提供されています。
