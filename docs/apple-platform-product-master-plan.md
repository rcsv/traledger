# TripMap Apple Platform Product Master Plan

Date: 2026-07-24

Status: Active implementation directive

Applies to: macOS, iOS, iPadOS

## 1. この文書の役割

この文書は、TripMap を Apple プラットフォーム上で完成度の高い旅行アプリへ育てるための
製品仕様、情報設計、機能配置、技術方針、検証方法、実装順序を一つにまとめたマスター指示書である。

実装担当者は、個別機能の都合から画面やデータ構造を決めてはならない。まず本書で、その機能が
旅行のどのフェーズに属し、どのプラットフォームで、どの情報階層として提示されるべきかを確認する。

文書間で判断が異なる場合は、次の優先順位を適用する。

1. データ破損、安全性、プライバシーに関する ADR
2. 本マスター指示書
3. `docs/product-direction.md`
4. `docs/place-card-spec.md` などの個別機能仕様
5. スパイク記録、README、過去の検証メモ

ただし、個別機能仕様が本書より新しく、変更理由と影響範囲を明示している場合は、その仕様を採用し、
本書を同じ変更セット内で更新する。

本書の内容は「すべてを一度に実装する」という意味ではない。順序を守り、各 Gate を閉じてから
次の層へ進むことが、最終的な体験品質を最短で高める。

## 2. プロダクトの結論

TripMap は旅行情報の総合検索サービスではない。

TripMap は、旅行者が自分で決めた旅程を中心に、計画中、旅行中、旅行後で最適な道具へ変化する
**ローカルファーストの旅程ワークスペース**である。

- 計画中は、旅程を組み立て、無理や抜けを見つけ、修正する **Planner**
- 旅行中は、現在地、今、次、移動、予約を迷わず確認する **Guide**
- 旅行後は、訪問記録、写真、メモを旅程へ結び直す **Memory**

三つの別製品を作らない。同じ Trip、Day、Activity、Venue、Travel Leg、Participant、Photo を、
フェーズごとに異なる優先順位で提示する。

TripMap の中心単位は「場所」ではなく **Activity** である。Venue は Activity に場所の意味を補う。
地図、MapKit、外部画像、将来の評価データは旅行者の意図を補助するものであり、Activity を
置き換えない。

## 3. 成功状態

TripMap が目指す成功状態は、機能数ではなく次の体験で判断する。

### 3.1 計画中

- Mac または iPad で一日分の予定を地図と時間軸を見ながら自然に組める。
- Activity の追加、並べ替え、時刻、滞在時間、Venue 設定を迷わず行える。
- Doctor が「なぜ問題か」「どこか」「どう直せるか」を短く説明する。
- 移動時間が Activity 間の関係として見え、過密な旅程を早期に発見できる。
- 変更は保存前後の意味が明確で、取り消し可能である。

### 3.2 旅行中

- iPhone を開いた直後に、今日、今、次、移動先が分かる。
- オフラインまたは通信不安定でも、保存済み旅程とユーザー画像は確認できる。
- MapKit、Look Around、Wikimedia、経路取得に失敗しても、旅程操作が止まらない。
- 予約情報、メモ、住所、Apple Maps への導線へ少ない操作で到達できる。
- 片手操作、Dynamic Type、VoiceOver で主要操作を完了できる。

### 3.3 旅行後

- 訪問した Activity と写真を短時間で結び付けられる。
- 計画と実際の違いを責める表示にせず、旅の記録として残せる。
- Trip Card は写真を主役に変え、タイトル、日付、訪問数を静かに添える。
- 共有や書き出しを行わない限り、旅行データはユーザーの端末と選択した iCloud 領域に留まる。

## 4. 製品原則

### 4.1 旅行者の意図が一次情報

- Activity のタイトル、時刻、所要時間、メモはユーザーの意図である。
- Venue 名、住所、カテゴリは場所の客観情報である。
- Activity タイトルと Venue 名が同一とは限らない。
- MapKit の検索結果で Activity のタイトルを自動上書きしない。
- 外部サービスの情報を保存する場合は、取得元と取得日時を区別する。

### 4.2 提案と変更を分離する

- Doctor、将来の AI、経路再計算は提案または観測であり、旅程変更ではない。
- 自動変更を行わず、変更前後と影響範囲を確認してから適用する。
- 可能な変更は Undo に参加させる。
- 破壊的変更には対象と連鎖削除を具体的に示す。

### 4.3 取得不能は正常系

- Look Around がない地域は正常である。
- Wikimedia に完全一致画像がない Venue は正常である。
- MapKit の経路、カテゴリ、Place ID が取得できないことも正常である。
- すべての非同期情報は `idle / loading / loaded / unavailable / failed / stale` を区別する。
- 取得失敗によって Activity、Day、Trip の閲覧や編集を停止しない。

### 4.4 Apple らしい適応を優先する

- SwiftUI の標準コンテナ、標準 Toolbar、標準 Sheet、標準 Menu を優先する。
- iPhone の画面を拡大して iPad へ置くだけの実装を禁止する。
- Mac の画面を縮小して iPhone へ押し込む実装を禁止する。
- 独自タブ、独自タイトルバー、独自ダイアログは、標準コンポーネントで要件を満たせない場合だけ使う。
- システムの文字サイズ、アクセントカラー、コントラスト、Reduce Motion を尊重する。

### 4.5 ローカルファースト

