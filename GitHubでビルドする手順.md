# GitHubでAPKをビルドする手順

## 必要なもの
- GitHubアカウント（あるとのこと）
- Git（インストールが必要）

---

## ステップ1: Gitをインストール

https://git-scm.com/download/win からダウンロードしてインストール
（設定は全部デフォルトでOK）

---

## ステップ2: GitHubでリポジトリ（保管場所）を作る

1. https://github.com にログイン
2. 右上の「+」→「New repository」
3. Repository name: `ferrari-obd`
4. Public のまま
5. 「Create repository」をクリック

---

## ステップ3: コードをGitHubにアップロード

スタートメニューで「Git Bash」を開いて以下を実行:

```
cd C:/Users/syume/ferrari_obd
git init
git add .
git commit -m "最初のアップロード"
git branch -M main
git remote add origin https://github.com/あなたのユーザー名/ferrari-obd.git
git push -u origin main
```

※「あなたのユーザー名」は自分のGitHubユーザー名に置き換える

---

## ステップ4: ビルドを待つ

1. GitHubのリポジトリページを開く
2. 「Actions」タブをクリック
3. 「Build APK」が実行中になる（5〜10分待つ）
4. 完了したら「ferrari-sound-apk」というファイルがダウンロードできる

---

## ステップ5: スマホにインストール

1. ダウンロードしたZIPを解凍するとAPKが出てくる
2. アローズアルファに転送（メールでもUSBでもOK）
3. スマホで「提供元不明のアプリ」を許可してインストール

---

## 本物のフェラーリ音に差し替える方法

今の状態はテスト用のピー音が鳴ります。

本物の音に変えるには:
1. freesound.org でフェラーリエンジン音を検索してMP3でダウンロード
2. `assets/sounds/` の4ファイルと差し替え（ファイル名はそのまま）
3. 再度 `git add . && git commit -m "音声更新" && git push`
4. 自動でAPKが再ビルドされる
