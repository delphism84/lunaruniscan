## UniScan WebSocket ?ъ슜 媛?대뱶 (FE)

- ?묒냽 URL: `wss://server.lunarsystem.co.kr:44444/ws/sendReq`
- ?꾨줈?좎퐳: JSON ?띿뒪??硫붿떆吏
- 硫붿떆吏 ??? `barcode` | `image`
- ?묐떟: ?쒕쾭??泥섎━ ?쒕쭏??`"ok"` ?띿뒪?몃? ?뚯떊
- ??? `image` ??낆? ?쒕쾭??`/public/files/` ?꾨옒???뚯씪 ??? ???寃쎈줈??異뷀썑 REST濡??쒓났 ?덉젙

### 怨듯넻 ?꾨뱶
- `userId` (string)
- `deviceId` (string)
- `msgType` (string: `barcode` | `image`)
- `msg` (string) - barcode ?띿뒪???먮뒗 ?대?吏??base64瑜?蹂대궪 ???ъ슜 媛??
- `imageBase64` (string, optional) - ?곗씠??URI ?먮뒗 ?쒖닔 base64. 議댁옱 ???곗꽑 ?ъ슜
- `imageExt` (string, optional) - ?뚯씪 ?뺤옣?? `jpg`/`png` ?? 誘몄?????`jpg`
- `ack` (number, optional) - 湲곕낯 0
- `rxTime` (ISO-8601, optional) - 誘몄??????쒕쾭 UTC ?쒓컙

### 硫붿떆吏 ?덉떆

#### 1) 諛붿퐫???꾩넚
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123",
  "ack": 0
}
```

#### 2) ?대?吏 ?꾩넚 (base64)
- data URI ?뺥깭 ?먮뒗 ?쒖닔 base64 紐⑤몢 ?덉슜?⑸땲??
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "image",
  "imageBase64": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...",
  "imageExt": "jpg",
  "ack": 0
}
```

### ?곌껐 肄붾뱶 ?ㅻ땲??

#### 釉뚮씪?곗? (?먯떆 WebSocket)
```javascript
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq');

ws.onopen = () => {
  // ?? 諛붿퐫??硫붿떆吏
  ws.send(JSON.stringify({
    userId: 'u1',
    deviceId: 'd1',
    msgType: 'barcode',
    msg: 'CODE128-ABC-123',
    ack: 0
  }));
};

ws.onmessage = (e) => {
  console.log('server:', e.data); // "ok"
};

ws.onerror = (e) => console.error('ws error', e);
ws.onclose = () => console.log('ws closed');
```

#### Node.js (ws)
```javascript
const WebSocket = require('ws');
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq');

ws.on('open', () => {
  ws.send(JSON.stringify({
    userId: 'u1',
    deviceId: 'd1',
    msgType: 'image',
    imageBase64: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...',
    imageExt: 'png'
  }));
});

ws.on('message', (msg) => console.log('server:', msg.toString()));
ws.on('error', console.error);
ws.on('close', () => console.log('ws closed'));
```

### ???諛??묎렐
- ?쒕쾭 ???寃쎈줈: `/var/UniScan/docker/be/public/files/`
- ?뺤쟻 ?쒓났 寃쎈줈: `/public/files/<?뚯씪紐?`
  - ?? `https://server.lunarsystem.co.kr/public/files/20250101_120000_123_u1_d1.jpg`

### 二쇱쓽 ?ы빆
- ?대?吏 ?곗씠?곌? ??寃쎌슦, 議곌컖(fragment)?쇰줈 ?꾩넚?섏뼱???쒕쾭媛 議곕┰ ??泥섎━?⑸땲??
- `imageBase64`媛 `data:` URI??寃쎌슦 ?쒕쾭媛 ?묐몢?대? ?쒓굅?⑸땲??
- ?뚯씪紐낆? `UTC_??꾩뒪?ы봽_user_device.ext` ?뺤떇?쇰줈 ??λ맗?덈떎.
- WSS??Nginx瑜??듯빐 `44444` ?ы듃濡??몄텧?섎ŉ, ?대? BE??`45444`?먯꽌 ?숈옉?⑸땲??

---

### ?꾩껜 ?섑뵆(JSON) - ???ы븿