- 保存済み Trip の閲覧と基本編集はネットワークなしで完了できる。
- 外部通信は Venue 解決、経路、画像、同期など、明確な付加価値のためだけに行う。
- 外部 API キーをアプリへ埋め込まない。
- 外部画像のためだけにアプリサーバーやリバースプロキシを導入しない。
- サーバー導入は、同期共有、秘密鍵保護、運用監査など、サーバーでしか解決できない要件が
  Research Gate を通過した場合だけ認める。

### 4.6 段階的に信頼を積む

- 見た目が完成していても、失敗状態、アクセシビリティ、永続化、実画面確認が未完なら Gate を閉じない。
- スパイクのコードをそのまま製品責務へ昇格させない。
- 実装と同じ変更セットでテストと仕様を更新する。

## 5. プラットフォーム別の役割

| 項目 | macOS | iPhone | iPadOS |
| --- | --- | --- | --- |
| 主目的 | 深い計画と編集 | 旅行中の即時確認 | 計画と旅行中の両立 |
| 主フェーズ | Planner | Guide | Planner / Guide |
| 基本構造 | Library と Trip の複数ウィンドウ | Tab + NavigationStack | NavigationSplitView |
| 地図と旅程 | 常時並置可能 | Map / List 切替 | 幅に応じて並置または切替 |
| 編集 | フル編集 | クイック編集中心 | フル編集 |
| キーボード | 必須 | 任意 | 必須 |
| ポインタ | 必須 | 対象外 | 必須 |
| 複数ウィンドウ | Trip ごと | 原則不要 | 対応する |
| 旅行中表示 | 補助 | 最優先 | 最優先へ切替可能 |

### 5.1 macOS

macOS は Planner の基準実装とする。

- Library Window と Trip Workspace Window を分離する。
- 複数 Trip を別ウィンドウで同時に開ける。
- Sidebar、Activity List、Map / Inspector の三領域を、ウィンドウ幅に応じて構成する。
- Toolbar には現在の文脈で有効な主要操作だけを置く。
- Command メニュー、キーボードショートカット、Undo / Redo、コンテキストメニューを提供する。
- Drag and Drop による Activity 並べ替えを最終的な標準操作にする。

### 5.2 iPhone

iPhone は Guide を主目的とするが、閲覧専用にはしない。

- 起動後は Trips から対象 Trip を開き、旅行中なら Today を第一候補にする。
- Guide の最上段に Day、次に `Map / List` 切替を置く現在の構造は維持する。
- Today / Now / Next が実装された後は、Guide の初期表示を Today Summary に昇格する。
- 時刻変更、完了、スキップ、短いメモ、Venue の再設定はクイック編集として提供する。
- Day の複製や複雑な一括操作は macOS / iPadOS へ委ねる。
- 重要操作は片手で届く領域に置き、地図上の小さなピンだけを操作入口にしない。

### 5.3 iPadOS

iPadOS は単なる大型 iPhone ではなく、適応型 Planner / Guide とする。

- Regular 幅では `NavigationSplitView` を使い、Day 一覧、Activity 一覧、Map / Detail を並置する。
- Compact 幅または狭い Stage Manager ウィンドウでは iPhone と同じ階層ナビゲーションへ折りたたむ。
- Split View、Stage Manager、外部ディスプレイ、横向き、縦向きを検証対象にする。
- Hardware Keyboard、Pointer、Drag and Drop、複数ウィンドウをサポートする。
- 旅行中は Sidebar を自動的に狭めてもよいが、ユーザーの選択を上書きしない。

Apple の Split View ガイドに従い、選択状態を各ペインで持続的に示し、狭幅では無理に複数ペインを
表示しない。

## 6. 情報アーキテクチャ

### 6.1 グローバル階層

全プラットフォームの最上位は次の三領域とする。

1. Trips
2. People
3. Me / Settings

機能が増えても最上位タブを安易に増やさない。Checklist、Doctor、Memory、Reservations は
Trip の一部であり、グローバルタブにしない。

### 6.2 Trip 内の階層

Trip 内は次の順序で構成する。

1. Overview
2. Today（旅行中のみ優先表示）
3. Day
4. Checklist
5. People
6. Memory（旅行後に強調）

macOS / iPadOS の Sidebar では、この階層を常時確認できる。iPhone では Overview から
NavigationStack で遷移する。

### 6.3 フェーズ

`Planner / Guide / Memory` はデータの別コピーではなく表示モードである。

- 日程前は Planner を提案する。
- 日程中は Guide を提案する。
- 日程後は Memory を提案する。
- ユーザーはいつでも手動で切り替えられる。
- 手動選択は Trip ごとに保存する。
- 自動提案はデータを変更しない。
- タイムゾーン判定には Trip の `timeZoneIdentifier` を使用する。

## 7. 画面仕様

### 7.1 Trip Library

#### 目的

旅行を見つけ、状態を理解し、開くための画面とする。旅程詳細や Doctor の全情報を詰め込まない。

#### 配置

- Upcoming、Past、All の分類を維持する。
- 検索はタイトル、国・地域、Participant を対象に段階的に広げる。
- 新規 Trip は Toolbar の primary action と空状態の両方から開始できる。
- macOS では行のクリックで選択、ダブルクリックまたは Return で開く動作もサポートする。
- iPhone / iPad では行全体を NavigationLink 相当の操作領域にする。

