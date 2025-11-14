using LnUniScannerBE.Hubs;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add SignalR
builder.Services.AddSignalR();

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFlutterApp", policy =>
    {
        policy.WithOrigins("http://127.0.0.1:58000", "http://localhost:58000")
              .AllowAnyHeader()
              .AllowAnyMethod()
              .AllowCredentials();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// Use CORS
app.UseCors("AllowFlutterApp");

app.UseAuthorization();

app.MapControllers();

// Map SignalR Hub
app.MapHub<ScannerHub>("/scannerhub");

// Serve static files for uploaded content (optional basic exposure)
app.UseDefaultFiles();
app.UseStaticFiles();

// Configure to run on port 51111
app.Urls.Add("http://localhost:50100");
app.Urls.Add("https://localhost:50101"); // HTTPS port

app.Run();
