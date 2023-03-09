# todayssatellite

Twitter bot program for https://twitter.com/todayssatellite & https://activitypub.garmy.jp/@todayssatellite
今日の人工衛星アカウントに定時にTweetをするためのbot
Mastodonへの投稿も復活していますがAPIを直接叩いています。

アカウントのフォロー状況を定期的に取得するスクリプトfollowers_rr.rbも同梱、そちらの利用方法は当該ファイルを確認のこと。

## Enviroment / 動作環境

ruby 2.4.0にて動作確認。ツイートリストのExcel化以前であれば ruby 1.6.6のころから動いていたはずです。

必要なgemsは twitter, daemons, roo の3つ。

mastodon対応はtoken等生成のためにgemsを使っていますが、このコード自体でtokenを生成したわけではなく、
tokenを生成する部分は正しく動作しない可能性があります。

## usage / 使用法

tweetlist.tsvにツイートする内容・日付・時刻を設定し

$ ruby bot_control.rb start

でdaemon化して起動します。
そうすると、tweetlist.xlsxに記載された日付・時刻に当該のツイートが送信されます。
daemon起動中でも定期的にtweetlist.xlsxの更新時刻は確認しているため、もしリストを編集してもdaemonの再起動を行う必要はありません。

daemonの終了は

$ ruby bot_control.rb stop

です。

なお、ツイート時点での文字数の確認は行っていません。
tweetlist.xlsxのC列に文字数確認を入れていますのでそちらをご利用下さい。

## about "Todays' Satellite" / 今日の人工衛星 とは

最新情報は
http://todayssatellite.jpn.org/about
に記載。といっても中身はたぶん一緒。

A brief explanation of the spacecraft (artificial satellite, rocket, spacecraft) launched in the past.
過去に打ち上げられた宇宙機（人工衛星、ロケット、探査機）の簡単な解説。

### Tweet time / 投稿時刻

7:00 AM in JST (Tweet at launch time of some spacecraft)
毎日7時前後（一部の宇宙機は発射時刻のtweetもあり）

### Source / 出典

Wikipedia, Official website of NASA, JAXA, and so on.
Wikipedia、NASAやJAXAの各種Webサイト

### Reference timezone / 日付の基準

UTC (Some Japanese spacefcraft tweets in past day)
UTC（一部の宇宙機の打上時刻は、日本時間の日付の前日にツイートされます）

### Contect / Bot運営への連絡先

@garmy in twitter