#### Trip Card / Row

Planner フェーズ:

- タイトル
- 日付
- Day 数
- 未解決の Doctor warning 数
- 必要であれば参加者の短い要約

Guide フェーズ:

- タイトル
- `Today Day N`
- 次の Activity と時刻
- オフラインで表示可能かを妨げない

Memory フェーズ:

- カバー写真
- タイトル
- 日付
- 訪問済み Activity 数

カバー写真がない場合は、地図スクリーンショットを自動生成して永続保存しない。アプリ内の
抽象的なプレースホルダーを使う。

### 7.2 Trip Overview

Overview は「Trip の状態を一目で把握し、次の作業を選ぶ」画面とする。

表示順:

1. Trip タイトル、日程、地域、Participant
2. 現在フェーズと切替
3. 最重要の Doctor issue
4. Day ごとの概要
5. Checklist 進捗
6. 旅行中は Today / Next
7. 旅行後は写真と訪問記録

Doctor issue を全件平坦に並べない。warning を優先し、種類と Day でまとめ、初期表示は最大数件にする。

### 7.3 Planner Workspace

#### macOS Regular

- Leading: Overview / Day / Checklist / People の Sidebar
- Center: 選択 Day の Activity 時間軸
- Trailing または背景: Map
- 必要な場合だけ Inspector: Activity 編集または Doctor 詳細

Map を隠した場合、Activity 一覧がその幅を使う。空白を残さない。

#### iPadOS Regular

- Primary: Day / Section navigation
- Secondary: Activity List
- Detail: Map または Activity / Venue detail

Map と一覧の選択状態は単一の `TripInteractionState` を通す。各 View が独自の選択状態を持たない。

#### Narrow Width

- Sidebar を rail、その後 hidden へ段階的に変える。
- rail には Overview、選択 Day、Doctor 件数を残す。
- 文字を極端に省略するよりペインを折りたたむ。

### 7.4 Guide

Guide は旅行中の認知負荷を最小化する。

#### Today Summary

最終形では次を表示する。

- Day 番号、日付、Day タイトル
- Now
- Next
- Next までの移動時間と出発目安
- 今日残っている Activity 数
- 未完了の重要 Checklist

Now 判定は Activity の開始時刻と滞在時間から行う。時刻未設定 Activity を無理に Now と判定しない。

#### Map

- 選択 Activity のピンを明確に強調する。
- ピンの主ラベルは Day 内 sequence とする。
- 地図上部に重複した Activity 詳細を常設しない。
- Venue Card は下部に置き、地図の主要部分を覆いすぎない。
- ユーザー位置は明示許可後だけ表示する。
- 常時追従を初期値にしない。

#### List

- Activity は時間軸順に表示する。
- Activity 間に Travel Leg を配置する。
- 選択 Activity を Map と共有する。
- `Now / Next / Completed / Skipped` は色だけに依存せず、ラベルと記号でも示す。

### 7.5 Memory

Memory は Core Planner が安定した後に実装する。

- Activity ごとに `planned / visited / skipped` を記録できる。
- 写真は PhotosPicker でユーザーが明示的に選択する。
- 撮影位置や日時から Activity 候補を提案しても、自動確定しない。
- 短い感想、実際の滞在時間、訪問メモを追加できる。
- Trip の写真一覧から Activity へ戻れる。
- 共有物には含まれる情報と位置情報の扱いを送信前に示す。

## 8. Activity と Venue の境界

### 8.1 Activity が所有する情報

- ユーザーが付けたタイトル
- Day 内 sequence
- 開始時刻
- 所要時間
- Activity category
- メモ
- 完了 / 訪問状態
- 予約参照
- Doctor issue の対象

### 8.2 Venue が所有する情報

- Venue 名
- 住所
- 緯度・経度
- MapKit Place Identifier
- MapKit から再解決した POI category
- ユーザーが選んだ Venue 画像
- 外部画像の参照と帰属情報

### 8.3 禁止する重複

- Venue Card に Activity タイトル、メモ、所要時間、Doctor issue を繰り返し表示しない。
- Activity Card に住所、外部画像帰属、Apple Maps の詳細情報を常設しない。
- Activity category と MapKit POI category を同一フィールドとして保存しない。

### 8.4 Activity Editor

Activity Editor は一つの編集フローとして次を扱う。

1. タイトル
2. 日付に結び付いた開始時刻
3. カテゴリ
4. 所要時間
5. メモ
6. Venue

Venue 検索は Editor 内の独立セクションに置く。検索結果選択後に、Activity タイトルを Venue 名へ
合わせるかを提案してもよいが、自動変更しない。

標準所要時間はカテゴリ別の提案として出し、未設定時だけワンタップで採用できるようにする。

### 8.5 Activity の操作

macOS / iPadOS:

- クリックで選択
- ダブルクリックで編集
- Return で編集
- Delete は確認または Undo 可能な削除
- Context Menu に編集、複製、別 Day へ移動、削除
- Drag and Drop で並べ替え

iPhone:

- タップで詳細または選択
- Swipe action は完了、編集など安全な操作を優先
- 削除は誤操作しにくい位置へ置く

## 9. Venue Card

Venue Card の詳細仕様は `docs/place-card-spec.md` を参照し、以下を絶対条件とする。

### 9.1 表示情報

Primary:

- 画像
- Venue 名
- POI category
- 住所または地域

Secondary:

- Activity sequence
- 開始時刻

