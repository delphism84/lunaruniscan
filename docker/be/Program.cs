using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Collections.Concurrent;
using System.IO.Compression;
using Microsoft.Extensions.FileProviders;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Driver;
using BCryptNet = BCrypt.Net.BCrypt;
using Google.Apis.Auth;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

var builder = WebApplication.CreateBuilder(args);

string mongoUri = Environment.GetEnvironmentVariable("MONGO_URI") ?? "mongodb://localhost:27017";
string mongoDbName = Environment.GetEnvironmentVariable("MONGO_DB") ?? "uniscan";
string apiKeyDefault = Environment.GetEnvironmentVariable("API_KEY_DEFAULT") ?? "lunar-earth-sun";
string? masterKeyB64 = Environment.GetEnvironmentVariable("API_KEY_MASTER_B64");
int tokenTtlMinutes = int.TryParse(Environment.GetEnvironmentVariable("TOKEN_TTL_MINUTES"), out var ttl) ? ttl : 120;
// simple demo credentials (replace with real user store later)
string authUser = Environment.GetEnvironmentVariable("AUTH_USER") ?? "admin";
string authPass = Environment.GetEnvironmentVariable("AUTH_PASS") ?? "admin123";

// SMTP settings
string smtpHost = Environment.GetEnvironmentVariable("SMTP_HOST") ?? "smtp.worksmobile.com";
int smtpPort = int.TryParse(Environment.GetEnvironmentVariable("SMTP_PORT"), out var sp) ? sp : 465;
string smtpUser = Environment.GetEnvironmentVariable("SMTP_USER") ?? "lunar@lunarsystem.co.kr";
string smtpPass = Environment.GetEnvironmentVariable("SMTP_PASS") ?? "";
string smtpFrom = Environment.GetEnvironmentVariable("SMTP_FROM") ?? smtpUser;

// Google OAuth settings (env takes priority; optional fallback to credentials json)
string googleClientId = Environment.GetEnvironmentVariable("GOOGLE_CLIENT_ID") ?? "257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com";
string googleClientSecret = Environment.GetEnvironmentVariable("GOOGLE_CLIENT_SECRET") ?? string.Empty;
string googleRedirectUri = Environment.GetEnvironmentVariable("GOOGLE_REDIRECT_URI") ?? "https://lunarsystem.co.kr/auth/google/callback";
string? googleCredsPath = Environment.GetEnvironmentVariable("GOOGLE_CREDENTIALS_JSON_PATH");
try
{
    if (string.IsNullOrWhiteSpace(googleClientSecret) && !string.IsNullOrWhiteSpace(googleCredsPath) && File.Exists(googleCredsPath))
    {
        using var fs = File.OpenRead(googleCredsPath);
        using var doc = JsonDocument.Parse(fs);
        if (doc.RootElement.TryGetProperty("web", out var web))
        {
            if (string.IsNullOrWhiteSpace(googleClientId) && web.TryGetProperty("client_id", out var idEl))
                googleClientId = idEl.GetString() ?? googleClientId;
            if (web.TryGetProperty("client_secret", out var secEl))
                googleClientSecret = secEl.GetString() ?? googleClientSecret;
            if (web.TryGetProperty("redirect_uris", out var urisEl) && urisEl.ValueKind == JsonValueKind.Array && urisEl.GetArrayLength() > 0)
            {
                var uri0 = urisEl[0].GetString();
                if (!string.IsNullOrWhiteSpace(uri0)) googleRedirectUri = uri0!;
            }
        }
    }
}
catch { }

// signing key priority: MASTER (base64) > DEFAULT (utf8)
byte[] tokenSigningKeyBytes;
string decodedMasterString = apiKeyDefault;
if (!string.IsNullOrWhiteSpace(masterKeyB64))
{
    try
    {
        tokenSigningKeyBytes = Convert.FromBase64String(masterKeyB64);
        decodedMasterString = Encoding.UTF8.GetString(tokenSigningKeyBytes);
    }
    catch
    {
        tokenSigningKeyBytes = Encoding.UTF8.GetBytes(apiKeyDefault);
        decodedMasterString = apiKeyDefault;
    }
}
else
{
    tokenSigningKeyBytes = Encoding.UTF8.GetBytes(apiKeyDefault);
}

builder.Services.AddSingleton<IMongoClient>(_ => new MongoClient(mongoUri));
builder.Services.AddSingleton(serviceProvider => {
    var client = serviceProvider.GetRequiredService<IMongoClient>();
    return client.GetDatabase(mongoDbName);
});

var app = builder.Build();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30)
});

// ensure public/files exists and serve as /public
var publicRoot = Path.Combine(app.Environment.ContentRootPath, "public");
var publicFiles = Path.Combine(publicRoot, "files");
Directory.CreateDirectory(publicFiles);
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(publicRoot),
    RequestPath = "/public"
});

