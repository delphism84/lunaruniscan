#db
mongodb://<USER>:<PASSWORD>@server.lunarsystem.co.kr:47017/?authSource=admin
dbname : lnuniscan

#?대찓???쒕쾭
lunar@lunarsystem.co.kr?섏? ?꾩옱 IMAP/SMTP瑜??ъ슜?섍퀬 ?덉뒿?덈떎.
蹂?湲곕뒫? 愿由ъ옄???섑빐??鍮꾪솢?깊솕 ?????덉뒿?덈떎.

硫붿씪 ?꾨줈洹몃옩 ?섍꼍 ?ㅼ젙
?ㅻ쭏?명룿, ?꾩썐猷????몃? 硫붿씪 ?꾨줈洹몃옩 ?섍꼍?ㅼ젙???꾨옒? 媛숈씠 ?깅줉??二쇱꽭??
?꾩?留?
IMAP ?쒕쾭紐?: imap.worksmobile.com
IMAP ?ы듃 : 993, 蹂댁븞?곌껐(SSL) ?꾩슂
SMTP ?쒕쾭紐?: smtp.worksmobile.com
SMTP ?ы듃 : 465, 蹂댁븞?곌껐(SSL) ?꾩슂
ID : <ACCOUNT_EMAIL>
?몄쬆 : ??鍮꾨?踰덊샇(沅뚯옣) ?먮뒗 OAuth2 ?ъ슜

# Node API 硫붿씪 .env (Worksmobile ?ъ슜)
MAIL_HOST=smtp.worksmobile.com
MAIL_PORT=465
MAIL_SECURE=true
MAIL_USER=<ACCOUNT_EMAIL>
MAIL_PASS=<APP_OR_ACCOUNT_PASSWORD>
MAIL_FROM="LnUniScan" <no-reply@lunarsystem.co.kr>
IMAP_HOST=imap.worksmobile.com
IMAP_PORT=993
IMAP_SECURE=true
IMAP_USER=<ACCOUNT_EMAIL>
IMAP_PASS=<APP_OR_ACCOUNT_PASSWORD>
MAIL_IMAP_TEST_ENABLED=false

# 援ш?(Gmail) 怨꾩젙 ?곕룞 以鍮?
?꾨옒 ??媛吏 以??섎굹瑜??좏깮?섏꽭??

1) OAuth2(XOAUTH2) ?ъ슜(沅뚯옣)
- ?꾩젣: Google Cloud Console ?꾨줈?앺듃 ?앹꽦, OAuth ?숈쓽?붾㈃ 援ъ꽦
- 踰붿쐞(Scope): https://mail.google.com/
- ?대씪?댁뼵???좏삎: Desktop ?먮뒗 Web
- 由щ뵒?됱뀡 URI: 媛쒕컻 ??http://localhost:<port>/oauth2/callback ?먮뒗 OAuth 2.0 Playground
- ?좏겙 諛쒓툒: OAuth 2.0 Playground?먯꽌 Gmail API ??https://mail.google.com/ ?좏깮, 蹂몄씤 ?대씪?댁뼵?몃줈 援먯껜 ?ъ슜, refresh_token ?띾뱷
- ?곌껐 ?뺣낫
  - SMTP: smtp.gmail.com / 587(STARTTLS) ?먮뒗 465(SSL)
  - IMAP: imap.gmail.com / 993(SSL)
  - ?몄쬆: XOAUTH2 (username=?꾩껜 ?대찓?? access_token? refresh_token?쇰줈 二쇨린 媛깆떊)

.env ?덉떆(?깆뿉???ъ슜)
MAIL_PROVIDER=gmail
MAIL_EMAIL=your@gmail.com
GOOGLE_CLIENT_ID=xxxxxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxx
GOOGLE_REFRESH_TOKEN=xxxxxxxxxxxxxxxxxxxx
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
IMAP_HOST=imap.gmail.com
IMAP_PORT=993
IMAP_SECURE=true

2) ??鍮꾨?踰덊샇 ?ъ슜(媛꾨떒)
- 援ш? 怨꾩젙?먯꽌 2?④퀎 ?몄쬆 ?쒖꽦??
- 蹂댁븞 ????鍮꾨?踰덊샇 ?앹꽦(?? Mail, 湲곌린: 湲고?)
- ?앹꽦??16?먮━ ??鍮꾨?踰덊샇瑜?IMAP/SMTP 鍮꾨?踰덊샇濡??ъ슜

# 蹂댁븞 ?덈궡
- ??臾몄꽌???ㅼ젣 鍮꾨?踰덊샇/?좏겙? ?덈? 湲곗옱?섏? ?딆뒿?덈떎.
- ?ㅼ젣 ?댁쁺 媛믪? .env(諛깆뾽? ?щ궡 蹂닿??? ?먮뒗 蹂댁븞 鍮꾨? ??μ냼?먮쭔 蹂닿??섏꽭??