# Place Card specification

Date: 2026-07-21

Status: Approved for the next implementation phase; external-image implementation has not started

Related documents:

- [Product direction](product-direction.md)
- [Place Card technical spike](spikes/place-card.md)

## Purpose

地図上の Place Card は、選択中 Activity の情報を繰り返すカードではなく、Activity に登録された
**Venue を理解し、次の操作へ進むためのカード**とする。

Activity のタイトル、カテゴリ、所要時間、メモ、Doctor 警告は左側の Activity 一覧と編集画面を
一次表示とする。地図上では Venue の写真、名称、種類、所在地を優先し、Activity の文脈は
シーケンス番号と時刻だけを短く残す。

## Information hierarchy

### Primary: Venue

- Venue のプライマリ画像
- Venue 名
- Apple Maps から解決できた POI カテゴリ
- 住所または市区町村・地域名
- 画像が地域イメージの場合、そのことを示すラベル

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

`場所の詳細` は Apple の純正 Place Card を開く。`Mapsで開く` は座標だけの独自ピンではなく、
Place ID または名称・座標検索で解決した `MKMapItem` を Apple Maps で開く。

## Primary image policy

画像は次の優先順位で一枚だけ表示する。

1. ユーザーが選択した画像
2. Wikimedia Commons で Venue と一致した画像
3. Pexels で取得した地域イメージ
4. Apple Look Around のスナップショット
5. Apple Maps の地図スナップショットまたは現在のプレースホルダー

上位の画像が利用可能になっても、ユーザーが選択した画像を自動で置き換えない。

### Exact Venue image

Venue 名、座標、Wikidata ID などから対象施設と同一と判断できる画像を指す。Wikimedia
Commons を最初の候補とし、座標だけで近隣画像を取得した場合は名称または関連エンティティで
追加照合する。

### Regional image

Pexels などで市区町村、地域、国、Venue カテゴリを組み合わせて取得した雰囲気画像を指す。
施設そのものの写真とはみなさない。

- `沖縄・本部町のイメージ` のようなラベルを常時表示する。
- Venue の正確な外観や内部であると誤認させる説明を付けない。
- 検索語は保存済み Venue 情報から作り、ユーザーの現在地は送信しない。

## Apple Place Card boundary

Apple の純正 Place Card に表示される写真は、公開 `MKMapItem` API の画像プロパティとして
取得できない。`MKMapItemDetailViewController` のビュー階層は非公開で、変更もサポートされない。

したがって、次を禁止する。

- 純正 Place Card のビュー階層から画像を取り出すこと
- Place Card のスクリーンショットや非公開 API を使って写真を再利用すること
- Apple Maps の写真を TripMap の保存画像として扱うこと

純正 Place Card は最新の詳細情報を見る二次画面としてのみ利用する。

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

### Pexels — first regional-image provider

- Exact Venue image ではなく、地域イメージのフォールバックとして使う。
- 提供元と写真家へのリンクを画像付近または画像詳細から確認できるようにする。
- API キーをアプリバイナリへ直接埋め込まない。製品化時は小さなプロキシサービスを使う。
- 無料枠、レート制限、利用規約を実装開始時とリリース前に再確認する。

参考: [Pexels API](https://www.pexels.com/api/documentation/)

### Providers not selected for the first implementation

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
- 地域画像を Exact Venue image に昇格させない。

## Accessibility

- 画像には Venue 名と画像区分を含む説明を付ける。
- 地域画像は VoiceOver でも `本部町の地域イメージ` と分かるようにする。
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

### Phase 1 — Venue-first layout

- 現在のユーザー画像とプレースホルダーだけを使い、通信なしで新レイアウトを実装する。
- Regular は 16:9、Compact は 1:1 のサムネイルを使う。
- Activity 情報をシーケンス番号と時刻まで減らす。
- 三つのアクションラベルとキーボード操作を確認する。

### Phase 2 — Image source model

- ユーザー画像と外部画像を区別する画像ソース型を追加する。
- 帰属、ライセンス、exact / regional、取得日時を保持する。
- プロバイダーに依存しない resolver interface とフォールバック順を実装する。

### Phase 3 — Wikimedia exact-venue resolver — implemented

- Wikipedia 記事タイトルの完全一致から page image を解決する。
- Commons の URL・作者・ライセンス・出典がそろう場合だけ表示し、メタデータは保存する。
- 曖昧な候補、近隣写真、帰属不明の画像は取得不能として Look Around 以降へフォールバックする。

### Phase 4 — Pexels regional-image spike

- Wikimedia で取得できない Venue に限定して地域画像を検索する。
- `地域イメージ` 表示、提供元リンク、レート制限を確認する。
- 製品化には API キーを保護するプロキシを必須とする。

### Phase 5 — Look Around fallback

- Look Around 対応地域だけ 16:9 スナップショットを生成する。
- 施設写真ではなく周辺外観として表示する。
- 画像なし、通信なし、Look Around なしの最終フォールバックを確認する。

## Acceptance criteria

- 地図カードは地図ペイン幅を使うが、画像は全面へ広がらない。
- Regular 幅では 16:9、Compact 幅では 1:1 の画像領域になる。
- Venue 名、カテゴリ、所在地が Activity の詳細より強く表示される。
- Activity 情報はシーケンス番号と時刻だけで文脈を維持する。
- `画像を選択 / 画像を変更` と `Mapsで開く` の意味が省略されない。
- ユーザー画像は自動取得画像より常に優先される。
- Exact Venue image と地域イメージを画面とアクセシビリティの両方で区別できる。
- すべての外部画像で必要な帰属情報へ到達できる。
- 画像取得に失敗しても Venue 情報、Place Card、Maps は利用できる。
- Apple Place Card の写真取得、非公開 API、スクレイピングを使用しない。
- 最初の製品実装に Google Places Photo を含めない。

## Non-goals

- Apple Place Card や Wanderlog のレビュー・写真ギャラリーを複製すること
- 外部画像をユーザー所有の写真として保存すること
- 自動検索だけで全 Venue に正確な写真を保証すること
- 画像取得のために最小 OS を引き上げること
- この仕様段階で外部 API キーやバックエンドを導入すること