// OAuth: Google redirect to consent screen
app.MapGet("/auth/google/login", async (HttpContext ctx) =>
{
    var returnTo = ctx.Request.Query["returnTo"].ToString();
    var state = string.IsNullOrWhiteSpace(returnTo) ? "" : Convert.ToBase64String(Encoding.UTF8.GetBytes(returnTo));
    string authUrl =
        "https://accounts.google.com/o/oauth2/v2/auth" +
        "?response_type=code" +
        "&client_id=" + Uri.EscapeDataString(googleClientId) +
        "&redirect_uri=" + Uri.EscapeDataString(googleRedirectUri) +
        "&scope=" + Uri.EscapeDataString("openid email profile") +
        "&access_type=offline" +
        "&prompt=consent" +
        "&state=" + Uri.EscapeDataString(state);
    ctx.Response.Redirect(authUrl);
});

// OAuth: Google callback (code -> token -> app token)
app.MapGet("/auth/google/callback", async (HttpContext context) =>
{
    var code = context.Request.Query["code"].ToString();
    if (string.IsNullOrWhiteSpace(code)) return Results.BadRequest(new { error = "missing_code" });
    if (string.IsNullOrWhiteSpace(googleClientId) || string.IsNullOrWhiteSpace(googleClientSecret))
        return Results.StatusCode(500);

    using var http = new HttpClient();
    var post = new FormUrlEncodedContent(new Dictionary<string, string>
    {
        ["code"] = code,
        ["client_id"] = googleClientId,
        ["client_secret"] = googleClientSecret,
        ["redirect_uri"] = googleRedirectUri,
        ["grant_type"] = "authorization_code"
    });
    HttpResponseMessage resp;
    try
    {
        resp = await http.PostAsync("https://oauth2.googleapis.com/token", post);
    }
    catch (Exception ex)
    {
        return Results.StatusCode(502);
    }
    var json = await resp.Content.ReadAsStringAsync();
    if (!resp.IsSuccessStatusCode) return Results.StatusCode(502);

    using var tokenDoc = JsonDocument.Parse(json);
    if (!tokenDoc.RootElement.TryGetProperty("id_token", out var idTokEl)) return Results.StatusCode(502);
    var idToken = idTokEl.GetString() ?? string.Empty;

    try
    {
        var allowedClientIdsEnv = Environment.GetEnvironmentVariable("GOOGLE_CLIENT_IDS");
        var allowedClientIds = !string.IsNullOrWhiteSpace(allowedClientIdsEnv)
            ? allowedClientIdsEnv.Split(',', StringSplitOptions.RemoveEmptyEntries)
            : new[] { googleClientId };
        var settings = new GoogleJsonWebSignature.ValidationSettings { Audience = allowedClientIds };
        var payload = await GoogleJsonWebSignature.ValidateAsync(idToken, settings);

        var email = payload.Email;
        var usersCol = GetUsers(app);
        var user = await usersCol.Find(x => x.Email == email).FirstOrDefaultAsync();
        if (user == null)
        {
            user = new AppUser
            {
                Email = email,
                UserId = email,
                DisplayName = payload.Name,
                PasswordHash = string.Empty,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
                GoogleSub = payload.Subject
            };
            await usersCol.InsertOneAsync(user);
        }

        var now = DateTimeOffset.UtcNow;
        var exp = now.AddMinutes(tokenTtlMinutes);
        var tok = TokenHelper.GenerateToken(tokenSigningKeyBytes, user.UserId ?? user.Email, null, now, exp);
        await GetSessions(app).InsertOneAsync(new AuthSession { Token = tok, UserId = user.UserId ?? user.Email, DeviceId = null, ExpiresAtUtc = exp.UtcDateTime, CreatedAt = DateTime.UtcNow, Provider = "google" });
        await GetLoginLogs(app).InsertOneAsync(new LoginLog { Email = email, Success = true, Provider = "google", Ip = context.Connection.RemoteIpAddress?.ToString(), CreatedAt = DateTime.UtcNow });

        return Results.Json(new { token = tok, expiresAtUtc = exp.UtcDateTime, email = user.Email, name = user.DisplayName });
    }
    catch (Exception ex)
    {
        var msg = ex.Message;
        return Results.Json(new { error = "google_login_failed", message = msg }, statusCode: 401);
    }
});