#### 1) 諛붿퐫???꾩넚 ?꾩껜 ?뚮줈??
- ?좏겙 諛쒓툒 ?붿껌(JSON)
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- ?좏겙 諛쒓툒 ?묐떟(JSON)
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```
- WSS ?묒냽 URL
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>
```
- 諛붿퐫??硫붿떆吏(JSON)
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123",
  "ack": 0,
  "rxTime": "2025-09-13T09:00:00Z"
}
```

#### 2) ?꾩＜ ?묒?(2px x 2px) ?대?吏 ?꾩넚 ?꾩껜 ?뚮줈??
- ?좏겙 諛쒓툒 ?붿껌(JSON)
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- ?좏겙 諛쒓툒 ?묐떟(JSON)
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```
- WSS ?묒냽 URL
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>
```
- 2x2 PNG ?대?吏 硫붿떆吏(JSON)
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "image",
  "imageExt": "png",
  "imageBase64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFklEQVQImWNgoBpgYGBg+M+ABQwMAADpNQfL9nEo6QAAAABJRU5ErkJggg==",
  "ack": 0,
  "rxTime": "2025-09-13T09:00:00Z"
}
```

---

### ?좏겙 諛쒓툒 諛??몄쬆 ?덉감
- 湲곕낯 API Key: `lunar-earth-sun`
- ?좏겙 TTL: 120遺?(?섍꼍蹂??`TOKEN_TTL_MINUTES`濡?議곗젙 媛??
- ?먮쫫: FE媛 API ?ㅻ줈 ?좏겙 諛쒓툒 ??WSS ?묒냽 ??`?token=...` 荑쇰━濡??꾩넚 ??BE媛 留뚮즺/以묐났 ?몄뀡 寃??諛??묒냽 ?덉슜

#### 1) ?좏겙 諛쒓툒 (REST)
- URL: `http://127.0.0.1:45444/api/token` (?몃? ?몄텧 ??Nginx ?꾨줉??援ъ꽦 ?꾩슂)
- ?붿껌(JSON):
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- ?묐떟(JSON):
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```

#### 2) WSS ?묒냽 (?좏겙 ?ы븿)
- URL: `wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>`
- 以묐났 ?곌껐 諛⑹?: 媛숈? ?좏겙?쇰줈 ?숈떆 ?묒냽 ??409 ?묐떟(?좏겙 ?ъ슜 以?
- 留뚮즺/?쒕챸 ?ㅻ쪟: 401 ?묐떟
  - 二쇱쓽: `token` 媛믪? `/api/token` ?묐떟??`token`???ъ슜?⑸땲?? `API_KEY_DEFAULT`??`API_KEY_MASTER_B64`(Base64) ?먯껜瑜??ｌ쑝硫?401??諛쒖깮?⑸땲??

#### ?덉젣 (釉뚮씪?곗?)
```javascript
// 1) ?좏겙 諛쒓툒
const tokenResp = await fetch('https://server.lunarsystem.co.kr/api/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ apiKey: 'lunar-earth-sun', userId: 'u1', deviceId: 'd1' })
}).then(r => r.json());

// 2) ?좏겙?쇰줈 WSS ?곌껐
const ws = new WebSocket(`wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=${encodeURIComponent(tokenResp.token)}`);
ws.onopen = () => {
  ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'barcode', msg: 'CODE128-ABC-123' }));
};
ws.onmessage = (e) => console.log('server:', e.data);
```

#### ?덉젣 (Node.js)
```javascript
const fetch = require('node-fetch');
const WebSocket = require('ws');

