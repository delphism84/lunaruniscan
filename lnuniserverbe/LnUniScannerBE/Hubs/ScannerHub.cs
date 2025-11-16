using Microsoft.AspNetCore.SignalR;
using System;

namespace LnUniScanBE.Hubs
{
    public class ScannerHub : Hub
    {
        public async Task JoinGroup(string groupName)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, groupName);
            await Clients.Group(groupName).SendAsync("UserJoined", Context.ConnectionId);
        }

        public async Task LeaveGroup(string groupName)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, groupName);
            await Clients.Group(groupName).SendAsync("UserLeft", Context.ConnectionId);
        }

        public async Task SendMessage(string user, string message)
        {
            await Clients.All.SendAsync("ReceiveMessage", user, message);
        }

        public async Task SendScanResult(string scanData)
        {
            await Clients.All.SendAsync("ScanResult", scanData);
        }

        public async Task SendToGroup(string groupName, string message)
        {
            await Clients.Group(groupName).SendAsync("GroupMessage", message);
        }

        public override async Task OnConnectedAsync()
        {
            await Clients.All.SendAsync("UserConnected", Context.ConnectionId);
            await base.OnConnectedAsync();
        }

        public override async Task OnDisconnectedAsync(Exception? exception)
        {
            await Clients.All.SendAsync("UserDisconnected", Context.ConnectionId);
            await base.OnDisconnectedAsync(exception);
        }

        // dispatch scan to a specific agent group: agent:{agentId}
        public async Task DispatchRequest(DispatchRequest request)
        {
            var group = $"agent:{request.AgentId}";
            await Clients.Group(group).SendAsync("DispatchRequest", request);
        }

        // agent acknowledges dispatch processing result
        public async Task AckDispatch(AckRequest ack)
        {
            await Clients.All.SendAsync("DispatchAck", ack);
        }
    }

    public class DispatchRequest
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string AgentId { get; set; } = string.Empty;
        public string Type { get; set; } = "barcode"; // barcode | image
        public string Data { get; set; } = string.Empty; // barcode text or file name
        public DispatchOptions Options { get; set; } = new DispatchOptions();
    }

    public class DispatchOptions
    {
        public bool SendEnter { get; set; } = true;
        public int DelayMs { get; set; } = 10;
    }

    public class AckRequest
    {
        public string Id { get; set; } = string.Empty; // dispatch id
        public string AgentId { get; set; } = string.Empty;
        public bool Success { get; set; }
        public string? Error { get; set; }
        public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
    }
}