Action:

- `画像を選択` / `画像を変更`
- `Mapsで開く`

電話番号、Web、営業時間、レビュー本文は表示しない。評価と投票数は将来の独立 Research Gate とする。

### 9.2 画像優先順位

優先順位は固定する。

1. ユーザー画像
2. Look Around
3. Wikimedia Commons の exact Venue image
4. プレースホルダー

上位ソースが決まった時点で、下位ソースの処理を開始しない。

### 9.3 画像解決の状態機械

`VenueImageResolutionModel` が一つの Venue Card に対する自動解決タスクを所有する。

- View の `body` 再評価で取得を再開しない。
- Place ID またはユーザー画像の有無が変わった場合だけ新しい request とする。
- Card が本当に画面から消えた場合は request を cancel する。
- 古い request の結果を request ID で拒否する。
- 取得した Wikimedia 画像は、親モデルへの保存結果を待たず Card 自身でも保持して表示する。
- ユーザー画像がある場合、Look Around と Wikimedia を一切呼ばない。
- Look Around 成功時、Wikimedia を呼ばない。
- Wikimedia の帰属情報が欠ける場合は表示しない。

### 9.4 Look Around

- `MKLookAroundSceneRequest` を Venue の `MKMapItem`、利用できなければ座標から作る。
- 取得不能はエラー Alert にせず Wikimedia へフォールバックする。
- Look Around は「Venue の公式写真」ではなく「周辺画像」として VoiceOver でも区別する。
- Scene の永続保存や Apple Maps 画像の抽出を行わない。

### 9.5 Wikimedia

- 最初の実装は日本語 Wikipedia の完全一致記事から Commons page image を解決する。
- 画像 URL、source page、作者、作者 URL、license、license URL、取得日時を保持する。
- 帰属表示から source page を開ける。
- 曖昧一致、近隣画像、地域イメージを exact Venue image として扱わない。
- Wikimedia が表示される頻度が低くても、イースターエッグ的演出を加えない。通常のフォールバックとして
  静かに表示する。

### 9.6 採用しない画像プロバイダー

現段階で Pexels、Unsplash、Google Places Photo、Flickr、Mapillary を追加しない。

Pexels は地域イメージを得るためだけに API キー保護サーバーを必要とし、Venue 一致も保証できない。
この問題のためにアプリサーバーやリバースプロキシを借りない。

## 10. Travel Leg と MapKit

### 10.1 Travel Leg の位置付け

移動は Activity の属性ではなく、前後 Activity の関係である。

将来の永続モデルとして最低限、次を持つ。

- from Activity ID
- to Activity ID
- transport type
- ユーザー指定の所要時間（任意）
- MapKit 推定時間と取得日時（キャッシュ）
- メモ（乗換、集合場所など）

初期段階では MapKit 推定を派生データとして扱い、安定後にユーザー指定値だけを永続化する。

### 10.2 表示

- Activity List の Activity 間に `車 25分` のように表示する。
- 計算中、利用不可、古い推定を区別する。
- Doctor の移動負荷は Travel Leg の合計から導く。
- Map 上では必要な場合だけ route polyline を表示し、全 Day の経路を常時重ねて読みにくくしない。

### 10.3 MapKit 境界

- 保存済み Place Identifier から `MKMapItem` を再解決する。
- 解決できない場合は名称と座標で検索する。
- `Mapsで開く` は解決済み `MKMapItem` を優先する。
- MapKit の検索結果をそのまま永続モデルにせず、交換可能な `PlaceSnapshot` を保存する。
- Apple Maps Server API は、クライアント MapKit で解決できない明確な要件が出るまで導入しない。

## 11. Doctor

Doctor は TripMap の中核差別化機能とする。

### 11.1 責務

- 入力不足を見つける。
- 時間的な矛盾を見つける。
- 過密や移動負荷を見つける。
- 食事や Participant など、忘れやすい計画要素を確認する。
- 問題の場所と修正入口を結ぶ。

### 11.2 表示規則

- `warning / info / calculating / unavailable` を分ける。
- 色だけで severity を表さない。
- Overview では種類と Day でまとめる。
- Day ではその Day の issue だけを出す。
- Activity では対象 Activity の issue だけを出す。
- suggestion がある場合は具体的な編集入口を提供する。

### 11.3 禁止事項

- Doctor 自身が旅程を自動変更しない。
- 同じ原因の issue を Overview、Day、Activity で別件として水増ししない。
- 外部情報が取得できないことを旅行者のミスとして warning にしない。
- 閾値を根拠なく頻繁に変更しない。変更時はテストと仕様へ理由を残す。

### 11.4 将来の AI

AI は Doctor が検出した問題に対する最小修正 fragment を提案する。

1. Doctor が deterministic に問題を検出
2. AI が一つ以上の修正案を生成
3. UI が変更前後、理由、影響 Day を表示
4. ユーザーが選択した fragment だけを適用

AI が利用不能でも、Doctor と手動編集で製品価値が成立することを必須とする。

## 12. People、Checklist、Reservation

### 12.1 People

- Participant はグローバルな人物レコードと Trip への assignment を分ける現在の構造を維持する。
- 連絡先アクセスを初期要件にしない。
- Contacts 連携は、ユーザーが明示選択した人物だけを取り込む独立 Gate とする。
- 重複名は Doctor が警告するが、自動統合しない。

### 12.2 Checklist

