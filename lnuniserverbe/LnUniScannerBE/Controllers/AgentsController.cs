using Microsoft.AspNetCore.Mvc;

namespace LnUniScannerBE.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AgentsController : ControllerBase
    {
        private static readonly List<AgentDto> _agents = new List<AgentDto>();

        [HttpGet]
        public IActionResult GetAgents()
        {
            return Ok(_agents);
        }

        [HttpPatch("{id}")]
        public IActionResult UpdateAgent(string id, [FromBody] UpdateAgentRequest request)
        {
            var agent = _agents.FirstOrDefault(a => a.AgentId == id);
            if (agent == null)
            {
                agent = new AgentDto { AgentId = id, Name = $"Agent-{id.Substring(0, 6)}" };
                _agents.Add(agent);
            }

            if (request.Status != null) agent.Status = request.Status!;
            if (request.OwnerUserId != null) agent.OwnerUserId = request.OwnerUserId!;

            return Ok(agent);
        }
    }

    public class AgentDto
    {
        public string AgentId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Status { get; set; } = "offline"; // online/offline/disabled
        public string? OwnerUserId { get; set; }
    }

    public class UpdateAgentRequest
    {
        public string? Status { get; set; }
        public string? OwnerUserId { get; set; }
    }
}


