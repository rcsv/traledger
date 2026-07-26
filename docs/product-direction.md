# Product direction: 旅の時間軸に合わせて UI が育つ

Last updated: 2026-07-27

全プラットフォームの機能配置、技術採否、品質 Gate、実装ロードマップの詳細は
[Apple Platform Product Master Plan](apple-platform-product-master-plan.md) を実装指示の基準とする。

## 一本のコンセプト

TripMap は、同じ旅程データを「計画中」「旅行中」「旅行後」で違う道具へ育てる。

- 計画中は、抜けや無理を発見して計画を整える **Planner**。
- 旅行中は、今と次だけを迷わず確認できる **Guide**。
- 旅行後は、写真と訪問記録から旅を振り返る **Memory**。

機能を増やすときは、この時間軸のどこで価値を出すかを先に決める。三つの別アプリを
作るのではなく、Activity、Venue、写真、移動、警告という同じデータの優先順位と見せ方を
切り替える。

## フェーズごとの UI

| フェーズ | 主役 | 強く表示するもの | 弱くするもの |
| --- | --- | --- | --- |
| 計画中 | Planner | Doctor、所要時間、食事、移動負荷、編集、チェックリスト | 写真中心の演出 |
| 旅行中 | Guide | Today、Now / Next、経路、予約、すばやいメモ | 長期的な集計、低優先度の警告 |
| 旅行後 | Memory | 写真、訪問済み Activity、実際の軌跡、思い出 | 未確定計画の編集、Doctor の催促 |

フェーズは旅行日程と現在時刻から提案し、ユーザーが手動で切り替えられるようにする。
自動判定によって入力内容や旅程を勝手に変更しない。

## 設計原則

1. **旅行者の意図を主役にする。** Apple Maps の Place 情報は文脈を補う資料であり、
   TripMap の Activity、時刻、所要時間、メモを置き換えない。
2. **提案は確認可能にする。** Doctor や将来の生成 AI は、理由と変更前後を示し、適用は
   明示操作にする。可能な限り取り消せるようにする。
3. **狭い画面でも状態を失わせない。** サイドバーは expanded / rail / hidden の三段階を
   目標とし、rail では Overview、Day、警告件数など現在地に必要な情報を残す。
4. **計画では情報、記憶では写真を先にする。** 同じ Trip Card でも計画中は状態を、
   旅行後はカバー写真を主役にする。
5. **取得不能を正常系として扱う。** Place Card、Look Around、経路、営業時間などは地域や
   OS により欠ける。読み込み中、取得済み、利用不可を明確に分け、必ずフォールバックを持つ。

## 現在地

基礎として次を実装済み。

- Activity / Venue の編集
- Activity のカテゴリと所要時間
- Doctor の Overview 集約、Day / Activity の該当箇所表示
- 食事予定、所要時間、MapKit による移動負荷のチェック

Research Gate 0 は限定採用で完了した。地図上のカードは Activity Card の複製ではなく、
画像、Venue 名、カテゴリ、所在地を示す **Venue Card** とする。電話、Web、営業時間などの
詳細はカードへ追加せず、`Mapsで開く` から Apple Maps に委譲する。

現在は **使い勝手の統合フェーズ**。Activity 入力、Travel Leg、日程変更、Reservation の
基礎は実装済みである。次は、実装済み機能を macOS のメニューと Planner から一貫して呼び出せる
ようにし、Activity の挿入、Overview の分析、Reservation 集約、地図からの場所選択を、既存の
Activity / Venue 境界を壊さず一連の操作として完成させる。

## 作業順序

この順序を、別の判断が文書化されるまでのデフォルトとする。

### Research Gate 0 — Place Card スパイク — 完了

Apple Maps の情報を TripMap の文脈に自然に足せるか、小さな試作で判断する。

検証項目:

- iOS 18 / macOS 15 以降の Apple Place Card API を既存の MapKit 選択状態から開けるか。
- 現在の配置先である iOS 17 / macOS 14 に、availability 判定と独自フォールバックを保てるか。
- 保存済み `mapKitIdentifier` から最新の `MKMapItem` を引き直せるか。
- 沖縄サンプルで名称、住所、電話、Web、営業時間などがどこまで表示されるか。
- TripMap の Activity ヘッダーと Apple の Place 詳細を二重表示にせず組み合わせられるか。