- Checklist は Trip 内機能として配置する。
- 項目はタイトル、完了状態、任意の期限、任意の担当者を持つ方向へ拡張する。
- Guide では今日または未完了の重要項目だけを出す。
- Widget や通知を導入する前に、アプリ内での編集と永続化を完成させる。

### 12.3 Reservation

Reservation は Activity に任意で結び付く参照情報とする。

初期フィールド:

- 種類
- 予約名
- confirmation code
- URL
- メモ

メール自動解析や Wallet 連携から始めない。まずユーザーが安全に保存し、Guide ですぐ開ける体験を作る。
confirmation code は通知や Widget に無条件表示しない。

## 13. Apple フレームワーク採用方針

### 13.1 現在の中核

- **SwiftUI:** 全プラットフォームの画面、Navigation、Toolbar、適応 Layout
- **SwiftData:** ローカル永続化
- **MapKit:** 地図、検索、Place 解決、Directions、Look Around、Apple Maps 連携
- **PhotosUI:** PhotosPicker によるユーザー主導の画像選択
- **Foundation:** Calendar、TimeZone、URLSession、Codable、Concurrency

### 13.2 次に採用する

- **UndoManager:** macOS / iPadOS の編集、並べ替え、削除
- **Transferable:** Activity / Day の Drag and Drop と共有境界
- **UserNotifications:** 明示的に設定した Activity reminder
- **AppIntents:** `次の予定を表示`、`今日の旅程を開く` など読み取り中心の操作
- **WidgetKit:** Today / Next の小さな Widget
- **CoreSpotlight / NSUserActivity:** Trip と Activity の検索、Handoff、Deep Link

App Intents はアプリの操作を Siri、Shortcuts、システム体験へ公開できるため、まず読み取り操作から導入する。
書き込み Intent は、確認と競合処理が完成してから追加する。

### 13.3 Research Gate 後に採用する

- **CloudKit / SwiftData sync:** 同一ユーザー端末間同期
- **CloudKit sharing:** 共同編集
- **ActivityKit:** 旅行中の Now / Next Live Activity
- **EventKit:** Activity のカレンダー書き出し
- **CoreLocation:** Guide の任意現在地表示と出発提案
- **BackgroundTasks:** 外部画像ではなく、同期や明示的な更新要件がある場合

SwiftData は CloudKit entitlement と互換 schema があれば同期へ接続できるが、現在のローカル schema を
そのまま本番同期へ昇格しない。migration、競合、削除、画像容量、iCloud 未ログイン状態を検証する。

### 13.4 採用しないもの

- MapKit の非公開 API
- Apple Place Card のビュー階層解析
- Apple Maps 写真のスクリーンショット再利用
- 外部 API キーのバイナリ埋め込み
- 目的が重複する第三者 UI フレームワーク
- 旅程の基本閲覧に必須となる WebView
- コア機能のための常時接続独自バックエンド

## 14. データ設計

### 14.1 Domain と Persistence の分離

- `Trip`, `Day`, `Activity`, `PlaceSnapshot` は Domain snapshot として Sendable を維持する。
- SwiftData model を View へ広範囲に直接渡さない。
- 編集は Domain で検証し、妥当な snapshot だけを Persistence へ適用する。
- 将来の schema-v8 exchange は Domain を経由する。

### 14.2 不変条件

- Trip title は空にしない。
- date range は昇順。
- Day date は Trip timezone の local civil date として保持する。
- Activity time は Day date と Trip timezone に結合する。
- sequence は Day / Activity 内で一意かつ連続。
- Activity は最大一つの Venue を持つ。
- UUID 重複を保存境界で拒否する。
- 不正な部分だけを黙って捨てて保存しない。

### 14.3 時刻

- 旅行日と Activity 時刻に裸の UTC `Date` を意味モデルとして使わない。
- `LocalDate` と `LocalTime` を入力・永続化境界で使う。
- ユーザー端末のタイムゾーン変更で旅程の壁時計時刻を動かさない。
- Guide の Now / Next 判定だけは、Trip timezone と現在時刻から instant を計算する。

### 14.4 画像

- ユーザー画像は正規化した JPEG として外部ストレージ属性へ保存する。
- EXIF の不要な位置情報を保存する必要があるかを明示判断し、初期実装では除去する。
- 外部画像はメタデータと URL を保存し、provider の条件を確認せずバイナリを恒久キャッシュしない。
- CloudKit 同期前に画像サイズ上限と容量試験を行う。

### 14.5 Migration

- 次の schema 変更から `VersionedSchema` と `SchemaMigrationPlan` の導入を検討する。
- migration test は旧 store fixture を開き、件数だけでなく意味値を比較する。
- 本番データを破棄して開発を進める運用をリリース前に終了する。

## 15. 同期と共同編集

同期は便利機能ではなくデータ安全機能として扱う。

### 15.1 同一ユーザー同期 Gate

検証項目:

- Mac、iPhone、iPad 間の作成、編集、削除
- オフライン編集後の競合
- Day 順序と Activity sequence の競合
- 画像容量
- iCloud サインアウト
- CloudKit quota
- schema migration
- 外部画像 URL 失効

完了条件:

- データ欠落なく往復する。
- 競合時に少なくともどの端末の変更を採用したか説明できる。
- 同期失敗でもローカル閲覧と編集を継続できる。

### 15.2 共同編集 Gate

