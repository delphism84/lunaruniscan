using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using LnUniScannerBE.Hubs;
using System.IO;

namespace LnUniScannerBE.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ScannerController : ControllerBase
    {
        private readonly IHubContext<ScannerHub> _hubContext;
        private readonly ILogger<ScannerController> _logger;

        public ScannerController(IHubContext<ScannerHub> hubContext, ILogger<ScannerController> logger)
        {
            _hubContext = hubContext;
            _logger = logger;
        }

        [HttpGet]
        public IActionResult Get()
        {
            return Ok(new { message = "Scanner API is running", timestamp = DateTime.Now });
        }

        [HttpPost("scan")]
        public async Task<IActionResult> ProcessScan([FromBody] ScanRequest request)
        {
            try
            {
                _logger.LogInformation($"Processing scan: {request.Data}");
                
                // Process scan data here
                var result = new ScanResult
                {
                    Id = Guid.NewGuid().ToString(),
                    Data = request.Data,
                    Timestamp = DateTime.Now,
                    Status = "Success"
                };

                // Send to all connected clients via SignalR
                await _hubContext.Clients.All.SendAsync("ScanResult", result);

                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing scan");
                return StatusCode(500, new { error = "Internal server error" });
            }
        }

        // multipart image upload: file + userId + deviceId + optionally fileName
        [HttpPost("image")]
        [RequestSizeLimit(50_000_000)] // 50 MB
        public async Task<IActionResult> UploadImage([FromForm] ImageUploadRequest request)
        {
            if (request.File == null || request.File.Length == 0)
            {
                return BadRequest(new { error = "No file uploaded" });
            }

            try
            {
                var userId = string.IsNullOrWhiteSpace(request.UserId) ? "anonymous" : request.UserId!.Trim();
                var day = DateTime.UtcNow.ToString("yyyyMMdd");
                var root = Path.Combine(AppContext.BaseDirectory, "files", "images", userId, day);
                Directory.CreateDirectory(root);

                var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmssfff");
                var name = string.IsNullOrWhiteSpace(request.FileName) ? $"{stamp}_{Guid.NewGuid().ToString("N").Substring(0,6)}.jpg" : request.FileName!;
                var fullPath = Path.Combine(root, name);

                using (var stream = System.IO.File.Create(fullPath))
                {
                    await request.File.CopyToAsync(stream);
                }

                var result = new ImageUploadResult
                {
                    Id = Guid.NewGuid().ToString(),
                    FileName = name,
                    StoragePath = fullPath,
                    UserId = userId,
                    Status = "Success",
                    Timestamp = DateTime.UtcNow
                };

                // broadcast minimal event
                await _hubContext.Clients.All.SendAsync("ScanResult", new
                {
                    id = result.Id,
                    type = "image",
                    data = result.FileName,
                    userId = result.UserId,
                    timestamp = result.Timestamp,
                    status = result.Status
                });

                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error uploading image");
                return StatusCode(500, new { error = "Internal server error" });
            }
        }

        [HttpPost("broadcast")]
        public async Task<IActionResult> Broadcast([FromBody] BroadcastRequest request)
        {
            try
            {
                await _hubContext.Clients.All.SendAsync("Broadcast", request.Message);
                return Ok(new { message = "Broadcast sent successfully" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error broadcasting message");
                return StatusCode(500, new { error = "Internal server error" });
            }
        }
    }

    public class ScanRequest
    {
        public string Data { get; set; } = string.Empty;
        public string? DeviceId { get; set; }
        public string? UserId { get; set; }
    }

    public class ScanResult
    {
        public string Id { get; set; } = string.Empty;
        public string Data { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    public class ImageUploadRequest
    {
        public IFormFile? File { get; set; }
        public string? UserId { get; set; }
        public string? DeviceId { get; set; }
        public string? FileName { get; set; }
    }

    public class ImageUploadResult
    {
        public string Id { get; set; } = string.Empty;
        public string FileName { get; set; } = string.Empty;
        public string StoragePath { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    public class BroadcastRequest
    {
        public string Message { get; set; } = string.Empty;
        public string? Type { get; set; }
    }
}