完了条件:

- 実機または macOS で一つの Venue を選び、ネイティブ Place Card またはフォールバックを
  表示できる。
- 取得可能な情報、OS 制約、欠落時の挙動を記録する。
- 本採用、限定採用、見送りのいずれかを理由付きで決定する。

非目標:

- Wanderlog と同等のレビュー、写真、推薦文を自前で再現すること。
- Place Card を Activity 編集 UI の代替にすること。
- このスパイクのためだけに最小 OS を引き上げること。

初回の技術検証結果は [Place Card spike](spikes/place-card.md) に記録する。
採用する情報設計、画像方針、外部プロバイダーの境界は
[Venue Card specification](place-card-spec.md) を実装時の基準とする。

結論は限定採用。Apple のネイティブ Place Card は Activity Card と情報が重複するため
製品 UI へ採用しない。TripMap 内には必要最小限の Venue 情報を直接表示し、それ以上の
確認は Apple Maps へ移動する。ユーザー評価や投票数は有用な将来候補だが、MapKit の
公開 API から安定取得できないため、別データプロバイダーの規約、帰属、費用を含めて
独立した Research Gate で判断する。

### 1 — Activity 入力 UX

- カードのダブルクリックとコンテキストメニューから編集へ入れるようにする。
- カテゴリ別の標準所要時間と、よく使う所要時間のクイック選択を検証する。
- Activity 編集と Venue Card の境界が一連の操作で理解できることを確認する。

### 2 — Doctor の情報整理

- Overview は種類と Day でグループ化し、最重要の数件と「すべて表示」を分ける。
- Day / Activity の局所警告から該当編集へ直接移動できるようにする。
- 警告、情報、計算中、取得不能の見た目を分ける。

### 3 — 移動負荷の説明力

- MapKit 計算を「計算中 / 完了 / 利用不可」で表示する。
- Activity 間に「車 25分」のような区間情報を置く。
- その後に徒歩、車、公共交通などの移動手段指定を検討する。

### 4 — 折りたたみサイドバー

- expanded / rail / hidden の三状態を試作する。
- rail に Overview、Day、選択状態、Doctor 件数を残す。
- 代表的なウィンドウ幅で、地図と Activity リストの実効面積を比較する。

### 5 — 選択 Activity オーバーレイ

- 地図上では場所、時刻、カテゴリ、所要時間、前後の移動を短く表示する。
- よく使う編集だけをその場に置き、詳細情報は Place Card または編集画面へ逃がす。
- 計画中と旅行中で、同じオーバーレイの情報優先度を切り替える。

### 6 — フェーズ別 UI の最小縦切り

- Planner / Guide / Memory の手動切替と日付による提案を実装する。
- 一つの Trip で、各フェーズの Overview と Activity Card の優先順位を比較する。
- 旅行後の Trip Card を写真主役にし、タイトル、日付、訪問数を付帯情報として置く。

## 2026-07-25 ユーザビリティ検証の採否

検証意見は、現行仕様との関係を次のように判断する。

