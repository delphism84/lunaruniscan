using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace UniScan.PcAgent;

[DataContract]
internal sealed class AgentConfig
{
    [DataMember(Name = "serverUrl")]
    public string ServerUrl { get; set; } = "ws://127.0.0.1:45444/ws/sendReq";

    [DataMember(Name = "group")]
    public string Group { get; set; } = "default";

    [DataMember(Name = "deviceName")]
    public string DeviceName { get; set; } = "PC-01";

    [DataMember(Name = "machineId")]
    public string MachineId { get; set; } = "";

    [DataMember(Name = "targetWindow")]
    public TargetWindowConfig TargetWindow { get; set; } = new TargetWindowConfig();

    [DataMember(Name = "barcodeSuffixKey")]
    public string BarcodeSuffixKey { get; set; } = "Enter";

    public static AgentConfig LoadOrCreate(string path)
    {
        AgentConfig cfg;

        try
        {
            if (File.Exists(path))
            {
                using var fs = File.OpenRead(path);
                var ser = new DataContractJsonSerializer(typeof(AgentConfig));
                cfg = (AgentConfig?)ser.ReadObject(fs) ?? new AgentConfig();
            }
            else
            {
                cfg = new AgentConfig();
            }
        }
        catch (Exception ex)
        {
            AgentLog.Error($"Config load failed: {path}", ex);

            // Try backup file in same directory if present.
            try
            {
                var bak = path + ".bak";
                if (File.Exists(bak))
                {
                    using var fs = File.OpenRead(bak);
                    var ser = new DataContractJsonSerializer(typeof(AgentConfig));
                    cfg = (AgentConfig?)ser.ReadObject(fs) ?? new AgentConfig();
                }
                else
                {
                    cfg = new AgentConfig();
                }
            }
            catch (Exception ex2)
            {
                AgentLog.Error($"Config backup load failed: {path}.bak", ex2);
                cfg = new AgentConfig();
            }
        }

        if (string.IsNullOrWhiteSpace(cfg.MachineId))
            cfg.MachineId = DeviceIdentity.GetStableMachineId();

        try
        {
            cfg.Save(path);
        }
        catch (Exception ex)
        {
            AgentLog.Error($"Config save failed: {path}", ex);
        }
        return cfg;
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? ".");

        using var ms = new MemoryStream();
        var ser = new DataContractJsonSerializer(typeof(AgentConfig));
        ser.WriteObject(ms, this);
        var json = Encoding.UTF8.GetString(ms.ToArray());

        var tmp = path + ".tmp";
        var bak = path + ".bak";

        File.WriteAllText(tmp, json, Encoding.UTF8);

        if (File.Exists(path))
        {
            // Atomic replace + keep backup.
            File.Replace(tmp, path, bak, ignoreMetadataErrors: true);
        }
        else
        {
            File.Move(tmp, path);
            try { File.WriteAllText(bak, json, Encoding.UTF8); } catch { }
        }
    }
}

[DataContract]
internal sealed class TargetWindowConfig
{
    [DataMember(Name = "processName")]
    public string ProcessName { get; set; } = "";

    [DataMember(Name = "windowTitleContains")]
    public string WindowTitleContains { get; set; } = "";
}