IMongoCollection<RxLog> GetCollection(WebApplication app) => app.Services.GetRequiredService<IMongoDatabase>().GetCollection<RxLog>("rxLogs");
IMongoCollection<BarcodeJob> GetJobs(WebApplication app) => app.Services.GetRequiredService<IMongoDatabase>().GetCollection<BarcodeJob>("barcodeJobs");
IMongoCollection<AppUser> GetUsers(WebApplication app) => app.Services.GetRequiredService<IMongoDatabase>().GetCollection<AppUser>("users");
IMongoCollection<AuthSession> GetSessions(WebApplication app) => app.Services.GetRequiredService<IMongoDatabase>().GetCollection<AuthSession>("sessions");
IMongoCollection<LoginLog> GetLoginLogs(WebApplication app) => app.Services.GetRequiredService<IMongoDatabase>().GetCollection<LoginLog>("loginLogs");

// in-memory session store (token -> session)
var activeSessions = new ConcurrentDictionary<string, SessionInfo>();

app.MapPost("/api/rx", async (RxLogInput input, HttpContext ctx) =>
{
    var collection = GetCollection(app);

    var rx = new RxLog
    {
        Id = ObjectId.GenerateNewId(),
        UserId = input.UserId,
        DeviceId = input.DeviceId,
        RxTime = input.RxTime == default ? DateTime.UtcNow : input.RxTime.ToUniversalTime(),
        Msg = input.Msg,
        Ack = input.Ack ?? 0,
        CreatedAt = DateTime.UtcNow
    };

    await collection.InsertOneAsync(rx);
    return Results.Created($"/api/rx/{rx.Id}", new { id = rx.Id.ToString() });
});

// (kept for compatibility but can be removed later) Token issuance via REST
app.MapPost("/api/token", async (TokenRequest req) =>
{
    return Results.StatusCode(410); // Gone - use WS login instead
});