同一ユーザー同期が安定するまで共同編集を始めない。

- Participant と Apple ID / CloudKit identity を同一視しない。
- 招待、権限、退出、所有者削除を設計する。
- Activity 単位の履歴または衝突説明が必要になるまで、リアルタイム共同カーソルを目標にしない。

## 16. オフライン、キャッシュ、ネットワーク

### 16.1 オフラインで必ず使えるもの

- Trip Library
- Trip / Day / Activity
- 保存済み Venue snapshot
- ユーザー画像
- Checklist
- Participant
- 保存済み予約参照

### 16.2 オンライン付加情報

- MapKit 再解決
- Directions
- Look Around
- Wikimedia
- 将来の同期

### 16.3 キャッシュ規則

- キャッシュキーには入力 Place / Activity、transport type、必要な時刻条件を含める。
- stale データは消すのではなく、古い推定として表示可能にする。
- Retry は指数バックオフを使い、View 再描画で無制限再試行しない。
- 同じ Venue Card で Wikipedia / Commons を重複取得しない。
- ネットワーク失敗を Alert の連続表示にしない。

## 17. 状態、エラー、フィードバック

### 17.1 Loading

- 画面全体を止めず、情報が入る領域だけを読み込み状態にする。
- 既存情報を消して Spinner だけにしない。
- 画像取得中も Venue 名、住所、操作を表示する。
- 経路計算中も Activity 一覧を操作できる。

### 17.2 Empty

空状態は次の三点を含む。

1. 何がないか
2. なぜ問題でないか、または次に何ができるか
3. 文脈に合う一つの primary action

### 17.3 Error

- 保存失敗は Alert で具体的に示し、modelContext を rollback する。
- 外部画像なしは Alert にしない。
- Maps 解決失敗は `Mapsで開く` 付近で再試行可能にする。
- store 自体を開けない場合はデータを勝手に作り直さず、復旧案を出す。

### 17.4 Success

- 通常の保存ごとに Toast を出さない。
- 大きな一括操作、import、sync recovery だけ明示結果を出す。
- 選択や並べ替えは直接操作の変化そのものをフィードバックとする。

## 18. アクセシビリティ

アクセシビリティは完了後の監査ではなく、各 View の受け入れ条件とする。

### 18.1 VoiceOver

- sequence pin は `Day N` または `予定 N` と Activity / Venue 名を説明する。
- Venue image は user / Look Around / Wikimedia / placeholder を区別する。
- warning 件数に severity と対象を含める。
- Map だけでしか到達できない情報を作らない。

### 18.2 Dynamic Type

- iPhone の Accessibility size で Activity、Venue、操作が欠落しない。
- Venue Card は `ViewThatFits` だけに頼らず、極端な文字サイズでは縦配置も許容する。
- 固定高さにテキストを閉じ込めない。

### 18.3 Keyboard と Pointer

- macOS / iPadOS で主要操作へ Full Keyboard Access で到達できる。
- Focus ring を隠さない。
- Hover だけで情報を伝えない。
- ショートカット候補:
  - Command-N: 新しい Trip
  - Command-Shift-N: 新しい Activity
  - Command-E: Activity 編集
  - Command-Delete: 確認付き削除
  - Command-Z / Shift-Command-Z: Undo / Redo
  - Command-F: 現在の一覧を検索

### 18.4 視覚設定

- 色だけで選択、warning、完了を示さない。
- Increase Contrast で Material 上の文字が読める。
- Reduce Motion では map camera と selection animation を短縮または無効化する。
- Differentiate Without Color を確認する。

## 19. Localization

- 画面文字列を日本語リテラルのまま拡散させず、String Catalog へ移す。
- `Activity`, `Venue`, `Trip`, `Day` を製品用語として翻訳規則に定義する。
- 日付、時刻、距離、通貨は FormatStyle を使う。
- 日本語住所を前提に国判定し続けない。Venue に country code / region を保存できる構造へ移行する。
- Right-to-Left layout と長い地名を最低限 snapshot test で確認する。

## 20. Privacy と Security

- 位置情報許可は Guide でユーザー位置を表示する直前に求める。
- Trip 作成時や起動時に位置情報許可を求めない。
- 写真は PhotosPicker を使い、写真ライブラリ全体の権限を初期要件にしない。
- confirmation code、Participant note、旅行日程を Widget や通知へ出す場合は表示範囲を選べるようにする。
- Analytics を導入する場合は Apple のプライバシー要件を確認し、第三者トラッキングを前提にしない。
- ログへ住所、予約番号、Participant note、画像 URL の query を無条件に出さない。
- 外部リンクは source / Maps など、ユーザーが理解できるラベルで開く。

## 21. パフォーマンス

- Map、Activity List、Doctor 計算を View の `body` で重複実行しない。
- MapKit request は model object が所有し、View の一時的再生成から分離する。
- 画像 decode と JPEG 正規化を MainActor で長時間実行しない。
- 長い Trip でも Day 単位に表示を限定する。
- SwiftData fetch は Trip 単位に絞り、全 store の snapshot 変換を頻繁に行わない。
- Instruments で起動、Trip open、Day switch、Map pan、画像設定の Time Profiler と Memory を確認する。

目標値は実測後に固定するが、最初の品質目安を次とする。

- Warm launch から Library 表示まで体感待ちなし
- Trip open で既存旅程を先に表示し、外部取得を後から反映
- Day switch で Activity 一覧を同期的に切替
- 画像正規化後の一枚を過大な解像度で保存しない

