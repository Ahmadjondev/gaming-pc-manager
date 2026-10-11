using System;
using System.IO;
using System.Text.Json;

namespace GameBooster
{
    public class Config
    {
        public string ServerUrl { get; set; } = "wss://gaming-pc-manager.onrender.com/ws/client";
        public string StationId { get; set; } = "laptop-01";
        public string StationName { get; set; } = "Gaming Laptop 01";
        public string AuthToken { get; set; } = "gameroom_secret_key_2026";
        public bool AutoStartWithWindows { get; set; } = true;
        public int TelemetryIntervalSeconds { get; set; } = 3;
        public bool AutoLockOnDisconnect { get; set; } = false;
        public int ControlPort { get; set; } = 48999;
        public bool EnableDirectControl { get; set; } = true;

        public static Config Load()
        {
            try
            {
                string configPath = Path.Combine(AppContext.BaseDirectory, "config.json");
                if (File.Exists(configPath))
                {
                    string json = File.ReadAllText(configPath);
                    var loaded = JsonSerializer.Deserialize<Config>(json, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });
                    if (loaded != null)
                    {
                        if (string.IsNullOrWhiteSpace(loaded.StationId) || loaded.StationId == "laptop-01")
                        {
                            loaded.StationId = Environment.MachineName.ToLowerInvariant();
                        }
                        if (string.IsNullOrWhiteSpace(loaded.StationName) || loaded.StationName == "Gaming Laptop 01")
                        {
                            loaded.StationName = Environment.MachineName;
                        }
                        return loaded;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error loading config: {ex.Message}. Using defaults.");
            }

            return new Config
            {
                StationId = Environment.MachineName.ToLowerInvariant(),
                StationName = Environment.MachineName
            };
        }
    }
}
