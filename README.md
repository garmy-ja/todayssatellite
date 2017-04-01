# todayssatellite

Twitter bot program for https://twitter.com/todayssatellite
今日の人工衛星アカウントに定時にTweetをするためのbot

## usage / 使用法

tweetlist.tsvにツイートする内容・日付・時刻を設定し

$ ruby bot_controll.rb start

でdaemon化して起動します。
そうすると、tweetlist.tsvに記載された日付・時刻に当該のツイートが送信されます。

daemonの終了は

$ ruby bot_controll.rb stop

です。
なお、ツイート時点での文字数の確認は行っていません。

## about "Todays' Satellite" / 今日の人工衛星 とは

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