## 22. テスト戦略

### 22.1 Domain Unit Test

必須対象:

- local date / time
- sequence
- Trip validation
- creation / editing
- Day replicate / swap
- Doctor
- interaction selection
- persistence snapshot round trip
- external image attribution
- image source priority
- Place resolver ranking
- travel estimate aggregation

### 22.2 Persistence Test

- in-memory store
- disk store reopen
- rollback
- relationship cascade
- migration fixture
- user image
- external image metadata

### 22.3 Async Model Test

- 同一 request ID では再取得しない
- input 変更で旧 request を cancel
- 遅い旧結果を拒否
- Look Around 成功で Wikimedia を呼ばない
- Look Around 失敗で Wikimedia を一度だけ呼ぶ
- user image 設定後に自動取得を呼ばない
- Card 再描画で Commons request を cancel しない

### 22.4 UI Test

最低限の自動 UI フロー:

- Trip 作成
- Library から Trip を開く
- Activity 追加・編集・削除
- Venue 設定
- Map / List の相互選択
- Day 切替
- Venue Card 表示
- user image 選択
- Doctor issue から編集へ移動

テスト用データ投入は Debug / UI Test configuration に閉じ、製品 RootView にレビュー用分岐を残さない。

### 22.5 実画面 Matrix

各大きな UI Gate で次を確認する。

macOS:

- 最小幅
- 標準幅
- 大画面
- Light / Dark
- Keyboard only

iPhone:

- 小型幅
- 標準幅
- Max 幅
- Portrait / Landscape
- Dynamic Type accessibility size

iPad:

- Full screen portrait / landscape
- 1/2 Split View
- 狭い Stage Manager window
- Hardware Keyboard / Pointer

共通:

- Light / Dark
- Increase Contrast
- Reduce Motion
- VoiceOver
- オフライン
- 低速通信

### 22.6 外部サービス実画面テスト

Venue image Gate:

1. user image を設定できる
2. user image 設定時に Look Around / Wikimedia が動かない
3. Look Around 対応 Venue で Look Around が表示される
4. Look Around 成功時に Wikimedia が動かない
5. Look Around 非対応の那覇空港で Wikimedia exact image が表示される
6. 作者と license が表示される
7. すべて失敗時に placeholder になる
8. Activity 切替で旧画像が混入しない

Simulator 基盤障害で確認できない場合は Gate を閉じず、`blocked by environment` と記録する。

## 23. 開発の進め方

### 23.1 一つの変更単位

各変更は次を含む。

1. 問題とユーザー価値
2. 仕様または ADR
3. Domain / Model
4. View
5. Unit test
6. 実画面確認
7. Known issue または完了記録

### 23.2 Research Gate

未知の API、外部 provider、同期、共同編集、AI は先に Gate を作る。

Gate 文書には次を記載する。

- Question
- Non-goals
- Test matrix
- Observed result
- Product decision
- Follow-up

成功したコードだけを製品へ昇格する。

### 23.3 Definition of Done

機能は次をすべて満たしたときだけ完了とする。

- 仕様の受け入れ条件を満たす
- Domain invariant を壊さない
- 保存と再起動後に意味値が保たれる
- loading / unavailable / failure がある
- Accessibility label と keyboard path がある
- Unit test がある
- 対象プラットフォームで build 成功
- 代表 viewport で実画面確認済み
- 一時的な起動分岐、ログ、fixture が製品コードに残っていない
- 文書が現状を正しく示す

## 24. 実装ロードマップ

順番は次を標準とする。後続機能を先に作らない。

### P0 — Venue Image Gate を閉じる

現状:

- 優先順位 coordinator は実装済み
- Look Around と Wikimedia resolver は実装済み
- View 再描画に対する task ownership を改善済み
- Wikimedia 取得結果を Card 内で保持する補正を実装済み
- resolver の依存性注入と lifecycle regression test は実装済み
- macOS の通常60テスト、macOS QA build、iOS generic Simulator build は成功
- 渋谷スクランブル交差点の Look Around と、那覇空港の Wikimedia fallback は
  実サービス smoke test で成功
- QA Trip の Library 表示は実画面確認済み
- macOS UI test target と専用 QA scheme は追加済み
- 残留 TripMap / `testmanagerd` の終了と全 Simulator shutdown により macOS UI automation mode は復旧済み
- 専用 QA scheme の6テストが成功し、渋谷 Look Around、那覇 Wikimedia と帰属リンク、
  native PhotosPicker でのユーザー画像選択、seed なし再起動後の永続化を確認済み
- CoreSimulator は復旧し、iOS generic Simulator build は成功
- macOS 1180×720 / 700×720 の regular / narrow と、176×99 / 88×88 の画像適応を確認済み
- Wikimedia attribution は keyboard focus 可能で、Tab 到達 UI test が成功
- VoiceOver を実際にオンにして論理的な Accessibility tree 順を確認し、確認後はオフへ復元済み
- iPhone 17 Pro / iOS 27 Simulator で那覇 Wikimedia とユーザー画像優先を実画面確認済み
- Accessibility XXL では Venue 情報と帰属を省略せず、操作を縦配置する adaptive layout を実装・確認済み

残作業:

