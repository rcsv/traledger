# Place Card spike

Date: 2026-07-21

Status: Limited adoption recommended

## Question

Apple Maps の Place Card を使い、TripMap の Activity 文脈を失わずに Venue の情報量を
増やせるか。

## What Apple provides

- `MKMapItem` は名称、住所、座標、電話、URL、カテゴリ、タイムゾーン、Place ID などを扱う。
- `MKMapItemDetailViewController` は住所や電話などを含む Apple 管理の Place Card を表示する。
- SwiftUI の `mapItemDetailSelectionAccessory` は、`MKMapItem` を持つ Marker などの
  Map content に Apple の選択アクセサリを付ける。
- `MKMapItemRequest` は保存済み Place ID から新しい `MKMapItem` を取得できる。

Place Card と Place ID の主要 API は iOS 18 / macOS 15 以降。現在の最低 OS は
iOS 17 / macOS 14 のため availability 境界が必須になる。

参考:

- [MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem)
- [Unlock the power of places with MapKit (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10097/)
- [Identifying unique locations with Place IDs](https://developer.apple.com/documentation/mapkit/identifying-unique-locations-with-place-ids)

## Prototype

`PlaceCardSpikeButton` を選択中 Activity の既存 Venue カードへ追加した。

1. iOS 18 / macOS 15 以降だけ「場所の詳細」を表示する。
2. `mapKitIdentifier` があれば `MKMapItemRequest` で最新の Place を取得する。
3. ID がない古いデータやサンプルは、名称、住所、座標を使った `MKLocalSearch` で補う。
4. `MKMapItemDetailViewController` を SwiftUI sheet 内に表示する。
5. 検索できない場合は TripMap の保存済み名称・住所を残し、「Mapsで開く」へ退避する。

macOS と iOS の両ターゲットで、最低 OS を変更せずコンパイルできることを確認した。

## Why not attach it directly to the sequence pin?

TripMap のピンは Day / Activity のシーケンスを示す独自 `Annotation` である。一方、
SwiftUI の Place Card selection accessory は `MKMapItem` に紐づく Map content を前提とする。
独自ピンを `Marker(item:)` へ置き換えると、シーケンス表現を失う。両方を重ねると以前の
「ピンの中にピン」問題が戻る。

そのため、地図上は TripMap のシーケンスピン、詳細は選択 Activity のカードから Apple の
Place Card、という役割分担にした。

## Findings

### Good fit

- Apple の Place 情報を自前モデルへ大量に複製せず、必要なときだけ最新情報を見せられる。
- 電話、Web、営業時間などを Activity 編集 UI へ詰め込まずに済む。
- TripMap の時刻、カテゴリ、所要時間、メモ、Doctor を主役に保てる。
- Place ID を保存できる新規 Venue は、名称検索より安定して再取得できる。

### Limits

- Apple が Place Card に表示する内容やレイアウトはアプリ側で細かく制御できない。
- 評価、レビュー、写真、編集記事などは、公開 `MKMapItem` の通常プロパティとして自由に
  取り出して TripMap 独自 UI に再配置できるわけではない。
- Place Card の情報量は場所と地域によって異なる。
- Place ID がない既存データの名称検索は、同名施設や移転で別の Place を選ぶ可能性がある。
- OS 14 / iOS 17 では純正 Place Card を出せないため、既存の Venue カードが製品として
  成立している必要がある。

## Decision

**限定採用**とする。

- Activity / Venue の独自カードを一次情報として維持する。
- 「場所の詳細」を二次アクションとして提供する。
- Apple Place Card 内の情報を TripMap の保存データとみなさない。
- シーケンスピンは置き換えない。
- 最低 OS はこの機能のためだけには引き上げない。

## Before promotion from spike

- 沖縄サンプルの複数 Venue で、名称検索が正しい場所を選ぶか目視確認する。
- 電話、Web、営業時間がある場所とない場所を比較する。
- 280 pt の Activity カードで三つのアクションが窮屈にならないよう、詳細と Maps を
  Menu または単一の「場所」アクションへまとめる。
- iPhone の sheet 高さ、閉じる操作、Dynamic Type を確認する。
- ID 検索失敗から名称検索へ落ちたことをログまたはデバッグ表示で判別できるようにする。

この目視確認が終わるまでは、コード名どおり Research Gate 0 のスパイクとして扱う。
