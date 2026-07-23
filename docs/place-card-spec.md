# Venue Card specification

Date: 2026-07-24

Status: Product direction adopted and implemented; macOS three-source UI verification passed, cross-device Gate pending

Related documents:

- [Product direction](product-direction.md)
- [Apple Platform Product Master Plan](apple-platform-product-master-plan.md)
- [Place Card technical spike](spikes/place-card.md)

Research Gate 0 の製品判断は限定採用で完了している。一方、画像実装の最終 Gate は別に管理する。
2026-07-24 に実サービスを使う smoke test で Look Around 成功と Wikimedia fallback を確認し、
ユーザー画像優先と非同期ライフサイクルは決定的テストで確認した。さらに macOS の専用 QA scheme で、
Venue Card 上の Look Around、Wikimedia fallback、PhotosPicker ユーザー画像の三経路を実画面確認した。
最終 Gate は、regular / narrow、明示的な VoiceOver 操作、iPhone 実画面の確認まで未完了とする。

## 2026-07-24 verification evidence

| Check | Result | Evidence |
| --- | --- | --- |
| ユーザー画像がある場合に自動取得しない | Pass | 注入した Look Around / Wikimedia resolver の呼び出しがともに0回になるモデルテスト |
| Look Around を Wikimedia より優先する | Pass | 渋谷スクランブル交差点で実 MapKit scene を取得し、Wikimedia 呼び出し0回を確認 |
| Look Around 取得不能時の Wikimedia fallback | Pass | 那覇空港で Look Around が `nil`、Commons exact-venue image の取得・保存コールバックを確認 |
| 同一 request の再実行防止 | Pass | 同一 Venue の連続 `load` で各 resolver が1回だけ呼ばれるモデルテスト |
| Venue 変更後の古い結果を棄却 | Pass | 遅延した旧 Wikimedia 結果が表示・保存されないモデルテスト |
| 通常 macOS regression | Pass | `TripMap-macOS` の60テストが成功 |
| 通常 iOS Simulator build | Pass | arm64 / x86_64 の generic Simulator build が成功 |
| QA fixture の Library 表示 | Pass | `TRIPMAP_QA` 専用ビルドで `Venue Image QA` Trip を実画面確認 |
| macOS UI automation mode | Pass | 残留 TripMap / `testmanagerd` を終了し、全 Simulator を shutdown して再生成した後、専用 QA scheme が test method まで到達 |
| 渋谷 Look Around の Venue Card | Pass | `venue-image` が「渋谷スクランブル交差点 周辺の Look Around 画像」として表示 |
| 那覇 Wikimedia fallback の Venue Card | Pass | `venue-image` が「那覇空港 の Wikimedia Commons 画像」として表示され、作者・license の帰属リンクも存在 |
| PhotosPicker ユーザー画像 | Pass | native PhotosPicker で既存ライブラリ画像を選択し、「沖縄美ら海水族館 の選択された画像」へ更新 |
| ユーザー画像の再起動後優先 | Pass | seed なしでアプリを再起動しても選択画像が復元され、外部画像へ戻らないことを確認 |
| macOS regular / narrow と明示的 VoiceOver 操作 | Pending | 三経路の source label と帰属リンクは Accessibility tree で確認済み。幅別レイアウトと VoiceOver 読み上げ順は未確認 |
| iPhone / iPad の再実画面確認 | Pending | CoreSimulator は復旧し generic iOS Simulator build は成功。iPhone の同一実画面 matrix は未実行、iPad は target 追加後に実施 |

live smoke test は通常テストへ外部通信依存を持ち込まないよう、
`OTHER_SWIFT_FLAGS='$(inherited) -D TRIPMAP_LIVE_VENUE_IMAGE_QA'` を指定した場合だけ
コンパイルされる。画面用 fixture も `TRIPMAP_QA` の場合だけ製品へ含まれ、通常ビルドには含めない。

最終視覚確認用に `TripMapUITests` target と `TripMap-VenueImage-QA` scheme を用意した。
UI automation 基盤が利用可能な環境では次を実行する。

```sh
xcodebuild -project TripMap.xcodeproj \
  -scheme TripMap-VenueImage-QA \
  -destination 'platform=macOS' \
  OTHER_SWIFT_FLAGS='$(inherited) -D TRIPMAP_QA' \
  test
```