- iPhone Simulator で live Look Around 成功を再現し、同一代表経路の最後の実画面証跡を得る
- Xcode 27 beta が iOS 17 SwiftData に存在しない symbol を参照する問題を、安定版 Xcode または
  修正済み beta で再確認する

iPadOS target と adaptive workspace は現行 shipping target の Venue Image Gate から分離し、
P1 以降の platform expansion Gate として扱う。

完了条件:

- `docs/place-card-spec.md` の Acceptance criteria を実画面証跡付きで満たす。

### P1 — Activity Input UX

- Double-click / Return / Context Menu
- Category duration suggestion
- Venue search section
- Drag reorder
- Undo / Redo
- iPhone quick edit

完了条件:

- 新規 Activity 作成から Venue 設定、地図確認、再編集まで一連の操作が説明なしで完了する。

### P2 — Doctor Information Architecture

- Overview grouping
- Day / Activity local issue
- issue から editor deep link
- warning / info / calculating / unavailable

完了条件:

- issue の原因、対象、修正入口が一画面で理解できる。

### P3 — Travel Leg

- leg UI
- transport type
- calculation states
- route detail
- Doctor integration

完了条件:

- Activity 間の移動時間が一覧上で説明でき、取得不能でも旅程が読める。

### P4 — Adaptive Workspace

- expanded / rail / hidden
- macOS window width
- iPad NavigationSplitView
- compact collapse
- keyboard / pointer

完了条件:

- 代表幅で Map と Activity の実効面積が確保され、選択状態を失わない。

### P5 — Phase Foundation

- phase suggestion
- manual override
- Planner / Guide / Memory shell
- Today Summary
- phase-specific Trip Card

完了条件:

- 一つの Trip で三フェーズを切り替え、同じデータが異なる優先順位で見える。

### P6 — Guide Readiness

- Now / Next
- completed / skipped
- reservation reference
- local notification
- offline review

完了条件:

- 通信なしでも当日の旅程を確認でき、次の場所を Apple Maps で開ける。

### P7 — Memory Minimum Slice

- visited state
- Activity photo attachment
- short reflection
- Memory Trip Card

完了条件:

- 一つの Trip を計画から旅行後の記録へ移行できる。

### P8 — Sync Research Gate

- versioned schema
- CloudKit compatibility
- conflict test
- image quota
- account states

完了条件:

- 同一ユーザー三端末でデータ欠落のない往復を証明する。

### P9 — System Experiences

- App Intents
- Spotlight / Handoff
- Today / Next Widget
- 必要性を確認した場合だけ Live Activity

完了条件:

- アプリ本体を開かなくても次の予定を安全に確認でき、操作後の source of truth が一つである。

### P10 — Collaboration / AI

同期と Doctor が十分に安定した後だけ着手する。

- CloudKit sharing
- change conflict UX
- Doctor-based AI fragments

完了条件:

- 共同編集または AI がなくても製品価値が成立し、追加機能がデータの信頼性を下げない。

## 25. 直近の具体的な指示

次の実装担当者は、この順序で作業する。

1. 安定版または修正済み Xcode の iPhone Simulator で渋谷 live Look Around を再確認する。
2. 成功証跡を `docs/place-card-spec.md` に追加し、Venue Image Gate を閉じる。
3. Venue Image Gate が閉じた後、Activity Card の double-click / Return / Context Menu を実装する。
4. Activity Editor の duration suggestion を実装する。
5. Doctor issue から対象 Activity Editor へ移動する。
6. Travel Leg の Domain 仕様を ADR として先に確定する。
7. iPadOS adaptive workspace を追加し、iPad viewport を確認する。

P0 が閉じる前に新しい外部画像 provider、評価データ、独自サーバー、AI、CloudKit を始めない。

## 26. 文書運用

- Product concept の変更は `docs/product-direction.md` と本書を更新する。
- 不変条件と永続化判断は ADR を追加する。
- 個別 UI の寸法、情報階層、acceptance は個別仕様へ置く。
- Known issue は再現条件、影響、回避策、解消条件を記載する。
- README は現在の起動状態、対応 OS、build コマンド、主要文書への入口だけを簡潔に保つ。
- 完了済みと未完了を混同しない。実装済みでも実画面未確認なら `implemented, verification pending` と書く。

## 27. 禁止事項一覧

- Activity と Venue の責務を再び混ぜない。
- Venue Card を施設ディレクトリにしない。
- 電話、Web、営業時間、レビューをカードへ足さない。
- ユーザー画像を自動画像で置換しない。
- Wikimedia の曖昧画像を exact Venue として表示しない。
- 外部画像取得のためだけにサーバーを建てない。
- View の `body` または短命な `.task` に長い非同期処理の所有権を置かない。
- MapKit の取得失敗で Alert を連発しない。
- iPhone、iPad、Mac を同じ固定レイアウトにしない。
- Date / TimeZone の意味を裸の `Date` に戻さない。
- SwiftData model を公開 exchange schema としない。
- Doctor や AI が確認なしに旅程を書き換えない。
- テスト専用 RootView 分岐を製品コードへ残さない。
- Gate 未完の機能を「完了」と文書化しない。

## 28. 公式リファレンス

- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [MKMapView and Look Around](https://developer.apple.com/documentation/mapkit/mkmapview)
- [Apple Human Interface Guidelines: Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [AppIntent](https://developer.apple.com/documentation/appintents/appintent)
- [Widget and Live Activity interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [CloudKit adoption guidance](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)