(async () => {
  const tokenResp = await fetch('http://127.0.0.1:45444/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiKey: 'lunar-earth-sun', userId: 'u1', deviceId: 'd1' })
  }).then(r => r.json());

  const ws = new WebSocket(`wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=${encodeURIComponent(tokenResp.token)}`);
  ws.on('open', () => ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'image', imageBase64: 'data:image/png;base64,...', imageExt: 'png' })));
  ws.on('message', (m) => console.log('server:', m.toString()));
})();
```

#### ?댁쁺 ??
- ?좏겙? HMAC-SHA256?쇰줈 ?쒕챸???ъ슜???붾컮?댁뒪/留뚮즺 ?뺣낫瑜??ы븿?⑸땲??
- 諛깆뿏?쒕뒗 ?좏겙 留뚮즺 ???묒냽 嫄곕?, ?몄뀡 醫낅즺 ???좏겙 ?쒓굅濡?媛꾨떒??愿由ы빀?덈떎.
- ?꾩슂 ???좏겙 TTL/鍮꾨???`API_KEY_DEFAULT`)瑜??섍꼍蹂?섎줈 援먯껜?섏뿬 ?뚯쟾(rotate) ?꾨왂???곸슜?섏꽭??

### ???곗꽑?쒖쐞? ?섍꼍蹂??
- 留덉뒪????Base64) ?곗꽑: `API_KEY_MASTER_B64`媛 ?ㅼ젙?섏뼱 ?덉쑝硫??대? ?붿퐫?⑺빐 ?쒕챸 ?ㅻ줈 ?ъ슜?⑸땲??
- 洹??몄뿉??湲곕낯 ??臾몄옄??`API_KEY_DEFAULT`, 湲곕낯媛? `lunar-earth-sun`)???ъ슜?⑸땲??
- ?꾩옱 ?댁쁺 湲곕낯媛?
  - `API_KEY_MASTER_B64`: `bHVuYXItZWFydGgtc3Vu` ("lunar-earth-sun"??Base64)
  - `API_KEY_DEFAULT`: `lunar-earth-sun`
  - `TOKEN_TTL_MINUTES`: `120`

諛쒓툒 ???덉슜?섎뒗 apiKey 媛?
- ?됰Ц `lunar-earth-sun` ?먮뒗 Base64 ?붿퐫??寃곌낵 臾몄옄???숈씪 媛? 紐⑤몢 ?덉슜?⑸땲??

### WSS-only ?몄쬆 (REST ?녿뒗 諛⑹떇)
- 荑쇰━濡?`apiKey`, `userId`, `deviceId`瑜??꾨떖???몄쬆/?몄뀡???섎┰?⑸땲??
- URL ?뺤떇:
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1
```
- ?좏슚??`apiKey`???ㅼ쓬 以??섎굹? ?쇱튂?댁빞 ?⑸땲??
  - `API_KEY_DEFAULT`???됰Ц 媛?(`lunar-earth-sun`)
  - `API_KEY_MASTER_B64`瑜?Base64 ?붿퐫?⑺븳 臾몄옄??(?꾩옱 ?숈씪 媛?
- ?몄뀡/留뚮즺: ?쒕쾭???대??곸쑝濡?TTL(湲곕낯 120遺????곸슜???몄뀡??愿由ы빀?덈떎. ?숈씪 ???ъ슜???붾컮?댁뒪 議고빀 以묐났 ?묒냽 ??409媛 諛쒖깮?????덉뒿?덈떎.

#### ?덉젣 (釉뚮씪?곗?)
```javascript
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1');
ws.onopen = () => {
  ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'barcode', msg: 'CODE128-ABC-123' }));
};
ws.onmessage = (e) => console.log('server:', e.data);
```

#### ?덉젣 (Node.js)
```javascript
const WebSocket = require('ws');
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1');
ws.on('open', () => ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'image', imageBase64: 'data:image/png;base64,...', imageExt: 'png' })));
ws.on('message', (m) => console.log('server:', m.toString()));
```

李멸퀬: 湲곗〈 ?좏겙 諛⑹떇? ??덉쑝濡??좎??섎ŉ, `?token=<signed-token>`???듯빐 ?숈씪 ?붾뱶?ъ씤?몄뿉 ?묒냽?????덉뒿?덈떎.

### WSS 濡쒓렇???뚮줈??(Flutter ?ы븿)
- ?묒냽: `wss://server.lunarsystem.co.kr:44444/ws/sendReq`
- 濡쒓렇???붿껌(JSON):
```json
{
  "msgType": "login",
  "userId": "admin",
  "password": "admin123",
  "deviceId": "d1"
}
```
- 濡쒓렇???깃났 ?묐떟(JSON):
```json
{
  "type": "token",
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T10:00:00Z"
}
```
- ?댄썑 紐⑤뱺 硫붿떆吏??`token` ?꾨뱶瑜??ы븿???꾩넚?⑸땲??
```json
{
  "userId": "admin",
  "deviceId": "d1",
  "token": "<signed-token>",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123"
}
```

#### Flutter ?덉떆 (web_socket_channel)
```dart
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

final channel = WebSocketChannel.connect(
  Uri.parse('wss://server.lunarsystem.co.kr:44444/ws/sendReq'),
);

void loginAndSend() {
  channel.sink.add(jsonEncode({
    'msgType': 'login',
    'userId': 'admin',
    'password': 'admin123',
    'deviceId': 'd1',
  }));

  channel.stream.listen((event) {
    final msg = jsonDecode(event as String);
    if (msg['type'] == 'token') {
      final token = msg['token'];
      // send barcode
      channel.sink.add(jsonEncode({
        'userId': 'admin',
        'deviceId': 'd1',
        'token': token,
        'msgType': 'barcode',
        'msg': 'CODE128-ABC-123',
      }));
    }
  });
}
```

二쇱쓽
- ?꾩옱 ?곕え ?먭꺽(admin/admin123)? ?섍꼍蹂??`AUTH_USER`, `AUTH_PASS`濡?蹂寃?媛?ν빀?덈떎.
- 怨좎젙 ??apiKey) 湲곕컲 getToken 諛⑹떇? ?쒓굅?섏뿀?듬땲?? 諛섎뱶??`login` ??`token` ?섏떊 ??`token` ?ы븿 硫붿떆吏 ?쒖쑝濡??ъ슜?섏꽭??

蹂댁븞 李멸퀬
- WSS(TLS)濡??뷀샇?붾릺誘濡??꾩넚 以??몄텧 ?꾪뿕? ??뒿?덈떎. ?ㅻ쭔 ?대씪?댁뼵????釉뚮씪?곗?/?? 硫붾え由щ? 由щ쾭?깊빐 ?좏겙??異붿텧?섎뒗 ?됱쐞??TLS濡?諛⑹뼱?섏? ?딆뒿?덈떎.
- ?꾪솕梨?沅뚯옣: 吏㏃? TTL(?? 15~30遺?, ?좏겙 ?щ컻湲????댁쟾 ?좏겙 利됱떆 ?먭린, 湲곌린 諛붿씤???좏겙 payload??userId/deviceId ?ы븿: ?대? 援ы쁽), ?쒕쾭痢??덉씠?몃━諛??댁긽?됱쐞 ?먯?, ?꾩슂 ??硫붿떆吏??nonce/timestamp 異붽? ???쒕쾭痢??ъ궗??諛⑹? 寃??

### 諛붿퐫???대?吏 ?몄떇 ?붿껌怨?吏꾪뻾瑜??대깽??
- ?붿껌(JSON): `msgType: "image"`, `taskType: "barcode"`, `token` ?ы븿, base64 ?먮뒗 gzip+base64 ?대?吏 ?꾩넚
```json
{
  "userId": "admin",
  "deviceId": "d1",
  "token": "<signed-token>",
  "msgType": "image",
  "taskType": "barcode",
  "imageExt": "png",
  "imageBase64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k...",
  "isGzip": false
}
```
- gzip(base64) ?덉떆: `imageBase64`??gzip?쇰줈 ?뺤텞??諛붿씠?덈━瑜?base64濡??몄퐫?⑺븯???ｊ퀬 `isGzip: true` ?ㅼ젙

- ?쒕쾭媛 蹂대궡??吏꾪뻾 ?대깽??JSON)
```json
{
  "type": "progress",
  "jobId": "c2a7...",
  "status": "uploading",
  "progress": 5,
  "etaSeconds": 5,
  "filePath": null,
  "error": null
}
```
- ?곹깭 媛? `uploading` ??`processing` ??`finish` (?먮뒗 `fail`)
- 二쇨린: ?곹깭 蹂寃????먮뒗 理쒖냼 1珥덈쭏???꾩넚
- ?꾨즺 ?덉떆
```json
{
  "type": "progress",
  "jobId": "c2a7...",
  "status": "finish",
  "progress": 100,
  "etaSeconds": 0,
  "filePath": "/public/files/20250101_120000_123_admin_d1.png",
  "error": null
}
```