この UI test は QA Trip を直接開き、渋谷の Look Around 画像ラベル、那覇の Wikimedia 画像ラベル、
作者・license の帰属リンクを実アプリの Accessibility tree で確認する。さらに native PhotosPicker
から既存ライブラリ画像を選び、ユーザー画像への更新と seed なしの再起動後の永続化を確認する。
PhotosPicker の実操作には、QA 実行環境の写真ライブラリに選択可能な画像が1枚以上必要である。通常
`TripMap-macOS` scheme では UI test を skip し、60件の deterministic test だけを実行する。
2026-07-24 は残留プロセスと Simulator 状態をリセットして automation mode を復旧し、専用 scheme の
3 test が failure 0 で成功した。最終再実行の結果 bundle は
`DerivedData-VenueImageUITest/Logs/Test/Test-TripMap-VenueImage-QA-2026.07.24_08-02-15-+0900.xcresult`。

Look Around の可用性は地点単位で変化する。今回の probe では東京駅と東京タワーは取得不能、
渋谷スクランブル交差点は取得可能だったため、QA fixture は渋谷を採用した。地名の知名度だけで
成功 fixture を固定せず、Gate 実行時に実サービス結果を再確認する。

## Purpose

地図上の Venue Card は、選択中 Activity の情報を繰り返すカードではなく、Activity に登録された
**Venue を理解し、次の操作へ進むためのカード**とする。初期調査では Place Card と呼んでいたが、
Apple のネイティブ Place Card と区別するため、製品 UI と現行仕様では Venue Card と呼ぶ。

Activity のタイトル、カテゴリ、所要時間、メモ、Doctor 警告は左側の Activity 一覧と編集画面を
一次表示とする。地図上では Venue の写真、名称、種類、所在地を優先し、Activity の文脈は
シーケンス番号と時刻だけを短く残す。

## Information hierarchy

### Primary: Venue

- Venue のプライマリ画像
- Venue 名
- Apple Maps から解決できた POI カテゴリ
- 住所または市区町村・地域名

### Secondary: Activity context

- Day 内のシーケンス番号
- 開始時刻（設定されている場合）

Activity タイトル、所要時間、メモ、警告は原則として重複表示しない。Venue 名と Activity
タイトルが異なる場合も、このカードでは Venue 名を主見出しにする。

## Layout

### Regular width

- カード外形は地図ペインの利用可能幅いっぱいに広げ、左右に現在の安全余白を保つ。
- 画像はカード全面へ広げない。
- 画像は左側に固定した 16:9 とし、目安を `176 × 99 pt` から `192 × 108 pt` とする。
- Venue 情報を画像の右側へ置く。
- 画像幅はカード幅の 40% を超えない。

### Compact width

- 画像は `88 × 88 pt` 程度の 1:1 サムネイルへ切り替える。
- Venue 情報は画像の右側に維持し、画像をフルブリード表示しない。
- アクションが一行に収まらない場合は二行または Menu へ適応させる。文字を意味不明な長さまで
  省略して一行へ押し込まない。

### Actions

通常幅では次のラベルを省略せず表示する。

1. `画像を選択` または `画像を変更`
2. `Mapsで開く`

Venue の詳細はカード内のカテゴリ・所在地でまず伝える。純正 Apple Maps の詳細は `Mapsで開く` の
遷移先で確認するため、独立した `場所の詳細` アクションは置かない。

`Mapsで開く` は座標だけの独自ピンではなく、Place ID または名称・座標検索で解決した
`MKMapItem` を Apple Maps で開く。

### Deliberately delegated information

電話番号、Webサイト、営業時間、レビュー本文は Venue Card に表示しない。これらは計画の
時間軸より施設ディレクトリとしての性格が強く、カードの情報密度を上げるため、Apple Maps や
旅行情報サービスで確認する。

評価、投票数、人気度は旅行者の判断材料として価値があるため、将来候補として明示的に残す。
ただし公開 `MKMapItem` API からアプリ独自 UI 用に安定取得できる情報ではない。導入する場合は、
別プロバイダーのデータ品質、対象地域、帰属表示、利用規約、キャッシュ条件、費用を比較する
独立した Research Gate を先に行う。現段階でカードの空き領域を推測値や無出典データで埋めない。

## Primary image policy

画像は次の優先順位で一枚だけ表示する。

1. ユーザーが選択した画像
2. Apple Look Around の周辺画像
3. Wikimedia Commons で Venue と一致した画像
4. 現在のプレースホルダー

上位の画像が利用可能になっても、ユーザーが選択した画像を自動で置き換えない。

### Exact Venue image