| 意見 | 判断 | 製品方針 |
| --- | --- | --- |
| Library のダッシュボード | 機能拡充 | Trip 一覧を置き換えず、旅行履歴を要約する二次領域として追加する。国別集計は country code の永続化後に行う。 |
| macOS メニューバー | 既定方針の未完 | Library、Trip 作成、Activity 作成、Participant、Settings を標準 Command として公開する。 |
| 旅行日程の変更 | 既定仕様・macOS 実装済み | scoped mutation と「予定がある Day は黙って削除しない」境界を維持し、iPhone / iPad からも到達可能にする。 |
| Activity 間の移動手段 | 既定仕様・Guide 実装済み | 車、徒歩、公共交通、その他を Planner からも編集可能にする。 |
| ダブルクリックで追加／挿入 | 一部不採用、代替拡充 | カードのダブルクリックは編集を維持する。先頭、Activity 間、末尾に明示的な挿入 affordance を置く。 |
| 地図の Venue を Activity に追加 | 機能拡充 | Venue 選択から Activity の下書きを作り、Day と挿入位置を確認してから保存する。 |
| 地図クリックで Venue 情報を表示 | 機能拡充 | 保存済み Activity 選択と未保存 Venue 候補を別状態として扱い、地図以外にも同じ操作経路を用意する。 |
| Activity 情報の拡充 | 一部は実装済み、段階的拡充 | 時刻、カテゴリ、所要時間、Venue、Reservation は既存情報を整理する。写真や詳細は Inspector へ段階表示し、費用は Domain 定義後に追加する。 |
| Activity Analysis | 機能拡充 | Trip Overview にカテゴリ件数、割合、未分類を派生集計として表示する。 |
| Activity Weaver の縦線 | デザイン方針追加 | Activity の順序を示す semantic timeline spine を採用し、Travel Leg や挿入操作と視覚的に統合する。 |
| Venue overlay の外部情報 | 課題は採用、解決策は Research Gate | 予定判断に役立つ情報と操作を優先する。Wikipedia 本文、旅行会社、予約 API は規約、帰属、費用、地域差を検証してから採否を決める。 |
| Reservation Summary | 基礎は実装済み、集約を拡充 | confirmation code を一覧へ露出せず、Trip Overview と Library Dashboard に件数・種類・次の予約を表示する。 |

集計やカードの情報量は、計画中、旅行中、旅行後で同じ強さにしない。長期集計は Library と
Planner / Memory の Overview で強くし、Guide では Today、Next、移動、直近の予約を優先する。

2026-07-26 の macOS 実画面確認で、Venue 検索 Sheet に検索欄が二重表示され、Navigation / Toolbar
領域が過大な空白を取る回帰を確認した。検索機能や MapKit resolver の問題ではなく、macOS Sheet に
`NavigationStack`、`HSplitView`、`List.searchable` の自動配置を重ねた presentation 問題である。
Activity / Venue Domain を変更せず、macOS 専用の明示的な header、検索欄、split content、footer
へ組み替える修正を、次の schema 非依存 UI slice とした。

同日の修正で明示レイアウトへ移行し、検索欄一つ、header 直下の左右ペイン、固定 footer、
初期 keyboard focus、Escape cancel を Activity Editor からの nested-sheet UI test と実画面で
確認した。2026-07-27 には MapKit 非依存の多状態 fixture と Planner の`場所から予定を追加`入口も
UI test で確認し、Dark Appearance でも同じ階層とコントラストをシート単体画像で確認した。
constrained window でもシート最小寸法、操作可能な検索欄・候補・Cancel、固定 footer を確認した。
iOS 27 の iPhone / iPad では Guide Quick Edit から共有 Venue 検索を開き、標準幅の縦配置と
modal 配置を実画面確認した。Accessibility XXL で見つかった preview 説明と下部検索バーの重なりは、
検索 modifier の所有範囲、scrollable preview、短い支援案内で修正し、iPhone / iPad の XXL と
Increase Contrast で再確認した。macOS Increase Contrast と VoiceOver の実確認は、Domain 変更を
伴わない検証 follow-up として継続する。

## 将来の生成 AI

Doctor の先に置く AI は「旅程を作り直す機能」ではなく、検出された問題に対する
**修正 fragment の提案**とする。

1. Doctor が根拠付きで問題を検出する。
2. AI が最小の修正案を一つ以上生成する。
3. UI が差分、理由、影響範囲を表示する。
4. ユーザーが選んだ fragment だけを適用する。

この順番なら、AI が利用できない場合も Doctor と手動編集だけで製品価値が残る。

## 運用

- 新しい大機能を始める前に、この文書のコンセプトと作業順序に照らす。
- 順序を変える場合は、変更理由と新しい完了条件を先にこの文書へ反映する。
- スパイクの結果は `docs/` に残し、成功したコードだけを製品 UI へ昇格させる。