### DB 湲곕줉
- 而щ젆?? `barcodeJobs`
- ?꾨뱶: `jobId, userId, deviceId, status, progressPercent, etaSeconds, filePath, error, createdAt, updatedAt`

### ?낅줈???щ㎎
- 湲곕낯: `imageBase64` (data URI 媛??
- ?뺤텞: `isGzip: true`?대㈃ gzip ?댁젣 ?????

### 鍮꾨?踰덊샇 ?ъ꽕??WS)
1) 肄붾뱶 諛쒖넚
```json
{ "msgType": "emailSend", "email": "user@example.com" }
```
2) 肄붾뱶 寃利??좏깮???뺤씤)
```json
{ "msgType": "emailVerify", "email": "user@example.com", "code": "123456" }
```
3) ?ъ꽕??
```json
{ "msgType": "passwordReset", "email": "user@example.com", "code": "123456", "password": "NewP@ss!" }
```
- ?깃났 ?묐떟: "password_reset_ok"
- ?ъ꽕????湲곗〈 ?몄뀡? 紐⑤몢 臾댄슚?붾맗?덈떎.

### 援ш? 濡쒓렇???곕룞

- 吏??諛⑹떇: 釉뚮씪?곗? OAuth 肄쒕갚 ?먮뒗 `id_token` 吏곸젒 ?꾨떖(WS)