Venue 名、座標、Wikidata ID などから対象施設と同一と判断できる画像を指す。Wikimedia
Commons を最初の候補とし、座標だけで近隣画像を取得した場合は名称または関連エンティティで
追加照合する。

## Apple Place Card boundary

Apple の純正 Place Card に表示される写真は、公開 `MKMapItem` API の画像プロパティとして
取得できない。`MKMapItemDetailViewController` のビュー階層は非公開で、変更もサポートされない。

したがって、次を禁止する。

- 純正 Place Card のビュー階層から画像を取り出すこと
- Place Card のスクリーンショットや非公開 API を使って写真を再利用すること
- Apple Maps の写真を TripMap の保存画像として扱うこと

純正 Place Card は製品 UI に組み込まない。詳細確認は、解決済み `MKMapItem` を使う
`Mapsで開く` に一本化する。

参考:

- [MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem)
- [MKMapItemDetailViewController](https://developer.apple.com/documentation/mapkit/mkmapitemdetailviewcontroller)
- [MKLookAroundSnapshotter](https://developer.apple.com/documentation/mapkit/mklookaroundsnapshotter)

## External image providers

### Wikimedia Commons — first exact-image provider

- 初回実装では日本語 Wikipedia の記事タイトルが Venue 名と完全一致する場合だけ、記事の page image を
  Commons ファイルへ解決する。近隣検索や曖昧な候補の自動採用は行わない。
- 無料利用を前提にできるが、ファイルごとのライセンス、作者、帰属表示を必ず保持する。
- 構造化データの取得結果だけでなく、実際の画像ライセンスを確認してから表示する。

参照: [MediaWiki Imageinfo](https://www.mediawiki.org/wiki/API%3AImageinfo)

### Providers not selected for the first implementation

- **Pexels:** 地域イメージのためだけに API キー保護用のプロキシと運用を追加する必要があり、
  Venue そのものの画像である保証もないため採用しない。既存バックエンドを持つ場合だけ再検討する。
- **Unsplash:** 画像品質は高いが、ホットリンク、ダウンロード通知、帰属表示、Production 審査の
  条件が増えるため、最初のプロバイダーにはしない。
- **Google Places Photo:** 施設写真の精度は期待できるが、従量課金と Google Maps 表示・帰属の
  条件が Apple Maps 中心の画面と衝突する可能性があるため採用しない。
- **Mapillary:** 座標検索には向くが、旅行写真ではなく道路・外観中心のため Look Around の
  代替候補としてのみ保留する。
- **Flickr:** 座標・ライセンス検索は可能だが、初期プロバイダーを増やさないため保留する。

参考:

- [Unsplash API guidelines](https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines)
- [Google Places policies](https://developers.google.com/maps/documentation/places/web-service/policies)
- [Google Maps Platform pricing](https://developers.google.com/maps/billing-and-pricing/pricing)

## Image attribution and persistence

外部画像では最低限、次のメタデータを画像と一緒に扱う。

- provider
- provider image ID
- image URL または取得に必要な参照
- source page URL
- photographer / author name
- photographer / author URL
- license identifier と license URL（提供される場合）
- exact Venue image / regional image の区分
- 取得日時

表示要件とキャッシュ可能期間は provider ごとに異なるため、一律に画像バイナリを永続保存しない。
ユーザーが自分で選択した画像と、外部サービスから一時表示する画像はデータモデル上も区別する。

帰属情報が欠落した画像は表示しない。プロバイダーから削除された画像は通常の取得不能として扱い、
次のフォールバックへ進む。

## Loading and failure states

- Venue のテキストとアクションは画像取得を待たずに表示する。
- 画像部分だけをプレースホルダーから更新する。
- 取得要求は選択 Activity が変わったらキャンセルする。
- 待機表示には上限を設け、無期限の ProgressView を残さない。
- ネットワーク障害、検索結果なし、利用規約上表示不可を通常のフォールバックとして扱う。

## Accessibility

- 画像には Venue 名と画像区分を含む説明を付ける。
- Look Around は周辺画像、Wikimedia は Venue の外部画像であることを VoiceOver でも区別する。
- 帰属情報と画像提供元へのリンクはキーボードで到達可能にする。
- ボタンのアクセシブル名称は画面上の完全なラベルと一致させる。
- Dynamic Type または文字拡大時は、画像を縮めるより情報列とアクションを折り返す。

## Privacy and security

- 外部画像検索へ送るのは Venue の名称、保存済み座標、地域、カテゴリに限定する。
- ユーザーの現在地、参加者、Activity メモ、旅行タイトルは送信しない。
- API キーやシークレットをリポジトリ、アプリバイナリ、ログへ保存しない。
- プロバイダー問い合わせ失敗時のログに完全なユーザーデータを残さない。

## Implementation order

この順序で進め、各段階で目視確認してから次へ進む。

### Phase 1 — Venue-first layout — implemented

- 現在のユーザー画像とプレースホルダーだけを使い、通信なしで新レイアウトを実装する。
- Regular は 16:9、Compact は 1:1 のサムネイルを使う。
- Activity 情報をシーケンス番号と時刻まで減らす。
- `画像を選択 / 変更` と `Mapsで開く` のラベルとキーボード操作を確認する。

### Phase 2 — Image source model — implemented

- ユーザー画像と外部画像を区別する画像ソース型を追加する。
- 帰属、ライセンス、exact / regional、取得日時を保持する。
- 表示側で画像ソースの優先順位と帰属表示を制御する。

### Phase 3 — Look Around automatic image — implemented

- ユーザー画像がない場合、最初に Look Around を問い合わせる。
- Look Around 対応地域では周辺外観として表示し、外部画像より優先する。
- Look Around が利用できない場合だけ Wikimedia へフォールバックする。

### Phase 4 — Wikimedia exact-venue fallback — implemented

- Wikipedia 記事タイトルの完全一致から page image を解決する。
- Commons の URL・作者・ライセンス・出典がそろう場合だけ表示し、メタデータは保存する。
- 曖昧な候補、近隣写真、帰属不明の画像は取得不能としてプレースホルダーへフォールバックする。

### Phase 5 — Regional-image provider — not selected

- Pexels は採用せず、画像のためだけのプロキシサービスを追加しない。
- 将来、別用途ですでにバックエンドを運用している場合に限り Research Gate を開き直す。

## Acceptance criteria

- 地図カードは地図ペイン幅を使うが、画像は全面へ広がらない。
- Regular 幅では 16:9、Compact 幅では 1:1 の画像領域になる。
- Venue 名、カテゴリ、所在地が Activity の詳細より強く表示される。
- Activity 情報はシーケンス番号と時刻だけで文脈を維持する。
- `画像を選択 / 画像を変更` と `Mapsで開く` の意味が省略されない。
- ユーザー画像は自動取得画像より常に優先される。
- Look Around と Exact Venue image を画面とアクセシビリティの両方で区別できる。
- すべての外部画像で必要な帰属情報へ到達できる。
- 画像取得に失敗しても Venue 情報と `Mapsで開く` は利用できる。
- Apple Place Card の写真取得、非公開 API、スクレイピングを使用しない。
- 最初の製品実装に Google Places Photo を含めない。

## Non-goals

- Apple Place Card や旅行情報サービスのレビュー・写真ギャラリーを複製すること
- 外部画像をユーザー所有の写真として保存すること
- 自動検索だけで全 Venue に正確な写真を保証すること
- 画像取得のために最小 OS を引き上げること
- この仕様段階で外部 API キーやバックエンドを導入すること

## Viewport review

2026-07-22 に現行の二段階レイアウトを確認した。

| Viewport | Layout | Result |
| --- | --- | --- |
| macOS、カード本文幅 400 pt 以上 | 16:9、`176 × 99 pt` の画像 | 2026-07-21の実画面レビューでVenue情報と二つのアクションを横方向に維持することを確認 |
| macOS、カード本文幅 400 pt 未満 | `88 × 88 pt` の画像 | `ViewThatFits` がCompact表示へ切り替わることをレイアウト条件で確認 |
| iPhone 17 Pro、標準文字サイズ | Compact | iOS 27 Simulatorで沖縄サンプルを直接表示して確認。Venue名、住所、順番、時刻、`Mapsで開く` が省略されない |
| iPhone 17 Pro、Accessibility XXL | Compact | 住所が二行へ折り返され、カードが縦へ拡張する。`Mapsで開く` は完全表示を維持する |

iOSターゲットは現在iPhoneのみであり、iPadはサポート対象に含めない。iPhone上では画像編集を
許可していないためアクションは `Mapsで開く` の一つ、macOS Plannerでは画像変更を加えた二つになる。

ネイティブ Place Card の sheet 高さ、閉じる操作、Dynamic Type は、該当 UI を採用しない決定により
Research Gate の完了条件から除外した。Venue Card は電話、Web、営業時間と `場所の詳細` ボタンを
持たず、二つのアクションだけなので、初期スパイクで発生した三ボタンの省略問題は再発しない。