app.Map("/ws/sendReq", async context =>
{
    // Auth priorities (handshake): token via query. If none, allow anonymous; client must login via WS message.
    var token = context.Request.Query["token"].ToString();

    bool isAuthenticated = false;
    DateTime expiresAtUtc = DateTime.MinValue;
    string sessionKey = $"ANON:{Guid.NewGuid():n}";

    if (!string.IsNullOrWhiteSpace(token))
    {
        var validate = TokenHelper.ValidateToken(tokenSigningKeyBytes, token);
        if (validate.IsValid)
        {
            isAuthenticated = true;
            expiresAtUtc = validate.ExpiresAtUtc;
            sessionKey = token;
        }
    }

    if (isAuthenticated)
    {
        var sessionId = Guid.NewGuid().ToString("n");
        var session = new SessionInfo { Token = sessionKey, ExpiresAtUtc = expiresAtUtc, SessionId = sessionId };
        if (!activeSessions.TryAdd(sessionKey, session))
        {
            context.Response.StatusCode = 409;
            await context.Response.WriteAsync("session already in use");
            return;
        }
    }

    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = 400;
        await context.Response.WriteAsync("WebSocket required");
        if (isAuthenticated) activeSessions.TryRemove(sessionKey, out _);
        return;
    }

    using var ws = await context.WebSockets.AcceptWebSocketAsync();
    var buffer = new byte[128 * 1024];
    var collection = GetCollection(app);

    while (ws.State == WebSocketState.Open)
    {
        // accumulate fragments
        var sb = new StringBuilder();
        WebSocketReceiveResult? result;
        do
        {
            result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            if (result.MessageType == WebSocketMessageType.Close)
        {
            await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
                activeSessions.TryRemove(sessionKey, out _);
                return;
            }
            sb.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
        } while (!result.EndOfMessage);

        var text = sb.ToString();
        try
        {
            var dto = JsonSerializer.Deserialize<WsMessageInput>(text) ?? new WsMessageInput();

            // WS login flow: client sends { msgType: "login", userId, password, deviceId }
            if (string.Equals(dto.MsgType, "login", StringComparison.OrdinalIgnoreCase))
            {
                var usersCol = GetUsers(app);
                var user = await usersCol.Find(x => x.Email == dto.UserId || x.UserId == dto.UserId).FirstOrDefaultAsync();
                bool ok = false;
                if (user != null && !string.IsNullOrWhiteSpace(dto.Password))
                {
                    ok = BCryptNet.Verify(dto.Password, user.PasswordHash);
                }
                if (!ok)
                {
                    var err = Encoding.UTF8.GetBytes("unauthorized");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    await GetLoginLogs(app).InsertOneAsync(new LoginLog { Email = dto.UserId ?? string.Empty, Success = false, Ip = context.Connection.RemoteIpAddress?.ToString(), CreatedAt = DateTime.UtcNow });
                    continue;
                }
                var now = DateTimeOffset.UtcNow;
                var exp = now.AddMinutes(tokenTtlMinutes);
                var tok = TokenHelper.GenerateToken(tokenSigningKeyBytes, user.UserId ?? user.Email, dto.DeviceId, now, exp);
                // mark this connection authenticated
                isAuthenticated = true;
                expiresAtUtc = exp.UtcDateTime;
                sessionKey = tok;
                await GetSessions(app).InsertOneAsync(new AuthSession { Token = tok, UserId = user.UserId ?? user.Email, DeviceId = dto.DeviceId, ExpiresAtUtc = exp.UtcDateTime, CreatedAt = DateTime.UtcNow });
                await GetLoginLogs(app).InsertOneAsync(new LoginLog { Email = user.Email, Success = true, Ip = context.Connection.RemoteIpAddress?.ToString(), CreatedAt = DateTime.UtcNow });
                var resp = JsonSerializer.Serialize(new { type = "token", token = tok, expiresAtUtc = exp.UtcDateTime });
                var respBytes = Encoding.UTF8.GetBytes(resp);
                await ws.SendAsync(new ArraySegment<byte>(respBytes), WebSocketMessageType.Text, true, CancellationToken.None);
                continue;
            }

            // WS signup via email code
            if (string.Equals(dto.MsgType, "userSignUp", StringComparison.OrdinalIgnoreCase))
            {
                var email = dto.Email;
                var code = dto.Code;
                var password = dto.Password;
                if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(password))
                {
                    var err = Encoding.UTF8.GetBytes("signup_invalid");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var codes = app.Services.GetRequiredService<IMongoDatabase>().GetCollection<EmailCode>("emailCodes");
                var found = await codes.Find(x => x.Email == email).SortByDescending(x => x.CreatedAt).FirstOrDefaultAsync();
                if (found == null || found.Code != code || found.ExpiresAt <= DateTime.UtcNow)
                {
                    var err = Encoding.UTF8.GetBytes("signup_code_invalid");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var usersCol = GetUsers(app);
                var exists = await usersCol.Find(x => x.Email == email).AnyAsync();
                if (exists)
                {
                    var err = Encoding.UTF8.GetBytes("signup_exists");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var user = new AppUser
                {
                    Email = email,
                    UserId = email,
                    DisplayName = dto.Msg ?? email,
                    PasswordHash = BCryptNet.HashPassword(password),
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                await usersCol.InsertOneAsync(user);
                var okSignup = Encoding.UTF8.GetBytes("signup_ok");
                await ws.SendAsync(new ArraySegment<byte>(okSignup), WebSocketMessageType.Text, true, CancellationToken.None);
                continue;
            }

            // WS logout (invalidate session token)
            if (string.Equals(dto.MsgType, "logout", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.IsNullOrWhiteSpace(dto.Token))
                {
                    await GetSessions(app).DeleteOneAsync(s => s.Token == dto.Token);
                }
                var ok = Encoding.UTF8.GetBytes("logout_ok");
                await ws.SendAsync(new ArraySegment<byte>(ok), WebSocketMessageType.Text, true, CancellationToken.None);
                continue;
            }

            // Google login with ID token
            if (string.Equals(dto.MsgType, "googleLogin", StringComparison.OrdinalIgnoreCase))
            {
                var idToken = dto.Msg ?? string.Empty;
                try
                {
                    var allowedClientIdsEnv = Environment.GetEnvironmentVariable("GOOGLE_CLIENT_IDS");
                    var allowedClientIds = !string.IsNullOrWhiteSpace(allowedClientIdsEnv)
                        ? allowedClientIdsEnv.Split(',', StringSplitOptions.RemoveEmptyEntries)
                        : new[] { "257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com" };
                    var settings = new GoogleJsonWebSignature.ValidationSettings
                    {
                        Audience = allowedClientIds
                    };
                    var payload = await GoogleJsonWebSignature.ValidateAsync(idToken, settings);
                    var email = payload.Email;
                    var usersCol = GetUsers(app);
                    var user = await usersCol.Find(x => x.Email == email).FirstOrDefaultAsync();
                    if (user == null)
                    {
                        user = new AppUser
                        {
                            Email = email,
                            UserId = email,
                            DisplayName = payload.Name,
                            PasswordHash = string.Empty,
                            CreatedAt = DateTime.UtcNow,
                            UpdatedAt = DateTime.UtcNow,
                            GoogleSub = payload.Subject
                        };
                        await usersCol.InsertOneAsync(user);
                    }
                    var now = DateTimeOffset.UtcNow;
                    var exp = now.AddMinutes(tokenTtlMinutes);
                    var tok = TokenHelper.GenerateToken(tokenSigningKeyBytes, user.UserId ?? user.Email, dto.DeviceId, now, exp);
                    await GetSessions(app).InsertOneAsync(new AuthSession { Token = tok, UserId = user.UserId ?? user.Email, DeviceId = dto.DeviceId, ExpiresAtUtc = exp.UtcDateTime, CreatedAt = DateTime.UtcNow, Provider = "google" });
                    await GetLoginLogs(app).InsertOneAsync(new LoginLog { Email = email, Success = true, Provider = "google", Ip = context.Connection.RemoteIpAddress?.ToString(), CreatedAt = DateTime.UtcNow });
                    var resp = JsonSerializer.Serialize(new { type = "token", token = tok, expiresAtUtc = exp.UtcDateTime });
                    var respBytes = Encoding.UTF8.GetBytes(resp);
                    await ws.SendAsync(new ArraySegment<byte>(respBytes), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                catch (Exception ex)
                {
                    var err = Encoding.UTF8.GetBytes($"google_login_failed:{ex.Message}");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                continue;
            }

            // For non-auth messages, require token (query or body)
            string? tokenInMsg = dto.Token;
            bool allowByToken = false;
            if (!string.IsNullOrWhiteSpace(tokenInMsg))
            {
                var v = TokenHelper.ValidateToken(tokenSigningKeyBytes, tokenInMsg);
                allowByToken = v.IsValid;
            }
            else if (isAuthenticated && expiresAtUtc > DateTime.UtcNow)
            {
                allowByToken = true; // authenticated in this connection by login
            }
            if (!allowByToken)
            {
                // allow email flows without token
                if (!string.Equals(dto.MsgType, "emailSend", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(dto.MsgType, "emailVerify", StringComparison.OrdinalIgnoreCase))
                {
                    var err = Encoding.UTF8.GetBytes("unauthorized");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
            }

            // email send (signup/verification/reset)
            if (string.Equals(dto.MsgType, "emailSend", StringComparison.OrdinalIgnoreCase))
            {
                var code = new Random().Next(100000, 999999).ToString();
                var email = dto.Email;
                if (string.IsNullOrWhiteSpace(email))
                {
                    var err = Encoding.UTF8.GetBytes("email required");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }

                try
                {
                    var message = new MimeMessage();
                    message.From.Add(MailboxAddress.Parse(smtpFrom));
                    message.To.Add(MailboxAddress.Parse(email));
                    message.Subject = "Your verification code";
                    message.Body = new TextPart("plain") { Text = $"Your code is {code}. It expires in 10 minutes." };

                    using var client = new SmtpClient();
                    var secure = smtpPort == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
                    await client.ConnectAsync(smtpHost, smtpPort, secure);
                    await client.AuthenticateAsync(smtpUser, smtpPass);
                    await client.SendAsync(message);
                    await client.DisconnectAsync(true);

                    var codes = app.Services.GetRequiredService<IMongoDatabase>().GetCollection<EmailCode>("emailCodes");
                    var doc = new EmailCode { Email = email, Code = code, ExpiresAt = DateTime.UtcNow.AddMinutes(10), CreatedAt = DateTime.UtcNow };
                    await codes.InsertOneAsync(doc);

                    var ok = Encoding.UTF8.GetBytes("email_sent");
                    await ws.SendAsync(new ArraySegment<byte>(ok), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                catch (Exception ex)
                {
                    var err = Encoding.UTF8.GetBytes($"email_error:{ex.Message}");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                continue;
            }

            // email verify
            if (string.Equals(dto.MsgType, "emailVerify", StringComparison.OrdinalIgnoreCase))
            {
                var email = dto.Email;
                var code = dto.Code;
                if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(code))
                {
                    var err = Encoding.UTF8.GetBytes("email_and_code_required");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var codes = app.Services.GetRequiredService<IMongoDatabase>().GetCollection<EmailCode>("emailCodes");
                var found = await codes.Find(x => x.Email == email).SortByDescending(x => x.CreatedAt).FirstOrDefaultAsync();
                if (found != null && found.Code == code && found.ExpiresAt > DateTime.UtcNow)
                {
                    var ok = Encoding.UTF8.GetBytes("email_verified");
                    await ws.SendAsync(new ArraySegment<byte>(ok), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                else
                {
                    var err = Encoding.UTF8.GetBytes("email_verify_failed");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                }
                continue;
            }

            // password reset: { msgType: "passwordReset", email, code, password }
            if (string.Equals(dto.MsgType, "passwordReset", StringComparison.OrdinalIgnoreCase))
            {
                var email = dto.Email;
                var code = dto.Code;
                var newPassword = dto.Password;
                if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(newPassword))
                {
                    var err = Encoding.UTF8.GetBytes("password_reset_invalid");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var codes = app.Services.GetRequiredService<IMongoDatabase>().GetCollection<EmailCode>("emailCodes");
                var found = await codes.Find(x => x.Email == email).SortByDescending(x => x.CreatedAt).FirstOrDefaultAsync();
                if (found == null || found.Code != code || found.ExpiresAt <= DateTime.UtcNow)
                {
                    var err = Encoding.UTF8.GetBytes("password_reset_code_invalid");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }

                var usersCol = GetUsers(app);
                var user = await usersCol.Find(x => x.Email == email).FirstOrDefaultAsync();
                if (user == null)
                {
                    var err = Encoding.UTF8.GetBytes("password_reset_user_not_found");
                    await ws.SendAsync(new ArraySegment<byte>(err), WebSocketMessageType.Text, true, CancellationToken.None);
                    continue;
                }
                var newHash = BCryptNet.HashPassword(newPassword);
                var update = Builders<AppUser>.Update
                    .Set(u => u.PasswordHash, newHash)
                    .Set(u => u.UpdatedAt, DateTime.UtcNow);
                await usersCol.UpdateOneAsync(x => x.Id == user.Id, update);

                // invalidate sessions for this user
                await GetSessions(app).DeleteManyAsync(s => s.UserId == (user.UserId ?? user.Email));

                var ok = Encoding.UTF8.GetBytes("password_reset_ok");
                await ws.SendAsync(new ArraySegment<byte>(ok), WebSocketMessageType.Text, true, CancellationToken.None);
                continue;
            }

            // barcode image recognition request with progress events
            if (string.Equals(dto.MsgType, "image", StringComparison.OrdinalIgnoreCase)
                && string.Equals(dto.TaskType, "barcode", StringComparison.OrdinalIgnoreCase))
            {
                var jobsCol = GetJobs(app);
                var jobId = Guid.NewGuid().ToString("n");

                async Task sendProgress(string status, int progress, int etaSeconds, string? fileRel = null, string? error = null)
                {
                    var payload = new
                    {
                        type = "progress",
                        jobId,
                        status,
                        progress,
                        etaSeconds,
                        filePath = fileRel,
                        error
                    };
                    var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(payload));
                    await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
                }

                async Task upsertJob(string status, int progress, int etaSeconds, string? fileAbs, string? fileRel, string? error)
                {
                    var update = Builders<BarcodeJob>.Update
                        .SetOnInsert(j => j.JobId, jobId)
                        .Set(j => j.UserId, dto.UserId)
                        .Set(j => j.DeviceId, dto.DeviceId)
                        .Set(j => j.Status, status)
                        .Set(j => j.ProgressPercent, progress)
                        .Set(j => j.EtaSeconds, etaSeconds)
                        .Set(j => j.FilePath, fileRel)
                        .Set(j => j.Error, error)
                        .Set(j => j.UpdatedAt, DateTime.UtcNow)
                        .SetOnInsert(j => j.CreatedAt, DateTime.UtcNow);
                    await jobsCol.UpdateOneAsync(j => j.JobId == jobId, update, new UpdateOptions { IsUpsert = true });
                }

                // 1) uploading
                await upsertJob("uploading", 5, 5, null, null, null);
                await sendProgress("uploading", 5, 5, null, null);

                // decode and save (support gzip+base64)
                byte[] imgBytes;
                try
                {
                    var base64 = dto.ImageBase64 ?? dto.Msg;
                    if (string.IsNullOrWhiteSpace(base64)) throw new Exception("no image");
                    var commaIdx = base64.IndexOf(',');
                    if (commaIdx >= 0 && base64[..commaIdx].Contains("base64", StringComparison.OrdinalIgnoreCase))
                        base64 = base64[(commaIdx + 1)..];
                    var raw = Convert.FromBase64String(base64);
                    if (dto.IsGzip == true)
                    {
                        using var ms = new MemoryStream(raw);
                        using var gz = new GZipStream(ms, CompressionMode.Decompress);
                        using var outMs = new MemoryStream();
                        await gz.CopyToAsync(outMs);
                        imgBytes = outMs.ToArray();
                    }
                    else
                    {
                        imgBytes = raw;
                    }
                }
                catch (Exception ex)
                {
                    await upsertJob("fail", 0, 0, null, null, ex.Message);
                    await sendProgress("fail", 0, 0, null, ex.Message);
                    continue;
                }

                var ext = WsHelpers.NormalizeExt(dto.ImageExt);
                var fileName = WsHelpers.GenerateFileName(dto.UserId, dto.DeviceId, ext);
                var absPath = Path.Combine(publicFiles, fileName);
                await File.WriteAllBytesAsync(absPath, imgBytes);
                var relPath = $"/public/files/{fileName}";

                await upsertJob("processing", 30, 3, absPath, relPath, null);
                await sendProgress("processing", 30, 3, relPath, null);

                // simulate processing progress
                for (int p = 40; p <= 90; p += 10)
                {
                    await Task.Delay(1000);
                    await upsertJob("processing", p, Math.Max(0, 100 - p) / 10, absPath, relPath, null);
                    await sendProgress("processing", p, Math.Max(0, 100 - p) / 10, relPath, null);
                }

                // finish
                await upsertJob("finish", 100, 0, absPath, relPath, null);
                await sendProgress("finish", 100, 0, relPath, null);
                continue;
            }

            string? savedRelativePath = null;
            if (string.Equals(dto.MsgType, "image", StringComparison.OrdinalIgnoreCase))
            {
                var base64 = dto.ImageBase64 ?? dto.Msg;
                if (!string.IsNullOrWhiteSpace(base64))
                {
                    var commaIdx = base64.IndexOf(',');
                    if (commaIdx >= 0 && base64[..commaIdx].Contains("base64", StringComparison.OrdinalIgnoreCase))
                    {
                        base64 = base64[(commaIdx + 1)..];
                    }
                    byte[] bytes = Convert.FromBase64String(base64);
                    var ext = WsHelpers.NormalizeExt(dto.ImageExt);
                    var fileName = WsHelpers.GenerateFileName(dto.UserId, dto.DeviceId, ext);
                    var absPath = Path.Combine(publicFiles, fileName);
                    await File.WriteAllBytesAsync(absPath, bytes);
                    savedRelativePath = $"/public/files/{fileName}";
                }
            }
            var rx = new RxLog
            {
                Id = ObjectId.GenerateNewId(),
                UserId = dto.UserId,
                DeviceId = dto.DeviceId,
                RxTime = dto.RxTime == default ? DateTime.UtcNow : dto.RxTime.ToUniversalTime(),
                Msg = dto.Msg ?? (dto.MsgType == "image" ? "image" : text),
                Ack = dto.Ack ?? 0,
                MsgType = dto.MsgType,
                FilePath = savedRelativePath,
                CreatedAt = DateTime.UtcNow
            };
            await collection.InsertOneAsync(rx);
        }
        catch
        {
            var fallback = new RxLog
            {
                Id = ObjectId.GenerateNewId(),
                UserId = null,
                DeviceId = null,
                RxTime = DateTime.UtcNow,
                Msg = text,
                Ack = 0,
                MsgType = null,
                FilePath = null,
                CreatedAt = DateTime.UtcNow
            };
            await collection.InsertOneAsync(fallback);
        }

        var okMsg = Encoding.UTF8.GetBytes("ok");
        await ws.SendAsync(new ArraySegment<byte>(okMsg), WebSocketMessageType.Text, true, CancellationToken.None);
    }
    activeSessions.TryRemove(sessionKey, out _);
});

app.Run();

public sealed class RxLogInput
{
    public string? UserId { get; set; }
    public string? DeviceId { get; set; }
    public DateTime RxTime { get; set; }
    public string? Msg { get; set; }
    public int? Ack { get; set; }
}

public sealed class AppUser
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("userId")]
    public string? UserId { get; set; }

    [BsonElement("email")]
    public string Email { get; set; } = string.Empty;

    [BsonElement("displayName")]
    public string? DisplayName { get; set; }

    [BsonElement("passwordHash")]
    public string PasswordHash { get; set; } = string.Empty;

    [BsonElement("googleSub")]
    public string? GoogleSub { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }

    [BsonElement("updatedAt")]
    public DateTime UpdatedAt { get; set; }
}

public sealed class AuthSession
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("token")]
    public string Token { get; set; } = string.Empty;

    [BsonElement("userId")]
    public string UserId { get; set; } = string.Empty;

    [BsonElement("deviceId")]
    public string? DeviceId { get; set; }

    [BsonElement("provider")]
    public string? Provider { get; set; }

    [BsonElement("expiresAtUtc")]
    public DateTime ExpiresAtUtc { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }
}

public sealed class LoginLog
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("email")]
    public string Email { get; set; } = string.Empty;

    [BsonElement("provider")]
    public string? Provider { get; set; }

    [BsonElement("success")]
    public bool Success { get; set; }

    [BsonElement("ip")]
    public string? Ip { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }
}

public sealed class RxLog
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("userId")]
    public string? UserId { get; set; }

    [BsonElement("deviceId")]
    public string? DeviceId { get; set; }

    [BsonElement("rxTime")]
    public DateTime RxTime { get; set; }

    [BsonElement("msg")]
    public string? Msg { get; set; }

    [BsonElement("ack")]
    public int Ack { get; set; }

    [BsonElement("msgType")]
    public string? MsgType { get; set; }

    [BsonElement("filePath")]
    public string? FilePath { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }
}

public sealed class TokenRequest
{
    public string ApiKey { get; set; } = string.Empty;
    public string? UserId { get; set; }
    public string? DeviceId { get; set; }
}

public sealed class TokenResponse
{
    public string Token { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
}

public sealed class WsMessageInput
{
    public string? UserId { get; set; }
    public string? DeviceId { get; set; }
    public string? Password { get; set; }
    public DateTime RxTime { get; set; }
    public string? Msg { get; set; }
    public string? MsgType { get; set; }
    public string? TaskType { get; set; } // e.g., "barcode" when msgType == "image"
    public string? ImageBase64 { get; set; }
    public string? ImageExt { get; set; }
    public int? Ack { get; set; }
    public string? ApiKey { get; set; }
    public string? Token { get; set; }
    public bool? IsGzip { get; set; }
    public string? Email { get; set; }
    public string? Code { get; set; }
}

internal static class WsHelpers
{
    public static string NormalizeExt(string? ext)
    {
        ext = (ext ?? "").Trim().Trim('.');
        if (string.IsNullOrWhiteSpace(ext)) return "jpg";
        ext = Regex.Replace(ext, "[^a-zA-Z0-9]", "").ToLowerInvariant();
        return ext switch { "jpeg" => "jpg", _ => ext };
    }

    public static string GenerateFileName(string? userId, string? deviceId, string ext)
    {
        var ts = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss_fff");
        var u = string.IsNullOrWhiteSpace(userId) ? "u" : Regex.Replace(userId, "[^a-zA-Z0-9]", "");
        var d = string.IsNullOrWhiteSpace(deviceId) ? "d" : Regex.Replace(deviceId, "[^a-zA-Z0-9]", "");
        return $"{ts}_{u}_{d}.{ext}";
    }
}

public sealed class SessionInfo
{
    public string Token { get; set; } = string.Empty;
    public string SessionId { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
}

public sealed class BarcodeJob
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("jobId")]
    public string JobId { get; set; } = string.Empty;

    [BsonElement("userId")]
    public string? UserId { get; set; }

    [BsonElement("deviceId")]
    public string? DeviceId { get; set; }

    [BsonElement("status")]
    public string Status { get; set; } = "uploading"; // uploading|processing|finish|fail

    [BsonElement("progressPercent")]
    public int ProgressPercent { get; set; }

    [BsonElement("etaSeconds")]
    public int EtaSeconds { get; set; }

    [BsonElement("filePath")]
    public string? FilePath { get; set; }

    [BsonElement("error")]
    public string? Error { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }

    [BsonElement("updatedAt")]
    public DateTime UpdatedAt { get; set; }
}

public sealed class EmailCode
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public ObjectId Id { get; set; }

    [BsonElement("email")]
    public string Email { get; set; } = string.Empty;

    [BsonElement("code")]
    public string Code { get; set; } = string.Empty;

    [BsonElement("expiresAt")]
    public DateTime ExpiresAt { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }
}

internal static class TokenHelper
{
    public static string GenerateToken(byte[] secretKeyBytes, string? userId, string? deviceId, DateTimeOffset issuedAt, DateTimeOffset expiresAt)
    {
        var header = new { alg = "HS256", typ = "JWT" };
        var payload = new
        {
            sub = $"{userId}|{deviceId}",
            iat = issuedAt.ToUnixTimeSeconds(),
            exp = expiresAt.ToUnixTimeSeconds(),
            uid = userId,
            did = deviceId,
            jti = Guid.NewGuid().ToString("n")
        };
        string headerB64 = Base64UrlEncode(JsonSerializer.Serialize(header));
        string payloadB64 = Base64UrlEncode(JsonSerializer.Serialize(payload));
        string data = $"{headerB64}.{payloadB64}";
        string sig = ComputeHmac(secretKeyBytes, data);
        return $"{data}.{sig}";
    }

    public static (bool IsValid, DateTime ExpiresAtUtc) ValidateToken(byte[] secretKeyBytes, string token)
    {
        try
        {
            var parts = token.Split('.');
            if (parts.Length != 3) return (false, DateTime.MinValue);
            var data = $"{parts[0]}.{parts[1]}";
            var expectedSig = ComputeHmac(secretKeyBytes, data);
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expectedSig), Encoding.UTF8.GetBytes(parts[2])))
                return (false, DateTime.MinValue);

            var payloadJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[1]));
            using var doc = JsonDocument.Parse(payloadJson);
            if (!doc.RootElement.TryGetProperty("exp", out var expEl)) return (false, DateTime.MinValue);
            var expUnix = expEl.GetInt64();
            var expUtc = DateTimeOffset.FromUnixTimeSeconds(expUnix).UtcDateTime;
            if (DateTime.UtcNow > expUtc) return (false, expUtc);
            return (true, expUtc);
        }
        catch
        {
            return (false, DateTime.MinValue);
        }
    }

    private static string ComputeHmac(byte[] key, string data)
    {
        using var h = new HMACSHA256(key);
        var hash = h.ComputeHash(Encoding.UTF8.GetBytes(data));
        return Base64UrlEncode(hash);
    }

    private static string Base64UrlEncode(string s) => Base64UrlEncode(Encoding.UTF8.GetBytes(s));
    private static string Base64UrlEncode(byte[] bytes)
    {
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
    private static byte[] Base64UrlDecode(string s)
    {
        s = s.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }
}