#### 1) 釉뚮씪?곗? OAuth 肄쒕갚 ?뚮줈??
- ?쒖옉 URL: `GET /auth/google/login`
  - ?좏깮: `?returnTo=<URL>`??state濡??몄퐫?⑺빐 蹂댁〈
- 肄쒕갚: `GET /auth/google/callback?code=...`
  - ?묐떟(JSON):
```json
{ "token": "<signed-token>", "expiresAtUtc": "2025-09-13T10:00:00Z", "email": "user@example.com", "name": "User" }
```
- 諛쏆? `token`???댄썑 WSS 硫붿떆吏??`token` ?꾨뱶???ы븿?섏뿬 ?ъ슜?⑸땲??

?섍꼍蹂??
- `GOOGLE_CLIENT_IDS`: ?덉슜 ?대씪?댁뼵??ID 紐⑸줉(肄ㅻ쭏 援щ텇). 誘몄?????湲곕낯媛?1媛??ъ슜
- `GOOGLE_CLIENT_ID`: ?⑥씪 ?대씪?댁뼵??ID (?좏겙 援먰솚???ъ슜)
- `GOOGLE_CLIENT_SECRET`: 援ш? OAuth ?대씪?댁뼵???쒗겕由?
- `GOOGLE_REDIRECT_URI`: 肄쒕갚 URL (?? `https://lunarsystem.co.kr/auth/google/callback`)
- `GOOGLE_CREDENTIALS_JSON_PATH`: 援ш? ?먭꺽?뚯씪(JSON) 寃쎈줈. 吏????`client_secret`, `redirect_uris[0]` ?먮룞 諛섏쁺

?ㅼ젙 ?덉떆
```bash
# ?쒖뒪???꾩빱 ?섍꼍???곸슜??媛??덉떆
export GOOGLE_CLIENT_IDS="257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com"
export GOOGLE_CLIENT_ID="257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="<YOUR_CLIENT_SECRET>"
export GOOGLE_REDIRECT_URI="https://lunarsystem.co.kr/auth/google/callback"
export GOOGLE_CREDENTIALS_JSON_PATH="/var/lunarsystem/client_secret_2_257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com.json"
```

Docker Compose ?덉떆 (諛쒖톸)
```yaml
services:
  be:
    environment:
      - GOOGLE_CLIENT_IDS=257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com
      - GOOGLE_CLIENT_ID=257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com
      - GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
      - GOOGLE_REDIRECT_URI=https://lunarsystem.co.kr/auth/google/callback
      - GOOGLE_CREDENTIALS_JSON_PATH=/var/lunarsystem/client_secret_2_257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com.json
```

#### 2) `id_token` 吏곸젒 ?꾨떖(WS)
- ?대씪?댁뼵?몄뿉??援ш? 濡쒓렇??SDK濡?`id_token`??痍⑤뱷 ?? ?꾨옒 硫붿떆吏濡??꾩넚?⑸땲??
```json
{
  "msgType": "googleLogin",
  "msg": "<google-id-token>",
  "deviceId": "d1"
}
```
- ?깃났 ???묐떟(JSON):
```json
{ "type": "token", "token": "<signed-token>", "expiresAtUtc": "2025-09-13T10:00:00Z" }
```
